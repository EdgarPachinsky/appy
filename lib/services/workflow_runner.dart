import 'dart:async';

import '../models/workflow.dart';
import 'run_session.dart';

enum StepStatus { pending, running, done, failed }

/// Progress of one run of a workflow, keyed by step id (so editing the
/// workflow mid-run doesn't shuffle the statuses).
class WorkflowRun {
  final Map<String, StepStatus> status = {};
  final Map<String, RunSession> sessions = {};
  bool active = true;
  bool cancelled = false;

  /// Stop was pressed: stopping the steps, then running the shutdown steps.
  bool stopping = false;

  /// Completes when the start steps are over (done, failed or stopped).
  final Completer<void> finished = Completer();
  String? error;

  StepStatus statusOf(WorkflowStep step) => status[step.id] ?? StepStatus.pending;
  int get doneCount => status.values.where((s) => s == StepStatus.done).length;
}

/// Completes with true once [session] got to what [step] waits for, false if
/// it failed or was stopped first.
Future<bool> waitForStep(RunSession session, WorkflowStep step) async {
  bool? finished() => switch (session.status) {
        RunStatus.failed => false,
        RunStatus.exited => session.exitCode == 0,
        _ => null,
      };

  switch (step.waitFor) {
    case WaitFor.none:
      return finished() ?? true;
    case WaitFor.delay:
      await Future<void>.delayed(Duration(seconds: step.delaySeconds));
      return finished() ?? true;
    case WaitFor.exit:
    case WaitFor.ready:
      final done = Completer<bool>();
      void check() {
        if (done.isCompleted) return;
        final result = finished() ?? (step.waitFor == WaitFor.ready && session.ready ? true : null);
        if (result != null) done.complete(result);
      }

      session.addListener(check);
      check();
      return done.future.whenComplete(() => session.removeListener(check));
  }
}
