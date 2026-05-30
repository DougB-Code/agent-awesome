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

  /// Returns the currently selected saved Operation.
  AutomationRunSetup? get selectedAutomationRunSetup {
    for (final setup in automationRunSetups) {
      if (setup.id == selectedAutomationRunSetupId) {
        return setup;
      }
    }
    return automationRunSetups.isEmpty ? null : automationRunSetups.first;
  }

  /// Returns the currently selected codebase.
  AutomationCodebase? get selectedAutomationCodebase {
    for (final codebase in automationCodebases) {
      if (codebase.id == selectedAutomationCodebaseId) {
        return codebase;
      }
    }
    return automationCodebases.isEmpty ? null : automationCodebases.first;
  }

  /// Returns the currently selected capability registry record.
  AutomationCapability? get selectedAutomationCapability {
    for (final capability in automationCapabilities) {
      if (capability.id == selectedAutomationCapabilityId) {
        return capability;
      }
    }
    return automationCapabilities.isEmpty ? null : automationCapabilities.first;
  }

  /// Returns the currently selected Computer or Server target.
  AutomationRuntimeTarget? get selectedAutomationRuntimeTarget {
    for (final target in automationRuntimeTargets) {
      if (target.id == selectedAutomationRuntimeTargetId) {
        return target;
      }
    }
    return automationRuntimeTargets.isEmpty
        ? null
        : automationRuntimeTargets.first;
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

  /// Returns the editable draft that backs one workflow definition.
  AutomationDraft? automationDraftForDefinition(
    AutomationDefinition definition,
  ) {
    for (final draft in automationDrafts) {
      final draftDefinition = _automationDefinitionFromDraft(draft);
      if (draftDefinition?.id == definition.id) {
        return draft;
      }
    }
    return null;
  }

  /// Starts quiet polling for user-deployable workflow files.
  void startAutomationFileRefreshFromUi() {
    if (_automationFileRefreshTimer != null || _isClosing) {
      return;
    }
    unawaited(_refreshAutomationFilesFromUi());
    _automationFileRefreshTimer = Timer.periodic(
      _automationFileRefreshInterval,
      (_) => unawaited(_refreshAutomationFilesFromUi()),
    );
  }

  /// Refreshes workflow authoring files without requiring runnable services.
  Future<void> refreshAutomationAuthoringFromUi() async {
    if (automationsBusy) {
      return;
    }
    automationsBusy = true;
    automationsMessage = '';
    _notifyControllerListeners();
    try {
      await _loadAutomationDrafts();
      startAutomationFileRefreshFromUi();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('workflow authoring refresh failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Refreshes all runnable Automations data through the gateway.
  Future<void> refreshAutomationsFromUi() async {
    if (automationsBusy) {
      return;
    }
    automationsBusy = true;
    automationsMessage = 'Refreshing automations';
    _notifyControllerListeners();
    try {
      await _loadAutomationDrafts();
      _notifyControllerListeners();
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      await _loadAutomations();
      startAutomationFileRefreshFromUi();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automations refresh failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Refreshes Automations without surfacing routine polling state in the UI.
  Future<void> _refreshAutomationFilesFromUi() {
    if (_automationFileRefresh != null) {
      return _automationFileRefresh!;
    }
    _automationFileRefresh = () async {
      try {
        if (!_initialized || _isClosing || automationsBusy) {
          return;
        }
        await _loadAutomationDrafts();
        if (automationsMessage == 'Refreshing automations') {
          automationsMessage = '';
        }
        _notifyControllerListeners();
      } catch (error) {
        await _log('automation file refresh failed: $error');
      } finally {
        _automationFileRefresh = null;
      }
    }();
    return _automationFileRefresh!;
  }

  /// Selects one automation draft for builder screens.
  void selectAutomationDraft(String draftId) {
    selectedAutomationDraftId = draftId;
    final definitionId = _definitionIdForDraftId(automationDrafts, draftId);
    if (definitionId.isNotEmpty) {
      selectedAutomationDefinitionId = definitionId;
    }
    _notifyControllerListeners();
  }

  /// Selects one automation run and loads its timeline.
  Future<void> selectAutomationRun(String runId) async {
    selectedAutomationRunId = runId;
    selectedAutomationOperationRunSnapshot = null;
    _notifyControllerListeners();
    await Future.wait(<Future<void>>[
      loadSelectedAutomationRunHistory(notify: false),
      loadSelectedAutomationRunSnapshot(notify: false),
    ]);
    _notifyControllerListeners();
  }

  /// Selects one saved Operation.
  void selectAutomationRunSetup(String setupId) {
    selectedAutomationRunSetupId = setupId;
    selectedAutomationOperationPreview = null;
    _notifyControllerListeners();
  }

  /// Selects one codebase catalog record.
  void selectAutomationCodebase(String codebaseId) {
    selectedAutomationCodebaseId = codebaseId;
    _notifyControllerListeners();
  }

  /// Selects one capability registry record.
  void selectAutomationCapability(String capabilityId) {
    selectedAutomationCapabilityId = capabilityId;
    _notifyControllerListeners();
  }

  /// Selects one Computer or Server target and loads its detail metadata.
  Future<void> selectAutomationRuntimeTarget(String targetId) async {
    selectedAutomationRuntimeTargetId = targetId;
    selectedAutomationTargetHealth = null;
    selectedAutomationTargetLogs = const <AutomationTargetLogEntry>[];
    selectedAutomationTargetSecrets = null;
    _notifyControllerListeners();
    await loadSelectedAutomationRuntimeTargetDetails();
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

  /// Loads the selected automation run timeline.
  Future<void> loadSelectedAutomationRunHistory({bool notify = true}) async {
    final run = selectedAutomationRun;
    if (run == null) {
      selectedAutomationEvents = const <AutomationEvent>[];
      if (notify) {
        _notifyControllerListeners();
      }
      return;
    }
    try {
      selectedAutomationEvents = await automationsClient.history(run.id);
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation history failed: $error');
    }
    if (notify) {
      _notifyControllerListeners();
    }
  }

  /// Loads the selected Operation run audit snapshot when one exists.
  Future<void> loadSelectedAutomationRunSnapshot({bool notify = true}) async {
    final run = selectedAutomationRun;
    if (run == null) {
      selectedAutomationOperationRunSnapshot = null;
      if (notify) {
        _notifyControllerListeners();
      }
      return;
    }
    try {
      selectedAutomationOperationRunSnapshot = await automationsClient
          .operationRunSnapshot(run.id);
    } catch (error) {
      selectedAutomationOperationRunSnapshot = null;
      await _log('operation run snapshot unavailable for ${run.id}: $error');
    }
    if (notify) {
      _notifyControllerListeners();
    }
  }

  /// Loads health, logs, and secret metadata for the selected target.
  Future<void> loadSelectedAutomationRuntimeTargetDetails({
    bool notify = true,
  }) async {
    final target = selectedAutomationRuntimeTarget;
    if (target == null) {
      selectedAutomationTargetHealth = null;
      selectedAutomationTargetLogs = const <AutomationTargetLogEntry>[];
      selectedAutomationTargetSecrets = null;
      if (notify) {
        _notifyControllerListeners();
      }
      return;
    }
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        automationsClient.targetHealth(target.id),
        automationsClient.targetLogs(target.id),
        automationsClient.targetSecrets(target.id),
      ]);
      selectedAutomationTargetHealth = results[0] as AutomationTargetHealth;
      selectedAutomationTargetLogs =
          results[1] as List<AutomationTargetLogEntry>;
      selectedAutomationTargetSecrets =
          results[2] as AutomationTargetSecretMetadata;
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation target detail load failed: $error');
    }
    if (notify) {
      _notifyControllerListeners();
    }
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
      final draft = await _createAutomationDraft(kind: kind, name: name);
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
      selectedAutomationDraftId = draft.id;
      final result = await _validateAutomationDraft(draft);
      _replaceAutomationDraft(
        _automationDraftWithValidation(draft, _validationResultMap(result)),
      );
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
      selectedAutomationDraftId = draft.id;
      await _publishAutomationDraft(draft);
      await _loadAutomationDrafts();
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
    _replaceAutomationDraft(draft);
    selectedAutomationDraftId = draft.id;
    automationsBusy = true;
    automationsMessage = 'Saving ${draft.name}';
    _notifyControllerListeners();
    try {
      final updated = await _saveAutomationDraft(draft);
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

  /// Duplicates one editable workflow draft into a new authoring file.
  Future<void> duplicateAutomationDraftFromUi(AutomationDraft draft) async {
    automationsBusy = true;
    automationsMessage = 'Duplicating ${draft.name}';
    _notifyControllerListeners();
    try {
      final name =
          '${draft.name.trim().isEmpty ? 'Workflow' : draft.name} Copy';
      final created = await _createAutomationDraft(
        kind: draft.kind,
        name: name,
      );
      final definitionId = _definitionIdFromDraftId(created.id);
      final body = _normalizedWorkflowBody(
        <String, dynamic>{...draft.body, 'id': definitionId, 'name': name},
        fallbackId: definitionId,
        fallbackName: name,
      );
      final duplicate = await _saveAutomationDraft(
        AutomationDraft(
          id: created.id,
          kind: draft.kind,
          name: name,
          description: draft.description,
          status: 'draft',
          body: body,
        ),
      );
      selectedAutomationDraftId = duplicate.id;
      await _loadAutomationDrafts();
      automationsMessage = 'Duplicated ${draft.name}';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation draft duplicate failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Deletes one editable workflow draft from the authoring file list.
  Future<void> deleteAutomationDraftFromUi(AutomationDraft draft) async {
    automationsBusy = true;
    automationsMessage = 'Deleting ${draft.name}';
    _notifyControllerListeners();
    try {
      final definitionId = _automationDraftDefinitionId(draft);
      await _deleteAutomationDraft(draft);
      automationDrafts = <AutomationDraft>[
        for (final existing in automationDrafts)
          if (existing.id != draft.id) existing,
      ];
      if (selectedAutomationDraftId == draft.id) {
        selectedAutomationDraftId = '';
      }
      if (definitionId.isNotEmpty &&
          selectedAutomationDefinitionId == definitionId) {
        selectedAutomationDefinitionId = '';
      }
      await _loadAutomationDrafts();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation draft delete failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Saves metadata for an operation-selectable workflow file.
  Future<void> saveAutomationDefinitionMetadataFromUi(
    AutomationDefinition definition, {
    required String name,
    required String description,
  }) async {
    final draft = automationDraftForDefinition(definition);
    if (draft == null) {
      automationsMessage = 'Workflow file is not editable';
      _notifyControllerListeners();
      return;
    }
    await saveAutomationDraftFromUi(
      _automationDraftWithMetadata(draft, name: name, description: description),
    );
    selectedAutomationDefinitionId = definition.id;
    _notifyControllerListeners();
  }

  /// Deletes the editable workflow file represented by one definition.
  Future<void> deleteAutomationDefinitionFromUi(
    AutomationDefinition definition,
  ) async {
    final draft = automationDraftForDefinition(definition);
    if (draft == null) {
      automationsMessage = 'Workflow file is not editable';
      _notifyControllerListeners();
      return;
    }
    await deleteAutomationDraftFromUi(draft);
  }

  /// Replaces one draft in local state so editor navigation keeps pending edits.
  void _replaceAutomationDraft(AutomationDraft draft) {
    final index = automationDrafts.indexWhere((item) => item.id == draft.id);
    if (index < 0) {
      automationDrafts = <AutomationDraft>[...automationDrafts, draft];
      return;
    }
    automationDrafts = <AutomationDraft>[
      for (var itemIndex = 0; itemIndex < automationDrafts.length; itemIndex++)
        itemIndex == index ? draft : automationDrafts[itemIndex],
    ];
  }

  /// Adds one state entry action to the selected workflow draft.
  Future<void> addAutomationActionToSelectedDraftFromUi(
    String actionName,
  ) async {
    final draft = selectedAutomationDraft;
    if (draft == null || actionName.trim().isEmpty) {
      return;
    }
    final body = _jsonMapCopy(draft.body);
    _appendStateMachineAction(body, actionName);
    await saveAutomationDraftFromUi(
      AutomationDraft(
        id: draft.id,
        kind: draft.kind,
        name: draft.name,
        description: draft.description,
        status: draft.status,
        body: body,
        validation: draft.validation,
        createdAt: draft.createdAt,
        updatedAt: draft.updatedAt,
      ),
    );
  }

  /// Starts one installed automation definition.
  Future<void> startAutomationDefinitionFromUi(
    AutomationDefinition definition, {
    Map<String, dynamic> input = const <String, dynamic>{},
  }) async {
    automationsBusy = true;
    automationsMessage = 'Starting ${definition.name}';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      final run = await automationsClient.startRun(definition.id, input: input);
      _recordStartedAutomationRun(run);
      await _loadAutomationRunsAndInbox();
      _recordStartedAutomationRunIfMissing(run);
      _startAutomationRunRefreshPolling();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation start failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Creates one saved Operation for an installed workflow file.
  Future<void> createAutomationRunSetupFromUi({
    required AutomationDefinition definition,
    required String name,
    String description = '',
    String codebaseId = '',
    String runtimeTargetId = '',
    String agentProfileId = '',
    Map<String, dynamic> input = const <String, dynamic>{},
    Map<String, dynamic> policy = const <String, dynamic>{},
    Map<String, dynamic> schedule = const <String, dynamic>{},
  }) async {
    automationsBusy = true;
    automationsMessage = 'Creating operation';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      final setup = await automationsClient.createRunSetup(
        definitionId: definition.id,
        name: name,
        description: description,
        codebaseId: codebaseId,
        runtimeTargetId: runtimeTargetId,
        agentProfileId: agentProfileId,
        input: input,
        policy: policy,
        schedule: schedule,
      );
      selectedAutomationRunSetupId = setup.id;
      await _loadAutomationRunSetups();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation operation create failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Updates one saved Operation from typed UI fields.
  Future<void> updateAutomationRunSetupFromUi(AutomationRunSetup setup) async {
    automationsBusy = true;
    automationsMessage = 'Updating operation';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      final saved = await automationsClient.updateRunSetup(setup);
      selectedAutomationRunSetupId = saved.id;
      await _loadAutomationRunSetups();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation operation update failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Deletes one saved Operation from the Operations catalog.
  Future<void> deleteAutomationRunSetupFromUi(AutomationRunSetup setup) async {
    automationsBusy = true;
    automationsMessage = 'Deleting ${setup.name}';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      await automationsClient.deleteRunSetup(setup.id);
      automationRunSetups = <AutomationRunSetup>[
        for (final existing in automationRunSetups)
          if (existing.id != setup.id) existing,
      ];
      if (selectedAutomationRunSetupId == setup.id) {
        selectedAutomationRunSetupId = automationRunSetups.isEmpty
            ? ''
            : automationRunSetups.first.id;
      }
      await _loadAutomationRunSetups();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation operation delete failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Creates or updates one codebase catalog record from typed UI fields.
  Future<void> upsertAutomationCodebaseFromUi(
    AutomationCodebase codebase,
  ) async {
    automationsBusy = true;
    automationsMessage = 'Saving codebase';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      final saved = await memoryClient.upsertCodebase(codebase: codebase);
      selectedAutomationCodebaseId = saved.id;
      await _loadAutomationCodebases();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation codebase save failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Starts one saved Operation.
  Future<void> startAutomationRunSetupFromUi(
    AutomationRunSetup setup, {
    Map<String, dynamic> input = const <String, dynamic>{},
  }) async {
    automationsBusy = true;
    automationsMessage = 'Starting ${setup.name}';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      final run = await automationsClient.startRunSetup(setup.id, input: input);
      _recordStartedAutomationRun(run);
      await _loadAutomationRunsAndInbox();
      _recordStartedAutomationRunIfMissing(run);
      _startAutomationRunRefreshPolling();
      automationsMessage = '';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation operation start failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Previews one saved Operation without starting it.
  Future<void> previewAutomationRunSetupFromUi(
    AutomationRunSetup setup, {
    Map<String, dynamic> input = const <String, dynamic>{},
  }) async {
    automationsBusy = true;
    automationsMessage = 'Testing operation';
    _notifyControllerListeners();
    try {
      if (!await _ensureAutomationRuntimeReady()) {
        return;
      }
      selectedAutomationRunSetupId = setup.id;
      selectedAutomationOperationPreview = await automationsClient
          .previewRunSetup(setup.id, input: input);
      automationsMessage = selectedAutomationOperationPreview?.status == 'ready'
          ? ''
          : 'Operation needs setup';
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation operation preview failed: $error');
    } finally {
      automationsBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Previews the selected saved Operation without starting it.
  Future<void> previewSelectedAutomationRunSetupFromUi() async {
    final setup = selectedAutomationRunSetup;
    if (setup == null) {
      return;
    }
    await previewAutomationRunSetupFromUi(setup);
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
      _loadAutomationRunSetups(),
      _loadAutomationCodebases(),
      _loadAutomationRuntimeTargets(),
      _loadAutomationRunsAndInbox(),
    ]);
  }

  /// Loads action types, definitions, and packages.
  Future<void> _loadAutomationCatalog() async {
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        automationsClient.listActionTypes(),
        automationsClient.listDefinitions(),
        automationsClient.listPackages(),
        automationsClient.listCapabilities(),
      ]);
      automationActionTypes = results[0] as List<AutomationActionType>;
      automationDefinitions = results[1] as List<AutomationDefinition>;
      automationPackages = results[2] as List<AutomationPackage>;
      automationCapabilities = results[3] as List<AutomationCapability>;
      _syncAutomationDefinitionsFromDrafts();
      await _loadAutomationToolNames();
      if (selectedAutomationCapabilityId.isEmpty &&
          automationCapabilities.isNotEmpty) {
        selectedAutomationCapabilityId = automationCapabilities.first.id;
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
      automationDrafts = await _listAutomationDrafts();
      _syncAutomationDefinitionsFromDrafts();
      if (selectedAutomationDraftId.isEmpty && automationDrafts.isNotEmpty) {
        selectedAutomationDraftId = automationDrafts.first.id;
      }
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation draft load failed: $error');
    }
  }

  /// Mirrors local workflow files into the Operations workflow selector.
  void _syncAutomationDefinitionsFromDrafts() {
    final localDefinitions = _automationDefinitionsFromDrafts(automationDrafts);
    final localIds = <String>{
      for (final definition in localDefinitions) definition.id,
    };
    final serviceDefinitions = <AutomationDefinition>[
      for (final definition in automationDefinitions)
        if (!_localAutomationDefinitionIds.contains(definition.id) &&
            !localIds.contains(definition.id))
          definition,
    ];
    automationDefinitions = <AutomationDefinition>[
      ...localDefinitions,
      ...serviceDefinitions,
    ];
    _localAutomationDefinitionIds = localIds;
    _selectAvailableAutomationDefinition();
  }

  /// Selects the first available workflow file when the previous one is gone.
  void _selectAvailableAutomationDefinition() {
    if (automationDefinitions.isEmpty) {
      selectedAutomationDefinitionId = '';
      return;
    }
    final selectedExists = automationDefinitions.any(
      (definition) => definition.id == selectedAutomationDefinitionId,
    );
    if (!selectedExists) {
      selectedAutomationDefinitionId = automationDefinitions.first.id;
    }
  }

  /// Loads saved Operations.
  Future<void> _loadAutomationRunSetups() async {
    try {
      automationRunSetups = await automationsClient.listRunSetups();
      if (selectedAutomationRunSetupId.isEmpty &&
          automationRunSetups.isNotEmpty) {
        selectedAutomationRunSetupId = automationRunSetups.first.id;
      }
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation operations load failed: $error');
    }
  }

  /// Loads typed codebases for Operations.
  Future<void> _loadAutomationCodebases() async {
    try {
      automationCodebases = await memoryClient.listCodebases();
      if (selectedAutomationCodebaseId.isEmpty &&
          automationCodebases.isNotEmpty) {
        selectedAutomationCodebaseId = automationCodebases.first.id;
      }
    } catch (error) {
      await _log('automation codebases load failed: $error');
    }
  }

  /// Loads Computer or Server targets for Operations.
  Future<void> _loadAutomationRuntimeTargets() async {
    try {
      automationRuntimeTargets = await automationsClient.listRuntimeTargets();
      final selectedStillExists = automationRuntimeTargets.any(
        (target) => target.id == selectedAutomationRuntimeTargetId,
      );
      if (!selectedStillExists) {
        selectedAutomationRuntimeTargetId = automationRuntimeTargets.isEmpty
            ? ''
            : automationRuntimeTargets.first.id;
      }
      await loadSelectedAutomationRuntimeTargetDetails(notify: false);
    } catch (error) {
      automationsMessage = error.toString();
      await _log('automation runtime targets load failed: $error');
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

  /// Inserts a just-started run immediately so Operations does not look idle.
  void _recordStartedAutomationRun(AutomationRun run) {
    selectedAutomationRunId = run.id;
    automationRuns = <AutomationRun>[
      run,
      for (final existing in automationRuns)
        if (existing.id != run.id) existing,
    ];
    _notifyControllerListeners();
  }

  /// Keeps the accepted run visible if an immediate list call is stale.
  void _recordStartedAutomationRunIfMissing(AutomationRun run) {
    if (automationRuns.any((existing) => existing.id == run.id)) {
      selectedAutomationRunId = run.id;
      return;
    }
    _recordStartedAutomationRun(run);
  }

  /// Starts bounded run polling while any local run is still active.
  void _startAutomationRunRefreshPolling() {
    if (!_hasControllerListeners ||
        _automationRunRefreshTimer != null ||
        !_automationRunsNeedPolling()) {
      return;
    }
    _automationRunRefreshTicks = 0;
    _automationRunRefreshTimer = Timer.periodic(
      _automationRunRefreshInterval,
      (_) => unawaited(_pollAutomationRuns()),
    );
  }

  /// Refreshes run state without blocking unrelated UI interactions.
  Future<void> _pollAutomationRuns() async {
    if (_isClosing ||
        !_hasControllerListeners ||
        _automationRunRefreshTicks >= 30 ||
        !_automationRunsNeedPolling()) {
      _stopAutomationRunRefreshPolling();
      return;
    }
    if (_automationRunRefreshInFlight) {
      return;
    }
    _automationRunRefreshInFlight = true;
    _automationRunRefreshTicks++;
    try {
      await _loadAutomationRunsAndInbox();
      _notifyControllerListeners();
      if (!_automationRunsNeedPolling()) {
        _stopAutomationRunRefreshPolling();
      }
    } finally {
      _automationRunRefreshInFlight = false;
    }
  }

  /// Stops active run polling when no visible runs still need updates.
  void _stopAutomationRunRefreshPolling() {
    _automationRunRefreshTimer?.cancel();
    _automationRunRefreshTimer = null;
    _automationRunRefreshTicks = 0;
  }

  /// Reports whether any known run is still expected to change.
  bool _automationRunsNeedPolling() {
    return automationRuns.any((run) {
      final status = run.status.trim().toLowerCase();
      final state = run.state.trim().toLowerCase();
      return <String>{
            'running',
            'waiting',
            'pending',
            'queued',
          }.contains(status) ||
          <String>{'running', 'waiting', 'pending', 'queued'}.contains(state);
    });
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

  /// Lists editable workflow files without requiring runnable workflow services.
  Future<List<AutomationDraft>> _listAutomationDrafts() async {
    if (_automationsClientInjected) {
      return automationsClient.listDrafts();
    }
    return _listLocalAutomationDrafts();
  }

  /// Creates one workflow authoring file through the local file boundary.
  Future<AutomationDraft> _createAutomationDraft({
    required String kind,
    required String name,
  }) async {
    if (_automationsClientInjected) {
      return automationsClient.createDraft(kind: kind, name: name);
    }
    return _createLocalAutomationDraft(kind: kind, name: name);
  }

  /// Saves one workflow authoring file through the local file boundary.
  Future<AutomationDraft> _saveAutomationDraft(AutomationDraft draft) async {
    if (_automationsClientInjected) {
      return automationsClient.updateDraft(draft);
    }
    return _saveLocalAutomationDraft(draft);
  }

  /// Validates a workflow draft without starting runnable services.
  Future<AutomationValidationResult> _validateAutomationDraft(
    AutomationDraft draft,
  ) async {
    if (_automationsClientInjected) {
      return automationsClient.validateDraft(draft.id);
    }
    return _validateLocalAutomationDraft(draft);
  }

  /// Publishes a workflow draft without starting runnable services.
  Future<void> _publishAutomationDraft(AutomationDraft draft) async {
    if (_automationsClientInjected) {
      await automationsClient.publishDraft(draft.id);
      return;
    }
    await _saveLocalAutomationDraft(draft);
  }

  /// Deletes one workflow authoring file through the local file boundary.
  Future<void> _deleteAutomationDraft(AutomationDraft draft) async {
    if (_automationsClientInjected) {
      await automationsClient.deleteDraft(draft.id);
      return;
    }
    await _deleteLocalAutomationDraft(draft);
  }

  /// Lists YAML workflow files from the selected agent's authoring folder.
  Future<List<AutomationDraft>> _listLocalAutomationDrafts() async {
    final directory = await _workflowAuthoringDirectory();
    if (!await directory.exists()) {
      return const <AutomationDraft>[];
    }
    final drafts = <AutomationDraft>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !_isWorkflowYamlPath(entity.path)) {
        continue;
      }
      final draft = await _draftFromLocalWorkflowFile(entity);
      if (draft != null) {
        drafts.add(draft);
      }
    }
    drafts.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return drafts;
  }

  /// Creates a blank state-machine workflow YAML file in the authoring folder.
  Future<AutomationDraft> _createLocalAutomationDraft({
    required String kind,
    required String name,
  }) async {
    if (kind.trim() != automationWorkflowKind) {
      throw StateError('Workflow authoring only supports workflow files');
    }
    final directory = await _workflowAuthoringDirectory();
    await directory.create(recursive: true);
    final baseId = _safeWorkflowDefinitionId(name);
    final definitionId = await _uniqueWorkflowDefinitionId(directory, baseId);
    final body = _blankWorkflowBody(definitionId, name);
    final file = File(
      await _uniqueWorkflowPath(
        directory.path,
        '${_safeWorkflowFileStem(name)}.yaml',
      ),
    );
    await file.writeAsString(encodeYamlMap(body));
    final draft = await _draftFromLocalWorkflowFile(file);
    if (draft == null) {
      throw StateError('Created workflow file could not be loaded');
    }
    return draft;
  }

  /// Saves a state-machine workflow draft as readable local YAML.
  Future<AutomationDraft> _saveLocalAutomationDraft(
    AutomationDraft draft,
  ) async {
    final file = await _localWorkflowFileForDraft(draft);
    await file.parent.create(recursive: true);
    final body = _normalizedWorkflowBody(
      draft.body,
      fallbackId: _definitionIdFromDraftId(draft.id),
      fallbackName: draft.name,
    );
    await file.writeAsString(encodeYamlMap(body));
    final saved = await _draftFromLocalWorkflowFile(file);
    if (saved == null) {
      throw StateError('Saved workflow file could not be loaded');
    }
    return saved;
  }

  /// Deletes the local YAML file backing an editable workflow draft.
  Future<void> _deleteLocalAutomationDraft(AutomationDraft draft) async {
    final file = await _localWorkflowFileForDraft(draft, mustExist: true);
    await file.delete();
  }

  /// Performs local structural validation for a state-machine workflow file.
  AutomationValidationResult _validateLocalAutomationDraft(
    AutomationDraft draft,
  ) {
    final diagnostics = <AutomationValidationDiagnostic>[];
    final body = _normalizedWorkflowBody(
      draft.body,
      fallbackId: _definitionIdFromDraftId(draft.id),
      fallbackName: draft.name,
    );
    final states = body['states'];
    if (states is! List || states.isEmpty) {
      diagnostics.add(
        const AutomationValidationDiagnostic(
          severity: 'error',
          path: 'states',
          message: 'At least one state is required.',
        ),
      );
    }
    final initial = _stringFromWorkflowBody(body, 'initial');
    if (initial.isNotEmpty && states is List && states.isNotEmpty) {
      final hasInitial = states.any((state) {
        return state is Map && '${state['id'] ?? ''}'.trim() == initial;
      });
      if (!hasInitial) {
        diagnostics.add(
          AutomationValidationDiagnostic(
            severity: 'error',
            path: 'initial',
            message: 'Initial state "$initial" does not exist.',
          ),
        );
      }
    }
    final valid = diagnostics
        .where((diagnostic) => diagnostic.severity == 'error')
        .isEmpty;
    return AutomationValidationResult(
      valid: valid,
      publishable: valid,
      diagnostics: diagnostics,
      definition: valid ? body : const <String, dynamic>{},
    );
  }

  /// Resolves the active workflow authoring directory without starting services.
  Future<Directory> _workflowAuthoringDirectory() async {
    final profile = await _workflowAuthoringProfile();
    return Directory(workflowDefinitionsDirectoryPathForProfile(profile));
  }

  /// Loads enough topology for authoring paths without booting the harness.
  Future<RuntimeProfile> _workflowAuthoringProfile() async {
    final loaded = runtimeProfile;
    if (loaded != null) {
      return loaded;
    }
    final loader = RuntimeProfileLoader(config);
    final profileFile = await _resolveInitialProfileFile(loader);
    runtimeProfilePath = profileFile.path;
    final profile = await _loadInitialRuntimeProfile(loader, profileFile);
    runtimeProfile = profile;
    return profile;
  }

  /// Loads one local workflow YAML file as an editable draft row.
  Future<AutomationDraft?> _draftFromLocalWorkflowFile(File file) async {
    try {
      final body = _workflowBodyFromYaml(await file.readAsString());
      if (body == null) {
        return null;
      }
      final definitionId = _workflowBodyId(body, file.path);
      final name = _workflowBodyName(body, definitionId);
      final normalized = _normalizedWorkflowBody(
        body,
        fallbackId: definitionId,
        fallbackName: name,
      );
      final stat = await file.stat();
      final updatedAt = stat.modified.toUtc().toIso8601String();
      return AutomationDraft(
        id: _draftIdFromDefinitionId(definitionId),
        kind: automationWorkflowKind,
        name: name,
        description: _stringFromWorkflowBody(normalized, 'description'),
        status: 'draft',
        body: normalized,
        updatedAt: updatedAt,
      );
    } catch (error) {
      await _log('workflow file load skipped ${file.path}: $error');
      return null;
    }
  }

  /// Resolves the YAML file backing a local workflow draft.
  Future<File> _localWorkflowFileForDraft(
    AutomationDraft draft, {
    bool mustExist = false,
  }) async {
    final directory = await _workflowAuthoringDirectory();
    final definitionId = _automationDraftDefinitionId(draft).isEmpty
        ? _definitionIdFromDraftId(draft.id)
        : _automationDraftDefinitionId(draft);
    if (await directory.exists()) {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || !_isWorkflowYamlPath(entity.path)) {
          continue;
        }
        final body = _workflowBodyFromYaml(await entity.readAsString());
        if (body != null &&
            _workflowBodyId(body, entity.path) == definitionId) {
          return entity;
        }
      }
    }
    if (mustExist) {
      throw FileSystemException('Workflow file not found', definitionId);
    }
    final filename = '${_safeWorkflowFileStem(draft.name)}.yaml';
    return File(await _uniqueWorkflowPath(directory.path, filename));
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
      localProcessStatuses = await _startRequiredRuntimeServices(
        profile,
        includeHarness: profile.workflow.hostedByHarness,
        includeMcpServers: false,
      );
      final failures = localProcessStatuses
          .where(
            (status) =>
                !_isLocalModelProcessStatus(status) &&
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

/// Returns a draft copy with updated validation metadata.
AutomationDraft _automationDraftWithValidation(
  AutomationDraft draft,
  Map<String, dynamic> validation,
) {
  return AutomationDraft(
    id: draft.id,
    kind: draft.kind,
    name: draft.name,
    description: draft.description,
    status: draft.status,
    body: draft.body,
    validation: validation,
    createdAt: draft.createdAt,
    updatedAt: draft.updatedAt,
  );
}

/// Encodes a validation result for draft card badges.
Map<String, dynamic> _validationResultMap(AutomationValidationResult result) {
  return <String, dynamic>{
    'valid': result.valid,
    'publishable': result.publishable,
    'diagnostics': <Map<String, dynamic>>[
      for (final diagnostic in result.diagnostics)
        <String, dynamic>{
          'severity': diagnostic.severity,
          'path': diagnostic.path,
          'message': diagnostic.message,
        },
    ],
    if (result.definition.isNotEmpty) 'definition': result.definition,
  };
}

/// Converts editable workflow drafts into operation-selectable definitions.
List<AutomationDefinition> _automationDefinitionsFromDrafts(
  List<AutomationDraft> drafts,
) {
  final definitions = <AutomationDefinition>[];
  final seenIds = <String>{};
  for (final draft in drafts) {
    final definition = _automationDefinitionFromDraft(draft);
    if (definition == null || !seenIds.add(definition.id)) {
      continue;
    }
    definitions.add(definition);
  }
  return definitions;
}

/// Converts one local workflow draft into a runnable definition snapshot.
AutomationDefinition? _automationDefinitionFromDraft(AutomationDraft draft) {
  if (!_isWorkflowDefinitionDraft(draft)) {
    return null;
  }
  final fallbackId = _automationDefinitionIdFromDraft(draft);
  if (fallbackId.isEmpty) {
    return null;
  }
  final body = _normalizedWorkflowBody(
    draft.body,
    fallbackId: fallbackId,
    fallbackName: draft.name,
  );
  final definitionId = _workflowBodyId(body, '$fallbackId.yaml');
  return AutomationDefinition(
    id: definitionId,
    kind: _stringFromWorkflowBody(body, 'kind').isEmpty
        ? automationWorkflowKind
        : _stringFromWorkflowBody(body, 'kind'),
    name: _workflowBodyName(body, definitionId),
    hash: _localAutomationDefinitionHash(draft),
    body: body,
    updatedAt: draft.updatedAt,
  );
}

/// Returns a workflow definition id for the selected draft id.
String _definitionIdForDraftId(List<AutomationDraft> drafts, String draftId) {
  for (final draft in drafts) {
    if (draft.id == draftId) {
      return _automationDefinitionIdFromDraft(draft);
    }
  }
  return '';
}

/// Returns the workflow definition id represented by one draft.
String _automationDefinitionIdFromDraft(AutomationDraft draft) {
  final bodyId = _automationDraftDefinitionId(draft);
  return bodyId.isEmpty ? _definitionIdFromDraftId(draft.id) : bodyId;
}

/// Reports whether a draft can appear as a workflow file in Operations.
bool _isWorkflowDefinitionDraft(AutomationDraft draft) {
  final kind = draft.kind.trim();
  return kind == automationWorkflowKind || kind == 'state_machine';
}

/// Returns a stable local hash placeholder for a file-backed definition.
String _localAutomationDefinitionHash(AutomationDraft draft) {
  final updatedAt = draft.updatedAt.trim();
  return updatedAt.isEmpty ? 'local:${draft.id}' : 'local:$updatedAt';
}

/// Returns a draft copy with user-editable workflow metadata changed.
AutomationDraft _automationDraftWithMetadata(
  AutomationDraft draft, {
  required String name,
  required String description,
}) {
  final trimmedName = name.trim();
  final body = _normalizedWorkflowBody(
    <String, dynamic>{...draft.body},
    fallbackId: _automationDefinitionIdFromDraft(draft),
    fallbackName: draft.name,
  );
  if (trimmedName.isNotEmpty) {
    body['name'] = trimmedName;
  }
  body['description'] = description.trim();
  return AutomationDraft(
    id: draft.id,
    kind: draft.kind,
    name: trimmedName.isEmpty ? draft.name : trimmedName,
    description: description.trim(),
    status: draft.status,
    body: body,
    validation: draft.validation,
    createdAt: draft.createdAt,
    updatedAt: draft.updatedAt,
  );
}

/// Decodes one workflow YAML document into a mutable map.
Map<String, dynamic>? _workflowBodyFromYaml(String content) {
  final decoded = plainYamlValue(loadYaml(content));
  if (decoded is! Map) {
    return null;
  }
  return _stringKeyedMap(decoded);
}

/// Creates a minimal state-machine workflow definition.
Map<String, dynamic> _blankWorkflowBody(String definitionId, String name) {
  final displayName = name.trim().isEmpty ? definitionId : name.trim();
  return <String, dynamic>{
    'apiVersion': automationWorkflowApiVersion,
    'kind': 'state_machine',
    'id': definitionId,
    'name': displayName,
    'description': '',
    'initial': 'start',
    'states': <Map<String, dynamic>>[
      <String, dynamic>{'id': 'start'},
    ],
  };
}

/// Returns a workflow body with required state-machine fields populated.
Map<String, dynamic> _normalizedWorkflowBody(
  Map<String, dynamic> body, {
  required String fallbackId,
  required String fallbackName,
}) {
  final normalized = _jsonCompatibleMap(body);
  final definitionId = _stringFromWorkflowBody(normalized, 'id').isEmpty
      ? fallbackId
      : _stringFromWorkflowBody(normalized, 'id');
  final name = _stringFromWorkflowBody(normalized, 'name').isEmpty
      ? fallbackName
      : _stringFromWorkflowBody(normalized, 'name');
  normalized['apiVersion'] =
      _stringFromWorkflowBody(normalized, 'apiVersion').isEmpty
      ? automationWorkflowApiVersion
      : normalized['apiVersion'];
  normalized['kind'] = 'state_machine';
  normalized['id'] = definitionId.trim().isEmpty
      ? _safeWorkflowDefinitionId(name)
      : definitionId;
  normalized['name'] = name.trim().isEmpty ? normalized['id'] : name;
  normalized.putIfAbsent('description', () => '');
  final states = normalized['states'];
  if (states is! List || states.isEmpty) {
    normalized['initial'] = 'start';
    normalized['states'] = <Map<String, dynamic>>[
      <String, dynamic>{'id': 'start'},
    ];
  } else if (_stringFromWorkflowBody(normalized, 'initial').isEmpty) {
    final first = states.first;
    if (first is Map) {
      normalized['initial'] = '${first['id'] ?? 'start'}'.trim();
    } else {
      normalized['initial'] = 'start';
    }
  }
  return normalized;
}

/// Converts nested YAML values into JSON-compatible maps and lists.
Map<String, dynamic> _jsonCompatibleMap(Map<String, dynamic> values) {
  return <String, dynamic>{
    for (final entry in values.entries)
      entry.key: _jsonCompatibleValue(entry.value),
  };
}

/// Converts one nested YAML value into JSON-compatible data.
dynamic _jsonCompatibleValue(dynamic value) {
  if (value is Map) {
    return _stringKeyedMap(value);
  }
  if (value is List) {
    return value.map(_jsonCompatibleValue).toList();
  }
  return value;
}

/// Converts any map with string-like keys into a JSON-compatible map.
Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> values) {
  return <String, dynamic>{
    for (final entry in values.entries)
      '${entry.key}': _jsonCompatibleValue(entry.value),
  };
}

/// Returns the workflow definition id from body or filename fallback.
String _workflowBodyId(Map<String, dynamic> body, String path) {
  final id = _stringFromWorkflowBody(body, 'id');
  if (id.isNotEmpty) {
    return id;
  }
  final filename = path.replaceAll('\\', '/').split('/').last;
  final dot = filename.lastIndexOf('.');
  final stem = dot <= 0 ? filename : filename.substring(0, dot);
  return _safeWorkflowDefinitionId(stem);
}

/// Returns the workflow display name from body or id fallback.
String _workflowBodyName(Map<String, dynamic> body, String definitionId) {
  final name = _stringFromWorkflowBody(body, 'name');
  if (name.isNotEmpty) {
    return name;
  }
  return definitionId
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

/// Reads a trimmed string from a workflow body map.
String _stringFromWorkflowBody(Map<String, dynamic> body, String key) {
  final value = body[key];
  return value == null ? '' : '$value'.trim();
}

/// Creates a stable draft id for one local workflow definition id.
String _draftIdFromDefinitionId(String definitionId) {
  return 'draft_${_safeWorkflowDefinitionId(definitionId)}';
}

/// Returns a definition id from a draft id fallback.
String _definitionIdFromDraftId(String draftId) {
  final trimmed = draftId.trim();
  if (trimmed.startsWith('draft_') && trimmed.length > 'draft_'.length) {
    return trimmed.substring('draft_'.length);
  }
  return _safeWorkflowDefinitionId(trimmed);
}

/// Reports whether a filesystem path is a workflow YAML file.
bool _isWorkflowYamlPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.yaml') || lower.endsWith('.yml');
}

/// Returns a filesystem-safe workflow filename stem.
String _safeWorkflowFileStem(String name) {
  final safe = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return safe.isEmpty ? 'workflow' : safe;
}

/// Returns a workflow definition id made of stable lowercase tokens.
String _safeWorkflowDefinitionId(String value) {
  final safe = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return safe.isEmpty ? 'workflow' : safe;
}

/// Returns a non-conflicting workflow definition id in one directory.
Future<String> _uniqueWorkflowDefinitionId(
  Directory directory,
  String baseId,
) async {
  final existing = <String>{};
  if (await directory.exists()) {
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !_isWorkflowYamlPath(entity.path)) {
        continue;
      }
      final body = _workflowBodyFromYaml(await entity.readAsString());
      if (body != null) {
        existing.add(_workflowBodyId(body, entity.path));
      }
    }
  }
  var candidate = _safeWorkflowDefinitionId(baseId);
  var suffix = 2;
  while (existing.contains(candidate)) {
    candidate = '${_safeWorkflowDefinitionId(baseId)}_$suffix';
    suffix++;
  }
  return candidate;
}

/// Returns a non-conflicting path in one workflow authoring directory.
Future<String> _uniqueWorkflowPath(String directory, String filename) async {
  final dot = filename.lastIndexOf('.');
  final base = dot <= 0 ? filename : filename.substring(0, dot);
  final extension = dot <= 0 ? '.yaml' : filename.substring(dot);
  var candidate = '$directory/$filename';
  var suffix = 2;
  while (await File(candidate).exists()) {
    candidate = '$directory/$base-$suffix$extension';
    suffix++;
  }
  return candidate;
}

/// Creates a detached JSON-compatible copy of a draft body.
Map<String, dynamic> _jsonMapCopy(Map<String, dynamic> value) {
  return jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
}

/// Returns the published definition id represented by one authoring draft.
String _automationDraftDefinitionId(AutomationDraft draft) {
  return '${draft.body['id'] ?? ''}'.trim();
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
    'command.execute' => <String, dynamic>{
      'template_id': '',
      'cwd': '',
      'parameters': <String, dynamic>{},
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
