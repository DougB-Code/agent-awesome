/// Runtime profile and config-file workflows for AgentAwesomeAppController.
part of 'app_controller.dart';

extension AgentAwesomeAppControllerRuntimeProfiles
    on AgentAwesomeAppController {
  /// Saves the active runtime profile JSON and reconnects owned clients.
  Future<void> saveRuntimeProfile(RuntimeProfile profile) async {
    final path = runtimeProfilePath.trim().isEmpty
        ? RuntimeProfileLoader(config).defaultRuntimeProfilePath()
        : runtimeProfilePath;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(encodeRuntimeProfileJson(profile));
    runtimeProfilePath = path;
    runtimeProfile = profile;
    if (config.autoStartLocalServices) {
      await _saveMemoryFirewallPolicyForActiveProfile();
    }
    await _refreshConfigCollections();
    await _configureClientsForRuntimeProfile(profile);
    _refreshEndpointSkeleton(profile);
    statusMessage = 'Runtime profile saved';
    _notifyControllerListeners();
  }

  /// Loads a different profile from disk and applies its runtime bindings.
  Future<void> loadRuntimeProfileFromPath(
    String path, {
    bool reloadData = true,
  }) async {
    final file = File(path);
    final profile = await RuntimeProfileLoader(config).loadFile(file);
    runtimeProfilePath = file.path;
    runtimeProfile = profile;
    if (config.autoStartLocalServices) {
      await _saveMemoryFirewallPolicyForActiveProfile();
    }
    await _refreshConfigCollections();
    await _configureClientsForRuntimeProfile(profile);
    _refreshEndpointSkeleton(profile);
    statusMessage = 'Runtime profile loaded';
    _notifyControllerListeners();
    if (reloadData) {
      await _loadToolCapabilities();
      await Future.wait(<Future<void>>[
        _loadSessions(),
        _loadMemory(),
        _loadTasks(),
      ]);
    }
  }

  /// Reads a text configuration file referenced by the active profile.
  Future<String> readConfigurationFile(String path) async {
    return configFiles.read(path);
  }

  /// Saves a text configuration file referenced by the active profile.
  Future<void> saveConfigurationFile(String path, String content) async {
    await configFiles.write(path, content);
    statusMessage = 'Saved $path';
    _notifyControllerListeners();
  }

  /// Runs portable validations for one agent package through the harness CLI.
  Future<AgentValidationResult> runAgentPackageValidations(
    String agentPath, {
    String validationId = '',
    String mode = '',
    bool live = false,
    bool requireValidations = false,
    bool requireAssertions = false,
    bool requireToolCalls = false,
    bool requireToolContracts = false,
  }) async {
    final harness = runtimeProfile?.harness;
    final workingDirectory = harness?.workingDirectory.trim().isNotEmpty == true
        ? harness!.workingDirectory
        : '${config.workspaceRoot}/harness';
    final packagePath = harness?.packagePath.trim().isNotEmpty == true
        ? harness!.packagePath
        : './cmd/agent-awesome';
    final result = await processSupervisor.run(
      ManagedProcessSpec(
        id: 'agent-validations-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Agent validations',
        executable: 'go',
        arguments: buildAgentValidationCommandArguments(
          packagePath: packagePath,
          agentPath: agentPath,
          validationId: validationId,
          mode: mode,
          live: live,
          modelPath: harness?.modelConfigPath ?? '',
          toolPath: harness?.toolConfigPath ?? '',
          requireValidations: requireValidations,
          requireAssertions: requireAssertions,
          requireToolCalls: requireToolCalls,
          requireToolContracts: requireToolContracts,
        ),
        workingDirectory: workingDirectory,
        kind: ManagedProcessKind.oneShotCommand,
        shutdownMode: ManagedProcessShutdownMode.processOnly,
        timeout: live
            ? const Duration(minutes: 10)
            : const Duration(minutes: 2),
        scope: 'agent-validations',
      ),
    );
    return parseAgentValidationProcessResult(result);
  }

  /// Runs portable validations for one tool package through the harness CLI.
  Future<ToolValidationSuiteResult> runToolPackageValidations(
    String toolPath, {
    String validationId = '',
    List<String> validationIds = const <String>[],
    String mode = '',
    bool requireAssertions = false,
    bool requireCoverage = false,
    bool requireInputSchemas = false,
  }) async {
    final harness = runtimeProfile?.harness;
    final workingDirectory = harness?.workingDirectory.trim().isNotEmpty == true
        ? harness!.workingDirectory
        : '${config.workspaceRoot}/harness';
    final packagePath = harness?.packagePath.trim().isNotEmpty == true
        ? harness!.packagePath
        : './cmd/agent-awesome';
    final result = await processSupervisor.run(
      ManagedProcessSpec(
        id: 'tool-validations-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Tool validations',
        executable: 'go',
        arguments: buildToolValidationCommandArguments(
          packagePath: packagePath,
          toolPath: toolPath,
          validationId: validationId,
          validationIds: validationIds,
          mode: mode,
          agentPath: harness?.agentConfigPath ?? '',
          modelPath: harness?.modelConfigPath ?? '',
          requireAssertions: requireAssertions,
          requireCoverage: requireCoverage,
          requireInputSchemas: requireInputSchemas,
        ),
        workingDirectory: workingDirectory,
        kind: ManagedProcessKind.oneShotCommand,
        shutdownMode: ManagedProcessShutdownMode.processOnly,
        timeout: const Duration(minutes: 2),
        scope: 'tool-validations',
      ),
    );
    return parseToolValidationProcessResult(result);
  }

  /// Runs portable validations for a shared package library through the harness CLI.
  Future<LibraryValidationResult> runPackageLibraryValidations({
    String root = '.',
    String agentPath = '',
    String agentDir = 'agents',
    String toolPath = '',
    String toolDir = 'tools',
    String mcpDir = 'mcp',
    bool requireAgentValidations = false,
    bool requireAgentAssertions = false,
    bool requireAgentToolCalls = false,
    bool requireAgentToolContracts = false,
    bool requireToolInputSchemas = false,
    bool requireToolCoverage = false,
    bool requireToolAssertions = false,
    bool liveAgents = false,
    String agentMode = '',
    String toolMode = '',
    String runtimeAgentPath = '',
  }) async {
    final harness = runtimeProfile?.harness;
    final agentDirectory = agentDir.trim();
    final toolDirectory = toolDir.trim();
    final mcpDirectory = mcpDir.trim();
    final rootPath = root.trim().isEmpty ? '.' : root.trim();
    final workingDirectory = harness?.workingDirectory.trim().isNotEmpty == true
        ? harness!.workingDirectory
        : '${config.workspaceRoot}/harness';
    final packagePath = harness?.packagePath.trim().isNotEmpty == true
        ? harness!.packagePath
        : './cmd/agent-awesome';
    final result = await processSupervisor.run(
      ManagedProcessSpec(
        id: 'library-validations-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Library validations',
        executable: 'go',
        arguments: buildLibraryValidationCommandArguments(
          packagePath: packagePath,
          rootPath: rootPath,
          agentPath: agentPath,
          agentDirectory: agentDirectory,
          toolPath: toolPath,
          toolDirectory: toolDirectory,
          mcpDirectory: mcpDirectory,
          liveAgents: liveAgents,
          agentMode: agentMode,
          toolMode: toolMode,
          runtimeAgentPath: runtimeAgentPath.trim().isNotEmpty
              ? runtimeAgentPath
              : harness?.agentConfigPath ?? '',
          modelPath: harness?.modelConfigPath ?? '',
          runtimeToolPath: harness?.toolConfigPath ?? '',
          requireAgentValidations: requireAgentValidations,
          requireAgentAssertions: requireAgentAssertions,
          requireAgentToolCalls: requireAgentToolCalls,
          requireAgentToolContracts: requireAgentToolContracts,
          requireToolInputSchemas: requireToolInputSchemas,
          requireToolCoverage: requireToolCoverage,
          requireToolAssertions: requireToolAssertions,
        ),
        workingDirectory: workingDirectory,
        kind: ManagedProcessKind.oneShotCommand,
        shutdownMode: ManagedProcessShutdownMode.processOnly,
        timeout: liveAgents
            ? const Duration(minutes: 10)
            : const Duration(minutes: 2),
        scope: 'library-validations',
      ),
    );
    return parseLibraryValidationProcessResult(result);
  }

  /// Creates a new runtime profile file copied from the active profile.
  Future<void> createRuntimeProfileFile() async {
    final profile = _activeRuntimeProfile();
    final directory = Directory(runtimeProfilesDirectoryPath());
    await directory.create(recursive: true);
    final nextPath = await _uniqueRuntimeProfilePath(
      directory.path,
      profile.id,
    );
    final nextId = _profileIdFromPath(nextPath);
    final next = profile.copyWith(id: nextId, label: 'New Profile');
    await File(nextPath).writeAsString(encodeRuntimeProfileJson(next));
    await loadRuntimeProfileFromPath(nextPath);
  }

  /// Duplicates the active runtime profile file and loads the duplicate.
  Future<void> duplicateRuntimeProfileFile() async {
    final profile = _activeRuntimeProfile();
    final directory = Directory(runtimeProfilesDirectoryPath());
    await directory.create(recursive: true);
    final nextPath = await _uniqueRuntimeProfilePath(
      directory.path,
      profile.id,
    );
    final nextId = _profileIdFromPath(nextPath);
    final next = profile.copyWith(id: nextId, label: '${profile.label} Copy');
    await File(nextPath).writeAsString(encodeRuntimeProfileJson(next));
    await loadRuntimeProfileFromPath(nextPath);
  }

  /// Deletes the active runtime profile file and loads another available file.
  Future<void> deleteActiveRuntimeProfileFile() async {
    final paths = await listRuntimeProfilePaths();
    if (paths.length <= 1) {
      throw const FileSystemException('Cannot delete the only runtime profile');
    }
    final current = runtimeProfilePath;
    final nextPath = paths.firstWhere((path) => path != current);
    await File(current).delete();
    await loadRuntimeProfileFromPath(nextPath);
  }

  /// Creates a new model or agent config file.
  Future<String> createConfigFile(ConfigFileKind kind) async {
    final path = await configFiles.create(kind);
    await _refreshConfigCollections();
    _notifyControllerListeners();
    return path;
  }

  /// Duplicates a model or agent config file.
  Future<String> duplicateConfigFile(ConfigFileEntry entry) async {
    final path = await configFiles.duplicate(entry.path, entry.kind);
    await _refreshConfigCollections();
    _notifyControllerListeners();
    return path;
  }

  /// Deletes a model or agent config file when it is not actively assigned.
  Future<void> deleteConfigFile(ConfigFileEntry entry) async {
    final profile = _activeRuntimeProfile();
    if (entry.path == profile.harness.modelConfigPath ||
        entry.path == profile.harness.agentConfigPath ||
        entry.path == profile.harness.toolConfigPath) {
      throw FileSystemException(
        'Cannot delete an assigned config file',
        entry.path,
      );
    }
    await configFiles.delete(entry.path, kind: entry.kind);
    await _refreshConfigCollections();
    _notifyControllerListeners();
  }

  /// Assigns a model or agent config file to the active profile.
  Future<void> assignConfigFile(ConfigFileEntry entry) async {
    await _assignConfigFile(entry.kind, entry.path);
  }

  /// Saves one configured memory domain and regenerates harness memory grants.
  Future<void> saveMemoryDomainRuntime({
    required String originalId,
    required McpServerRuntime server,
  }) async {
    final profile = _activeRuntimeProfile();
    final index = profile.memoryDomains.indexWhere(
      (candidate) => candidate.id == originalId,
    );
    if (index < 0) {
      throw FileSystemException('Memory domain is not referenced', originalId);
    }
    final servers = <McpServerRuntime>[
      for (var i = 0; i < profile.memoryDomains.length; i++)
        i == index ? server : profile.memoryDomains[i],
    ];
    final next = _withMemoryDomainGrantRewrite(
      profile.copyWith(memoryDomains: servers),
      originalId: originalId,
      nextId: server.id,
      enabled: server.enabled,
    );
    await _saveRuntimeProfileAndGeneratedToolConfig(_validatedProfile(next));
    statusMessage = '${server.label} domain saved';
    _notifyControllerListeners();
  }

  /// Creates a new configurable memory domain in the active runtime profile.
  Future<McpServerRuntime> createMemoryDomainRuntime() async {
    final profile = _activeRuntimeProfile();
    final id = _uniqueMemoryDomainId(profile, 'memory');
    final port = _nextMemoryDomainPort(profile);
    final domain = McpServerRuntime(
      id: id,
      label: _memoryDomainLabel(id),
      kind: 'memory',
      endpoint: 'http://127.0.0.1:$port/mcp',
      healthUrl: 'http://127.0.0.1:$port/healthz',
      workingDirectory: '${config.workspaceRoot}/memory',
      packagePath: './cmd/memoryd',
      dbPath: memoryDomainDatabasePath(id),
      dataDir: memoryDomainDataDirectoryPath(id),
      arguments: _memoryStorageArguments(
        <String>[
          '--addr',
          '127.0.0.1:$port',
          '--firewall-policy',
          memoryFirewallPolicyPath(),
        ],
        dbPath: memoryDomainDatabasePath(id),
        dataDir: memoryDomainDataDirectoryPath(id),
      ),
      autoStart: true,
      enabled: true,
    );
    final next = profile.copyWith(
      memoryDomains: <McpServerRuntime>[...profile.memoryDomains, domain],
    );
    await _saveRuntimeProfileAndGeneratedToolConfig(_validatedProfile(next));
    statusMessage = '${domain.label} domain created';
    _notifyControllerListeners();
    return domain;
  }

  /// Deletes a memory domain and removes its access grants.
  Future<void> deleteMemoryDomainRuntime(String domainId) async {
    final profile = _activeRuntimeProfile();
    if (profile.memoryDomains.length <= 1) {
      throw FileSystemException(
        'Cannot delete the only memory domain',
        domainId,
      );
    }
    final remaining = profile.memoryDomains
        .where((domain) => domain.id != domainId)
        .toList();
    if (remaining.length == profile.memoryDomains.length) {
      throw FileSystemException('Memory domain is not referenced', domainId);
    }
    final next = _withMemoryDomainGrantRemoval(
      profile.copyWith(memoryDomains: remaining),
      removedId: domainId,
    );
    await _saveRuntimeProfileAndGeneratedToolConfig(_validatedProfile(next));
    statusMessage = 'Memory domain deleted';
    _notifyControllerListeners();
  }

  /// Refreshes local service health for the active runtime profile.
  Future<void> refreshRuntimeServiceStatuses() async {
    final profile = _activeRuntimeProfile();
    localProcessStatuses = await localServices.startRequiredServices(profile);
    statusMessage = 'Runtime service status refreshed';
    _notifyControllerListeners();
  }

  /// Restarts managed memory services for the active runtime profile.
  Future<void> restartMemoryRuntimeServices() async {
    final profile = _activeRuntimeProfile();
    localProcessStatuses = await localServices.restartMemoryServices(profile);
    statusMessage = 'Memory services restarted';
    _notifyControllerListeners();
  }

  /// Saves agent-profile memory access grants.
  Future<void> saveAgentMemoryRuntime(AgentMemoryRuntime agentMemory) async {
    final profile = _activeRuntimeProfile().copyWith(agentMemory: agentMemory);
    await _saveRuntimeProfileAndGeneratedToolConfig(_validatedProfile(profile));
    await _restartMemoryServicesForFirewallPolicy();
    statusMessage = 'Agent memory access saved';
    _notifyControllerListeners();
  }

  /// Renames a model or agent config file and updates active assignments.
  Future<String> renameConfigFile(ConfigFileEntry entry, String name) async {
    final nextPath = await configFiles.rename(entry, name);
    final profile = _activeRuntimeProfile();
    var harness = profile.harness;
    if (profile.harness.modelConfigPath == entry.path) {
      harness = harness.copyWith(modelConfigPath: nextPath);
    }
    if (profile.harness.agentConfigPath == entry.path) {
      harness = harness.copyWith(agentConfigPath: nextPath);
    }
    if (profile.harness.toolConfigPath == entry.path) {
      harness = harness.copyWith(toolConfigPath: nextPath);
    }
    if (entry.kind == ConfigFileKind.mcp) {
      runtimeProfile = profile;
      await saveRuntimeProfile(runtimeProfile!);
      return nextPath;
    }
    runtimeProfile = profile.copyWith(harness: harness);
    await saveRuntimeProfile(runtimeProfile!);
    return nextPath;
  }

  /// Assigns a config path to the active profile for a config kind.
  Future<void> _assignConfigFile(ConfigFileKind kind, String path) async {
    final profile = _activeRuntimeProfile();
    final harness = switch (kind) {
      ConfigFileKind.model => profile.harness.copyWith(modelConfigPath: path),
      ConfigFileKind.agent => profile.harness.copyWith(agentConfigPath: path),
      ConfigFileKind.tool => profile.harness.copyWith(toolConfigPath: path),
      ConfigFileKind.mcp => profile.harness,
    };
    await saveRuntimeProfile(profile.copyWith(harness: harness));
  }

  /// Migrates default profile config files into app-owned editable locations.
  Future<RuntimeProfile> _migrateDefaultProfileConfigs(
    RuntimeProfile profile,
  ) async {
    if (config.runtimeProfilePath.trim().isNotEmpty) {
      return profile;
    }
    final topologyProfile = await _withCurrentDefaultServiceTopology(profile);
    final storageProfile = _withDefaultMemoryStorage(topologyProfile);
    final harness = storageProfile.harness;
    final modelPath = await _ensureSharedModelConfig(
      sourcePath: harness.modelConfigPath,
    );
    final agentPath = await _copyConfigIntoAppDirectory(
      sourcePath: harness.agentConfigPath,
      targetDirectory: agentConfigsDirectoryPath(),
      targetName: '${profile.id}-agent.yaml',
    );
    final toolPath = await _copyConfigIntoAppDirectory(
      sourcePath: harness.toolConfigPath,
      targetDirectory: '${toolConfigsDirectoryPath()}/${profile.id}',
      targetName: aaToolPackageConfigFilename,
    );
    final graphToolPath = await _writeDefaultGraphToolConfig(
      profile: storageProfile,
      requestedPath: toolPath ?? harness.toolConfigPath,
      targetName: aaToolPackageConfigFilename,
    );
    final next = storageProfile.copyWith(
      harness: harness.copyWith(
        modelConfigPath: modelPath,
        agentConfigPath: agentPath ?? harness.agentConfigPath,
        toolConfigPath: graphToolPath,
      ),
    );
    if (encodeRuntimeProfileJson(next) != encodeRuntimeProfileJson(profile)) {
      final file = File(runtimeProfilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(encodeRuntimeProfileJson(next));
    }
    return next;
  }

  /// Rebases the shipped default service topology onto the current bundle.
  Future<RuntimeProfile> _withCurrentDefaultServiceTopology(
    RuntimeProfile profile,
  ) async {
    final loader = RuntimeProfileLoader(config);
    final shippedFile = File(loader.shippedRuntimeProfilePath());
    if (!await shippedFile.exists()) {
      return profile;
    }
    final shipped = await loader.loadFile(shippedFile);
    return shipped.copyWith(
      harness: shipped.harness.copyWith(
        modelConfigPath: profile.harness.modelConfigPath,
        agentConfigPath: profile.harness.agentConfigPath,
        toolConfigPath: profile.harness.toolConfigPath,
      ),
    );
  }

  /// Places default managed memory files in the OS app data directory.
  RuntimeProfile _withDefaultMemoryStorage(RuntimeProfile profile) {
    return profile.copyWith(
      memoryDomains: profile.memoryDomains.map((server) {
        if (server.kind != 'memory' || !server.autoStart) {
          return server;
        }
        final dbPath = server.dbPath.trim().isEmpty
            ? memoryDomainDatabasePath(server.id)
            : server.dbPath;
        final dataDir = server.dataDir.trim().isEmpty
            ? memoryDomainDataDirectoryPath(server.id)
            : server.dataDir;
        return server.copyWith(
          dbPath: dbPath,
          dataDir: dataDir,
          arguments: _memoryStorageArguments(
            server.arguments,
            dbPath: dbPath,
            dataDir: dataDir,
          ),
        );
      }).toList(),
    );
  }

  /// Creates or migrates the shared model config referenced by all profiles.
  Future<String> _ensureSharedModelConfig({required String sourcePath}) async {
    final target = File(defaultModelConfigPath());
    await target.parent.create(recursive: true);
    if (!await target.exists()) {
      final document = await _configuredModelDocumentFromSource(sourcePath);
      await target.writeAsString(document.toYaml());
    }
    return target.path;
  }

  /// Reads configured model providers from a source config file.
  Future<ModelConfigDocument> _configuredModelDocumentFromSource(
    String sourcePath,
  ) async {
    final path = sourcePath.trim();
    if (path.isEmpty) {
      return emptyModelConfigDocument();
    }
    final source = File(path);
    if (!await source.exists()) {
      return emptyModelConfigDocument();
    }
    final document = ModelConfigDocument.parse(await source.readAsString());
    return _modelDocumentWithConfiguredProviders(
      document,
      await _configuredModelProviders(document),
    );
  }

  /// Keeps only model providers the app can prove were configured.
  Future<List<ModelProviderConfig>> _configuredModelProviders(
    ModelConfigDocument document, {
    ModelProviderConfig? replacingProvider,
  }) async {
    final providers = <ModelProviderConfig>[];
    for (final candidate in document.providers) {
      if (candidate.id == replacingProvider?.id) {
        continue;
      }
      if (replacingProvider != null &&
          _isManagedLocalModelProviderId(replacingProvider.id) &&
          _isManagedLocalModelProviderId(candidate.id)) {
        continue;
      }
      if (await _isConfiguredModelProvider(candidate)) {
        providers.add(candidate);
      }
    }
    if (replacingProvider != null) {
      providers.add(replacingProvider);
    }
    return providers;
  }

  /// Returns whether a provider has local runtime or stored credential backing.
  Future<bool> _isConfiguredModelProvider(ModelProviderConfig provider) async {
    if (_isManagedLocalModelProviderId(provider.id)) {
      return true;
    }
    if (provider.apiKey.trim().isEmpty) {
      return false;
    }
    if (_isClosing) {
      return false;
    }
    final lookup = await credentialStore.lookup(provider.apiKey);
    return lookup.found;
  }

  /// Builds a model document whose default points at an available provider.
  ModelConfigDocument _modelDocumentWithConfiguredProviders(
    ModelConfigDocument document,
    List<ModelProviderConfig> providers,
  ) {
    final refs = <String>{
      for (final provider in providers)
        for (final model in provider.models) '${provider.id}:${model.id}',
    };
    final defaultRef = refs.contains(document.defaultRef)
        ? document.defaultRef
        : providers.isEmpty
        ? ''
        : modelProviderDefaultRef(providers.first);
    return document.copyWith(defaultRef: defaultRef, providers: providers);
  }

  /// Rewrites memory daemon storage arguments while preserving other flags.
  List<String> _memoryStorageArguments(
    List<String> arguments, {
    required String dbPath,
    required String dataDir,
  }) {
    final withoutStorageFlags = <String>[];
    for (var index = 0; index < arguments.length; index++) {
      final value = arguments[index];
      if (value == '--db' || value == '--data') {
        index++;
        continue;
      }
      withoutStorageFlags.add(value);
    }
    return <String>[...withoutStorageFlags, '--db', dbPath, '--data', dataDir];
  }

  /// Writes the target graph-backed MCP tool config before harness startup.
  Future<String> _writeDefaultGraphToolConfig({
    required RuntimeProfile profile,
    required String requestedPath,
    required String targetName,
  }) async {
    final graphServers = profile.memoryServers.where((server) {
      return profile.agentMemory.readDomains.contains(server.id) ||
          profile.agentMemory.writeDomains.contains(server.id);
    }).toList();
    if (graphServers.isEmpty) {
      throw FileSystemException('Memory domains are missing', profile.id);
    }
    var path = requestedPath.trim();
    if (!_isToolPackageConfigPath(path)) {
      path = toolPackageConfigPath(profile.id);
    }
    var file = File(path);
    if (path.isEmpty || !await file.exists()) {
      final directory = Directory(
        '${toolConfigsDirectoryPath()}/${profile.id}',
      );
      await directory.create(recursive: true);
      path = '${directory.path}/$targetName';
      file = File(path);
    }

    final document = await file.exists()
        ? ToolConfigDocument.parse(await file.readAsString())
        : emptyToolConfigDocument();
    final target = graphBackedMemoryToolConfigForDomains(
      memoryDomains: graphServers,
      agentMemory: profile.agentMemory,
      workflow: profile.workflow,
      mcpServers: profile.serviceMcpServers,
      localExec: document.localExec,
      extra: document.extra,
    );
    final validationError = toolConfigValidationError(target);
    if (validationError.isNotEmpty) {
      throw FileSystemException(validationError, path);
    }
    final toolDocument = target.copyWith(mcp: emptyToolConfigDocument().mcp);
    final mcpDocument = emptyToolConfigDocument().copyWith(mcp: target.mcp);
    final mcpFile = File(mcpPackageConfigPath(profile.id));
    await file.parent.create(recursive: true);
    await mcpFile.parent.create(recursive: true);
    await file.writeAsString(toolDocument.toYaml());
    await mcpFile.writeAsString(mcpDocument.toYaml());
    await _log('wrote graph-backed tool package $path');
    await _log('wrote graph-backed MCP package ${mcpFile.path}');
    return path;
  }

  /// Saves profile JSON after regenerating the domain-aware tool config.
  Future<void> _saveRuntimeProfileAndGeneratedToolConfig(
    RuntimeProfile profile,
  ) async {
    final toolPath = await _writeDefaultGraphToolConfig(
      profile: profile,
      requestedPath: profile.harness.toolConfigPath,
      targetName: aaToolPackageConfigFilename,
    );
    await saveRuntimeProfile(
      profile.copyWith(
        harness: profile.harness.copyWith(toolConfigPath: toolPath),
      ),
    );
  }

  /// Reports whether a path points at one package-scoped tool.yaml file.
  bool _isToolPackageConfigPath(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    if (!normalized.endsWith('/$aaToolPackageConfigFilename')) {
      return false;
    }
    return normalized.startsWith('${toolConfigsDirectoryPath()}/');
  }

  /// Validates a profile by round-tripping through the target schema parser.
  RuntimeProfile _validatedProfile(RuntimeProfile profile) {
    return RuntimeProfile.fromJson(profile.toJson());
  }

  /// Rewrites agent grants when a memory domain id changes or is disabled.
  RuntimeProfile _withMemoryDomainGrantRewrite(
    RuntimeProfile profile, {
    required String originalId,
    required String nextId,
    required bool enabled,
  }) {
    if (originalId == nextId && enabled) {
      return profile;
    }
    final memory = profile.agentMemory;
    final readDomains = _rewrittenDomainGrantList(
      memory.readDomains,
      originalId: originalId,
      nextId: nextId,
      keep: enabled,
    );
    final writeDomains = _rewrittenDomainGrantList(
      memory.writeDomains,
      originalId: originalId,
      nextId: nextId,
      keep: enabled,
    );
    var defaultWriteDomain = memory.defaultWriteDomain == originalId
        ? nextId
        : memory.defaultWriteDomain;
    if (!enabled && defaultWriteDomain == nextId) {
      defaultWriteDomain = _firstDomainId(writeDomains, profile.memoryDomains);
    }
    final effectiveWriteDomains = writeDomains.isEmpty
        ? <String>[defaultWriteDomain]
        : writeDomains;
    final effectiveReadDomains = readDomains.isEmpty
        ? <String>[defaultWriteDomain]
        : readDomains;
    final flows = <MemoryDomainFlow>[
      for (final flow in memory.allowedFlows)
        if (enabled ||
            (flow.fromDomain != originalId && flow.toDomain != originalId))
          MemoryDomainFlow(
            fromDomain: flow.fromDomain == originalId
                ? nextId
                : flow.fromDomain,
            toDomain: flow.toDomain == originalId ? nextId : flow.toDomain,
          ),
    ];
    return profile.copyWith(
      agentMemory: AgentMemoryRuntime(
        actor: memory.actor,
        readDomains: effectiveReadDomains,
        writeDomains: effectiveWriteDomains,
        defaultWriteDomain: defaultWriteDomain,
        allowedSensitivities: memory.allowedSensitivities,
        allowedFlows: flows,
      ),
    );
  }

  /// Removes all agent grants for a deleted domain.
  RuntimeProfile _withMemoryDomainGrantRemoval(
    RuntimeProfile profile, {
    required String removedId,
  }) {
    final memory = profile.agentMemory;
    final readDomains = memory.readDomains
        .where((domain) => domain != removedId)
        .toList();
    final writeDomains = memory.writeDomains
        .where((domain) => domain != removedId)
        .toList();
    final fallback = _firstDomainId(writeDomains, profile.memoryDomains);
    return profile.copyWith(
      agentMemory: AgentMemoryRuntime(
        actor: memory.actor,
        readDomains: readDomains.isEmpty
            ? <String>[profile.memoryDomains.first.id]
            : readDomains,
        writeDomains: writeDomains.isEmpty ? <String>[fallback] : writeDomains,
        defaultWriteDomain: memory.defaultWriteDomain == removedId
            ? fallback
            : memory.defaultWriteDomain,
        allowedSensitivities: memory.allowedSensitivities,
        allowedFlows: <MemoryDomainFlow>[
          for (final flow in memory.allowedFlows)
            if (flow.fromDomain != removedId && flow.toDomain != removedId)
              flow,
        ],
      ),
    );
  }

  /// Rewrites one read/write domain grant list.
  List<String> _rewrittenDomainGrantList(
    List<String> domains, {
    required String originalId,
    required String nextId,
    required bool keep,
  }) {
    final rewritten = <String>[];
    for (final domain in domains) {
      if (domain == originalId) {
        if (keep && !rewritten.contains(nextId)) {
          rewritten.add(nextId);
        }
      } else if (!rewritten.contains(domain)) {
        rewritten.add(domain);
      }
    }
    return rewritten;
  }

  /// Returns a valid writable fallback domain id.
  String _firstDomainId(
    List<String> preferred,
    List<McpServerRuntime> domains,
  ) {
    for (final id in preferred) {
      if (domains.any((domain) => domain.id == id && domain.enabled)) {
        return id;
      }
    }
    for (final domain in domains) {
      if (domain.enabled) {
        return domain.id;
      }
    }
    return domains.first.id;
  }

  /// Returns a collision-free memory domain id.
  String _uniqueMemoryDomainId(RuntimeProfile profile, String prefix) {
    final existing = profile.memoryDomains.map((domain) => domain.id).toSet();
    var index = 2;
    var candidate = '$prefix-$index';
    while (existing.contains(candidate)) {
      index++;
      candidate = '$prefix-$index';
    }
    return candidate;
  }

  /// Returns the next conventional loopback memory port.
  int _nextMemoryDomainPort(RuntimeProfile profile) {
    final used = <int>{};
    for (final domain in profile.memoryDomains) {
      final uri = Uri.tryParse(domain.endpoint);
      if (uri != null && uri.hasPort) {
        used.add(uri.port);
      }
    }
    var port = 8090;
    while (used.contains(port)) {
      port++;
    }
    return port;
  }

  /// Formats a generated label for a domain id.
  String _memoryDomainLabel(String id) {
    return id
        .split(RegExp(r'[-_]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  /// Rebuilds owned service clients from the active runtime profile.
  Future<void> _configureClientsForRuntimeProfile(
    RuntimeProfile profile,
  ) async {
    final headers = await _gatewayHeadersForProfile(profile);
    _runtimeGatewayHeaders = headers;
    if (!_assistantClientInjected) {
      assistantClient.close();
      assistantClient = AssistantClient(
        baseUrl: profile.gateway.apiBaseUrl,
        appName: profile.harness.appName,
        userId: profile.harness.userId,
        headers: headers,
        logger: logger,
      );
    }
    if (!_memoryClientInjected) {
      memoryClient.close();
      memoryClient = MemoryClient(
        rpc: GatewayContextClient(
          baseUrl: _contextBaseUrl(profile),
          headers: headers,
          logger: logger,
        ),
      );
    }
    if (!_tasksClientInjected) {
      tasksClient.close();
      tasksClient = TasksClient(
        rpc: GatewayContextClient(
          baseUrl: _contextBaseUrl(profile),
          headers: headers,
          logger: logger,
        ),
      );
    }
    if (!_executiveSummaryClientInjected) {
      executiveSummaryClient.close();
      executiveSummaryClient = ExecutiveSummaryClient(
        rpc: GatewayContextClient(
          baseUrl: _contextBaseUrl(profile),
          headers: headers,
          logger: logger,
        ),
      );
    }
    if (!_automationsClientInjected) {
      automationsClient.close();
      automationsClient = AutomationsClient(
        baseUrl: _workflowBaseUrl(profile.gateway.apiBaseUrl),
        headers: headers,
        logger: logger,
      );
    }
  }

  /// Returns the gateway context route used by all UI context clients.
  String _contextBaseUrl(RuntimeProfile profile) {
    final uri = Uri.parse(profile.gateway.apiBaseUrl);
    return uri.replace(path: '/api/context', query: null).toString();
  }

  /// Returns headers needed to call protected gateway routes.
  Future<Map<String, String>> _gatewayHeadersForProfile(
    RuntimeProfile profile,
  ) async {
    final headers = <String, String>{...config.gatewayAuthHeaders};
    final credential = profile.gateway.authCredential.trim();
    if (!headers.containsKey('Authorization') && credential.isNotEmpty) {
      final lookup = await credentialStore.lookup(credential);
      if (lookup.found && lookup.secretValue.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${lookup.secretValue.trim()}';
      }
    }
    final profileId = profile.gateway.profileId.trim();
    if (profileId.isNotEmpty) {
      headers['X-Agent-Awesome-Profile'] = profileId;
    }
    return headers;
  }
}

/// Builds CLI arguments for one tool-package validation run.
List<String> buildToolValidationCommandArguments({
  required String packagePath,
  required String toolPath,
  String validationId = '',
  List<String> validationIds = const <String>[],
  String mode = '',
  String agentPath = '',
  String modelPath = '',
  bool requireAssertions = false,
  bool requireCoverage = false,
  bool requireInputSchemas = false,
}) {
  final selectedValidationIds = <String>{
    if (validationId.trim().isNotEmpty) validationId.trim(),
    for (final id in validationIds)
      if (id.trim().isNotEmpty) id.trim(),
  };
  return <String>[
    'run',
    packagePath,
    'tools',
    'validate',
    '--tool',
    toolPath,
    if (_validationModeArgument(mode).isNotEmpty) ...<String>[
      '--mode',
      _validationModeArgument(mode),
    ],
    if (agentPath.trim().isNotEmpty) ...<String>['--agent', agentPath.trim()],
    if (modelPath.trim().isNotEmpty) ...<String>['--model', modelPath.trim()],
    for (final id in selectedValidationIds) ...<String>['--validation', id],
    if (requireAssertions) '--require-assertions',
    if (requireCoverage) '--require-coverage',
    if (requireInputSchemas) '--require-input-schemas',
    '--json',
  ];
}

/// Builds CLI arguments for one agent-package validation run.
List<String> buildAgentValidationCommandArguments({
  required String packagePath,
  required String agentPath,
  String validationId = '',
  String mode = '',
  bool live = false,
  String modelPath = '',
  String toolPath = '',
  bool requireValidations = false,
  bool requireAssertions = false,
  bool requireToolCalls = false,
  bool requireToolContracts = false,
}) {
  return <String>[
    'run',
    packagePath,
    'agents',
    'validate',
    '--agent',
    agentPath,
    if (_validationModeArgument(mode).isNotEmpty) ...<String>[
      '--mode',
      _validationModeArgument(mode),
    ],
    if (live) '--live',
    if (live && modelPath.trim().isNotEmpty) ...<String>[
      '--model',
      modelPath.trim(),
    ],
    if ((live || requireToolContracts) &&
        toolPath.trim().isNotEmpty) ...<String>['--tool', toolPath.trim()],
    if (validationId.trim().isNotEmpty) ...<String>[
      '--validation',
      validationId.trim(),
    ],
    if (requireValidations) '--require-validations',
    if (requireAssertions) '--require-assertions',
    if (requireToolCalls) '--require-tool-calls',
    if (requireToolContracts) '--require-tool-contracts',
    '--json',
  ];
}

/// Builds CLI arguments for one shared package-library validation run.
List<String> buildLibraryValidationCommandArguments({
  required String packagePath,
  required String rootPath,
  String agentPath = '',
  required String agentDirectory,
  String toolPath = '',
  required String toolDirectory,
  String mcpDirectory = 'mcp',
  bool requireAgentValidations = false,
  bool requireAgentAssertions = false,
  bool requireAgentToolCalls = false,
  bool requireAgentToolContracts = false,
  bool requireToolInputSchemas = false,
  bool requireToolCoverage = false,
  bool requireToolAssertions = false,
  bool liveAgents = false,
  String agentMode = '',
  String toolMode = '',
  String runtimeAgentPath = '',
  String modelPath = '',
  String runtimeToolPath = '',
}) {
  return <String>[
    'run',
    packagePath,
    'library',
    'validate',
    '--root',
    rootPath,
    if (agentPath.trim().isNotEmpty) ...<String>[
      '--agent',
      agentPath.trim(),
    ] else if (agentDirectory.isNotEmpty) ...<String>[
      '--agent-dir',
      agentDirectory,
    ] else ...<String>['--agent-dir', ''],
    if (toolPath.trim().isNotEmpty) ...<String>[
      '--tool',
      toolPath.trim(),
    ] else if (toolDirectory.isNotEmpty) ...<String>[
      '--tool-dir',
      toolDirectory,
    ] else ...<String>['--tool-dir', ''],
    if (toolPath.trim().isEmpty)
      if (mcpDirectory.isNotEmpty) ...<String>[
        '--mcp-dir',
        mcpDirectory,
      ] else ...<String>['--mcp-dir', ''],
    if (_validationModeArgument(agentMode).isNotEmpty) ...<String>[
      '--agent-mode',
      _validationModeArgument(agentMode),
    ],
    if (_validationModeArgument(toolMode).isNotEmpty) ...<String>[
      '--tool-mode',
      _validationModeArgument(toolMode),
    ],
    if (liveAgents) '--live-agents',
    if (_validationModeArgument(toolMode) == 'live' &&
        runtimeAgentPath.trim().isNotEmpty) ...<String>[
      '--runtime-agent',
      runtimeAgentPath.trim(),
    ],
    if (liveAgents && modelPath.trim().isNotEmpty) ...<String>[
      '--model',
      modelPath.trim(),
    ],
    if (liveAgents && runtimeToolPath.trim().isNotEmpty) ...<String>[
      '--runtime-tool',
      runtimeToolPath.trim(),
    ],
    if (requireAgentValidations) '--require-agent-validations',
    if (requireAgentAssertions) '--require-agent-assertions',
    if (requireAgentToolCalls) '--require-agent-tool-calls',
    if (requireAgentToolContracts) '--require-agent-tool-contracts',
    if (requireToolInputSchemas) '--require-tool-input-schemas',
    if (requireToolCoverage) '--require-tool-coverage',
    if (requireToolAssertions) '--require-tool-assertions',
    '--json',
  ];
}

/// Normalizes optional validation mode filters for CLI command builders.
String _validationModeArgument(String mode) {
  final value = mode.trim().toLowerCase();
  if (value == 'mocked' || value == 'live') {
    return value;
  }
  return '';
}

/// Parses one agent validation process result from harness CLI JSON.
AgentValidationResult parseAgentValidationProcessResult(
  ManagedProcessResult result,
) {
  return _parseValidationProcessResult(
    result,
    failureLabel: 'Agent validation failed',
    invalidJsonLabel: 'Agent validation returned invalid JSON',
    parser: AgentValidationResult.fromJson,
  );
}

/// Parses one tool validation process result from harness CLI JSON.
ToolValidationSuiteResult parseToolValidationProcessResult(
  ManagedProcessResult result,
) {
  return _parseValidationProcessResult(
    result,
    failureLabel: 'Tool validation failed',
    invalidJsonLabel: 'Tool validation returned invalid JSON',
    parser: ToolValidationSuiteResult.fromJson,
  );
}

/// Parses one library validation process result from harness CLI JSON.
LibraryValidationResult parseLibraryValidationProcessResult(
  ManagedProcessResult result,
) {
  return _parseValidationProcessResult(
    result,
    failureLabel: 'Library validation failed',
    invalidJsonLabel: 'Library validation returned invalid JSON',
    parser: LibraryValidationResult.fromJson,
  );
}

/// Parses validation JSON before interpreting nonzero process exits.
T _parseValidationProcessResult<T>(
  ManagedProcessResult result, {
  required String failureLabel,
  required String invalidJsonLabel,
  required T Function(Map<String, dynamic> json) parser,
}) {
  if (result.timedOut) {
    final detail = _validationProcessFailureDetail(result);
    throw StateError(detail.isEmpty ? failureLabel : detail);
  }
  try {
    final decoded = jsonDecode(result.stdout);
    if (decoded is Map<String, dynamic>) {
      return parser(decoded);
    }
  } catch (_) {
    // Fall through to process-error reporting below.
  }
  if (result.exitCode != 0) {
    final detail = _validationProcessFailureDetail(result);
    throw StateError(detail.isEmpty ? failureLabel : detail);
  }
  throw StateError(invalidJsonLabel);
}

/// Returns stderr when available, otherwise stdout, for process errors.
String _validationProcessFailureDetail(ManagedProcessResult result) {
  return result.stderr.trim().isEmpty
      ? result.stdout.trim()
      : result.stderr.trim();
}

/// Returns a non-conflicting profile copy path in the profile directory.
Future<String> _uniqueRuntimeProfilePath(
  String directory,
  String profileId,
) async {
  final base = profileId.trim().isEmpty ? 'profile' : profileId;
  var candidate = '$directory/$base-copy.json';
  var index = 2;
  while (await File(candidate).exists()) {
    candidate = '$directory/$base-copy-$index.json';
    index++;
  }
  return candidate;
}

Future<RuntimeProfileFileEntry> _profileEntryForPath(
  String path, {
  String activePath = '',
}) async {
  try {
    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is Map<String, dynamic>) {
      return RuntimeProfileFileEntry(
        path: path,
        id: _optionalString(decoded['id'], fallback: _profileIdFromPath(path)),
        label: _optionalString(
          decoded['label'],
          fallback: _profileIdFromPath(path),
        ),
        active: _sameProfilePath(path, activePath),
        runtimeKind: _profileRuntimeKind(decoded),
        memoryDomainLabels: _profileMemoryDomainLabels(decoded),
      );
    }
  } catch (_) {
    // Invalid profile files remain visible by filename so they can be repaired.
  }
  return RuntimeProfileFileEntry(
    path: path,
    id: _profileIdFromPath(path),
    label: _profileIdFromPath(path),
    active: _sameProfilePath(path, activePath),
  );
}

/// _sameProfilePath compares runtime profile paths after filesystem cleanup.
bool _sameProfilePath(String left, String right) {
  if (left.trim().isEmpty || right.trim().isEmpty) {
    return false;
  }
  return File(left).absolute.path == File(right).absolute.path;
}

/// _profileRuntimeKind summarizes whether a profile points to local or cloud APIs.
String _profileRuntimeKind(Map<String, dynamic> profile) {
  final gateway = profile['gateway'];
  if (gateway is! Map<String, dynamic>) {
    return '';
  }
  final url = _optionalString(gateway['api_base_url'], fallback: '');
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return '';
  }
  final host = uri.host.toLowerCase();
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
    return 'Local';
  }
  return 'Cloud';
}

/// _profileMemoryDomainLabels returns readable memory domain names.
List<String> _profileMemoryDomainLabels(Map<String, dynamic> profile) {
  final domains = profile['memory_domains'];
  if (domains is! List) {
    return const <String>[];
  }
  return domains
      .whereType<Map<String, dynamic>>()
      .map((domain) {
        return _optionalString(
          domain['label'],
          fallback: _optionalString(domain['id'], fallback: 'memory'),
        );
      })
      .where((label) => label.trim().isNotEmpty)
      .toList();
}

Future<String?> _copyConfigIntoAppDirectory({
  required String sourcePath,
  required String targetDirectory,
  required String targetName,
}) async {
  if (sourcePath.trim().isEmpty || sourcePath.startsWith(targetDirectory)) {
    return sourcePath;
  }
  final source = File(sourcePath);
  if (!await source.exists()) {
    return null;
  }
  final directory = Directory(targetDirectory);
  await directory.create(recursive: true);
  final target = File('${directory.path}/$targetName');
  if (!await target.exists()) {
    await target.writeAsString(await source.readAsString());
  }
  return target.path;
}

/// Derives a stable profile id from a profile file path.
String _profileIdFromPath(String path) {
  final filename = path.replaceAll('\\', '/').split('/').last;
  final dot = filename.lastIndexOf('.');
  if (dot <= 0) {
    return filename;
  }
  return filename.substring(0, dot);
}

String _optionalString(dynamic value, {required String fallback}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}
