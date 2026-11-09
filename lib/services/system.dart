import 'dart:io';

/// Small OS helpers: `open` on macOS, Explorer / the shell on Windows.
class SystemActions {
  static String get revealLabel => Platform.isWindows ? 'Show in Explorer' : 'Show in Finder';

  static Future<void> openUrl(String url) =>
      Platform.isWindows ? _run('rundll32', ['url.dll,FileProtocolHandler', url]) : _open([url]);

  static Future<void> revealInFinder(String path) => Platform.isWindows ? _run('explorer', [path]) : _open([path]);

  static Future<void> openInTerminal(String path) => Platform.isWindows
      ? _run('cmd', ['/c', 'start', '', 'powershell', '-NoExit'], workingDirectory: path)
      : _open(['-a', 'Terminal', path]);

  static Future<void> _open(List<String> args) => _run('/usr/bin/open', args);

  static Future<void> _run(String exe, List<String> args, {String? workingDirectory}) async {
    try {
      await Process.run(exe, args, workingDirectory: workingDirectory);
    } catch (_) {}
  }
}
