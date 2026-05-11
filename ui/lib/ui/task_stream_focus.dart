/// Focus-selection model for task stream highlighting.
part of 'task_stream_canvas.dart';

/// TaskStreamFocus describes the currently emphasized route, row, or task.
class TaskStreamFocus {
  /// Creates a task stream focus target.
  const TaskStreamFocus({
    this.taskId = '',
    this.streamId = '',
    this.rowId = '',
    this.taskIds = const <String>{},
    this.streamIds = const <String>{},
    this.rowIds = const <String>{},
  });

  /// Creates focus around one card and its immediate graph neighborhood.
  factory TaskStreamFocus.card(TaskStreamCard card) {
    return TaskStreamFocus(taskId: card.taskId);
  }

  /// Creates focus around one link and its route.
  factory TaskStreamFocus.link(TaskStreamLink link) {
    return TaskStreamFocus(
      taskId: link.streamId.isEmpty ? link.fromTaskId : '',
      streamId: link.streamId,
    );
  }

  /// Focused task id.
  final String taskId;

  /// Focused stream route id.
  final String streamId;

  /// Focused row id.
  final String rowId;

  /// Additional focused task ids.
  final Set<String> taskIds;

  /// Additional focused stream route ids.
  final Set<String> streamIds;

  /// Additional focused row ids.
  final Set<String> rowIds;

  /// Whether this focus has no target.
  bool get isEmpty {
    return taskId.isEmpty &&
        streamId.isEmpty &&
        rowId.isEmpty &&
        taskIds.isEmpty &&
        streamIds.isEmpty &&
        rowIds.isEmpty;
  }

  /// Returns whether a task id is directly selected.
  bool hasTaskId(String id) {
    return id.isNotEmpty && (taskId == id || taskIds.contains(id));
  }

  /// Returns whether a stream route id is directly selected.
  bool hasStreamId(String id) {
    return id.isNotEmpty && (streamId == id || streamIds.contains(id));
  }

  /// Returns whether a row id is directly selected.
  bool hasRowId(String id) {
    return id.isNotEmpty && (rowId == id || rowIds.contains(id));
  }

  /// Returns a new focus with the provided target toggled in this focus set.
  TaskStreamFocus toggled(TaskStreamFocus target) {
    final nextTaskIds = effectiveTaskIds();
    final nextStreamIds = effectiveStreamIds();
    final nextRowIds = effectiveRowIds();
    _toggleIds(nextTaskIds, target.effectiveTaskIds());
    _toggleIds(nextStreamIds, target.effectiveStreamIds());
    _toggleIds(nextRowIds, target.effectiveRowIds());
    return TaskStreamFocus(
      taskIds: nextTaskIds,
      streamIds: nextStreamIds,
      rowIds: nextRowIds,
    );
  }

  /// Returns all focused task ids, including the primary single-value field.
  Set<String> effectiveTaskIds() {
    return <String>{...taskIds, if (taskId.isNotEmpty) taskId};
  }

  /// Returns all focused stream ids, including the primary single-value field.
  Set<String> effectiveStreamIds() {
    return <String>{...streamIds, if (streamId.isNotEmpty) streamId};
  }

  /// Returns all focused row ids, including the primary single-value field.
  Set<String> effectiveRowIds() {
    return <String>{...rowIds, if (rowId.isNotEmpty) rowId};
  }

  /// Compares focus values.
  @override
  bool operator ==(Object other) {
    return other is TaskStreamFocus &&
        other.taskId == taskId &&
        other.streamId == streamId &&
        other.rowId == rowId &&
        _stringSetsEqual(other.taskIds, taskIds) &&
        _stringSetsEqual(other.streamIds, streamIds) &&
        _stringSetsEqual(other.rowIds, rowIds);
  }

  /// Hashes focus values.
  @override
  int get hashCode {
    return Object.hash(
      taskId,
      streamId,
      rowId,
      Object.hashAllUnordered(taskIds),
      Object.hashAllUnordered(streamIds),
      Object.hashAllUnordered(rowIds),
    );
  }
}

/// Toggles all requested ids inside a mutable id set.
void _toggleIds(Set<String> selected, Set<String> requested) {
  for (final id in requested) {
    if (!selected.remove(id)) {
      selected.add(id);
    }
  }
}

/// Returns whether two string sets contain identical values.
bool _stringSetsEqual(Set<String> left, Set<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final value in left) {
    if (!right.contains(value)) {
      return false;
    }
  }
  return true;
}
