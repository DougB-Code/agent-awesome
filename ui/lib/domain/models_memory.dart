/// Memory record, filter, capture, repair, and source data models.
part of 'models.dart';

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
    this.domainId = '',
    this.evidenceId = '',
    this.firewall = 'user',
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

  /// Memory domain that owns this record.
  final String domainId;

  /// Raw source record id backing the memory record.
  final String evidenceId;

  /// Memory firewall boundary.
  final String firewall;

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

  /// Durable raw source path.
  final String rawPath;

  /// Raw source checksum.
  final String rawChecksum;

  /// Raw source media type.
  final String rawMediaType;

  /// Optional hydrated raw source text.
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
    String? domainId,
    String? firewall,
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
      domainId: domainId ?? this.domainId,
      evidenceId: evidenceId,
      firewall: firewall ?? this.firewall,
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

  /// Source record id supporting the edge.
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
    required this.firewall,
    required this.title,
    required this.path,
    required this.status,
    required this.sourceIds,
    this.domainId = '',
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

  /// Memory firewall used to build the page.
  final String firewall;

  /// Human-readable page title.
  final String title;

  /// Durable page path.
  final String path;

  /// Lifecycle status.
  final String status;

  /// Source record ids cited by the page.
  final List<String> sourceIds;

  /// Memory domain used to build this page.
  final String domainId;

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

  /// Returns a copy annotated with domain provenance.
  CompiledMemoryPage copyWith({String? domainId}) {
    return CompiledMemoryPage(
      id: id,
      kind: kind,
      firewall: firewall,
      title: title,
      path: path,
      status: status,
      sourceIds: sourceIds,
      domainId: domainId ?? this.domainId,
      content: content,
      stale: stale,
      uncertainty: uncertainty,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// MemoryFilterState stores memory retrieval and local stewardship filters.
class MemoryFilterState {
  /// Creates memory filter state.
  const MemoryFilterState({
    this.firewall = 'user',
    this.includeGlobal = false,
    this.text = '',
    this.kinds = const <String>[],
    this.topics = const <String>[],
    this.entityIds = const <String>[],
    this.allowedSensitivities = const <String>['public', 'internal', 'private'],
    this.localStatus = '',
    this.localTrustLevel = '',
    this.limit = 100,
  });

  /// Retrieval firewall id.
  final String firewall;

  /// Whether retrieval should include globally shared records.
  final bool includeGlobal;

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
    String? firewall,
    bool? includeGlobal,
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
      firewall: firewall ?? this.firewall,
      includeGlobal: includeGlobal ?? this.includeGlobal,
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
    required this.firewall,
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

  /// Memory firewall.
  final String firewall;

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

/// MemoryExportDraft stores user-reviewed declassification text.
class MemoryExportDraft {
  /// Creates a reviewed memory-domain export draft.
  const MemoryExportDraft({
    required this.title,
    required this.content,
    required this.firewall,
    required this.sensitivity,
  });

  /// Exported record title.
  final String title;

  /// Sanitized source content approved for the destination domain.
  final String content;

  /// Destination memory firewall.
  final String firewall;

  /// Destination sensitivity label.
  final String sensitivity;
}

/// MemoryExportResult stores a backend-enforced memory export decision.
class MemoryExportResult {
  /// Creates a memory export decision result.
  const MemoryExportResult({
    required this.exported,
    this.capture = const <String, dynamic>{},
    this.safetyEvent,
  });

  /// Whether the reviewed copy was written to the destination domain.
  final bool exported;

  /// Destination capture response when an export was written.
  final Map<String, dynamic> capture;

  /// Harness-generated safety decision event.
  final MemorySafetyEvent? safetyEvent;
}

/// MemorySafetyEvent records a domain-policy decision for review.
class MemorySafetyEvent {
  /// Creates an immutable memory safety event.
  const MemorySafetyEvent({
    required this.id,
    required this.kind,
    required this.severity,
    required this.title,
    required this.detail,
    required this.sourceDomain,
    required this.targetDomain,
    this.sourceMemoryId = '',
    this.approved = false,
    this.createdAt,
  });

  /// Stable event id.
  final String id;

  /// Event category, such as blocked_export or approved_export.
  final String kind;

  /// Review severity.
  final String severity;

  /// Human-readable event title.
  final String title;

  /// Review detail for the decision.
  final String detail;

  /// Source memory domain id.
  final String sourceDomain;

  /// Destination memory domain id.
  final String targetDomain;

  /// Source memory record id when one is involved.
  final String sourceMemoryId;

  /// Whether a user explicitly approved the movement.
  final bool approved;

  /// Event creation timestamp.
  final DateTime? createdAt;
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
