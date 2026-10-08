import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import '../services/app_launcher.dart';
import '../services/detector.dart';
import '../services/git_status.dart';
import '../services/port_scanner.dart';
import '../services/resource_monitor.dart';
import '../services/run_session.dart';
import '../services/shell_env.dart';

/// All projects and all run sessions. Notifies on structural / status changes
/// (not on every log line — listen to a [RunSession] for that).
class AppState extends ChangeNotifier {
  static const _prefsKey = 'appy.projects.v1';
  static const _showPortsKey = 'appy.showPorts';

  final List<Project> projects = [];
  final Map<String, RunSession> sessions = {};

  /// Git branch / status per project id (missing = not a git repo).
  final Map<String, GitInfo> git = {};

  SharedPreferences? _prefs;
  Timer? _gitTimer;
  Timer? _statsTimer;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw != null) {
      try {
        for (final item in jsonDecode(raw) as List) {
          projects.add(Project.fromJson((item as Map).cast<String, dynamic>()));
        }
      } catch (_) {}
    }
    for (final project in projects) {
      project.info = await ProjectDetector.detect(project.path);
    }
    notifyListeners();

    // Background work: shell env → git status; installed editors; live stats.
    ShellEnv.load().then((_) => refreshGit());
    AppLauncher.load().then((_) => notifyListeners());
    _gitTimer = Timer.periodic(const Duration(seconds: 30), (_) => refreshGit());
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sampleStats());
  }

  @override
  void dispose() {
    _gitTimer?.cancel();
    _statsTimer?.cancel();
    super.dispose();
  }

  // --------------------------------------------------------------- git / stats

  GitInfo? gitFor(Project project) => git[project.id];

  // ------------------------------------------------------------------- ports

  bool get showPorts => _prefs?.getBool(_showPortsKey) ?? true;

  set showPorts(bool value) {
    _prefs?.setBool(_showPortsKey, value);
    notifyListeners();
  }

  /// The project whose folder contains [dir] (deepest match wins).
  Project? projectForPath(String? dir) {
    if (dir == null) return null;
    Project? best;
    for (final x in projects) {
      if (dir == x.path || dir.startsWith('${x.path}/')) {
        if (best == null || x.path.length > best.path.length) best = x;
      }
    }
    return best;
  }

  /// Kills processes (e.g. the ones holding a port). Commands Appy started are
  /// stopped through their session so their cards update; others get SIGTERM,
  /// then SIGKILL if still alive.
  Future<void> killProcesses(Set<int> pids) async {
    final parents = await PortScanner.parents();
    final sessionsToStop = <RunSession>{};
    final others = <int>{};
    for (final pid in pids) {
      final session = _sessionOwning(pid, parents);
      if (session != null) {
        sessionsToStop.add(session);
      } else {
        others.add(pid);
      }
    }
    for (final pid in others) {
      Process.killPid(pid, ProcessSignal.sigterm);
    }
    await Future.wait(sessionsToStop.map((s) => s.stop()));
    if (others.isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    for (final pid in others) {
      if (PortScanner.isAlive(pid)) Process.killPid(pid, ProcessSignal.sigkill);
    }
  }

  RunSession? _sessionOwning(int pid, Map<int, int> parents) {
    final roots = {
      for (final s in activeSessions)
        if (s.pid != null) s.pid!: s,
    };
    var current = pid;
    final seen = <int>{};
    while (seen.add(current)) {
      final session = roots[current];
      if (session != null) return session;
      final parent = parents[current];
      if (parent == null || parent <= 1) return null;
      current = parent;
    }
    return null;
  }

  Future<void> refreshGit([Project? only]) async {
    final env = await ShellEnv.load();
    var changed = false;
    for (final project in only == null ? List.of(projects) : [only]) {
      final info = await GitStatus.read(project.path, env);
      if (info == null) {
        changed |= git.remove(project.id) != null;
      } else if (git[project.id] != info) {
        git[project.id] = info;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> _sampleStats() async {
    final running = activeSessions.where((s) => s.pid != null).toList();
    if (running.isEmpty) return;
    final stats = await ResourceMonitor.sample(running.map((s) => s.pid!));
    for (final s in running) {
      if (s.isActive) s.stats.value = stats[s.pid];
    }
  }

  // ---------------------------------------------------------------- projects

  /// Pinned first, then in the order they were added.
  List<Project> get orderedProjects => [
        ...projects.where((x) => x.pinned),
        ...projects.where((x) => !x.pinned),
      ];

  List<Project> get pinnedProjects => projects.where((x) => x.pinned).toList();

  Project? projectById(String id) => projects.where((x) => x.id == id).firstOrNull;

  Future<Project> addFolder(String path) async {
    final normalized = p.normalize(path);
    final existing = projects.where((x) => x.path == normalized).firstOrNull;
    if (existing != null) return existing;
    final project = Project(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      path: normalized,
      name: p.basename(normalized),
    );
    project.info = await ProjectDetector.detect(normalized);
    projects.add(project);
    _save();
    notifyListeners();
    refreshGit(project);
    return project;
  }

  Future<void> removeProject(Project project) async {
    for (final s in sessionsOf(project)) {
      await s.stop();
      sessions.remove(s.key);
    }
    projects.remove(project);
    _save();
    notifyListeners();
  }

  void rename(Project project, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    project.name = trimmed;
    _save();
    notifyListeners();
  }

  /// Sorted list of every tag in use.
  List<String> get allTags => {for (final x in projects) ...x.tags}.toList()..sort();

  void setTags(Project project, List<String> tags) {
    final clean = <String>[];
    for (final t in tags) {
      final tag = t.trim().replaceAll('#', '');
      if (tag.isNotEmpty && !clean.contains(tag)) clean.add(tag);
    }
    project.tags
      ..clear()
      ..addAll(clean);
    _save();
    notifyListeners();
  }

  /// Drag-to-reorder: put [draggedId] where [targetId] is.
  void moveProject(String draggedId, String targetId) {
    final from = projects.indexWhere((x) => x.id == draggedId);
    final to = projects.indexWhere((x) => x.id == targetId);
    if (from == -1 || to == -1 || from == to) return;
    final project = projects.removeAt(from);
    projects.insert(to, project);
    _save();
    notifyListeners();
  }

  void togglePin(Project project) {
    project.pinned = !project.pinned;
    _save();
    notifyListeners();
  }

  Future<void> rescan(Project project) async {
    project.info = await ProjectDetector.detect(project.path);
    notifyListeners();
    refreshGit(project);
  }

  void addCustomCommand(Project project, String command) {
    final cmd = command.trim();
    if (cmd.isEmpty || project.customCommands.contains(cmd)) return;
    project.customCommands.add(cmd);
    _save();
    notifyListeners();
  }

  void removeCustomCommand(Project project, String command) {
    project.customCommands.remove(command);
    _save();
    notifyListeners();
  }

  bool folderExists(Project project) => Directory(project.path).existsSync();

  // ---------------------------------------------------------------- sessions

  RunSession? sessionFor(Project project, RunOption option) => sessions[sessionKey(project.id, option.id)];

  List<RunSession> sessionsOf(Project project) =>
      sessions.values.where((s) => s.project.id == project.id).toList();

  List<RunSession> get activeSessions => sessions.values.where((s) => s.isActive).toList();

  bool isRunning(Project project) => sessionsOf(project).any((s) => s.isActive);

  Future<RunSession> run(Project project, RunOption option) async {
    final key = sessionKey(project.id, option.id);
    final session = sessions[key] ??= _newSession(project, option);
    if (session.isActive) return session;
    notifyListeners();
    final env = await ShellEnv.load();
    await session.start(env);
    return session;
  }

  RunSession _newSession(Project project, RunOption option) {
    final session = RunSession(project: project, option: option);
    var wasActive = false;
    session.onStateChanged = () {
      notifyListeners();
      // A command finished (build, pub get, checkout…) → git state may have changed.
      if (wasActive && !session.isActive) refreshGit(project);
      wasActive = session.isActive;
    };
    return session;
  }

  Future<void> stop(RunSession session) => session.stop();

  /// Stop + start again (flutter: full rebuild).
  Future<void> rebuild(RunSession session) async {
    await session.stop();
    final env = await ShellEnv.load();
    await session.start(env);
  }

  void dismiss(RunSession session) {
    if (session.isActive) return;
    sessions.remove(session.key);
    session.dispose();
    notifyListeners();
  }

  Future<void> stopAll() async {
    await Future.wait(activeSessions.map((s) => s.stop()));
  }

  void _save() {
    _prefs?.setString(_prefsKey, jsonEncode(projects.map((x) => x.toJson()).toList()));
  }
}
