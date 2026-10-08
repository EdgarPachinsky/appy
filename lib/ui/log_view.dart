import 'package:flutter/material.dart';

import '../services/run_session.dart';
import '../theme.dart';

/// Terminal-like output for a session. Newest line at the bottom; stays
/// pinned to the bottom while output streams in.
class LogView extends StatelessWidget {
  const LogView({super.key, required this.session});
  final RunSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final logs = session.logs;
        if (logs.isEmpty) {
          return const Center(
            child: Text('No output yet', style: TextStyle(color: AppColors.faint, fontSize: 13)),
          );
        }
        return SelectionArea(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            itemCount: logs.length,
            itemBuilder: (context, i) {
              final line = logs[logs.length - 1 - i];
              final color = line.isSystem
                  ? AppColors.lavender
                  : line.isError
                      ? const Color(0xFFE9A7A7)
                      : const Color(0xFFCFCDDA);
              return Text(
                line.text.isEmpty ? ' ' : line.text,
                style: TextStyle(
                  fontFamily: monoFont,
                  fontSize: 12,
                  height: 1.45,
                  color: color,
                  fontWeight: line.isSystem ? FontWeight.w600 : FontWeight.w400,
                ),
              );
            },
          ),
        );
      },
    );
  }
}
