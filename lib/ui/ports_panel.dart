import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/port_scanner.dart';
import '../services/run_session.dart';
import '../services/system.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'widgets.dart';

/// Dashboard panel: which ports are in use, by what, and a one-click kill.
class PortsPanel extends StatefulWidget {
  const PortsPanel({super.key, required this.state});
  final AppState state;

  @override
  State<PortsPanel> createState() => _PortsPanelState();
}

class _PortsPanelState extends State<PortsPanel> {
  final _input = TextEditingController();
  List<PortInfo> _ports = const [];
  bool _loading = true;
  bool _showAll = false;
  final Set<String> _killing = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ports = await PortScanner.scan();
    if (!mounted) return;
    setState(() {
      _ports = ports;
      _loading = false;
    });
  }

  Future<void> _kill(List<PortInfo> targets, int port) async {
    if (targets.isEmpty) {
      _toast('Nothing is listening on :$port');
      return;
    }
    final key = '$port';
    setState(() => _killing.add(key));
    await widget.state.killProcesses(targets.map((t) => t.pid).toSet());
    await _refresh();
    if (!mounted) return;
    setState(() => _killing.remove(key));
    final names = targets.map((t) => t.command).toSet().join(', ');
    final survived = _ports.any((x) => targets.any((t) => t.pid == x.pid && t.port == x.port));
    _toast(survived ? 'Could not stop $names on :$port' : 'Killed $names on :$port');
  }

  Future<void> _killFromInput() async {
    final port = int.tryParse(_input.text.trim().replaceAll(':', ''));
    if (port == null || port <= 0 || port > 65535) {
      _toast('Enter a port number, e.g. 4200');
      return;
    }
    final targets = (await PortScanner.scan()).where((x) => x.port == port).toList();
    await _kill(targets, port);
    _input.clear();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(color: AppColors.text, fontSize: 13)),
        backgroundColor: AppColors.borderStrong,
        behavior: SnackBarBehavior.floating,
        width: 380,
        duration: const Duration(seconds: 3),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final visible = _showAll
        ? _ports
        : _ports.where((x) => PortScanner.looksLikeDev(x) || state.projectForPath(x.cwd) != null).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.lan_outlined, size: 16, color: AppColors.lavender),
                const SizedBox(width: 8),
                const Text('Ports', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('${visible.length}', style: const TextStyle(color: AppColors.faint, fontSize: 12)),
                const Spacer(),
                _Toggle(
                  options: const ['Dev', 'All'],
                  selected: _showAll ? 1 : 0,
                  onChanged: (i) => setState(() => _showAll = i == 1),
                ),
                IconAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Refresh',
                  color: AppColors.muted,
                  size: 28,
                  onPressed: _refresh,
                ),
              ],
            ),
          ),
          // Quick kill
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    onSubmitted: (_) => _killFromInput(),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9:]'))],
                    style: const TextStyle(fontSize: 13, fontFamily: monoFont),
                    decoration: appyInputDecoration('Kill port, e.g. 4200').copyWith(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PillButton(
                  label: 'Kill',
                  icon: Icons.power_settings_new_rounded,
                  color: AppColors.red,
                  onPressed: _killFromInput,
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.lavender),
                    ),
                  )
                : visible.isEmpty
                    ? Center(
                        child: Text(
                          _showAll ? 'No ports in use' : 'No dev ports in use',
                          style: const TextStyle(color: AppColors.faint, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: visible.length,
                        itemBuilder: (context, i) => _row(visible[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _row(PortInfo info) {
    final project = widget.state.projectForPath(info.cwd);
    final where = project?.name ??
        (info.cwd == null || info.cwd == '/' ? null : p.basename(info.cwd!));
    final killing = _killing.contains('${info.port}');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.tile,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: project != null ? AppColors.lavender.withAlpha(50) : AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              ':${info.port}',
              style: const TextStyle(
                fontFamily: monoFont,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.lavender,
              ),
            ),
          ),
          Expanded(
            child: Tooltip(
              message: '${info.command} · pid ${info.pid} · ${info.address}${info.cwd != null ? '\n${info.cwd}' : ''}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.command,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [if (where != null) where, 'pid ${info.pid}'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.faint),
                  ),
                ],
              ),
            ),
          ),
          IconAction(
            icon: Icons.open_in_new_rounded,
            tooltip: 'Open localhost:${info.port}',
            color: AppColors.muted,
            size: 28,
            onPressed: () => SystemActions.openUrl('http://localhost:${info.port}'),
          ),
          const SizedBox(width: 2),
          IconAction(
            icon: Icons.power_settings_new_rounded,
            tooltip: 'Kill ${info.command} (pid ${info.pid})',
            color: AppColors.red,
            filled: true,
            size: 28,
            onPressed: killing ? null : () => _kill([info], info.port),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.options, required this.selected, required this.onChanged});
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: AppColors.tile, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: i == selected ? AppColors.borderStrong : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    options[i],
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: i == selected ? AppColors.text : AppColors.faint,
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

/// Shown when a command crashed because its port was taken:
/// kills whatever holds the port and runs the command again.
class PortInUseButton extends StatefulWidget {
  const PortInUseButton({super.key, required this.session, required this.state});
  final RunSession session;
  final AppState state;

  @override
  State<PortInUseButton> createState() => _PortInUseButtonState();
}

class _PortInUseButtonState extends State<PortInUseButton> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    await widget.state.freePortAndRetry(widget.session);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final port = widget.session.portInUse;
    if (port == null) return const SizedBox.shrink();
    return Tooltip(
      message: 'Port $port is taken by another process',
      child: PillButton(
        label: _busy ? 'Freeing :$port…' : 'Kill :$port & retry',
        icon: Icons.bolt_rounded,
        color: AppColors.amber,
        onPressed: _busy ? null : _retry,
      ),
    );
  }
}
