import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/project.dart';
import '../models/workflow.dart';
import '../services/hotkeys.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'ports_panel.dart';
import 'project_card.dart';
import 'project_page.dart';
import 'widgets.dart';
import 'workflow_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});
  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  /// 'all' | 'running' | 'pinned' | 'tag:<name>'
  String _filter = 'all';

  AppState get state => widget.state;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _addProject() async {
    final path = await getDirectoryPath(confirmButtonText: 'Add Project');
    if (path == null) return;
    await state.addFolder(path);
  }

  void _open(Project project) {
    Navigator.of(context).push(projectRoute(project, state));
  }

  bool _matches(Project p) {
    if (_filter == 'running' && !state.isRunning(p)) return false;
    if (_filter == 'pinned' && !p.pinned) return false;
    if (_filter.startsWith('tag:') && !p.tags.contains(_filter.substring(4))) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    final branch = state.gitFor(p)?.branch;
    return [p.name, p.path, p.info.title, ...p.tags, if (branch != null) branch]
        .any((s) => s.toLowerCase().contains(q));
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final all = state.orderedProjects;
        final tags = state.allTags;
        if (_filter.startsWith('tag:') && !tags.contains(_filter.substring(4))) _filter = 'all';
        final projects = all.where(_matches).toList();
        final running = state.activeSessions.length;

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => _searchFocus.requestFocus(),
            const SingleActivator(LogicalKeyboardKey.escape): _clearSearch,
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Column(
                children: [
                  _header(running, hasProjects: all.isNotEmpty),
                  if (all.isNotEmpty) _filters(all, tags),
                  if (all.isNotEmpty) _workflowsBar(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _projectsArea(all, projects)),
                        if (state.showPorts)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 20, 24),
                            child: SizedBox(width: 320, child: PortsPanel(state: state)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _projectsArea(List<Project> all, List<Project> projects) {
    return all.isEmpty
                        ? _EmptyState(onAdd: _addProject)
                        : projects.isEmpty
                            ? const Center(
                                child: Text('No projects match',
                                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 380,
                                  mainAxisExtent: 220,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                ),
                                itemCount: projects.length,
                                itemBuilder: (context, i) => _ReorderableCard(
                                  key: ValueKey(projects[i].id),
                                  project: projects[i],
                                  state: state,
                                  onOpen: () => _open(projects[i]),
                                ),
                              );
  }

  Widget _header(int running, {required bool hasProjects}) {
    return DragToMoveArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(84, 14, 20, 14),
        child: Row(
          children: [
            const AppyLogo(size: 28),
            const SizedBox(width: 10),
            const Text('appy', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(width: 12),
            if (running > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.green.withAlpha(22),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const StatusDot(color: AppColors.green, size: 6, glow: true),
                    const SizedBox(width: 6),
                    Text('$running running',
                        style: const TextStyle(color: AppColors.green, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            const Spacer(),
            IconAction(
              icon: state.notificationsOn ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
              tooltip: state.notificationsOn ? 'Notifications on — click to mute' : 'Notifications off',
              color: state.notificationsOn ? AppColors.lavender : AppColors.muted,
              onPressed: () => state.notificationsOn = !state.notificationsOn,
            ),
            const SizedBox(width: 6),
            PillButton(
              label: 'Ports',
              icon: Icons.lan_outlined,
              color: state.showPorts ? AppColors.lavender : AppColors.muted,
              onPressed: () => state.showPorts = !state.showPorts,
            ),
            const SizedBox(width: 10),
            if (hasProjects) ...[
              SizedBox(
                width: 230,
                child: TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  style: const TextStyle(fontSize: 13),
                  decoration: appyInputDecoration('Search  ⌘F').copyWith(
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
                            onPressed: _clearSearch,
                          ),
                    suffixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 26),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PillButton(
                label: 'Add project',
                icon: Icons.add_rounded,
                primary: true,
                onPressed: _addProject,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _newWorkflow() async {
    final name = await showTextInputDialog(
      context,
      title: 'New workflow',
      hint: 'e.g. run css workcard',
      confirmLabel: 'Create',
    );
    if (name == null || name.isEmpty || !mounted) return;
    Navigator.of(context).push(workflowRoute(state.addWorkflow(name), state));
  }

  Widget _workflowsBar() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.only(right: 10),
              child: Text('WORKFLOWS',
                  style: TextStyle(color: AppColors.faint, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ),
          ),
          for (final w in state.workflows)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _WorkflowChip(
                workflow: w,
                state: state,
                onOpen: () => Navigator.of(context).push(workflowRoute(w, state)),
              ),
            ),
          Center(
            child: IconAction(
              icon: Icons.add_rounded,
              tooltip: 'New workflow',
              color: AppColors.muted,
              size: 28,
              onPressed: _newWorkflow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters(List<Project> all, List<String> tags) {
    final runningCount = all.where(state.isRunning).length;
    final pinnedCount = all.where((x) => x.pinned).length;
    final chips = <(String, String, int)>[
      ('all', 'All', all.length),
      ('running', 'Running', runningCount),
      if (pinnedCount > 0) ('pinned', 'Pinned', pinnedCount),
      for (final tag in tags) ('tag:$tag', '#$tag', all.where((x) => x.tags.contains(tag)).length),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _FilterChip(
                label: c.$2,
                count: c.$3,
                selected: _filter == c.$1,
                onTap: () => setState(() => _filter = c.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.count, required this.selected, required this.onTap});
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
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('$count', style: TextStyle(color: fg.withAlpha(140), fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkflowChip extends StatelessWidget {
  const _WorkflowChip({required this.workflow, required this.state, required this.onOpen});
  final Workflow workflow;
  final AppState state;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final run = state.workflowRuns[workflow.id];
    final running = run?.active ?? false;
    final live = state.isWorkflowLive(workflow);
    final failed = !live && run != null && !run.cancelled && run.error != null;
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: live ? AppColors.green.withAlpha(90) : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.only(left: 11, right: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (live || failed) ...[
                StatusDot(
                  color: failed ? AppColors.red : (running ? AppColors.amber : AppColors.green),
                  size: 6,
                  glow: live,
                ),
                const SizedBox(width: 6),
              ],
              Text(workflow.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              if (running) ...[
                const SizedBox(width: 6),
                Text('${run!.doneCount}/${workflow.steps.length}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
              ] else if (workflow.hotkey != null) ...[
                const SizedBox(width: 6),
                Text(Hotkeys.label(workflow.hotkey!), style: const TextStyle(color: AppColors.faint, fontSize: 11.5)),
              ],
              const SizedBox(width: 2),
              live
                  ? IconAction(
                      icon: Icons.stop_rounded,
                      tooltip: 'Stop workflow',
                      color: AppColors.red,
                      size: 26,
                      onPressed: () => state.stopWorkflow(workflow),
                    )
                  : IconAction(
                      icon: Icons.play_arrow_rounded,
                      tooltip: 'Run workflow',
                      color: AppColors.lavender,
                      size: 26,
                      onPressed: workflow.steps.isEmpty ? null : () => state.runWorkflow(workflow),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A project card that can be dragged onto another card to reorder.
/// Pinned and unpinned projects reorder within their own section.
class _ReorderableCard extends StatelessWidget {
  const _ReorderableCard({super.key, required this.project, required this.state, required this.onOpen});
  final Project project;
  final AppState state;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final card = ProjectCard(project: project, state: state, onOpen: onOpen);
        return DragTarget<String>(
          onWillAcceptWithDetails: (details) {
            final dragged = state.projectById(details.data);
            return dragged != null && dragged.id != project.id && dragged.pinned == project.pinned;
          },
          onAcceptWithDetails: (details) => state.moveProject(details.data, project.id),
          builder: (context, candidates, _) {
            final hovering = candidates.isNotEmpty;
            return Draggable<String>(
              data: project.id,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: Transform.translate(
                offset: Offset(-constraints.maxWidth / 2, -24),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Opacity(opacity: 0.92, child: card),
                  ),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.25, child: card),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: hovering ? AppColors.lavender : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: card,
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppyLogo(size: 84),
          const SizedBox(height: 18),
          const Text('Add your first project', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Pick a folder or drop it here — Appy detects Flutter, Node, Rust, Go, Python…\nand suggests how to run it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),
          PillButton(label: 'Add project folder', icon: Icons.create_new_folder_outlined, primary: true, onPressed: onAdd),
        ],
      ),
    );
  }
}
