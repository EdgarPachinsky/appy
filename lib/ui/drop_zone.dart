import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Drop folders anywhere on the window to add them as projects.
class FolderDropZone extends StatefulWidget {
  const FolderDropZone({super.key, required this.child, required this.onFolders});
  final Widget child;
  final void Function(List<String> paths) onFolders;

  @override
  State<FolderDropZone> createState() => _FolderDropZoneState();
}

class _FolderDropZoneState extends State<FolderDropZone> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        final folders = details.files.map((f) => f.path).where(FileSystemEntity.isDirectorySync).toList();
        if (folders.isNotEmpty) widget.onFolders(folders);
      },
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    margin: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.bg.withAlpha(215),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.lavender, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.create_new_folder_outlined, size: 38, color: AppColors.lavender),
                        SizedBox(height: 12),
                        Text(
                          'Drop folders to add them',
                          style: TextStyle(color: AppColors.lavender, fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
