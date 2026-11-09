import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import '../models/workflow.dart';
import '../services/app_launcher.dart';
import '../services/detector.dart';
import '../services/git_status.dart';
import '../services/helpers.dart';
import '../services/hotkeys.dart';
import '../services/native_bridge.dart';
import '../services/port_scanner.dart';
import '../services/resource_monitor.dart';
import '../services/run_session.dart';
import '../services/shell_env.dart';
import '../services/workflow_runner.dart';

/// All projects and all run sessions. Notifies on structural / status changes
/// (not on every log line — listen to a [RunSession] for that).
class AppState extends ChangeNotifier {
  static const _prefsKey = 'appy.projects.v1';
  static const _showPortsKey = 'appy.showPorts';
  static const _workflowsKey = 'appy.workflows.v1';
  static const _notificationsKey = 'appy.notifications';

  final List<Project> projects = [];
  final Map<String, RunSession> sessions = {};

  /// Git branch / status per project id (missing = not a git repo).
  final Map<String, GitInfo> git = {};

  final List<Workflow> workflows = [];

  /// Latest run of each workflow, by workflow id.
  final Map<String, WorkflowRun> workflowRuns = {};

  /// Where workflow commands that don't belong to a project run.
  final Project homeProject = Project(id: 'home', path: Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/', name: 'Home');

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
    final rawWorkflows = _prefs!.getString(_workflowsKey);
    if (rawWorkflows != null) {
      try {
        for (final item in jsonDecode(rawWorkflows) as List) {
          workflows.add(Workflow.fromJson((item as Map).cast<String, dynamic>()));
        }
      } catch (_) {}
    }
    for (final project in projects) {
      project.info = await ProjectDetector.detect(project.path);
    }
    notifyListeners();
    syncHotkeys();

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

  // ----------------------------------------------------------- notifications

  bool get notificationsOn => _prefs?.getBool(_notificationsKey) ?? true;

  set notificationsOn(bool value) {
    _prefs?.setBool(_notificationsKey, value);
    notifyListeners();
  }

  void _notify(String title, String body, {bool sound = false}) {
    if (notificationsOn) NativeBridge.notify(title, body, sound: sound);
  }

  /// "css-front · " — empty for commands run in the home folder.
  String _where(RunSession s) => s.project.id == homeProject.id ? '' : '${s.project.name} · ';

  void _notifyReady(RunSession s) => _notify('▶ ${s.option.label} is running', '${_where(s)}${s.url ?? 'ready'}');

  void _notifyFinished(RunSession s) {
    if (s.stoppedByUser) return;
    if (s.status == RunStatus.failed) {
      final reason = s.portInUse != null ? 'port ${s.portInUse} is in use' : 'exit code ${s.exitCode}';
      _notify('✗ ${s.option.label} failed', '${_where(s)}$reason', sound: true);
    } else {
      _notify('✓ ${s.option.label} done', '${_where(s)}finished');
    }
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

  List<RunSession> sessionsOf(Project project) => sessions.values.where((s) => s.project.id == project.id).toList();

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
    var wasReady = false;
    session.onStateChanged = () {
      notifyListeners();
      if (wasActive && !session.isActive) {
        // A command finished (build, pub get, checkout…) → git state may have changed.
        refreshGit(project);
        _notifyFinished(session);
      } else if (!wasReady && session.ready && session.isActive) {
        _notifyReady(session);
      }
      wasActive = session.isActive;
      wasReady = session.ready;
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

  /// Something else holds [session]'s port: kill it and run the command again.
  Future<void> freePortAndRetry(RunSession session) async {
    final port = session.portInUse;
    if (port == null) return;
    final pids = (await PortScanner.scan()).where((x) => x.port == port).map((x) => x.pid).toSet();
    await session.stop(); // e.g. nodemon stays alive after the crash
    await killProcesses(pids);
    await run(session.project, session.option);
  }

  Future<void> stopAll() async {
    await Future.wait(activeSessions.map((s) => s.stop()));
  }

  // --------------------------------------------------------------- workflows

  Workflow addWorkflow(String name) {
    final workflow = Workflow(id: DateTime.now().microsecondsSinceEpoch.toRadixString(36), name: name.trim());
    workflows.add(workflow);
    workflowChanged();
    return workflow;
  }

  Future<void> removeWorkflow(Workflow workflow) async {
    if (isWorkflowLive(workflow)) await stopWorkflow(workflow);
    workflows.remove(workflow);
    workflowRuns.remove(workflow.id);
    workflowChanged();
  }

  /// Call after editing a workflow in place (name, steps, waits, shortcut).
  void workflowChanged() {
    _prefs?.setString(_workflowsKey, jsonEncode(workflows.map((w) => w.toJson()).toList()));
    syncHotkeys();
    notifyListeners();
  }

  /// Registers every workflow's start / stop shortcut system-wide.
  void syncHotkeys() => Hotkeys.sync(workflows, onStart: startShortcut, onStop: stopWorkflow);

  bool isWorkflowRunning(Workflow workflow) => workflowRuns[workflow.id]?.active ?? false;

  /// The run is going, or a command of its steps is still running.
  bool isWorkflowLive(Workflow workflow, [Set<String>? seen]) {
    if (isWorkflowRunning(workflow)) return true;
    final inner = {...?seen, workflow.id}; // a saved loop must not recurse forever
    return workflow.steps.any((step) {
      final id = step.workflowId;
      if (id == null) return _activeSession(step) != null;
      final child = workflowById(id);
      return child != null && !inner.contains(id) && isWorkflowLive(child, inner);
    });
  }

  Workflow? workflowById(String id) => workflows.where((w) => w.id == id).firstOrNull;

  /// Whether [outer] runs [inner], directly or through nested workflows.
  bool workflowContains(Workflow outer, Workflow inner, [Set<String>? seen]) {
    final visited = seen ?? {};
    if (!visited.add(outer.id)) return false;
    for (final step in [...outer.steps, ...outer.shutdownSteps]) {
      final child = step.workflowId == null ? null : workflowById(step.workflowId!);
      if (child == null) continue;
      if (child == inner || workflowContains(child, inner, visited)) return true;
    }
    return false;
  }

  /// [child] can be a step of [parent] without making a loop.
  bool canNest(Workflow parent, Workflow child) => child != parent && !workflowContains(child, parent);

  RunSession? _activeSession(WorkflowStep step) {
    final target = resolveStep(step);
    final session = target == null ? null : sessionFor(target.$1, target.$2);
    return session != null && session.isActive ? session : null;
  }

  /// The project and command a step runs, or null if its project was removed.
  (Project, RunOption)? resolveStep(WorkflowStep step) {
    final project = step.projectId == homeProject.id ? homeProject : projectById(step.projectId);
    if (project == null) return null;
    final option = (step.optionId == null ? null : project.optionById(step.optionId!)) ??
        RunOption(
          id: 'custom:${step.command}',
          label: step.label,
          command: step.command,
          group: 'Custom',
          isFlutterRun: step.command.startsWith('flutter run') && step.command.contains('--machine'),
        );
    return (project, option);
  }

  /// Runs the steps in order; stops at the first one that fails. True if
  /// all steps got there. Already running → waits for that run instead.
  /// [chain] = the workflows this one runs inside (nested workflow steps).
  Future<bool> runWorkflow(Workflow workflow, {Set<String> chain = const {}}) async {
    final current = workflowRuns[workflow.id];
    if (current != null && current.active) {
      await current.finished.future;
      return current.error == null;
    }
    if (current?.stopping ?? false) return false;
    if (workflow.steps.isEmpty) return true;
    final run = workflowRuns[workflow.id] = WorkflowRun();
    final inner = {...chain, workflow.id};
    notifyListeners();
    for (final step in List.of(workflow.steps)) {
      if (run.cancelled) break;
      if (!await _runStep(run, step, chain: inner)) {
        run.error ??= run.cancelled ? 'Stopped' : '"${_stepName(step)}" failed';
        break;
      }
    }
    run.active = false;
    run.finished.complete();
    notifyListeners();
    if (chain.isEmpty) {
      // Nested workflows report through the outer one.
      if (run.error == null) {
        _notify('✓ ${workflow.name}', 'All ${workflow.steps.length} steps done', sound: true);
      } else if (!run.cancelled) {
        _notify('✗ ${workflow.name} stopped', run.error!, sound: true);
      }
    }
    return run.error == null;
  }

  /// Shuts the workflow down, like Ctrl+C on each of its commands: stops the
  /// run and every running command of its steps, then the workflows it
  /// contains (with their "On stop" steps), then runs its own shutdown steps
  /// (all of them, even if one fails).
  Future<void> stopWorkflow(Workflow workflow, {Set<String> chain = const {}}) async {
    final run = workflowRuns[workflow.id] ??= WorkflowRun()
      ..active = false
      ..finished.complete();
    if (run.stopping) return;
    run
      ..cancelled = true
      ..stopping = true;
    notifyListeners();
    final inner = {...chain, workflow.id};
    final running = workflow.steps.map(_activeSession).whereType<RunSession>().toSet();
    await Future.wait(running.map((s) => s.stop()));
    for (final step in workflow.steps) {
      final child = step.workflowId == null ? null : workflowById(step.workflowId!);
      if (child != null && !inner.contains(child.id)) await stopWorkflow(child, chain: inner);
    }
    final failed = <String>[];
    for (final step in List.of(workflow.shutdownSteps)) {
      if (!await _runStep(run, step, shutdown: true, chain: inner)) failed.add(_stepName(step));
    }
    run.stopping = false;
    notifyListeners();
    if (chain.isNotEmpty) return;
    _notify(
      '■ ${workflow.name} shut down',
      failed.isEmpty
          ? 'Stopped ${running.length} command${running.length == 1 ? '' : 's'}'
          : 'Failed: ${failed.join(', ')}',
      sound: failed.isNotEmpty,
    );
  }

  /// A step's display name; nested workflows show their current name.
  String _stepName(WorkflowStep step) =>
      step.workflowId == null ? step.label : (workflowById(step.workflowId!)?.name ?? step.label);

  /// The workflow's start shortcut: starts it, or — when it has no stop
  /// shortcut of its own — shuts it down if it's live.
  void startShortcut(Workflow workflow) =>
      workflow.stopHotkey == null && isWorkflowLive(workflow) ? stopWorkflow(workflow) : runWorkflow(workflow);

  /// Runs one step and waits for it as configured; true if it got there.
  Future<bool> _runStep(WorkflowRun run, WorkflowStep step,
      {bool shutdown = false, Set<String> chain = const {}}) async {
    if (step.workflowId case final id?) return _runNested(run, step, id, shutdown: shutdown, chain: chain);
    final target = resolveStep(step);
    if (target == null) {
      run.status[step.id] = StepStatus.failed;
      run.error = 'The project of "${step.label}" was removed';
      notifyListeners();
      return false;
    }
    run.status[step.id] = StepStatus.running;
    notifyListeners();
    // A server Appy runs gets stopped through its session and awaited, so a
    // later step starts it fresh instead of finding it "running" mid-death.
    if (killPortTarget(step.command) case final port?) {
      final pids = (await PortScanner.scan()).where((x) => x.port == port).map((x) => x.pid).toSet();
      await killProcesses(pids);
    }
    final session = run.sessions[step.id] = await this.run(target.$1, target.$2);
    if (run.cancelled && !shutdown) {
      // Stop was pressed while this was starting, after the shutdown looked.
      await session.stop();
      run.status[step.id] = StepStatus.failed;
      notifyListeners();
      return false;
    }
    notifyListeners();
    final ok = await waitForStep(session, step);
    run.status[step.id] = ok ? StepStatus.done : StepStatus.failed;
    notifyListeners();
    return ok;
  }

  /// A step that runs a whole other workflow, waiting for it as configured.
  Future<bool> _runNested(WorkflowRun run, WorkflowStep step, String id,
      {required bool shutdown, required Set<String> chain}) async {
    final child = workflowById(id);
    String? problem;
    if (child == null) problem = 'The workflow "${step.label}" was removed';
    if (child != null && chain.contains(id)) problem = '"${child.name}" would run inside itself';
    if (problem != null) {
      run.status[step.id] = StepStatus.failed;
      run.error = problem;
      notifyListeners();
      return false;
    }
    run.status[step.id] = StepStatus.running;
    notifyListeners();
    final childRun = runWorkflow(child!, chain: chain);
    var ok = switch (step.waitFor) {
      WaitFor.none => true,
      WaitFor.delay => await Future.delayed(Duration(seconds: step.delaySeconds), () => true),
      WaitFor.exit || WaitFor.ready => await childRun,
    };
    // Stop pressed meanwhile: the shutdown stops the child too.
    if (run.cancelled && !shutdown) ok = false;
    final childError = workflowRuns[id]?.error;
    if (!ok && childError != null && run.error == null && !run.cancelled) {
      run.error = '${child.name}: $childError';
    }
    run.status[step.id] = ok ? StepStatus.done : StepStatus.failed;
    notifyListeners();
    return ok;
  }

  void _save() {
    _prefs?.setString(_prefsKey, jsonEncode(projects.map((x) => x.toJson()).toList()));
  }
}
