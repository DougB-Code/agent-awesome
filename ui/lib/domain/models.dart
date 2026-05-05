/// Contains UI-facing domain models shared by clients, state, and widgets.
library;

/// ConnectionStateKind describes service availability for the shell.
enum ConnectionStateKind {
  /// The service has not been checked yet.
  unknown,

  /// The service responded successfully.
  connected,

  /// The service failed or timed out.
  disconnected,
}

/// ChatRole identifies the speaker or event class in a chat timeline.
enum ChatRole {
  /// User-authored message.
  user,

  /// Assistant-authored message.
  assistant,

  /// Tool or function activity.
  tool,
}

/// ChatSession represents the ADK session backing one user-visible chat.
class ChatSession {
  /// Creates a user-visible chat summary backed by an ADK session.
  const ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  /// ADK session identifier.
  final String id;

  /// Human-readable title.
  final String title;

  /// Last update timestamp.
  final DateTime updatedAt;
}

/// ChatHistoryEntry stores app-owned chat metadata across profiles.
class ChatHistoryEntry {
  /// Creates a local chat history entry.
  const ChatHistoryEntry({
    required this.profilePath,
    required this.profileId,
    required this.profileLabel,
    required this.sessionId,
    required this.title,
    required this.updatedAt,
    this.createdAt,
    this.titleStatus = 'session',
    this.titleError = '',
  });

  /// Runtime profile path that owns the ADK session.
  final String profilePath;

  /// Runtime profile id captured when the chat was saved.
  final String profileId;

  /// Runtime profile label captured when the chat was saved.
  final String profileLabel;

  /// ADK session id inside the owning profile.
  final String sessionId;

  /// App-visible chat title.
  final String title;

  /// Chat creation timestamp when known.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime updatedAt;

  /// Title generation state such as session, manual, pending, generated, or failed.
  final String titleStatus;

  /// Last title generation error.
  final String titleError;

  /// Stable app-local key for profile/session lookup.
  String get key {
    return '$profilePath::$sessionId';
  }

  /// Returns a copy with selected metadata changed.
  ChatHistoryEntry copyWith({
    String? profilePath,
    String? profileId,
    String? profileLabel,
    String? sessionId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? titleStatus,
    String? titleError,
  }) {
    return ChatHistoryEntry(
      profilePath: profilePath ?? this.profilePath,
      profileId: profileId ?? this.profileId,
      profileLabel: profileLabel ?? this.profileLabel,
      sessionId: sessionId ?? this.sessionId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      titleStatus: titleStatus ?? this.titleStatus,
      titleError: titleError ?? this.titleError,
    );
  }

  /// Encodes this history entry to JSON.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'profile_path': profilePath,
      'profile_id': profileId,
      'profile_label': profileLabel,
      'session_id': sessionId,
      'title': title,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'title_status': titleStatus,
      'title_error': titleError,
    };
  }

  /// Parses a history entry from decoded JSON.
  factory ChatHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ChatHistoryEntry(
      profilePath: _modelString(json['profile_path']),
      profileId: _modelString(json['profile_id']),
      profileLabel: _modelString(json['profile_label']),
      sessionId: _modelString(json['session_id']),
      title: _modelString(json['title'], fallback: 'Untitled chat'),
      createdAt: _modelDateTime(json['created_at']),
      updatedAt: _modelDateTime(json['updated_at']) ?? DateTime.now(),
      titleStatus: _modelString(json['title_status'], fallback: 'session'),
      titleError: _modelString(json['title_error']),
    );
  }
}

/// ChatMessage represents one normalized message or activity row.
class ChatMessage {
  /// Creates a normalized chat message.
  const ChatMessage({
    required this.id,
    required this.role,
    required this.author,
    required this.text,
    required this.createdAt,
    this.toolActivity,
    this.isPartial = false,
  });

  /// Stable UI id.
  final String id;

  /// Speaker or event type.
  final ChatRole role;

  /// Display author.
  final String author;

  /// Display text.
  final String text;

  /// Timestamp for ordering and display.
  final DateTime createdAt;

  /// Optional tool activity metadata.
  final ToolActivity? toolActivity;

  /// Whether the message is a streaming partial.
  final bool isPartial;

  /// Returns a copy with changed display text.
  ChatMessage copyWith({String? text, bool? isPartial}) {
    return ChatMessage(
      id: id,
      role: role,
      author: author,
      text: text ?? this.text,
      createdAt: createdAt,
      toolActivity: toolActivity,
      isPartial: isPartial ?? this.isPartial,
    );
  }
}

/// ToolActivity summarizes one function call or result.
class ToolActivity {
  /// Creates a tool activity row.
  const ToolActivity({
    required this.name,
    required this.status,
    required this.summary,
  });

  /// Tool or function name.
  final String name;

  /// Short status such as requested, completed, or denied.
  final String status;

  /// Human-readable summary.
  final String summary;
}

/// ConfirmationRequest stores an ADK confirmation prompt awaiting user choice.
class ConfirmationRequest {
  /// Creates a confirmation request.
  const ConfirmationRequest({
    required this.callId,
    required this.hint,
    required this.options,
    this.toolName = '',
  });

  /// ADK function-call id to echo in the response.
  final String callId;

  /// Human-readable prompt text.
  final String hint;

  /// Available confirmation options.
  final List<ConfirmationOption> options;

  /// Original tool name that requested confirmation, when supplied by ADK.
  final String toolName;
}

/// ConfirmationOption describes one selectable confirmation action.
class ConfirmationOption {
  /// Creates a confirmation option.
  const ConfirmationOption({required this.action, required this.label});

  /// Machine action sent back to ADK.
  final String action;

  /// User-facing label.
  final String label;
}

/// ConfirmationReply is the user's response to an ADK confirmation request.
class ConfirmationReply {
  /// Creates a confirmation reply.
  const ConfirmationReply({
    required this.callId,
    required this.confirmed,
    this.action,
  });

  /// ADK function-call id.
  final String callId;

  /// Whether the action is approved.
  final bool confirmed;

  /// Optional selected action.
  final String? action;
}

/// MemoryRecord represents one durable memory row for display.
class MemoryRecord {
  /// Creates a display memory record.
  const MemoryRecord({
    required this.id,
    required this.title,
    required this.summary,
    required this.kind,
    required this.topics,
    required this.sourceLabel,
    this.evidenceId = '',
    this.scope = 'user',
    this.trustLevel = 'source_original',
    this.sensitivity = 'private',
    this.status = 'active',
    this.subjects = const <String>[],
    this.entityIds = const <String>[],
    this.entityNames = const <String>[],
    this.sourceSystem = '',
    this.sourceId = '',
    this.rawPath = '',
    this.rawChecksum = '',
    this.rawMediaType = '',
    this.rawContent = '',
    this.relationships = const <MemoryRelationship>[],
    this.eventTime,
    this.createdAt,
    this.updatedAt,
  });

  /// Memory record id.
  final String id;

  /// Display title.
  final String title;

  /// Short summary.
  final String summary;

  /// Memory kind.
  final String kind;

  /// Topics associated with the record.
  final List<String> topics;

  /// Source label.
  final String sourceLabel;

  /// Raw evidence id backing the memory record.
  final String evidenceId;

  /// Ownership and visibility boundary.
  final String scope;

  /// Provenance trust classification.
  final String trustLevel;

  /// Disclosure sensitivity.
  final String sensitivity;

  /// Lifecycle status.
  final String status;

  /// Primary subject headings.
  final List<String> subjects;

  /// Canonical entity ids linked to the record.
  final List<String> entityIds;

  /// Canonical entity names linked to the record.
  final List<String> entityNames;

  /// Source system name.
  final String sourceSystem;

  /// Source system record id.
  final String sourceId;

  /// Durable raw evidence path.
  final String rawPath;

  /// Raw evidence checksum.
  final String rawChecksum;

  /// Raw evidence media type.
  final String rawMediaType;

  /// Optional hydrated raw evidence text.
  final String rawContent;

  /// Outgoing memory relationships.
  final List<MemoryRelationship> relationships;

  /// Optional real-world event time.
  final DateTime? eventTime;

  /// Memory creation time.
  final DateTime? createdAt;

  /// Memory update time.
  final DateTime? updatedAt;

  /// Returns a copy with hydrated source content or repaired metadata.
  MemoryRecord copyWith({
    String? title,
    String? summary,
    String? kind,
    String? scope,
    String? trustLevel,
    String? sensitivity,
    String? status,
    List<String>? subjects,
    List<String>? topics,
    List<String>? entityIds,
    List<String>? entityNames,
    String? rawContent,
    List<MemoryRelationship>? relationships,
    DateTime? updatedAt,
  }) {
    return MemoryRecord(
      id: id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      kind: kind ?? this.kind,
      topics: topics ?? this.topics,
      sourceLabel: sourceLabel,
      evidenceId: evidenceId,
      scope: scope ?? this.scope,
      trustLevel: trustLevel ?? this.trustLevel,
      sensitivity: sensitivity ?? this.sensitivity,
      status: status ?? this.status,
      subjects: subjects ?? this.subjects,
      entityIds: entityIds ?? this.entityIds,
      entityNames: entityNames ?? this.entityNames,
      sourceSystem: sourceSystem,
      sourceId: sourceId,
      rawPath: rawPath,
      rawChecksum: rawChecksum,
      rawMediaType: rawMediaType,
      rawContent: rawContent ?? this.rawContent,
      relationships: relationships ?? this.relationships,
      eventTime: eventTime,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// MemoryRelationship represents a typed edge between memory objects.
class MemoryRelationship {
  /// Creates a memory relationship edge.
  const MemoryRelationship({
    required this.id,
    required this.fromId,
    required this.type,
    required this.toId,
    required this.trustLevel,
    this.sourceId = '',
    this.createdAt,
  });

  /// Relationship id.
  final String id;

  /// Source memory object id.
  final String fromId;

  /// Controlled relationship type.
  final String type;

  /// Target memory object id.
  final String toId;

  /// Evidence id supporting the edge.
  final String sourceId;

  /// Trust classification for the edge.
  final String trustLevel;

  /// Relationship creation time.
  final DateTime? createdAt;
}

/// CompiledMemoryPage represents a source-backed entity page or timeline.
class CompiledMemoryPage {
  /// Creates a compiled memory page.
  const CompiledMemoryPage({
    required this.id,
    required this.kind,
    required this.scope,
    required this.title,
    required this.path,
    required this.status,
    required this.sourceIds,
    this.content = '',
    this.stale = false,
    this.uncertainty = const <String>[],
    this.createdAt,
    this.updatedAt,
  });

  /// Page id.
  final String id;

  /// Page kind, usually entity_page or timeline.
  final String kind;

  /// Ownership scope used to build the page.
  final String scope;

  /// Human-readable page title.
  final String title;

  /// Durable page path.
  final String path;

  /// Lifecycle status.
  final String status;

  /// Evidence ids cited by the page.
  final List<String> sourceIds;

  /// Optional markdown content.
  final String content;

  /// Whether the page should be rebuilt.
  final bool stale;

  /// Known uncertainty surfaced during compilation.
  final List<String> uncertainty;

  /// Page creation time.
  final DateTime? createdAt;

  /// Page update time.
  final DateTime? updatedAt;
}

/// MemoryFilterState stores memory retrieval and local stewardship filters.
class MemoryFilterState {
  /// Creates memory filter state.
  const MemoryFilterState({
    this.scope = 'user',
    this.text = '',
    this.kinds = const <String>[],
    this.topics = const <String>[],
    this.entityIds = const <String>[],
    this.allowedSensitivities = const <String>['public', 'internal', 'private'],
    this.localStatus = '',
    this.localTrustLevel = '',
    this.limit = 100,
  });

  /// Retrieval scope.
  final String scope;

  /// Full-text query.
  final String text;

  /// Included memory kinds.
  final List<String> kinds;

  /// Required topics.
  final List<String> topics;

  /// Required entity ids.
  final List<String> entityIds;

  /// Sensitivity levels allowed in retrieval.
  final List<String> allowedSensitivities;

  /// Local status filter applied after retrieval.
  final String localStatus;

  /// Local trust filter applied after retrieval.
  final String localTrustLevel;

  /// Maximum records to request.
  final int limit;

  /// Returns a copy with updated filter fields.
  MemoryFilterState copyWith({
    String? scope,
    String? text,
    List<String>? kinds,
    List<String>? topics,
    List<String>? entityIds,
    List<String>? allowedSensitivities,
    String? localStatus,
    String? localTrustLevel,
    int? limit,
  }) {
    return MemoryFilterState(
      scope: scope ?? this.scope,
      text: text ?? this.text,
      kinds: kinds ?? this.kinds,
      topics: topics ?? this.topics,
      entityIds: entityIds ?? this.entityIds,
      allowedSensitivities: allowedSensitivities ?? this.allowedSensitivities,
      localStatus: localStatus ?? this.localStatus,
      localTrustLevel: localTrustLevel ?? this.localTrustLevel,
      limit: limit ?? this.limit,
    );
  }
}

/// MemoryCaptureDraft stores a careful user-authored capture request.
class MemoryCaptureDraft {
  /// Creates a memory capture draft.
  const MemoryCaptureDraft({
    required this.content,
    required this.title,
    required this.kind,
    required this.scope,
    required this.trustLevel,
    required this.sensitivity,
    required this.sourceSystem,
    required this.sourceId,
    this.mediaType = 'text/plain; charset=utf-8',
    this.subjects = const <String>[],
    this.topics = const <String>[],
    this.entityNames = const <String>[],
  });

  /// Source text or serialized source content.
  final String content;

  /// Human-readable memory title.
  final String title;

  /// Memory kind.
  final String kind;

  /// Memory scope.
  final String scope;

  /// Trust level.
  final String trustLevel;

  /// Sensitivity level.
  final String sensitivity;

  /// Source system label.
  final String sourceSystem;

  /// Source record id.
  final String sourceId;

  /// Source media type.
  final String mediaType;

  /// Subject headings.
  final List<String> subjects;

  /// Topic labels.
  final List<String> topics;

  /// Entity labels.
  final List<String> entityNames;
}

/// MemoryRepairDraft stores explicit memory metadata corrections.
class MemoryRepairDraft {
  /// Creates a memory repair draft.
  const MemoryRepairDraft({
    required this.memoryId,
    this.title,
    this.summary,
    this.kind,
    this.sensitivity,
    this.status,
    this.subjects,
    this.topics,
    this.entityNames,
  });

  /// Memory record id.
  final String memoryId;

  /// Corrected title.
  final String? title;

  /// Corrected summary.
  final String? summary;

  /// Corrected kind.
  final String? kind;

  /// Corrected sensitivity.
  final String? sensitivity;

  /// Corrected lifecycle status.
  final String? status;

  /// Corrected subject headings.
  final List<String>? subjects;

  /// Corrected topic labels.
  final List<String>? topics;

  /// Corrected entity names.
  final List<String>? entityNames;
}

/// SourceItem represents a file/source backing the workspace.
class SourceItem {
  /// Creates a source item.
  const SourceItem({
    required this.id,
    required this.title,
    required this.detail,
  });

  /// Stable source id.
  final String id;

  /// Display title.
  final String title;

  /// Secondary text.
  final String detail;
}

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
    this.topics = const <String>[],
    this.estimateMinutes = 0,
    this.energyRequired = '',
    this.effort = 0,
    this.value = 0,
    this.urgency = 0,
    this.risk = 0,
    this.context = '',
    this.domain = '',
    this.project = '',
    this.location = '',
    this.owner = '',
    this.spendCents = 0,
    this.earnCents = 0,
    this.saveCents = 0,
    this.currency = '',
    this.source = '',
    this.workBreakdown = const TaskWorkBreakdown(),
    this.confidence = 0,
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

  /// Organization topics.
  final List<String> topics;

  /// Estimated task duration in minutes.
  final int estimateMinutes;

  /// Required energy mode.
  final String energyRequired;

  /// Effort score from 0 to 1.
  final double effort;

  /// Value score from 0 to 1.
  final double value;

  /// Urgency score from 0 to 1.
  final double urgency;

  /// Risk score from 0 to 1.
  final double risk;

  /// Execution context.
  final String context;

  /// Cross-cutting task view.
  final String domain;

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

  /// Task source.
  final String source;

  /// Optional WBS planning metadata.
  final TaskWorkBreakdown workBreakdown;

  /// Metadata confidence from 0 to 1.
  final double confidence;

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
      topics: topics,
      estimateMinutes: estimateMinutes,
      energyRequired: energyRequired,
      effort: effort,
      value: value,
      urgency: urgency,
      risk: risk,
      context: context,
      domain: domain,
      project: project,
      location: location,
      owner: owner,
      spendCents: spendCents,
      earnCents: earnCents,
      saveCents: saveCents,
      currency: currency,
      source: source,
      workBreakdown: workBreakdown ?? this.workBreakdown,
      confidence: confidence,
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

  /// Linked memory evidence id.
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

  /// Memory evidence id to link.
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

/// TaskRelationSuggestion stores one inferred relation recommendation.
class TaskRelationSuggestion {
  /// Creates a task relation suggestion.
  const TaskRelationSuggestion({
    required this.id,
    required this.fromTaskId,
    required this.toTaskId,
    required this.relationType,
    this.confidence = 0,
    this.explanation = '',
  });

  /// Stable suggestion id.
  final String id;

  /// Source task id.
  final String fromTaskId;

  /// Target task id.
  final String toTaskId;

  /// Relationship type.
  final String relationType;

  /// Suggestion confidence.
  final double confidence;

  /// Suggestion explanation.
  final String explanation;
}

/// TaskMetadataSuggestion stores one inferred metadata recommendation.
class TaskMetadataSuggestion {
  /// Creates a task metadata suggestion.
  const TaskMetadataSuggestion({
    required this.id,
    required this.taskId,
    this.estimateMinutes = 0,
    this.energyRequired = '',
    this.effort = 0,
    this.value = 0,
    this.urgency = 0,
    this.risk = 0,
    this.context = '',
    this.domain = '',
    this.project = '',
    this.location = '',
    this.owner = '',
    this.source = '',
    this.confidence = 0,
    this.explanation = '',
  });

  /// Stable suggestion id.
  final String id;

  /// Task receiving metadata.
  final String taskId;

  /// Estimated task duration.
  final int estimateMinutes;

  /// Suggested energy mode.
  final String energyRequired;

  /// Suggested effort score.
  final double effort;

  /// Suggested value score.
  final double value;

  /// Suggested urgency score.
  final double urgency;

  /// Suggested risk score.
  final double risk;

  /// Suggested execution context.
  final String context;

  /// Suggested cross-cutting task view.
  final String domain;

  /// Suggested project.
  final String project;

  /// Suggested location.
  final String location;

  /// Suggested responsible person.
  final String owner;

  /// Suggested source.
  final String source;

  /// Suggestion confidence.
  final double confidence;

  /// Human-readable explanation.
  final String explanation;
}

/// TaskCommitmentSuggestion stores one inferred commitment recommendation.
class TaskCommitmentSuggestion {
  /// Creates a task commitment suggestion.
  const TaskCommitmentSuggestion({
    required this.id,
    required this.taskId,
    this.people = const <String>[],
    this.domain = '',
    this.project = '',
    this.timeWindow = '',
    this.responsibility = '',
    this.promiseSource = '',
    this.hardness = '',
    this.consequence = '',
    this.confidence = 0,
    this.explanation = '',
  });

  /// Stable suggestion id.
  final String id;

  /// Task represented by this suggested commitment.
  final String taskId;

  /// Suggested affected people.
  final List<String> people;

  /// Suggested cross-cutting task view.
  final String domain;

  /// Suggested project.
  final String project;

  /// Suggested time window.
  final String timeWindow;

  /// Suggested responsibility state.
  final String responsibility;

  /// Suggested promise source.
  final String promiseSource;

  /// Suggested soft or hard commitment.
  final String hardness;

  /// Suggested consequence if ignored.
  final String consequence;

  /// Suggestion confidence.
  final double confidence;

  /// Human-readable explanation.
  final String explanation;
}

/// TaskCommitment stores one first-class task commitment.
class TaskCommitment {
  /// Creates a task commitment.
  const TaskCommitment({
    required this.id,
    required this.taskId,
    this.people = const <String>[],
    this.domain = '',
    this.project = '',
    this.timeWindow = '',
    this.responsibility = '',
    this.promiseSource = '',
    this.hardness = '',
    this.consequence = '',
    this.actor = '',
    this.createdAt,
    this.updatedAt,
  });

  /// Stable commitment id.
  final String id;

  /// Referenced task id.
  final String taskId;

  /// Affected people.
  final List<String> people;

  /// Cross-cutting task view.
  final String domain;

  /// Project name.
  final String project;

  /// Time window label.
  final String timeWindow;

  /// Responsibility state.
  final String responsibility;

  /// Source of promise.
  final String promiseSource;

  /// Soft or hard commitment.
  final String hardness;

  /// Consequence if ignored.
  final String consequence;

  /// Last actor.
  final String actor;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;
}

/// TaskProjectionGraph stores canonical task facts for client-owned projections.
class TaskProjectionGraph {
  /// Creates a canonical task projection graph.
  const TaskProjectionGraph({
    this.schemaVersion = '1.0',
    this.generatedAt,
    this.tasks = const <TaskProjectionTask>[],
    this.facets = const <TaskProjectionFacet>[],
    this.memberships = const <TaskProjectionMembership>[],
    this.edges = const <TaskProjectionEdge>[],
    this.commitments = const <TaskCommitment>[],
    this.metadataGaps = const <TaskMetadataGapRecord>[],
    this.insightSummaries = const <TaskInsightSummary>[],
    this.quality = const TaskProjectionQuality(),
  });

  /// Schema version returned by the projection graph service.
  final String schemaVersion;

  /// Projection generation timestamp.
  final DateTime? generatedAt;

  /// Canonical projected task records.
  final List<TaskProjectionTask> tasks;

  /// Reusable grouping facets.
  final List<TaskProjectionFacet> facets;

  /// Task-to-facet membership records.
  final List<TaskProjectionMembership> memberships;

  /// Sparse meaningful task-to-task edges.
  final List<TaskProjectionEdge> edges;

  /// First-class commitments included in v2 graph responses.
  final List<TaskCommitment> commitments;

  /// Source or derived metadata gaps included in v2 graph responses.
  final List<TaskMetadataGapRecord> metadataGaps;

  /// Precomputed insight summaries included in v2 graph responses.
  final List<TaskInsightSummary> insightSummaries;

  /// Graph quality and coverage metrics.
  final TaskProjectionQuality quality;
}

/// TaskProjectionQuality stores graph-level trust and completeness metrics.
class TaskProjectionQuality {
  /// Creates graph quality metrics.
  const TaskProjectionQuality({
    this.schemaConfidence = 0,
    this.metadataCompleteness = 0,
    this.relationCoverage = 0,
    this.warnings = const <String>[],
  });

  /// Confidence that the graph matches the expected schema.
  final double schemaConfidence;

  /// Aggregate metadata completeness from 0 to 1.
  final double metadataCompleteness;

  /// Aggregate relation coverage from 0 to 1.
  final double relationCoverage;

  /// Human-readable graph warnings.
  final List<String> warnings;
}

/// TaskProjectionTask stores one task with derived scores and facets.
class TaskProjectionTask {
  /// Creates a canonical projected task.
  const TaskProjectionTask({
    required this.taskId,
    required this.title,
    required this.status,
    required this.priority,
    this.description = '',
    this.dueAt,
    this.scheduledAt,
    this.topics = const <String>[],
    this.estimateMinutes = 0,
    this.energyRequired = '',
    this.context = '',
    this.domain = '',
    this.project = '',
    this.location = '',
    this.owner = '',
    this.source = '',
    this.workBreakdown = const TaskWorkBreakdown(),
    this.projectId = '',
    this.workstreamId = '',
    this.valueType = '',
    this.obligationLevel = '',
    this.consequenceSeverity = '',
    this.agentSafety = '',
    this.handoffReadiness = '',
    this.dependencyState = '',
    this.scores = const TaskProjectionScores(),
    this.scoreComponents = const <String, List<TaskScoreComponent>>{},
    this.facetIds = const <String>[],
    this.evidenceIds = const <String>[],
    this.missingFields = const <String>[],
    this.confidence = 0,
    this.explanation = '',
  });

  /// Referenced task id.
  final String taskId;

  /// Display title.
  final String title;

  /// Task notes.
  final String description;

  /// Backend lifecycle status.
  final String status;

  /// Backend task priority.
  final String priority;

  /// Optional due timestamp.
  final DateTime? dueAt;

  /// Optional scheduled timestamp.
  final DateTime? scheduledAt;

  /// Task topics.
  final List<String> topics;

  /// Estimated duration in minutes.
  final int estimateMinutes;

  /// Required energy mode.
  final String energyRequired;

  /// Execution context.
  final String context;

  /// Cross-cutting task view.
  final String domain;

  /// Project name from explicit task metadata.
  final String project;

  /// Location requirement.
  final String location;

  /// Responsible person.
  final String owner;

  /// Task source.
  final String source;

  /// Optional WBS planning metadata.
  final TaskWorkBreakdown workBreakdown;

  /// Normalized owning project id.
  final String projectId;

  /// Normalized workstream id.
  final String workstreamId;

  /// Controlled primary value type.
  final String valueType;

  /// Controlled obligation level.
  final String obligationLevel;

  /// Controlled consequence severity.
  final String consequenceSeverity;

  /// Controlled agent safety state.
  final String agentSafety;

  /// Controlled handoff readiness state.
  final String handoffReadiness;

  /// Controlled dependency state.
  final String dependencyState;

  /// Derived projection scores.
  final TaskProjectionScores scores;

  /// Per-score explanation components keyed by score name.
  final Map<String, List<TaskScoreComponent>> scoreComponents;

  /// Stable facet ids associated with this task.
  final List<String> facetIds;

  /// Evidence records that support task classifications.
  final List<String> evidenceIds;

  /// Missing fields that lower insight confidence.
  final List<String> missingFields;

  /// Projection confidence from 0 to 1.
  final double confidence;

  /// Human-readable projection explanation.
  final String explanation;

  /// Returns this task with selected graph fields replaced.
  TaskProjectionTask copyWith({
    String? taskId,
    String? title,
    String? status,
    String? priority,
    String? description,
    DateTime? dueAt,
    DateTime? scheduledAt,
    List<String>? topics,
    int? estimateMinutes,
    String? energyRequired,
    String? context,
    String? domain,
    String? project,
    String? location,
    String? owner,
    String? source,
    TaskWorkBreakdown? workBreakdown,
    String? projectId,
    String? workstreamId,
    String? valueType,
    String? obligationLevel,
    String? consequenceSeverity,
    String? agentSafety,
    String? handoffReadiness,
    String? dependencyState,
    TaskProjectionScores? scores,
    Map<String, List<TaskScoreComponent>>? scoreComponents,
    List<String>? facetIds,
    List<String>? evidenceIds,
    List<String>? missingFields,
    double? confidence,
    String? explanation,
  }) {
    return TaskProjectionTask(
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      description: description ?? this.description,
      dueAt: dueAt ?? this.dueAt,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      topics: topics ?? this.topics,
      estimateMinutes: estimateMinutes ?? this.estimateMinutes,
      energyRequired: energyRequired ?? this.energyRequired,
      context: context ?? this.context,
      domain: domain ?? this.domain,
      project: project ?? this.project,
      location: location ?? this.location,
      owner: owner ?? this.owner,
      source: source ?? this.source,
      workBreakdown: workBreakdown ?? this.workBreakdown,
      projectId: projectId ?? this.projectId,
      workstreamId: workstreamId ?? this.workstreamId,
      valueType: valueType ?? this.valueType,
      obligationLevel: obligationLevel ?? this.obligationLevel,
      consequenceSeverity: consequenceSeverity ?? this.consequenceSeverity,
      agentSafety: agentSafety ?? this.agentSafety,
      handoffReadiness: handoffReadiness ?? this.handoffReadiness,
      dependencyState: dependencyState ?? this.dependencyState,
      scores: scores ?? this.scores,
      scoreComponents: scoreComponents ?? this.scoreComponents,
      facetIds: facetIds ?? this.facetIds,
      evidenceIds: evidenceIds ?? this.evidenceIds,
      missingFields: missingFields ?? this.missingFields,
      confidence: confidence ?? this.confidence,
      explanation: explanation ?? this.explanation,
    );
  }
}

/// TaskProjectionScores stores derived insight scores for one task.
class TaskProjectionScores {
  /// Creates derived task projection scores.
  const TaskProjectionScores({
    this.reward = 0,
    this.pressure = 0,
    this.risk = 0,
    this.timePressure = 0,
    this.humanEffort = 0,
    this.agentFit = 0,
    this.obligation = 0,
    this.consequenceSeverity = 0,
    this.agentSafety = 0,
    this.handoffReadiness = 0,
    this.contextReadiness = 0,
    this.humanJudgmentNeed = 0,
    this.downstreamValue = 0,
    this.blockerEffort = 0,
    this.unblockLeverage = 0,
    this.metadataCompleteness = 0,
    this.staleness = 0,
    this.commitmentHardness = 0,
    this.elevation = 0,
    this.terrainZone = '',
  });

  /// Reward or upside score.
  final double reward;

  /// Combined pressure score.
  final double pressure;

  /// Failure or delay risk score.
  final double risk;

  /// Deadline pressure score.
  final double timePressure;

  /// Human attention cost score.
  final double humanEffort;

  /// Agent delegation fit score.
  final double agentFit;

  /// Obligation or must-do score.
  final double obligation;

  /// Consequence severity score.
  final double consequenceSeverity;

  /// Agent safety score.
  final double agentSafety;

  /// Handoff readiness score.
  final double handoffReadiness;

  /// Context readiness score.
  final double contextReadiness;

  /// Human judgment requirement score.
  final double humanJudgmentNeed;

  /// Downstream value unlocked by this task.
  final double downstreamValue;

  /// Estimated effort to clear this blocker.
  final double blockerEffort;

  /// Downstream value per unit of blocker effort.
  final double unblockLeverage;

  /// Metadata completeness score.
  final double metadataCompleteness;

  /// Staleness score.
  final double staleness;

  /// Commitment hardness score.
  final double commitmentHardness;

  /// Overall importance score.
  final double elevation;

  /// Derived terrain zone id.
  final String terrainZone;
}

/// TaskScoreComponent explains one component of a derived score.
class TaskScoreComponent {
  /// Creates one score component.
  const TaskScoreComponent({
    required this.name,
    required this.value,
    this.explanation = '',
  });

  /// Machine-readable component name.
  final String name;

  /// Component contribution or normalized value.
  final double value;

  /// Human-readable score explanation.
  final String explanation;
}

/// TaskProjectionFacet stores one reusable grouping entity.
class TaskProjectionFacet {
  /// Creates a canonical task grouping facet.
  const TaskProjectionFacet({
    required this.id,
    required this.dimension,
    required this.label,
    this.description = '',
    this.source = '',
    this.version = '',
    this.sourceField = '',
    this.provenance = '',
    this.confidence = 0,
  });

  /// Stable facet id.
  final String id;

  /// Facet dimension such as time or context.
  final String dimension;

  /// User-facing label.
  final String label;

  /// Short dimension explanation.
  final String description;

  /// Fact source such as task, derived, or commitment.
  final String source;

  /// Controlled vocabulary version.
  final String version;

  /// Source field used to derive this facet.
  final String sourceField;

  /// Short provenance label.
  final String provenance;

  /// Facet confidence from 0 to 1.
  final double confidence;

  /// Returns this facet with selected identity fields replaced.
  TaskProjectionFacet copyWith({
    String? id,
    String? dimension,
    String? label,
    String? description,
    String? source,
    String? version,
    String? sourceField,
    String? provenance,
    double? confidence,
  }) {
    return TaskProjectionFacet(
      id: id ?? this.id,
      dimension: dimension ?? this.dimension,
      label: label ?? this.label,
      description: description ?? this.description,
      source: source ?? this.source,
      version: version ?? this.version,
      sourceField: sourceField ?? this.sourceField,
      provenance: provenance ?? this.provenance,
      confidence: confidence ?? this.confidence,
    );
  }
}

/// TaskProjectionMembership links a task to a facet.
class TaskProjectionMembership {
  /// Creates a task-to-facet membership.
  const TaskProjectionMembership({
    required this.taskId,
    required this.facetId,
    required this.dimension,
    this.source = '',
    this.confidence = 0,
    this.explanation = '',
  });

  /// Referenced task id.
  final String taskId;

  /// Referenced facet id.
  final String facetId;

  /// Facet dimension.
  final String dimension;

  /// Membership source.
  final String source;

  /// Membership confidence from 0 to 1.
  final double confidence;

  /// Human-readable membership explanation.
  final String explanation;

  /// Returns this membership with selected identity fields replaced.
  TaskProjectionMembership copyWith({
    String? taskId,
    String? facetId,
    String? dimension,
    String? source,
    double? confidence,
    String? explanation,
  }) {
    return TaskProjectionMembership(
      taskId: taskId ?? this.taskId,
      facetId: facetId ?? this.facetId,
      dimension: dimension ?? this.dimension,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      explanation: explanation ?? this.explanation,
    );
  }
}

/// TaskProjectionEdge stores one sparse meaningful task relation.
class TaskProjectionEdge {
  /// Creates a canonical task projection edge.
  const TaskProjectionEdge({
    required this.fromTaskId,
    required this.toTaskId,
    required this.relationType,
    this.id = '',
    this.directionSemantics = '',
    this.source = '',
    this.sourceKind = '',
    this.scope = '',
    this.sensitivity = '',
    this.confidence = 0,
    this.explanation = '',
    this.evidenceIds = const <String>[],
    this.actor = '',
    this.createdAt,
    this.updatedAt,
    this.confirmedAt,
    this.dismissedAt,
  });

  /// Stable relation id.
  final String id;

  /// Source task id.
  final String fromTaskId;

  /// Target task id.
  final String toTaskId;

  /// Relationship type.
  final String relationType;

  /// Edge source.
  final String source;

  /// Explicit direction semantics for graph analytics.
  final String directionSemantics;

  /// Source kind such as explicit, inferred, or system-derived.
  final String sourceKind;

  /// Access scope attached to the edge's source graph fact.
  final String scope;

  /// Sensitivity attached to the edge's source graph fact.
  final String sensitivity;

  /// Edge confidence from 0 to 1.
  final double confidence;

  /// Human-readable edge explanation.
  final String explanation;

  /// Evidence records that support this relation.
  final List<String> evidenceIds;

  /// Last actor.
  final String actor;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;

  /// User confirmation timestamp.
  final DateTime? confirmedAt;

  /// User dismissal timestamp.
  final DateTime? dismissedAt;

  /// Returns this edge with selected identity fields replaced.
  TaskProjectionEdge copyWith({
    String? id,
    String? fromTaskId,
    String? toTaskId,
    String? relationType,
    String? directionSemantics,
    String? source,
    String? sourceKind,
    String? scope,
    String? sensitivity,
    double? confidence,
    String? explanation,
    List<String>? evidenceIds,
    String? actor,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? confirmedAt,
    DateTime? dismissedAt,
  }) {
    return TaskProjectionEdge(
      id: id ?? this.id,
      fromTaskId: fromTaskId ?? this.fromTaskId,
      toTaskId: toTaskId ?? this.toTaskId,
      relationType: relationType ?? this.relationType,
      directionSemantics: directionSemantics ?? this.directionSemantics,
      source: source ?? this.source,
      sourceKind: sourceKind ?? this.sourceKind,
      scope: scope ?? this.scope,
      sensitivity: sensitivity ?? this.sensitivity,
      confidence: confidence ?? this.confidence,
      explanation: explanation ?? this.explanation,
      evidenceIds: evidenceIds ?? this.evidenceIds,
      actor: actor ?? this.actor,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      dismissedAt: dismissedAt ?? this.dismissedAt,
    );
  }
}

/// TaskMetadataGapRecord stores a source or derived insight-blocking gap.
class TaskMetadataGapRecord {
  /// Creates one metadata gap.
  const TaskMetadataGapRecord({
    required this.id,
    required this.taskId,
    required this.field,
    this.severity = 'info',
    this.blocksInsights = const <String>[],
    this.message = '',
    this.proposedAction = '',
    this.suggestedValues = const <String>[],
    this.confidence = 0,
  });

  /// Stable gap id.
  final String id;

  /// Referenced task id.
  final String taskId;

  /// Missing or low-confidence field.
  final String field;

  /// Severity such as info, medium, or high.
  final String severity;

  /// Insight ids blocked by this gap.
  final List<String> blocksInsights;

  /// User-facing gap message.
  final String message;

  /// User-facing repair action.
  final String proposedAction;

  /// Controlled suggested values.
  final List<String> suggestedValues;

  /// Gap confidence from 0 to 1.
  final double confidence;

  /// Returns this gap with a new task id.
  TaskMetadataGapRecord copyWith({String? id, String? taskId}) {
    return TaskMetadataGapRecord(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      field: field,
      severity: severity,
      blocksInsights: blocksInsights,
      message: message,
      proposedAction: proposedAction,
      suggestedValues: suggestedValues,
      confidence: confidence,
    );
  }
}

/// TaskInsightSummary stores one precomputed or derived insight count.
class TaskInsightSummary {
  /// Creates one insight summary.
  const TaskInsightSummary({
    required this.id,
    required this.title,
    this.question = '',
    this.count = 0,
    this.estimatedMinutes = 0,
    this.primaryTaskIds = const <String>[],
    this.warningCount = 0,
    this.explanation = '',
  });

  /// Stable insight id.
  final String id;

  /// User-facing title.
  final String title;

  /// User-facing question.
  final String question;

  /// Matching task count.
  final int count;

  /// Estimated human minutes represented by the insight.
  final int estimatedMinutes;

  /// Primary task ids represented by the insight.
  final List<String> primaryTaskIds;

  /// Warning count represented by the insight.
  final int warningCount;

  /// Human-readable summary explanation.
  final String explanation;
}

/// TaskStreamProjection groups tasks into fact lanes with relationship links.
class TaskStreamProjection {
  /// Creates a task stream projection.
  const TaskStreamProjection({
    this.generatedAt,
    this.lanes = const <TaskStreamLane>[],
    this.links = const <TaskStreamLink>[],
  });

  /// Projection generation timestamp.
  final DateTime? generatedAt;

  /// Ordered stream lanes.
  final List<TaskStreamLane> lanes;

  /// Visible relation links between projected stream cards.
  final List<TaskStreamLink> links;
}

/// TaskStreamLane stores one stream time column.
class TaskStreamLane {
  /// Creates a task stream lane.
  const TaskStreamLane({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.cards = const <TaskStreamCard>[],
  });

  /// Stable lane id.
  final String id;

  /// Display title.
  final String title;

  /// Secondary display text.
  final String subtitle;

  /// Projected task cards.
  final List<TaskStreamCard> cards;
}

/// TaskStreamCard stores one projected task card.
class TaskStreamCard {
  /// Creates a task stream card.
  const TaskStreamCard({
    required this.taskId,
    required this.title,
    required this.status,
    required this.priority,
    this.dueAt,
    this.scheduledAt,
    this.context = '',
    this.domain = '',
    this.project = '',
    this.owner = '',
    this.flowLane = '',
    this.streamId = '',
    this.readyNow = false,
    this.nextBestAction = '',
    this.batchScore = 0,
    this.contextSwitchCost = 0,
    this.spendLabel = '',
    this.spendScore = 0,
    this.bottleneckScore = 0,
    this.confidence = 0,
    this.explanation = '',
    this.relatedTaskCount = 0,
    this.estimateMinutes = 0,
  });

  /// Referenced task id.
  final String taskId;

  /// Display task title.
  final String title;

  /// Backend task status.
  final String status;

  /// Backend task priority.
  final String priority;

  /// Optional due timestamp.
  final DateTime? dueAt;

  /// Optional scheduled timestamp.
  final DateTime? scheduledAt;

  /// Best inferred context.
  final String context;

  /// Cross-cutting task view when supplied by the task stream backend.
  final String domain;

  /// Owning project when supplied by the task stream backend.
  final String project;

  /// Responsible person when supplied by the task stream backend.
  final String owner;

  /// Optional backend flow lane used for relation coloring.
  final String flowLane;

  /// Stable route identifier for coloring related flow edges.
  final String streamId;

  /// Whether the task can be acted on now.
  final bool readyNow;

  /// Suggested next action.
  final String nextBestAction;

  /// Batching score from 0 to 1.
  final double batchScore;

  /// Human effort or context-switch cost from 0 to 1.
  final double contextSwitchCost;

  /// Human-readable explicit spend label when supplied by the backend.
  final String spendLabel;

  /// Normalized explicit spend score from 0 to 1 when supplied by the backend.
  final double spendScore;

  /// Bottleneck score from 0 to 1.
  final double bottleneckScore;

  /// Projection confidence from 0 to 1.
  final double confidence;

  /// Human-readable placement explanation.
  final String explanation;

  /// Number of related task edges.
  final int relatedTaskCount;

  /// Estimated duration in minutes.
  final int estimateMinutes;
}

/// TaskStreamLink stores a relation that can be drawn across stream rows.
class TaskStreamLink {
  /// Creates a stream relation link.
  const TaskStreamLink({
    required this.fromTaskId,
    required this.toTaskId,
    required this.relationType,
    this.transitionType = '',
    this.streamId = '',
    this.confidence = 0,
    this.explanation = '',
  });

  /// Source projected task id.
  final String fromTaskId;

  /// Target projected task id.
  final String toTaskId;

  /// Relation type from the task graph.
  final String relationType;

  /// Relationship transition type.
  final String transitionType;

  /// Stable route identifier for coloring this transition.
  final String streamId;

  /// Relation confidence from 0 to 1.
  final double confidence;

  /// Human-readable relation explanation.
  final String explanation;
}

/// PriorityTerrainProjection stores priority terrain points.
class PriorityTerrainProjection {
  /// Creates a priority terrain projection.
  const PriorityTerrainProjection({
    this.generatedAt,
    this.points = const <PriorityTerrainPoint>[],
    this.bands = const <PriorityTerrainBand>[],
  });

  /// Projection generation timestamp.
  final DateTime? generatedAt;

  /// Projected task points.
  final List<PriorityTerrainPoint> points;

  /// Named terrain bands.
  final List<PriorityTerrainBand> bands;
}

/// PriorityTerrainPoint stores one task's terrain placement.
class PriorityTerrainPoint {
  /// Creates a priority terrain point.
  const PriorityTerrainPoint({
    required this.taskId,
    required this.title,
    required this.status,
    required this.priority,
    this.dueAt,
    this.urgencyScore = 0,
    this.valueScore = 0,
    this.effortScore = 0,
    this.riskScore = 0,
    this.rewardScore = 0,
    this.timePressureScore = 0,
    this.agentFitScore = 0,
    this.humanEffortScore = 0,
    this.terrainZone = '',
    this.x = 0,
    this.y = 0,
    this.elevation = 0,
    this.recommendedNextStep = '',
    this.confidence = 0,
    this.explanation = '',
  });

  /// Referenced task id.
  final String taskId;

  /// Display title.
  final String title;

  /// Backend task status.
  final String status;

  /// Backend task priority.
  final String priority;

  /// Optional due timestamp.
  final DateTime? dueAt;

  /// Normalized urgency score.
  final double urgencyScore;

  /// Normalized value score.
  final double valueScore;

  /// Normalized effort score.
  final double effortScore;

  /// Normalized risk score.
  final double riskScore;

  /// Derived reward or upside score.
  final double rewardScore;

  /// Derived time-pressure score.
  final double timePressureScore;

  /// Derived agent delegation fit score.
  final double agentFitScore;

  /// Derived human attention cost score.
  final double humanEffortScore;

  /// Derived terrain zone identifier.
  final String terrainZone;

  /// Normalized x coordinate.
  final double x;

  /// Normalized y coordinate.
  final double y;

  /// Combined priority score.
  final double elevation;

  /// Suggested next step.
  final String recommendedNextStep;

  /// Projection confidence from 0 to 1.
  final double confidence;

  /// Placement explanation.
  final String explanation;
}

/// PriorityTerrainBand describes one terrain region.
class PriorityTerrainBand {
  /// Creates a priority terrain band.
  const PriorityTerrainBand({
    required this.id,
    required this.title,
    this.description = '',
  });

  /// Stable band id.
  final String id;

  /// Display title.
  final String title;

  /// Region explanation.
  final String description;
}

/// TaskConstellationProjection stores spatial task graph nodes and edges.
class TaskConstellationProjection {
  /// Creates a task constellation projection.
  const TaskConstellationProjection({
    this.generatedAt,
    this.nodes = const <TaskConstellationNode>[],
    this.edges = const <TaskConstellationEdge>[],
  });

  /// Projection generation timestamp.
  final DateTime? generatedAt;

  /// Spatial task nodes.
  final List<TaskConstellationNode> nodes;

  /// Visual relation edges.
  final List<TaskConstellationEdge> edges;
}

/// TaskConstellationNode stores one spatial task node.
class TaskConstellationNode {
  /// Creates a task constellation node.
  const TaskConstellationNode({
    required this.taskId,
    required this.title,
    required this.status,
    this.category = '',
    this.timeHorizon = '',
    this.owner = '',
    this.project = '',
    this.x = 0,
    this.y = 0,
    this.size = 0,
    this.urgency = 0,
    this.confidence = 0,
    this.explanation = '',
  });

  /// Referenced task id.
  final String taskId;

  /// Display title.
  final String title;

  /// Backend task status.
  final String status;

  /// Context or category label.
  final String category;

  /// Time horizon label.
  final String timeHorizon;

  /// Responsible person or owner label.
  final String owner;

  /// Project or delivery stream label.
  final String project;

  /// Normalized x coordinate.
  final double x;

  /// Normalized y coordinate.
  final double y;

  /// Normalized node size.
  final double size;

  /// Normalized urgency.
  final double urgency;

  /// Projection confidence.
  final double confidence;

  /// Placement explanation.
  final String explanation;
}

/// TaskConstellationEdge stores one task relation edge.
class TaskConstellationEdge {
  /// Creates a task constellation edge.
  const TaskConstellationEdge({
    required this.fromTaskId,
    required this.toTaskId,
    required this.relationType,
    this.id = '',
    this.confidence = 0,
    this.source = '',
    this.factSource = '',
    this.sourceKind = '',
    this.scope = '',
    this.sensitivity = '',
    this.explanation = '',
    this.evidenceIds = const <String>[],
    this.actor = '',
    this.createdAt,
    this.updatedAt,
    this.confirmedAt,
    this.dismissedAt,
  });

  /// Stable relation id when backed by a graph fact.
  final String id;

  /// Source task id.
  final String fromTaskId;

  /// Target task id.
  final String toTaskId;

  /// Relationship type.
  final String relationType;

  /// Edge confidence.
  final double confidence;

  /// Edge source.
  final String source;

  /// Original graph fact source when the display source is a visual role.
  final String factSource;

  /// Source kind such as explicit, inferred, or system-derived.
  final String sourceKind;

  /// Access scope attached to the edge's source graph fact.
  final String scope;

  /// Sensitivity attached to the edge's source graph fact.
  final String sensitivity;

  /// Edge explanation.
  final String explanation;

  /// Evidence records that support this relation.
  final List<String> evidenceIds;

  /// Last actor.
  final String actor;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;

  /// User confirmation timestamp.
  final DateTime? confirmedAt;

  /// User dismissal timestamp.
  final DateTime? dismissedAt;
}

/// ProjectWorkspace represents the focused workspace state.
class ProjectWorkspace {
  /// Creates a focused project workspace.
  const ProjectWorkspace({
    required this.title,
    required this.subtitle,
    required this.tasks,
    required this.sources,
    required this.memoryRecords,
  });

  /// Workspace title.
  final String title;

  /// Workspace subtitle.
  final String subtitle;

  /// Project tasks and plan steps.
  final List<WorkspaceTask> tasks;

  /// Source list.
  final List<SourceItem> sources;

  /// Contextual memory records.
  final List<MemoryRecord> memoryRecords;
}

/// EndpointStatus summarizes one service connection.
class EndpointStatus {
  /// Creates a service status row.
  const EndpointStatus({
    required this.name,
    required this.url,
    required this.state,
    this.message = '',
  });

  /// Service name.
  final String name;

  /// Service URL.
  final String url;

  /// Availability state.
  final ConnectionStateKind state;

  /// Optional status detail.
  final String message;
}

/// Converts a decoded model value to a display string.
String _modelString(dynamic value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

/// Converts a decoded model value to an optional timestamp.
DateTime? _modelDateTime(dynamic value) {
  final text = _modelString(value);
  if (text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}
