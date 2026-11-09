import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

import '../models/project.dart';
import '../models/workflow.dart';
import '../state/app_state.dart';
import 'app_launcher.dart';
import 'hotkeys.dart';
import 'run_session.dart';
import 'system.dart';

/// Menu bar icon. Click → dropdown with running apps first, then pinned
/// projects, each with run / stop / hot reload / restart / rebuild actions.
class TrayController with TrayListener {
  TrayController({
    required this.state,
    required this.onShowWindow,
    required this.onOpenProject,
    required this.onQuit,
  });

  final AppState state;
  final Future<void> Function() onShowWindow;
  final Future<void> Function(Project project) onOpenProject;
  final Future<void> Function() onQuit;

  Future<void> init() async {
    // Windows needs an .ico; the black template icon would vanish on a dark taskbar anyway.
    await trayManager.setIcon(Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png', isTemplate: true);
    await trayManager.setToolTip('Appy');
    trayManager.addListener(this);
  }

  void dispose() => trayManager.removeListener(this);

  @override
  void onTrayIconMouseDown() => _popUp();

  @override
  void onTrayIconRightMouseDown() => _popUp();

  // The menu is rebuilt right before it opens, so it always shows the live
  // state and is never swapped out while open (item ids stay valid).
  Future<void> _popUp() async {
    await trayManager.setContextMenu(_buildMenu());
    await trayManager.popUpContextMenu();
  }

  // ---------------------------------------------------------------------------

  Menu _buildMenu() {
    final active = state.activeSessions;
    final pinned = state.pinnedProjects;

    return Menu(items: [
      MenuItem(
        label: active.isEmpty ? 'Nothing running' : 'Running · ${active.length}',
        disabled: true,
      ),
      for (final s in active)
        MenuItem.submenu(
          label: '${_statusGlyph(s)}  ${s.project.name} — ${s.option.label}${_stats(s)}',
          submenu: Menu(items: _sessionItems(s, showOpen: true)),
        ),
      if (state.workflows.isNotEmpty) ...[
        MenuItem.separator(),
        MenuItem(label: 'Workflows', disabled: true),
        for (final w in state.workflows) _workflowItem(w),
      ],
      if (pinned.isNotEmpty) ...[
        MenuItem.separator(),
        MenuItem(label: 'Pinned', disabled: true),
        for (final project in pinned)
          MenuItem.submenu(
            label: '${state.isRunning(project) ? '●' : '○'}  ${project.name}',
            submenu: Menu(items: _projectItems(project)),
          ),
      ],
      MenuItem.separator(),
      MenuItem(label: 'Open Appy', onClick: (_) => onShowWindow()),
      MenuItem(label: 'Quit Appy', onClick: (_) => onQuit()),
    ]);
  }

  List<MenuItem> _sessionItems(RunSession s, {bool showOpen = false}) {
    final url = s.url;
    return [
      MenuItem(label: s.option.command, disabled: true),
      MenuItem.separator(),
      if (url != null) MenuItem(label: 'Open $url', onClick: (_) => SystemActions.openUrl(url)),
      if (s.portInUse case final port?)
        MenuItem(label: '⚡  Kill :$port & retry', onClick: (_) => state.freePortAndRetry(s)),
      if (s.isFlutter) ...[
        MenuItem(label: '⚡  Hot Reload', disabled: !s.canReload, onClick: (_) => s.hotReload()),
        MenuItem(label: '↻  Hot Restart', disabled: !s.canReload, onClick: (_) => s.hotRestart()),
        MenuItem(label: '⟳  Rebuild', onClick: (_) => state.rebuild(s)),
        MenuItem(label: '■  Quit', onClick: (_) => state.stop(s)),
      ] else ...[
        MenuItem(label: '⟳  Restart', onClick: (_) => state.rebuild(s)),
        MenuItem(label: '■  Stop', onClick: (_) => state.stop(s)),
      ],
      if (showOpen) ...[
        MenuItem.separator(),
        MenuItem(label: 'Show Output…', onClick: (_) => onOpenProject(s.project)),
      ],
    ];
  }

  List<MenuItem> _projectItems(Project project) {
    final options = project.allOptions;
    final git = state.gitFor(project);
    final apps = AppLauncher.appsFor(project);
    return [
      MenuItem(label: project.info.title, disabled: true),
      if (git != null)
        MenuItem(
          label: '⎇  ${git.branch}${git.isClean ? '' : '  ·  ${git.changes} changed'}',
          disabled: true,
        ),
      MenuItem.separator(),
      if (options.isEmpty) MenuItem(label: 'No run options', disabled: true),
      for (final option in options.take(16))
        if (state.sessionFor(project, option) case final s? when s.isActive)
          MenuItem.submenu(
            label: '${_statusGlyph(s)}  ${option.label}',
            submenu: Menu(items: _sessionItems(s)),
          )
        else if (state.sessionFor(project, option)?.portInUse case final port?)
          MenuItem(
            label: '⚡  ${option.label} — kill :$port & retry',
            onClick: (_) => state.freePortAndRetry(state.sessionFor(project, option)!),
          )
        else
          MenuItem(label: '▶  ${option.label}', onClick: (_) => state.run(project, option)),
      MenuItem.separator(),
      MenuItem(label: 'Open in Appy…', onClick: (_) => onOpenProject(project)),
      if (apps.isNotEmpty)
        MenuItem.submenu(
          label: 'Open in',
          submenu: Menu(items: [
            for (final app in apps) MenuItem(label: app.name, onClick: (_) => AppLauncher.open(app, project)),
          ]),
        ),
      MenuItem(label: SystemActions.revealLabel, onClick: (_) => SystemActions.revealInFinder(project.path)),
    ];
  }

  MenuItem _workflowItem(Workflow w) {
    final run = state.workflowRuns[w.id];
    final shortcut = w.hotkey == null ? '' : '   ${Hotkeys.label(w.hotkey!)}';
    final stopShortcut = w.stopHotkey == null ? '' : '   ${Hotkeys.label(w.stopHotkey!)}';
    if (run != null && run.stopping) {
      return MenuItem(label: '◐  ${w.name} — shutting down…', disabled: true);
    }
    if (run != null && run.active) {
      return MenuItem(
        label: '◐  ${w.name}  ${run.doneCount}/${w.steps.length} — Stop$stopShortcut',
        onClick: (_) => state.stopWorkflow(w),
      );
    }
    if (state.isWorkflowLive(w)) {
      return MenuItem.submenu(
        label: '●  ${w.name}',
        submenu: Menu(items: [
          MenuItem(label: '▶  Run again', onClick: (_) => state.runWorkflow(w)),
          MenuItem(label: '■  Stop$stopShortcut', onClick: (_) => state.stopWorkflow(w)),
        ]),
      );
    }
    final failed = run != null && !run.cancelled && run.error != null;
    if (w.shutdownSteps.isNotEmpty) {
      return MenuItem.submenu(
        label: '${failed ? '✗' : '○'}  ${w.name}$shortcut',
        submenu: Menu(items: [
          MenuItem(label: '▶  Run', disabled: w.steps.isEmpty, onClick: (_) => state.runWorkflow(w)),
          MenuItem(label: '■  Shut down$stopShortcut', onClick: (_) => state.stopWorkflow(w)),
        ]),
      );
    }
    return MenuItem(
      label: '${failed ? '✗' : '▶'}  ${w.name}$shortcut',
      disabled: w.steps.isEmpty,
      onClick: (_) => state.runWorkflow(w),
    );
  }

  String _stats(RunSession s) {
    final stats = s.stats.value;
    return stats == null ? '' : '   (${stats.label})';
  }

  String _statusGlyph(RunSession s) => switch (s.status) {
        RunStatus.running => '●',
        RunStatus.starting || RunStatus.stopping => '◐',
        _ => '○',
      };
}
