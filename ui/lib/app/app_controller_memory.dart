/// Memory stewardship and file-source workflows for AgentAwesomeAppController.
part of 'app_controller.dart';

extension AgentAwesomeAppControllerMemory on AgentAwesomeAppController {
  /// Returns the selected memory record when it is still visible.
  MemoryRecord? get selectedMemory {
    for (final record in workspace.memoryRecords) {
      if (record.id == selectedMemoryId) {
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
    try {
      final records = await memoryClient.searchSources(
        firewall: memory.firewall,
        text: memory.title,
        kinds: memoryFilters.kinds,
        allowedSensitivities: _sensitivitiesIncluding(memory.sensitivity),
        limit: memoryFilters.limit,
      );
      final hydrated = records.where((record) => record.id == memory.id);
      if (hydrated.isNotEmpty) {
        _replaceMemoryRecord(hydrated.first);
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
    try {
      await memoryClient.saveMemoryCandidate(
        draft: draft,
        idempotencyKey: idempotencyKey.trim().isEmpty
            ? 'agent_awesome_ui:${DateTime.now().microsecondsSinceEpoch}:${draft.title}'
            : idempotencyKey.trim(),
      );
      memoryMessage = 'Memory candidate saved';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
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

  /// Imports a local source file and stores it as a memory-backed file.
  Future<void> importFileFromUi() async {
    memoryBusy = true;
    memoryMessage = 'Selecting file';
    _notifyControllerListeners();
    try {
      final imported = await fileImporter.pickFile();
      if (imported == null) {
        memoryMessage = 'File import canceled';
        return;
      }
      await memoryClient.saveMemoryCandidate(
        draft: imported.toMemoryDraft(),
        idempotencyKey: imported.idempotencyKey,
      );
      memoryMessage = 'Imported ${imported.name}';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
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
    try {
      final records = await memoryClient.searchSources(
        firewall: file.firewall,
        text: file.title,
        kinds: <String>[file.kind],
        allowedSensitivities: _sensitivitiesIncluding(file.sensitivity),
        limit: 20,
      );
      for (final record in records) {
        if (record.id == file.id || record.evidenceId == file.evidenceId) {
          _replaceMemoryRecord(record);
          return record;
        }
      }
    } catch (error) {
      await _log('file source hydration failed: $error');
    }
    return file;
  }

  /// Builds the text payload used by the current ADK chat endpoint.
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
    try {
      final repaired = await memoryClient.repairMemoryRecord(draft: draft);
      _replaceMemoryRecord(repaired);
      selectedMemoryId = repaired.id;
      memoryMessage = 'Memory metadata repaired';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
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
    try {
      await memoryClient.submitMemoryCorrection(
        memoryId: memory.id,
        text: text,
        firewall: memory.firewall,
      );
      memoryMessage = 'Correction saved as new memory';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
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
    try {
      selectedMemoryPage = await memoryClient.loadEntityPage(
        firewall: memory.firewall,
        entityId: memory.entityIds.isEmpty ? '' : memory.entityIds.first,
        title: memory.entityNames.isEmpty
            ? memory.title
            : memory.entityNames.first,
      );
      memoryMessage = 'Entity page loaded';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
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
    try {
      selectedMemoryPage = await memoryClient.loadTimeline(
        firewall: memory.firewall,
        topic: topic.trim(),
        entityId: memory.entityIds.isEmpty ? '' : memory.entityIds.first,
      );
      memoryMessage = 'Timeline loaded';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
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
    try {
      selectedMemoryPage = await memoryClient.refreshCompiledPage(
        kind: page.kind,
        firewall: page.firewall,
        title: page.title,
        topic: page.kind == 'timeline' ? page.title : '',
      );
      memoryMessage = 'Compiled page refreshed';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
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
        final client = _memoryClientFor(server);
        try {
          records.addAll(
            await client.searchMemory(
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
        } finally {
          if (!identical(client, memoryClient)) {
            client.close();
          }
        }
      }
      workspace = ProjectWorkspace(
        title: workspace.title,
        subtitle: workspace.subtitle,
        tasks: workspace.tasks,
        sources: records.map((record) {
          return SourceItem(
            id: record.id,
            title: record.title,
            detail: '${record.kind} • ${record.sourceLabel}',
          );
        }).toList(),
        memoryRecords: records,
      );
      if (records.isEmpty) {
        selectedMemoryId = null;
      } else if (selectedMemoryId == null ||
          !records.any((record) => record.id == selectedMemoryId)) {
        selectedMemoryId = records.first.id;
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
      return record.id == replacement.id ? replacement : record;
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
}
