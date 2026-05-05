/// Normalizes task score inputs for insight queries.
library;

import 'models.dart';

/// TaskInsightScoreProfile stores query-ready normalized scores for a task.
class TaskInsightScoreProfile {
  /// Creates one insight score profile.
  const TaskInsightScoreProfile({
    required this.taskId,
    this.reward = 0,
    this.pressure = 0,
    this.risk = 0,
    this.timePressure = 0,
    this.humanEffort = 0,
    this.agentFit = 0,
    this.obligation = 0,
    this.consequence = 0,
    this.agentSafety = 0,
    this.handoffReadiness = 0,
    this.contextReadiness = 0,
    this.humanJudgmentNeed = 0,
    this.downstreamValue = 0,
    this.blockerEffort = 0,
    this.unblockLeverage = 0,
    this.metadataCompleteness = 0,
    this.commitmentHardness = 0,
    this.confidence = 0,
  });

  /// Canonical task id.
  final String taskId;

  /// Reward or upside.
  final double reward;

  /// Combined pressure.
  final double pressure;

  /// Failure or delay risk.
  final double risk;

  /// Deadline pressure.
  final double timePressure;

  /// Human attention cost.
  final double humanEffort;

  /// Agent capability fit.
  final double agentFit;

  /// Must-do obligation.
  final double obligation;

  /// Consequence severity.
  final double consequence;

  /// Agent safety.
  final double agentSafety;

  /// Handoff readiness.
  final double handoffReadiness;

  /// Context readiness.
  final double contextReadiness;

  /// Human judgment need.
  final double humanJudgmentNeed;

  /// Downstream value unlocked by this task.
  final double downstreamValue;

  /// Blocker effort cost.
  final double blockerEffort;

  /// Unblock value per unit effort.
  final double unblockLeverage;

  /// Metadata completeness.
  final double metadataCompleteness;

  /// Commitment hardness.
  final double commitmentHardness;

  /// Metadata confidence.
  final double confidence;

  /// Builds a profile from canonical graph and workspace task facts.
  factory TaskInsightScoreProfile.fromTask({
    required String taskId,
    WorkspaceTask? workspaceTask,
    TaskProjectionTask? projectionTask,
    double downstreamValue = 0,
    double unblockLeverage = 0,
    double commitmentHardness = 0,
  }) {
    final scores = projectionTask?.scores ?? const TaskProjectionScores();
    final confidence = _scoreOr(
      projectionTask?.confidence ?? 0,
      workspaceTask?.confidence ?? 0,
      fallback: 0.55,
    );
    final effort = _scoreOr(
      scores.humanEffort,
      workspaceTask?.effort ?? 0,
      fallback: _effortFromEstimate(workspaceTask?.estimateMinutes ?? 0),
    );
    final reward = _scoreOr(
      scores.reward,
      workspaceTask?.value ?? 0,
      fallback: _priorityReward(
        workspaceTask?.priority ?? projectionTask?.priority ?? '',
      ),
    );
    final timePressure = _scoreOr(
      scores.timePressure,
      workspaceTask?.urgency ?? 0,
      fallback: _timePressure(workspaceTask?.dueAt ?? projectionTask?.dueAt),
    );
    final pressure = _scoreOr(
      scores.pressure,
      workspaceTask?.urgency ?? 0,
      fallback: timePressure,
    );
    final risk = _scoreOr(scores.risk, workspaceTask?.risk ?? 0, fallback: 0.2);
    final agentFit = _scoreOr(
      scores.agentFit,
      0,
      fallback: _agentFitFallback(workspaceTask, projectionTask),
    );
    final obligation = _scoreOr(
      scores.obligation,
      0,
      fallback: _obligationFallback(workspaceTask, projectionTask),
    );
    final consequence = _scoreOr(
      scores.consequenceSeverity,
      0,
      fallback: _consequenceFallback(workspaceTask, projectionTask),
    );
    final agentSafety = _scoreOr(
      scores.agentSafety,
      0,
      fallback: _agentSafetyFallback(workspaceTask, projectionTask, risk),
    );
    final contextReadiness = _scoreOr(
      scores.contextReadiness,
      0,
      fallback: _contextReadinessFallback(workspaceTask, projectionTask),
    );
    final handoffReadiness = _scoreOr(
      scores.handoffReadiness,
      0,
      fallback: _min3(agentFit, agentSafety, contextReadiness),
    );
    final metadataCompleteness = _scoreOr(
      scores.metadataCompleteness,
      0,
      fallback: _metadataCompletenessFallback(workspaceTask, projectionTask),
    );
    return TaskInsightScoreProfile(
      taskId: taskId,
      reward: reward,
      pressure: pressure,
      risk: risk,
      timePressure: timePressure,
      humanEffort: effort,
      agentFit: agentFit,
      obligation: obligation,
      consequence: consequence,
      agentSafety: agentSafety,
      handoffReadiness: handoffReadiness,
      contextReadiness: contextReadiness,
      humanJudgmentNeed: _scoreOr(
        scores.humanJudgmentNeed,
        risk,
        fallback: risk,
      ),
      downstreamValue: _scoreOr(scores.downstreamValue, downstreamValue),
      blockerEffort: _scoreOr(scores.blockerEffort, effort),
      unblockLeverage: _scoreOr(scores.unblockLeverage, unblockLeverage),
      metadataCompleteness: metadataCompleteness,
      commitmentHardness: _scoreOr(
        scores.commitmentHardness,
        commitmentHardness,
      ),
      confidence: confidence,
    );
  }
}

/// Returns a clamped first non-zero score with a fallback.
double _scoreOr(double primary, double secondary, {double fallback = 0}) {
  if (primary > 0) {
    return _clamp01(primary);
  }
  if (secondary > 0) {
    return _clamp01(secondary);
  }
  return _clamp01(fallback);
}

/// Converts an estimate into a broad human-effort score.
double _effortFromEstimate(int minutes) {
  if (minutes <= 0) {
    return 0.30;
  }
  return _clamp01(minutes / 180);
}

/// Gives high priorities a conservative reward fallback.
double _priorityReward(String priority) {
  return switch (priority) {
    'urgent' => 0.78,
    'high' => 0.68,
    'normal' => 0.42,
    'low' => 0.22,
    _ => 0.35,
  };
}

/// Computes deadline pressure using the local clock.
double _timePressure(DateTime? dueAt) {
  if (dueAt == null) {
    return 0.05;
  }
  final now = DateTime.now();
  final days = dueAt.difference(now).inHours / 24;
  if (days < 0) {
    return 1.0;
  }
  if (days < 1) {
    return 0.90;
  }
  if (days < 2) {
    return 0.75;
  }
  if (days < 7) {
    return 0.55;
  }
  if (days < 14) {
    return 0.35;
  }
  return 0.15;
}

/// Derives agent fit from task shape when no backend score exists.
double _agentFitFallback(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? task,
) {
  final text = _taskText(workspaceTask, task);
  var score = 0.35;
  if (text.contains('draft') || text.contains('summarize')) {
    score += 0.22;
  }
  if (text.contains('review') || text.contains('compare')) {
    score += 0.16;
  }
  final context = (workspaceTask?.context ?? task?.context ?? '').toLowerCase();
  if (context.contains('admin') || context.contains('research')) {
    score += 0.16;
  }
  if ((workspaceTask?.description ?? task?.description ?? '').isNotEmpty) {
    score += 0.10;
  }
  return _clamp01(score);
}

/// Derives obligation from status, priority, and controlled metadata.
double _obligationFallback(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? task,
) {
  final value = (task?.obligationLevel ?? '').toLowerCase();
  if (value.contains('legal') || value.contains('must')) {
    return 0.92;
  }
  if (value.contains('client') || value.contains('committed')) {
    return 0.78;
  }
  if (value.contains('should')) {
    return 0.55;
  }
  final priority = workspaceTask?.priority ?? task?.priority ?? '';
  if (priority == 'urgent') {
    return 0.78;
  }
  if (priority == 'high') {
    return 0.62;
  }
  return 0.35;
}

/// Derives consequence from controlled metadata and topic/domain hints.
double _consequenceFallback(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? task,
) {
  final value = (task?.consequenceSeverity ?? '').toLowerCase();
  if (value.contains('critical')) {
    return 1.0;
  }
  if (value.contains('high')) {
    return 0.78;
  }
  if (value.contains('medium')) {
    return 0.55;
  }
  final text = _taskText(workspaceTask, task);
  if (_containsSensitiveValue(text)) {
    return 0.62;
  }
  return 0.28;
}

/// Derives safety and defaults sensitive domains to review.
double _agentSafetyFallback(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? task,
  double risk,
) {
  final safety = (task?.agentSafety ?? '').toLowerCase();
  if (safety == 'safe') {
    return 0.85;
  }
  if (safety == 'unsafe') {
    return 0.12;
  }
  if (safety == 'needs_review') {
    return 0.58;
  }
  final text = _taskText(workspaceTask, task);
  if (_containsSensitiveValue(text)) {
    return 0.52;
  }
  return _clamp01(0.78 - risk * 0.36);
}

/// Derives context readiness from description, estimate, and memory links.
double _contextReadinessFallback(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? task,
) {
  var score = 0.25;
  if ((workspaceTask?.description ?? task?.description ?? '').trim().length >
      12) {
    score += 0.30;
  }
  if ((workspaceTask?.estimateMinutes ?? task?.estimateMinutes ?? 0) > 0) {
    score += 0.15;
  }
  if ((workspaceTask?.memoryLinks ?? const <TaskMemoryLink>[]).isNotEmpty ||
      (task?.evidenceIds ?? const <String>[]).isNotEmpty) {
    score += 0.20;
  }
  if ((workspaceTask?.context ?? task?.context ?? '').trim().isNotEmpty) {
    score += 0.10;
  }
  return _clamp01(score);
}

/// Derives metadata completeness from the fields the current UI knows.
double _metadataCompletenessFallback(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? task,
) {
  final checks = <bool>[
    (workspaceTask?.status ?? task?.status ?? '').isNotEmpty,
    (workspaceTask?.priority ?? task?.priority ?? '').isNotEmpty,
    workspaceTask?.dueAt != null || task?.dueAt != null,
    (workspaceTask?.estimateMinutes ?? task?.estimateMinutes ?? 0) > 0,
    (workspaceTask?.context ?? task?.context ?? '').isNotEmpty,
    (workspaceTask?.domain ?? task?.domain ?? '').isNotEmpty,
    (workspaceTask?.owner ?? task?.owner ?? '').isNotEmpty,
    (task?.valueType ?? '').isNotEmpty,
    (task?.obligationLevel ?? '').isNotEmpty,
    (task?.agentSafety ?? '').isNotEmpty,
  ];
  final present = checks.where((check) => check).length;
  return present / checks.length;
}

/// Returns the minimum of three normalized values.
double _min3(double first, double second, double third) {
  return _clamp01([first, second, third].reduce((a, b) => a < b ? a : b));
}

/// Returns title, description, domain, context, and topics as lowercase text.
String _taskText(WorkspaceTask? workspaceTask, TaskProjectionTask? task) {
  return <String>[
    workspaceTask?.title ?? task?.title ?? '',
    workspaceTask?.description ?? task?.description ?? '',
    workspaceTask?.domain ?? task?.domain ?? '',
    workspaceTask?.context ?? task?.context ?? '',
    ...(workspaceTask?.topics ?? task?.topics ?? const <String>[]),
  ].join(' ').toLowerCase();
}

/// Returns true when text suggests sensitive or approval-heavy work.
bool _containsSensitiveValue(String text) {
  return text.contains('legal') ||
      text.contains('lawyer') ||
      text.contains('finance') ||
      text.contains('invoice') ||
      text.contains('payment') ||
      text.contains('medical') ||
      text.contains('client') ||
      text.contains('employment');
}

/// Clamps a score into the 0-1 range.
double _clamp01(num value) {
  return value.clamp(0, 1).toDouble();
}
