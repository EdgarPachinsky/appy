import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../models/workflow.dart';

/// System-wide shortcuts that start workflows (work while Appy is hidden).
class Hotkeys {
  static Future<void> _pending = Future.value();
  static bool _paused = false;

  /// Unregisters every shortcut until [resume] — e.g. while recording one,
  /// so pressing a combo that's already registered records it instead of
  /// firing it.
  static Future<void> pause() {
    _paused = true;
    return _pending = _pending.then((_) async {
      try {
        await hotKeyManager.unregisterAll();
      } catch (_) {}
    });
  }

  /// Ends [pause]; call [sync] afterwards to register the shortcuts again.
  static void resume() => _paused = false;

  /// Each widget test has its own fake clock; a queue left from the last one never finishes.
  @visibleForTesting
  static void reset() {
    _pending = Future.value();
    _paused = false;
  }

  /// Replaces all registered shortcuts with the workflows' current ones.
  /// Calls are queued so overlapping syncs can't double-register.
  static Future<void> sync(
    List<Workflow> workflows, {
    required void Function(Workflow) onStart,
    required void Function(Workflow) onStop,
  }) =>
      _pending = _pending.then((_) => _sync(workflows, onStart, onStop));

  static Future<void> _sync(
    List<Workflow> workflows,
    void Function(Workflow) onStart,
    void Function(Workflow) onStop,
  ) async {
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {
      return; // No plugin (tests) — nothing to register with.
    }
    if (_paused) return;
    for (final w in workflows) {
      for (final (json, handler) in [(w.hotkey, onStart), (w.stopHotkey, onStop)]) {
        if (json == null) continue;
        try {
          await hotKeyManager.register(HotKey.fromJson(json), keyDownHandler: (_) => handler(w));
        } catch (_) {}
      }
    }
  }

  static const _order = [HotKeyModifier.control, HotKeyModifier.alt, HotKeyModifier.shift, HotKeyModifier.meta];
  static const _glyphs = {
    HotKeyModifier.control: '⌃',
    HotKeyModifier.alt: '⌥',
    HotKeyModifier.shift: '⇧',
    HotKeyModifier.meta: '⌘',
  };

  /// e.g. "⌥⌘1".
  static String label(Map<String, dynamic> json) => keys(json).join();

  /// The keys in Mac order, e.g. ["⌥", "⌘", "1"].
  static List<String> keys(Map<String, dynamic> json) {
    try {
      final key = HotKey.fromJson(json);
      final mods = key.modifiers ?? const [];
      return [
        for (final m in _order)
          if (mods.contains(m)) _glyphs[m]!,
        key.logicalKey.keyLabel.toUpperCase(),
      ];
    } catch (_) {
      return const [];
    }
  }
}
