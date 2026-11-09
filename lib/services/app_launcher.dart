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
    KnownApp('PyCharm CE', 'com.jetbrains.pycharm.ce', 'PyCharm CE.app', AppCategory.ide, kinds: {ProjectKind.python}),
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

  /// Windows: where each app usually installs (`%VAR%` expanded) and the
  /// arguments that go before the project folder.
  static const _knownWindows = <({KnownApp app, List<String> paths, List<String> args})>[
    (
      app: KnownApp('VS Code', '', 'Code.exe', AppCategory.editor),
      paths: [r'%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe', r'%ProgramFiles%\Microsoft VS Code\Code.exe'],
      args: [],
    ),
    (
      app: KnownApp('Cursor', '', 'Cursor.exe', AppCategory.editor),
      paths: [r'%LOCALAPPDATA%\Programs\cursor\Cursor.exe'],
      args: []
    ),
    (
      app: KnownApp('Windsurf', '', 'Windsurf.exe', AppCategory.editor),
      paths: [r'%LOCALAPPDATA%\Programs\Windsurf\Windsurf.exe'],
      args: []
    ),
    (
      app: KnownApp('Zed', '', 'Zed.exe', AppCategory.editor),
      paths: [r'%LOCALAPPDATA%\Programs\Zed\Zed.exe'],
      args: []
    ),
    (
      app: KnownApp('Sublime Text', '', 'sublime_text.exe', AppCategory.editor),
      paths: [r'%ProgramFiles%\Sublime Text\sublime_text.exe'],
      args: [],
    ),
    (
      app: KnownApp('Android Studio', '', 'studio64.exe', AppCategory.ide,
          kinds: {ProjectKind.flutter, ProjectKind.dart}),
      paths: [r'%ProgramFiles%\Android\Android Studio\bin\studio64.exe'],
      args: [],
    ),
    // shortcut: JetBrains Toolbox 2.x locations only; versioned %ProgramFiles%\JetBrains\* installs aren't found.
    (
      app: KnownApp('IntelliJ IDEA', '', 'idea64.exe', AppCategory.ide),
      paths: [r'%LOCALAPPDATA%\Programs\IntelliJ IDEA Ultimate\bin\idea64.exe'],
      args: [],
    ),
    (
      app: KnownApp('IntelliJ IDEA CE', '', 'idea64.exe', AppCategory.ide),
      paths: [r'%LOCALAPPDATA%\Programs\IntelliJ IDEA Community Edition\bin\idea64.exe'],
      args: [],
    ),
    (
      app: KnownApp('WebStorm', '', 'webstorm64.exe', AppCategory.ide, kinds: {ProjectKind.node}),
      paths: [r'%LOCALAPPDATA%\Programs\WebStorm\bin\webstorm64.exe'],
      args: [],
    ),
    (
      app: KnownApp('PyCharm', '', 'pycharm64.exe', AppCategory.ide, kinds: {ProjectKind.python}),
      paths: [
        r'%LOCALAPPDATA%\Programs\PyCharm Professional\bin\pycharm64.exe',
        r'%LOCALAPPDATA%\Programs\PyCharm\bin\pycharm64.exe'
      ],
      args: [],
    ),
    (
      app: KnownApp('GoLand', '', 'goland64.exe', AppCategory.ide, kinds: {ProjectKind.go}),
      paths: [r'%LOCALAPPDATA%\Programs\GoLand\bin\goland64.exe'],
      args: [],
    ),
    (
      app: KnownApp('RustRover', '', 'rustrover64.exe', AppCategory.ide, kinds: {ProjectKind.rust}),
      paths: [r'%LOCALAPPDATA%\Programs\RustRover\bin\rustrover64.exe'],
      args: [],
    ),
    (
      app: KnownApp('Windows Terminal', '', 'wt.exe', AppCategory.terminal),
      paths: [r'%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe'],
      args: ['-d'],
    ),
    (
      app: KnownApp('GitHub Desktop', '', 'GitHubDesktop.exe', AppCategory.git),
      paths: [r'%LOCALAPPDATA%\GitHubDesktop\GitHubDesktop.exe'],
      args: ['--cli-open'],
    ),
    (app: KnownApp('Fork', '', 'Fork.exe', AppCategory.git), paths: [r'%LOCALAPPDATA%\Fork\Fork.exe'], args: []),
    (
      app: KnownApp('Sourcetree', '', 'SourceTree.exe', AppCategory.git),
      paths: [r'%LOCALAPPDATA%\SourceTree\SourceTree.exe'],
      args: ['-f'],
    ),
  ];

  static String _expand(String path) =>
      path.replaceAllMapped(RegExp(r'%(\w+)%'), (m) => Platform.environment[m.group(1)!] ?? m.group(0)!);

  static List<InstalledApp>? _installed;
  static Future<List<InstalledApp>>? _loading;

  static List<InstalledApp> get installed => _installed ?? const [];

  static Future<List<InstalledApp>> load() {
    if (_installed != null) return Future.value(_installed);
    return _loading ??= _detect();
  }

  /// Every app in the usual folders (and one level of subfolders, e.g.
  /// JetBrains Toolbox), plus Xcode's Simulator — sorted by name.
  static Future<List<({String name, String path})>> allApps() async {
    final home = Platform.environment['HOME'] ?? '';
    final roots = ['/Applications', '$home/Applications', '/System/Applications'];
    final apps = <String, String>{}; // path → name
    void scan(String dir, {required bool deeper}) {
      try {
        for (final entry in Directory(dir).listSync(followLinks: false)) {
          if (entry is! Directory) continue;
          if (entry.path.endsWith('.app')) {
            apps[entry.path] = p.basenameWithoutExtension(entry.path);
          } else if (deeper) {
            scan(entry.path, deeper: false);
          }
        }
      } catch (_) {} // missing or unreadable folder
    }

    for (final root in roots) {
      scan(root, deeper: true);
    }
    const simulator = '/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app';
    if (Directory(simulator).existsSync()) apps[simulator] = 'Simulator';
    final list = [for (final e in apps.entries) (name: e.value, path: e.key)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// The app's bundle id (e.g. com.apple.iphonesimulator), or null.
  static Future<String?> bundleId(String appPath) async {
    try {
      final r = await Process.run('/usr/bin/plutil',
          ['-extract', 'CFBundleIdentifier', 'raw', '-o', '-', p.join(appPath, 'Contents', 'Info.plist')]);
      final id = (r.stdout as String).trim();
      return r.exitCode == 0 && id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<InstalledApp>> _detect() async {
    if (Platform.isWindows) {
      return _installed = [
        for (final k in _knownWindows)
          // followLinks: false — wt.exe is an app alias that only exists as a link.
          if (k.paths
                  .map(_expand)
                  .where((p) => FileSystemEntity.typeSync(p, followLinks: false) != FileSystemEntityType.notFound)
                  .firstOrNull
              case final path?)
            InstalledApp(k.app, path),
      ];
    }
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
      if (Platform.isWindows) {
        final args = _knownWindows.firstWhere((k) => k.app.name == app.name).args;
        await Process.start(app.path, [...args, target], mode: ProcessStartMode.detached);
      } else {
        await Process.run('/usr/bin/open', ['-a', app.path, target]);
      }
    } catch (_) {}
  }
}
