import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../models/project.dart';
import '../models/workflow.dart';
import '../services/helpers.dart';
import '../services/hotkeys.dart';
import '../services/run_session.dart';
import '../services/system.dart';
import '../services/workflow_runner.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'app_step_dialog.dart';
import 'dialogs.dart';
import 'log_view.dart';
import 'ports_panel.dart';
import 'widgets.dart';

Route<void> workflowRoute(Workflow workflow, AppState state) => PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, __, ___) => WorkflowPage(workflow: workflow, state: state),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
    );

/// A chip on the palette. [resolve] builds the step; helpers ask for their
/// argument first and return null when cancelled.
class _PaletteItem {
  const _PaletteItem(this.label, this.tooltip, this.resolve);
  final String label;
  final String tooltip;
  final Future<WorkflowStep?> Function() resolve;
}

/// Board for one workflow: commands from any project on the left, the
/// ordered steps on the right, output of the selected step below them.
class WorkflowPage extends StatefulWidget {
  const WorkflowPage({super.key, required this.workflow, required this.state});
  final Workflow workflow;
  final AppState state;

  @override
  State<WorkflowPage> createState() => _WorkflowPageState();
}

class _WorkflowPageState extends State<WorkflowPage> {
  String? _selectedStepId;
  final _search = TextEditingController();
  String _query = '';

  /// Palette panels the user opened (all start closed). 'helpers' or a project id.
  final Set<String> _expanded = {};

  /// Editing the "On stop" steps instead of the start steps.
  bool _onStop = false;

  Workflow get workflow => widget.workflow;
  List<WorkflowStep> get _steps => _onStop ? workflow.shutdownSteps : workflow.steps;
  AppState get state => widget.state;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _insert(WorkflowStep step, [int? index]) {
    // Clamped: the list may have changed while a helper's prompt was open.
    _steps.insert((index ?? _steps.length).clamp(0, _steps.length), step);
    state.workflowChanged();
  }

  Future<void> _add(_PaletteItem item, [int? index]) async {
    final step = await item.resolve();
    if (step != null && mounted) _insert(step, index);
  }

  _PaletteItem _optionItem(Project project, RunOption o) => _PaletteItem(
        o.label,
        o.command,
        () async => WorkflowStep(projectId: project.id, optionId: o.id, label: o.label, command: o.command),
      );

  _PaletteItem _helperItem(HelperCommand h, Project project) => _PaletteItem(
        h.argHint == null ? h.label : '${h.label}…',
        h.argHint == null ? h.build('')! : h.argHint!,
        () => _resolveHelper(h, project),
      );

  Future<WorkflowStep?> _resolveHelper(HelperCommand h, Project project) async {
    var arg = '';
    if (h.argHint != null) {
      final input = await showTextInputDialog(
        context,
        title: h.label,
        hint: h.argHint!,
        confirmLabel: 'Add step',
        monospace: true,
      );
      if (input == null || input.isEmpty) return null;
      arg = input;
    }
    final command = h.build(arg);
    if (command == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$arg" isn\'t valid here. ${h.argHint}')));
      }
      return null;
    }
    final label = h.argHint == null ? h.label : '${h.label} $arg';
    return WorkflowStep(projectId: project.id, label: label, command: command, waitFor: h.waitFor);
  }

  Future<void> _addCustom(Project project) async {
    final cmd = await showTextInputDialog(
      context,
      title: 'Command in ${project.name}',
      hint: 'e.g. git pull && npm install',
      confirmLabel: 'Add step',
      monospace: true,
    );
    if (cmd == null || cmd.isEmpty) return;
    _insert(WorkflowStep(projectId: project.id, label: cmd, command: cmd));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        if (!state.workflows.contains(workflow)) return const Scaffold(body: SizedBox.shrink());
        final run = state.workflowRuns[workflow.id];
        final selected = run?.sessions[_selectedStepId];
        return Scaffold(
          body: Column(
            children: [
              _header(context, run),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 300, child: _palette()),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _board(run)),
                            if (selected != null) ...[
                              const SizedBox(height: 14),
                              SizedBox(height: 240, child: _console(selected)),
                            ],
                          ],
                        ),
                      ),
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

  Widget _header(BuildContext context, WorkflowRun? run) {
    final running = run?.active ?? false;
    final live = state.isWorkflowLive(workflow);
    final stopping = run?.stopping ?? false;
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
            const Icon(Icons.account_tree_outlined, color: AppColors.lavender, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workflow.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _summary(run),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: run != null && run.error != null && !run.cancelled && !running
                          ? AppColors.red
                          : AppColors.faint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            IconAction(
              icon: Icons.edit_outlined,
              tooltip: 'Rename',
              color: AppColors.muted,
              onPressed: () async {
                final name = await showTextInputDialog(context, title: 'Rename workflow', initial: workflow.name);
                if (name == null || name.isEmpty) return;
                workflow.name = name;
                state.workflowChanged();
              },
            ),
            IconAction(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete workflow',
              color: AppColors.muted,
              onPressed: () async {
                final navigator = Navigator.of(context);
                final ok = await showConfirmDialog(
                  context,
                  title: 'Delete "${workflow.name}"?',
                  message: 'Its steps are removed. Your projects and commands stay as they are.',
                  confirmLabel: 'Delete',
                );
                if (!ok) return;
                await state.removeWorkflow(workflow);
                navigator.maybePop();
              },
            ),
            const SizedBox(width: 6),
            _shortcutsMenu(),
            const SizedBox(width: 8),
            if (live || stopping || workflow.shutdownSteps.isNotEmpty)
              Tooltip(
                message: 'Ctrl+C every running command of this workflow, then run its "On stop" steps',
                child: PillButton(
                  label: stopping ? 'Shutting down…' : 'Stop',
                  icon: Icons.stop_rounded,
                  color: AppColors.red,
                  onPressed: stopping ? null : () => state.stopWorkflow(workflow),
                ),
              ),
            if (!running) ...[
              const SizedBox(width: 8),
              PillButton(
                label: live ? 'Run again' : 'Run',
                icon: Icons.play_arrow_rounded,
                primary: true,
                onPressed: workflow.steps.isEmpty || stopping ? null : () => state.runWorkflow(workflow),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _summary(WorkflowRun? run) {
    final n = workflow.steps.length;
    final steps = '$n step${n == 1 ? '' : 's'}';
    if (run == null) return steps;
    if (run.stopping) return 'Shutting down…';
    if (run.active) return 'Running · ${run.doneCount}/$n done';
    if (run.cancelled) return '$steps · shut down';
    return run.error ?? '$steps · last run finished';
  }

  Widget _shortcutsMenu() => _ShortcutChip(start: workflow.hotkey, stop: workflow.stopHotkey, onTap: _editShortcuts);

  Future<void> _editShortcuts() async {
    // Not awaited: a slow plugin call must not keep the dialog from opening.
    Hotkeys.pause();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => _ShortcutsDialog(workflow: workflow, state: state),
    );
    Hotkeys.resume();
    state.syncHotkeys();
  }

  // ----------------------------------------------------------------- palette

  Widget _palette() {
    final q = _query.toLowerCase();
    bool hit(String text) => text.toLowerCase().contains(q);
    bool itemHit(_PaletteItem i) => hit(i.label) || hit(i.tooltip);

    final panels = <Widget>[];
    void panel(String id, String title, String subtitle, List<_PaletteItem> items, {Project? addTo}) {
      // A matching title shows all its commands; otherwise only matching ones.
      final shown = q.isEmpty || hit(title) ? items : items.where(itemHit).toList();
      if (q.isNotEmpty && shown.isEmpty) return;
      panels.add(_PalettePanel(
        title: title,
        subtitle: subtitle,
        items: shown,
        expanded: q.isNotEmpty || _expanded.contains(id),
        onToggle: () => setState(() => _expanded.contains(id) ? _expanded.remove(id) : _expanded.add(id)),
        onAdd: _add,
        onCustom: addTo == null ? null : () => _addCustom(addTo),
      ));
    }

    panel('helpers', 'Helpers', 'apps, kill port, wait, notify…', [
      // Apps are addressed by macOS bundle id; no Windows equivalent yet.
      if (!Platform.isWindows)
        _PaletteItem(
          'Run application…',
          'Open, restart or quit any app',
          () => showAppStepDialog(context, projectId: state.homeProject.id),
        ),
      for (final h in globalHelpers) _helperItem(h, state.homeProject),
    ]);
    // Only ones that can't end up running this workflow inside themselves.
    final nestable = [
      for (final w in state.workflows)
        if (state.canNest(workflow, w)) w
    ];
    if (nestable.isNotEmpty) {
      panel('workflows', 'Workflows', 'run a whole workflow as one step', [
        for (final w in nestable)
          _PaletteItem(
            w.name,
            '${w.steps.length} steps — runs them all, then continues',
            () async => WorkflowStep.workflow(w),
          ),
      ]);
    }
    for (final project in state.orderedProjects) {
      panel(
        project.id,
        project.name,
        project.info.title,
        [
          for (final o in project.allOptions) _optionItem(project, o),
          if (state.gitFor(project) != null)
            for (final h in gitHelpers) _helperItem(h, project),
        ],
        addTo: project,
      );
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim()),
              style: const TextStyle(fontSize: 13),
              decoration: appyInputDecoration('Search projects & commands').copyWith(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                prefixIcon: const Icon(Icons.search_rounded, size: 17, color: AppColors.faint),
                prefixIconConstraints: const BoxConstraints(minWidth: 34),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconAction(
                        icon: Icons.close_rounded,
                        tooltip: 'Clear',
                        color: AppColors.muted,
                        size: 26,
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
                suffixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 26),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Text(
              'Drag commands onto the board, or click to add them at the end.',
              style: TextStyle(color: AppColors.faint, fontSize: 11.5, height: 1.4),
            ),
          ),
          Expanded(
            child: panels.isEmpty
                ? const Center(
                    child: Text('Nothing matches', style: TextStyle(color: AppColors.faint, fontSize: 13)),
                  )
                : ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 10), children: panels),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- board

  Widget _board(WorkflowRun? run) {
    final steps = _steps;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                _BoardTab(
                  label: 'Start',
                  count: workflow.steps.length,
                  selected: !_onStop,
                  onTap: () => setState(() => _onStop = false),
                ),
                const SizedBox(width: 6),
                _BoardTab(
                  label: 'On stop',
                  count: workflow.shutdownSteps.length,
                  selected: _onStop,
                  onTap: () => setState(() => _onStop = true),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _onStop
                        ? 'Stop sends Ctrl+C to every running command above, then runs these.'
                        : 'Run top to bottom when you press Run.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.faint, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _stepList(steps, run)),
        ],
      ),
    );
  }

  Widget _stepList(List<WorkflowStep> steps, WorkflowRun? run) {
    return steps.isEmpty
        ? _DropArea(
            onDrop: _add,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.move_down_rounded, color: AppColors.faint, size: 30),
                  const SizedBox(height: 10),
                  Text(
                    _onStop
                        ? 'Optional: drop clean-up commands here,\ne.g. docker compose down or Helpers → Kill port'
                        : 'Drop commands here — they run top to bottom',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.faint, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          )
        : ReorderableListView.builder(
            padding: const EdgeInsets.all(12),
            buildDefaultDragHandles: false,
            itemCount: steps.length,
            onReorderItem: (from, to) {
              steps.insert(to, steps.removeAt(from));
              state.workflowChanged();
            },
            footer: _DropArea(
              onDrop: _add,
              child: const SizedBox(
                height: 56,
                child: Center(
                  child: Text('Drop here to add at the end', style: TextStyle(color: AppColors.faint, fontSize: 12)),
                ),
              ),
            ),
            itemBuilder: (context, i) => _DropArea(
              key: ValueKey(steps[i].id),
              onDrop: (item) => _add(item, i),
              child: _stepCard(i, steps[i], run),
            ),
          );
  }

  Widget _stepCard(int index, WorkflowStep step, WorkflowRun? run) {
    final target = state.resolveStep(step);
    final nested = step.workflowId != null;
    final child = nested ? state.workflowById(step.workflowId!) : null;
    final childRun = child == null ? null : state.workflowRuns[child.id];
    final (where, missing) = nested
        ? (child == null ? 'Missing workflow' : 'Workflow', child == null)
        : (target?.$1.name ?? 'Missing project', target == null);
    final detail = !nested
        ? step.command
        : child == null
            ? ''
            : childRun != null && childRun.active
                ? 'Running · ${childRun.doneCount}/${child.steps.length} done'
                : '${child.steps.length} steps${child.shutdownSteps.isEmpty ? '' : ' · ${child.shutdownSteps.length} on stop'}';
    final session = run?.sessions[step.id];
    final selected = _selectedStepId == step.id && session != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.cardHover : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: session == null ? null : () => setState(() => _selectedStepId = selected ? null : step.id),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AppColors.lavender.withAlpha(120) : AppColors.border),
            ),
            child: Row(
              children: [
                _StepBadge(index: index, status: run?.statusOf(step) ?? StepStatus.pending),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (nested) ...[
                            const Icon(Icons.account_tree_outlined, size: 12, color: AppColors.lavender),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            where,
                            style: TextStyle(
                              color: missing ? AppColors.red : (nested ? AppColors.lavender : AppColors.muted),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(child?.name ?? step.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: AppColors.faint, fontFamily: nested ? null : monoFont)),
                    ],
                  ),
                ),
                if (session != null && session.isActive) ...[
                  StatsText(sessions: [session]),
                  const SizedBox(width: 8),
                ],
                if (child != null)
                  IconAction(
                    icon: Icons.open_in_new_rounded,
                    tooltip: 'Open "${child.name}"',
                    color: AppColors.muted,
                    size: 26,
                    onPressed: () => Navigator.of(context).push(workflowRoute(child, state)),
                  ),
                _waitMenu(step),
                IconAction(
                  icon: Icons.close_rounded,
                  tooltip: 'Remove step',
                  color: AppColors.faint,
                  size: 26,
                  onPressed: () {
                    _steps.remove(step);
                    state.workflowChanged();
                  },
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.drag_indicator_rounded, color: AppColors.faint, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _waitMenu(WorkflowStep step) {
    final label = step.waitFor == WaitFor.delay ? 'Wait ${step.delaySeconds} s' : step.waitFor.label;
    return PopupMenuButton<WaitFor>(
      tooltip: 'When to start the next step',
      color: AppColors.surface,
      onSelected: (mode) async {
        if (mode == WaitFor.delay) {
          final raw = await showTextInputDialog(
            context,
            title: 'Seconds to wait',
            initial: '${step.delaySeconds}',
            confirmLabel: 'Set',
          );
          final seconds = int.tryParse(raw ?? '');
          if (seconds == null || seconds < 0) return;
          step.delaySeconds = seconds;
        }
        step.waitFor = mode;
        state.workflowChanged();
      },
      itemBuilder: (_) => [
        for (final mode in WaitFor.values)
          PopupMenuItem(
            value: mode,
            child: Text(mode.label, style: const TextStyle(fontSize: 13)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.lavender.withAlpha(18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: AppColors.lavender, fontSize: 11.5, fontWeight: FontWeight.w600)),
            const Icon(Icons.arrow_drop_down_rounded, color: AppColors.lavender, size: 16),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- console

  Widget _console(RunSession s) {
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
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                StatusDot(color: statusColor(s.status), glow: s.status == RunStatus.running),
                const SizedBox(width: 8),
                Text(statusLabel(s.status), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${s.project.name} · ${s.option.command}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.faint, fontFamily: monoFont),
                  ),
                ),
                if (s.portInUse != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: PortInUseButton(session: s, state: state),
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
                if (s.isActive)
                  IconAction(
                    icon: Icons.stop_rounded,
                    tooltip: 'Stop',
                    color: AppColors.red,
                    filled: true,
                    onPressed: s.status == RunStatus.stopping ? null : () => state.stop(s),
                  ),
                IconAction(
                  icon: Icons.close_rounded,
                  tooltip: 'Hide output',
                  color: AppColors.muted,
                  onPressed: () => setState(() => _selectedStepId = null),
                ),
              ],
            ),
          ),
          Expanded(child: LogView(key: ValueKey(s.key), session: s)),
        ],
      ),
    );
  }
}

/// A collapsible group of palette chips (a project, or the helpers).
class _PalettePanel extends StatelessWidget {
  const _PalettePanel({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.expanded,
    required this.onToggle,
    required this.onAdd,
    this.onCustom,
  });

  final String title;
  final String subtitle;
  final List<_PaletteItem> items;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(_PaletteItem) onAdd;
  final VoidCallback? onCustom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.faint, fontSize: 11)),
                      ],
                    ),
                  ),
                  Text('${items.length}', style: const TextStyle(color: AppColors.faint, fontSize: 11.5)),
                  if (onCustom != null)
                    IconAction(
                      icon: Icons.add_rounded,
                      tooltip: 'Custom command in $title',
                      color: AppColors.muted,
                      size: 24,
                      onPressed: onCustom,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 2, 4, 10),
            child: items.isEmpty
                ? const Text('Nothing detected — add a command with +',
                    style: TextStyle(color: AppColors.faint, fontSize: 11.5))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final item in items) _PaletteChip(item: item, onTap: onAdd)],
                  ),
          ),
      ],
    );
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({required this.item, required this.onTap});
  final _PaletteItem item;
  final void Function(_PaletteItem) onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Material(
      color: AppColors.tile,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onTap(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Text(item.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    );
    return Tooltip(
      message: item.tooltip,
      child: Draggable<_PaletteItem>(
        data: item,
        feedback: Material(type: MaterialType.transparency, child: Opacity(opacity: 0.9, child: chip)),
        childWhenDragging: Opacity(opacity: 0.4, child: chip),
        child: MouseRegion(cursor: SystemMouseCursors.grab, child: chip),
      ),
    );
  }
}

/// Header chip showing the start / stop shortcuts as keycaps.
class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({required this.start, required this.stop, required this.onTap});
  final Map<String, dynamic>? start;
  final Map<String, dynamic>? stop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final none = start == null && stop == null;
    Widget half(IconData icon, Color color, Map<String, dynamic> hotkey) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            _Keycaps(Hotkeys.keys(hotkey)),
          ],
        );
    return Tooltip(
      message: 'Global shortcuts to start / stop this workflow',
      child: Material(
        color: AppColors.text.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: none ? 12 : 9, vertical: none ? 7 : 5),
            child: none
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.keyboard_command_key_rounded, size: 15, color: AppColors.muted),
                      SizedBox(width: 6),
                      Text('Add shortcuts',
                          style: TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (start != null) half(Icons.play_arrow_rounded, AppColors.green, start!),
                      if (start != null && stop != null)
                        Container(
                          width: 1,
                          height: 16,
                          margin: const EdgeInsets.symmetric(horizontal: 9),
                          color: AppColors.borderStrong,
                        ),
                      if (stop != null) half(Icons.stop_rounded, AppColors.red, stop!),
                      const SizedBox(width: 10),
                      const Text('Edit',
                          style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Keys drawn as small Mac-style keycaps, e.g. [⌥][⌘][C].
class _Keycaps extends StatelessWidget {
  const _Keycaps(this.keys);
  final List<String> keys;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, key) in keys.indexed)
            Container(
              constraints: const BoxConstraints(minWidth: 19),
              height: 20,
              margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.tile,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppColors.borderStrong),
                // Hard 1.5px shadow under the cap reads as key depth.
                boxShadow: const [BoxShadow(color: Color(0xFF07070A), offset: Offset(0, 1.5))],
              ),
              child: Text(
                key,
                style: const TextStyle(color: AppColors.text, fontSize: 11, fontWeight: FontWeight.w600, height: 1),
              ),
            ),
        ],
      );
}

class _BoardTab extends StatelessWidget {
  const _BoardTab({required this.label, required this.count, required this.selected, required this.onTap});
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.lavenderInk : AppColors.text;
    return Material(
      color: selected ? AppColors.lavender : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: selected ? AppColors.lavender : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Text('$label  $count', style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Accepts palette commands; outlines itself while one hovers over it.
class _DropArea extends StatelessWidget {
  const _DropArea({super.key, required this.onDrop, required this.child});
  final void Function(_PaletteItem) onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_PaletteItem>(
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            top: BorderSide(color: candidates.isNotEmpty ? AppColors.lavender : Colors.transparent, width: 2),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.index, required this.status});
  final int index;
  final StepStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, child) = switch (status) {
      StepStatus.pending => (
          AppColors.muted,
          Text('${index + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      StepStatus.running => (
          AppColors.amber,
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.amber),
          ),
        ),
      StepStatus.done => (AppColors.green, const Icon(Icons.check_rounded, size: 16, color: AppColors.green)),
      StepStatus.failed => (AppColors.red, const Icon(Icons.close_rounded, size: 16, color: AppColors.red)),
    };
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withAlpha(26), shape: BoxShape.circle),
      child: DefaultTextStyle.merge(style: TextStyle(color: color), child: child),
    );
  }
}

/// Both global shortcuts of a workflow: set, change (recorded inline) or clear.
class _ShortcutsDialog extends StatefulWidget {
  const _ShortcutsDialog({required this.workflow, required this.state});
  final Workflow workflow;
  final AppState state;

  @override
  State<_ShortcutsDialog> createState() => _ShortcutsDialogState();
}

class _ShortcutsDialogState extends State<_ShortcutsDialog> {
  /// Which row is recording: false = start, true = stop, null = none.
  bool? _recording;
  HotKey? _recorded;

  Workflow get workflow => widget.workflow;

  Map<String, dynamic>? _get(bool stop) => stop ? workflow.stopHotkey : workflow.hotkey;

  void _set(bool stop, Map<String, dynamic>? value) {
    if (stop) {
      workflow.stopHotkey = value;
    } else {
      workflow.hotkey = value;
    }
    widget.state.workflowChanged();
  }

  /// What already uses the recorded combo (any other shortcut of any workflow).
  String? get _usedBy {
    final recorded = _recorded;
    if (recorded == null) return null;
    final label = Hotkeys.label(recorded.toJson());
    for (final w in widget.state.workflows) {
      for (final (json, stop) in [(w.hotkey, false), (w.stopHotkey, true)]) {
        if (json == null || (w == workflow && stop == _recording)) continue;
        if (Hotkeys.label(json) != label) continue;
        final kind = stop ? 'stop' : 'start';
        return w == workflow ? "this workflow's $kind shortcut" : '${w.name} ($kind)';
      }
    }
    return null;
  }

  // A bare letter as a system-wide shortcut would hijack normal typing.
  bool get _hasModifier => (_recorded?.modifiers ?? const []).isNotEmpty;
  bool get _valid => _hasModifier && _usedBy == null;

  void _startRecording(bool stop) => setState(() {
        _recording = stop;
        _recorded = null;
      });

  void _stopRecording() => setState(() {
        _recording = null;
        _recorded = null;
      });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SizedBox(
        width: 500,
        // Scrolls rather than overflows in a short window.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Global shortcuts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'Work anywhere on your Mac, even when Appy is hidden. '
                'Combos with ⌃⌥⌘ are safest — other apps rarely use them.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 16),
              _row(stop: false),
              const SizedBox(height: 8),
              _row(stop: true),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: PillButton(label: 'Done', primary: true, onPressed: () => Navigator.of(context).pop()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row({required bool stop}) {
    final current = _get(stop);
    final recording = _recording == stop;
    final recorded = _recorded;
    final subtitle = stop
        ? 'Ctrl+C every command, then run the "On stop" steps'
        : workflow.stopHotkey == null
            ? 'Runs the workflow — press again while it runs to stop it'
            : 'Runs the workflow';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: recording ? AppColors.lavender.withAlpha(140) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(stop ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 18, color: stop ? AppColors.red : AppColors.green),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stop ? 'Stop workflow' : 'Start workflow',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppColors.faint, fontSize: 11.5)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (recording) ...[
                Container(
                  height: 30,
                  constraints: const BoxConstraints(minWidth: 110),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.tile,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.lavender),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Listens for keys; we draw the result ourselves.
                      Offstage(child: HotKeyRecorder(onHotKeyRecorded: (k) => setState(() => _recorded = k))),
                      recorded == null
                          ? const Text('Press keys…', style: TextStyle(color: AppColors.lavender, fontSize: 12))
                          : _Keycaps(Hotkeys.keys(recorded.toJson())),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                PillButton(label: 'Cancel', onPressed: _stopRecording),
                const SizedBox(width: 6),
                PillButton(
                  label: 'Save',
                  primary: true,
                  onPressed: _valid
                      ? () {
                          _set(stop, recorded!.toJson());
                          _stopRecording();
                        }
                      : null,
                ),
              ] else ...[
                current == null
                    ? const Text('Not set', style: TextStyle(color: AppColors.faint, fontSize: 12))
                    : _Keycaps(Hotkeys.keys(current)),
                const SizedBox(width: 10),
                PillButton(
                  label: current == null ? 'Set' : 'Change',
                  onPressed: _recording == null ? () => _startRecording(stop) : null,
                ),
                // Same width either way so both rows line up.
                SizedBox(
                  width: 32,
                  child: current == null
                      ? null
                      : IconAction(
                          icon: Icons.close_rounded,
                          tooltip: 'Clear ${stop ? 'stop' : 'start'} shortcut',
                          color: AppColors.muted,
                          onPressed: _recording == null ? () => setState(() => _set(stop, null)) : null,
                        ),
                ),
              ],
            ],
          ),
          if (recording && recorded != null && !_valid)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 8),
              child: Text(
                !_hasModifier ? 'Add ⌘, ⌥, ⌃ or ⇧ to the key' : 'Already used by $_usedBy',
                style: const TextStyle(color: AppColors.amber, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
