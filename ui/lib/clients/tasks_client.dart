/// Graph-backed task tool client methods.
part of 'mcp_client.dart';

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
    double urgency = 0,
    String project = '',
    String location = '',
    String owner = '',
    int spendCents = 0,
    int earnCents = 0,
    int saveCents = 0,
    String currency = '',
    TaskWorkBreakdown workBreakdown = const TaskWorkBreakdown(),
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
      urgency: urgency,
      project: project,
      location: location,
      owner: owner,
      spendCents: spendCents,
      earnCents: earnCents,
      saveCents: saveCents,
      currency: currency,
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
    double? urgency,
    String? project,
    String? location,
    String? owner,
    int? spendCents,
    int? earnCents,
    int? saveCents,
    String? currency,
    TaskWorkBreakdown? workBreakdown,
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
      urgency: urgency,
      project: project,
      location: location,
      owner: owner,
      spendCents: spendCents,
      earnCents: earnCents,
      saveCents: saveCents,
      currency: currency,
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
