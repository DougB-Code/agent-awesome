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
