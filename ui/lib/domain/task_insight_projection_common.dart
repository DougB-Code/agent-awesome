/// Shared indexed-task projection helpers.
part of 'task_projection_adapters.dart';

List<String> _activeTaskIds(TaskInsightIndex index) {
  final taskIds = <String>{
    ...index.workspaceTasksById.keys,
    ...index.projectionTasksById.keys,
  }.where(index.isActiveTask).toList();
  taskIds.sort((left, right) {
    return index.titleForTaskId(left).compareTo(index.titleForTaskId(right));
  });
  return taskIds;
}

/// Returns the stream lane id for one task.
String _laneIdFor(TaskInsightIndex index, String taskId) {
  final facet = index.facetLabelForTask(taskId, 'time').toLowerCase();
  if (facet.contains('now') ||
      facet.contains('today') ||
      facet.contains('overdue')) {
    return 'now';
  }
  if (facet.contains('next') || facet.contains('tomorrow')) {
    return 'next';
  }
  final window = _dueWindow(_dueAtFor(index, taskId), DateTime.now());
  return switch (window) {
    'overdue' || 'today' => 'now',
    'tomorrow' => 'next',
    'this-week' => 'later',
    _ => 'upcoming',
  };
}

/// Returns a task status from queue or projection facts.
String _statusFor(TaskInsightIndex index, String taskId) {
  return _firstNonEmpty(<String>[
    index.workspaceTasksById[taskId]?.status ?? '',
    index.projectionTasksById[taskId]?.status ?? '',
    'open',
  ]);
}

/// Returns a task priority from queue or projection facts.
String _priorityFor(TaskInsightIndex index, String taskId) {
  return _firstNonEmpty(<String>[
    index.workspaceTasksById[taskId]?.priority ?? '',
    index.projectionTasksById[taskId]?.priority ?? '',
    'normal',
  ]);
}

/// Returns a task due date from queue or projection facts.
DateTime? _dueAtFor(TaskInsightIndex index, String taskId) {
  return index.workspaceTasksById[taskId]?.dueAt ??
      index.projectionTasksById[taskId]?.dueAt;
}

/// Returns a task scheduled date from queue or projection facts.
DateTime? _scheduledAtFor(TaskInsightIndex index, String taskId) {
  return index.workspaceTasksById[taskId]?.scheduledAt ??
      index.projectionTasksById[taskId]?.scheduledAt;
}

/// Returns the best owner label for an indexed task.
String _ownerForIndexedTask(TaskInsightIndex index, String taskId) {
  return _firstNonEmpty(<String>[
    index.facetLabelForTask(taskId, 'person'),
    index.workspaceTasksById[taskId]?.owner ?? '',
    index.projectionTasksById[taskId]?.owner ?? '',
    'Unassigned',
  ]);
}

/// Returns the best project label for an indexed task.
String _projectForIndexedTask(TaskInsightIndex index, String taskId) {
  final workspaceTask = index.workspaceTasksById[taskId];
  final projectionTask = index.projectionTasksById[taskId];
  return _firstNonEmpty(<String>[
    workspaceTask?.project ?? '',
    projectionTask?.project ?? '',
    projectionTask?.projectId ?? '',
    workspaceTask?.sourceLabel ?? '',
    index.facetLabelForTask(taskId, 'project'),
    'No project',
  ]);
}

/// Returns the best insight-aware next action for one task.
String _indexNextBestAction(TaskInsightIndex index, String taskId) {
  final plan = index.unblockPlanFor(taskId);
  if (plan.hasExplicitBlocker || _statusFor(index, taskId) == 'blocked') {
    return plan.smallestNextAction;
  }
  final candidate = index.candidateForTask(taskId, TaskInsightIds.agentHandoff);
  if (candidate != null && candidate.severity != 'warning') {
    return 'Prepare an agent handoff brief.';
  }
  final projectionTask = index.projectionTasksById[taskId];
  if (projectionTask != null) {
    return _nextBestAction(projectionTask);
  }
  final workspaceTask = index.workspaceTasksById[taskId];
  if (workspaceTask != null && workspaceTask.description.isNotEmpty) {
    return 'Open the task notes and continue.';
  }
  return 'Start with the task title as the next action.';
}

/// Returns the most specific insight id for explaining one task.
String _primaryInsightId(TaskInsightIndex index, String taskId) {
  for (final insightId in const <String>[
    TaskInsightIds.quickUnblocks,
    TaskInsightIds.agentHandoff,
    TaskInsightIds.nextWeekHighValue,
    TaskInsightIds.highRiskLowConfidence,
  ]) {
    if (index.candidateForTask(taskId, insightId) != null) {
      return insightId;
    }
  }
  return TaskInsightIds.all;
}
