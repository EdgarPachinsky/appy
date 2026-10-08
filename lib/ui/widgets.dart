import 'package:flutter/material.dart';

import '../services/git_status.dart';
import '../services/resource_monitor.dart';
import '../services/run_session.dart';
import '../theme.dart';

/// Dark rounded tile with a lavender circle and a lowercase letter —
/// same style as the app icon.
class ProjectAvatar extends StatelessWidget {
  const ProjectAvatar({super.key, required this.name, this.size = 44});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toLowerCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.tile,
        borderRadius: BorderRadius.circular(size * 0.27),
        border: Border.all(color: AppColors.border),
      ),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.62,
        height: size * 0.62,
        decoration: const BoxDecoration(color: AppColors.lavender, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          letter,
          style: TextStyle(
            color: AppColors.lavenderInk,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.34,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class AppyLogo extends StatelessWidget {
  const AppyLogo({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/appy_logo.png', width: size, height: size, filterQuality: FilterQuality.medium);
}

Color statusColor(RunStatus status) => switch (status) {
      RunStatus.running => AppColors.green,
      RunStatus.starting || RunStatus.stopping => AppColors.amber,
      RunStatus.failed => AppColors.red,
      RunStatus.exited => AppColors.faint,
    };

String statusLabel(RunStatus status) => switch (status) {
      RunStatus.running => 'Running',
      RunStatus.starting => 'Starting',
      RunStatus.stopping => 'Stopping',
      RunStatus.failed => 'Failed',
      RunStatus.exited => 'Stopped',
    };

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8, this.glow = false});
  final Color color;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: glow ? [BoxShadow(color: color.withAlpha(140), blurRadius: 8)] : null,
        ),
      );
}

/// Card surface with a subtle hover state.
class HoverCard extends StatefulWidget {
  const HoverCard({super.key, required this.child, this.onTap, this.highlighted = false, this.padding});
  final Widget child;
  final VoidCallback? onTap;
  final bool highlighted;
  final EdgeInsets? padding;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: widget.padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hover ? AppColors.cardHover : AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.highlighted
                  ? AppColors.green.withAlpha(90)
                  : (_hover ? AppColors.borderStrong : AppColors.border),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Compact icon button used across cards and toolbars.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
    this.size = 30,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = !enabled ? AppColors.faint : (color ?? AppColors.text);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? fg.withAlpha(28) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          hoverColor: AppColors.borderStrong.withAlpha(120),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.55, color: fg),
          ),
        ),
      ),
    );
  }
}

/// Rounded button with label. Primary = lavender fill.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.color,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? AppColors.lavender : (color ?? AppColors.text).withAlpha(18);
    final fg = primary ? AppColors.lavenderInk : (color ?? AppColors.text);
    return Material(
      color: onPressed == null ? bg.withAlpha(60) : bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class KindBadge extends StatelessWidget {
  const KindBadge(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.lavender.withAlpha(22),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.lavender, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
}

String shortenPath(String path) {
  const prefix = '/Users/';
  if (path.startsWith(prefix)) {
    final rest = path.substring(prefix.length);
    final slash = rest.indexOf('/');
    return slash == -1 ? '~' : '~${rest.substring(slash)}';
  }
  return path;
}

/// Branch name + change count, e.g. "main ● 3 ↑1".
class GitBadge extends StatelessWidget {
  const GitBadge(this.info, {super.key});
  final GitInfo info;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      info.isClean ? 'clean' : '${info.changes} changed',
      if (info.ahead > 0) '${info.ahead} ahead',
      if (info.behind > 0) '${info.behind} behind',
    ];
    return Tooltip(
      message: '${info.branch} · ${parts.join(' · ')}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.alt_route_rounded, size: 13, color: AppColors.muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              info.branch,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 6),
          if (info.isClean)
            const Icon(Icons.check_rounded, size: 12, color: AppColors.green)
          else
            Text('● ${info.changes}', style: const TextStyle(color: AppColors.amber, fontSize: 11)),
          if (info.ahead > 0)
            Text('  ↑${info.ahead}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          if (info.behind > 0)
            Text('  ↓${info.behind}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Live "12% · 340 MB" for one or more running sessions (summed).
class StatsText extends StatelessWidget {
  const StatsText({super.key, required this.sessions, this.style});
  final List<RunSession> sessions;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([for (final s in sessions) s.stats]),
      builder: (context, _) {
        ProcStats? total;
        for (final s in sessions) {
          final v = s.stats.value;
          if (v != null) total = total == null ? v : total + v;
        }
        if (total == null) return const SizedBox.shrink();
        return Tooltip(
          message: 'CPU · Memory (whole process tree)',
          child: Text(
            total.label,
            maxLines: 1,
            style: style ?? const TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.2, fontFamily: monoFont),
          ),
        );
      },
    );
  }
}
