/// Backlog screen-command workflows for AgentAwesomeAppController.
part of 'app_controller.dart';

extension AgentAwesomeAppControllerScreenCommands on AgentAwesomeAppController {
  /// Runs a structured AI command against the Backlog screen.
  Future<void> runBacklogScreenCommand({
    required String text,
    required String scopeLabel,
  }) async {
    final command = text.trim();
    if (command.isEmpty || screenCommandBusy) {
      return;
    }
    screenCommandBusy = true;
    screenCommandMessage = 'Planning screen changes';
    _notifyControllerListeners();
    try {
      final profile = runtimeProfile;
      if (profile == null) {
        throw StateError('Agent runtime is not loaded');
      }
      final modelConfigContent = await _readRuntimeModelConfigContent(
        profile.harness.modelConfigPath,
      );
      final planned = await screenCommandPlanner.planBacklogCommand(
        modelConfigContent: modelConfigContent,
        command: command,
        snapshot: _backlogScreenSnapshot(scopeLabel),
      );
      if (planned.intent != ScreenCommandIntent.change) {
        activeScreenCommandRun = planned;
        assistantChatPanelOpen = true;
        backlogChatPanelOpen = true;
        backlogReviewPanelOpen = false;
        screenCommandMessage = planned.message.trim().isEmpty
            ? 'Opening chat for this screen'
            : planned.message.trim();
        _notifyControllerListeners();
        await sendUserMessage(
          buildScreenCommandPrompt(
            scopeLabel: scopeLabel,
            userText: command,
            relevantIds: _screenCommandRelevantIds(),
          ),
          displayText: command,
        );
        return;
      }
      final prepared = _preparedBacklogScreenRun(planned);
      activeScreenCommandRun = prepared;
      backlogReviewPanelOpen = prepared.changes.isNotEmpty;
      screenCommandMessage = _screenRunSummary(prepared);
      _notifyControllerListeners();
      await _applyAutoScreenChanges(prepared);
    } catch (error) {
      activeScreenCommandRun = ScreenCommandRun(
        id: 'screen-run-${DateTime.now().microsecondsSinceEpoch}',
        command: command,
        intent: ScreenCommandIntent.change,
        message: error.toString(),
        changes: const <ScreenChange>[],
        createdAt: DateTime.now(),
      );
      backlogReviewPanelOpen = true;
      screenCommandMessage = error.toString();
      await _log('backlog screen command failed: $error');
    } finally {
      screenCommandBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Opens the Backlog review side panel.
  void openBacklogReviewPanel() {
    backlogReviewPanelOpen = true;
    _notifyControllerListeners();
  }

  /// Opens the Backlog inspector side panel.
  void openBacklogInspectorPanel() {
    backlogReviewPanelOpen = false;
    _notifyControllerListeners();
  }

  /// Closes the auxiliary Backlog chat panel.
  void closeBacklogChatPanel() {
    assistantChatPanelOpen = false;
    backlogChatPanelOpen = false;
    _notifyControllerListeners();
  }

  /// Selects a task from the queue and restores the inspector pane.
  void inspectBacklogTask(String taskId) {
    taskSelectionKind = 'task';
    selectedTaskId = taskId;
    selectedTaskConstellationEdge = null;
    backlogReviewPanelOpen = false;
    _notifyControllerListeners();
  }

  /// Focuses a review-panel change in the Backlog queue.
  void focusBacklogScreenChange(String changeId) {
    final change = screenChangeForId(changeId);
    if (change == null) {
      return;
    }
    focusedScreenChangeId = changeId;
    focusedBacklogTaskId = change.target.taskId;
    if (focusedBacklogTaskId.isNotEmpty) {
      taskSelectionKind = 'task';
      selectedTaskId = focusedBacklogTaskId;
      selectedTaskConstellationEdge = null;
    }
    _notifyControllerListeners();
  }

  /// Clears the pending Backlog queue focus request.
  void clearBacklogScreenFocus() {
    if (focusedBacklogTaskId.isEmpty && focusedScreenChangeId.isEmpty) {
      return;
    }
    focusedBacklogTaskId = '';
    focusedScreenChangeId = '';
    _notifyControllerListeners();
  }

  /// Returns the active screen changes for one backlog task.
  List<ScreenChange> screenChangesForTask(String taskId) {
    final run = activeScreenCommandRun;
    if (run == null || taskId.isEmpty) {
      return const <ScreenChange>[];
    }
    return run.changes.where((change) {
      return change.target.taskId == taskId &&
          change.status != ScreenChangeStatus.rejected &&
          change.status != ScreenChangeStatus.undone;
    }).toList();
  }

  /// Returns one active screen change by id.
  ScreenChange? screenChangeForId(String changeId) {
    final run = activeScreenCommandRun;
    if (run == null) {
      return null;
    }
    for (final change in run.changes) {
      if (change.id == changeId) {
        return change;
      }
    }
    return null;
  }

  /// Applies one reviewable Backlog screen change.
  Future<void> applyScreenChangeFromUi(String changeId) async {
    final change = screenChangeForId(changeId);
    if (change == null ||
        change.status != ScreenChangeStatus.proposed ||
        change.safety == ScreenChangeSafety.rejected) {
      return;
    }
    await _applyBacklogScreenChange(change);
  }

  /// Rejects one reviewable Backlog screen change.
  Future<void> rejectScreenChangeFromUi(String changeId) async {
    final change = screenChangeForId(changeId);
    if (change == null || change.status != ScreenChangeStatus.proposed) {
      return;
    }
    _replaceScreenChange(
      change.copyWith(
        status: ScreenChangeStatus.rejected,
        safety: ScreenChangeSafety.rejected,
        error: 'Rejected by user',
      ),
    );
    screenCommandMessage = 'Screen change rejected';
    _notifyControllerListeners();
  }

  /// Undoes one applied Backlog screen change when an inverse edit is known.
  Future<void> undoScreenChangeFromUi(String changeId) async {
    final change = screenChangeForId(changeId);
    if (change == null ||
        change.status != ScreenChangeStatus.applied ||
        !_screenChangeCanUndo(change)) {
      return;
    }
    final server = _graphServerForScreenChange(change);
    if (server == null) {
      _replaceScreenChange(
        change.copyWith(
          status: ScreenChangeStatus.failed,
          error: 'No graph memory server',
        ),
      );
      _notifyControllerListeners();
      return;
    }
    screenCommandBusy = true;
    screenCommandMessage = 'Undoing screen change';
    _notifyControllerListeners();
    try {
      if (change.operation == ScreenChangeOperation.createTask) {
        await _withTasksClientForGraphServer(server, (client) {
          return client.deleteTask(change.target.taskId, actor: _memoryActor());
        });
      } else {
        await _withTasksClientForGraphServer(server, (client) {
          return _updateTaskForScreenFields(
            client: client,
            taskId: change.target.taskId,
            fields: _undoFieldsForChange(change),
          );
        });
      }
      await _loadTasks();
      _replaceScreenChange(change.copyWith(status: ScreenChangeStatus.undone));
      screenCommandMessage = 'Screen change undone';
    } catch (error) {
      _replaceScreenChange(
        change.copyWith(status: ScreenChangeStatus.failed, error: '$error'),
      );
      screenCommandMessage = error.toString();
    } finally {
      screenCommandBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Reports whether the UI can undo one applied screen change.
  bool screenChangeCanUndo(ScreenChange change) {
    return change.status == ScreenChangeStatus.applied &&
        _screenChangeCanUndo(change);
  }

  /// Builds a compact Backlog snapshot for AI planning.
  BacklogScreenSnapshot _backlogScreenSnapshot(String scopeLabel) {
    return BacklogScreenSnapshot(
      scopeLabel: scopeLabel,
      selectedTaskId: selectedGraphTaskId,
      filters: <String, dynamic>{
        'statuses': taskFilters.statuses,
        'priorities': taskFilters.priorities,
        'topics': taskFilters.topics,
        'search': taskFilters.search,
        'overdue_only': taskFilters.overdueOnly,
        'include_done': taskFilters.includeDone,
      },
      availableTools: primaryMemoryToolNames.toList()..sort(),
      visibleTasks: filteredTasks.take(50).map((task) {
        return BacklogScreenTaskSnapshot(
          id: task.id,
          title: task.title,
          description: task.description,
          status: task.status,
          priority: task.priority,
          dueAt: _screenDateValue(task.dueAt),
          scheduledAt: _screenDateValue(task.scheduledAt),
          followUpAt: _screenDateValue(task.followUpAt),
          topics: task.topics,
          estimateMinutes: task.estimateMinutes,
          owner: task.owner,
        );
      }).toList(),
    );
  }

  /// Validates and classifies one Backlog screen-command run.
  ScreenCommandRun _preparedBacklogScreenRun(ScreenCommandRun planned) {
    final bulk = planned.changes.length > 1;
    final prepared = <ScreenChange>[
      for (final change in planned.changes)
        _preparedBacklogScreenChange(change, bulk: bulk),
    ];
    return planned.copyWith(changes: prepared);
  }

  /// Validates and classifies one Backlog screen-command change.
  ScreenChange _preparedBacklogScreenChange(
    ScreenChange change, {
    required bool bulk,
  }) {
    try {
      final toolName = screenChangeOperationToolName(change.operation);
      if (primaryMemoryToolNames.isNotEmpty &&
          !primaryMemoryToolNames.contains(toolName)) {
        return _rejectedScreenChange(change, 'Tool is unavailable: $toolName');
      }
      final target = _resolvedScreenChangeTarget(change);
      final fields = _normalizedScreenFields(change.fields);
      final invalidField = _invalidScreenChangeField(change.operation, fields);
      if (invalidField.isNotEmpty) {
        return _rejectedScreenChange(change, invalidField);
      }
      final beforeValues = _beforeValuesForChange(change, target, fields);
      final afterValues = _afterValuesForChange(change, target, fields);
      final safe =
          !bulk &&
          change.confidence >= 0.85 &&
          target.taskId.isNotEmpty &&
          const <ScreenChangeOperation>{
            ScreenChangeOperation.updateTask,
            ScreenChangeOperation.completeTask,
            ScreenChangeOperation.cancelTask,
          }.contains(change.operation);
      return change.copyWith(
        target: target,
        fields: fields,
        beforeValues: beforeValues,
        afterValues: afterValues,
        safety: safe
            ? ScreenChangeSafety.autoApply
            : ScreenChangeSafety.needsReview,
        status: ScreenChangeStatus.proposed,
        error: '',
      );
    } catch (error) {
      return _rejectedScreenChange(change, error.toString());
    }
  }

  /// Applies all auto-safe changes from a prepared run.
  Future<void> _applyAutoScreenChanges(ScreenCommandRun run) async {
    final autoChanges = run.changes.where((change) {
      return change.status == ScreenChangeStatus.proposed &&
          change.safety == ScreenChangeSafety.autoApply;
    }).toList();
    for (final change in autoChanges) {
      await _applyBacklogScreenChange(change);
    }
  }

  /// Applies one validated Backlog screen change through the task service.
  Future<void> _applyBacklogScreenChange(ScreenChange change) async {
    final server = _graphServerForScreenChange(change);
    if (server == null) {
      _replaceScreenChange(
        change.copyWith(
          status: ScreenChangeStatus.failed,
          error: 'No graph memory server',
        ),
      );
      _notifyControllerListeners();
      return;
    }
    screenCommandBusy = true;
    screenCommandMessage = 'Applying screen change';
    _notifyControllerListeners();
    try {
      String appliedTaskId = change.target.taskId;
      await _withTasksClientForGraphServer(server, (client) async {
        switch (change.operation) {
          case ScreenChangeOperation.createTask:
            final task = await _createTaskForScreenFields(
              client: client,
              fields: change.fields,
            );
            appliedTaskId = task.id;
          case ScreenChangeOperation.updateTask:
            await _updateTaskForScreenFields(
              client: client,
              taskId: change.target.taskId,
              fields: change.fields,
            );
          case ScreenChangeOperation.completeTask:
            await client.completeTask(
              change.target.taskId,
              actor: _memoryActor(),
            );
          case ScreenChangeOperation.cancelTask:
            await client.cancelTask(
              change.target.taskId,
              actor: _memoryActor(),
            );
          case ScreenChangeOperation.deleteTask:
            await client.deleteTask(
              change.target.taskId,
              actor: _memoryActor(),
            );
          case ScreenChangeOperation.upsertTaskRelation:
            await client.upsertTaskRelation(
              fromTaskId: _stringField(change.fields, 'from_task_id'),
              toTaskId: _stringField(change.fields, 'to_task_id'),
              relationType: _stringField(
                change.fields,
                'type',
                fallback: 'related_to',
              ),
              confidence: _doubleField(change.fields, 'confidence'),
              explanation: _stringField(change.fields, 'note'),
              actor: _memoryActor(),
            );
          case ScreenChangeOperation.deleteTaskRelation:
            await client.deleteTaskRelation(
              _stringField(change.fields, 'relation_id'),
              actor: _memoryActor(),
            );
          case ScreenChangeOperation.linkTaskMemory:
            await client.linkTaskMemory(
              taskId: change.target.taskId,
              link: TaskMemoryLinkDraft(
                memoryId: _stringField(change.fields, 'memory_id'),
                memoryEvidenceId: _stringField(
                  change.fields,
                  'memory_evidence_id',
                ),
                relationship: _stringField(
                  change.fields,
                  'relationship',
                  fallback: 'context',
                ),
                note: _stringField(change.fields, 'note'),
              ),
            );
        }
      });
      if (appliedTaskId.isNotEmpty) {
        selectedTaskId = appliedTaskId;
        taskSelectionKind = 'task';
      }
      await _loadTasks();
      _replaceScreenChange(
        change.copyWith(
          target: change.target.copyWith(taskId: appliedTaskId),
          status: ScreenChangeStatus.applied,
          error: '',
        ),
      );
      screenCommandMessage = 'Screen change applied';
    } catch (error) {
      _replaceScreenChange(
        change.copyWith(status: ScreenChangeStatus.failed, error: '$error'),
      );
      screenCommandMessage = error.toString();
    } finally {
      screenCommandBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Returns the graph server that should handle one screen command change.
  McpServerRuntime? _graphServerForScreenChange(ScreenChange change) {
    return switch (change.operation) {
      ScreenChangeOperation.createTask => _primaryGraphServer(),
      ScreenChangeOperation.upsertTaskRelation => _graphServerForTaskId(
        _stringField(change.fields, 'from_task_id'),
      ),
      _ => _graphServerForTaskId(change.target.taskId),
    };
  }

  /// Creates a task from screen-change fields.
  Future<WorkspaceTask> _createTaskForScreenFields({
    required TasksClient client,
    required Map<String, dynamic> fields,
  }) {
    return client.createTask(
      title: _stringField(fields, 'title'),
      description: _stringField(fields, 'description'),
      status: _stringField(fields, 'status', fallback: 'open'),
      priority: _stringField(fields, 'priority', fallback: 'normal'),
      dueAt: _dateField(fields, 'due_at'),
      scheduledAt: _dateField(fields, 'scheduled_at'),
      followUpAt: _dateField(fields, 'follow_up_at'),
      topics: _stringListField(fields, 'topics'),
      estimateMinutes: _intField(fields, 'estimate_minutes'),
      urgency: _doubleField(fields, 'urgency'),
      project: _stringField(fields, 'project'),
      location: _stringField(fields, 'location'),
      owner: _stringField(fields, 'person'),
      actor: _memoryActor(),
    );
  }

  /// Updates a task from screen-change fields.
  Future<WorkspaceTask> _updateTaskForScreenFields({
    required TasksClient client,
    required String taskId,
    required Map<String, dynamic> fields,
  }) {
    return client.updateTask(
      taskId: taskId,
      title: _optionalStringField(fields, 'title'),
      description: _optionalStringField(fields, 'description'),
      status: _optionalStringField(fields, 'status'),
      priority: _optionalStringField(fields, 'priority'),
      dueAt: _dateField(fields, 'due_at'),
      clearDueAt: _boolField(fields, 'clear_due_at'),
      scheduledAt: _dateField(fields, 'scheduled_at'),
      clearScheduledAt: _boolField(fields, 'clear_scheduled_at'),
      followUpAt: _dateField(fields, 'follow_up_at'),
      clearFollowUpAt: _boolField(fields, 'clear_follow_up_at'),
      topics: fields.containsKey('topics')
          ? _stringListField(fields, 'topics')
          : null,
      replaceTopics: fields.containsKey('topics'),
      estimateMinutes: fields.containsKey('estimate_minutes')
          ? _intField(fields, 'estimate_minutes')
          : null,
      urgency: fields.containsKey('urgency')
          ? _doubleField(fields, 'urgency')
          : null,
      project: _optionalStringField(fields, 'project'),
      location: _optionalStringField(fields, 'location'),
      owner: _optionalStringField(fields, 'person'),
      actor: _memoryActor(),
    );
  }

  /// Replaces one screen change in the active run.
  void _replaceScreenChange(ScreenChange replacement) {
    final run = activeScreenCommandRun;
    if (run == null) {
      return;
    }
    activeScreenCommandRun = run.copyWith(
      changes: run.changes.map((change) {
        return change.id == replacement.id ? replacement : change;
      }).toList(),
    );
  }

  /// Builds the selected ids line used when opening chat from a screen command.
  String _screenCommandRelevantIds() {
    return <String>[
      if (selectedGraphTaskId.isNotEmpty)
        'selected backlog id: $selectedGraphTaskId',
      if (selectedMemory?.id.isNotEmpty == true)
        'selected memory id: ${_memorySelectionKey(selectedMemory!)}',
    ].join(', ');
  }

  /// Returns a concise user-facing summary for a prepared run.
  String _screenRunSummary(ScreenCommandRun run) {
    final rejected = run.changes
        .where((change) => change.safety == ScreenChangeSafety.rejected)
        .length;
    final auto = run.changes
        .where((change) => change.safety == ScreenChangeSafety.autoApply)
        .length;
    final review = run.changes
        .where((change) => change.safety == ScreenChangeSafety.needsReview)
        .length;
    return 'AI found ${run.changes.length} changes: $auto safe, $review review, $rejected rejected';
  }

  /// Resolves or validates the target for one change.
  ScreenChangeTarget _resolvedScreenChangeTarget(ScreenChange change) {
    if (change.operation == ScreenChangeOperation.createTask ||
        change.operation == ScreenChangeOperation.deleteTaskRelation ||
        change.operation == ScreenChangeOperation.upsertTaskRelation) {
      return change.target;
    }
    final taskId = change.target.taskId.trim();
    if (taskId.isNotEmpty) {
      if (_taskById(taskId) == null) {
        throw StateError('Unknown task id: $taskId');
      }
      return change.target.copyWith(taskId: taskId);
    }
    final title = change.target.taskTitle.trim();
    if (title.isEmpty) {
      throw StateError('Task id is required');
    }
    final matches = workspace.tasks.where((task) {
      return task.title.toLowerCase() == title.toLowerCase();
    }).toList();
    if (matches.length != 1) {
      throw StateError(
        matches.isEmpty
            ? 'No task matches "$title"'
            : 'Task title is ambiguous: "$title"',
      );
    }
    return change.target.copyWith(taskId: matches.single.id);
  }

  /// Returns one workspace task by id.
  WorkspaceTask? _taskById(String taskId) {
    for (final task in workspace.tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  /// Returns a rejected copy of a screen change.
  ScreenChange _rejectedScreenChange(ScreenChange change, String error) {
    return change.copyWith(
      status: ScreenChangeStatus.rejected,
      safety: ScreenChangeSafety.rejected,
      error: error,
    );
  }

  /// Trims field names in a screen-change payload.
  Map<String, dynamic> _normalizedScreenFields(Map<String, dynamic> fields) {
    final normalized = <String, dynamic>{};
    for (final entry in fields.entries) {
      normalized[entry.key.trim()] = entry.value;
    }
    return normalized;
  }

  /// Returns a validation message for invalid operation fields.
  String _invalidScreenChangeField(
    ScreenChangeOperation operation,
    Map<String, dynamic> fields,
  ) {
    final allowed = switch (operation) {
      ScreenChangeOperation.createTask ||
      ScreenChangeOperation.updateTask => _taskScreenChangeFields,
      ScreenChangeOperation.completeTask ||
      ScreenChangeOperation.cancelTask ||
      ScreenChangeOperation.deleteTask => const <String>{},
      ScreenChangeOperation.upsertTaskRelation => const <String>{
        'from_task_id',
        'to_task_id',
        'type',
        'note',
        'confidence',
      },
      ScreenChangeOperation.deleteTaskRelation => const <String>{'relation_id'},
      ScreenChangeOperation.linkTaskMemory => const <String>{
        'memory_id',
        'memory_evidence_id',
        'relationship',
        'note',
      },
    };
    for (final key in fields.keys) {
      if (!allowed.contains(key)) {
        return 'Unsupported field for ${screenChangeOperationToolName(operation)}: $key';
      }
    }
    if ((operation == ScreenChangeOperation.createTask ||
            operation == ScreenChangeOperation.updateTask) &&
        fields.containsKey('status') &&
        !_taskStatusValues.contains(_stringField(fields, 'status'))) {
      return 'Invalid task status: ${_stringField(fields, 'status')}';
    }
    if ((operation == ScreenChangeOperation.createTask ||
            operation == ScreenChangeOperation.updateTask) &&
        fields.containsKey('priority') &&
        !_taskPriorityValues.contains(_stringField(fields, 'priority'))) {
      return 'Invalid task priority: ${_stringField(fields, 'priority')}';
    }
    if (operation == ScreenChangeOperation.createTask &&
        _stringField(fields, 'title').isEmpty) {
      return 'Task title is required';
    }
    if (operation == ScreenChangeOperation.upsertTaskRelation &&
        (_stringField(fields, 'from_task_id').isEmpty ||
            _stringField(fields, 'to_task_id').isEmpty)) {
      return 'Relation changes require from_task_id and to_task_id';
    }
    if (operation == ScreenChangeOperation.deleteTaskRelation &&
        _stringField(fields, 'relation_id').isEmpty) {
      return 'Relation deletion requires relation_id';
    }
    if (operation == ScreenChangeOperation.linkTaskMemory &&
        _stringField(fields, 'memory_id').isEmpty &&
        _stringField(fields, 'memory_evidence_id').isEmpty) {
      return 'Memory link requires a memory id or source record id';
    }
    if (fields.containsKey('topics') && fields['topics'] is! List) {
      return 'topics must be a list';
    }
    for (final key in const <String>[
      'due_at',
      'scheduled_at',
      'follow_up_at',
    ]) {
      if (_stringField(fields, key).isNotEmpty &&
          _dateField(fields, key) == null) {
        return '$key must be an ISO date or timestamp';
      }
    }
    return '';
  }

  /// Captures before-values for a validated change.
  Map<String, dynamic> _beforeValuesForChange(
    ScreenChange change,
    ScreenChangeTarget target,
    Map<String, dynamic> fields,
  ) {
    final task = _taskById(target.taskId);
    if (task == null) {
      return const <String, dynamic>{};
    }
    if (change.operation == ScreenChangeOperation.completeTask ||
        change.operation == ScreenChangeOperation.cancelTask ||
        change.operation == ScreenChangeOperation.deleteTask) {
      return <String, dynamic>{
        'status': task.status,
        'title': task.title,
        'description': task.description,
        'priority': task.priority,
        'due_at': _screenDateValue(task.dueAt),
        'scheduled_at': _screenDateValue(task.scheduledAt),
        'follow_up_at': _screenDateValue(task.followUpAt),
      };
    }
    return <String, dynamic>{
      for (final key in fields.keys) key: _taskValueForField(task, key),
    };
  }

  /// Builds after-values for a validated change.
  Map<String, dynamic> _afterValuesForChange(
    ScreenChange change,
    ScreenChangeTarget target,
    Map<String, dynamic> fields,
  ) {
    if (change.operation == ScreenChangeOperation.completeTask) {
      return const <String, dynamic>{'status': 'done'};
    }
    if (change.operation == ScreenChangeOperation.cancelTask) {
      return const <String, dynamic>{'status': 'canceled'};
    }
    if (change.operation == ScreenChangeOperation.deleteTask) {
      return const <String, dynamic>{'status': 'deleted'};
    }
    return fields;
  }

  /// Returns one task field value in planner wire shape.
  dynamic _taskValueForField(WorkspaceTask task, String key) {
    return switch (key) {
      'title' => task.title,
      'description' => task.description,
      'status' => task.status,
      'priority' => task.priority,
      'due_at' => _screenDateValue(task.dueAt),
      'scheduled_at' => _screenDateValue(task.scheduledAt),
      'follow_up_at' => _screenDateValue(task.followUpAt),
      'topics' => task.topics,
      'estimate_minutes' => task.estimateMinutes,
      'urgency' => task.urgency,
      'project' => task.project,
      'location' => task.location,
      'person' => task.owner,
      'clear_due_at' => task.dueAt == null,
      'clear_scheduled_at' => task.scheduledAt == null,
      'clear_follow_up_at' => task.followUpAt == null,
      _ => '',
    };
  }

  /// Reports whether one applied change has a safe inverse.
  bool _screenChangeCanUndo(ScreenChange change) {
    if (change.operation == ScreenChangeOperation.createTask) {
      return change.target.taskId.isNotEmpty;
    }
    return const <ScreenChangeOperation>{
      ScreenChangeOperation.updateTask,
      ScreenChangeOperation.completeTask,
      ScreenChangeOperation.cancelTask,
    }.contains(change.operation);
  }

  /// Builds update_task fields that reverse one applied task edit.
  Map<String, dynamic> _undoFieldsForChange(ScreenChange change) {
    final fields = <String, dynamic>{};
    for (final entry in change.beforeValues.entries) {
      if (entry.key == 'due_at' && entry.value.toString().isEmpty) {
        fields['clear_due_at'] = true;
      } else if (entry.key == 'scheduled_at' &&
          entry.value.toString().isEmpty) {
        fields['clear_scheduled_at'] = true;
      } else if (entry.key == 'follow_up_at' &&
          entry.value.toString().isEmpty) {
        fields['clear_follow_up_at'] = true;
      } else {
        fields[entry.key] = entry.value;
      }
    }
    return fields;
  }

  /// Formats a nullable date for planner and diff display.
  String _screenDateValue(DateTime? value) {
    return value == null ? '' : value.toIso8601String();
  }
}

const Set<String> _taskScreenChangeFields = <String>{
  'title',
  'description',
  'status',
  'priority',
  'due_at',
  'scheduled_at',
  'follow_up_at',
  'clear_due_at',
  'clear_scheduled_at',
  'clear_follow_up_at',
  'topics',
  'estimate_minutes',
  'urgency',
  'project',
  'location',
  'person',
};

const Set<String> _taskStatusValues = <String>{
  'open',
  'waiting',
  'blocked',
  'done',
  'canceled',
};

const Set<String> _taskPriorityValues = <String>{
  'low',
  'normal',
  'high',
  'urgent',
};

/// Reads an optional string field from a screen-change payload.
String? _optionalStringField(Map<String, dynamic> fields, String key) {
  if (!fields.containsKey(key)) {
    return null;
  }
  return _stringField(fields, key);
}

/// Reads a string field from a screen-change payload.
String _stringField(
  Map<String, dynamic> fields,
  String key, {
  String fallback = '',
}) {
  return stringValue(fields[key], fallback: fallback, trim: true);
}

/// Reads an integer field from a screen-change payload.
int _intField(Map<String, dynamic> fields, String key) {
  final value = fields[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return intValue(value);
}

/// Reads a floating-point field from a screen-change payload.
double _doubleField(Map<String, dynamic> fields, String key) {
  return doubleValue(fields[key]);
}

/// Reads a boolean field from a screen-change payload.
bool _boolField(Map<String, dynamic> fields, String key) {
  return boolValue(fields[key]);
}

/// Reads a string-list field from a screen-change payload.
List<String> _stringListField(Map<String, dynamic> fields, String key) {
  return stringList(fields[key], trim: true);
}

/// Reads an ISO date or timestamp field from a screen-change payload.
DateTime? _dateField(Map<String, dynamic> fields, String key) {
  return parseOptionalDateTime(fields[key], trim: true);
}
