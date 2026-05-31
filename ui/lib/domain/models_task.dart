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

  /// Agent runtime graph source id that returned this task.
  final String sourceId;

  /// Agent runtime graph source label that returned this task.
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

  /// Encodes the task filters to JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'statuses': statuses,
      'priorities': priorities,
      'topics': topics,
      if (search.trim().isNotEmpty) 'search': search.trim(),
      'overdue_only': overdueOnly,
      'include_done': includeDone,
      'limit': limit,
    };
  }

  /// Parses task filters from JSON-compatible data.
  factory TaskFilterState.fromJson(Map<String, dynamic> json) {
    return TaskFilterState(
      statuses: stringList(json['statuses'], trim: true),
      priorities: stringList(json['priorities'], trim: true),
      topics: stringList(json['topics'], trim: true),
      search: stringValue(json['search'], trim: true),
      overdueOnly: boolValue(json['overdue_only']),
      includeDone: boolValue(json['include_done'], fallback: true),
      limit: intValue(json['limit'], fallback: 100),
    );
  }

  /// Reports whether this filter has the same configured values as [other].
  bool sameAs(TaskFilterState other) {
    return _sameTaskFilterValues(statuses, other.statuses) &&
        _sameTaskFilterValues(priorities, other.priorities) &&
        _sameTaskFilterValues(topics, other.topics) &&
        search.trim() == other.search.trim() &&
        overdueOnly == other.overdueOnly &&
        includeDone == other.includeDone &&
        limit == other.limit;
  }
}

/// SavedTaskFilter stores one user-named task filter preset.
class SavedTaskFilter {
  /// Creates a saved task filter preset.
  const SavedTaskFilter({
    required this.id,
    required this.label,
    required this.filters,
  });

  /// Stable preset id.
  final String id;

  /// User-facing preset label.
  final String label;

  /// Task filters applied by the preset.
  final TaskFilterState filters;

  /// Encodes the preset to JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'filters': filters.toJson(),
    };
  }

  /// Parses a saved task filter preset from JSON-compatible data.
  factory SavedTaskFilter.fromJson(Map<String, dynamic> json) {
    final filters = jsonObject(json['filters']);
    return SavedTaskFilter(
      id: stringValue(json['id'], trim: true),
      label: stringValue(json['label'], trim: true),
      filters: TaskFilterState.fromJson(filters),
    );
  }
}

/// Returns a readable label for a task filter preset.
String taskFilterPresetLabel(TaskFilterState filters) {
  final parts = <String>[];
  if (filters.statuses.isEmpty) {
    parts.add('Any status');
  } else {
    parts.add(_taskFilterJoined(filters.statuses));
  }
  if (filters.priorities.isNotEmpty) {
    parts.add(_taskFilterJoined(filters.priorities));
  }
  if (filters.topics.isNotEmpty) {
    parts.add(_taskFilterJoined(filters.topics));
  }
  if (filters.overdueOnly) {
    parts.add('Overdue');
  }
  if (parts.isEmpty) {
    return 'Task filter';
  }
  return parts.join(' / ');
}

/// Returns a stable id for a saved task filter preset.
String taskFilterPresetId(TaskFilterState filters) {
  final raw = <String>[
    ...filters.statuses,
    '|',
    ...filters.priorities,
    '|',
    ...filters.topics,
    '|',
    filters.search.trim(),
    '|',
    filters.overdueOnly ? 'overdue' : '',
    '|',
    filters.includeDone ? 'include-done' : '',
    '|',
    filters.limit.toString(),
  ].join('-');
  final normalized = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final trimmed = normalized
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return trimmed.isEmpty ? 'task-filter' : 'task-filter-$trimmed';
}

/// Parses saved task filter presets from decoded JSON.
List<SavedTaskFilter> parseSavedTaskFilters(dynamic value) {
  final presets = <SavedTaskFilter>[];
  final seen = <String>{};
  for (final json in jsonObjectList(value)) {
    final preset = SavedTaskFilter.fromJson(json);
    if (preset.id.isEmpty || preset.label.isEmpty || seen.contains(preset.id)) {
      continue;
    }
    seen.add(preset.id);
    presets.add(preset);
  }
  return presets;
}

/// Reports whether two task filter lists contain the same ordered values.
bool _sameTaskFilterValues(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

/// Returns comma-joined title case labels for filter values.
String _taskFilterJoined(List<String> values) {
  return values.map(_taskFilterLabel).join(', ');
}

/// Returns a readable label for one filter value.
String _taskFilterLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed
      .split(RegExp(r'[_\-\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
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
