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

  /// Raw source record id backing the memory record.
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

  /// Source record ids cited by the page.
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
