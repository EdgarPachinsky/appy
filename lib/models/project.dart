/// What kind of project a folder is. Detected from files in the folder.
enum ProjectKind { flutter, dart, node, rust, go, python, swift, docker, make, unknown }

extension ProjectKindLabel on ProjectKind {
  String get label => switch (this) {
        ProjectKind.flutter => 'Flutter',
        ProjectKind.dart => 'Dart',
        ProjectKind.node => 'Node',
        ProjectKind.rust => 'Rust',
        ProjectKind.go => 'Go',
        ProjectKind.python => 'Python',
        ProjectKind.swift => 'Swift',
        ProjectKind.docker => 'Docker',
        ProjectKind.make => 'Make',
        ProjectKind.unknown => 'Folder',
      };
}

/// One thing Appy can run inside a project, e.g. `npm run dev`.
class RunOption {
  const RunOption({
    required this.id,
    required this.label,
    required this.command,
    this.group = 'Run',
    this.isFlutterRun = false,
    this.primary = false,
  });

  final String id;
  final String label;
  final String command;
  final String group;

  /// `flutter run --machine …` — supports hot reload / restart / quit.
  final bool isFlutterRun;

  /// The default action shown on the project card.
  final bool primary;
}

/// Result of scanning a project folder.
class ProjectInfo {
  const ProjectInfo({
    required this.kind,
    required this.title,
    this.options = const [],
  });

  final ProjectKind kind;

  /// Human label, e.g. "Flutter" or "Node · Vite".
  final String title;
  final List<RunOption> options;

  static const empty = ProjectInfo(kind: ProjectKind.unknown, title: 'Folder');
}

class Project {
  Project({
    required this.id,
    required this.path,
    required this.name,
    this.pinned = false,
    List<String>? customCommands,
    List<String>? tags,
    this.info = ProjectInfo.empty,
  })  : customCommands = customCommands ?? [],
        tags = tags ?? [];

  final String id;
  final String path;
  String name;
  bool pinned;
  final List<String> customCommands;

  /// User tags, used as groups / filters on the home screen.
  final List<String> tags;
  ProjectInfo info;

  List<RunOption> get allOptions => [
        ...info.options,
        for (final cmd in customCommands)
          RunOption(
            id: 'custom:$cmd',
            label: cmd,
            command: cmd,
            group: 'Custom',
            isFlutterRun: cmd.startsWith('flutter run') && cmd.contains('--machine'),
          ),
      ];

  RunOption? get primaryOption {
    final all = allOptions;
    if (all.isEmpty) return null;
    return all.where((o) => o.primary).firstOrNull ?? all.first;
  }

  RunOption? optionById(String id) => allOptions.where((o) => o.id == id).firstOrNull;

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'name': name,
        'pinned': pinned,
        'customCommands': customCommands,
        'tags': tags,
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        path: json['path'] as String,
        name: json['name'] as String,
        pinned: json['pinned'] as bool? ?? false,
        customCommands: (json['customCommands'] as List?)?.cast<String>().toList(),
        tags: (json['tags'] as List?)?.cast<String>().toList(),
      );
}
