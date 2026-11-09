import 'dart:convert';
import 'dart:io';

import '../models/workflow.dart';

/// A ready-made workflow command. [build] turns the user's argument into the
/// shell command, or returns null when the argument isn't valid.
class HelperCommand {
  const HelperCommand(this.label, this.build, {this.argHint, this.waitFor = WaitFor.exit});

  final String label;

  /// What to ask for (shown as the input hint); null = takes no argument.
  final String? argHint;
  final String? Function(String arg) build;

  /// null = guess from the command, like any custom command.
  final WaitFor? waitFor;
}

/// Wraps [s] in single quotes for zsh.
String shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

int? _port(String s) {
  final port = int.tryParse(s.trim());
  return port != null && port > 0 && port < 65536 ? port : null;
}

String? _url(String s) {
  final uri = Uri.tryParse(s.trim());
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty ? s.trim() : null;
}

/// Frees [port]: SIGTERM to whatever listens on it, SIGKILL to what's still
/// there after 5 s. Only listeners (not e.g. a browser tab connected to it);
/// `for p in $(…)` because zsh doesn't word-split a plain `$pids`.
/// Succeeds once nothing listens on the port.
String killPortCommand(int port, {bool windows = false}) {
  if (windows || Platform.isWindows) {
    // Windows has no polite stop for console programs, so straight to Stop-Process.
    final listeners =
        '@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Where-Object OwningProcess -gt 4)';
    return _ps(
        '\$l={$listeners}; & \$l | ForEach-Object {Stop-Process -Id \$_.OwningProcess -Force -ErrorAction SilentlyContinue}; '
        'for(\$i=0;\$i -lt 10;\$i++){if((& \$l).Count -eq 0){exit 0}; Start-Sleep -Milliseconds 500}; '
        '[Console]::Error.WriteLine(${psQuote('Port $port is still in use')}); exit 1');
  }
  final listeners = 'lsof -ti tcp:$port -sTCP:LISTEN';
  return 'for p in \$($listeners); do kill \$p; done; '
      'for i in \$(seq 10); do $listeners >/dev/null || exit 0; sleep 0.5; done; '
      'for p in \$($listeners); do kill -9 \$p; done; sleep 0.5; '
      '$listeners >/dev/null && { echo ${shellQuote('Port $port is still in use')} >&2; exit 1; }; exit 0';
}

final _killPort = RegExp(
    r'^(?:for p in \$\(lsof -ti tcp:|powershell -NoProfile -Command "\$l=\{@\(Get-NetTCPConnection -State Listen -LocalPort )(\d+)');

/// The port a [killPortCommand] frees, or null for any other command.
int? killPortTarget(String command) => int.tryParse(_killPort.firstMatch(command)?.group(1) ?? '');

// shortcut: rewrites "Kill port" steps saved before the fix above; drop once
// no saved workflow has the old command.
final _oldKillPort = RegExp(r'^pids=\$\(lsof -ti tcp:(\d+)\); \[ -z "\$pids" \] \|\| kill -9 \$pids$');

/// Upgrades a saved step's command that an older Appy generated.
String upgradeSavedCommand(String command) {
  final old = _oldKillPort.firstMatch(command);
  return old == null ? command : killPortCommand(int.parse(old.group(1)!));
}

/// Polls [check] once a second for up to two minutes.
String _waitLoop(String check, String what) =>
    'for i in \$(seq 120); do $check && exit 0; sleep 1; done; echo ${shellQuote('Gave up waiting for $what')} >&2; exit 1';

/// Wraps [s] in single quotes for PowerShell.
String psQuote(String s) => "'${s.replaceAll("'", "''")}'";

/// Runs a PowerShell [script] from cmd. The script must not contain `"`
/// (cmd and PowerShell would end the quoted argument there).
String _ps(String script) => 'powershell -NoProfile -Command "$script"';

String _psWaitLoop(String check, String what) => _ps('for(\$i=0;\$i -lt 120;\$i++){if($check){exit 0}; Start-Sleep 1}; '
    '[Console]::Error.WriteLine(${psQuote('Gave up waiting for $what')}); exit 1');

/// Run in the home folder; not tied to a project.
final globalHelpers = Platform.isWindows ? windowsHelpers : macHelpers;

final windowsHelpers = <HelperCommand>[
  HelperCommand('Run command', (a) => a.trim().isEmpty ? null : a.trim(),
      argHint: 'Any command, runs in your home folder', waitFor: null),
  HelperCommand('Kill port', argHint: 'Port, e.g. 3000', (a) {
    final port = _port(a);
    return port == null ? null : killPortCommand(port, windows: true);
  }),
  HelperCommand('Wait for port', argHint: 'Port, e.g. 8080', (a) {
    final port = _port(a);
    return port == null
        ? null
        : _psWaitLoop('(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)', ':$port');
  }),
  HelperCommand('Wait for URL', argHint: 'URL, e.g. http://localhost:3000/health', (a) {
    final url = _url(a)?.replaceAll('"', '%22');
    return url == null ? null : _psWaitLoop('\$(curl.exe -sfo NUL ${psQuote(url)}; \$LASTEXITCODE -eq 0)', url);
  }),
  HelperCommand('Open URL', argHint: 'URL, e.g. http://localhost:5173', (a) {
    final url = _url(a)?.replaceAll('"', '%22');
    return url == null ? null : _ps('Start-Process ${psQuote(url)}');
  }),
  HelperCommand('Wait seconds', argHint: 'Seconds, e.g. 5', (a) {
    final seconds = int.tryParse(a.trim());
    return seconds == null || seconds < 0 ? null : _ps('Start-Sleep $seconds');
  }),
  HelperCommand(
      'Start Docker',
      (_) => _psWaitLoop(
          '\$(docker info *>\$null; if(\$LASTEXITCODE -and -not (Get-Process -Name \'Docker Desktop\' -ErrorAction SilentlyContinue))'
              '{Start-Process (Join-Path \$env:ProgramFiles \'Docker\\Docker\\Docker Desktop.exe\') -ErrorAction SilentlyContinue}; '
              'docker info *>\$null; \$LASTEXITCODE -eq 0)',
          'Docker')),
];

final macHelpers = <HelperCommand>[
  HelperCommand('Run command', (a) => a.trim().isEmpty ? null : a.trim(),
      argHint: 'Any command, runs in your home folder', waitFor: null),
  HelperCommand('Kill port', argHint: 'Port, e.g. 3000', (a) {
    final port = _port(a);
    return port == null ? null : killPortCommand(port);
  }),
  HelperCommand('Wait for port', argHint: 'Port, e.g. 8080', (a) {
    final port = _port(a);
    return port == null ? null : _waitLoop('nc -z localhost $port', ':$port');
  }),
  HelperCommand('Wait for URL', argHint: 'URL, e.g. http://localhost:3000/health', (a) {
    final url = _url(a);
    return url == null ? null : _waitLoop('curl -sfo /dev/null ${shellQuote(url)}', url);
  }),
  HelperCommand('Open URL', argHint: 'URL, e.g. http://localhost:5173', (a) {
    final url = _url(a);
    return url == null ? null : 'open ${shellQuote(url)}';
  }),
  HelperCommand('Notify', argHint: 'Message, e.g. CSS workcard is up', (a) {
    final text = a.trim();
    // jsonEncode gives a quoted, escaped string AppleScript accepts as-is.
    return text.isEmpty
        ? null
        : 'osascript -e ${shellQuote('display notification ${jsonEncode(text)} with title "Appy"')}';
  }),
  HelperCommand('Wait seconds', argHint: 'Seconds, e.g. 5', (a) {
    final seconds = int.tryParse(a.trim());
    return seconds == null || seconds < 0 ? null : 'sleep $seconds';
  }),
  HelperCommand('Open iOS Simulator', (_) => 'open -a Simulator'),
  HelperCommand('Start Docker',
      (_) => _waitLoop('(docker info >/dev/null 2>&1 || open -ga Docker; docker info >/dev/null 2>&1)', 'Docker')),
];

/// Run in a project's folder when it is a git repo.
final gitHelpers = <HelperCommand>[
  HelperCommand('git pull', (_) => 'git pull'),
  HelperCommand('git fetch', (_) => 'git fetch --all --prune'),
  HelperCommand('git stash', (_) => 'git stash'),
  HelperCommand('Checkout branch', argHint: 'Branch, e.g. develop', (a) {
    final branch = a.trim();
    final valid = RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(branch) && !branch.startsWith('-');
    return valid ? 'git checkout $branch' : null;
  }),
];

/// What a "Run application" step does with the app.
enum AppAction { open, openIfNotRunning, restart, quit }

extension AppActionText on AppAction {
  String get label => switch (this) {
        AppAction.open => 'Open',
        AppAction.openIfNotRunning => 'Open if not running',
        AppAction.restart => 'Restart',
        AppAction.quit => 'Quit',
      };

  String get hint => switch (this) {
        AppAction.open => 'Brings it to the front, launching it if needed',
        AppAction.openIfNotRunning => 'Launches it only when it isn\'t running yet',
        AppAction.restart => 'Quits it if it runs, then opens it again',
        AppAction.quit => 'Asks it to quit, like ⌘Q — handy in "On stop"',
      };

  /// Step label, e.g. "Restart Simulator".
  String stepLabel(String app) => this == AppAction.openIfNotRunning ? 'Open $app if not running' : '$label $app';
}

final _bundleId = RegExp(r'^[A-Za-z0-9.-]+$');

/// Shell command for a "Run application" step, or null for an invalid bundle id.
/// Apps are addressed by bundle id, so renaming or moving them doesn't matter.
/// [args] are passed as-is to the shell (the user's own command line).
/// Quitting is polite only (AppleScript, like ⌘Q): never a force-kill, which
/// would throw away unsaved work if the app asks "Save changes?".
String? appCommand({
  required String bundleId,
  required String name,
  required AppAction action,
  bool background = false,
  String target = '',
  String args = '',
}) {
  if (!_bundleId.hasMatch(bundleId)) return null;
  final running = '[ -n "\$(lsappinfo find bundleid=$bundleId)" ]';
  final open = [
    'open',
    if (background) '-g',
    '-b $bundleId',
    if (target.trim().isNotEmpty) shellQuote(target.trim()),
    if (args.trim().isNotEmpty) '--args ${args.trim()}',
  ].join(' ');
  final quit = 'if $running; then '
      'osascript -e ${shellQuote('tell application id "$bundleId" to quit')} >/dev/null 2>&1 || '
      '{ echo ${shellQuote('Appy may not control $name yet: allow it in System Settings › Privacy & Security › Automation')} >&2; exit 1; }; '
      'for i in \$(seq 40); do $running || break; sleep 0.5; done; '
      // `if`, not `&&`: as the last command, a false `&&` would make the step fail.
      'if $running; then echo ${shellQuote('$name did not quit (is it asking to save?)')} >&2; exit 1; fi; '
      'fi';
  return switch (action) {
    AppAction.open => open,
    AppAction.openIfNotRunning => '$running && { echo ${shellQuote('$name is already running')}; exit 0; }; $open',
    AppAction.restart => '$quit; $open',
    AppAction.quit => quit,
  };
}
