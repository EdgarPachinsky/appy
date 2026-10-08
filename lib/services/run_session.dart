import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/project.dart';
import 'resource_monitor.dart';

enum RunStatus { starting, running, stopping, exited, failed }

class LogLine {
  const LogLine(this.text, {this.isError = false, this.isSystem = false});
  final String text;
  final bool isError;
  final bool isSystem;
}

String sessionKey(String projectId, String optionId) => '$projectId::$optionId';

/// One running (or finished) command inside a project.
///
/// Listeners of this object are notified when logs change (throttled).
/// [onStateChanged] fires when status / url / reload state change.
class RunSession extends ChangeNotifier {
  RunSession({required this.project, required this.option, this.onStateChanged});

  final Project project;
  final RunOption option;
  VoidCallback? onStateChanged;

  String get key => sessionKey(project.id, option.id);

  RunStatus status = RunStatus.exited;
  int? exitCode;
  DateTime startedAt = DateTime.now();
  String? url;
  bool busy = false;

  final List<LogLine> logs = [];
  static const _maxLogs = 4000;

  /// Live CPU / memory of the whole process tree (null when not running).
  final ValueNotifier<ProcStats?> stats = ValueNotifier(null);

  int? get pid => _process?.pid;

  Process? _process;
  String? _appId;
  int _rpcId = 0;
  bool _stopRequested = false;
  Timer? _notifyTimer;

  bool get isActive =>
      status == RunStatus.starting || status == RunStatus.running || status == RunStatus.stopping;
  bool get isFlutter => option.isFlutterRun;
  bool get canReload => isFlutter && _appId != null && status == RunStatus.running && !busy;

  Future<void> start(Map<String, String> env) async {
    if (isActive) return;
    status = RunStatus.starting;
    exitCode = null;
    url = null;
    busy = false;
    _appId = null;
    _stopRequested = false;
    startedAt = DateTime.now();
    if (logs.isNotEmpty) _log('');
    _log('\$ ${option.command}', system: true);
    _stateChanged();

    // `exec` keeps the pid pointing at the real tool (so stdin reaches
    // `flutter run`), unless the command is a shell chain.
    final cmd = option.command;
    final script = RegExp(r'[;&|]').hasMatch(cmd) ? cmd : 'exec $cmd';

    try {
      final process = await Process.start(
        '/bin/zsh',
        ['-c', script],
        workingDirectory: project.path,
        environment: env,
        includeParentEnvironment: false,
      );
      _process = process;
      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_onStdout);
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) => _log(line, error: true));
      process.exitCode.then((code) => _onExit(process, code));
    } catch (e) {
      status = RunStatus.failed;
      _log('Could not start: $e', error: true);
      _stateChanged();
      return;
    }

    if (!isFlutter) status = RunStatus.running;
    _stateChanged();
  }

  void _onExit(Process process, int code) {
    if (!identical(process, _process)) return;
    _process = null;
    _appId = null;
    busy = false;
    stats.value = null;
    exitCode = code;
    status = (code == 0 || _stopRequested) ? RunStatus.exited : RunStatus.failed;
    _log(_stopRequested ? 'Stopped' : 'Exited with code $code', system: true);
    _stateChanged();
  }

  /// Stop gracefully (flutter: app.stop), then SIGTERM, then SIGKILL.
  Future<void> stop() async {
    final process = _process;
    if (process == null || status == RunStatus.stopping) return;
    _stopRequested = true;
    status = RunStatus.stopping;
    _stateChanged();

    if (isFlutter && _appId != null) {
      _send('app.stop', {'appId': _appId});
      if (await _waitExit(process, const Duration(seconds: 5))) return;
    }
    await killProcessTree(process.pid, ProcessSignal.sigterm);
    if (await _waitExit(process, const Duration(seconds: 4))) return;
    await killProcessTree(process.pid, ProcessSignal.sigkill);
  }

  void hotReload() => _restart(full: false);
  void hotRestart() => _restart(full: true);

  void _restart({required bool full}) {
    if (!canReload) return;
    busy = true;
    _log(full ? 'Hot restart…' : 'Hot reload…', system: true);
    _send('app.restart', {'appId': _appId, 'fullRestart': full, 'pause': false, 'reason': 'manual'});
    _stateChanged();
    // Safety net in case the daemon never answers.
    Timer(const Duration(seconds: 30), () {
      if (busy) {
        busy = false;
        _stateChanged();
      }
    });
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------

  Future<bool> _waitExit(Process process, Duration timeout) async {
    try {
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  void _send(String method, Map<String, dynamic> params) {
    final process = _process;
    if (process == null) return;
    try {
      process.stdin.writeln(jsonEncode([
        {'id': ++_rpcId, 'method': method, 'params': params}
      ]));
    } catch (_) {}
  }

  void _onStdout(String line) {
    if (isFlutter) {
      final t = line.trim();
      if (t.startsWith('[{') && t.endsWith('}]')) {
        try {
          for (final m in jsonDecode(t) as List) {
            _onDaemonMessage((m as Map).cast<String, dynamic>());
          }
          return;
        } catch (_) {}
      }
    }
    _log(line);
  }

  void _onDaemonMessage(Map<String, dynamic> m) {
    final event = m['event'] as String?;
    final params = (m['params'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

    if (event == null) {
      // Response to one of our requests (reload / restart / stop).
      if (m['error'] != null) {
        _log('${m['error']}', error: true);
      } else {
        final result = m['result'];
        if (result is Map && result['code'] != null && result['code'] != 0) {
          _log('${result['message'] ?? 'Request failed'}', error: true);
        } else if (busy) {
          _log('Done', system: true);
        }
      }
      if (busy) {
        busy = false;
        _stateChanged();
      }
      return;
    }

    switch (event) {
      case 'app.start':
        _appId = params['appId'] as String?;
        _stateChanged();
      case 'app.started':
        status = RunStatus.running;
        _log('App is running', system: true);
        _stateChanged();
      case 'app.log':
        final text = params['log'];
        if (text != null) _log('$text', error: params['error'] == true);
      case 'app.progress':
        final message = params['message'];
        if (message is String && message.isNotEmpty) _log(message, system: true);
      case 'daemon.logMessage':
        final logMessage = params['message'];
        if (logMessage != null) _log('$logMessage', error: params['level'] == 'error');
      case 'app.webLaunchUrl':
        final u = params['url'];
        if (u is String) {
          url = u;
          _stateChanged();
        }
      case 'app.stop':
        final error = params['error'];
        if (error != null) _log('$error', error: true);
      default:
        break;
    }
  }

  static final _ansi = RegExp(r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1B\\))');
  static final _localUrl =
      RegExp(r'https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1?\])(?::\d+)?(?:/[^\s"' "'" r')\]]*)?');

  void _log(String raw, {bool error = false, bool system = false}) {
    final text = raw.replaceAll(_ansi, '').replaceAll('\r', '');
    logs.add(LogLine(text, isError: error, isSystem: system));
    if (logs.length > _maxLogs) logs.removeRange(0, logs.length - _maxLogs);

    if (url == null && !system) {
      final match = _localUrl.firstMatch(text);
      if (match != null) {
        url = match.group(0)!.replaceFirst('0.0.0.0', 'localhost');
        _stateChanged();
      }
    }
    _scheduleNotify();
  }

  void _scheduleNotify() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 60), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  void _stateChanged() {
    notifyListeners();
    onStateChanged?.call();
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    stats.dispose();
    super.dispose();
  }
}

/// Signals a process and all of its descendants (npm → node → vite…).
Future<void> killProcessTree(int pid, ProcessSignal signal) async {
  final all = <int>[];
  final queue = <int>[pid];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    try {
      final r = await Process.run('/usr/bin/pgrep', ['-P', '$current']);
      for (final line in (r.stdout as String).split('\n')) {
        final child = int.tryParse(line.trim());
        if (child != null && !all.contains(child)) {
          all.add(child);
          queue.add(child);
        }
      }
    } catch (_) {}
  }
  for (final child in all.reversed) {
    Process.killPid(child, signal);
  }
  Process.killPid(pid, signal);
}
