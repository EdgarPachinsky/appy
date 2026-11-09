import 'package:flutter/material.dart';

import '../models/project.dart';
import '../services/run_session.dart';
import '../services/system.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'open_in_button.dart';
import 'widgets.dart';

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project, required this.state, required this.onOpen});

  final Project project;
  final AppState state;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final active = state.sessionsOf(project).where((s) => s.isActive).toList();
    final primary = project.primaryOption;
    final chips = project.allOptions.where((o) => o.id != primary?.id).toList();
    final git = state.gitFor(project);

    return HoverCard(
      onTap: onOpen,
      highlighted: active.isNotEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProjectAvatar(name: project.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Flexible(child: KindBadge(project.info.title)),
                        if (project.tags.isNotEmpty) ...[
                          const SizedBox(width: 8),
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
              OpenInButton(project: project),
              IconAction(
                icon: project.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                tooltip: project.pinned ? 'Unpin from menu bar' : 'Pin to menu bar',
                color: project.pinned ? AppColors.lavender : AppColors.muted,
                onPressed: () => state.togglePin(project),
              ),
              _CardMenu(project: project, state: state),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  shortenPath(project.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.faint, fontSize: 12),
                ),
              ),
              if (git != null) ...[
                const SizedBox(width: 10),
                Flexible(child: GitBadge(git)),
              ],
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 26,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final option in chips.take(6))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _OptionChip(
                      option: option,
                      session: state.sessionFor(project, option),
                      onTap: () {
                        final s = state.sessionFor(project, option);
                        if (s != null && s.isActive) {
                          state.stop(s);
                        } else {
                          state.run(project, option);
                        }
                      },
                    ),
                  ),
                if (chips.length > 6)
                  Center(
                    child: Text('+${chips.length - 6}', style: const TextStyle(color: AppColors.faint, fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: active.isEmpty ? _idleFooter(primary) : _runningFooter(active),
          ),
        ],
      ),
    );
  }

  Widget _idleFooter(RunOption? primary) {
    return Row(
      children: [
        Expanded(
          child: Text(
            primary == null ? 'No run options found' : primary.command.replaceAll(' --machine', ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 12, fontFamily: monoFont),
          ),
        ),
        const SizedBox(width: 8),
        if (primary != null)
          PillButton(
            label: primary.label,
            icon: Icons.play_arrow_rounded,
            primary: true,
            onPressed: () => state.run(project, primary),
          ),
      ],
    );
  }

  Widget _runningFooter(List<RunSession> active) {
    final s = active.first;
    final more = active.length > 1 ? '  +${active.length - 1}' : '';
    return Row(
      children: [
        StatusDot(color: statusColor(s.status), glow: s.status == RunStatus.running),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${statusLabel(s.status)} · ${s.option.label}$more',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.25),
              ),
              StatsText(sessions: active),
            ],
          ),
        ),
        if (s.url != null)
          IconAction(
            icon: Icons.open_in_new_rounded,
            tooltip: 'Open ${s.url}',
            onPressed: () => SystemActions.openUrl(s.url!),
          ),
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
          onPressed: s.status == RunStatus.stopping ? null : () => state.rebuild(s),
        ),
        const SizedBox(width: 2),
        IconAction(
          icon: Icons.stop_rounded,
          tooltip: s.isFlutter ? 'Quit' : 'Stop',
          color: AppColors.red,
          filled: true,
          onPressed: s.status == RunStatus.stopping ? null : () => state.stop(s),
        ),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.option, required this.session, required this.onTap});
  final RunOption option;
  final RunSession? session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = session?.isActive ?? false;
    return Tooltip(
      message: active ? 'Stop · ${option.command}' : option.command,
      child: Material(
        color: active ? AppColors.green.withAlpha(24) : AppColors.tile,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: active ? AppColors.green.withAlpha(80) : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active) ...[
                  StatusDot(color: statusColor(session!.status), size: 6),
                  const SizedBox(width: 6),
                ],
                Text(option.label, style: const TextStyle(fontSize: 12, color: AppColors.text)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.project, required this.state});
  final Project project;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      color: AppColors.surface,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      icon: const Icon(Icons.more_horiz_rounded, size: 18, color: AppColors.muted),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 180),
      onSelected: (value) => handleProjectMenu(context, value, project, state),
      itemBuilder: (_) => projectMenuItems(),
    );
  }
}

List<PopupMenuEntry<String>> projectMenuItems() {
  PopupMenuItem<String> item(String value, IconData icon, String label, {Color? color}) => PopupMenuItem(
        value: value,
        height: 36,
        child: Row(
          children: [
            Icon(icon, size: 16, color: color ?? AppColors.muted),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 13, color: color ?? AppColors.text)),
          ],
        ),
      );
  return [
    item('rename', Icons.edit_outlined, 'Rename'),
    item('tags', Icons.sell_outlined, 'Edit tags'),
    item('finder', Icons.folder_open_outlined, SystemActions.revealLabel),
    item('terminal', Icons.terminal_rounded, 'Open in Terminal'),
    item('rescan', Icons.manage_search_rounded, 'Re-detect project'),
    const PopupMenuDivider(height: 8),
    item('remove', Icons.delete_outline_rounded, 'Remove from Appy', color: AppColors.red),
  ];
}

Future<void> handleProjectMenu(BuildContext context, String value, Project project, AppState state) async {
  switch (value) {
    case 'rename':
      final name = await showTextInputDialog(context, title: 'Rename project', initial: project.name);
      if (name != null) state.rename(project, name);
    case 'tags':
      final text = await showTextInputDialog(
        context,
        title: 'Tags',
        initial: project.tags.join(', '),
        hint: 'work, client, personal',
      );
      if (text != null) state.setTags(project, text.split(','));
    case 'finder':
      await SystemActions.revealInFinder(project.path);
    case 'terminal':
      await SystemActions.openInTerminal(project.path);
    case 'rescan':
      await state.rescan(project);
    case 'remove':
      final ok = await showConfirmDialog(
        context,
        title: 'Remove ${project.name}?',
        message: 'Running commands will be stopped. Files on disk are not touched.',
      );
      if (ok) await state.removeProject(project);
  }
}
