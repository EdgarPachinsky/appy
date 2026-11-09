import 'package:appy/models/workflow.dart';
import 'package:appy/theme.dart';
import 'package:appy/ui/app_step_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pick app → Add step returns the step', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    WorkflowStep? result;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Builder(builder: (context) => TextButton(
        onPressed: () async => result = await showAppStepDialog(context, projectId: 'home'),
        child: const Text('open'),
      )),
    ));
    await tester.tap(find.text('open'));
    for (var i = 0; i < 20 && find.text('Calculator').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.enterText(find.widgetWithText(TextField, 'Search apps'), 'calcul');
    await tester.pump();
    // Real I/O (plutil) only completes when started outside the fake clock.
    await tester.runAsync(() async {
      await tester.tap(find.text('Calculator'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    for (var i = 0; i < 30 && find.text('RUNS').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('RUNS'), findsOneWidget, reason: 'bundle id read → command preview shown');
    await tester.tap(find.text('Quit'));
    await tester.pump();
    await tester.ensureVisible(find.text('Add step'));
    await tester.tap(find.text('Add step'));
    await tester.pumpAndSettle();
    expect(result?.label, 'Quit Calculator');
    expect(result?.command, contains('com.apple.calculator'));
    expect(result?.waitFor, WaitFor.exit);
  });
}
