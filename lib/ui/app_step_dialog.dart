import 'package:flutter/material.dart';

import '../models/workflow.dart';
import '../services/app_launcher.dart';
import '../services/helpers.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'widgets.dart';

/// Picks an installed app and what to do with it; returns the step, or null.
Future<WorkflowStep?> showAppStepDialog(BuildContext context, {required String projectId}) => showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _AppStepDialog(projectId: projectId),
    );

class _AppStepDialog extends StatefulWidget {
  const _AppStepDialog({required this.projectId});
  final String projectId;

  @override
  State<_AppStepDialog> createState() => _AppStepDialogState();
}

class _AppStepDialogState extends State<_AppStepDialog> {
  List<({String name, String path})>? _apps;
  String _query = '';
  ({String name, String path})? _app;
  String? _bundleId;
  bool _noBundleId = false;
  AppAction _action = AppAction.open;
  bool _background = false;
  final _target = TextEditingController();
  final _args = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppLauncher.allApps().then((apps) {
      if (mounted) setState(() => _apps = apps);
    });
    _target.addListener(() => setState(() {}));
    _args.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _target.dispose();
    _args.dispose();
    super.dispose();
  }

  Future<void> _pick(({String name, String path}) app) async {
    setState(() {
      _app = app;
      _bundleId = null;
      _noBundleId = false;
    });
    final id = await AppLauncher.bundleId(app.path);
    if (!mounted || _app != app) return;
    setState(() {
      _bundleId = id;
      _noBundleId = id == null;
    });
  }

  bool get _quits => _action == AppAction.quit;

  String? get _command => _app == null || _bundleId == null
      ? null
      : appCommand(
          bundleId: _bundleId!,
          name: _app!.name,
          action: _action,
          background: _background && !_quits,
          target: _quits ? '' : _target.text,
          args: _quits ? '' : _args.text,
        );

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final shown = (_apps ?? const []).where((a) => a.name.toLowerCase().contains(q)).toList();
    final command = _command;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Run application', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              _label('App'),
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v.trim()),
                style: const TextStyle(fontSize: 13),
                decoration: appyInputDecoration('Search apps').copyWith(
                  prefixIcon: const Icon(Icons.search_rounded, size: 17, color: AppColors.faint),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 170,
                decoration: BoxDecoration(
                  color: AppColors.tile,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: _apps == null
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.lavender))
                    : shown.isEmpty
                        ? const Center(
                            child: Text('No app matches', style: TextStyle(color: AppColors.faint, fontSize: 12.5)))
                        : ListView.builder(
                            padding: const EdgeInsets.all(4),
                            itemCount: shown.length,
                            itemBuilder: (context, i) => _appRow(shown[i]),
                          ),
              ),
              if (_noBundleId)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text("Couldn't read this app's id — pick another one",
                      style: TextStyle(color: AppColors.amber, fontSize: 12)),
                ),
              const SizedBox(height: 14),
              _label('Action'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final a in AppAction.values) _actionChip(a)],
              ),
              const SizedBox(height: 6),
              Text(_action.hint, style: const TextStyle(color: AppColors.faint, fontSize: 12)),
              if (!_quits) ...[
                const SizedBox(height: 14),
                _label('Options'),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _background = !_background),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _background,
                        activeColor: AppColors.lavender,
                        checkColor: AppColors.lavenderInk,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) => setState(() => _background = v ?? false),
                      ),
                      const Text('Open in the background (don\'t bring it to the front)',
                          style: TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _target,
                  style: const TextStyle(fontSize: 12.5, fontFamily: monoFont),
                  decoration: appyInputDecoration('File, folder or URL to open with it (optional)'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _args,
                  style: const TextStyle(fontSize: 12.5, fontFamily: monoFont),
                  decoration: appyInputDecoration('Launch arguments, used when it starts (optional)'),
                ),
              ],
              if (command != null) ...[
                const SizedBox(height: 14),
                _label('Runs'),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.tile, borderRadius: BorderRadius.circular(8)),
                  child: SelectableText(
                    command,
                    maxLines: 4,
                    style: const TextStyle(color: AppColors.faint, fontSize: 11, fontFamily: monoFont, height: 1.4),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PillButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),
                  PillButton(
                    label: 'Add step',
                    primary: true,
                    onPressed: command == null
                        ? null
                        : () => Navigator.of(context).pop(WorkflowStep(
                              projectId: widget.projectId,
                              label: _action.stepLabel(_app!.name),
                              command: command,
                              waitFor: WaitFor.exit,
                            )),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: AppColors.faint, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      );

  Widget _appRow(({String name, String path}) app) {
    final selected = _app == app;
    return Material(
      color: selected ? AppColors.lavender.withAlpha(30) : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => _pick(app),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.apps_rounded, size: 15, color: selected ? AppColors.lavender : AppColors.faint),
              const SizedBox(width: 8),
              Text(app.name, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : null)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shortenPath(app.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.faint, fontSize: 11),
                ),
              ),
              if (selected) const Icon(Icons.check_rounded, size: 16, color: AppColors.lavender),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionChip(AppAction a) {
    final selected = _action == a;
    return Material(
      color: selected ? AppColors.lavender : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: selected ? AppColors.lavender : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => setState(() => _action = a),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Text(a.label,
              style: TextStyle(
                  color: selected ? AppColors.lavenderInk : AppColors.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
