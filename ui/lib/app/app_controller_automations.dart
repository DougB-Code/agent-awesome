/// Automations workflow loading and UI actions for AgentAwesomeAppController.
part of 'app_controller.dart';

extension AgentAwesomeAppControllerAutomations on AgentAwesomeAppController {
  /// Returns the currently selected automation draft.
  AutomationDraft? get selectedAutomationDraft {
    for (final draft in automationDrafts) {
      if (draft.id == selectedAutomationDraftId) {
        return draft;
      }
    }
    return automationDrafts.isEmpty ? null : automationDrafts.first;
  }

  /// Returns the currently selected automation run.
  AutomationRun? get selectedAutomationRun {
    for (final run in automationRuns) {
      if (run.id == selectedAutomationRunId) {
        return run;
      }
    }
    return automationRuns.isEmpty ? null : automationRuns.first;
  }

  /// Returns the currently selected pending automation inbox item.
  AutomationPendingItem? get selectedAutomationPendingItem {
    for (final item in automationInbox) {
      if (item.id == selectedAutomationPendingItemId) {
        return item;
      }
    }
    return automationInbox.isEmpty ? null : automationInbox.first;
  }

  /// Returns the currently selected published automation definition.
  AutomationDefinition? get selectedAutomationDefinition {
    for (final definition in automationDefinitions) {
      if (definition.id == selectedAutomationDefinitionId) {
        return definition;
      }
    }
    return automationDefinitions.isEmpty ? null : automationDefinitions.first;
  }

  /// Returns the currently selected automation template.
  AutomationTemplate? get selectedAutomationTemplate {
    for (final template in automationTemplates) {
      if (template.id == selectedAutomationTemplateId) {
        return template;
      }
    }
    return automationTemplates.isEmpty ? null : automationTemplates.first;
  }

  /// Refreshes all Automations data from workflowd through the gateway.
  Future<void> refreshAutomationsFromUi() async {
    if (automationsBusy) {
      return;
    }
    automationsBusy = true;
    automationsMessage = 'Refreshing automations';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      await _loadAutomations();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automations refresh failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Selects one automation draft for builder screens.
  void selectAutomationDraft(String draftId) {
    selectedAutomationDraftId = draftId;
    _notifyControllerListeners();
  }

  /// Selects one automation run and loads its timeline.
  Future<void> selectAutomationRun(String runId) async {
    selectedAutomationRunId = runId;
    _notifyControllerListeners();
    await loadSelectedAutomationRunHistory();
  }

  /// Selects one pending automation inbox item for header actions.
  void selectAutomationPendingItem(String itemId) {
    selectedAutomationPendingItemId = itemId;
    _notifyControllerListeners();
  }

  /// Selects one published automation definition for header actions.
  void selectAutomationDefinition(String definitionId) {
    selectedAutomationDefinitionId = definitionId;
    _notifyControllerListeners();
  }

  /// Selects one automation template for header actions.
  void selectAutomationTemplate(String templateId) {
    selectedAutomationTemplateId = templateId;
    _notifyControllerListeners();
  }

  /// Loads the selected automation run timeline.
  Future<void> loadSelectedAutomationRunHistory() async {
    final run = selectedAutomationRun;
    if (run == null) {
      selectedAutomationEvents = const <AutomationEvent>[];
      _notifyControllerListeners();
      return;
    }
    try {
      selectedAutomationEvents = await automationsClient.history(run.id);
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation history failed: $error');
    }
    _notifyControllerListeners();
  }

  /// Creates a new workflow draft from a builder screen.
  Future<void> createAutomationDraftFromUi({
    required String kind,
    required String name,
  }) async {
    automationsBusy = true;
    automationsMessage = 'Creating automation draft';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      final draft = await automationsClient.createDraft(kind: kind, name: name);
      selectedAutomationDraftId = draft.id;
      await _loadAutomationDrafts();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation draft create failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Instantiates one template as an editable draft.
  Future<void> instantiateAutomationTemplateFromUi(
    AutomationTemplate template,
  ) async {
    automationsBusy = true;
    automationsMessage = 'Creating draft from template';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      final draft = await automationsClient.instantiateTemplate(
        template.id,
        name: template.name,
      );
      selectedAutomationDraftId = draft.id;
      await _loadAutomationDrafts();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('template instantiate failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Validates the selected automation draft.
  Future<void> validateSelectedAutomationDraftFromUi() async {
    final draft = selectedAutomationDraft;
    if (draft == null) {
      return;
    }
    await validateAutomationDraftFromUi(draft);
  }

  /// Validates one automation draft.
  Future<void> validateAutomationDraftFromUi(AutomationDraft draft) async {
    automationsBusy = true;
    automationsMessage = 'Validating ${draft.name}';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      selectedAutomationDraftId = draft.id;
      final result = await automationsClient.validateDraft(draft.id);
      automationsMessage = result.publishable
          ? ''
          : 'Draft needs review before publishing';
      await _loadAutomationDrafts();
    } catch (error) {
      automationsMessage = error.toString();
      await _log('draft validation failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Publishes the selected automation draft.
  Future<void> publishSelectedAutomationDraftFromUi() async {
    final draft = selectedAutomationDraft;
    if (draft == null) {
      return;
    }
    await publishAutomationDraftFromUi(draft);
  }

  /// Publishes one automation draft.
  Future<void> publishAutomationDraftFromUi(AutomationDraft draft) async {
    automationsBusy = true;
    automationsMessage = 'Publishing ${draft.name}';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      selectedAutomationDraftId = draft.id;
      await automationsClient.publishDraft(draft.id);
      await _loadAutomations();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('draft publish failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Saves one editable automation draft.
  Future<void> saveAutomationDraftFromUi(AutomationDraft draft) async {
    automationsBusy = true;
    automationsMessage = 'Saving ${draft.name}';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      final updated = await automationsClient.updateDraft(draft);
      selectedAutomationDraftId = updated.id;
      await _loadAutomationDrafts();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation draft save failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Adds one action node or state entry action to the selected draft.
  Future<void> addAutomationActionToSelectedDraftFromUi(
    String actionName,
  ) async {
    final draft = selectedAutomationDraft;
    if (draft == null || actionName.trim().isEmpty) {
      return;
    }
    automationsBusy = true;
    automationsMessage = 'Adding action';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      final body = _jsonMapCopy(draft.body);
      if (draft.kind == 'state_machine') {
        _appendStateMachineAction(body, actionName);
      } else {
        _appendTaskGraphNode(body, actionName);
      }
      final updated = AutomationDraft(
        id: draft.id,
        kind: draft.kind,
        name: draft.name,
        description: draft.description,
        status: draft.status,
        body: body,
        validation: draft.validation,
        createdAt: draft.createdAt,
        updatedAt: draft.updatedAt,
      );
      await automationsClient.updateDraft(updated);
      await _loadAutomationDrafts();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation action add failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Starts one installed automation definition.
  Future<void> startAutomationDefinitionFromUi(
    AutomationDefinition definition,
  ) async {
    automationsBusy = true;
    automationsMessage = 'Starting ${definition.name}';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      final run = await automationsClient.startRun(definition.id);
      selectedAutomationRunId = run.id;
      await _loadAutomationRunsAndInbox();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation start failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Sends an approval signal for one pending automation item.
  Future<void> approveAutomationPendingItemFromUi(
    AutomationPendingItem item,
  ) async {
    await _signalAutomationItem(item, 'approved', <String, dynamic>{
      'approved': true,
      'pending_id': item.id,
    });
  }

  /// Sends a rejection signal for one pending automation item.
  Future<void> rejectAutomationPendingItemFromUi(
    AutomationPendingItem item,
  ) async {
    await _signalAutomationItem(item, 'rejected', <String, dynamic>{
      'approved': false,
      'pending_id': item.id,
    });
  }

  /// Opens the Automations conversational creation panel.
  void openAutomationsChatPanel() {
    assistantChatPanelOpen = true;
    automationsChatPanelOpen = true;
    _notifyControllerListeners();
  }

  /// Closes the Automations conversational creation panel.
  void closeAutomationsChatPanel() {
    assistantChatPanelOpen = false;
    automationsChatPanelOpen = false;
    _notifyControllerListeners();
  }

  /// Starts or continues chat with an automation-authoring context prompt.
  Future<void> startAutomationChatFromUi(String userText) async {
    assistantChatPanelOpen = true;
    automationsChatPanelOpen = true;
    _notifyControllerListeners();
    final prompt = _automationChatPrompt(userText);
    final created = selectedSessionId == null ? await createChat() : true;
    if (created) {
      await sendUserMessage(prompt, displayText: userText);
    }
  }

  /// Loads all Automations data without changing busy state.
  Future<void> _loadAutomations() async {
    await Future.wait(<Future<void>>[
      _loadAutomationCatalog(),
      _loadAutomationDrafts(),
      _loadAutomationRunsAndInbox(),
    ]);
  }

  /// Loads action types, definitions, templates, and packages.
  Future<void> _loadAutomationCatalog() async {
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        automationsClient.listActionTypes(),
        automationsClient.listDefinitions(),
        automationsClient.listTemplates(),
        automationsClient.listPackages(),
      ]);
      automationActionTypes = results[0] as List<AutomationActionType>;
      automationDefinitions = results[1] as List<AutomationDefinition>;
      automationTemplates = results[2] as List<AutomationTemplate>;
      automationPackages = results[3] as List<AutomationPackage>;
      await _loadAutomationToolNames();
      if (selectedAutomationDefinitionId.isEmpty &&
          automationDefinitions.isNotEmpty) {
        selectedAutomationDefinitionId = automationDefinitions.first.id;
      }
      if (selectedAutomationTemplateId.isEmpty &&
          automationTemplates.isNotEmpty) {
        selectedAutomationTemplateId = automationTemplates.first.id;
      }
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation catalog load failed: $error');
    }
  }

  /// Loads harness context tool names for Run Tool node selection.
  Future<void> _loadAutomationToolNames() async {
    try {
      automationToolNames = (await tasksClient.listToolNames()).toSet();
    } catch (error) {
      automationToolNames = const <String>{};
      await _log('automation tool names load failed: $error');
    }
  }

  /// Loads editable workflow drafts.
  Future<void> _loadAutomationDrafts() async {
    try {
      automationDrafts = await automationsClient.listDrafts();
      if (selectedAutomationDraftId.isEmpty && automationDrafts.isNotEmpty) {
        selectedAutomationDraftId = automationDrafts.first.id;
      }
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation draft load failed: $error');
    }
  }

  /// Loads workflow runs and pending user items.
  Future<void> _loadAutomationRunsAndInbox() async {
    try {
      automationRuns = await automationsClient.listRuns();
      automationInbox = await automationsClient.inbox();
      if (selectedAutomationRunId.isEmpty && automationRuns.isNotEmpty) {
        selectedAutomationRunId = automationRuns.first.id;
      }
      if (selectedAutomationPendingItemId.isEmpty &&
          automationInbox.isNotEmpty) {
        selectedAutomationPendingItemId = automationInbox.first.id;
      }
      await loadSelectedAutomationRunHistory();
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation runs load failed: $error');
    }
  }

  Future<void> _signalAutomationItem(
    AutomationPendingItem item,
    String signal,
    Map<String, dynamic> payload,
  ) async {
    automationsBusy = true;
    automationsMessage = 'Sending workflow signal';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      await automationsClient.signal(item.runId, signal, payload: payload);
      await _loadAutomationRunsAndInbox();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('workflow signal failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  String _automationChatPrompt(String userText) {
    final draft = selectedAutomationDraft;
    final actionNames = automationActionTypes
        .map((action) {
          return '${action.name}${action.available ? '' : ' (draft-only)'}';
        })
        .join(', ');
    return '''
You are helping create or revise an Agent Awesome automation.

User request:
$userText

Current automation context:
- selected draft: ${draft == null ? 'none' : '${draft.id} (${draft.kind})'}
- available actions: $actionNames
- open approvals: ${automationInbox.length}
- recent runs: ${automationRuns.length}

Use workflow authoring MCP tools to create or update drafts. Do not publish until the user explicitly approves the draft.
''';
  }

  /// Ensures the gateway-routed workflow API is reachable before UI actions.
  Future<bool> _ensureAutomationRuntimeReady() async {
    await _ensureInitialized();
    if (_isClosing) {
      automationsMessage = 'Agent Awesome runtime is shutting down';
      _notifyControllerListeners();
      return false;
    }
    final profile = runtimeProfile;
    if (profile == null) {
      automationsMessage = statusMessage;
      _notifyControllerListeners();
      return false;
    }
    try {
      _throwIfClosing();
      localProcessStatuses = await localServices.startRequiredServices(profile);
      final failures = localProcessStatuses
          .where(
            (status) =>
                status.name != 'Local model' &&
                status.state == ConnectionStateKind.disconnected,
          )
          .toList();
      if (failures.isNotEmpty) {
        automationsMessage = failures
            .map((status) => '${status.name}: ${status.message}')
            .join(' | ');
        statusMessage = 'Local services are not ready';
        await _log('automation runtime unavailable: $automationsMessage');
        _notifyControllerListeners();
        return false;
      }
      return true;
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation runtime readiness failed: $error');
      _notifyControllerListeners();
      return false;
    }
  }
}

/// Builds the gateway workflow API URL from a gateway API base URL.
String _workflowBaseUrl(String gatewayBaseUrl) {
  final uri = Uri.parse(gatewayBaseUrl);
  return uri.replace(path: '/api/workflows', query: null).toString();
}

/// Creates a detached JSON-compatible copy of a draft body.
Map<String, dynamic> _jsonMapCopy(Map<String, dynamic> value) {
  return jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
}

/// Appends one executable action node to a task-graph draft body.
void _appendTaskGraphNode(
  Map<String, dynamic> body,
  String actionName, [
  Map<String, dynamic>? args,
]) {
  final nodes = _editableList(body, 'nodes');
  final id = _nextAutomationStepId(nodes, actionName);
  nodes.add(<String, dynamic>{
    'id': id,
    'uses': actionName,
    'with': args ?? _defaultAutomationActionArgs(actionName),
  });
  body['nodes'] = nodes;
}

/// Appends one executable entry action to a state-machine draft body.
void _appendStateMachineAction(
  Map<String, dynamic> body,
  String actionName, [
  Map<String, dynamic>? args,
]) {
  final states = _editableList(body, 'states');
  if (states.isEmpty) {
    states.add(<String, dynamic>{'id': 'review'});
    body['initial'] = 'review';
  }
  final first = Map<String, dynamic>.from(states.first as Map);
  final actions = _editableList(first, 'on_entry');
  actions.add(<String, dynamic>{
    'id': _nextAutomationStepId(actions, actionName),
    'uses': actionName,
    'with': args ?? _defaultAutomationActionArgs(actionName),
  });
  first['on_entry'] = actions;
  states[0] = first;
  body['states'] = states;
}

/// Returns an editable copy of a draft list field.
List<dynamic> _editableList(Map<String, dynamic> body, String key) {
  final value = body[key];
  if (value is List) {
    return List<dynamic>.from(value);
  }
  return <dynamic>[];
}

/// Builds a unique draft-local step id for an action name.
String _nextAutomationStepId(List<dynamic> items, String actionName) {
  final base = actionName.replaceAll('.', '_').replaceAll('-', '_');
  final existing = items
      .whereType<Map>()
      .map((item) => '${item['id'] ?? ''}')
      .toSet();
  var index = items.length + 1;
  var id = '${base}_$index';
  while (existing.contains(id)) {
    index++;
    id = '${base}_$index';
  }
  return id;
}

/// Provides valid starting arguments for one built-in action type.
Map<String, dynamic> _defaultAutomationActionArgs(String actionName) {
  return switch (actionName) {
    'tool.call' => <String, dynamic>{
      'name': '',
      'domain_id': '',
      'arguments': <String, dynamic>{},
    },
    'mcp.call' => <String, dynamic>{
      'endpoint': '',
      'tool': '',
      'arguments': <String, dynamic>{},
    },
    'workflow.run' => <String, dynamic>{
      'workflow': '',
      'input': <String, dynamic>{},
    },
    'workflow.signal' => <String, dynamic>{
      'signal': 'continue',
      'payload': <String, dynamic>{},
    },
    'human.request' => <String, dynamic>{
      'prompt': 'Review this automation step.',
      'payload': <String, dynamic>{},
    },
    'delay.until' => <String, dynamic>{'duration': '1m'},
    _ => <String, dynamic>{},
  };
}
