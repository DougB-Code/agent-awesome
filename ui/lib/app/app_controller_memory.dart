/// Memory stewardship and file-source workflows for AgentAwesomeAppController.
part of 'app_controller.dart';

extension AgentAwesomeAppControllerMemory on AgentAwesomeAppController {
  /// Returns the stable selection key for a memory record across domains.
  String memorySelectionKey(MemoryRecord record) {
    return _memorySelectionKey(record);
  }

  /// Returns the selected memory record when it is still visible.
  MemoryRecord? get selectedMemory {
    for (final record in workspace.memoryRecords) {
      if (_memorySelectionKey(record) == selectedMemoryId ||
          record.id == selectedMemoryId) {
        return record;
      }
    }
    if (workspace.memoryRecords.isEmpty) {
      return null;
    }
    return workspace.memoryRecords.first;
  }

  /// Returns records after applying local filters unsupported by retrieval.
  List<MemoryRecord> get filteredMemoryRecords {
    return workspace.memoryRecords.where((record) {
      if (memoryFilters.localStatus.isNotEmpty &&
          record.status != memoryFilters.localStatus) {
        return false;
      }
      if (memoryFilters.localTrustLevel.isNotEmpty &&
          record.trustLevel != memoryFilters.localTrustLevel) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Applies memory filters and reloads records from the service.
  Future<void> applyMemoryFilters(MemoryFilterState filters) async {
    memoryFilters = filters;
    await _loadMemory();
  }

  /// Selects a memory and hydrates its source preview when possible.
  Future<void> selectMemory(String memoryId) async {
    selectedMemoryId = memoryId;
    for (final record in workspace.memoryRecords) {
      if (_memorySelectionKey(record) == memoryId || record.id == memoryId) {
        selectedMemoryId = _memorySelectionKey(record);
        break;
      }
    }
    selectedMemoryPage = null;
    _notifyControllerListeners();
    await hydrateSelectedMemorySource();
  }

  /// Loads raw source text for the selected memory without mutating source truth.
  Future<void> hydrateSelectedMemorySource() async {
    final memory = selectedMemory;
    if (memory == null || memory.rawContent.isNotEmpty) {
      return;
    }
    memoryBusy = true;
    memoryMessage = 'Loading source content';
    _notifyControllerListeners();
    final server = _memoryServerForRecord(memory);
    try {
      final records = await _withMemoryClientForServer(
        server,
        (client) => client.searchSources(
          actor: _memoryActor(),
          firewall: memory.firewall,
          text: memory.title,
          kinds: memoryFilters.kinds,
          allowedSensitivities: _sensitivitiesIncluding(memory.sensitivity),
          limit: memoryFilters.limit,
        ),
      );
      final hydrated = records.where((record) => record.id == memory.id);
      if (hydrated.isNotEmpty) {
        _replaceMemoryRecord(_withRecordDomain(hydrated.first, server));
        memoryMessage = 'Source content loaded';
      } else {
        memoryMessage = 'Source content was not returned by search';
      }
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
    } catch (error) {
      memoryMessage = error.toString();
      workspace = ProjectWorkspace(
        title: workspace.title,
        subtitle: workspace.subtitle,
        tasks: workspace.tasks,
        sources: const <SourceItem>[],
        memoryRecords: const <MemoryRecord>[],
      );
      selectedMemoryId = null;
      selectedMemoryPage = null;
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Saves a reviewed memory candidate as immutable source-backed content.
  Future<void> saveMemoryCandidateFromUi(
    MemoryCaptureDraft draft, {
    String idempotencyKey = '',
  }) async {
    memoryBusy = true;
    memoryMessage = 'Saving reviewed memory candidate';
    _notifyControllerListeners();
    final server = _defaultWriteMemoryServer();
    try {
      await _withMemoryClientForServer(
        server,
        (client) => client.saveMemoryCandidate(
          draft: draft,
          actor: _memoryActor(),
          idempotencyKey: idempotencyKey.trim().isEmpty
              ? 'agent_awesome_ui:${DateTime.now().microsecondsSinceEpoch}:${draft.title}'
              : idempotencyKey.trim(),
        ),
      );
      memoryMessage = 'Memory candidate saved';
      _setEndpoint(server.label, ConnectionStateKind.connected, memoryMessage);
      await _loadMemory();
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Exports a user-reviewed copy from one memory domain to the default domain.
  Future<bool> exportMemoryCopyFromUi(
    MemoryRecord source,
    MemoryExportDraft draft,
  ) async {
    final sourceDomain = source.domainId.trim();
    final target = _defaultWriteMemoryServer();
    if (sourceDomain.isEmpty || sourceDomain == target.id) {
      memoryMessage = 'Memory is already in the default write domain';
      _recordMemorySafetyEvent(
        kind: 'skipped_export',
        severity: 'info',
        title: 'Export not needed',
        detail: memoryMessage,
        sourceDomain: sourceDomain,
        targetDomain: target.id,
        sourceMemoryId: source.id,
        approved: false,
      );
      _notifyControllerListeners();
      return false;
    }
    if (!_memoryDomainFlowAllowed(sourceDomain, target.id)) {
      memoryMessage =
          'Export blocked: ${memoryDomainLabel(sourceDomain)} cannot write to ${target.label}';
      _recordMemorySafetyEvent(
        kind: 'blocked_export',
        severity: 'warning',
        title: 'Export blocked',
        detail: memoryMessage,
        sourceDomain: sourceDomain,
        targetDomain: target.id,
        sourceMemoryId: source.id,
        approved: false,
      );
      _notifyControllerListeners();
      return false;
    }
    final content = draft.content.trim();
    if (content.isEmpty) {
      return false;
    }
    memoryBusy = true;
    memoryMessage = 'Exporting reviewed memory copy';
    _notifyControllerListeners();
    try {
      await _withMemoryClientForServer(
        target,
        (client) => client.saveMemoryCandidate(
          draft: MemoryCaptureDraft(
            content: content,
            title: draft.title.trim().isEmpty
                ? source.title
                : draft.title.trim(),
            kind: source.kind,
            firewall: draft.firewall.trim().isEmpty
                ? source.firewall
                : draft.firewall.trim(),
            trustLevel: 'user_asserted',
            sensitivity: draft.sensitivity.trim().isEmpty
                ? source.sensitivity
                : draft.sensitivity.trim(),
            sourceSystem: 'agent_awesome_declassification',
            sourceId: _memoryExportSourceId(source),
            subjects: source.subjects,
            topics: source.topics,
            entityNames: source.entityNames,
          ),
          actor: _memoryActor(),
          idempotencyKey:
              'agent_awesome_declassification:$sourceDomain:${source.id}:${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      memoryMessage = 'Reviewed memory copy exported';
      _recordMemorySafetyEvent(
        kind: 'approved_export',
        severity: 'review',
        title: 'Reviewed memory copy exported',
        detail:
            '${memoryDomainLabel(sourceDomain)} -> ${target.label}: ${source.title}',
        sourceDomain: sourceDomain,
        targetDomain: target.id,
        sourceMemoryId: source.id,
        approved: true,
      );
      _setEndpoint(target.label, ConnectionStateKind.connected, memoryMessage);
      await _loadMemory();
      return true;
    } catch (error) {
      memoryMessage = error.toString();
      _recordMemorySafetyEvent(
        kind: 'failed_export',
        severity: 'error',
        title: 'Export failed',
        detail: memoryMessage,
        sourceDomain: sourceDomain,
        targetDomain: target.id,
        sourceMemoryId: source.id,
        approved: false,
      );
      _setEndpoint(
        target.label,
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
      return false;
    } finally {
      memoryBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Reports whether a record can be copied into the default write domain.
  bool canExportMemoryRecord(MemoryRecord record) {
    final sourceDomain = record.domainId.trim();
    final profile = runtimeProfile;
    if (profile == null || sourceDomain.isEmpty) {
      return false;
    }
    final targetDomain = profile.agentMemory.defaultWriteDomain;
    return sourceDomain != targetDomain &&
        _memoryDomainFlowAllowed(sourceDomain, targetDomain);
  }

  /// Returns a human-readable memory domain label.
  String memoryDomainLabel(String domainId) {
    final id = domainId.trim();
    if (id.isEmpty) {
      return '';
    }
    final profile = runtimeProfile;
    if (profile != null) {
      for (final domain in profile.memoryDomains) {
        if (domain.id == id) {
          return domain.label.trim().isEmpty ? domain.id : domain.label;
        }
      }
    }
    return id;
  }

  /// Clears reviewed memory-domain safety events.
  void clearMemorySafetyEvents() {
    memorySafetyEvents = const <MemorySafetyEvent>[];
    _notifyControllerListeners();
  }

  /// Imports a local source file and stores it as a memory-backed file.
  Future<void> importFileFromUi() async {
    memoryBusy = true;
    memoryMessage = 'Selecting file';
    _notifyControllerListeners();
    final server = _defaultWriteMemoryServer();
    try {
      final imported = await fileImporter.pickFile();
      if (imported == null) {
        memoryMessage = 'File import canceled';
        return;
      }
      await _withMemoryClientForServer(
        server,
        (client) => client.saveMemoryCandidate(
          draft: imported.toMemoryDraft(),
          actor: _memoryActor(),
          idempotencyKey: imported.idempotencyKey,
        ),
      );
      memoryMessage = 'Imported ${imported.name}';
      _setEndpoint(server.label, ConnectionStateKind.connected, memoryMessage);
      await _loadMemory();
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Sends one indexed file to the current chat using the active model policy.
  Future<void> sendFileToChatFromUi(MemoryRecord file) async {
    final hydrated = await _hydratedFileRecord(file);
    final capabilities = await activeModelFileCapabilities();
    final payload = _fileChatPrompt(hydrated, capabilities);
    await sendUserMessage(payload, displayText: 'Review ${hydrated.title}');
  }

  /// Resolves the active model's file handling from the harness model config.
  Future<ModelFileCapabilities> activeModelFileCapabilities() async {
    final path = runtimeProfile?.harness.modelConfigPath.trim() ?? '';
    if (path.isEmpty) {
      return fallbackModelFileCapabilities('No active model config is loaded.');
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        return fallbackModelFileCapabilities(
          'The active model config was not found.',
        );
      }
      final document = ModelConfigDocument.parse(await file.readAsString());
      final selection = activeModelFileSelection(document);
      if (selection == null) {
        return fallbackModelFileCapabilities(
          'The active model config has no usable provider/model selection.',
        );
      }
      return modelFileCapabilitiesFor(
        provider: selection.provider,
        model: selection.model,
      );
    } catch (error) {
      return fallbackModelFileCapabilities(
        'Could not inspect model file support: $error',
      );
    }
  }

  /// Loads raw source text for a file record before sending it to chat.
  Future<MemoryRecord> _hydratedFileRecord(MemoryRecord file) async {
    if (file.rawContent.trim().isNotEmpty) {
      return file;
    }
    final server = _memoryServerForRecord(file);
    try {
      final records = await _withMemoryClientForServer(
        server,
        (client) => client.searchSources(
          actor: _memoryActor(),
          firewall: file.firewall,
          text: file.title,
          kinds: <String>[file.kind],
          allowedSensitivities: _sensitivitiesIncluding(file.sensitivity),
          limit: 20,
        ),
      );
      for (final record in records) {
        if (record.id == file.id || record.evidenceId == file.evidenceId) {
          final hydrated = _withRecordDomain(record, server);
          _replaceMemoryRecord(hydrated);
          return hydrated;
        }
      }
    } catch (error) {
      await _log('file source hydration failed: $error');
    }
    return file;
  }

  /// Builds the text payload used by the current chat endpoint.
  String _fileChatPrompt(
    MemoryRecord file,
    ModelFileCapabilities capabilities,
  ) {
    final title = file.title.trim().isEmpty
        ? 'Untitled file'
        : file.title.trim();
    final mediaType = file.rawMediaType.trim().isEmpty
        ? 'application/octet-stream'
        : file.rawMediaType.trim();
    final content = file.rawContent.trim().isEmpty
        ? 'The source content has not been hydrated by the memory service.'
        : file.rawContent.trim();
    final transport = capabilities.usesBase64Fallback
        ? 'base64_text'
        : 'native_file_parts_requested';
    return '''
Please review this file and use it as source material for the conversation.

File name: $title
Media type: $mediaType
Source: ${file.sourceLabel}
Model: ${capabilities.modelName.isEmpty ? 'unknown' : capabilities.modelName}
Native file support detected: ${capabilities.nativeFileParts}
Transport selected: $transport
Transport reason: ${capabilities.reason}

--- file_payload ---
$content
'''
        .trim();
  }

  /// Repairs selected memory metadata without changing raw source content.
  Future<void> repairMemoryFromUi(MemoryRepairDraft draft) async {
    memoryBusy = true;
    memoryMessage = 'Repairing memory metadata';
    _notifyControllerListeners();
    final memory = selectedMemory;
    final server = memory == null
        ? _defaultWriteMemoryServer()
        : _memoryServerForRecord(memory);
    try {
      final repaired = _withRecordDomain(
        await _withMemoryClientForServer(
          server,
          (client) =>
              client.repairMemoryRecord(draft: draft, actor: _memoryActor()),
        ),
        server,
      );
      _replaceMemoryRecord(repaired);
      selectedMemoryId = _memorySelectionKey(repaired);
      memoryMessage = 'Memory metadata repaired';
      _setEndpoint(server.label, ConnectionStateKind.connected, memoryMessage);
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Stores a correction as a new source-backed memory.
  Future<void> submitMemoryCorrectionFromUi(String text) async {
    final memory = selectedMemory;
    if (memory == null) {
      return;
    }
    memoryBusy = true;
    memoryMessage = 'Submitting source-backed correction';
    _notifyControllerListeners();
    final server = _memoryServerForRecord(memory);
    try {
      await _withMemoryClientForServer(
        server,
        (client) => client.submitMemoryCorrection(
          memoryId: memory.id,
          text: text,
          firewall: memory.firewall,
          actor: _memoryActor(),
        ),
      );
      memoryMessage = 'Correction saved as new memory';
      _setEndpoint(server.label, ConnectionStateKind.connected, memoryMessage);
      await _loadMemory();
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Loads or creates a compiled entity page for the selected memory.
  Future<void> loadEntityPageFromUi(MemoryRecord memory) async {
    if (memory.entityIds.isEmpty && memory.entityNames.isEmpty) {
      memoryMessage = 'Select a memory with an entity first';
      _notifyControllerListeners();
      return;
    }
    memoryBusy = true;
    memoryMessage = 'Loading compiled entity page';
    _notifyControllerListeners();
    final server = _memoryServerForRecord(memory);
    try {
      selectedMemoryPage = _withPageDomain(
        await _withMemoryClientForServer(
          server,
          (client) => client.loadEntityPage(
            actor: _memoryActor(),
            firewall: memory.firewall,
            entityId: memory.entityIds.isEmpty ? '' : memory.entityIds.first,
            title: memory.entityNames.isEmpty
                ? memory.title
                : memory.entityNames.first,
          ),
        ),
        server,
      );
      memoryMessage = 'Entity page loaded';
      _setEndpoint(server.label, ConnectionStateKind.connected, memoryMessage);
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Loads or creates a compiled timeline for a topic.
  Future<void> loadTimelineFromUi(String topic) async {
    final memory = selectedMemory;
    if (memory == null || topic.trim().isEmpty) {
      return;
    }
    memoryBusy = true;
    memoryMessage = 'Loading source-backed timeline';
    _notifyControllerListeners();
    final server = _memoryServerForRecord(memory);
    try {
      selectedMemoryPage = _withPageDomain(
        await _withMemoryClientForServer(
          server,
          (client) => client.loadTimeline(
            actor: _memoryActor(),
            firewall: memory.firewall,
            topic: topic.trim(),
            entityId: memory.entityIds.isEmpty ? '' : memory.entityIds.first,
          ),
        ),
        server,
      );
      memoryMessage = 'Timeline loaded';
      _setEndpoint(server.label, ConnectionStateKind.connected, memoryMessage);
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      _notifyControllerListeners();
    }
  }

  /// Refreshes the last loaded compiled memory page.
  Future<void> refreshSelectedMemoryPageFromUi() async {
    final page = selectedMemoryPage;
    if (page == null) {
      return;
    }
    memoryBusy = true;
    memoryMessage = 'Refreshing compiled page';
    _notifyControllerListeners();
    final server = page.domainId.trim().isEmpty
        ? _defaultWriteMemoryServer()
        : _memoryServerForRecord(
            MemoryRecord(
              id: page.id,
              domainId: page.domainId,
              title: page.title,
              summary: '',
              kind: page.kind,
              topics: const <String>[],
              sourceLabel: page.path,
            ),
          );
    try {
      selectedMemoryPage = _withPageDomain(
        await _withMemoryClientForServer(
          server,
          (client) => client.refreshCompiledPage(
            actor: _memoryActor(),
            kind: page.kind,
            firewall: page.firewall,
            title: page.title,
            topic: page.kind == 'timeline' ? page.title : '',
          ),
        ),
        server,
      );
      memoryMessage = 'Compiled page refreshed';
      _setEndpoint(server.label, ConnectionStateKind.connected, memoryMessage);
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      _notifyControllerListeners();
    }
  }

  Future<void> _loadMemory() async {
    await _log('load memory start');
    try {
      memoryBusy = true;
      memoryMessage = 'Searching memory';
      _notifyControllerListeners();
      final records = <MemoryRecord>[];
      final failures = <String>[];
      for (final server in _activeRuntimeProfile().memoryServers) {
        await _log('load memory via ${server.label} ${server.endpoint}');
        try {
          final domainRecords = await _withMemoryClientForServer(
            server,
            (client) => client.searchMemory(
              actor: _memoryActor(),
              firewall: memoryFilters.firewall,
              includeGlobal: memoryFilters.includeGlobal,
              text: memoryFilters.text,
              kinds: memoryFilters.kinds,
              topics: memoryFilters.topics,
              entityIds: memoryFilters.entityIds,
              allowedSensitivities: memoryFilters.allowedSensitivities,
              limit: memoryFilters.limit,
            ),
          );
          records.addAll(
            domainRecords.map((record) => _withRecordDomain(record, server)),
          );
          _setEndpoint(
            server.label,
            ConnectionStateKind.connected,
            'Connected',
          );
        } catch (error) {
          await _log('load memory failed for ${server.label}: $error');
          failures.add('${server.label}: $error');
          _setEndpoint(
            server.label,
            ConnectionStateKind.disconnected,
            error.toString(),
          );
        }
      }
      workspace = ProjectWorkspace(
        title: workspace.title,
        subtitle: workspace.subtitle,
        tasks: workspace.tasks,
        sources: records.map((record) {
          return SourceItem(
            id: _memorySelectionKey(record),
            title: record.title,
            detail:
                '${record.kind} • ${record.sourceLabel} • ${record.domainId}',
          );
        }).toList(),
        memoryRecords: records,
      );
      if (records.isEmpty) {
        selectedMemoryId = null;
      } else if (selectedMemoryId == null ||
          !records.any(
            (record) =>
                _memorySelectionKey(record) == selectedMemoryId ||
                record.id == selectedMemoryId,
          )) {
        selectedMemoryId = _memorySelectionKey(records.first);
      }
      memoryMessage = records.isEmpty
          ? failures.isEmpty
                ? 'No memory records matched the current filters'
                : failures.join(' | ')
          : 'Loaded ${records.length} memory records';
      await _log('load memory complete records=${records.length}');
    } catch (error) {
      await _log('load memory failed: $error');
      memoryMessage = error.toString();
    } finally {
      memoryBusy = false;
    }
    _notifyControllerListeners();
  }

  void _replaceMemoryRecord(MemoryRecord replacement) {
    final records = workspace.memoryRecords.map((record) {
      return _memorySelectionKey(record) == _memorySelectionKey(replacement)
          ? replacement
          : record;
    }).toList();
    workspace = ProjectWorkspace(
      title: workspace.title,
      subtitle: workspace.subtitle,
      tasks: workspace.tasks,
      sources: workspace.sources,
      memoryRecords: records,
    );
  }

  List<String> _sensitivitiesIncluding(String sensitivity) {
    if (memoryFilters.allowedSensitivities.contains(sensitivity)) {
      return memoryFilters.allowedSensitivities;
    }
    return <String>[...memoryFilters.allowedSensitivities, sensitivity];
  }

  /// Checks configured same-domain or explicit memory information flow.
  bool _memoryDomainFlowAllowed(String sourceDomain, String targetDomain) {
    if (sourceDomain == targetDomain) {
      return true;
    }
    final profile = runtimeProfile;
    if (profile == null) {
      return false;
    }
    return profile.agentMemory.allowedFlows.any((flow) {
      return flow.fromDomain == sourceDomain && flow.toDomain == targetDomain;
    });
  }

  /// Builds an auditable source id for an exported memory copy.
  String _memoryExportSourceId(MemoryRecord source) {
    final evidence = source.evidenceId.trim();
    return <String>[
      source.domainId.trim(),
      source.id.trim(),
      if (evidence.isNotEmpty) evidence,
    ].join(':');
  }

  /// Records a bounded in-session memory safety event.
  void _recordMemorySafetyEvent({
    required String kind,
    required String severity,
    required String title,
    required String detail,
    required String sourceDomain,
    required String targetDomain,
    required String sourceMemoryId,
    required bool approved,
  }) {
    final now = DateTime.now();
    final event = MemorySafetyEvent(
      id: 'memory-safety-${now.microsecondsSinceEpoch}',
      kind: kind,
      severity: severity,
      title: title,
      detail: detail,
      sourceDomain: sourceDomain,
      targetDomain: targetDomain,
      sourceMemoryId: sourceMemoryId,
      approved: approved,
      createdAt: now,
    );
    memorySafetyEvents = <MemorySafetyEvent>[
      event,
      ...memorySafetyEvents,
    ].take(100).toList();
  }
}
