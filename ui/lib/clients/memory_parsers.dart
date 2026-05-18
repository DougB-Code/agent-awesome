/// Parsers for memory tool result payloads.
part of 'mcp_client.dart';

List<MemoryRecord> parseMemoryRecords(dynamic content) {
  final bundle = content is Map<String, dynamic>
      ? content
      : <String, dynamic>{};
  final rawRecords = bundle['primary_memory'];
  if (rawRecords is! List) {
    return const <MemoryRecord>[];
  }
  return rawRecords
      .whereType<Map<String, dynamic>>()
      .map(parseMemoryRecord)
      .toList();
}

/// Parses one memory record.
MemoryRecord parseMemoryRecord(dynamic content) {
  final record = content is Map<String, dynamic>
      ? content
      : <String, dynamic>{};
  final source = record['source'];
  final raw = record['raw'];
  final metadata = record['metadata'];
  final rawSourceSystem = source is Map<String, dynamic>
      ? stringValue(source['system'], fallback: 'source')
      : 'source';
  final sourceId = source is Map<String, dynamic>
      ? stringValue(source['id'])
      : '';
  final sourceSystem = _displayMemorySourceSystem(rawSourceSystem);
  final rawMap = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
  final metadataMap = metadata is Map<String, dynamic>
      ? metadata
      : <String, dynamic>{};
  return MemoryRecord(
    id: stringValue(record['id']),
    domainId: stringValue(
      record['domain_id'],
      fallback: stringValue(metadataMap['domain_id']),
    ),
    evidenceId: stringValue(record['evidence_id']),
    title: stringValue(record['title'], fallback: 'Untitled memory'),
    summary: stringValue(record['summary']),
    kind: stringValue(record['kind'], fallback: 'memory'),
    firewall: stringValue(record['firewall'], fallback: 'user'),
    trustLevel: stringValue(record['trust_level'], fallback: 'source_original'),
    sensitivity: stringValue(record['sensitivity'], fallback: 'private'),
    status: stringValue(record['status'], fallback: 'active'),
    subjects: stringList(record['subjects']),
    topics: stringList(record['topics']),
    entityIds: stringList(record['entity_ids']),
    entityNames: stringList(record['entity_names']),
    sourceSystem: sourceSystem,
    sourceId: sourceId,
    sourceLabel: _displayMemorySourceLabel(rawSourceSystem, sourceId),
    rawPath: stringValue(rawMap['path']),
    rawChecksum: stringValue(rawMap['checksum']),
    rawMediaType: stringValue(rawMap['media_type']),
    rawContent: stringValue(rawMap['content_text']),
    relationships: parseMemoryRelationships(record['relationships']),
    eventTime: parseOptionalDateTime(record['event_time']),
    createdAt: parseOptionalDateTime(record['created_at']),
    updatedAt: parseOptionalDateTime(record['updated_at']),
  );
}

/// Returns a product-facing source system label for memory display.
String _displayMemorySourceSystem(String value) {
  return switch (value.trim().toLowerCase()) {
    'google_adk_session' || 'adk_session' => 'chat_session',
    'agent_awesome_chat' => 'chat',
    _ => value,
  };
}

/// Returns a product-facing source record label for memory display.
String _displayMemorySourceLabel(String system, String id) {
  final displaySystem = _displayMemorySourceSystem(system);
  final label = _memorySourceDisplayName(displaySystem);
  if (id.trim().isEmpty) {
    return label;
  }
  return '$label: ${id.trim()}';
}

/// Returns a readable label for one source system value.
String _memorySourceDisplayName(String value) {
  return switch (value.trim().toLowerCase()) {
    'chat' || 'chat_session' => 'Chat',
    _ => _memoryParserTitleCase(value),
  };
}

/// Converts source system identifiers into readable fallback labels.
String _memoryParserTitleCase(String value) {
  return value
      .trim()
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

/// Parses relationship edges from memory records.
List<MemoryRelationship> parseMemoryRelationships(dynamic content) {
  if (content is! List) {
    return const <MemoryRelationship>[];
  }
  return content.whereType<Map<String, dynamic>>().map((relationship) {
    return MemoryRelationship(
      id: stringValue(relationship['id']),
      fromId: stringValue(relationship['from_id']),
      type: stringValue(relationship['type']),
      toId: stringValue(relationship['to_id']),
      sourceId: stringValue(relationship['source_id']),
      trustLevel: stringValue(
        relationship['trust_level'],
        fallback: 'source_original',
      ),
      createdAt: parseOptionalDateTime(relationship['created_at']),
    );
  }).toList();
}

/// Parses a backend-enforced memory export result.
MemoryExportResult parseMemoryExportResult(dynamic content) {
  final result = content is Map<String, dynamic>
      ? content
      : <String, dynamic>{};
  final capture = result['capture'];
  return MemoryExportResult(
    exported: boolValue(result['exported']),
    capture: capture is Map<String, dynamic> ? capture : <String, dynamic>{},
    safetyEvent: parseMemorySafetyEvent(result['safety_event']),
  );
}

/// Parses one memory safety decision event.
MemorySafetyEvent? parseMemorySafetyEvent(dynamic content) {
  if (content is! Map<String, dynamic>) {
    return null;
  }
  return MemorySafetyEvent(
    id: stringValue(content['id']),
    kind: stringValue(content['kind']),
    severity: stringValue(content['severity']),
    title: stringValue(content['title']),
    detail: stringValue(content['detail']),
    sourceDomain: stringValue(content['source_domain']),
    targetDomain: stringValue(content['target_domain']),
    sourceMemoryId: stringValue(content['source_memory_id']),
    approved: boolValue(content['approved']),
    createdAt: parseOptionalDateTime(content['created_at']),
  );
}

/// Parses a compiled page returned by the memory service.
CompiledMemoryPage parseCompiledMemoryPage(dynamic content) {
  final page = content is Map<String, dynamic> ? content : <String, dynamic>{};
  return CompiledMemoryPage(
    id: stringValue(page['id']),
    domainId: stringValue(page['domain_id']),
    kind: stringValue(page['kind'], fallback: 'entity_page'),
    firewall: stringValue(page['firewall'], fallback: 'user'),
    title: stringValue(page['title'], fallback: 'Untitled page'),
    path: stringValue(page['path']),
    status: stringValue(page['status'], fallback: 'active'),
    sourceIds: stringList(page['source_ids']),
    content: stringValue(page['content']),
    stale: page['stale'] == true,
    uncertainty: stringList(page['uncertainty']),
    createdAt: parseOptionalDateTime(page['created_at']),
    updatedAt: parseOptionalDateTime(page['updated_at']),
  );
}
