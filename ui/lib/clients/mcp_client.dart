/// Provides JSON-RPC clients for Agent Awesome MCP services.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/app_logger.dart';
import '../domain/date_formatting.dart';
import '../domain/json_value.dart';
import '../domain/models.dart';

/// McpException reports a JSON-RPC or MCP tool error.
class McpException implements Exception {
  /// Creates an MCP exception with a display message.
  const McpException(this.message);

  /// Error message.
  final String message;

  /// Formats the exception for logs and UI fallback details.
  @override
  String toString() => 'McpException: $message';
}

/// ToolRpcClient defines the common structured tool-call client contract.
abstract class ToolRpcClient {
  /// JSON-style endpoint or API base URL used by this client.
  String get endpoint;

  /// Calls a named tool and returns structured content.
  Future<dynamic> callTool(String name, [Map<String, dynamic>? arguments]);

  /// Lists tool names exposed through this client.
  Future<List<String>> listToolNames();

  /// Closes any owned HTTP resources.
  void close();
}

/// McpJsonRpcClient calls one streamable HTTP MCP JSON-RPC endpoint.
class McpJsonRpcClient implements ToolRpcClient {
  /// Creates a JSON-RPC client for an MCP endpoint.
  McpJsonRpcClient({
    required this.endpoint,
    http.Client? httpClient,
    Map<String, String> headers = const <String, String>{},
    this.logger,
  }) : headers = Map<String, String>.unmodifiable(headers),
       _http = httpClient ?? http.Client();

  /// JSON-RPC endpoint URL.
  @override
  final String endpoint;

  /// Headers applied to every MCP JSON-RPC request.
  final Map<String, String> headers;

  final http.Client _http;
  final AppLogger? logger;
  int _nextId = 1;

  /// Calls an MCP tool and returns its structured content.
  @override
  Future<dynamic> callTool(
    String name, [
    Map<String, dynamic>? arguments,
  ]) async {
    final id = _nextId++;
    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/call',
      'params': <String, dynamic>{
        'name': name,
        'arguments': arguments ?? <String, dynamic>{},
      },
    };
    await _log('POST $endpoint tools/call id=$id name=$name');
    final response = await _http.post(
      Uri.parse(endpoint),
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(payload),
    );
    await _log('POST $endpoint tools/call id=$id -> ${response.statusCode}');
    if (response.statusCode != 200) {
      throw McpException('HTTP ${response.statusCode} from $endpoint');
    }
    final content = parseToolStructuredContent(jsonDecode(response.body));
    await _log('tools/call id=$id name=$name parsed');
    return content;
  }

  /// Lists tool names exposed by this MCP endpoint.
  @override
  Future<List<String>> listToolNames() async {
    final id = _nextId++;
    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/list',
      'params': <String, dynamic>{},
    };
    await _log('POST $endpoint tools/list id=$id');
    final response = await _http.post(
      Uri.parse(endpoint),
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(payload),
    );
    await _log('POST $endpoint tools/list id=$id -> ${response.statusCode}');
    if (response.statusCode != 200) {
      throw McpException('HTTP ${response.statusCode} from $endpoint');
    }
    return parseToolNames(jsonDecode(response.body));
  }

  /// Closes the underlying HTTP client.
  @override
  void close() {
    _http.close();
  }

  Future<void> _log(String message) async {
    await logger?.write('mcp-client', message);
  }

  Map<String, String> _headers({bool contentTypeJson = false}) {
    return <String, String>{
      ...headers,
      if (contentTypeJson) 'Content-Type': 'application/json',
    };
  }
}

/// GatewayContextClient calls harness-owned context tools through the gateway.
class GatewayContextClient implements ToolRpcClient {
  /// Creates a gateway context API client.
  GatewayContextClient({
    required this.baseUrl,
    http.Client? httpClient,
    Map<String, String> headers = const <String, String>{},
    this.logger,
  }) : headers = Map<String, String>.unmodifiable(headers),
       _http = httpClient ?? http.Client();

  /// Gateway context API base URL.
  final String baseUrl;

  /// Headers applied to every gateway context API request.
  final Map<String, String> headers;

  final http.Client _http;
  final AppLogger? logger;

  @override
  String get endpoint => baseUrl;

  /// Calls one harness-owned context tool.
  @override
  Future<dynamic> callTool(
    String name, [
    Map<String, dynamic>? arguments,
  ]) async {
    final uri = _uri('/tools/call');
    await _log('POST $uri context tool name=$name');
    final response = await _http.post(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(<String, dynamic>{
        'name': name,
        'arguments': arguments ?? <String, dynamic>{},
      }),
    );
    await _log('POST $uri context tool name=$name -> ${response.statusCode}');
    if (response.statusCode != 200) {
      throw McpException('HTTP ${response.statusCode} from $uri');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const McpException('Context response was not an object');
    }
    if (decoded['error'] != null) {
      throw McpException('Context error: ${decoded['error']}');
    }
    return decoded['structuredContent'];
  }

  /// Lists context tool names exposed by the harness.
  @override
  Future<List<String>> listToolNames() async {
    final uri = _uri('/tools/list');
    await _log('GET $uri context tools/list');
    final response = await _http.get(uri, headers: _headers());
    await _log('GET $uri context tools/list -> ${response.statusCode}');
    if (response.statusCode != 200) {
      throw McpException('HTTP ${response.statusCode} from $uri');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const McpException('Context tool list was not an object');
    }
    final tools = decoded['tools'];
    if (tools is! List<dynamic>) {
      throw const McpException('Context tools field was not a list');
    }
    return tools.whereType<String>().toList();
  }

  /// Closes the underlying HTTP client.
  @override
  void close() {
    _http.close();
  }

  Uri _uri(String path) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmed$path');
  }

  Future<void> _log(String message) async {
    await logger?.write('context-client', message);
  }

  Map<String, String> _headers({bool contentTypeJson = false}) {
    return <String, String>{
      ...headers,
      if (contentTypeJson) 'Content-Type': 'application/json',
    };
  }
}

/// Extracts structuredContent from a MCP tools/call response.
dynamic parseToolStructuredContent(dynamic decoded) {
  if (decoded is! Map<String, dynamic>) {
    throw const McpException('MCP response was not an object');
  }
  if (decoded['error'] != null) {
    throw McpException('JSON-RPC error: ${decoded['error']}');
  }
  final result = decoded['result'];
  if (result is! Map<String, dynamic>) {
    throw const McpException('MCP result was not an object');
  }
  if (result['isError'] == true) {
    throw McpException('Tool returned error: ${result['structuredContent']}');
  }
  return result['structuredContent'];
}

/// Extracts tool names from a MCP tools/list response.
List<String> parseToolNames(dynamic decoded) {
  if (decoded is! Map<String, dynamic>) {
    throw const McpException('MCP response was not an object');
  }
  if (decoded['error'] != null) {
    throw McpException('JSON-RPC error: ${decoded['error']}');
  }
  final result = decoded['result'];
  if (result is! Map<String, dynamic>) {
    throw const McpException('MCP tools/list result was not an object');
  }
  final tools = result['tools'];
  if (tools is! List) {
    return const <String>[];
  }
  return tools
      .whereType<Map<String, dynamic>>()
      .map((tool) => stringValue(tool['name']))
      .where((name) => name.isNotEmpty)
      .toList();
}

/// MemoryClient wraps the user-facing memory MCP tools.
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

/// TasksClient wraps graph-backed task tools exposed by the memory MCP server.
class TasksClient {
  /// Creates a task tool client.
  TasksClient({required ToolRpcClient rpc}) : _rpc = rpc;

  final ToolRpcClient _rpc;

  /// MCP endpoint used by this client.
  String get endpoint => _rpc.endpoint;

  /// Lists MCP tool names for graph-backed task capability checks.
  Future<List<String>> listToolNames() {
    return _rpc.listToolNames();
  }

  /// Lists operational tasks.
  Future<List<WorkspaceTask>> listTasks({
    TaskFilterState filters = const TaskFilterState(),
    bool includeDone = true,
    bool includeLinks = true,
    int limit = 100,
  }) async {
    final arguments = _taskQueryArguments(
      filters: filters,
      includeDone: includeDone,
      includeLinks: includeLinks,
      limit: limit,
    );
    final content = await _rpc.callTool('list_tasks', arguments);
    return parseWorkspaceTasks(content);
  }

  /// Creates an operational task.
  Future<WorkspaceTask> createTask({
    required String title,
    String description = '',
    String status = 'open',
    String priority = 'normal',
    DateTime? dueAt,
    DateTime? scheduledAt,
    DateTime? followUpAt,
    List<String> topics = const <String>[],
    int estimateMinutes = 0,
    String energyRequired = '',
    double effort = 0,
    double value = 0,
    double urgency = 0,
    double risk = 0,
    String context = '',
    String domain = '',
    String project = '',
    String location = '',
    String owner = '',
    int spendCents = 0,
    int earnCents = 0,
    int saveCents = 0,
    String currency = '',
    String source = '',
    TaskWorkBreakdown workBreakdown = const TaskWorkBreakdown(),
    double confidence = 0,
    List<TaskMemoryLinkDraft> memoryLinks = const <TaskMemoryLinkDraft>[],
    String actor = 'agent_awesome_ui',
  }) async {
    final arguments = <String, dynamic>{
      'actor': actor,
      'title': title,
      'description': description,
      'status': status,
      'priority': priority,
    };
    if (dueAt != null) {
      arguments['due_at'] = _dateArgument(dueAt);
    }
    if (scheduledAt != null) {
      arguments['scheduled_at'] = _dateArgument(scheduledAt);
    }
    if (followUpAt != null) {
      arguments['follow_up_at'] = _dateArgument(followUpAt);
    }
    if (topics.isNotEmpty) {
      arguments['topics'] = topics;
    }
    _addTaskMetadataArguments(
      arguments,
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
      confidence: confidence,
    );
    _addTaskWorkBreakdownArgument(arguments, workBreakdown);
    if (memoryLinks.isNotEmpty) {
      arguments['memory_links'] = memoryLinks
          .map(_memoryLinkDraftPayload)
          .toList();
    }
    final content = await _rpc.callTool('create_task', arguments);
    return parseWorkspaceTask(content);
  }

  /// Updates mutable task fields.
  Future<WorkspaceTask> updateTask({
    required String taskId,
    String? title,
    String? description,
    String? status,
    String? priority,
    DateTime? dueAt,
    bool clearDueAt = false,
    DateTime? scheduledAt,
    bool clearScheduledAt = false,
    DateTime? followUpAt,
    bool clearFollowUpAt = false,
    List<String>? topics,
    bool replaceTopics = false,
    int? estimateMinutes,
    String? energyRequired,
    double? effort,
    double? value,
    double? urgency,
    double? risk,
    String? context,
    String? domain,
    String? project,
    String? location,
    String? owner,
    int? spendCents,
    int? earnCents,
    int? saveCents,
    String? currency,
    String? source,
    TaskWorkBreakdown? workBreakdown,
    double? confidence,
    String actor = 'agent_awesome_ui',
  }) async {
    final arguments = <String, dynamic>{'task_id': taskId, 'actor': actor};
    if (title != null) {
      arguments['title'] = title;
    }
    if (description != null) {
      arguments['description'] = description;
    }
    if (status != null) {
      arguments['status'] = status;
    }
    if (priority != null) {
      arguments['priority'] = priority;
    }
    if (dueAt != null) {
      arguments['due_at'] = _dateArgument(dueAt);
    }
    if (clearDueAt) {
      arguments['clear_due_at'] = true;
    }
    if (scheduledAt != null) {
      arguments['scheduled_at'] = _dateArgument(scheduledAt);
    }
    if (clearScheduledAt) {
      arguments['clear_scheduled_at'] = true;
    }
    if (followUpAt != null) {
      arguments['follow_up_at'] = _dateArgument(followUpAt);
    }
    if (clearFollowUpAt) {
      arguments['clear_follow_up_at'] = true;
    }
    if (topics != null) {
      arguments['topics'] = topics;
      arguments['replace_topics'] = replaceTopics;
    }
    _addOptionalTaskMetadataArguments(
      arguments,
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
      confidence: confidence,
    );
    if (workBreakdown != null) {
      arguments['work_breakdown'] = _taskWorkBreakdownPayload(workBreakdown);
    }
    final content = await _rpc.callTool('update_task', arguments);
    return parseWorkspaceTask(content);
  }

  /// Marks an operational task complete.
  Future<WorkspaceTask> completeTask(
    String taskId, {
    String actor = 'agent_awesome_ui',
  }) async {
    final content = await _rpc.callTool('complete_task', <String, dynamic>{
      'task_id': taskId,
      'actor': actor,
    });
    return parseWorkspaceTask(content);
  }

  /// Marks an operational task canceled.
  Future<WorkspaceTask> cancelTask(
    String taskId, {
    String actor = 'agent_awesome_ui',
  }) async {
    final content = await _rpc.callTool('cancel_task', <String, dynamic>{
      'task_id': taskId,
      'actor': actor,
    });
    return parseWorkspaceTask(content);
  }

  /// Permanently deletes an operational task.
  Future<void> deleteTask(
    String taskId, {
    String actor = 'agent_awesome_ui',
  }) async {
    await _rpc.callTool('delete_task', <String, dynamic>{
      'task_id': taskId,
      'actor': actor,
    });
  }

  /// Links memory to an operational task.
  Future<TaskMemoryLink> linkTaskMemory({
    required String taskId,
    required TaskMemoryLinkDraft link,
  }) async {
    final content = await _rpc.callTool('link_task_memory', <String, dynamic>{
      'task_id': taskId,
      'link': _memoryLinkDraftPayload(link),
    });
    return parseTaskMemoryLink(content);
  }

  /// Unlinks memory from an operational task.
  Future<void> unlinkTaskMemory({
    required String taskId,
    required String linkId,
  }) async {
    await _rpc.callTool('unlink_task_memory', <String, dynamic>{
      'task_id': taskId,
      'link_id': linkId,
    });
  }

  /// Lists explicit task relation records.
  Future<List<TaskRelationRecord>> listTaskRelations() async {
    final content = await _rpc.callTool('list_task_relations');
    return parseTaskRelations(content);
  }

  /// Creates or updates one task relation.
  Future<TaskRelationRecord> upsertTaskRelation({
    required String fromTaskId,
    required String toTaskId,
    String relationType = 'related_to',
    double confidence = 1,
    String source = 'explicit',
    String explanation = '',
    String actor = 'agent_awesome_ui',
  }) async {
    final content = await _rpc
        .callTool('upsert_task_relation', <String, dynamic>{
          'from_task_id': fromTaskId,
          'to_task_id': toTaskId,
          'type': relationType,
          'confidence': confidence,
          'note': explanation,
          'actor': actor,
        });
    return parseTaskRelation(content);
  }

  /// Deletes one task relation.
  Future<void> deleteTaskRelation(
    String relationId, {
    String actor = 'agent_awesome_ui',
  }) async {
    await _rpc.callTool('delete_task_relation', <String, dynamic>{
      'relation_id': relationId,
      'actor': actor,
    });
  }

  /// Lists first-class task commitments.
  Future<List<TaskCommitment>> listCommitments() async {
    final content = await _rpc.callTool('list_commitments');
    return parseTaskCommitments(content);
  }

  /// Creates or updates one first-class task commitment.
  Future<TaskCommitment> upsertCommitment({
    String commitmentId = '',
    required String taskId,
    List<String> people = const <String>[],
    String domain = '',
    String project = '',
    String timeWindow = '',
    String responsibility = '',
    String promiseSource = '',
    String hardness = '',
    String consequence = '',
    String actor = 'agent_awesome_ui',
  }) async {
    final arguments = <String, dynamic>{
      'task_id': taskId,
      'people': people,
      'view': domain,
      'project': project,
      'time_window': timeWindow,
      'responsibility': responsibility,
      'promise_source': promiseSource,
      'hardness': hardness,
      'consequence': consequence,
      'actor': actor,
    };
    if (commitmentId.isNotEmpty) {
      arguments['commitment_id'] = commitmentId;
    }
    final content = await _rpc.callTool('upsert_commitment', arguments);
    return parseTaskCommitment(content);
  }

  /// Deletes one first-class task commitment.
  Future<void> deleteCommitment(
    String commitmentId, {
    String actor = 'agent_awesome_ui',
  }) async {
    await _rpc.callTool('delete_commitment', <String, dynamic>{
      'commitment_id': commitmentId,
      'actor': actor,
    });
  }

  /// Lists inferred task relation suggestions.
  Future<List<TaskRelationSuggestion>> suggestTaskRelationships() async {
    final content = await _rpc.callTool('suggest_task_relationships');
    return parseTaskRelationSuggestions(content);
  }

  /// Lists inferred task metadata suggestions.
  Future<List<TaskMetadataSuggestion>> suggestTaskMetadata() async {
    final content = await _rpc.callTool('suggest_task_metadata');
    return parseTaskMetadataSuggestions(content);
  }

  /// Lists inferred task commitment suggestions.
  Future<List<TaskCommitmentSuggestion>> suggestCommitments() async {
    final content = await _rpc.callTool('suggest_commitments');
    return parseTaskCommitmentSuggestions(content);
  }

  /// Accepts one inferred task suggestion.
  Future<void> applyTaskSuggestion(
    String suggestionId, {
    String actor = 'agent_awesome_ui',
  }) async {
    await _rpc.callTool('apply_task_suggestion', <String, dynamic>{
      'suggestion_id': suggestionId,
      'actor': actor,
    });
  }

  /// Dismisses one inferred task suggestion.
  Future<void> dismissTaskSuggestion(
    String suggestionId, {
    String actor = 'agent_awesome_ui',
  }) async {
    await _rpc.callTool('dismiss_task_suggestion', <String, dynamic>{
      'suggestion_id': suggestionId,
      'actor': actor,
    });
  }

  /// Loads canonical task facts for client-owned projections.
  Future<TaskProjectionGraph> getTaskProjectionGraph() async {
    final content = await _rpc.callTool(
      'task_graph_projection',
      <String, dynamic>{
        'tasks': <String, dynamic>{'include_done': true, 'limit': 100},
        'include_facets': true,
      },
    );
    return parseTaskProjectionGraph(content);
  }

  /// Loads WBS metadata directly from graph properties.
  Future<Map<String, TaskWorkBreakdown>> getTaskWorkBreakdowns() async {
    final content = await _rpc.callTool(
      'query_context_graph',
      <String, dynamic>{
        'query':
            'FIND task RETURN id, work_breakdown ORDER BY title ASC LIMIT 100',
      },
    );
    return parseTaskWorkBreakdownRows(content);
  }

  /// Closes the underlying JSON-RPC HTTP client.
  void close() {
    _rpc.close();
  }
}

/// Parses memory records from memory retrieval bundles.
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
  final sourceSystem = source is Map<String, dynamic>
      ? stringValue(source['system'], fallback: 'source')
      : 'source';
  final sourceId = source is Map<String, dynamic>
      ? stringValue(source['id'])
      : '';
  final rawMap = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
  return MemoryRecord(
    id: stringValue(record['id']),
    evidenceId: stringValue(record['evidence_id']),
    title: stringValue(record['title'], fallback: 'Untitled memory'),
    summary: stringValue(record['summary']),
    kind: stringValue(record['kind'], fallback: 'memory'),
    scope: stringValue(record['scope'], fallback: 'user'),
    trustLevel: stringValue(record['trust_level'], fallback: 'source_original'),
    sensitivity: stringValue(record['sensitivity'], fallback: 'private'),
    status: stringValue(record['status'], fallback: 'active'),
    subjects: stringList(record['subjects']),
    topics: stringList(record['topics']),
    entityIds: stringList(record['entity_ids']),
    entityNames: stringList(record['entity_names']),
    sourceSystem: sourceSystem,
    sourceId: sourceId,
    sourceLabel: sourceId.isEmpty ? sourceSystem : '$sourceSystem:$sourceId',
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

/// Parses a compiled page returned by the memory service.
CompiledMemoryPage parseCompiledMemoryPage(dynamic content) {
  final page = content is Map<String, dynamic> ? content : <String, dynamic>{};
  return CompiledMemoryPage(
    id: stringValue(page['id']),
    kind: stringValue(page['kind'], fallback: 'entity_page'),
    scope: stringValue(page['scope'], fallback: 'user'),
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

/// Parses workspace tasks from graph-backed task tool results.
List<WorkspaceTask> parseWorkspaceTasks(dynamic content) {
  if (content is! List) {
    return const <WorkspaceTask>[];
  }
  return content
      .whereType<Map<String, dynamic>>()
      .map(parseWorkspaceTask)
      .toList();
}

/// Parses one workspace task from a graph-backed task tool result.
WorkspaceTask parseWorkspaceTask(dynamic content) {
  final task = content is Map<String, dynamic> ? content : <String, dynamic>{};
  final status = stringValue(task['status'], fallback: 'open');
  final priority = stringValue(task['priority'], fallback: 'normal');
  final dueAt = parseOptionalDateTime(task['due_at']);
  final scheduledAt = parseOptionalDateTime(task['scheduled_at']);
  final followUpAt = parseOptionalDateTime(task['follow_up_at']);
  final detailParts = <String>[statusLabel(status)];
  if (priority.isNotEmpty && priority != 'normal') {
    detailParts.add(priorityLabel(priority));
  }
  if (dueAt != null) {
    detailParts.add('Due ${formatLocalDate(dueAt)}');
  } else if (scheduledAt != null) {
    detailParts.add('Scheduled ${formatLocalDate(scheduledAt)}');
  } else if (followUpAt != null) {
    detailParts.add('Review ${formatLocalDate(followUpAt)}');
  }
  return WorkspaceTask(
    id: stringValue(task['id']),
    title: stringValue(task['title'], fallback: 'Untitled task'),
    detail: detailParts.join(' • '),
    done: status == 'done',
    description: stringValue(task['description']),
    status: status,
    priority: priority,
    dueAt: dueAt,
    scheduledAt: scheduledAt,
    followUpAt: followUpAt,
    topics: stringList(task['topics']),
    overdue: boolValue(task['overdue']),
    memoryLinks: parseTaskMemoryLinks(task['memory_links']),
    estimateMinutes: intValue(task['estimate_minutes']),
    energyRequired: stringValue(task['energy_required']),
    effort: doubleValue(task['effort']),
    value: doubleValue(task['value']),
    urgency: doubleValue(task['urgency']),
    risk: doubleValue(task['risk']),
    context: stringValue(task['context']),
    domain: stringValue(task['view']),
    project: stringValue(task['project']),
    location: stringValue(task['location']),
    owner: stringValue(task['person']),
    spendCents: intValue(task['spend_cents']),
    earnCents: intValue(task['earn_cents']),
    saveCents: intValue(task['save_cents']),
    currency: stringValue(task['currency']),
    source: stringValue(task['source']),
    workBreakdown: parseTaskWorkBreakdown(task['work_breakdown']),
    confidence: doubleValue(task['confidence']),
    createdAt: parseOptionalDateTime(task['created_at']),
    updatedAt: parseOptionalDateTime(task['updated_at']),
    completedAt: parseOptionalDateTime(task['completed_at']),
    canceledAt: parseOptionalDateTime(task['canceled_at']),
    active: status == 'open' || status == 'waiting' || status == 'blocked',
    idempotencyKey: stringValue(task['idempotency_key']),
  );
}

/// Parses WBS metadata from a graph-backed task tool result.
TaskWorkBreakdown parseTaskWorkBreakdown(dynamic content) {
  final workBreakdown = _workBreakdownMap(content);
  return TaskWorkBreakdown(
    code: stringValue(workBreakdown['code']),
    deliverable: stringValue(workBreakdown['deliverable']),
    startCriteria: stringList(workBreakdown['start_criteria']),
    acceptanceCriteria: stringList(workBreakdown['acceptance_criteria']),
    requirementRefs: stringList(workBreakdown['requirement_refs']),
    rubricRefs: stringList(workBreakdown['rubric_refs']),
    resources: parseTaskResourceRequirements(workBreakdown['resources']),
    estimatedCostCents: intValue(workBreakdown['spend_cents']),
    costCurrency: stringValue(workBreakdown['spend_currency']),
  );
}

/// Parses graph query rows containing task WBS metadata.
Map<String, TaskWorkBreakdown> parseTaskWorkBreakdownRows(dynamic content) {
  final result = content is Map<String, dynamic>
      ? content
      : <String, dynamic>{};
  final rows = result['rows'];
  if (rows is! List) {
    return const <String, TaskWorkBreakdown>{};
  }
  final values = <String, TaskWorkBreakdown>{};
  for (final row in rows.whereType<Map<String, dynamic>>()) {
    final taskId = stringValue(
      row['id'],
      fallback: stringValue(row['task_id']),
    );
    if (taskId.isEmpty) {
      continue;
    }
    final workBreakdown = parseTaskWorkBreakdown(row['work_breakdown']);
    if (taskWorkBreakdownHasContent(workBreakdown)) {
      values[taskId] = workBreakdown;
    }
  }
  return values;
}

/// Reports whether WBS metadata has useful content.
bool taskWorkBreakdownHasContent(TaskWorkBreakdown workBreakdown) {
  return workBreakdown.code.isNotEmpty ||
      workBreakdown.deliverable.isNotEmpty ||
      workBreakdown.startCriteria.isNotEmpty ||
      workBreakdown.acceptanceCriteria.isNotEmpty ||
      workBreakdown.requirementRefs.isNotEmpty ||
      workBreakdown.rubricRefs.isNotEmpty ||
      workBreakdown.resources.isNotEmpty ||
      workBreakdown.estimatedCostCents > 0 ||
      workBreakdown.costCurrency.isNotEmpty;
}

/// Converts JSON-object or JSON-string WBS payloads to maps.
Map<String, dynamic> _workBreakdownMap(dynamic content) {
  if (content is Map<String, dynamic>) {
    return content;
  }
  if (content is String && content.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return <String, dynamic>{};
    }
  }
  return <String, dynamic>{};
}

/// Parses WBS resource requirements from graph-backed task tool results.
List<TaskResourceRequirement> parseTaskResourceRequirements(dynamic content) {
  if (content is! List) {
    return const <TaskResourceRequirement>[];
  }
  return content.whereType<Map<String, dynamic>>().map((resource) {
    return TaskResourceRequirement(
      name: stringValue(resource['name']),
      type: stringValue(resource['type']),
      quantity: doubleValue(resource['quantity']),
      unit: stringValue(resource['unit']),
      estimatedCostCents: intValue(resource['spend_cents']),
      costCurrency: stringValue(resource['spend_currency']),
      notes: stringValue(resource['notes']),
    );
  }).toList();
}

/// Parses task memory links.
List<TaskMemoryLink> parseTaskMemoryLinks(dynamic content) {
  if (content is! List) {
    return const <TaskMemoryLink>[];
  }
  return content
      .whereType<Map<String, dynamic>>()
      .map(parseTaskMemoryLink)
      .toList();
}

/// Parses one task memory link.
TaskMemoryLink parseTaskMemoryLink(dynamic content) {
  final link = content is Map<String, dynamic> ? content : <String, dynamic>{};
  return TaskMemoryLink(
    id: stringValue(link['id']),
    memoryId: stringValue(link['memory_id']),
    memoryEvidenceId: stringValue(link['memory_evidence_id']),
    relationship: stringValue(link['relationship'], fallback: 'context'),
    note: stringValue(link['note']),
    createdAt: parseOptionalDateTime(link['created_at']),
  );
}

/// Parses explicit task relation records.
List<TaskRelationRecord> parseTaskRelations(dynamic content) {
  if (content is! List) {
    return const <TaskRelationRecord>[];
  }
  return content
      .whereType<Map<String, dynamic>>()
      .map(parseTaskRelation)
      .toList();
}

/// Parses one explicit task relation record.
TaskRelationRecord parseTaskRelation(dynamic content) {
  final relation = content is Map<String, dynamic>
      ? content
      : <String, dynamic>{};
  return TaskRelationRecord(
    id: stringValue(relation['id']),
    fromTaskId: stringValue(relation['from_task_id']),
    toTaskId: stringValue(relation['to_task_id']),
    relationType: stringValue(
      relation['relation_type'],
      fallback: 'related_to',
    ),
    confidence: doubleValue(relation['confidence']),
    source: stringValue(relation['source']),
    explanation: stringValue(relation['explanation']),
    actor: stringValue(relation['actor']),
    createdAt: parseOptionalDateTime(relation['created_at']),
    updatedAt: parseOptionalDateTime(relation['updated_at']),
  );
}

/// Parses inferred task relation suggestions.
List<TaskRelationSuggestion> parseTaskRelationSuggestions(dynamic content) {
  if (content is! List) {
    return const <TaskRelationSuggestion>[];
  }
  return content.whereType<Map<String, dynamic>>().map((suggestion) {
    return TaskRelationSuggestion(
      id: stringValue(suggestion['id']),
      fromTaskId: stringValue(suggestion['from_task_id']),
      toTaskId: stringValue(suggestion['to_task_id']),
      relationType: stringValue(
        suggestion['relation_type'],
        fallback: 'related_to',
      ),
      confidence: doubleValue(suggestion['confidence']),
      explanation: stringValue(suggestion['explanation']),
    );
  }).toList();
}

/// Parses inferred task metadata suggestions.
List<TaskMetadataSuggestion> parseTaskMetadataSuggestions(dynamic content) {
  if (content is! List) {
    return const <TaskMetadataSuggestion>[];
  }
  return content.whereType<Map<String, dynamic>>().map((suggestion) {
    return TaskMetadataSuggestion(
      id: stringValue(suggestion['id']),
      taskId: stringValue(suggestion['task_id']),
      estimateMinutes: intValue(suggestion['estimate_minutes']),
      energyRequired: stringValue(suggestion['energy_required']),
      effort: doubleValue(suggestion['effort']),
      value: doubleValue(suggestion['value']),
      urgency: doubleValue(suggestion['urgency']),
      risk: doubleValue(suggestion['risk']),
      context: stringValue(suggestion['context']),
      domain: stringValue(suggestion['view']),
      project: stringValue(suggestion['project']),
      location: stringValue(suggestion['location']),
      owner: stringValue(suggestion['person']),
      source: stringValue(suggestion['source']),
      confidence: doubleValue(suggestion['confidence']),
      explanation: stringValue(suggestion['explanation']),
    );
  }).toList();
}

/// Parses inferred task commitment suggestions.
List<TaskCommitmentSuggestion> parseTaskCommitmentSuggestions(dynamic content) {
  if (content is! List) {
    return const <TaskCommitmentSuggestion>[];
  }
  return content.whereType<Map<String, dynamic>>().map((suggestion) {
    return TaskCommitmentSuggestion(
      id: stringValue(suggestion['id']),
      taskId: stringValue(suggestion['task_id']),
      people: stringList(suggestion['people']),
      domain: stringValue(suggestion['view']),
      project: stringValue(suggestion['project']),
      timeWindow: stringValue(suggestion['time_window']),
      responsibility: stringValue(suggestion['responsibility']),
      promiseSource: stringValue(suggestion['promise_source']),
      hardness: stringValue(suggestion['hardness']),
      consequence: stringValue(suggestion['consequence']),
      confidence: doubleValue(suggestion['confidence']),
      explanation: stringValue(suggestion['explanation']),
    );
  }).toList();
}

/// Parses stored task commitments.
List<TaskCommitment> parseTaskCommitments(dynamic content) {
  if (content is! List) {
    return const <TaskCommitment>[];
  }
  return content
      .whereType<Map<String, dynamic>>()
      .map(parseTaskCommitment)
      .toList();
}

/// Parses one stored task commitment.
TaskCommitment parseTaskCommitment(dynamic content) {
  final commitment = content is Map<String, dynamic>
      ? content
      : <String, dynamic>{};
  return TaskCommitment(
    id: stringValue(commitment['id']),
    taskId: stringValue(commitment['task_id']),
    people: stringList(commitment['people']),
    domain: stringValue(commitment['view']),
    project: stringValue(commitment['project']),
    timeWindow: stringValue(commitment['time_window']),
    responsibility: stringValue(commitment['responsibility']),
    promiseSource: stringValue(commitment['promise_source']),
    hardness: stringValue(commitment['hardness']),
    consequence: stringValue(commitment['consequence']),
    actor: stringValue(commitment['actor']),
    createdAt: parseOptionalDateTime(commitment['created_at']),
    updatedAt: parseOptionalDateTime(commitment['updated_at']),
  );
}

/// Parses a canonical task projection graph.
TaskProjectionGraph parseTaskProjectionGraph(dynamic content) {
  final graph = content is Map<String, dynamic> ? content : <String, dynamic>{};
  final edges = graph['relations'] ?? graph['edges'];
  return TaskProjectionGraph(
    schemaVersion: stringValue(graph['schema_version'], fallback: '1.0'),
    generatedAt: parseOptionalDateTime(graph['generated_at']),
    tasks: parseTaskProjectionTasks(graph['tasks']),
    facets: parseTaskProjectionFacets(graph['facets']),
    memberships: parseTaskProjectionMemberships(graph['memberships']),
    edges: parseTaskProjectionEdges(edges),
    commitments: parseTaskCommitments(graph['commitments']),
    metadataGaps: parseTaskMetadataGapRecords(graph['metadata_gaps']),
    insightSummaries: parseTaskInsightSummaries(graph['insight_summaries']),
    quality: parseTaskProjectionQuality(graph['quality']),
  );
}

/// Parses graph quality metrics.
TaskProjectionQuality parseTaskProjectionQuality(dynamic content) {
  final quality = content is Map<String, dynamic>
      ? content
      : <String, dynamic>{};
  return TaskProjectionQuality(
    schemaConfidence: doubleValue(quality['schema_confidence']),
    metadataCompleteness: doubleValue(quality['metadata_completeness']),
    relationCoverage: doubleValue(quality['relation_coverage']),
    warnings: stringList(quality['warnings']),
  );
}

/// Parses canonical projected tasks.
List<TaskProjectionTask> parseTaskProjectionTasks(dynamic content) {
  if (content is! List) {
    return const <TaskProjectionTask>[];
  }
  return content.whereType<Map<String, dynamic>>().map((task) {
    final raw = jsonObject(task['raw']);
    final normalized = jsonObject(task['normalized']);
    final quality = jsonObject(task['quality']);
    return TaskProjectionTask(
      taskId: stringValue(task['task_id'], fallback: stringValue(task['id'])),
      title: stringValue(
        task['title'],
        fallback: stringValue(raw['title'], fallback: 'Untitled task'),
      ),
      description: stringValue(
        task['description'],
        fallback: stringValue(raw['description']),
      ),
      status: stringValue(
        task['status'],
        fallback: stringValue(
          normalized['status'],
          fallback: stringValue(raw['status'], fallback: 'open'),
        ),
      ),
      priority: stringValue(
        task['priority'],
        fallback: stringValue(
          normalized['priority'],
          fallback: stringValue(raw['priority'], fallback: 'normal'),
        ),
      ),
      dueAt: parseOptionalDateTime(task['due_at'] ?? raw['due_at']),
      scheduledAt: parseOptionalDateTime(
        task['scheduled_at'] ?? raw['scheduled_at'],
      ),
      topics: stringList(task['topics']).isNotEmpty
          ? stringList(task['topics'])
          : stringList(raw['topics']),
      estimateMinutes: intValue(
        task['estimate_minutes'],
        fallback: intValue(raw['estimate_minutes']),
      ),
      energyRequired: stringValue(
        task['energy_required'],
        fallback: stringValue(raw['energy_required']),
      ),
      context: stringValue(
        task['context'],
        fallback: stringValue(raw['context']),
      ),
      domain: stringValue(task['view'], fallback: stringValue(raw['view'])),
      project: stringValue(
        task['project'],
        fallback: stringValue(raw['project']),
      ),
      location: stringValue(
        task['location'],
        fallback: stringValue(raw['location']),
      ),
      owner: stringValue(task['person'], fallback: stringValue(raw['person'])),
      source: stringValue(task['source'], fallback: stringValue(raw['source'])),
      workBreakdown: parseTaskWorkBreakdown(
        task['work_breakdown'] ?? raw['work_breakdown'],
      ),
      projectId: stringValue(normalized['project_id']),
      workstreamId: stringValue(normalized['workstream_id']),
      valueType: stringValue(normalized['value_type']),
      obligationLevel: stringValue(normalized['obligation_level']),
      consequenceSeverity: stringValue(normalized['consequence_severity']),
      agentSafety: stringValue(normalized['agent_safety']),
      handoffReadiness: stringValue(normalized['handoff_readiness']),
      dependencyState: stringValue(normalized['dependency_state']),
      scores: parseTaskProjectionScores(task['scores']),
      scoreComponents: parseTaskScoreComponents(task['score_components']),
      facetIds: stringList(task['facet_ids']),
      evidenceIds: stringList(task['evidence_ids']),
      missingFields: stringList(quality['missing_fields']),
      confidence: doubleValue(
        task['confidence'],
        fallback: doubleValue(quality['confidence']),
      ),
      explanation: stringValue(
        task['explanation'],
        fallback: stringValue(quality['explanation']),
      ),
    );
  }).toList();
}

/// Parses derived task projection scores.
TaskProjectionScores parseTaskProjectionScores(dynamic content) {
  final scores = content is Map<String, dynamic>
      ? content
      : <String, dynamic>{};
  return TaskProjectionScores(
    reward: doubleValue(scores['reward']),
    pressure: doubleValue(scores['pressure']),
    risk: doubleValue(scores['risk']),
    timePressure: doubleValue(scores['time_pressure']),
    humanEffort: doubleValue(scores['human_effort']),
    agentFit: doubleValue(scores['agent_fit']),
    obligation: doubleValue(scores['obligation']),
    consequenceSeverity: doubleValue(
      scores['consequence_severity'],
      fallback: doubleValue(scores['consequence']),
    ),
    agentSafety: doubleValue(scores['agent_safety']),
    handoffReadiness: doubleValue(scores['handoff_readiness']),
    contextReadiness: doubleValue(scores['context_readiness']),
    humanJudgmentNeed: doubleValue(scores['human_judgment_need']),
    downstreamValue: doubleValue(scores['downstream_value']),
    blockerEffort: doubleValue(scores['blocker_effort']),
    unblockLeverage: doubleValue(scores['unblock_leverage']),
    metadataCompleteness: doubleValue(scores['metadata_completeness']),
    staleness: doubleValue(scores['staleness']),
    commitmentHardness: doubleValue(scores['commitment_hardness']),
    elevation: doubleValue(scores['elevation']),
    terrainZone: stringValue(scores['terrain_zone']),
  );
}

/// Parses score explanations keyed by score name.
Map<String, List<TaskScoreComponent>> parseTaskScoreComponents(
  dynamic content,
) {
  if (content is! Map<String, dynamic>) {
    return const <String, List<TaskScoreComponent>>{};
  }
  final output = <String, List<TaskScoreComponent>>{};
  for (final entry in content.entries) {
    final value = entry.value;
    if (value is! List) {
      continue;
    }
    final components = value.whereType<Map<String, dynamic>>().map((
      Map<String, dynamic> component,
    ) {
      return TaskScoreComponent(
        name: stringValue(component['name']),
        value: doubleValue(component['value']),
        explanation: stringValue(component['explanation']),
      );
    }).toList();
    output[entry.key] = components;
  }
  return output;
}

/// Parses reusable task projection facets.
List<TaskProjectionFacet> parseTaskProjectionFacets(dynamic content) {
  if (content is! List) {
    return const <TaskProjectionFacet>[];
  }
  return content.whereType<Map<String, dynamic>>().map((facet) {
    return TaskProjectionFacet(
      id: stringValue(facet['id']),
      dimension: stringValue(facet['dimension']),
      label: stringValue(facet['label']),
      description: stringValue(facet['description']),
      source: stringValue(facet['source']),
      version: stringValue(facet['version']),
      sourceField: stringValue(facet['source_field']),
      provenance: stringValue(facet['provenance']),
      confidence: doubleValue(facet['confidence']),
    );
  }).toList();
}

/// Parses task projection facet memberships.
List<TaskProjectionMembership> parseTaskProjectionMemberships(dynamic content) {
  if (content is! List) {
    return const <TaskProjectionMembership>[];
  }
  return content.whereType<Map<String, dynamic>>().map((membership) {
    return TaskProjectionMembership(
      taskId: stringValue(membership['task_id']),
      facetId: stringValue(membership['facet_id']),
      dimension: stringValue(membership['dimension']),
      source: stringValue(membership['source']),
      confidence: doubleValue(membership['confidence']),
      explanation: stringValue(membership['explanation']),
    );
  }).toList();
}

/// Parses sparse task projection edges.
List<TaskProjectionEdge> parseTaskProjectionEdges(dynamic content) {
  if (content is! List) {
    return const <TaskProjectionEdge>[];
  }
  return content.whereType<Map<String, dynamic>>().map((edge) {
    return TaskProjectionEdge(
      id: stringValue(edge['id']),
      fromTaskId: stringValue(edge['from_task_id']),
      toTaskId: stringValue(edge['to_task_id']),
      relationType: stringValue(
        edge['relation_type'],
        fallback: stringValue(edge['type']),
      ),
      directionSemantics: stringValue(edge['direction_semantics']),
      source: stringValue(edge['source']),
      sourceKind: stringValue(edge['source_kind']),
      scope: stringValue(edge['scope']),
      sensitivity: stringValue(edge['sensitivity']),
      confidence: doubleValue(edge['confidence']),
      explanation: stringValue(edge['explanation']),
      evidenceIds: stringList(edge['evidence_ids']),
      actor: stringValue(edge['actor']),
      createdAt: parseOptionalDateTime(edge['created_at']),
      updatedAt: parseOptionalDateTime(edge['updated_at']),
      confirmedAt: parseOptionalDateTime(edge['confirmed_at']),
      dismissedAt: parseOptionalDateTime(edge['dismissed_at']),
    );
  }).toList();
}

/// Parses source-provided metadata gaps.
List<TaskMetadataGapRecord> parseTaskMetadataGapRecords(dynamic content) {
  if (content is! List) {
    return const <TaskMetadataGapRecord>[];
  }
  return content.whereType<Map<String, dynamic>>().map((gap) {
    return TaskMetadataGapRecord(
      id: stringValue(gap['id']),
      taskId: stringValue(gap['task_id']),
      field: stringValue(gap['field']),
      severity: stringValue(gap['severity'], fallback: 'info'),
      blocksInsights: stringList(gap['blocks_insights']),
      message: stringValue(gap['message']),
      proposedAction: stringValue(gap['proposed_action']),
      suggestedValues: stringList(gap['suggested_values']),
      confidence: doubleValue(gap['confidence']),
    );
  }).toList();
}

/// Parses source-provided insight summaries.
List<TaskInsightSummary> parseTaskInsightSummaries(dynamic content) {
  if (content is! List) {
    return const <TaskInsightSummary>[];
  }
  return content.whereType<Map<String, dynamic>>().map((summary) {
    return TaskInsightSummary(
      id: stringValue(summary['id']),
      title: stringValue(summary['title']),
      question: stringValue(summary['question']),
      count: intValue(summary['count']),
      estimatedMinutes: intValue(summary['estimated_minutes']),
      primaryTaskIds: stringList(summary['primary_task_ids']),
      warningCount: intValue(summary['warning_count']),
      explanation: stringValue(summary['explanation']),
    );
  }).toList();
}

/// Converts backend task status values into compact display labels.
String statusLabel(String status) {
  switch (status) {
    case 'done':
      return 'Done';
    case 'waiting':
      return 'Waiting';
    case 'blocked':
      return 'Blocked';
    case 'canceled':
      return 'Canceled';
    default:
      return 'Open';
  }
}

/// Converts backend task priority values into compact display labels.
String priorityLabel(String priority) {
  switch (priority) {
    case 'urgent':
      return 'Urgent';
    case 'high':
      return 'High';
    case 'low':
      return 'Low';
    default:
      return 'Normal';
  }
}

/// Builds task query arguments while omitting empty filters.
Map<String, dynamic> _taskQueryArguments({
  required TaskFilterState filters,
  required bool includeDone,
  required bool includeLinks,
  required int limit,
}) {
  final arguments = <String, dynamic>{
    'include_done': includeDone,
    'include_links': includeLinks,
    'limit': limit,
  };
  if (filters.statuses.isNotEmpty) {
    arguments['statuses'] = filters.statuses;
  }
  if (filters.priorities.isNotEmpty) {
    arguments['priorities'] = filters.priorities;
  }
  if (filters.topics.isNotEmpty) {
    arguments['topics'] = filters.topics;
  }
  if (filters.search.trim().isNotEmpty) {
    arguments['search'] = filters.search.trim();
  }
  if (filters.overdueOnly) {
    arguments['overdue_only'] = true;
  }
  return arguments;
}

/// Adds non-empty task graph metadata arguments to a create payload.
void _addTaskMetadataArguments(
  Map<String, dynamic> arguments, {
  required int estimateMinutes,
  required String energyRequired,
  required double effort,
  required double value,
  required double urgency,
  required double risk,
  required String context,
  required String domain,
  required String project,
  required String location,
  required String owner,
  required int spendCents,
  required int earnCents,
  required int saveCents,
  required String currency,
  required String source,
  required double confidence,
}) {
  if (estimateMinutes > 0) {
    arguments['estimate_minutes'] = estimateMinutes;
  }
  if (energyRequired.trim().isNotEmpty) {
    arguments['energy_required'] = energyRequired.trim();
  }
  if (effort > 0) {
    arguments['effort'] = effort;
  }
  if (value > 0) {
    arguments['value'] = value;
  }
  if (urgency > 0) {
    arguments['urgency'] = urgency;
  }
  if (risk > 0) {
    arguments['risk'] = risk;
  }
  if (context.trim().isNotEmpty) {
    arguments['context'] = context.trim();
  }
  if (domain.trim().isNotEmpty) {
    arguments['view'] = domain.trim();
  }
  if (project.trim().isNotEmpty) {
    arguments['project'] = project.trim();
  }
  if (location.trim().isNotEmpty) {
    arguments['location'] = location.trim();
  }
  if (owner.trim().isNotEmpty) {
    arguments['person'] = owner.trim();
  }
  if (spendCents > 0) {
    arguments['spend_cents'] = spendCents;
  }
  if (earnCents > 0) {
    arguments['earn_cents'] = earnCents;
  }
  if (saveCents > 0) {
    arguments['save_cents'] = saveCents;
  }
  if (currency.trim().isNotEmpty) {
    arguments['currency'] = currency.trim();
  }
  if (source.trim().isNotEmpty) {
    arguments['source'] = source.trim();
  }
  if (confidence > 0) {
    arguments['confidence'] = confidence;
  }
}

/// Adds WBS metadata to a create payload when any WBS field exists.
void _addTaskWorkBreakdownArgument(
  Map<String, dynamic> arguments,
  TaskWorkBreakdown workBreakdown,
) {
  final payload = _taskWorkBreakdownPayload(workBreakdown);
  if (payload.isNotEmpty) {
    arguments['work_breakdown'] = payload;
  }
}

/// Adds nullable task graph metadata arguments to an update payload.
void _addOptionalTaskMetadataArguments(
  Map<String, dynamic> arguments, {
  required int? estimateMinutes,
  required String? energyRequired,
  required double? effort,
  required double? value,
  required double? urgency,
  required double? risk,
  required String? context,
  required String? domain,
  required String? project,
  required String? location,
  required String? owner,
  required int? spendCents,
  required int? earnCents,
  required int? saveCents,
  required String? currency,
  required String? source,
  required double? confidence,
}) {
  if (estimateMinutes != null) {
    arguments['estimate_minutes'] = estimateMinutes;
  }
  if (energyRequired != null) {
    arguments['energy_required'] = energyRequired.trim();
  }
  if (effort != null) {
    arguments['effort'] = effort;
  }
  if (value != null) {
    arguments['value'] = value;
  }
  if (urgency != null) {
    arguments['urgency'] = urgency;
  }
  if (risk != null) {
    arguments['risk'] = risk;
  }
  if (context != null) {
    arguments['context'] = context.trim();
  }
  if (domain != null) {
    arguments['view'] = domain.trim();
  }
  if (project != null) {
    arguments['project'] = project.trim();
  }
  if (location != null) {
    arguments['location'] = location.trim();
  }
  if (owner != null) {
    arguments['person'] = owner.trim();
  }
  if (spendCents != null) {
    arguments['spend_cents'] = spendCents;
  }
  if (earnCents != null) {
    arguments['earn_cents'] = earnCents;
  }
  if (saveCents != null) {
    arguments['save_cents'] = saveCents;
  }
  if (currency != null) {
    arguments['currency'] = currency.trim();
  }
  if (source != null) {
    arguments['source'] = source.trim();
  }
  if (confidence != null) {
    arguments['confidence'] = confidence;
  }
}

/// Converts WBS metadata to graph-backed task tool arguments.
Map<String, dynamic> _taskWorkBreakdownPayload(
  TaskWorkBreakdown workBreakdown,
) {
  final payload = <String, dynamic>{};
  if (workBreakdown.code.trim().isNotEmpty) {
    payload['code'] = workBreakdown.code.trim();
  }
  if (workBreakdown.deliverable.trim().isNotEmpty) {
    payload['deliverable'] = workBreakdown.deliverable.trim();
  }
  if (workBreakdown.startCriteria.isNotEmpty) {
    payload['start_criteria'] = workBreakdown.startCriteria;
  }
  if (workBreakdown.acceptanceCriteria.isNotEmpty) {
    payload['acceptance_criteria'] = workBreakdown.acceptanceCriteria;
  }
  if (workBreakdown.requirementRefs.isNotEmpty) {
    payload['requirement_refs'] = workBreakdown.requirementRefs;
  }
  if (workBreakdown.rubricRefs.isNotEmpty) {
    payload['rubric_refs'] = workBreakdown.rubricRefs;
  }
  if (workBreakdown.resources.isNotEmpty) {
    payload['resources'] = workBreakdown.resources
        .map(_taskResourceRequirementPayload)
        .toList();
  }
  if (workBreakdown.estimatedCostCents > 0) {
    payload['spend_cents'] = workBreakdown.estimatedCostCents;
  }
  if (workBreakdown.costCurrency.trim().isNotEmpty) {
    payload['spend_currency'] = workBreakdown.costCurrency.trim();
  }
  return payload;
}

/// Converts one WBS resource requirement to graph-backed task tool arguments.
Map<String, dynamic> _taskResourceRequirementPayload(
  TaskResourceRequirement resource,
) {
  final payload = <String, dynamic>{'name': resource.name.trim()};
  if (resource.type.trim().isNotEmpty) {
    payload['type'] = resource.type.trim();
  }
  if (resource.quantity > 0) {
    payload['quantity'] = resource.quantity;
  }
  if (resource.unit.trim().isNotEmpty) {
    payload['unit'] = resource.unit.trim();
  }
  if (resource.estimatedCostCents > 0) {
    payload['spend_cents'] = resource.estimatedCostCents;
  }
  if (resource.costCurrency.trim().isNotEmpty) {
    payload['spend_currency'] = resource.costCurrency.trim();
  }
  if (resource.notes.trim().isNotEmpty) {
    payload['notes'] = resource.notes.trim();
  }
  return payload;
}

/// Formats a timestamp for graph-backed task tool arguments.
String _dateArgument(DateTime value) {
  return value.toUtc().toIso8601String();
}

/// Converts a memory link draft to graph-backed task tool arguments.
Map<String, dynamic> _memoryLinkDraftPayload(TaskMemoryLinkDraft draft) {
  final payload = <String, dynamic>{'relationship': draft.relationship};
  if (draft.memoryId.isNotEmpty) {
    payload['memory_id'] = draft.memoryId;
  }
  if (draft.memoryEvidenceId.isNotEmpty) {
    payload['memory_evidence_id'] = draft.memoryEvidenceId;
  }
  if (draft.note.isNotEmpty) {
    payload['note'] = draft.note;
  }
  return payload;
}
