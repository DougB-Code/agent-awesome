/// Chat session, streaming, and chat-history workflows for AgentAwesomeAppController.
part of 'app_controller.dart';

extension AgentAwesomeAppControllerChat on AgentAwesomeAppController {
  /// Selects a chat session and loads its events when connected.
  Future<void> selectSession(String sessionId, {String chatKey = ''}) async {
    await _log('select session requested $sessionId');
    final key = chatKey.trim().isEmpty
        ? _chatHistoryKey(sessionId)
        : chatKey.trim();
    selectedSessionId = sessionId;
    selectedChatHistoryKey = key;
    pendingConfirmation = null;
    messages = const <ChatMessage>[];
    _notifyControllerListeners();
    try {
      final events = await assistantClient.loadSessionEvents(sessionId);
      final routedEvents = _chatEventsWithInheritedModelRefs(events);
      _rememberLiveSession(sessionId);
      await _touchHistoryChat(sessionId);
      _restoreChatModelRefFromEvents(routedEvents);
      messages = routedEvents
          .map(_messageFromEvent)
          .whereType<ChatMessage>()
          .toList();
      _scheduleChatTitleRefresh(
        sessionId: sessionId,
        transcript: List<ChatMessage>.from(messages),
      );
      _setEndpoint(
        'Agent API',
        ConnectionStateKind.connected,
        'Loaded session',
      );
    } catch (error) {
      await _log('select session failed $sessionId: $error');
      if (selectedSessionId == sessionId) {
        messages = const <ChatMessage>[];
      }
      await _log('preserving chat history entry for unavailable session');
      _setEndpoint(
        'Agent API',
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    }
    _notifyControllerListeners();
  }

  /// Selects a saved chat in the current agent runtime.
  Future<void> selectHistoryChat(String chatKey) async {
    ChatHistoryEntry? target;
    for (final entry in chatHistory) {
      if (entry.key == chatKey) {
        target = entry;
        break;
      }
    }
    if (target == null) {
      final sessionId = chatKey.trim();
      if (sessionId.isEmpty) {
        return;
      }
      _selectHistoryChatCard(sessionId, sessionId);
      await selectSession(sessionId, chatKey: sessionId);
      return;
    }
    _selectHistoryChatCard(target.key, target.sessionId);
    await selectSession(target.sessionId, chatKey: target.key);
  }

  /// Marks a history chat as the active left-panel selection immediately.
  void _selectHistoryChatCard(String chatKey, String sessionId) {
    selectedChatHistoryKey = chatKey;
    selectedSessionId = sessionId;
    pendingConfirmation = null;
    messages = const <ChatMessage>[];
    _notifyControllerListeners();
  }

  /// Restores the most recent saved chat as the active chat card selection.
  bool _restoreSelectedChatFromHistory() {
    final selectedKey = selectedChatHistoryKey.trim();
    if (selectedKey.isNotEmpty) {
      final entry = _historyEntryByKey(selectedKey);
      if (entry != null && entry.sessionId.trim().isNotEmpty) {
        selectedChatHistoryKey = entry.key;
        selectedSessionId = entry.sessionId;
        return true;
      }
    }
    final sessionId = selectedSessionId?.trim() ?? '';
    if (sessionId.isNotEmpty) {
      final entry = _historyEntryByKey(_chatHistoryKey(sessionId));
      if (entry != null && entry.sessionId.trim().isNotEmpty) {
        selectedChatHistoryKey = entry.key;
        selectedSessionId = entry.sessionId;
        return true;
      }
    }
    for (final entry in _sortedHistory(chatHistory)) {
      if (entry.key.trim().isEmpty || entry.sessionId.trim().isEmpty) {
        continue;
      }
      selectedChatHistoryKey = entry.key;
      selectedSessionId = entry.sessionId;
      return true;
    }
    return false;
  }

  /// Deletes a saved chat and its backing runtime session.
  Future<void> deleteHistoryChat(String chatKey) async {
    await _ensureInitialized();
    await _log('delete chat requested $chatKey');
    final target = _chatTargetFromKey(chatKey);
    if (target == null) {
      await _log('delete chat ignored: target not found');
      return;
    }
    try {
      if (!await _ensureChatRuntimeReady()) {
        await _log('delete chat blocked: managed runtime unavailable');
        _notifyControllerListeners();
        throw StateError(statusMessage);
      }
      await assistantClient.deleteSession(target.sessionId);
      await _removeHistoryChat(sessionId: target.sessionId);
      _chatTaskIds.remove(target.sessionId);
      sessions = sessions
          .where((session) => session.id != target.sessionId)
          .toList();
      if (selectedSessionId == target.sessionId) {
        pendingConfirmation = null;
        if (sessions.isEmpty) {
          if (!_restoreSelectedChatFromHistory()) {
            selectedSessionId = null;
            selectedChatHistoryKey = '';
          }
          messages = const <ChatMessage>[];
        } else {
          selectedSessionId = sessions.first.id;
          await selectSession(sessions.first.id);
        }
      }
      _setEndpoint('Agent API', ConnectionStateKind.connected, 'Deleted chat');
      await _log('deleted chat session ${target.sessionId}');
    } catch (error) {
      await _log('delete chat failed: $error');
      _setEndpoint(
        'Agent API',
        ConnectionStateKind.disconnected,
        error.toString(),
      );
      rethrow;
    } finally {
      _notifyControllerListeners();
    }
  }

  /// Creates a new chat session.
  Future<bool> createChat() async {
    await _ensureInitialized();
    await _log('create chat requested');
    if (runtimeProfile == null) {
      await _log('create chat blocked: agent runtime missing');
      _setEndpoint(
        'Agent runtime',
        ConnectionStateKind.disconnected,
        statusMessage,
      );
      _notifyControllerListeners();
      return false;
    }
    if (!await _ensureChatRuntimeReady()) {
      await _log('create chat blocked: managed runtime unavailable');
      messages = <ChatMessage>[
        ...messages,
        ChatMessage(
          id: 'runtime-${DateTime.now().microsecondsSinceEpoch}',
          role: ChatRole.tool,
          author: 'Runtime',
          text: _agentUnavailableMessage(),
          createdAt: DateTime.now(),
        ),
      ];
      _notifyControllerListeners();
      return false;
    }
    try {
      final session = await assistantClient.createSession();
      sessions = <ChatSession>[session, ...sessions];
      selectedSessionId = session.id;
      selectedChatHistoryKey = _chatHistoryKey(session.id);
      messages = const <ChatMessage>[];
      await _upsertHistoryChat(session);
      _setEndpoint('Agent API', ConnectionStateKind.connected, 'Created chat');
      await _log('created chat session ${session.id}');
      unawaited(Future.wait(<Future<void>>[_loadMemory(), _loadTasks()]));
      _notifyControllerListeners();
      return true;
    } catch (error) {
      await _log('create chat failed: $error');
      _setEndpoint(
        'Agent API',
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    }
    _notifyControllerListeners();
    return false;
  }

  /// Sends a user-authored chat message with optional hidden routing context.
  Future<void> sendUserMessage(
    String text, {
    String displayText = '',
    String modelRef = '',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || sending) {
      await _log(
        'send user message ignored empty=${trimmed.isEmpty} sending=$sending',
      );
      return;
    }
    final visibleText = displayText.trim().isEmpty
        ? displayTextFromUserPrompt(trimmed)
        : displayText.trim();
    final runModelRef = _chatModelRefForSend(modelRef);
    await _log(
      'send user message requested length=${trimmed.length} modelRef=$runModelRef',
    );
    statusMessage = 'Preparing managed chat runtime';
    _notifyControllerListeners();
    final runtimeReady = await _ensureChatRuntimeReady();
    final ready = runtimeReady && await _ensureLiveSession();
    final sessionId = selectedSessionId;
    messages = <ChatMessage>[
      ...messages,
      ChatMessage(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        role: ChatRole.user,
        author: 'You',
        text: visibleText,
        createdAt: DateTime.now(),
      ),
    ];
    if (!ready || sessionId == null) {
      await _log('send user message blocked: no live session');
      messages = <ChatMessage>[
        ...messages,
        ChatMessage(
          id: 'runtime-${DateTime.now().microsecondsSinceEpoch}',
          role: ChatRole.tool,
          author: 'Runtime',
          text: _agentUnavailableMessage(),
          createdAt: DateTime.now(),
        ),
      ];
      sending = false;
      _notifyControllerListeners();
      return;
    }
    sending = true;
    _notifyControllerListeners();
    await _log('streaming run for session $sessionId');
    await _streamRun(
      sessionId: sessionId,
      text: trimmed,
      modelRef: runModelRef,
    );
  }

  /// Responds to a pending runtime confirmation request.
  Future<void> answerConfirmation(ConfirmationOption option) async {
    final confirmation = pendingConfirmation;
    final sessionId = selectedSessionId;
    if (confirmation == null || sessionId == null) {
      return;
    }
    pendingConfirmation = null;
    _notifyControllerListeners();
    await _sendConfirmationReply(
      sessionId: sessionId,
      confirmation: confirmation,
      option: option,
    );
  }

  /// Sends a runtime confirmation response back to the active assistant session.
  Future<void> _sendConfirmationReply({
    required String sessionId,
    required ConfirmationRequest confirmation,
    required ConfirmationOption option,
  }) async {
    await _streamRun(
      sessionId: sessionId,
      reply: ConfirmationReply(
        callId: confirmation.callId,
        confirmed: option.action != 'deny',
        action: option.action,
      ),
    );
  }

  /// Returns the best non-denial option for an auto-approved task operation.
  ConfirmationOption _approvalOption(ConfirmationRequest confirmation) {
    return confirmation.options.firstWhere(
      (option) => option.action != 'deny',
      orElse: () =>
          const ConfirmationOption(action: 'approve_once', label: 'Approve'),
    );
  }

  /// Reports whether a confirmation can be satisfied without user interaction.
  bool _shouldAutoApproveTaskConfirmation(ConfirmationRequest confirmation) {
    return _taskWriteToolNames.contains(confirmation.toolName);
  }

  /// Loads live runtime sessions while preserving saved chat selection.
  Future<void> _loadSessions() async {
    await _log('load sessions start');
    try {
      final loaded = await assistantClient.listSessions();
      await _log('load sessions returned ${loaded.length}');
      sessions = loaded;
      if (loaded.isNotEmpty) {
        await _mergeHistorySessions(loaded);
        selectedSessionId = loaded.first.id;
        await selectSession(loaded.first.id);
      } else {
        await _log(
          'load sessions empty; preserving local chat history ${chatHistory.length}',
        );
        if (!_restoreSelectedChatFromHistory()) {
          selectedSessionId = null;
          selectedChatHistoryKey = '';
        }
        messages = const <ChatMessage>[];
      }
      _setEndpoint('Agent API', ConnectionStateKind.connected, 'Connected');
    } catch (error) {
      await _log('load sessions failed: $error');
      _setEndpoint(
        'Agent API',
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    }
  }

  /// Merges runtime sessions into the local chat history.
  Future<void> _mergeHistorySessions(List<ChatSession> loaded) async {
    var changed = false;
    final entriesByKey = <String, ChatHistoryEntry>{
      for (final entry in chatHistory) entry.key: entry,
    };
    if (runtimeProfile == null) {
      return;
    }
    for (final session in loaded) {
      final key = _chatHistoryKey(session.id);
      final existing = entriesByKey[key];
      final entry = _historyEntryForSession(session, existing: existing);
      if (existing == null ||
          existing.updatedAt != entry.updatedAt ||
          existing.agentLabel != entry.agentLabel) {
        entriesByKey[key] = entry;
        changed = true;
      }
    }
    if (!changed) {
      return;
    }
    chatHistory = _sortedHistory(entriesByKey.values);
    await chatHistoryStore.save(chatHistory);
  }

  /// Adds or updates one chat history entry.
  Future<void> _upsertHistoryChat(ChatSession session) async {
    final entriesByKey = <String, ChatHistoryEntry>{
      for (final entry in chatHistory) entry.key: entry,
    };
    final key = _chatHistoryKey(session.id);
    entriesByKey[key] = _historyEntryForSession(
      session,
      existing: entriesByKey[key],
    );
    chatHistory = _sortedHistory(entriesByKey.values);
    await chatHistoryStore.save(chatHistory);
  }

  /// Updates an active chat's history timestamp after it is selected.
  Future<void> _touchHistoryChat(String sessionId) async {
    if (runtimeProfile == null) {
      return;
    }
    final session = sessions.firstWhere(
      (candidate) => candidate.id == sessionId,
      orElse: () => ChatSession(
        id: sessionId,
        title: titleFromSession(sessionId),
        updatedAt: DateTime.now(),
      ),
    );
    await _upsertHistoryChat(session);
  }

  /// Builds a history entry for a session in the active agent.
  ChatHistoryEntry _historyEntryForSession(
    ChatSession session, {
    ChatHistoryEntry? existing,
  }) {
    final existingTitle = existing?.title.trim() ?? '';
    return ChatHistoryEntry(
      agentPath: defaultAgentConfigPath,
      agentLabel: activeAgentLabel,
      sessionId: session.id,
      title: existingTitle.isEmpty ? session.title : existingTitle,
      createdAt: existing?.createdAt ?? session.updatedAt,
      updatedAt: session.updatedAt,
      titleStatus: existing?.titleStatus ?? 'session',
      titleError: existing?.titleError ?? '',
    );
  }

  /// Persists one chat history entry without re-reading the whole history.
  Future<void> _saveHistoryEntry(ChatHistoryEntry entry) async {
    final entriesByKey = <String, ChatHistoryEntry>{
      for (final existing in chatHistory) existing.key: existing,
    };
    entriesByKey[entry.key] = entry;
    chatHistory = _sortedHistory(entriesByKey.values);
    await chatHistoryStore.save(chatHistory);
    _notifyControllerListeners();
  }

  /// Removes one chat from the local history.
  Future<void> _removeHistoryChat({required String sessionId}) async {
    final key = _chatHistoryKey(sessionId);
    chatHistory = _sortedHistory(
      chatHistory.where((entry) => entry.key != key),
    );
    await chatHistoryStore.save(chatHistory);
  }

  /// Reports whether the active harness session list includes a session.
  bool _hasLiveSession(String sessionId) {
    return sessions.any((session) => session.id == sessionId);
  }

  /// Ensures a successfully loaded session is present in local live state.
  void _rememberLiveSession(String sessionId) {
    if (_hasLiveSession(sessionId)) {
      return;
    }
    final entry = _historyEntryByKey(_chatHistoryKey(sessionId));
    sessions = <ChatSession>[
      ChatSession(
        id: sessionId,
        title: entry?.title ?? titleFromSession(sessionId),
        updatedAt: entry?.updatedAt ?? DateTime.now(),
      ),
      ...sessions,
    ];
  }

  /// Returns one history entry by stable key.
  ChatHistoryEntry? _historyEntryByKey(String key) {
    for (final entry in chatHistory) {
      if (entry.key == key) {
        return entry;
      }
    }
    return null;
  }

  /// Resolves a chat picker key to a session id.
  ({String sessionId})? _chatTargetFromKey(String key) {
    final entry = _historyEntryByKey(key);
    if (entry != null) {
      return (sessionId: entry.sessionId);
    }
    final trimmed = key.trim();
    return trimmed.isEmpty ? null : (sessionId: trimmed);
  }

  /// Starts model-backed chat title refresh without blocking chat display.
  void _scheduleChatTitleRefresh({
    required String sessionId,
    required List<ChatMessage> transcript,
  }) {
    unawaited(
      _refreshChatTitle(
        sessionId: sessionId,
        transcript: transcript,
      ).catchError((Object error) {
        return _log('chat title refresh crashed for $sessionId: $error');
      }),
    );
  }

  /// Generates and persists a chat title with a deterministic fallback.
  Future<void> _refreshChatTitle({
    required String sessionId,
    required List<ChatMessage> transcript,
  }) async {
    final titleModelConfigPath = summaryModelConfigPath;
    final titleModelRef = summaryModelRef;
    if (sessionId.trim().isEmpty) {
      await _log('chat title refresh skipped: missing session id');
      return;
    }
    final key = _chatHistoryKey(sessionId);
    final entry = _historyEntryByKey(key);
    if (entry == null) {
      await _log('chat title refresh skipped for $sessionId: no history entry');
      return;
    }
    final status = entry.titleStatus.trim();
    if (status == 'generated' ||
        (status == 'pending' && appSettings.chatTitleSummariesEnabled)) {
      await _log('chat title refresh skipped for $sessionId: status=$status');
      return;
    }
    if (status == 'manual' && !_isFallbackChatTitle(entry.title, sessionId)) {
      await _log('chat title refresh skipped for $sessionId: manual title');
      return;
    }
    if (!appSettings.chatTitleSummariesEnabled) {
      await _saveFallbackChatTitle(
        sessionId: sessionId,
        transcript: transcript,
        reason: 'disabled',
        entry: entry,
      );
      return;
    }
    if (titleModelConfigPath.isEmpty) {
      await _saveFallbackChatTitle(
        sessionId: sessionId,
        transcript: transcript,
        reason: 'no title model',
        entry: entry,
      );
      return;
    }
    await _saveHistoryEntry(
      entry.copyWith(titleStatus: 'pending', titleError: ''),
    );
    await _log(
      'chat title refresh started for $sessionId using $titleModelConfigPath'
      '${titleModelRef.isEmpty ? '' : ' $titleModelRef'}',
    );
    try {
      final modelConfigContent =
          appSettings.summaryModelConfigPath.trim().isNotEmpty
          ? await readConfigurationFile(titleModelConfigPath)
          : await _readRuntimeModelConfigContent(titleModelConfigPath);
      final title = await titleClient.generateTitle(
        modelConfigContent: modelConfigContent,
        modelRef: titleModelRef,
        messages: transcript,
      );
      final current = _historyEntryByKey(key) ?? entry;
      await _saveHistoryEntry(
        current.copyWith(
          title: title,
          titleStatus: 'generated',
          titleError: '',
        ),
      );
      await _log('generated title for chat $sessionId: $title');
    } catch (error) {
      final current = _historyEntryByKey(key) ?? entry;
      await _saveHistoryEntry(
        current.copyWith(
          title: _fallbackChatTitleFromTranscript(transcript, sessionId),
          titleStatus: 'failed',
          titleError: error.toString(),
        ),
      );
      await _log('chat title generation failed for $sessionId: $error');
    }
  }

  /// Saves a transcript-derived title when model summarization is unavailable.
  Future<void> _saveFallbackChatTitle({
    required String sessionId,
    required List<ChatMessage> transcript,
    required String reason,
    required ChatHistoryEntry entry,
  }) async {
    final status = entry.titleStatus.trim();
    if (status == 'generated' ||
        (status == 'manual' && !_isFallbackChatTitle(entry.title, sessionId))) {
      await _log('chat title fallback skipped for $sessionId: status=$status');
      return;
    }
    final title = _fallbackChatTitleFromTranscript(transcript, sessionId);
    await _saveHistoryEntry(
      entry.copyWith(title: title, titleStatus: 'fallback', titleError: ''),
    );
    await _log('chat title fallback saved for $sessionId: $reason');
  }

  /// Reads a model config referenced by the active agent runtime topology.
  Future<String> _readRuntimeModelConfigContent(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw const FileSystemException('Runtime model config path is empty');
    }
    final file = File(trimmed);
    if (!await file.exists()) {
      throw FileSystemException('Runtime model config does not exist', trimmed);
    }
    return file.readAsString();
  }

  Future<bool> _ensureLiveSession() async {
    final sessionId = selectedSessionId;
    if (sessionId != null && _hasLiveSession(sessionId)) {
      await _log('live session already selected $sessionId');
      return true;
    }
    if (sessionId != null) {
      await _log('selected session missing from live harness list $sessionId');
      await _log('preserving chat history entry for missing live session');
      selectedSessionId = null;
      selectedChatHistoryKey = '';
      messages = const <ChatMessage>[];
    }
    await _log('no selected session; creating chat');
    return createChat();
  }

  /// Starts required local services before creating or continuing a chat.
  Future<bool> _ensureChatRuntimeReady() async {
    await _ensureInitialized();
    if (_isClosing) {
      statusMessage = 'Agent Awesome runtime is shutting down';
      _notifyControllerListeners();
      return false;
    }
    final profile = runtimeProfile;
    if (profile == null) {
      return false;
    }
    try {
      _throwIfClosing();
      localProcessStatuses = await _startRequiredRuntimeServices(profile);
      _throwIfClosing();
      await _startConfiguredLocalModelRuntime();
      final failures = localProcessStatuses
          .where((status) => status.state == ConnectionStateKind.disconnected)
          .toList();
      if (failures.isNotEmpty) {
        statusMessage = failures
            .map((status) => '${status.name}: ${status.message}')
            .join(' | ');
        await _log('chat runtime unavailable: $statusMessage');
        _notifyControllerListeners();
        return false;
      }
      return true;
    } catch (error) {
      statusMessage = error.toString();
      await _log('chat runtime readiness failed: $error');
      _notifyControllerListeners();
      return false;
    }
  }

  String _agentUnavailableMessage() {
    final profile = runtimeProfile;
    if (profile == null) {
      return statusMessage;
    }
    for (final status in localProcessStatuses) {
      if (status.name == profile.harness.label &&
          status.state == ConnectionStateKind.disconnected &&
          status.message.isNotEmpty) {
        return 'Agent Awesome could not start the managed harness: ${status.message}';
      }
    }
    for (final status in localProcessStatuses) {
      if (_isLocalModelProcessStatus(status) &&
          status.state == ConnectionStateKind.disconnected &&
          status.message.isNotEmpty) {
        return 'Agent Awesome could not start the local model: ${status.message}';
      }
    }
    for (final status in endpointStatuses) {
      if (status.name == 'Agent API' &&
          status.state == ConnectionStateKind.disconnected &&
          status.message.isNotEmpty) {
        return 'Agent Awesome could not reach the managed Agent API: ${status.message}';
      }
    }
    return 'Agent Awesome is still preparing the managed Agent API.';
  }

  Future<void> _streamRun({
    required String sessionId,
    String text = '',
    ConfirmationReply? reply,
    String modelRef = '',
  }) async {
    try {
      await _log(
        'stream run start session=$sessionId textLength=${text.length} confirmation=${reply != null} modelRef=$modelRef',
      );
      var count = 0;
      ConfirmationRequest? autoConfirmation;
      await for (final event in assistantClient.sendMessage(
        sessionId: sessionId,
        text: text,
        confirmation: reply,
        modelRef: modelRef,
      )) {
        count++;
        await _log(
          'stream event #$count author=${event.author} textLength=${event.text.length} partial=${event.partial} tool=${event.toolActivity?.name ?? ''} error=${event.errorMessage.isNotEmpty}',
        );
        _restoreChatModelRefFromEvent(event);
        autoConfirmation ??= _applyEvent(event, sessionId: sessionId);
      }
      await _log('stream run complete session=$sessionId events=$count');
      if (count == 0) {
        messages = <ChatMessage>[
          ...messages,
          ChatMessage(
            id: 'runtime-${DateTime.now().microsecondsSinceEpoch}',
            role: ChatRole.tool,
            author: 'Runtime',
            text:
                'The Agent API completed the run without returning any stream events. Check ${config.serviceLogDirectory}/ui.log and harness.log for the request trace.',
            createdAt: DateTime.now(),
          ),
        ];
      }
      _setEndpoint('Agent API', ConnectionStateKind.connected, 'Run complete');
      if (autoConfirmation != null) {
        await _log(
          'auto-approving task confirmation for ${autoConfirmation.toolName}',
        );
        await _sendConfirmationReply(
          sessionId: sessionId,
          confirmation: autoConfirmation,
          option: _approvalOption(autoConfirmation),
        );
      }
      if (reply == null) {
        _scheduleChatTitleRefresh(
          sessionId: sessionId,
          transcript: List<ChatMessage>.from(messages),
        );
      }
    } catch (error) {
      await _log('stream run failed session=$sessionId: $error');
      _setEndpoint(
        'Agent API',
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      sending = false;
      _notifyControllerListeners();
    }
  }

  /// Selects the model ref used for future chat turns.
  void selectChatModelRef(String modelRef) {
    final normalized = _normalizeChatModelRef(modelRef);
    if (chatModelRef == normalized) {
      return;
    }
    chatModelRef = normalized;
    _notifyControllerListeners();
  }

  /// Model choices available to the active chat profile.
  List<ModelConfigChoice> get chatModelChoices {
    return _activeModelConfigEntry()?.modelChoices ??
        const <ModelConfigChoice>[];
  }

  /// Effective model ref used when sending without an explicit override.
  String get activeChatModelRef {
    return _chatModelRefForSend('');
  }

  /// Effective model choice used when sending without an explicit override.
  ModelConfigChoice? get activeChatModelChoice {
    final activeRef = activeChatModelRef;
    for (final choice in chatModelChoices) {
      if (choice.ref == activeRef) {
        return choice;
      }
    }
    return null;
  }

  /// Returns the configured model file currently assigned to the profile.
  ConfigFileEntry? _activeModelConfigEntry() {
    final path = runtimeProfile?.harness.modelConfigPath.trim() ?? '';
    for (final entry in availableModelConfigs) {
      if (entry.path == path || entry.assigned) {
        return entry;
      }
    }
    return null;
  }

  /// Resolves an explicit or selected model ref to a configured choice.
  String _chatModelRefForSend(String explicitRef) {
    final choices = chatModelChoices;
    if (choices.isEmpty) {
      return '';
    }
    final requested = _normalizeChatModelRef(
      explicitRef.trim().isEmpty ? chatModelRef : explicitRef,
    );
    for (final choice in choices) {
      if (choice.ref == requested) {
        return choice.ref;
      }
    }
    for (final choice in choices) {
      if (choice.isDefault) {
        return choice.ref;
      }
    }
    return choices.first.ref;
  }

  /// Restores the composer model from the latest routed event in a chat.
  void _restoreChatModelRefFromEvents(List<AssistantEvent> events) {
    for (final event in events.reversed) {
      if (_restoreChatModelRefFromEvent(event)) {
        return;
      }
    }
  }

  /// Restores the composer model from one event when it names a known model.
  bool _restoreChatModelRefFromEvent(AssistantEvent event) {
    final modelRef = _normalizeChatModelRef(event.modelRef);
    if (modelRef.isEmpty || !_chatModelChoiceExists(modelRef)) {
      return false;
    }
    chatModelRef = modelRef;
    return true;
  }

  /// Reports whether a provider:model ref belongs to the active model config.
  bool _chatModelChoiceExists(String modelRef) {
    for (final choice in chatModelChoices) {
      if (choice.ref == modelRef) {
        return true;
      }
    }
    return false;
  }

  /// Adds missing assistant route labels from the most recent routed turn.
  List<AssistantEvent> _chatEventsWithInheritedModelRefs(
    List<AssistantEvent> events,
  ) {
    var latestModelRef = '';
    final restored = <AssistantEvent>[];
    for (final event in events) {
      if (event.modelRef.trim().isNotEmpty) {
        latestModelRef = event.modelRef.trim();
      }
      restored.add(_chatEventWithInheritedModelRef(event, latestModelRef));
    }
    return restored;
  }

  /// Returns an event with a restored model ref when storage omitted it.
  AssistantEvent _chatEventWithInheritedModelRef(
    AssistantEvent event,
    String latestModelRef,
  ) {
    if (event.modelRef.trim().isNotEmpty ||
        latestModelRef.trim().isEmpty ||
        event.author == 'user') {
      return event;
    }
    return AssistantEvent(
      id: event.id,
      author: event.author,
      text: event.text,
      partial: event.partial,
      toolActivity: event.toolActivity,
      confirmation: event.confirmation,
      modelRef: latestModelRef.trim(),
      errorMessage: event.errorMessage,
    );
  }

  /// Normalizes user-facing model refs before storing or sending them.
  String _normalizeChatModelRef(String modelRef) {
    return modelRef.trim();
  }
}
