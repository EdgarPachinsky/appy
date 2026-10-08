import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project.dart';

/// Looks at a folder and figures out what it is and how it can be run.
class ProjectDetector {
  static Future<ProjectInfo> detect(String dir) async {
    try {
      return _detect(dir);
    } catch (_) {
      return ProjectInfo.empty;
    }
  }

  static ProjectInfo _detect(String dir) {
    bool has(String name) =>
        FileSystemEntity.typeSync(p.join(dir, name)) != FileSystemEntityType.notFound;

    String? read(String name) {
      final file = File(p.join(dir, name));
      if (!file.existsSync()) return null;
      try {
        return file.readAsStringSync();
      } catch (_) {
        return null;
      }
    }

    final kinds = <ProjectKind>[];
    final tags = <String>[];
    final options = <RunOption>[];

    // ---------- Flutter / Dart ----------
    final pubspec = read('pubspec.yaml');
    if (pubspec != null) {
      final isFlutter = RegExp(r'^\s+sdk:\s*flutter\s*$', multiLine: true).hasMatch(pubspec);
      if (isFlutter) {
        kinds.add(ProjectKind.flutter);
        final targets = <(String, String, String)>[
          // (folder, device id, label)
          if (has('macos')) ('macos', 'macos', 'macOS'),
          if (has('web')) ('web', 'chrome', 'Chrome'),
          if (has('ios')) ('ios', 'iPhone', 'iOS Simulator'),
          if (has('windows') && Platform.isWindows) ('windows', 'windows', 'Windows'),
          if (has('linux') && Platform.isLinux) ('linux', 'linux', 'Linux'),
        ];
        for (var i = 0; i < targets.length; i++) {
          final t = targets[i];
          options.add(RunOption(
            id: 'flutter:run:${t.$2}',
            label: 'Run ${t.$3}',
            command: 'flutter run --machine -d ${t.$2}',
            group: 'Flutter',
            isFlutterRun: true,
            primary: i == 0,
          ));
        }
        options.addAll(const [
          RunOption(id: 'flutter:pub-get', label: 'pub get', command: 'flutter pub get', group: 'Flutter'),
          RunOption(id: 'flutter:test', label: 'test', command: 'flutter test', group: 'Flutter'),
          RunOption(id: 'flutter:analyze', label: 'analyze', command: 'flutter analyze', group: 'Flutter'),
          RunOption(id: 'flutter:clean', label: 'clean', command: 'flutter clean', group: 'Flutter'),
        ]);
        if (has('macos')) {
          options.add(const RunOption(
              id: 'flutter:build-macos', label: 'build macOS', command: 'flutter build macos', group: 'Flutter'));
        }
        if (has('web')) {
          options.add(const RunOption(
              id: 'flutter:build-web', label: 'build web', command: 'flutter build web', group: 'Flutter'));
        }
      } else {
        kinds.add(ProjectKind.dart);
        options.addAll([
          RunOption(
              id: 'dart:run', label: 'run', command: 'dart run', group: 'Dart', primary: has('bin')),
          const RunOption(id: 'dart:test', label: 'test', command: 'dart test', group: 'Dart'),
          const RunOption(id: 'dart:pub-get', label: 'pub get', command: 'dart pub get', group: 'Dart'),
          const RunOption(id: 'dart:analyze', label: 'analyze', command: 'dart analyze', group: 'Dart'),
        ]);
      }
    }

    // ---------- Node ----------
    final packageJson = read('package.json');
    if (packageJson != null) {
      kinds.add(ProjectKind.node);
      Map<String, dynamic> pkg = {};
      try {
        pkg = (jsonDecode(packageJson) as Map).cast<String, dynamic>();
      } catch (_) {}

      final pm = (has('bun.lockb') || has('bun.lock'))
          ? 'bun'
          : has('pnpm-lock.yaml')
              ? 'pnpm'
              : has('yarn.lock')
                  ? 'yarn'
                  : 'npm';

      final deps = <String>{
        ...?(pkg['dependencies'] as Map?)?.keys.cast<String>(),
        ...?(pkg['devDependencies'] as Map?)?.keys.cast<String>(),
      };
      final framework = _nodeFramework(deps);
      if (framework != null) tags.add(framework);

      final scripts = (pkg['scripts'] as Map?)?.cast<String, dynamic>() ?? {};
      const priority = ['dev', 'start', 'serve', 'watch', 'preview', 'build', 'test', 'lint'];
      final names = scripts.keys.toList()
        ..sort((a, b) {
          final ia = priority.indexOf(a), ib = priority.indexOf(b);
          if (ia != -1 || ib != -1) {
            return (ia == -1 ? 999 : ia).compareTo(ib == -1 ? 999 : ib);
          }
          return a.compareTo(b);
        });
      final primaryScript = ['dev', 'start', 'serve'].where(scripts.containsKey).firstOrNull ??
          names.firstOrNull;

      for (final name in names) {
        options.add(RunOption(
          id: 'node:$name',
          label: name,
          command: _nodeScript(pm, name),
          group: 'Scripts',
          primary: name == primaryScript && !options.any((o) => o.primary),
        ));
      }
      options.add(RunOption(id: 'node:install', label: '$pm install', command: '$pm install', group: 'Scripts'));
    }

    // ---------- Rust ----------
    if (has('Cargo.toml')) {
      kinds.add(ProjectKind.rust);
      options.addAll([
        RunOption(
            id: 'cargo:run', label: 'run', command: 'cargo run', group: 'Cargo', primary: !options.any((o) => o.primary)),
        const RunOption(id: 'cargo:build', label: 'build --release', command: 'cargo build --release', group: 'Cargo'),
        const RunOption(id: 'cargo:test', label: 'test', command: 'cargo test', group: 'Cargo'),
        const RunOption(id: 'cargo:check', label: 'check', command: 'cargo check', group: 'Cargo'),
      ]);
    }

    // ---------- Go ----------
    if (has('go.mod')) {
      kinds.add(ProjectKind.go);
      options.addAll([
        RunOption(id: 'go:run', label: 'run .', command: 'go run .', group: 'Go', primary: !options.any((o) => o.primary)),
        const RunOption(id: 'go:build', label: 'build', command: 'go build ./...', group: 'Go'),
        const RunOption(id: 'go:test', label: 'test', command: 'go test ./...', group: 'Go'),
      ]);
    }

    // ---------- Python ----------
    final isPython = has('pyproject.toml') || has('requirements.txt') || has('manage.py') || has('main.py') || has('app.py');
    if (isPython) {
      kinds.add(ProjectKind.python);
      final venv = has('.venv/bin/activate')
          ? 'source .venv/bin/activate && '
          : has('venv/bin/activate')
              ? 'source venv/bin/activate && '
              : '';
      final py = <RunOption>[];
      if (has('manage.py')) {
        tags.add('Django');
        py.add(RunOption(id: 'py:django', label: 'runserver', command: '${venv}python3 manage.py runserver', group: 'Python'));
      }
      for (final entry in ['main.py', 'app.py']) {
        if (has(entry)) {
          py.add(RunOption(id: 'py:$entry', label: entry, command: '${venv}python3 $entry', group: 'Python'));
        }
      }
      if (has('requirements.txt')) {
        py.add(RunOption(
            id: 'py:install', label: 'pip install', command: '${venv}pip3 install -r requirements.txt', group: 'Python'));
      }
      if (has('tests') || has('pytest.ini')) {
        py.add(RunOption(id: 'py:test', label: 'pytest', command: '${venv}python3 -m pytest', group: 'Python'));
      }
      final needsPrimary = !options.any((o) => o.primary);
      for (var i = 0; i < py.length; i++) {
        final o = py[i];
        options.add(RunOption(
            id: o.id, label: o.label, command: o.command, group: o.group, primary: needsPrimary && i == 0));
      }
    }

    // ---------- Swift package ----------
    if (has('Package.swift')) {
      kinds.add(ProjectKind.swift);
      options.addAll([
        RunOption(id: 'swift:run', label: 'run', command: 'swift run', group: 'Swift', primary: !options.any((o) => o.primary)),
        const RunOption(id: 'swift:build', label: 'build', command: 'swift build', group: 'Swift'),
        const RunOption(id: 'swift:test', label: 'test', command: 'swift test', group: 'Swift'),
      ]);
    }

    // ---------- Docker compose ----------
    final compose = ['compose.yaml', 'compose.yml', 'docker-compose.yml', 'docker-compose.yaml'].where(has).firstOrNull;
    if (compose != null) {
      kinds.add(ProjectKind.docker);
      options.addAll([
        RunOption(
            id: 'docker:up', label: 'compose up', command: 'docker compose up', group: 'Docker', primary: !options.any((o) => o.primary)),
        const RunOption(id: 'docker:down', label: 'compose down', command: 'docker compose down', group: 'Docker'),
      ]);
    }

    // ---------- Makefile ----------
    final makefile = read('Makefile');
    if (makefile != null) {
      kinds.add(ProjectKind.make);
      final targets = <String>{};
      for (final m in RegExp(r'^([A-Za-z0-9][\w\-.]*)\s*:(?!=)', multiLine: true).allMatches(makefile)) {
        targets.add(m.group(1)!);
        if (targets.length >= 12) break;
      }
      var first = !options.any((o) => o.primary);
      for (final t in targets) {
        options.add(RunOption(id: 'make:$t', label: t, command: 'make $t', group: 'Make', primary: first));
        first = false;
      }
    }

    if (kinds.isEmpty) return ProjectInfo.empty.withOptions(options);

    final title = [
      kinds.map((k) => k.label).take(2).join(' + '),
      ...tags.take(1),
    ].join(' · ');
    return ProjectInfo(kind: kinds.first, title: title, options: options);
  }

  static String _nodeScript(String pm, String script) => switch (pm) {
        'yarn' => 'yarn $script',
        'pnpm' => 'pnpm run $script',
        'bun' => 'bun run $script',
        _ => 'npm run $script',
      };

  static String? _nodeFramework(Set<String> deps) {
    const known = <String, String>{
      'next': 'Next.js',
      'nuxt': 'Nuxt',
      '@remix-run/react': 'Remix',
      'astro': 'Astro',
      '@sveltejs/kit': 'SvelteKit',
      '@angular/core': 'Angular',
      'expo': 'Expo',
      'react-native': 'React Native',
      'electron': 'Electron',
      '@nestjs/core': 'NestJS',
      'vite': 'Vite',
      'svelte': 'Svelte',
      'vue': 'Vue',
      'react': 'React',
      'express': 'Express',
      'fastify': 'Fastify',
    };
    for (final entry in known.entries) {
      if (deps.contains(entry.key)) return entry.value;
    }
    return null;
  }
}

extension on ProjectInfo {
  ProjectInfo withOptions(List<RunOption> options) => ProjectInfo(kind: kind, title: title, options: options);
}
