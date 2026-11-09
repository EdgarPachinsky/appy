import '../services/helpers.dart';

/// When a workflow moves on from a step to the next one.
enum WaitFor { exit, ready, delay, none }

extension WaitForLabel on WaitFor {
  String get label => switch (this) {
        WaitFor.exit => 'Wait to finish',
        WaitFor.ready => 'Wait until ready',
        WaitFor.delay => 'Wait a few seconds',
        WaitFor.none => "Don't wait",
      };
}

/// One command of a workflow: a project's run option, or any command run in
/// a project's folder ([optionId] == null).
class WorkflowStep {
  WorkflowStep({
    String? id,
    required this.projectId,
    this.optionId,
    required this.label,
    required this.command,
    WaitFor? waitFor,
    this.delaySeconds = 5,
    this.workflowId,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        waitFor = waitFor ?? defaultWaitFor(command);

  /// A step that runs another whole workflow.
  WorkflowStep.workflow(Workflow workflow)
      : this(projectId: '', workflowId: workflow.id, label: workflow.name, command: '', waitFor: WaitFor.exit);

  final String id;

  /// Runs this workflow instead of a command (then [projectId] and [command] are empty).
  final String? workflowId;
  final String projectId;
  final String? optionId;
  final String label;

  /// Kept so the step still runs if re-detecting the project drops the option.
  final String command;
  WaitFor waitFor;
  int delaySeconds;

  // The lookbehind keeps paths like /dev/null from counting as `dev`.
  static final _longRunning = RegExp(r'flutter run|(?<![\w/.-])(dev|start|serve|watch|preview|runserver|up)\b');

  /// Dev servers never exit, so wait for them to be ready; everything else to finish.
  static WaitFor defaultWaitFor(String command) =>
      _longRunning.hasMatch(command) ? WaitFor.ready : WaitFor.exit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'optionId': optionId,
        'label': label,
        'command': command,
        'waitFor': waitFor.name,
        'delaySeconds': delaySeconds,
        if (workflowId != null) 'workflowId': workflowId,
      };

  factory WorkflowStep.fromJson(Map<String, dynamic> json) => WorkflowStep(
        id: json['id'] as String?,
        projectId: json['projectId'] as String,
        optionId: json['optionId'] as String?,
        label: json['label'] as String,
        command: upgradeSavedCommand(json['command'] as String),
        waitFor: WaitFor.values.where((w) => w.name == json['waitFor']).firstOrNull,
        delaySeconds: json['delaySeconds'] as int? ?? 5,
        workflowId: json['workflowId'] as String?,
      );
}

/// A named list of commands from any projects, run in order.
class Workflow {
  Workflow({
    required this.id,
    required this.name,
    List<WorkflowStep>? steps,
    List<WorkflowStep>? shutdownSteps,
    this.hotkey,
    this.stopHotkey,
  })  : steps = steps ?? [],
        shutdownSteps = shutdownSteps ?? [];

  final String id;
  String name;
  final List<WorkflowStep> steps;

  /// Run after Stop has stopped the steps, e.g. `docker compose down`.
  final List<WorkflowStep> shutdownSteps;

  /// Global shortcuts, as `HotKey.toJson()` from hotkey_manager. Without a
  /// [stopHotkey], [hotkey] toggles: start, or shut down when running.
  Map<String, dynamic>? hotkey;
  Map<String, dynamic>? stopHotkey;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'steps': steps.map((s) => s.toJson()).toList(),
        'shutdownSteps': shutdownSteps.map((s) => s.toJson()).toList(),
        'hotkey': hotkey,
        'stopHotkey': stopHotkey,
      };

  factory Workflow.fromJson(Map<String, dynamic> json) => Workflow(
        id: json['id'] as String,
        name: json['name'] as String,
        steps: [
          for (final s in (json['steps'] as List? ?? const []))
            WorkflowStep.fromJson((s as Map).cast<String, dynamic>()),
        ],
        shutdownSteps: [
          for (final s in (json['shutdownSteps'] as List? ?? const []))
            WorkflowStep.fromJson((s as Map).cast<String, dynamic>()),
        ],
        hotkey: (json['hotkey'] as Map?)?.cast<String, dynamic>(),
        stopHotkey: (json['stopHotkey'] as Map?)?.cast<String, dynamic>(),
      );
}
