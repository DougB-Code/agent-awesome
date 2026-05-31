/// Graph-backed task queue and projection runbooks for AgentAwesomeAppController.
part of 'app_controller.dart';

extension AgentAwesomeAppControllerTasks on AgentAwesomeAppController {
  /// Creates a task after local UI confirmation.
  Future<void> createTaskFromUi(
    String title, {
    String description = '',
    String status = 'open',
    String priority = 'normal',
    DateTime? dueAt,
    DateTime? scheduledAt,
    List<String> topics = const <String>[],
    bool linkSelectedMemory = false,
  }) async {
    final server = _primaryGraphServer();
    if (server == null) {
      _setEndpoint(
        'Backlog',
        ConnectionStateKind.disconnected,
        'No graph memory server',
      );
      _notifyControllerListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Creating backlog item';
    _notifyControllerListeners();
    try {
      final memoryLinks = linkSelectedMemory
          ? _selectedMemoryLinkDrafts('originated_from')
          : const <TaskMemoryLinkDraft>[];
      await _withTasksClientForGraphServer(server, (client) {
        return client.createTask(
          title: title,
          description: description,
          status: status,
          priority: priority,
          dueAt: dueAt,
          scheduledAt: scheduledAt,
          topics: topics,
          memoryLinks: memoryLinks,
          actor: _memoryActor(),
        );
      });
      await _loadTasks();
      taskSelectionKind = 'task';
      _setEndpoint(
        server.label,
        ConnectionStateKind.connected,
        'Backlog item created',
      );
      tasksMessage = 'Backlog item created';
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
    }
    _notifyControllerListeners();
  }

  /// Returns the selected task when the task inspector is active.
  WorkspaceTask? get selectedTask {
    if (taskSelectionKind != 'task') {
      return null;
    }
    if (selectedTaskId != null) {
      final indexedTask = taskInsightIndex.workspaceTaskForId(selectedTaskId);
      if (indexedTask != null) {
        return indexedTask;
      }
      for (final task in workspace.tasks) {
        if (task.id == selectedTaskId) {
          return task;
        }
      }
    }
    if (workspace.tasks.isEmpty) {
      return null;
    }
    return workspace.tasks.first;
  }

  /// Returns the selected task's graph task id.
  String get selectedGraphTaskId {
    final taskId = selectedTaskId;
    if (taskId != null && taskId.isNotEmpty) {
      return taskId;
    }
    final task = selectedTask;
    return task == null ? '' : task.id;
  }

  /// Returns explicit relation records connected to the selected task.
  List<TaskRelationRecord> get selectedTaskRelations {
    final task = selectedTask;
    if (task == null) {
      return const <TaskRelationRecord>[];
    }
    final taskId = task.id;
    return taskRelations.where((relation) {
      return relation.fromTaskId == taskId || relation.toTaskId == taskId;
    }).toList();
  }

  /// Returns the selected constellation edge when the inspector is in edge mode.
  TaskConstellationEdge? get selectedConstellationEdge {
    if (taskSelectionKind != 'constellation_edge') {
      return null;
    }
    final edge = selectedTaskConstellationEdge;
    if (edge == null) {
      return null;
    }
    if (!taskInsightIndex.isVisibleEndpoint(edge.fromTaskId) ||
        !taskInsightIndex.isVisibleEndpoint(edge.toTaskId)) {
      return null;
    }
    return edge;
  }

  /// Returns tasks after applying local queue filters.
  List<WorkspaceTask> get filteredTasks {
    return workspace.tasks.where((task) {
      final terminal = task.status == 'done' || task.status == 'canceled';
      if (!taskFilters.includeDone && terminal) {
        return false;
      }
      if (taskFilters.statuses.isNotEmpty &&
          !taskFilters.statuses.contains(task.status)) {
        return false;
      }
      if (taskFilters.priorities.isNotEmpty &&
          !taskFilters.priorities.contains(task.priority)) {
        return false;
      }
      if (taskFilters.topics.isNotEmpty &&
          !task.topics.any(taskFilters.topics.contains)) {
        return false;
      }
      if (taskFilters.overdueOnly && !task.overdue) {
        return false;
      }
      final search = taskFilters.search.trim();
      if (search.isNotEmpty &&
          !_textContains('${task.title} ${task.description}', search)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Returns all task topics in count order.
  List<String> get taskTopics {
    final counts = <String, int>{};
    for (final task in workspace.tasks) {
      for (final topic in task.topics) {
        counts[topic] = (counts[topic] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((left, right) {
        final countCompare = right.value.compareTo(left.value);
        return countCompare == 0 ? left.key.compareTo(right.key) : countCompare;
      });
    return entries.map((entry) => entry.key).toList();
  }

  /// Returns tasks created from or otherwise associated with the selected chat.
  List<WorkspaceTask> get selectedChatTasks {
    final sessionId = selectedSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return const <WorkspaceTask>[];
    }
    final associatedTaskIds = _chatTaskIds[sessionId] ?? const <String>{};
    final conversationText = messages
        .map((message) => '${message.author} ${message.text}')
        .join('\n');
    return workspace.tasks.where((task) {
      return _taskBelongsToChat(task, sessionId) ||
          associatedTaskIds.contains(task.id) ||
          _taskTitleAppearsInChat(task, conversationText);
    }).toList();
  }

  /// Applies local task filters and refreshes the task surface.
  Future<void> applyTaskFilters(TaskFilterState filters) async {
    taskFilters = filters;
    _notifyControllerListeners();
  }

  /// Refreshes graph-backed task state from memory graph servers.
  Future<void> refreshTasksFromUi() async {
    await _loadTasks();
  }

  /// Refreshes graph-backed memory records from memory MCP servers.
  Future<void> refreshMemoryFromUi() async {
    await _loadMemory();
  }

  /// Reports whether the primary memory server advertises a tool.
  bool primaryMemoryToolAvailable(String toolName) {
    return primaryMemoryToolNames.contains(toolName);
  }

  /// Selects a task for the inspector.
  void selectTask(String taskId) {
    taskSelectionKind = 'task';
    selectedTaskId = taskId;
    selectedTaskConstellationEdge = null;
    _notifyControllerListeners();
  }

  /// Selects a constellation relation edge for the inspector.
  void selectConstellationEdge(TaskConstellationEdge edge) {
    taskSelectionKind = 'constellation_edge';
    selectedTaskConstellationEdge = edge;
    selectedTaskId = null;
    _notifyControllerListeners();
  }

  /// Clears the selected constellation edge without changing task data.
  void clearConstellationEdgeSelection() {
    if (selectedTaskConstellationEdge == null &&
        taskSelectionKind != 'constellation_edge') {
      return;
    }
    selectedTaskConstellationEdge = null;
    if (taskSelectionKind == 'constellation_edge') {
      taskSelectionKind = 'task';
    }
    _notifyControllerListeners();
  }

  /// Completes a task after local UI confirmation.
  Future<void> completeTaskFromUi(String taskId) async {
    final server = _graphServerForTaskId(taskId);
    if (server == null) {
      _setEndpoint(
        'Backlog',
        ConnectionStateKind.disconnected,
        'No graph memory server',
      );
      _notifyControllerListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Completing backlog item';
    _notifyControllerListeners();
    try {
      await _withTasksClientForGraphServer(server, (client) {
        return client.completeTask(taskId, actor: _memoryActor());
      });
      await _loadTasks();
      _setEndpoint(
        server.label,
        ConnectionStateKind.connected,
        'Backlog item completed',
      );
      tasksMessage = 'Backlog item completed';
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
    }
    _notifyControllerListeners();
  }

  /// Updates mutable task fields after local UI confirmation.
  Future<void> updateTaskFromUi({
    required String taskId,
    String? title,
    String? description,
    String? status,
    String? priority,
    DateTime? dueAt,
    bool clearDueAt = false,
    DateTime? scheduledAt,
    bool clearScheduledAt = false,
    List<String>? topics,
    int? estimateMinutes,
    double? urgency,
    String? location,
    String? owner,
    TaskWorkBreakdown? workBreakdown,
  }) async {
    final server = _graphServerForTaskId(taskId);
    if (server == null) {
      _setEndpoint(
        'Backlog',
        ConnectionStateKind.disconnected,
        'No graph memory server',
      );
      _notifyControllerListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Saving backlog item';
    _notifyControllerListeners();
    try {
      await _withTasksClientForGraphServer(server, (client) {
        return client.updateTask(
          taskId: taskId,
          title: title,
          description: description,
          status: status,
          priority: priority,
          dueAt: dueAt,
          clearDueAt: clearDueAt,
          scheduledAt: scheduledAt,
          clearScheduledAt: clearScheduledAt,
          topics: topics,
          replaceTopics: topics != null,
          estimateMinutes: estimateMinutes,
          urgency: urgency,
          location: location,
          owner: owner,
          workBreakdown: workBreakdown,
          actor: _memoryActor(),
        );
      });
      selectedTaskId = taskId;
      taskSelectionKind = 'task';
      await _loadTasks();
      _setEndpoint(
        server.label,
        ConnectionStateKind.connected,
        'Backlog item saved',
      );
      tasksMessage = 'Backlog item saved';
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Creates or updates an explicit task relation from the inspector.
  Future<void> upsertTaskRelationFromUi({
    required String fromTaskId,
    required String toTaskId,
    String relationType = 'related_to',
    double confidence = 1,
    String explanation = '',
  }) async {
    await _mutateTaskGraphFromUi(
      server: _graphServerForTaskId(fromTaskId),
      selectedTaskAfter: fromTaskId,
      busyMessage: 'Saving backlog relation',
      successMessage: 'Backlog relation saved',
      action: (client) async {
        await client.upsertTaskRelation(
          fromTaskId: fromTaskId,
          toTaskId: toTaskId,
          relationType: relationType,
          confidence: confidence,
          explanation: explanation,
          actor: _memoryActor(),
        );
      },
    );
  }

  /// Deletes an explicit task relation from the inspector.
  Future<void> deleteTaskRelationFromUi(TaskRelationRecord relation) async {
    await _mutateTaskGraphFromUi(
      server: _graphServerForTaskId(relation.fromTaskId),
      selectedTaskAfter: relation.fromTaskId,
      busyMessage: 'Deleting backlog relation',
      successMessage: 'Backlog relation deleted',
      action: (client) async {
        await client.deleteTaskRelation(relation.id, actor: _memoryActor());
      },
    );
  }

  /// Cancels a task after local UI confirmation.
  Future<void> cancelTaskFromUi(String taskId) async {
    final server = _graphServerForTaskId(taskId);
    if (server == null) {
      _setEndpoint(
        'Backlog',
        ConnectionStateKind.disconnected,
        'No graph memory server',
      );
      _notifyControllerListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Canceling backlog item';
    _notifyControllerListeners();
    try {
      await _withTasksClientForGraphServer(server, (client) {
        return client.cancelTask(taskId, actor: _memoryActor());
      });
      selectedTaskId = taskId;
      await _loadTasks();
      _setEndpoint(
        server.label,
        ConnectionStateKind.connected,
        'Backlog item canceled',
      );
      tasksMessage = 'Backlog item canceled';
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Deletes a task after local UI confirmation.
  Future<void> deleteTaskFromUi(String taskId) async {
    final server = _graphServerForTaskId(taskId);
    if (server == null) {
      _setEndpoint(
        'Backlog',
        ConnectionStateKind.disconnected,
        'No graph memory server',
      );
      _notifyControllerListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Deleting backlog item';
    _notifyControllerListeners();
    try {
      await _withTasksClientForGraphServer(server, (client) {
        return client.deleteTask(taskId, actor: _memoryActor());
      });
      if (selectedTaskId == taskId) {
        selectedTaskId = null;
      }
      await _loadTasks();
      _setEndpoint(
        server.label,
        ConnectionStateKind.connected,
        'Backlog item deleted',
      );
      tasksMessage = 'Backlog item deleted';
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Links the selected memory record to a backlog item.
  Future<void> linkSelectedMemoryToTaskFromUi(String taskId) async {
    final server = _graphServerForTaskId(taskId);
    final drafts = _selectedMemoryLinkDrafts('context');
    if (server == null || drafts.isEmpty) {
      tasksMessage = 'Select a graph memory server and memory record first';
      _notifyControllerListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Linking memory to backlog item';
    _notifyControllerListeners();
    try {
      await _withTasksClientForGraphServer(server, (client) {
        return client.linkTaskMemory(taskId: taskId, link: drafts.first);
      });
      selectedTaskId = taskId;
      taskSelectionKind = 'task';
      await _loadTasks();
      _setEndpoint(
        server.label,
        ConnectionStateKind.connected,
        'Memory linked',
      );
      tasksMessage = 'Memory linked';
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
      _notifyControllerListeners();
    }
  }

  Future<void> _loadTasks() async {
    await _log('load tasks start');
    tasksBusy = true;
    tasksMessage = 'Loading backlog';
    _notifyControllerListeners();
    final tasks = <WorkspaceTask>[];
    final failures = <String>[];
    final profile = runtimeProfile;
    if (profile == null) {
      workspace = ProjectWorkspace(
        title: workspace.title,
        subtitle: workspace.subtitle,
        tasks: const <WorkspaceTask>[],
        sources: workspace.sources,
        memoryRecords: workspace.memoryRecords,
      );
      _clearTaskProjections();
      tasksBusy = false;
      tasksMessage = 'Agent runtime is not loaded';
      _notifyControllerListeners();
      return;
    }
    for (final server in profile.memoryServers) {
      await _log('load tasks via ${server.label} ${server.endpoint}');
      final client = _tasksClientFor(server);
      try {
        final serverTasks = await client.listTasks(
          filters: const TaskFilterState(statuses: <String>[]),
          includeDone: true,
          includeLinks: true,
          limit: taskFilters.limit,
        );
        final workBreakdowns = await _loadTaskWorkBreakdowns(client);
        await _log('load tasks ${server.label} returned ${serverTasks.length}');
        tasks.addAll(
          serverTasks.map((task) {
            final workBreakdown =
                _taskWorkBreakdownHasContent(task.workBreakdown)
                ? task.workBreakdown
                : workBreakdowns[task.id];
            return task.copyWith(
              sourceId: server.id,
              sourceLabel: server.label,
              workBreakdown: workBreakdown,
            );
          }),
        );
        _setEndpoint(server.label, ConnectionStateKind.connected, 'Connected');
      } catch (error) {
        await _log('load tasks failed for ${server.label}: $error');
        failures.add('${server.label}: $error');
        _setEndpoint(
          server.label,
          ConnectionStateKind.disconnected,
          error.toString(),
        );
      } finally {
        if (!identical(client, tasksClient)) {
          client.close();
        }
      }
    }
    tasks.sort(_compareTasksForWorkQueue);
    workspace = ProjectWorkspace(
      title: workspace.title,
      subtitle: workspace.subtitle,
      tasks: tasks,
      sources: workspace.sources,
      memoryRecords: workspace.memoryRecords,
    );
    if (selectedTaskId != null &&
        !tasks.any((task) => task.id == selectedTaskId)) {
      selectedTaskId = null;
    }
    await _loadTaskProjections(profile.memoryServers, workspaceTasks: tasks);
    final selectedEdge = selectedTaskConstellationEdge;
    if (selectedEdge != null &&
        (!taskInsightIndex.isVisibleEndpoint(selectedEdge.fromTaskId) ||
            !taskInsightIndex.isVisibleEndpoint(selectedEdge.toTaskId))) {
      selectedTaskConstellationEdge = null;
    }
    tasksMessage = failures.isEmpty
        ? 'Loaded ${tasks.length} backlog items'
        : failures.join(' | ');
    tasksBusy = false;
    await _log('load tasks complete tasks=${tasks.length}');
    unawaited(_loadToday(quiet: true));
    _notifyControllerListeners();
  }

  /// Loads WBS graph facts that may be absent from the task DTO.
  Future<Map<String, TaskWorkBreakdown>> _loadTaskWorkBreakdowns(
    TasksClient client,
  ) async {
    try {
      return await client.getTaskWorkBreakdowns();
    } catch (error) {
      await _log('load task WBS facts failed: $error');
      return const <String, TaskWorkBreakdown>{};
    }
  }

  /// Loads read-only task graph projections from memory graph endpoints.
  Future<void> _loadTaskProjections(
    List<McpServerRuntime> servers, {
    required List<WorkspaceTask> workspaceTasks,
  }) async {
    if (servers.isEmpty) {
      _clearTaskProjections();
      return;
    }
    final failures = <String>[];
    var projectionGraph = const TaskProjectionGraph();
    final relationRecords = <TaskRelationRecord>[];
    final server = servers.first;
    final missing = await _missingGraphProjectionTools(server);
    if (missing.isNotEmpty) {
      final message =
          '${server.label} is missing projection tools: ${missing.join(', ')}';
      failures.add(message);
      await _log(message);
    } else {
      try {
        projectionGraph = await _withTasksClientForGraphServer(server, (
          client,
        ) {
          return client.getTaskProjectionGraph();
        });
      } catch (error) {
        failures.add('${server.label} Projection Graph: $error');
      }
    }
    try {
      relationRecords.addAll(await _loadTaskRelationsForGraphServer(server));
    } catch (error) {
      failures.add('${server.label} Task Relations: $error');
    }
    taskProjectionGraph = projectionGraph;
    taskRelations = relationRecords;
    taskInsightIndex = TaskInsightIndex.build(
      workspaceTasks: workspaceTasks,
      graph: taskProjectionGraph,
    );
    taskInsightSummaries = taskInsightIndex.insightSummaries;
    taskStreamProjection = TaskInsightProjectionAdapters.stream(
      taskInsightIndex,
    );
    taskConstellationProjection = TaskInsightProjectionAdapters.constellation(
      taskInsightIndex,
    );
    taskInsightMessage = taskInsightIndex.projectionCoverageMessage;
    final messages = <String>[
      ...failures,
      if (taskInsightMessage.isNotEmpty) taskInsightMessage,
    ];
    taskProjectionMessage = messages.join(' | ');
    if (taskProjectionMessage.isNotEmpty) {
      await _log('load task projections: $taskProjectionMessage');
    }
  }

  /// Returns projection tools missing from a memory graph endpoint.
  Future<List<String>> _missingGraphProjectionTools(
    McpServerRuntime server,
  ) async {
    try {
      final names = await _withTasksClientForGraphServer(server, (client) {
        return client.listToolNames();
      });
      final available = names.toSet();
      return _requiredTaskProjectionTools
          .where((tool) => !available.contains(tool))
          .toList();
    } catch (error) {
      await _log('task projection tool check failed: $error');
      return const <String>[];
    }
  }

  /// Loads explicit task relations from one memory graph endpoint.
  Future<List<TaskRelationRecord>> _loadTaskRelationsForGraphServer(
    McpServerRuntime server,
  ) async {
    return _withTasksClientForGraphServer(server, (client) {
      return client.listTaskRelations();
    });
  }

  /// Clears read-only task projection and relation state.
  void _clearTaskProjections() {
    taskProjectionGraph = const TaskProjectionGraph();
    taskInsightIndex = TaskInsightIndex.empty;
    taskInsightSummaries = const <TaskInsightQuerySummary>[];
    taskStreamProjection = const TaskStreamProjection();
    taskConstellationProjection = const TaskConstellationProjection();
    taskProjectionMessage = '';
    taskInsightMessage = '';
    taskRelations = const <TaskRelationRecord>[];
  }

  /// Reloads tasks and associates newly created tasks with the active chat.
  Future<void> _loadTasksAfterChatTaskWrite({
    required String sessionId,
    required bool associateCreatedTask,
  }) async {
    final previousTaskIds = workspace.tasks.map((task) => task.id).toSet();
    await _loadTasks();
    if (!associateCreatedTask || sessionId.isEmpty) {
      return;
    }
    final createdTaskIds = workspace.tasks
        .where((task) => !previousTaskIds.contains(task.id))
        .map((task) => task.id)
        .toSet();
    if (createdTaskIds.isEmpty) {
      return;
    }
    final existingTaskIds = _chatTaskIds[sessionId] ?? <String>{};
    _chatTaskIds[sessionId] = <String>{...existingTaskIds, ...createdTaskIds};
    await _log(
      'associated chat $sessionId with created tasks ${createdTaskIds.join(',')}',
    );
    _notifyControllerListeners();
  }

  /// Runs a task graph mutation and refreshes derived task views.
  Future<void> _mutateTaskGraphFromUi({
    required McpServerRuntime? server,
    required String busyMessage,
    required String successMessage,
    required Future<void> Function(TasksClient client) action,
    String? selectedTaskAfter,
  }) async {
    if (server == null) {
      _setEndpoint(
        'Backlog',
        ConnectionStateKind.disconnected,
        'No graph memory server',
      );
      _notifyControllerListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = busyMessage;
    _notifyControllerListeners();
    try {
      await _withTasksClientForGraphServer(server, action);
      if (selectedTaskAfter != null && selectedTaskAfter.isNotEmpty) {
        selectedTaskId = selectedTaskAfter;
        taskSelectionKind = 'task';
      }
      await _loadTasks();
      _setEndpoint(server.label, ConnectionStateKind.connected, successMessage);
      tasksMessage = successMessage;
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Runs a task client action against one graph server and closes temp clients.
  Future<T> _withTasksClientForGraphServer<T>(
    McpServerRuntime server,
    Future<T> Function(TasksClient client) action,
  ) async {
    final client = _tasksClientFor(server);
    try {
      return await action(client);
    } finally {
      if (!identical(client, tasksClient)) {
        client.close();
      }
    }
  }

  /// Creates memory link drafts from the selected memory when domains match.
  List<TaskMemoryLinkDraft> _selectedMemoryLinkDrafts(String relationship) {
    final memory = selectedMemory;
    if (memory == null) {
      return const <TaskMemoryLinkDraft>[];
    }
    if (memory.domainId.trim().isNotEmpty &&
        memory.domainId !=
            _activeRuntimeProfile().agentMemory.defaultWriteDomain) {
      return const <TaskMemoryLinkDraft>[];
    }
    return <TaskMemoryLinkDraft>[
      TaskMemoryLinkDraft(
        memoryId: memory.id,
        memoryEvidenceId: memory.evidenceId,
        relationship: relationship,
        note: memory.title,
      ),
    ];
  }
}
