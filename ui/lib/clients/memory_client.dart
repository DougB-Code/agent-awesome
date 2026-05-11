/// User-facing memory tool client methods.
part of 'mcp_client.dart';

class MemoryClient {
  /// Creates a memory tool client.
  MemoryClient({required ToolRpcClient rpc}) : _rpc = rpc;

  final ToolRpcClient _rpc;

  /// MCP endpoint used by this client.
  String get endpoint => _rpc.endpoint;

  /// Lists MCP tool names for endpoint capability checks.
  Future<List<String>> listToolNames() {
    return _rpc.listToolNames();
  }

  /// Searches memory records for the memory panel and source list.
  Future<List<MemoryRecord>> searchMemory({
    String scope = 'user',
    String text = '',
    List<String> kinds = const <String>[],
    List<String> topics = const <String>[],
    List<String> entityIds = const <String>[],
    List<String> allowedSensitivities = const <String>[
      'public',
      'internal',
      'private',
    ],
    int limit = 20,
  }) async {
    final content = await _rpc.callTool('search_memory', <String, dynamic>{
      'scope': scope,
      'text': text,
      'kinds': kinds,
      'topics': topics,
      'entity_ids': entityIds,
      'allowed_sensitivities': allowedSensitivities,
      'limit': limit,
    });
    return parseMemoryRecords(content);
  }

  /// Searches source-backed text records.
  Future<List<MemoryRecord>> searchSources({
    String scope = 'user',
    String text = '',
    List<String> kinds = const <String>[],
    List<String> topics = const <String>[],
    List<String> entityIds = const <String>[],
    List<String> allowedSensitivities = const <String>[
      'public',
      'internal',
      'private',
    ],
    int limit = 20,
  }) async {
    final content = await _rpc.callTool('search_sources', <String, dynamic>{
      'scope': scope,
      'text': text,
      'kinds': kinds,
      'topics': topics,
      'entity_ids': entityIds,
      'allowed_sensitivities': allowedSensitivities,
      'limit': limit,
    });
    return parseMemoryRecords(content);
  }

  /// Saves a carefully reviewed memory candidate.
  Future<dynamic> saveMemoryCandidate({
    required MemoryCaptureDraft draft,
    String actor = 'agent_awesome_ui',
    String idempotencyKey = '',
  }) {
    return _rpc.callTool('save_memory_candidate', <String, dynamic>{
      'actor': actor,
      'content': draft.content,
      'title': draft.title,
      'media_type': draft.mediaType,
      'source': <String, dynamic>{
        'system': draft.sourceSystem,
        'id': draft.sourceId,
      },
      'kind': draft.kind,
      'scope': draft.scope,
      'trust_level': draft.trustLevel,
      'sensitivity': draft.sensitivity,
      'subjects': draft.subjects,
      'topics': draft.topics,
      'entity_names': draft.entityNames,
      'idempotency_key': idempotencyKey,
    });
  }

  /// Loads or builds a compiled entity page.
  Future<CompiledMemoryPage> loadEntityPage({
    required String scope,
    required String entityId,
    required String title,
  }) async {
    final content = await _rpc.callTool('load_entity_page', <String, dynamic>{
      'scope': scope,
      'entity_id': entityId,
      'title': title,
    });
    return parseCompiledMemoryPage(content);
  }

  /// Loads or builds a source-backed timeline.
  Future<CompiledMemoryPage> loadTimeline({
    required String scope,
    required String topic,
    String entityId = '',
  }) async {
    final content = await _rpc.callTool('load_timeline', <String, dynamic>{
      'scope': scope,
      'topic': topic,
      'entity_id': entityId,
    });
    return parseCompiledMemoryPage(content);
  }

  /// Refreshes a compiled entity page or timeline.
  Future<CompiledMemoryPage> refreshCompiledPage({
    required String kind,
    required String scope,
    required String title,
    String entityId = '',
    String topic = '',
    String actor = 'agent_awesome_ui',
  }) async {
    final content = await _rpc
        .callTool('refresh_compiled_page', <String, dynamic>{
          'actor': actor,
          'kind': kind,
          'scope': scope,
          'title': title,
          'entity_id': entityId,
          'topic': topic,
        });
    return parseCompiledMemoryPage(content);
  }

  /// Applies explicit memory metadata repairs.
  Future<MemoryRecord> repairMemoryRecord({
    required MemoryRepairDraft draft,
    String actor = 'agent_awesome_ui',
  }) async {
    final arguments = <String, dynamic>{
      'actor': actor,
      'memory_id': draft.memoryId,
    };
    if (draft.title != null) {
      arguments['title'] = draft.title;
    }
    if (draft.summary != null) {
      arguments['summary'] = draft.summary;
    }
    if (draft.kind != null) {
      arguments['kind'] = draft.kind;
    }
    if (draft.sensitivity != null) {
      arguments['sensitivity'] = draft.sensitivity;
    }
    if (draft.status != null) {
      arguments['status'] = draft.status;
    }
    if (draft.subjects != null) {
      arguments['subjects'] = draft.subjects;
    }
    if (draft.topics != null) {
      arguments['topics'] = draft.topics;
    }
    if (draft.entityNames != null) {
      arguments['entity_names'] = draft.entityNames;
    }
    final content = await _rpc.callTool('repair_memory_record', arguments);
    return parseMemoryRecord(content);
  }

  /// Stores a user correction as new source-backed memory.
  Future<dynamic> submitMemoryCorrection({
    required String memoryId,
    required String text,
    required String scope,
    String actor = 'agent_awesome_ui',
  }) {
    return _rpc.callTool('submit_memory_correction', <String, dynamic>{
      'actor': actor,
      'memory_id': memoryId,
      'scope': scope,
      'text': text,
    });
  }

  /// Closes the underlying JSON-RPC HTTP client.
  void close() {
    _rpc.close();
  }
}
