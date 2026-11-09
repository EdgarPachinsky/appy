import 'package:appy/models/workflow.dart';
import 'package:appy/services/hotkeys.dart';
import 'package:appy/state/app_state.dart';
import 'package:appy/theme.dart';
import 'package:appy/ui/workflow_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

void main() {
  /// Calls to the native hotkey plugin, e.g. "unregisterAll", "register".
  late List<String> native;

  setUp(() {
    Hotkeys.reset();
    native = [];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('dev.leanflutter.plugins/hotkey_manager'), (call) async {
      native.add(call.method);
      return null;
    });
    messenger.setMockStreamHandler(const EventChannel('dev.leanflutter.plugins/hotkey_manager_event'),
        MockStreamHandler.inline(onListen: (_, __) {}));
  });

  Future<Workflow> open(WidgetTester tester, {Map<String, dynamic>? start}) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState();
    final w = state.addWorkflow('css');
    w.steps.add(WorkflowStep(projectId: 'home', label: 'x', command: 'sleep 1'));
    w.hotkey = start;
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: WorkflowPage(workflow: w, state: state)));
    await tester.tap(find.byTooltip('Global shortcuts to start / stop this workflow'));
    await tester.pump(const Duration(milliseconds: 400)); // the header's double-tap timeout
    await tester.pumpAndSettle();
    expect(find.text('Global shortcuts'), findsOneWidget);
    return w;
  }

  Future<void> press(WidgetTester tester, List<LogicalKeyboardKey> keys) async {
    for (final k in keys) {
      await tester.sendKeyDownEvent(k);
    }
    for (final k in keys.reversed) {
      await tester.sendKeyUpEvent(k);
    }
    await tester.pump();
  }

  Future<void> tapRowButton(WidgetTester tester, String row, String button) async {
    final rowBox = find.ancestor(of: find.text(row), matching: find.byType(Container)).first;
    await tester.tap(find.descendant(of: rowBox, matching: find.text(button)));
    await tester.pumpAndSettle();
  }

  testWidgets('set a stop shortcut inline, then clear it', (tester) async {
    final w = await open(tester);
    expect(find.text('Not set'), findsNWidgets(2));

    await tapRowButton(tester, 'Stop workflow', 'Set');
    expect(find.text('Press keys…'), findsOneWidget);
    await press(tester, [LogicalKeyboardKey.altLeft, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyX]);
    await tapRowButton(tester, 'Stop workflow', 'Save');
    expect(w.stopHotkey, isNotNull);
    expect(w.hotkey, isNull, reason: 'only the stop row changed');
    expect(find.text('Change'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear stop shortcut'));
    await tester.pumpAndSettle();
    expect(w.stopHotkey, isNull);
    expect(find.text('Not set'), findsNWidgets(2));
  });

  testWidgets('refuses a combo already in use, and a bare key', (tester) async {
    final start = HotKey(key: PhysicalKeyboardKey.keyF, modifiers: [HotKeyModifier.alt, HotKeyModifier.meta]);
    final w = await open(tester, start: start.toJson());

    await tapRowButton(tester, 'Stop workflow', 'Set');
    await press(tester, [LogicalKeyboardKey.altLeft, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyF]);
    expect(find.textContaining("Already used by this workflow's start shortcut"), findsOneWidget);
    await tapRowButton(tester, 'Stop workflow', 'Save'); // disabled
    expect(w.stopHotkey, isNull);

    await press(tester, [LogicalKeyboardKey.keyF]);
    expect(find.text('Add ⌘, ⌥, ⌃ or ⇧ to the key'), findsOneWidget);

    await tapRowButton(tester, 'Stop workflow', 'Cancel');
    expect(find.text('Press keys…'), findsNothing);
    expect(w.stopHotkey, isNull);
  });

  testWidgets('global shortcuts are paused while open, registered again on Done', (tester) async {
    final start = HotKey(key: PhysicalKeyboardKey.keyF, modifiers: [HotKeyModifier.alt, HotKeyModifier.meta]);
    await open(tester, start: start.toJson());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    native.clear();

    // Saving while open must not re-register (it would fire instead of record).
    await tapRowButton(tester, 'Stop workflow', 'Set');
    await press(tester, [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyX]);
    await tapRowButton(tester, 'Stop workflow', 'Save');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(native, isNot(contains('register')));

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(native.where((m) => m == 'register'), hasLength(2), reason: 'start + stop');
  });
}
