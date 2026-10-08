import 'package:flutter/material.dart';

import '../models/project.dart';
import '../services/app_launcher.dart';
import '../theme.dart';

/// "Open in…" — lists editors / IDEs / terminals / git apps installed on
/// this Mac that fit the project.
class OpenInButton extends StatelessWidget {
  const OpenInButton({super.key, required this.project, this.size = 30});
  final Project project;
  final double size;

  static IconData _icon(AppCategory c) => switch (c) {
        AppCategory.editor => Icons.code_rounded,
        AppCategory.ide => Icons.integration_instructions_outlined,
        AppCategory.terminal => Icons.terminal_rounded,
        AppCategory.git => Icons.alt_route_rounded,
        AppCategory.finder => Icons.folder_open_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final apps = AppLauncher.appsFor(project);
    return PopupMenuButton<InstalledApp>(
      tooltip: apps.isEmpty ? 'No supported apps found' : 'Open in…',
      enabled: apps.isNotEmpty,
      color: AppColors.surface,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 200),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: (app) => AppLauncher.open(app, project),
      itemBuilder: (_) {
        final entries = <PopupMenuEntry<InstalledApp>>[];
        AppCategory? last;
        for (final app in apps) {
          if (last != null && last != app.app.category) entries.add(const PopupMenuDivider(height: 8));
          last = app.app.category;
          entries.add(PopupMenuItem(
            value: app,
            height: 34,
            child: Row(
              children: [
                Icon(_icon(app.app.category), size: 15, color: AppColors.muted),
                const SizedBox(width: 10),
                Text(app.name, style: const TextStyle(fontSize: 13, color: AppColors.text)),
              ],
            ),
          ));
        }
        return entries;
      },
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          Icons.launch_rounded,
          size: size * 0.55,
          color: apps.isEmpty ? AppColors.faint : AppColors.muted,
        ),
      ),
    );
  }
}
