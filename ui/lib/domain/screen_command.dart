/// Defines structured AI screen-command plans and reviewable changes.
library;

import 'dart:convert';

import 'json_value.dart';

/// ScreenCommandIntent identifies the planner's top-level decision.
enum ScreenCommandIntent {
  /// The user asked for changes to the current screen.
  change,

  /// The user asked an informational question about the current screen.
  question,

  /// The planner needs more user detail before changes are safe.
  clarification,
}

/// ScreenChangeOperation identifies one supported screen mutation.
enum ScreenChangeOperation {
  /// Create a graph-backed backlog task.
  createTask,

  /// Update mutable fields on one graph-backed task.
  updateTask,

  /// Mark one graph-backed task complete.
  completeTask,

  /// Mark one graph-backed task canceled.
  cancelTask,

  /// Delete one graph-backed task.
  deleteTask,

  /// Create or update a task relation.
  upsertTaskRelation,

  /// Delete a task relation.
  deleteTaskRelation,

  /// Link memory to a task.
  linkTaskMemory,
}

/// ScreenChangeStatus stores the review lifecycle for one change.
enum ScreenChangeStatus {
  /// The change is valid and awaiting user review.
  proposed,

  /// The change was applied to the backing service.
  applied,

  /// The change was rejected by validation or the user.
  rejected,

  /// The change failed while applying or undoing.
  failed,

  /// The applied change was undone.
  undone,
}

/// ScreenChangeSafety describes how the UI should treat one change.
enum ScreenChangeSafety {
  /// The app may apply this change without additional review.
  autoApply,

  /// The user must review this change before persistence.
  needsReview,

  /// The app must not apply this change.
  rejected,
}

/// ScreenChangeTarget points a proposed change at a UI or data object.
class ScreenChangeTarget {
  /// Creates a screen-change target.
  const ScreenChangeTarget({this.taskId = '', this.taskTitle = ''});

  /// Canonical task id, when the planner supplied or validation resolved it.
  final String taskId;

  /// Human-readable task title used for display or title-only resolution.
  final String taskTitle;

  /// Returns a copy with selected target fields changed.
  ScreenChangeTarget copyWith({String? taskId, String? taskTitle}) {
    return ScreenChangeTarget(
      taskId: taskId ?? this.taskId,
      taskTitle: taskTitle ?? this.taskTitle,
    );
  }
}

/// ScreenChange stores one reviewable mutation returned by the planner.
class ScreenChange {
  /// Creates a reviewable screen change.
  const ScreenChange({
    required this.id,
    required this.operation,
    required this.target,
    required this.summary,
    this.reason = '',
    this.confidence = 0,
    this.fields = const <String, dynamic>{},
    this.beforeValues = const <String, dynamic>{},
    this.afterValues = const <String, dynamic>{},
    this.status = ScreenChangeStatus.proposed,
    this.safety = ScreenChangeSafety.needsReview,
    this.error = '',
  });

  /// Stable in-memory change id.
  final String id;

  /// Mutation operation.
  final ScreenChangeOperation operation;

  /// UI or graph object changed by the operation.
  final ScreenChangeTarget target;

  /// Short user-facing change summary.
  final String summary;

  /// Planner explanation for why the change fits the command.
  final String reason;

  /// Planner confidence from 0 to 1.
  final double confidence;

  /// Operation-specific field payload.
  final Map<String, dynamic> fields;

  /// Captured values before applying the change.
  final Map<String, dynamic> beforeValues;

  /// Intended values after applying the change.
  final Map<String, dynamic> afterValues;

  /// Review or persistence status.
  final ScreenChangeStatus status;

  /// Safety classification chosen by app validation.
  final ScreenChangeSafety safety;

  /// Validation or persistence error.
  final String error;

  /// Returns a copy with selected fields changed.
  ScreenChange copyWith({
    String? id,
    ScreenChangeOperation? operation,
    ScreenChangeTarget? target,
    String? summary,
    String? reason,
    double? confidence,
    Map<String, dynamic>? fields,
    Map<String, dynamic>? beforeValues,
    Map<String, dynamic>? afterValues,
    ScreenChangeStatus? status,
    ScreenChangeSafety? safety,
    String? error,
  }) {
    return ScreenChange(
      id: id ?? this.id,
      operation: operation ?? this.operation,
      target: target ?? this.target,
      summary: summary ?? this.summary,
      reason: reason ?? this.reason,
      confidence: confidence ?? this.confidence,
      fields: fields ?? this.fields,
      beforeValues: beforeValues ?? this.beforeValues,
      afterValues: afterValues ?? this.afterValues,
      status: status ?? this.status,
      safety: safety ?? this.safety,
      error: error ?? this.error,
    );
  }
}

/// ScreenCommandRun stores one planner response and app validation result.
class ScreenCommandRun {
  /// Creates a structured screen-command run.
  const ScreenCommandRun({
    required this.id,
    required this.command,
    required this.intent,
    this.message = '',
    this.confidence = 0,
    this.changes = const <ScreenChange>[],
    this.createdAt,
  });

  /// Stable in-memory run id.
  final String id;

  /// Original user command.
  final String command;

  /// Planner intent classification.
  final ScreenCommandIntent intent;

  /// Planner response, clarification, or error text.
  final String message;

  /// Top-level planner confidence from 0 to 1.
  final double confidence;

  /// Proposed or applied screen changes.
  final List<ScreenChange> changes;

  /// Local creation timestamp.
  final DateTime? createdAt;

  /// Returns a copy with selected fields changed.
  ScreenCommandRun copyWith({
    String? id,
    String? command,
    ScreenCommandIntent? intent,
    String? message,
    double? confidence,
    List<ScreenChange>? changes,
    DateTime? createdAt,
  }) {
    return ScreenCommandRun(
      id: id ?? this.id,
      command: command ?? this.command,
      intent: intent ?? this.intent,
      message: message ?? this.message,
      confidence: confidence ?? this.confidence,
      changes: changes ?? this.changes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// BacklogScreenTaskSnapshot stores compact task state for AI planning.
class BacklogScreenTaskSnapshot {
  /// Creates one task snapshot row.
  const BacklogScreenTaskSnapshot({
    required this.id,
    required this.title,
    this.description = '',
    this.status = '',
    this.priority = '',
    this.dueAt = '',
    this.scheduledAt = '',
    this.followUpAt = '',
    this.topics = const <String>[],
    this.estimateMinutes = 0,
    this.context = '',
    this.owner = '',
  });

  /// Task id.
  final String id;

  /// Task title.
  final String title;

  /// Task description.
  final String description;

  /// Lifecycle status.
  final String status;

  /// Priority value.
  final String priority;

  /// ISO due timestamp or date.
  final String dueAt;

  /// ISO scheduled timestamp or date.
  final String scheduledAt;

  /// ISO stale-review timestamp or date.
  final String followUpAt;

  /// Topic tags.
  final List<String> topics;

  /// Estimated minutes.
  final int estimateMinutes;

  /// Execution context.
  final String context;

  /// Responsible person.
  final String owner;

  /// Encodes this task snapshot for the model prompt.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      if (description.isNotEmpty) 'description': description,
      if (status.isNotEmpty) 'status': status,
      if (priority.isNotEmpty) 'priority': priority,
      if (dueAt.isNotEmpty) 'due_at': dueAt,
      if (scheduledAt.isNotEmpty) 'scheduled_at': scheduledAt,
      if (followUpAt.isNotEmpty) 'follow_up_at': followUpAt,
      if (topics.isNotEmpty) 'topics': topics,
      if (estimateMinutes > 0) 'estimate_minutes': estimateMinutes,
      if (context.isNotEmpty) 'context': context,
      if (owner.isNotEmpty) 'person': owner,
    };
  }
}

/// BacklogScreenSnapshot stores the current backlog view for planning.
class BacklogScreenSnapshot {
  /// Creates a compact backlog screen snapshot.
  const BacklogScreenSnapshot({
    required this.scopeLabel,
    required this.visibleTasks,
    this.selectedTaskId = '',
    this.filters = const <String, dynamic>{},
    this.availableTools = const <String>[],
  });

  /// Human-readable screen and area label.
  final String scopeLabel;

  /// Visible backlog tasks.
  final List<BacklogScreenTaskSnapshot> visibleTasks;

  /// Selected task id, when available.
  final String selectedTaskId;

  /// Active queue filters.
  final Map<String, dynamic> filters;

  /// Available graph-backed write tools.
  final List<String> availableTools;

  /// Encodes this screen snapshot for the model prompt.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'scope': scopeLabel,
      'selected_task_id': selectedTaskId,
      'filters': filters,
      'available_tools': availableTools,
      'visible_tasks': visibleTasks.map((task) => task.toJson()).toList(),
    };
  }
}

/// ScreenCommandFormatException reports malformed planner JSON.
class ScreenCommandFormatException implements Exception {
  /// Creates a format exception for planner responses.
  const ScreenCommandFormatException(this.message);

  /// Human-readable parse failure.
  final String message;

  @override
  String toString() => 'ScreenCommandFormatException: $message';
}

/// Parses one strict JSON screen-command response.
ScreenCommandRun parseScreenCommandRun(String content, {String command = ''}) {
  final decoded = jsonDecode(content);
  if (decoded is! Map<String, dynamic>) {
    throw const ScreenCommandFormatException(
      'Planner response must be an object',
    );
  }
  return parseScreenCommandRunMap(decoded, command: command);
}

/// Parses one decoded screen-command response map.
ScreenCommandRun parseScreenCommandRunMap(
  Map<String, dynamic> decoded, {
  String command = '',
}) {
  final now = DateTime.now();
  final intent = screenCommandIntentFromWire(
    stringValue(decoded['intent'], trim: true),
  );
  final changesSource = decoded['changes'];
  final changes = changesSource is List
      ? changesSource
            .whereType<Map<String, dynamic>>()
            .map(parseScreenChangeMap)
            .toList()
      : const <ScreenChange>[];
  return ScreenCommandRun(
    id: stringValue(
      decoded['id'],
      fallback: 'screen-run-${now.microsecondsSinceEpoch}',
      trim: true,
    ),
    command: stringValue(decoded['command'], fallback: command, trim: true),
    intent: intent,
    message: stringValue(decoded['message'], trim: true),
    confidence: normalizedDouble(decoded['confidence']),
    changes: changes,
    createdAt: now,
  );
}

/// Parses one decoded screen-change response map.
ScreenChange parseScreenChangeMap(Map<String, dynamic> decoded) {
  final operation = screenChangeOperationFromWire(
    stringValue(decoded['operation'], trim: true),
  );
  final targetSource = decoded['target'];
  final target = targetSource is Map<String, dynamic>
      ? ScreenChangeTarget(
          taskId: stringValue(targetSource['task_id'], trim: true),
          taskTitle: stringValue(targetSource['task_title'], trim: true),
        )
      : ScreenChangeTarget(
          taskId: stringValue(decoded['task_id'], trim: true),
          taskTitle: stringValue(decoded['task_title'], trim: true),
        );
  final fields = jsonStringKeyMap(decoded['fields']);
  final now = DateTime.now();
  return ScreenChange(
    id: stringValue(
      decoded['id'],
      fallback: 'screen-change-${now.microsecondsSinceEpoch}',
      trim: true,
    ),
    operation: operation,
    target: target,
    summary: stringValue(
      decoded['summary'],
      fallback: _operationLabel(operation),
      trim: true,
    ),
    reason: stringValue(decoded['reason'], trim: true),
    confidence: normalizedDouble(decoded['confidence']),
    fields: fields,
  );
}

/// Converts a wire intent string to a ScreenCommandIntent value.
ScreenCommandIntent screenCommandIntentFromWire(String value) {
  switch (value.trim().toLowerCase()) {
    case 'change':
    case 'changes':
    case 'command':
      return ScreenCommandIntent.change;
    case 'question':
    case 'answer':
      return ScreenCommandIntent.question;
    case 'clarification':
    case 'clarify':
      return ScreenCommandIntent.clarification;
    default:
      throw ScreenCommandFormatException('Unknown screen intent "$value"');
  }
}

/// Converts a wire operation string to a ScreenChangeOperation value.
ScreenChangeOperation screenChangeOperationFromWire(String value) {
  switch (value.trim().toLowerCase()) {
    case 'create_task':
      return ScreenChangeOperation.createTask;
    case 'update_task':
      return ScreenChangeOperation.updateTask;
    case 'complete_task':
      return ScreenChangeOperation.completeTask;
    case 'cancel_task':
      return ScreenChangeOperation.cancelTask;
    case 'delete_task':
      return ScreenChangeOperation.deleteTask;
    case 'upsert_task_relation':
      return ScreenChangeOperation.upsertTaskRelation;
    case 'delete_task_relation':
      return ScreenChangeOperation.deleteTaskRelation;
    case 'link_task_memory':
      return ScreenChangeOperation.linkTaskMemory;
    default:
      throw ScreenCommandFormatException('Unknown screen operation "$value"');
  }
}

/// Converts one operation to its MCP tool name.
String screenChangeOperationToolName(ScreenChangeOperation operation) {
  return switch (operation) {
    ScreenChangeOperation.createTask => 'create_task',
    ScreenChangeOperation.updateTask => 'update_task',
    ScreenChangeOperation.completeTask => 'complete_task',
    ScreenChangeOperation.cancelTask => 'cancel_task',
    ScreenChangeOperation.deleteTask => 'delete_task',
    ScreenChangeOperation.upsertTaskRelation => 'upsert_task_relation',
    ScreenChangeOperation.deleteTaskRelation => 'delete_task_relation',
    ScreenChangeOperation.linkTaskMemory => 'link_task_memory',
  };
}

/// Builds a readable fallback summary for one operation.
String _operationLabel(ScreenChangeOperation operation) {
  return screenChangeOperationToolName(operation).replaceAll('_', ' ');
}
