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
    final env = Map<String, String>.of(Platform.environment);
    const marker = '__APPY_ENV__';
    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
    try {
      final result = await Process.run(
        shell,
        ['-ilc', 'printf "$marker"; /usr/bin/env -0'],
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      ).timeout(const Duration(seconds: 15));
      final out = result.stdout as String;
      final start = out.indexOf(marker);
      if (start >= 0) {
        for (final entry in out.substring(start + marker.length).split('\u0000')) {
          final eq = entry.indexOf('=');
          if (eq > 0) env[entry.substring(0, eq).trim()] = entry.substring(eq + 1);
        }
      }
    } catch (_) {
      // Fall back to the app's own environment plus common paths below.
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
