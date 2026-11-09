import 'dart:convert';
import 'dart:io';

/// Apps launched from Finder/Dock get a tiny PATH. This loads the user's real
/// login-shell environment once (nvm, Homebrew, Flutter, pyenv…) so commands
/// run exactly like they would in Terminal.
class ShellEnv {
  static Map<String, String>? _cached;
  static Future<Map<String, String>>? _loading;

  static Future<Map<String, String>> load() {
    if (_cached != null) return Future.value(_cached);
    return _loading ??= _load();
  }

  static Future<Map<String, String>> _load() async {
    // Windows apps already get the user's full PATH from the registry.
    if (Platform.isWindows) return _cached = Map<String, String>.of(Platform.environment);
    final env = Map<String, String>.of(Platform.environment);
    const marker = '__APPY_ENV__';
    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
    Process? process;
    try {
      // Detached = its own session without a controlling terminal. An
      // interactive (-i) shell would otherwise take over the terminal that
      // `flutter run` reads r / R from, and the next keypress crashes it.
      process = await Process.start(
        shell,
        ['-ilc', 'printf "$marker"; /usr/bin/env -0'],
        mode: ProcessStartMode.detachedWithStdio,
      );
      process.stderr.drain<void>();
      final out = await process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 15));
      final start = out.indexOf(marker);
      if (start >= 0) {
        for (final entry in out.substring(start + marker.length).split('\u0000')) {
          final eq = entry.indexOf('=');
          if (eq > 0) env[entry.substring(0, eq).trim()] = entry.substring(eq + 1);
        }
      }
    } catch (_) {
      // Fall back to the app's own environment plus common paths below.
      process?.kill(); // e.g. a .zshrc that hangs past the timeout
    }

    final home = env['HOME'] ?? '';
    final path = (env['PATH'] ?? '').split(':').where((s) => s.isNotEmpty).toList();
    for (final extra in [
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '$home/.pub-cache/bin',
      '$home/.cargo/bin',
      '$home/go/bin',
      '/usr/bin',
      '/bin',
      '/usr/sbin',
      '/sbin',
    ]) {
      if (!path.contains(extra)) path.add(extra);
    }
    env['PATH'] = path.join(':');
    env.remove('_');
    env.remove('SHLVL');
    env.remove('OLDPWD');
    env.remove('PWD');
    _cached = env;
    return env;
  }
}
