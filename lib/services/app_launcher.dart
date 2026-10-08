import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project.dart';

enum AppCategory { editor, ide, terminal, git, finder }

class KnownApp {
  const KnownApp(this.name, this.bundleId, this.fileName, this.category, {this.kinds});

  final String name;
  final String bundleId;
  final String fileName;
  final AppCategory category;

  /// Only suggested for these project kinds (null = any project).
  final Set<ProjectKind>? kinds;
}

class InstalledApp {
  const InstalledApp(this.app, this.path);
  final KnownApp app;
  final String path;
  String get name => app.name;
}

/// Detects which editors / IDEs / terminals / git clients are installed and
/// opens projects in them.
class AppLauncher {
  static const _known = <KnownApp>[
    KnownApp('VS Code', 'com.microsoft.VSCode', 'Visual Studio Code.app', AppCategory.editor),
    KnownApp('Cursor', 'com.todesktop.230313mzl4w4u92', 'Cursor.app', AppCategory.editor),
    KnownApp('Windsurf', 'com.exafunction.windsurf', 'Windsurf.app', AppCategory.editor),
    KnownApp('Zed', 'dev.zed.Zed', 'Zed.app', AppCategory.editor),
    KnownApp('Sublime Text', 'com.sublimetext.4', 'Sublime Text.app', AppCategory.editor),
    KnownApp('Nova', 'com.panic.Nova', 'Nova.app', AppCategory.editor),
    KnownApp('Xcode', 'com.apple.dt.Xcode', 'Xcode.app', AppCategory.ide,
        kinds: {ProjectKind.flutter, ProjectKind.swift}),
    KnownApp('Android Studio', 'com.google.android.studio', 'Android Studio.app', AppCategory.ide,
        kinds: {ProjectKind.flutter, ProjectKind.dart}),
    KnownApp('IntelliJ IDEA', 'com.jetbrains.intellij', 'IntelliJ IDEA.app', AppCategory.ide),
    KnownApp('IntelliJ IDEA CE', 'com.jetbrains.intellij.ce', 'IntelliJ IDEA CE.app', AppCategory.ide),
    KnownApp('WebStorm', 'com.jetbrains.WebStorm', 'WebStorm.app', AppCategory.ide, kinds: {ProjectKind.node}),
    KnownApp('PyCharm', 'com.jetbrains.pycharm', 'PyCharm.app', AppCategory.ide, kinds: {ProjectKind.python}),
    KnownApp('PyCharm CE', 'com.jetbrains.pycharm.ce', 'PyCharm CE.app', AppCategory.ide,
        kinds: {ProjectKind.python}),
    KnownApp('GoLand', 'com.jetbrains.goland', 'GoLand.app', AppCategory.ide, kinds: {ProjectKind.go}),
    KnownApp('RustRover', 'com.jetbrains.rustrover', 'RustRover.app', AppCategory.ide, kinds: {ProjectKind.rust}),
    KnownApp('Terminal', 'com.apple.Terminal', 'Terminal.app', AppCategory.terminal),
    KnownApp('iTerm', 'com.googlecode.iterm2', 'iTerm.app', AppCategory.terminal),
    KnownApp('Warp', 'dev.warp.Warp-Stable', 'Warp.app', AppCategory.terminal),
    KnownApp('Ghostty', 'com.mitchellh.ghostty', 'Ghostty.app', AppCategory.terminal),
    KnownApp('GitHub Desktop', 'com.github.GitHubClient', 'GitHub Desktop.app', AppCategory.git),
    KnownApp('Fork', 'com.DanPristupov.Fork', 'Fork.app', AppCategory.git),
    KnownApp('Tower', 'com.fournova.Tower3', 'Tower.app', AppCategory.git),
    KnownApp('Sourcetree', 'com.torusknot.SourceTreeNotMAS', 'Sourcetree.app', AppCategory.git),
  ];

  static List<InstalledApp>? _installed;
  static Future<List<InstalledApp>>? _loading;

  static List<InstalledApp> get installed => _installed ?? const [];

  static Future<List<InstalledApp>> load() {
    if (_installed != null) return Future.value(_installed);
    return _loading ??= _detect();
  }

  static Future<List<InstalledApp>> _detect() async {
    final home = Platform.environment['HOME'] ?? '';
    final dirs = [
      '/Applications',
      '$home/Applications',
      '/System/Applications/Utilities',
      '/Applications/Utilities',
      '$home/Applications/JetBrains Toolbox',
      '/Applications/Setapp',
    ];
    final found = await Future.wait(_known.map((app) async {
      for (final dir in dirs) {
        final path = p.join(dir, app.fileName);
        if (Directory(path).existsSync()) return InstalledApp(app, path);
      }
      // Fallback: ask Spotlight by bundle id (apps installed elsewhere).
      try {
        final r = await Process.run('/usr/bin/mdfind', ['kMDItemCFBundleIdentifier == "${app.bundleId}"'])
            .timeout(const Duration(seconds: 5));
        final hit = (r.stdout as String).split('\n').map((l) => l.trim()).where((l) => l.endsWith('.app')).firstOrNull;
        if (hit != null) return InstalledApp(app, hit);
      } catch (_) {}
      return null;
    }));
    _installed = found.whereType<InstalledApp>().toList();
    return _installed!;
  }

  /// Installed apps that make sense for this project, most relevant first.
  static List<InstalledApp> appsFor(Project project) {
    final kind = project.info.kind;
    final isRepo = Directory(p.join(project.path, '.git')).existsSync();
    bool fits(InstalledApp a) {
      if (a.app.category == AppCategory.git && !isRepo) return false;
      final kinds = a.app.kinds;
      return kinds == null || kinds.contains(kind);
    }

    const order = [AppCategory.editor, AppCategory.ide, AppCategory.terminal, AppCategory.git];
    final list = installed.where(fits).toList()
      ..sort((a, b) => order.indexOf(a.app.category).compareTo(order.indexOf(b.app.category)));
    return list;
  }

  static Future<void> open(InstalledApp app, Project project) async {
    var target = project.path;
    if (app.app.bundleId == 'com.apple.dt.Xcode') {
      for (final candidate in [
        'macos/Runner.xcworkspace',
        'ios/Runner.xcworkspace',
        'Package.swift',
      ]) {
        final full = p.join(project.path, candidate);
        if (FileSystemEntity.typeSync(full) != FileSystemEntityType.notFound) {
          target = full;
          break;
        }
      }
    }
    try {
      await Process.run('/usr/bin/open', ['-a', app.path, target]);
    } catch (_) {}
  }
}
