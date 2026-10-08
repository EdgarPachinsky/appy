import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../models/project.dart';
import '../services/run_session.dart';
import '../services/system.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'log_view.dart';
import 'open_in_button.dart';
import 'project_card.dart';
import 'widgets.dart';

Route<void> projectRoute(Project project, AppState state) => PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, __, ___) => ProjectPage(project: project, state: state),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
    );

class ProjectPage extends StatefulWidget {
  const ProjectPage({super.key, required this.project, required this.state});
  final Project project;
  final AppState state;

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  String? _selectedKey;

  Project get project => widget.project;
  AppState get state => widget.state;

  RunSession? _selected(List<RunSession> sessions) {
    final explicit = sessions.where((s) => s.key == _selectedKey).firstOrNull;
    if (explicit != null) return explicit;
    return sessions.where((s) => s.isActive).firstOrNull ?? sessions.lastOrNull;
  }

  Future<void> _run(RunOption option) async {
    setState(() => _selectedKey = sessionKey(project.id, option.id));
    await state.run(project, option);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        if (!state.projects.contains(project)) {
          return const Scaffold(body: SizedBox.shrink());
        }
        final sessions = state.sessionsOf(project);
        final selected = _selected(sessions);
        return Scaffold(
          body: Column(
            children: [
              _header(context),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 320, child: _optionsPanel(context)),
                      const SizedBox(width: 14),
                      Expanded(child: _consolePanel(sessions, selected)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------ header

  Widget _header(BuildContext context) {
    return DragToMoveArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(84, 14, 16, 16),
        child: Row(
          children: [
            IconAction(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 10),
            ProjectAvatar(name: project.name, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      KindBadge(project.info.title),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          shortenPath(project.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.faint, fontSize: 12),
                        ),
                      ),
                      if (state.gitFor(project) case final git?) ...[
                        const SizedBox(width: 12),
                        Flexible(child: GitBadge(git)),
                      ],
                      if (project.tags.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            project.tags.map((t) => '#$t').join('  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconAction(
              icon: project.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              tooltip: project.pinned ? 'Unpin from menu bar' : 'Pin to menu bar',
              color: project.pinned ? AppColors.lavender : AppColors.muted,
              onPressed: () => state.togglePin(project),
            ),
            IconAction(
              icon: Icons.edit_outlined,
              tooltip: 'Rename',
              color: AppColors.muted,
              onPressed: () => handleProjectMenu(context, 'rename', project, state),
            ),
            IconAction(
              icon: Icons.sell_outlined,
              tooltip: 'Edit tags',
              color: AppColors.muted,
              onPressed: () => handleProjectMenu(context, 'tags', project, state),
            ),
            OpenInButton(project: project),
            IconAction(
              icon: Icons.folder_open_outlined,
              tooltip: 'Show in Finder',
              color: AppColors.muted,
              onPressed: () => SystemActions.revealInFinder(project.path),
            ),
            IconAction(
              icon: Icons.terminal_rounded,
              tooltip: 'Open in Terminal',
              color: AppColors.muted,
              onPressed: () => SystemActions.openInTerminal(project.path),
            ),
            IconAction(
              icon: Icons.manage_search_rounded,
              tooltip: 'Re-detect project',
              color: AppColors.muted,
              onPressed: () => state.rescan(project),
            ),
            IconAction(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Remove from Appy',
              color: AppColors.muted,
              onPressed: () async {
                final navigator = Navigator.of(context);
                await handleProjectMenu(context, 'remove', project, state);
                if (!state.projects.contains(project)) navigator.maybePop();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ run options

  Widget _optionsPanel(BuildContext context) {
    final groups = <String, List<RunOption>>{};
    for (final o in project.allOptions) {
      groups.putIfAbsent(o.group, () => []).add(o);
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: groups.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nothing to run was detected.\nAdd a custom command below.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                    children: [
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                          child: Text(
                            entry.key.toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.faint,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        for (final option in entry.value) _optionRow(option),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
          ),
          Container(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(10),
            child: PillButton(
              label: 'Add custom command',
              icon: Icons.add_rounded,
              onPressed: () async {
                final cmd = await showTextInputDialog(
                  context,
                  title: 'Custom command',
                  hint: 'e.g. npm run dev -- --port 4000',
                  confirmLabel: 'Add',
                  monospace: true,
                );
                if (cmd != null) state.addCustomCommand(project, cmd);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionRow(RunOption option) {
    final session = state.sessionFor(project, option);
    final active = session?.isActive ?? false;
    final selected = session != null && session.key == _selectedKey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.lavender.withAlpha(16) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: session != null ? () => setState(() => _selectedKey = session.key) : () => _run(option),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  child: session == null
                      ? null
                      : StatusDot(
                          color: statusColor(session.status),
                          size: 7,
                          glow: session.status == RunStatus.running,
                        ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.command,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.faint, fontFamily: monoFont),
                      ),
                    ],
                  ),
                ),
                if (option.group == 'Custom' && !active)
                  IconAction(
                    icon: Icons.close_rounded,
                    tooltip: 'Remove command',
                    color: AppColors.faint,
                    size: 26,
                    onPressed: () => state.removeCustomCommand(project, option.command),
                  ),
                (session != null && session.isActive)
                    ? IconAction(
                        icon: Icons.stop_rounded,
                        tooltip: 'Stop',
                        color: AppColors.red,
                        filled: true,
                        onPressed: session.status == RunStatus.stopping ? null : () => state.stop(session),
                      )
                    : IconAction(
                        icon: Icons.play_arrow_rounded,
                        tooltip: 'Run',
                        color: AppColors.lavender,
                        filled: true,
                        onPressed: () => _run(option),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- console

  Widget _consolePanel(List<RunSession> sessions, RunSession? selected) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.tile,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sessions.length > 1)
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final s in sessions) _sessionTab(s, s == selected),
                ],
              ),
            ),
          if (selected != null) _consoleToolbar(selected),
          Expanded(
            child: selected == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.terminal_rounded, color: AppColors.faint, size: 28),
                        SizedBox(height: 10),
                        Text('Run something to see its output here',
                            style: TextStyle(color: AppColors.faint, fontSize: 13)),
                      ],
                    ),
                  )
                : LogView(key: ValueKey(selected.key), session: selected),
          ),
        ],
      ),
    );
  }

  Widget _sessionTab(RunSession s, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Material(
        color: isSelected ? AppColors.card : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _selectedKey = s.key),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                StatusDot(color: statusColor(s.status), size: 6),
                const SizedBox(width: 7),
                Text(
                  s.option.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? AppColors.text : AppColors.muted,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _consoleToolbar(RunSession s) {
    final stopping = s.status == RunStatus.stopping;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          StatusDot(color: statusColor(s.status), glow: s.status == RunStatus.running),
          const SizedBox(width: 8),
          Text(statusLabel(s.status), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          if (s.isActive) ...[
            const SizedBox(width: 10),
            StatsText(sessions: [s]),
          ],
          if (s.busy) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.amber),
            ),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              s.option.command,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.faint, fontFamily: monoFont),
            ),
          ),
          if (s.url != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: PillButton(
                label: s.url!.replaceFirst(RegExp(r'^https?://'), ''),
                icon: Icons.open_in_new_rounded,
                onPressed: () => SystemActions.openUrl(s.url!),
              ),
            ),
          if (s.isActive) ...[
            if (s.isFlutter) ...[
              IconAction(
                icon: Icons.bolt_rounded,
                tooltip: 'Hot reload',
                color: AppColors.amber,
                onPressed: s.canReload ? s.hotReload : null,
              ),
              IconAction(
                icon: Icons.restart_alt_rounded,
                tooltip: 'Hot restart',
                onPressed: s.canReload ? s.hotRestart : null,
              ),
            ],
            IconAction(
              icon: Icons.refresh_rounded,
              tooltip: s.isFlutter ? 'Rebuild' : 'Restart',
              onPressed: stopping ? null : () => state.rebuild(s),
            ),
            IconAction(
              icon: Icons.stop_rounded,
              tooltip: s.isFlutter ? 'Quit' : 'Stop',
              color: AppColors.red,
              filled: true,
              onPressed: stopping ? null : () => state.stop(s),
            ),
          ] else ...[
            IconAction(
              icon: Icons.play_arrow_rounded,
              tooltip: 'Run again',
              color: AppColors.lavender,
              onPressed: () => _run(s.option),
            ),
            IconAction(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              color: AppColors.muted,
              onPressed: () {
                setState(() => _selectedKey = null);
                state.dismiss(s);
              },
            ),
          ],
          IconAction(
            icon: Icons.delete_sweep_outlined,
            tooltip: 'Clear output',
            color: AppColors.muted,
            onPressed: s.clearLogs,
          ),
        ],
      ),
    );
  }
}
