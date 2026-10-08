import 'dart:io';

import 'package:appy/models/project.dart';
import 'package:appy/services/detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('appy_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('detects a Vite node project and prefers the dev script', () async {
    File('${dir.path}/package.json').writeAsStringSync(
        '{"scripts":{"build":"vite build","dev":"vite"},"devDependencies":{"vite":"5"}}');
    File('${dir.path}/pnpm-lock.yaml').writeAsStringSync('');
    final info = await ProjectDetector.detect(dir.path);
    expect(info.kind, ProjectKind.node);
    expect(info.title, 'Node · Vite');
    final primary = info.options.firstWhere((o) => o.primary);
    expect(primary.command, 'pnpm run dev');
  });

  test('detects a Flutter app with macOS target', () async {
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: x\ndependencies:\n  flutter:\n    sdk: flutter\n');
    Directory('${dir.path}/macos').createSync();
    final info = await ProjectDetector.detect(dir.path);
    expect(info.kind, ProjectKind.flutter);
    final primary = info.options.firstWhere((o) => o.primary);
    expect(primary.isFlutterRun, isTrue);
    expect(primary.command, 'flutter run --machine -d macos');
  });

  test('empty folder has no options', () async {
    final info = await ProjectDetector.detect(dir.path);
    expect(info.kind, ProjectKind.unknown);
    expect(info.options, isEmpty);
  });
}
