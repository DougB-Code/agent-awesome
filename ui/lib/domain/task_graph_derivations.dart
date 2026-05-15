/// Derives query-ready task insight labels from graph facts.
library;

import 'task_graph_facts.dart';

/// TaskGraphDerivedStatus describes computed task health from node and edge facts.
enum TaskGraphDerivedStatus {
  /// Task has a completion timestamp.
  completed,

  /// Task has a cancellation timestamp.
  canceled,

  /// Task has one or more blocker edges.
  blocked,

  /// Task is past its due timestamp.
  overdue,

  /// Task is scheduled after its due timestamp.
  slipping,

  /// Task is scheduled for now or has no future schedule.
  ready,

  /// Task is scheduled in the future.
  scheduled,

  /// Task has no schedule or due date.
  unscheduled,
}

/// TaskGraphTimeWindow groups tasks by date without storing time labels.
enum TaskGraphTimeWindow {
  /// Target time is before today.
  past,

  /// Target time has arrived today.
  now,

  /// Target time is later today.
  today,

  /// Target time is within the next seven days.
  thisWeek,

  /// Target time is within the following seven days.
  nextWeek,

  /// Target time is beyond two weeks.
  later,

  /// No schedule or deadline exists.
  unscheduled,
}

/// TaskGraphAttentionTarget explains where attention should go next.
enum TaskGraphAttentionTarget {
  /// Remove an explicit blocker edge first.
  clearBlocker,

  /// Protect slipping or overdue work.
  deadlineRisk,

  /// Review spend before committing more resources.
  spendReview,

  /// Capture upside from high earn or save potential.
  highReturn,

  /// Work is available to do now.
  readyNow,

  /// Maintain or defer without special attention.
  maintain,
}

/// TaskGraphDerivedState stores derived task labels for projections.
class TaskGraphDerivedState {
  /// Creates one derived state record.
  const TaskGraphDerivedState({
    required this.status,
    required this.timeWindow,
    required this.attentionTarget,
    this.blockerIds = const <String>[],
  });

  /// Computed task status.
  final TaskGraphDerivedStatus status;

  /// Computed time window.
  final TaskGraphTimeWindow timeWindow;

  /// Computed attention target.
  final TaskGraphAttentionTarget attentionTarget;

  /// Direct blocker task ids derived from graph edges.
  final List<String> blockerIds;
}

/// TaskGraphDeriver computes qualitative labels from quantifiable graph facts.
class TaskGraphDeriver {
  const TaskGraphDeriver._();

  /// Returns all direct blockers for a task id.
  static List<String> blockerIdsFor(TaskGraphSnapshot graph, String taskId) {
    final blockers = <String>{};
    for (final edge in graph.edges) {
      if (edge.kind == TaskGraphEdgeKind.blocks && edge.toTaskId == taskId) {
        blockers.add(edge.fromTaskId);
      }
      if (edge.kind == TaskGraphEdgeKind.dependsOn &&
          edge.fromTaskId == taskId) {
        blockers.add(edge.toTaskId);
      }
    }
    return blockers.toList()..sort();
  }

  /// Returns all tasks directly blocked by a task id.
  static List<String> blockedTaskIdsFor(
    TaskGraphSnapshot graph,
    String taskId,
  ) {
    final blocked = <String>{};
    for (final edge in graph.edges) {
      if (edge.kind == TaskGraphEdgeKind.blocks && edge.fromTaskId == taskId) {
        blocked.add(edge.toTaskId);
      }
      if (edge.kind == TaskGraphEdgeKind.dependsOn && edge.toTaskId == taskId) {
        blocked.add(edge.fromTaskId);
      }
    }
    return blocked.toList()..sort();
  }

  /// Returns the full derived state for one task node.
  static TaskGraphDerivedState stateFor({
    required TaskGraphSnapshot graph,
    required TaskGraphNode node,
    required DateTime now,
  }) {
    final blockerIds = blockerIdsFor(graph, node.id);
    final status = _statusFor(node, blockerIds, now);
    final timeWindow = _timeWindowFor(node, now);
    return TaskGraphDerivedState(
      status: status,
      timeWindow: timeWindow,
      attentionTarget: _attentionTargetFor(node, status, timeWindow),
      blockerIds: blockerIds,
    );
  }

  /// Returns a computed status for one task.
  static TaskGraphDerivedStatus _statusFor(
    TaskGraphNode node,
    List<String> blockerIds,
    DateTime now,
  ) {
    if (node.completedAt != null) {
      return TaskGraphDerivedStatus.completed;
    }
    if (node.canceledAt != null) {
      return TaskGraphDerivedStatus.canceled;
    }
    if (blockerIds.isNotEmpty) {
      return TaskGraphDerivedStatus.blocked;
    }
    final dueAt = node.dueAt;
    if (dueAt != null && dueAt.isBefore(now)) {
      return TaskGraphDerivedStatus.overdue;
    }
    final scheduledAt = node.scheduledAt;
    if (dueAt != null && scheduledAt != null && scheduledAt.isAfter(dueAt)) {
      return TaskGraphDerivedStatus.slipping;
    }
    if (scheduledAt != null && scheduledAt.isAfter(now)) {
      return TaskGraphDerivedStatus.scheduled;
    }
    if (scheduledAt != null || dueAt != null) {
      return TaskGraphDerivedStatus.ready;
    }
    return TaskGraphDerivedStatus.unscheduled;
  }

  /// Returns a rolling time window for schedule or due dates.
  static TaskGraphTimeWindow _timeWindowFor(TaskGraphNode node, DateTime now) {
    final target = node.scheduledAt ?? node.dueAt;
    if (target == null) {
      return TaskGraphTimeWindow.unscheduled;
    }
    final today = _startOfDay(now);
    if (target.isBefore(today)) {
      return TaskGraphTimeWindow.past;
    }
    if (!target.isAfter(now)) {
      return TaskGraphTimeWindow.now;
    }
    if (target.isBefore(today.add(const Duration(days: 1)))) {
      return TaskGraphTimeWindow.today;
    }
    if (target.isBefore(today.add(const Duration(days: 7)))) {
      return TaskGraphTimeWindow.thisWeek;
    }
    if (target.isBefore(today.add(const Duration(days: 14)))) {
      return TaskGraphTimeWindow.nextWeek;
    }
    return TaskGraphTimeWindow.later;
  }

  /// Returns where attention should go for one derived state.
  static TaskGraphAttentionTarget _attentionTargetFor(
    TaskGraphNode node,
    TaskGraphDerivedStatus status,
    TaskGraphTimeWindow timeWindow,
  ) {
    if (status == TaskGraphDerivedStatus.blocked) {
      return TaskGraphAttentionTarget.clearBlocker;
    }
    if (status == TaskGraphDerivedStatus.overdue ||
        status == TaskGraphDerivedStatus.slipping) {
      return TaskGraphAttentionTarget.deadlineRisk;
    }
    if (node.spendCents > 0 && node.earnCents + node.saveCents <= 0) {
      return TaskGraphAttentionTarget.spendReview;
    }
    if (node.netReturnCents > 0 && _highPriority(node.priority)) {
      return TaskGraphAttentionTarget.highReturn;
    }
    if (timeWindow == TaskGraphTimeWindow.now) {
      return TaskGraphAttentionTarget.readyNow;
    }
    return TaskGraphAttentionTarget.maintain;
  }

  /// Reports whether a task priority should boost attention.
  static bool _highPriority(String priority) {
    final normalized = priority.trim().toLowerCase();
    return normalized == 'urgent' || normalized == 'high';
  }

  /// Returns midnight for a timestamp.
  static DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
