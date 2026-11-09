import 'dart:convert';
import 'dart:io';

import 'package:appy/models/project.dart';
import 'package:appy/models/workflow.dart';
import 'package:appy/services/app_launcher.dart';
import 'package:appy/services/helpers.dart';
import 'package:appy/services/hotkeys.dart';
import 'package:appy/services/run_session.dart';
import 'package:appy/services/workflow_runner.dart';
import 'package:appy/state/app_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

void main() {
  late Directory dir;
  final sessions = <RunSession>[];

  setUp(() => dir = Directory.systemTemp.createTempSync('appy_wf'));
  tearDown(() async {
    for (final s in sessions) {
      await s.stop();
    }
    sessions.clear();
    dir.deleteSync(recursive: true);
  });

  Future<(RunSession, bool)> runStep(String command, WaitFor waitFor) async {
    final project = Project(id: 'p', path: dir.path, name: 'p');
    final session = RunSession(project: project, option: RunOption(id: 'x', label: 'x', command: command));
    sessions.add(session);
    await session.start(Platform.environment);
    final step = WorkflowStep(projectId: 'p', label: 'x', command: command, waitFor: waitFor, delaySeconds: 0);
    final ok = await waitForStep(session, step).timeout(const Duration(seconds: 10));
    return (session, ok);
  }

  test('servers wait until ready, one-shot commands until they exit', () {
    for (final cmd in ['npm run dev', 'flutter run --machine -d macos', 'docker compose up', 'pnpm run start']) {
      expect(WorkflowStep.defaultWaitFor(cmd), WaitFor.ready, reason: cmd);
    }
    for (final cmd in ['flutter pub get', 'npm run build', 'git pull', 'npm run update', 'cargo test', 'curl -sf x >/dev/null']) {
      expect(WorkflowStep.defaultWaitFor(cmd), WaitFor.exit, reason: cmd);
    }
  });

  test('workflow survives a json round trip', () {
    final w = Workflow(id: 'w', name: 'css', steps: [
      WorkflowStep(projectId: 'a', optionId: 'node:dev', label: 'dev', command: 'npm run dev'),
      WorkflowStep(projectId: 'home', label: 'ls', command: 'ls', waitFor: WaitFor.delay, delaySeconds: 3),
    ], shutdownSteps: [
      WorkflowStep(projectId: 'a', label: 'down', command: 'docker compose down'),
    ]);
    final back = Workflow.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>);
    expect(back.name, 'css');
    expect(back.steps.map((s) => s.id), w.steps.map((s) => s.id));
    expect(back.steps[0].waitFor, WaitFor.ready);
    expect(back.steps[1].optionId, isNull);
    expect(back.steps[1].delaySeconds, 3);
    expect(back.shutdownSteps.single.command, 'docker compose down');
  });

  test('exit: succeeds on code 0, fails otherwise', () async {
    expect((await runStep('echo hi', WaitFor.exit)).$2, isTrue);
    expect((await runStep('exit 3', WaitFor.exit)).$2, isFalse);
  });

  test('ready: a dev server URL moves on while it keeps running', () async {
    final (session, ok) = await runStep('echo "  Local:   http://localhost:5173/"; sleep 30', WaitFor.ready);
    expect(ok, isTrue);
    expect(session.isActive, isTrue);
    expect(session.url, 'http://localhost:5173/');
  });

  test('ready: a command that crashes before being ready fails', () async {
    final (session, ok) = await runStep(
        'echo "Error: listen EADDRINUSE: address already in use :::3000" >&2; exit 1', WaitFor.ready);
    expect(ok, isFalse);
    expect(session.portInUse, 3000);
  });

  test('port in use is read from Go and Rails style errors', () async {
    final (go, _) = await runStep('echo "listen tcp :8080: bind: address already in use"; exit 1', WaitFor.exit);
    expect(go.portInUse, 8080);
    final (rails, _) = await runStep(
        'echo "Address already in use - bind(2) for \\"127.0.0.1\\" port 4000"; exit 1', WaitFor.exit);
    expect(rails.portInUse, 4000);
  });

  test("don't wait: moves on right away", () async {
    final (session, ok) = await runStep('sleep 30', WaitFor.none);
    expect(ok, isTrue);
    expect(session.isActive, isTrue);
  });

  test('hotkey json is storable and labelled mac-style', () {
    final key = HotKey(key: PhysicalKeyboardKey.digit1, modifiers: [HotKeyModifier.meta, HotKeyModifier.alt]);
    final json = jsonDecode(jsonEncode(key.toJson())) as Map<String, dynamic>;
    expect(Hotkeys.label(json), '⌥⌘1');
  });

  group('helpers', () {
    HelperCommand helper(String label) => [...globalHelpers, ...gitHelpers].firstWhere((h) => h.label == label);

    test('reject invalid arguments', () {
      expect(helper('Kill port').build('abc'), isNull);
      expect(helper('Kill port').build('70000'), isNull);
      expect(helper('Wait for URL').build('localhost:3000'), isNull);
      expect(helper('Open URL').build('file:///etc/passwd'), isNull);
      expect(helper('Checkout branch').build('main; rm -rf ~'), isNull);
      expect(helper('Checkout branch').build('--force'), isNull);
      expect(helper('Checkout branch').build('feature/css-card'), 'git checkout feature/css-card');
      expect(helper('Notify').build('  '), isNull);
    });

    test('quoted arguments reach the command intact', () async {
      final r = await Process.run('/bin/zsh', ['-c', 'echo ${shellQuote("it's \$HOME; ok")}']);
      expect((r.stdout as String).trim(), "it's \$HOME; ok");
      expect(helper('Notify').build('Bob\'s "css" card'), contains(r'display notification "Bob'));
    });

    test('wait for port, then kill port — the server only, not connected clients', () async {
      const port = 47123;
      final server = await Process.start('python3', ['-m', 'http.server', '$port']);
      addTearDown(server.kill);
      final wait = await Process.run('/bin/zsh', ['-c', helper('Wait for port').build('$port')!]);
      expect(wait.exitCode, 0);
      // Like a browser tab open on the dev server.
      final client = await Process.start(
          'python3', ['-c', 'import socket,time; s=socket.create_connection(("127.0.0.1",$port)); time.sleep(30)']);
      addTearDown(client.kill);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final kill = await Process.run('/bin/zsh', ['-c', helper('Kill port').build('$port')!]);
      expect(kill.exitCode, 0, reason: '${kill.stderr}');
      await server.exitCode.timeout(const Duration(seconds: 5));
      expect(Process.runSync('/bin/kill', ['-0', '${client.pid}']).exitCode, 0, reason: 'client must survive');
      // Nothing left on the port: still succeeds.
      expect((await Process.run('/bin/zsh', ['-c', helper('Kill port').build('$port')!])).exitCode, 0);
    });

    test('kill port force-kills a server that ignores Ctrl+C', () async {
      const port = 47124;
      final server = await Process.start('python3', [
        '-c',
        'import signal,socket,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); '
            's=socket.socket(); s.bind(("127.0.0.1",$port)); s.listen(); time.sleep(60)',
      ]);
      addTearDown(server.kill);
      await Process.run('/bin/zsh', ['-c', helper('Wait for port').build('$port')!]);
      final kill = await Process.run('/bin/zsh', ['-c', helper('Kill port').build('$port')!]);
      expect(kill.exitCode, 0, reason: '${kill.stderr}');
      expect(await server.exitCode.timeout(const Duration(seconds: 5)), -9);
    });

    test('saved steps with the old kill command are upgraded on load', () {
      final step = WorkflowStep.fromJson({
        'projectId': 'home',
        'label': 'Kill port 4200',
        'command': r'pids=$(lsof -ti tcp:4200); [ -z "$pids" ] || kill -9 $pids',
      });
      expect(step.command, killPortCommand(4200));
      expect(upgradeSavedCommand('npm run dev'), 'npm run dev');
    });
  });

  group('shutdown', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    Future<(AppState, Workflow)> setup() async {
      final state = AppState();
      final project = await state.addFolder(dir.path);
      final w = state.addWorkflow('css');
      w.steps.add(WorkflowStep(
          projectId: project.id, label: 'server', command: 'echo "listening on 1234"; sleep 60', waitFor: WaitFor.ready));
      w.shutdownSteps.add(WorkflowStep(projectId: project.id, label: 'down', command: 'touch down.txt'));
      addTearDown(state.stopAll);
      return (state, w);
    }

    test('Stop ctrl+c\'s the running steps, then runs the On stop steps', () async {
      final (state, w) = await setup();
      await state.runWorkflow(w).timeout(const Duration(seconds: 20));
      expect(state.isWorkflowLive(w), isTrue);

      await state.stopWorkflow(w).timeout(const Duration(seconds: 20));
      expect(state.isWorkflowLive(w), isFalse);
      expect(state.activeSessions, isEmpty);
      expect(File('${dir.path}/down.txt').existsSync(), isTrue);
    });

    test('a server started outside the run is stopped too', () async {
      final (state, w) = await setup();
      final target = state.resolveStep(w.steps.single)!;
      await state.run(target.$1, target.$2); // e.g. started from the project page
      expect(state.isWorkflowLive(w), isTrue);
      await state.stopWorkflow(w).timeout(const Duration(seconds: 20));
      expect(state.activeSessions, isEmpty);
    });

    test('without a stop shortcut, the start shortcut toggles', () async {
      final (state, w) = await setup();
      state.startShortcut(w);
      await Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return state.isWorkflowRunning(w);
      }).timeout(const Duration(seconds: 20));
      expect(state.isWorkflowLive(w), isTrue);
      state.startShortcut(w);
      await Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return state.workflowRuns[w.id]!.stopping;
      }).timeout(const Duration(seconds: 20));
      expect(state.isWorkflowLive(w), isFalse);
      expect(File('${dir.path}/down.txt').existsSync(), isTrue);
    });

    test('with a stop shortcut, the start shortcut only starts', () async {
      final (state, w) = await setup();
      w.stopHotkey = {'placeholder': true};
      await state.runWorkflow(w).timeout(const Duration(seconds: 20));
      state.startShortcut(w); // already live → would run again, not stop
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(state.isWorkflowLive(w), isTrue);
      expect(state.workflowRuns[w.id]!.stopping, isFalse);
    });

    test('stop shortcut json survives a round trip', () {
      final w = Workflow(id: 'w', name: 'css', hotkey: {'a': 1}, stopHotkey: {'b': 2});
      final back = Workflow.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>);
      expect(back.stopHotkey, {'b': 2});
    });

    test('rerun: Kill port on a server Appy runs restarts it instead of skipping it', () async {
      final sent = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('appy/native'), (call) async {
        if (call.method == 'notify') sent.add((call.arguments as Map)['title'] as String);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('appy/native'), null));
      final state = AppState();
      addTearDown(state.stopAll);
      final project = await state.addFolder(dir.path);
      final w = state.addWorkflow('rerun');
      w.steps.addAll([
        WorkflowStep(projectId: 'home', label: 'Kill port 47130', command: killPortCommand(47130)),
        WorkflowStep(
            projectId: project.id, label: 'server', command: 'python3 -u -m http.server 47130', waitFor: WaitFor.ready),
      ]);
      await state.runWorkflow(w).timeout(const Duration(seconds: 20));
      await state.runWorkflow(w).timeout(const Duration(seconds: 20)); // servers still up
      expect(state.workflowRuns[w.id]!.error, isNull);
      expect(state.activeSessions.single.option.label, 'server');
      expect(sent.where((t) => t == '▶ server is running'), hasLength(2));
      expect(sent.where((t) => t.startsWith('✗')), isEmpty);
    });
  });

  group('nested workflows', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late List<String> sent;
    late AppState state;
    late String projectId;

    setUp(() async {
      sent = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('appy/native'), (call) async {
        if (call.method == 'notify') sent.add((call.arguments as Map)['title'] as String);
        return null;
      });
      state = AppState();
      projectId = (await state.addFolder(dir.path)).id;
    });
    tearDown(() async {
      await state.stopAll();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('appy/native'), null);
    });

    WorkflowStep echo(String text) => WorkflowStep(projectId: projectId, label: text, command: 'echo $text >> log.txt');
    String log() => File('${dir.path}/log.txt').readAsStringSync().split('\n').where((l) => l.isNotEmpty).join(' ');

    test('runs the child between steps, in order, reporting only through the parent', () async {
      final child = state.addWorkflow('child')..steps.addAll([echo('B1'), echo('B2')]);
      final parent = state.addWorkflow('parent')
        ..steps.addAll([echo('A'), WorkflowStep.workflow(child), echo('C')]);
      expect(await state.runWorkflow(parent).timeout(const Duration(seconds: 20)), isTrue);
      expect(log(), 'A B1 B2 C');
      expect(sent.last, '✓ parent');
      expect(sent, isNot(contains('✓ child')), reason: 'the child reports through the parent');
    });

    test('a failing child fails the parent and says why', () async {
      final child = state.addWorkflow('child')
        ..steps.add(WorkflowStep(projectId: projectId, label: 'boom', command: 'exit 3'));
      final parent = state.addWorkflow('parent')..steps.addAll([WorkflowStep.workflow(child), echo('never')]);
      expect(await state.runWorkflow(parent).timeout(const Duration(seconds: 20)), isFalse);
      expect(state.workflowRuns[parent.id]!.error, 'child: "boom" failed');
      expect(File('${dir.path}/log.txt').existsSync(), isFalse);
    });

    test('Stop shuts the child down too, with its On stop steps', () async {
      final child = state.addWorkflow('child')
        ..steps.add(WorkflowStep(
            projectId: projectId, label: 'server', command: 'echo "listening"; sleep 60', waitFor: WaitFor.ready))
        ..shutdownSteps.add(echo('child-down'));
      final parent = state.addWorkflow('parent')
        ..steps.add(WorkflowStep.workflow(child))
        ..shutdownSteps.add(echo('parent-down'));
      await state.runWorkflow(parent).timeout(const Duration(seconds: 20));
      expect(state.isWorkflowLive(parent), isTrue, reason: "the child's server counts");

      await state.stopWorkflow(parent).timeout(const Duration(seconds: 20));
      expect(state.activeSessions, isEmpty);
      expect(log(), 'child-down parent-down');
      expect(sent.where((t) => t.startsWith('■')), ['■ parent shut down']);
    });

    test('loops are refused in the palette and stopped at run time', () async {
      final a = state.addWorkflow('a')..steps.add(echo('A'));
      final b = state.addWorkflow('b')..steps.add(WorkflowStep.workflow(a));
      expect(state.canNest(a, b), isFalse, reason: 'b already runs a');
      expect(state.canNest(b, a), isTrue);
      expect(state.canNest(a, a), isFalse);

      a.steps.add(WorkflowStep.workflow(b)); // a saved loop, e.g. from an old version
      expect(await state.runWorkflow(a).timeout(const Duration(seconds: 20)), isFalse);
      expect(state.workflowRuns[b.id]!.error, '"a" would run inside itself');
      expect(state.isWorkflowLive(a), isFalse, reason: 'no endless recursion');
    });
  });

  group('run application', () {
    test('finds installed apps and reads their bundle id', () async {
      final apps = await AppLauncher.allApps();
      final calculator = apps.firstWhere((a) => a.name == 'Calculator');
      expect(await AppLauncher.bundleId(calculator.path), 'com.apple.calculator');
      expect(await AppLauncher.bundleId('/nope/Missing.app'), isNull);
    });

    test('commands address the app by a validated bundle id', () {
      expect(appCommand(bundleId: 'x"; rm -rf ~', name: 'X', action: AppAction.open), isNull);
      expect(appCommand(bundleId: 'com.apple.calculator', name: 'Calculator', action: AppAction.open, background: true),
          'open -g -b com.apple.calculator');
      expect(
          appCommand(
              bundleId: 'com.google.Chrome', name: 'Chrome', action: AppAction.open, target: "http://localhost:4200/a b"),
          "open -b com.google.Chrome 'http://localhost:4200/a b'");
      expect(AppAction.openIfNotRunning.stepLabel('Simulator'), 'Open Simulator if not running');
    });
  });
}
