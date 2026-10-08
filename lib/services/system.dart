import 'dart:io';

/// Small macOS helpers built on `open`.
class SystemActions {
  static Future<void> openUrl(String url) => _open([url]);
  static Future<void> revealInFinder(String path) => _open([path]);
  static Future<void> openInTerminal(String path) => _open(['-a', 'Terminal', path]);

  static Future<void> _open(List<String> args) async {
    try {
      await Process.run('/usr/bin/open', args);
    } catch (_) {}
  }
}
