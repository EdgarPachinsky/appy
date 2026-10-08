import 'package:flutter/services.dart';

/// Talks to Appy's own Swift code (macos/Runner/MainFlutterWindow.swift).
class NativeBridge {
  static const _channel = MethodChannel('appy/native');

  /// Lets folders be dropped onto the menu bar icon.
  static Future<void> enableTrayDrop(void Function(List<String> paths) onDrop) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'trayDrop') {
        final paths = (call.arguments as List?)?.cast<String>() ?? const <String>[];
        if (paths.isNotEmpty) onDrop(paths);
      }
      return null;
    });
    // The status item is created asynchronously; retry briefly.
    for (var i = 0; i < 5; i++) {
      try {
        final ok = await _channel.invokeMethod<bool>('enableTrayDrop');
        if (ok == true) return;
      } on MissingPluginException {
        return; // Native side not installed (setup.sh not re-run).
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }
}
