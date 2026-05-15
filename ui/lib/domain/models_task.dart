/// Workspace task, task metadata, and relation data models.
part of 'models.dart';

/// WorkspaceTask represents a task or plan step in the UI.
class WorkspaceTask {
  /// Creates a workspace task.
  const WorkspaceTask({
    required this.id,
    required this.title,
    required this.detail,
    required this.done,
    this.description = '',
    this.status = 'open',
    this.priority = 'normal',
    this.dueAt,
    this.scheduledAt,
    this.followUpAt,
    this.topics = const <String>[],
    this.estimateMinutes = 0,
    this.urgency = 0,
    this.risk = 0,
    this.project = '',
    this.location = '',
    this.owner = '',
    this.spendCents = 0,
    this.earnCents = 0,
    this.saveCents = 0,
    this.currency = '',
    this.workBreakdown = const TaskWorkBreakdown(),
    this.overdue = false,
    this.memoryLinks = const <TaskMemoryLink>[],
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.canceledAt,
    this.active = false,
    this.idempotencyKey = '',
    this.sourceId = '',
    this.sourceLabel = '',
  });

  /// Task id.
  final String id;

  /// Task title.
  final String title;

  /// Secondary status text.
  final String detail;

  /// Whether the task is complete.
  final bool done;

  /// Task notes.
  final String description;

  /// Backend lifecycle status.
  final String status;

  /// Backend priority value.
  final String priority;

  /// Optional due timestamp.
  final DateTime? dueAt;

  /// Optional scheduled timestamp.
  final DateTime? scheduledAt;

  /// Optional stale-review timestamp.
  final DateTime? followUpAt;

  /// Organization topics.
  final List<String> topics;

  /// Estimated task duration in minutes.
  final int estimateMinutes;

  /// Urgency score from 0 to 1.
  final double urgency;

  /// Risk score from 0 to 1.
  final double risk;

  /// Project the task belongs to.
  final String project;

  /// Location requirement.
  final String location;

  /// Responsible person.
  final String owner;

  /// Expected spend in minor currency units.
  final int spendCents;

  /// Expected earnings in minor currency units.
  final int earnCents;

  /// Expected savings in minor currency units.
  final int saveCents;

  /// Currency code for spend, earnings, and savings.
  final String currency;

  /// Optional WBS planning metadata.
  final TaskWorkBreakdown workBreakdown;

  /// Whether the task is past due.
  final bool overdue;

  /// Contextual memory references.
  final List<TaskMemoryLink> memoryLinks;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;

  /// Completion timestamp.
  final DateTime? completedAt;

  /// Cancellation timestamp.
  final DateTime? canceledAt;

  /// Whether the task is currently active.
  final bool active;

  /// Backend idempotency key, used to associate agent-created tasks with chats.
  final String idempotencyKey;

  /// Runtime profile graph source id that returned this task.
  final String sourceId;

  /// Runtime profile graph source label that returned this task.
  final String sourceLabel;

  /// Returns a copy with changed runtime source metadata.
  WorkspaceTask copyWith({
    String? sourceId,
    String? sourceLabel,
    TaskWorkBreakdown? workBreakdown,
  }) {
    return WorkspaceTask(
      id: id,
      title: title,
      detail: detail,
      done: done,
      description: description,
      status: status,
      priority: priority,
      dueAt: dueAt,
      scheduledAt: scheduledAt,
      followUpAt: followUpAt,
      topics: topics,
      estimateMinutes: estimateMinutes,
      urgency: urgency,
      risk: risk,
      project: project,
      location: location,
      owner: owner,
      spendCents: spendCents,
      earnCents: earnCents,
      saveCents: saveCents,
      currency: currency,
      workBreakdown: workBreakdown ?? this.workBreakdown,
      overdue: overdue,
      memoryLinks: memoryLinks,
      createdAt: createdAt,
      updatedAt: updatedAt,
      completedAt: completedAt,
      canceledAt: canceledAt,
      active: active,
      idempotencyKey: idempotencyKey,
      sourceId: sourceId ?? this.sourceId,
      sourceLabel: sourceLabel ?? this.sourceLabel,
    );
  }
}

/// TaskWorkBreakdown stores WBS planning metadata for one task.
class TaskWorkBreakdown {
  /// Creates WBS metadata for a task or work package.
  const TaskWorkBreakdown({
    this.code = '',
    this.deliverable = '',
    this.startCriteria = const <String>[],
    this.acceptanceCriteria = const <String>[],
    this.requirementRefs = const <String>[],
    this.rubricRefs = const <String>[],
    this.resources = const <TaskResourceRequirement>[],
    this.estimatedCostCents = 0,
    this.costCurrency = '',
  });

  /// WBS hierarchy code such as 1.2.3.
  final String code;

  /// Concrete task deliverable.
  final String deliverable;

  /// Conditions needed before work can start.
  final List<String> startCriteria;

  /// Conditions that prove the work is done.
  final List<String> acceptanceCriteria;

  /// Assignment requirement references satisfied by this task.
  final List<String> requirementRefs;

  /// Rubric criterion references supported by this task.
  final List<String> rubricRefs;

  /// People, tools, materials, or other resources needed.
  final List<TaskResourceRequirement> resources;

  /// Estimated cost in minor currency units.
  final int estimatedCostCents;

  /// Three-letter ISO currency code for estimated cost.
  final String costCurrency;
}

/// TaskResourceRequirement stores one resource needed by a WBS task.
class TaskResourceRequirement {
  /// Creates one WBS resource requirement.
  const TaskResourceRequirement({
    required this.name,
    this.type = '',
    this.quantity = 0,
    this.unit = '',
    this.estimatedCostCents = 0,
    this.costCurrency = '',
    this.notes = '',
  });

  /// Resource name.
  final String name;

  /// Resource category such as person, software, equipment, or material.
  final String type;

  /// Required quantity.
  final double quantity;

  /// Quantity unit.
  final String unit;

  /// Estimated resource cost in minor currency units.
  final int estimatedCostCents;

  /// Three-letter ISO currency code for resource cost.
  final String costCurrency;

  /// Resource notes.
  final String notes;
}

/// TaskMemoryLink references memory attached to a task object.
class TaskMemoryLink {
  /// Creates a task memory link.
  const TaskMemoryLink({
    required this.id,
    this.memoryId = '',
    this.memoryEvidenceId = '',
    this.relationship = 'context',
    this.note = '',
    this.createdAt,
  });

  /// Link id.
  final String id;

  /// Linked memory record id.
  final String memoryId;

  /// Linked memory source record id.
  final String memoryEvidenceId;

  /// Relationship from task object to memory.
  final String relationship;

  /// Optional link note.
  final String note;

  /// Creation timestamp.
  final DateTime? createdAt;
}

/// TaskMemoryLinkDraft describes a memory link write request.
class TaskMemoryLinkDraft {
  /// Creates a memory link draft.
  const TaskMemoryLinkDraft({
    this.memoryId = '',
    this.memoryEvidenceId = '',
    this.relationship = 'context',
    this.note = '',
  });

  /// Memory record id to link.
  final String memoryId;

  /// Memory source record id to link.
  final String memoryEvidenceId;

  /// Relationship from task object to memory.
  final String relationship;

  /// Optional link note.
  final String note;
}

/// TaskFilterState stores the active local task work-queue filters.
class TaskFilterState {
  /// Creates task queue filters.
  const TaskFilterState({
    this.statuses = const <String>['open', 'waiting', 'blocked'],
    this.priorities = const <String>[],
    this.topics = const <String>[],
    this.search = '',
    this.overdueOnly = false,
    this.includeDone = true,
    this.limit = 100,
  });

  /// Statuses to display; empty means all statuses.
  final List<String> statuses;

  /// Priorities to display; empty means all priorities.
  final List<String> priorities;

  /// Topics to display; empty means all topics.
  final List<String> topics;

  /// Local search text.
  final String search;

  /// Whether to display only overdue tasks.
  final bool overdueOnly;

  /// Whether done and canceled tasks may be displayed.
  final bool includeDone;

  /// Requested service page size.
  final int limit;

  /// Returns a filter copy with selected fields changed.
  TaskFilterState copyWith({
    List<String>? statuses,
    List<String>? priorities,
    List<String>? topics,
    String? search,
    bool? overdueOnly,
    bool? includeDone,
    int? limit,
  }) {
    return TaskFilterState(
      statuses: statuses ?? this.statuses,
      priorities: priorities ?? this.priorities,
      topics: topics ?? this.topics,
      search: search ?? this.search,
      overdueOnly: overdueOnly ?? this.overdueOnly,
      includeDone: includeDone ?? this.includeDone,
      limit: limit ?? this.limit,
    );
  }
}

/// TaskRelationRecord stores one explicit or inferred relation edge.
class TaskRelationRecord {
  /// Creates a task relation record.
  const TaskRelationRecord({
    required this.id,
    required this.fromTaskId,
    required this.toTaskId,
    required this.relationType,
    this.confidence = 0,
    this.source = '',
    this.explanation = '',
    this.actor = '',
    this.createdAt,
    this.updatedAt,
  });

  /// Stable relation id.
  final String id;

  /// Source task id.
  final String fromTaskId;

  /// Target task id.
  final String toTaskId;

  /// Relationship type.
  final String relationType;

  /// Relation confidence from 0 to 1.
  final double confidence;

  /// Relation source.
  final String source;

  /// Human-readable explanation.
  final String explanation;

  /// Last actor.
  final String actor;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;
}
