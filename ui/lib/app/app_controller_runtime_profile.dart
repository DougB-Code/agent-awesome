/// Agent runtime and config-file workflows for AgentAwesomeAppController.
part of 'app_controller.dart';

extension AgentAwesomeAppControllerRuntimeProfiles
    on AgentAwesomeAppController {
  /// Saves the active agent runtime topology JSON and reconnects owned clients.
  Future<void> saveRuntimeProfile(RuntimeProfile profile) async {
    final previousProfile = runtimeProfile;
    final launchChanged =
        previousProfile != null &&
        !_sameRuntimeLaunchSignature(previousProfile, profile);
    final path = runtimeProfilePath.trim().isEmpty
        ? RuntimeProfileLoader(config).defaultRuntimeProfilePath()
        : runtimeProfilePath;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(encodeRuntimeProfileJson(profile));
    runtimeProfilePath = path;
    runtimeProfile = profile;
    if (launchChanged) {
      _runtimeServicesNeedRestart = true;
    }
    if (config.autoStartLocalServices) {
      await _saveMemoryFirewallPolicyForActiveProfile();
    }
    await _refreshConfigCollections();
    await _configureClientsForRuntimeProfile(profile);
    _refreshEndpointSkeleton(profile);
    statusMessage = 'Agent runtime saved';
    _notifyControllerListeners();
  }

  /// Starts required services and consumes pending runtime restart requests.
  Future<List<ServiceProcessStatus>> _startRequiredRuntimeServices(
    RuntimeProfile profile, {
    bool restartAutoStarted = false,
    bool includeHarness = true,
    bool includeMcpServers = true,
  }) async {
    final restart = restartAutoStarted || _runtimeServicesNeedRestart;
    final statuses = await localServices.startRequiredServices(
      profile,
      restartAutoStarted: restart,
      includeHarness: includeHarness,
      includeMcpServers: includeMcpServers,
    );
    if (restart && !_hasRequiredRuntimeServiceFailure(statuses)) {
      _runtimeServicesNeedRestart = false;
    }
    return statuses;
  }

  /// Reports whether any required non-model service failed to start.
  bool _hasRequiredRuntimeServiceFailure(List<ServiceProcessStatus> statuses) {
    return statuses.any((status) {
      return !_isLocalModelProcessStatus(status) &&
          status.state == ConnectionStateKind.disconnected;
    });
  }

  /// Reads a text configuration file referenced by the active runtime.
  Future<String> readConfigurationFile(String path) async {
    return configFiles.read(path);
  }

  /// Saves a text configuration file referenced by the active runtime.
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
    String modelPath = '',
    bool requireValidations = false,
    bool requireAssertions = false,
    bool requireToolCalls = false,
    bool requireToolContracts = false,
  }) async {
    final harness = runtimeProfile?.harness;
    final workingDirectory = harness?.workingDirectory.trim().isNotEmpty == true
        ? harness!.workingDirectory
        : '${config.workspaceRoot}/harness';
    final executablePath = harness?.executablePath.trim().isNotEmpty == true
        ? harness!.executablePath
        : 'agent-awesome';
    final result = await processSupervisor.run(
      ManagedProcessSpec(
        id: 'agent-validations-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Agent validations',
        executable: executablePath,
        arguments: buildAgentValidationCommandArguments(
          agentPath: agentPath,
          validationId: validationId,
          mode: mode,
          live: live,
          modelPath: modelPath.trim().isNotEmpty
              ? modelPath.trim()
              : harness?.modelConfigPath ?? '',
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

  /// Runs model-owned validations through the active agent prompt.
  Future<AgentValidationResult> runModelPackageValidations(
    String modelPath, {
    String validationId = '',
    String mode = '',
    bool live = false,
    bool requireValidations = false,
    bool requireAssertions = false,
    bool requireToolCalls = false,
    bool requireToolContracts = false,
  }) async {
    final harness = runtimeProfile?.harness;
    final agentPath = harness?.agentConfigPath.trim() ?? '';
    if (agentPath.isEmpty) {
      throw StateError('Active agent config is not selected');
    }
    final modelContent = await configFiles.read(modelPath);
    final modelDocument = ModelConfigDocument.parse(modelContent);
    final agentContent = await configFiles.read(agentPath);
    final agentDocument = AgentConfigDocument.parse(agentContent);
    final validationAgent = agentDocument.copyWith(
      validations: modelDocument.validations,
    );
    final tempAgentPath = await _writeModelValidationAgentConfig(
      modelPath,
      validationAgent,
    );
    return runAgentPackageValidations(
      tempAgentPath,
      validationId: validationId,
      mode: mode,
      live: live,
      modelPath: modelPath,
      requireValidations: requireValidations,
      requireAssertions: requireAssertions,
      requireToolCalls: requireToolCalls,
      requireToolContracts: requireToolContracts,
    );
  }

  /// Writes a temporary agent config that carries model-owned validations.
  Future<String> _writeModelValidationAgentConfig(
    String modelPath,
    AgentConfigDocument document,
  ) async {
    final encoded = base64Url
        .encode(utf8.encode(modelPath))
        .replaceAll('=', '');
    final file = File(
      '${config.workspaceRoot}/build/model-validations/$encoded.agent.yaml',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(document.toYaml());
    return file.path;
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
    final executablePath = harness?.executablePath.trim().isNotEmpty == true
        ? harness!.executablePath
        : 'agent-awesome';
    final result = await processSupervisor.run(
      ManagedProcessSpec(
        id: 'tool-validations-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Tool validations',
        executable: executablePath,
        arguments: buildToolValidationCommandArguments(
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

  /// Starts or checks one server declared in an MCP package config file.
  Future<ServiceProcessStatus> startMcpServerFromConfig(
    String configPath, {
    String serverName = '',
  }) async {
    final content = await readConfigurationFile(configPath);
    final document = ToolConfigDocument.parse(content);
    final server = _mcpServerFromDocument(document, serverName);
    if (server == null) {
      return const ServiceProcessStatus(
        name: 'MCP server',
        url: '',
        state: ConnectionStateKind.disconnected,
        message: 'No MCP server is declared in this file',
      );
    }
    final transport = normalizedMcpTransport(server.transport);
    if (transport == 'streamable-http') {
      return _checkHttpMcpServer(server);
    }
    if (transport == 'stdio') {
      return _startStdioMcpServer(server);
    }
    return ServiceProcessStatus(
      name: _mcpServerDisplayName(server),
      url: '',
      state: ConnectionStateKind.disconnected,
      message: 'Unsupported MCP transport "$transport"',
    );
  }

  /// Returns one configured MCP server from a loaded package document.
  McpServerToolConfig? _mcpServerFromDocument(
    ToolConfigDocument document,
    String serverName,
  ) {
    final requested = serverName.trim();
    if (requested.isNotEmpty) {
      for (final server in document.mcp.servers) {
        if (server.name.trim() == requested) {
          return server;
        }
      }
    }
    if (document.mcp.servers.isEmpty) {
      return null;
    }
    return document.mcp.servers.first;
  }

  /// Lists tools on an HTTP MCP server to verify it can be invoked.
  Future<ServiceProcessStatus> _checkHttpMcpServer(
    McpServerToolConfig server,
  ) async {
    final endpoint = mcpServerEndpoint(server);
    if (endpoint.isEmpty) {
      return ServiceProcessStatus(
        name: _mcpServerDisplayName(server),
        url: '',
        state: ConnectionStateKind.disconnected,
        message: 'HTTP endpoint is missing',
      );
    }
    final client = McpJsonRpcClient(
      endpoint: endpoint,
      headers: _resolvedMcpHeaders(server),
      logger: logger,
    );
    try {
      final tools = await client.listToolNames();
      final count = tools.length;
      statusMessage = 'MCP server ${_mcpServerDisplayName(server)} responded';
      _notifyControllerListeners();
      return ServiceProcessStatus(
        name: _mcpServerDisplayName(server),
        url: endpoint,
        state: ConnectionStateKind.connected,
        message: '$count ${count == 1 ? 'tool' : 'tools'} available',
      );
    } finally {
      client.close();
    }
  }

  /// Starts a stdio MCP server as an app-supervised process.
  Future<ServiceProcessStatus> _startStdioMcpServer(
    McpServerToolConfig server,
  ) async {
    final command = server.command.trim();
    if (command.isEmpty) {
      return ServiceProcessStatus(
        name: _mcpServerDisplayName(server),
        url: '',
        state: ConnectionStateKind.disconnected,
        message: 'Stdio command is missing',
      );
    }
    final id = _mcpProcessId(server.name);
    final logPath =
        '${config.workspaceRoot}/build/ui-mcp/${_mcpSafeId(server.name)}.log';
    final handle = await processSupervisor.start(
      ManagedProcessSpec(
        id: id,
        name: 'MCP ${_mcpServerDisplayName(server)}',
        executable: command,
        arguments: server.args,
        environment: server.env,
        kind: ManagedProcessKind.longRunningService,
        shutdownMode: ManagedProcessShutdownMode.processGroup,
        outputLogPath: logPath,
        scope: 'mcp-packages',
      ),
    );
    statusMessage =
        'Started MCP server ${_mcpServerDisplayName(server)} (pid ${handle.pid})';
    _notifyControllerListeners();
    return ServiceProcessStatus(
      name: _mcpServerDisplayName(server),
      url: logPath,
      state: ConnectionStateKind.connected,
      message: 'Started pid ${handle.pid}',
    );
  }

  /// Resolves HTTP headers that an MCP package references by environment name.
  Map<String, String> _resolvedMcpHeaders(McpServerToolConfig server) {
    final headers = <String, String>{};
    for (final entry in server.headersFromEnv.entries) {
      final header = entry.key.trim();
      final envName = entry.value.trim();
      if (header.isEmpty || envName.isEmpty) {
        continue;
      }
      final value = Platform.environment[envName]?.trim() ?? '';
      if (value.isEmpty) {
        throw StateError(
          'MCP header "$header" requires non-empty environment variable $envName',
        );
      }
      headers[header] = value;
    }
    return headers;
  }

  /// Returns a compact display name for one MCP server config.
  String _mcpServerDisplayName(McpServerToolConfig server) {
    final name = server.name.trim();
    return name.isEmpty ? 'MCP server' : name;
  }

  /// Returns a stable supervised process id for a package-scoped MCP server.
  String _mcpProcessId(String value) {
    return 'mcp-${_mcpSafeId(value)}-${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Converts arbitrary MCP names into filesystem and process-id safe text.
  String _mcpSafeId(String value) {
    final id = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return id.isEmpty ? 'server' : id;
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
    final executablePath = harness?.executablePath.trim().isNotEmpty == true
        ? harness!.executablePath
        : 'agent-awesome';
    final result = await processSupervisor.run(
      ManagedProcessSpec(
        id: 'library-validations-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Library validations',
        executable: executablePath,
        arguments: buildLibraryValidationCommandArguments(
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

  /// Assigns a model or agent config file to the active runtime.
  Future<void> assignConfigFile(ConfigFileEntry entry) async {
    await _assignConfigFile(entry.kind, entry.path);
  }

  /// Selects the active agent config while keeping topology plumbing hidden.
  Future<void> selectActiveAgentConfig(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await saveAppSettings(
      appSettings.copyWith(defaultAgentConfigPath: trimmed),
    );
    await _assignConfigFile(ConfigFileKind.agent, trimmed);
    statusMessage = 'Agent selected';
    _notifyControllerListeners();
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

  /// Creates a new configurable memory domain in the active agent runtime topology.
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
      executablePath: '${config.workspaceRoot}/memory/build/bin/memoryd',
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

  /// Duplicates a memory domain with isolated local storage paths and port.
  Future<McpServerRuntime> duplicateMemoryDomainRuntime(String domainId) async {
    final profile = _activeRuntimeProfile();
    final source = profile.memoryDomains.firstWhere(
      (domain) => domain.id == domainId,
      orElse: () => throw FileSystemException(
        'Memory domain is not referenced',
        domainId,
      ),
    );
    final id = _uniqueMemoryDomainId(profile, source.id);
    final port = _nextMemoryDomainPort(profile);
    final dbPath = memoryDomainDatabasePath(id);
    final dataDir = memoryDomainDataDirectoryPath(id);
    final domain = source.copyWith(
      id: id,
      label: '${source.label.trim().isEmpty ? source.id : source.label} Copy',
      endpoint: 'http://127.0.0.1:$port/mcp',
      healthUrl: 'http://127.0.0.1:$port/healthz',
      dbPath: dbPath,
      dataDir: dataDir,
      arguments: _memoryStorageArguments(
        <String>[
          '--addr',
          '127.0.0.1:$port',
          '--firewall-policy',
          memoryFirewallPolicyPath(),
        ],
        dbPath: dbPath,
        dataDir: dataDir,
      ),
    );
    final next = profile.copyWith(
      memoryDomains: <McpServerRuntime>[...profile.memoryDomains, domain],
    );
    await _saveRuntimeProfileAndGeneratedToolConfig(_validatedProfile(next));
    statusMessage = '${domain.label} domain duplicated';
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

  /// Refreshes local service health for the active agent runtime topology.
  Future<void> refreshRuntimeServiceStatuses() async {
    final profile = _activeRuntimeProfile();
    localProcessStatuses = await _startRequiredRuntimeServices(profile);
    statusMessage = 'Runtime service status refreshed';
    _notifyControllerListeners();
  }

  /// Restarts managed memory services for the active agent runtime topology.
  Future<void> restartMemoryRuntimeServices() async {
    final profile = _activeRuntimeProfile();
    localProcessStatuses = await localServices.restartMemoryServices(profile);
    statusMessage = 'Memory services restarted';
    _notifyControllerListeners();
  }

  /// Saves active agent memory access grants.
  Future<void> saveAgentMemoryRuntime(AgentMemoryRuntime agentMemory) async {
    final profile = _activeRuntimeProfile().copyWith(agentMemory: agentMemory);
    await _saveRuntimeProfileAndGeneratedToolConfig(_validatedProfile(profile));
    await _restartMemoryServicesForFirewallPolicy();
    statusMessage = 'Agent memory access saved';
    _notifyControllerListeners();
  }

  /// Selects the default memory domain independently from the active agent.
  Future<void> selectDefaultMemoryDomain(String domainId) async {
    final trimmed = domainId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final profile = _activeRuntimeProfile();
    if (!profile.memoryDomains.any((domain) => domain.id == trimmed)) {
      throw FileSystemException('Memory domain is not configured', trimmed);
    }
    await saveAppSettings(
      appSettings.copyWith(selectedMemoryDomainId: trimmed),
    );
    await _saveRuntimeProfileAndGeneratedToolConfig(
      _validatedProfile(_withSelectedMemoryDomain(profile, trimmed)),
    );
    await _restartMemoryServicesForFirewallPolicy();
    statusMessage = 'Memory selected';
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

  /// Assigns a config path to the active runtime for a config kind.
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

  /// Applies app-owned agent and memory selections to launch topology data.
  Future<RuntimeProfile> _withAppRuntimeSelections(
    RuntimeProfile profile,
  ) async {
    var next = profile;
    final agentPath = appSettings.defaultAgentConfigPath.trim();
    if (agentPath.isNotEmpty && await File(agentPath).exists()) {
      next = next.copyWith(
        harness: next.harness.copyWith(agentConfigPath: agentPath),
      );
    }
    final memoryDomainId = appSettings.selectedMemoryDomainId.trim();
    if (memoryDomainId.isNotEmpty &&
        next.memoryDomains.any((domain) => domain.id == memoryDomainId)) {
      next = _withSelectedMemoryDomain(next, memoryDomainId);
    }
    return next;
  }

  /// Migrates default topology config files into app-owned editable locations.
  Future<RuntimeProfile> _migrateDefaultProfileConfigs(
    RuntimeProfile profile,
  ) async {
    if (config.runtimeProfilePath.trim().isNotEmpty) {
      return profile;
    }
    final topologyProfile = await _withCurrentDefaultServiceTopology(profile);
    final storageProfile = _withDefaultMemoryStorage(topologyProfile);
    final workflowProfile = _withAgentOwnedWorkflowDefinitions(storageProfile);
    await _copyWorkflowDefinitionsForRuntimeAgent(profile, workflowProfile);
    final harness = workflowProfile.harness;
    final modelPath = await _ensureSharedModelConfig(
      sourcePath: harness.modelConfigPath,
    );
    final agentPath = await _copyConfigIntoAppDirectory(
      sourcePath: harness.agentConfigPath,
      targetDirectory: agentRuntimeConfigDirectoryPath(profile.id),
      targetName: 'agent.yaml',
    );
    final toolPath = await _copyConfigIntoAppDirectory(
      sourcePath: harness.toolConfigPath,
      targetDirectory: '${toolConfigsDirectoryPath()}/${profile.id}',
      targetName: aaToolPackageConfigFilename,
    );
    final graphToolPath = await _writeDefaultGraphToolConfig(
      profile: workflowProfile,
      requestedPath: toolPath ?? harness.toolConfigPath,
      targetName: aaToolPackageConfigFilename,
    );
    final next = workflowProfile.copyWith(
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
    if (await target.exists()) {
      final document = ModelConfigDocument.parse(await target.readAsString());
      final scoped = modelConfigDocumentForDefaultProvider(document);
      if (scoped.toYaml() != document.toYaml()) {
        await target.writeAsString(scoped.toYaml());
      }
      return target.path;
    }
    final document = await _configuredModelDocumentFromSource(sourcePath);
    await target.writeAsString(document.toYaml());
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
    return modelConfigDocumentForDefaultProvider(
      document.copyWith(defaultRef: defaultRef, providers: providers),
    );
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

  /// Returns a profile whose agent writes to the selected memory domain.
  RuntimeProfile _withSelectedMemoryDomain(
    RuntimeProfile profile,
    String domainId,
  ) {
    final memory = profile.agentMemory;
    return profile.copyWith(
      agentMemory: AgentMemoryRuntime(
        actor: memory.actor,
        readDomains: _domainListWith(memory.readDomains, domainId),
        writeDomains: _domainListWith(memory.writeDomains, domainId),
        defaultWriteDomain: domainId,
        allowedSensitivities: memory.allowedSensitivities,
        allowedFlows: memory.allowedFlows,
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

  /// Returns a domain grant list containing the selected domain once.
  List<String> _domainListWith(List<String> domains, String domainId) {
    final values = <String>[];
    for (final domain in domains) {
      final trimmed = domain.trim();
      if (trimmed.isNotEmpty && !values.contains(trimmed)) {
        values.add(trimmed);
      }
    }
    if (!values.contains(domainId)) {
      values.add(domainId);
    }
    return values;
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

  /// Rebuilds owned service clients from the active agent runtime topology.
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

/// Returns a profile whose workflow files belong to this runtime agent bundle.
RuntimeProfile _withAgentOwnedWorkflowDefinitions(RuntimeProfile profile) {
  return profile.copyWith(
    workflow: profile.workflow.copyWith(
      definitionsDir: agentWorkflowDefinitionsDirectoryPath(profile.id),
    ),
  );
}

/// Copies workflow definition files into a newly created runtime agent bundle.
Future<void> _copyWorkflowDefinitionsForRuntimeAgent(
  RuntimeProfile source,
  RuntimeProfile target,
) async {
  final sourcePath = _workflowDefinitionsCopySourcePath(source);
  final targetPath = workflowDefinitionsDirectoryPathForProfile(target);
  if (_normalizedFileSystemPath(sourcePath) ==
      _normalizedFileSystemPath(targetPath)) {
    await Directory(targetPath).create(recursive: true);
    return;
  }
  final sourceDirectory = Directory(sourcePath);
  final targetDirectory = Directory(targetPath);
  if (!await sourceDirectory.exists()) {
    await targetDirectory.create(recursive: true);
    return;
  }
  await _copyDirectoryContents(sourceDirectory, targetDirectory);
}

/// Returns the source workflow folder to copy when bundling a runtime agent.
String _workflowDefinitionsCopySourcePath(RuntimeProfile source) {
  final configured = source.workflow.definitionsDir.trim();
  if (configured.isEmpty) {
    return workflowDefinitionsDirectoryPathForProfile(source);
  }
  final normalized = configured.replaceAll('\\', '/');
  final agentRoot =
      '${agentRuntimeConfigRootDirectoryPath().replaceAll('\\', '/')}/';
  if (normalized.startsWith(agentRoot) && normalized.endsWith('/workflows')) {
    return workflowDefinitionsDirectoryPathForProfile(source);
  }
  return configured;
}

/// Copies ordinary files and directories while rejecting symbolic links.
Future<void> _copyDirectoryContents(
  Directory source,
  Directory target, {
  bool overwriteExisting = false,
}) async {
  await target.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final targetPath = '${target.path}/$relative';
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw FileSystemException(
        'Runtime agent bundle files cannot include symbolic links',
        entity.path,
      );
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(targetPath).create(recursive: true);
      continue;
    }
    if (type == FileSystemEntityType.file) {
      final targetFile = File(targetPath);
      if (await targetFile.exists() && !overwriteExisting) {
        continue;
      }
      await targetFile.parent.create(recursive: true);
      await File(entity.path).copy(targetPath);
    }
  }
}

/// Returns a normalized absolute path string for path comparison.
String _normalizedFileSystemPath(String path) {
  return File(path).absolute.path.replaceAll('\\', '/');
}

/// Reports whether two profiles would launch the same local services.
bool _sameRuntimeLaunchSignature(RuntimeProfile left, RuntimeProfile right) {
  return listEquals(
    _runtimeLaunchSignature(left),
    _runtimeLaunchSignature(right),
  );
}

/// Returns launch-affecting profile values for local service restarts.
List<String> _runtimeLaunchSignature(RuntimeProfile profile) {
  return <String>[
    'profile:${profile.id}',
    ..._harnessLaunchSignature(profile),
    ..._workflowLaunchSignature(profile),
    ..._gatewayLaunchSignature(profile),
    for (final server in profile.mcpServers.where((server) => server.enabled))
      ..._mcpServerLaunchSignature(profile, server),
  ];
}

/// Returns launch-affecting harness values.
List<String> _harnessLaunchSignature(RuntimeProfile profile) {
  final harness = profile.harness;
  return <String>[
    'harness:${agentRuntimeServiceId(profile, harness.id)}',
    'harness.enabled:true',
    'harness.auto:${harness.autoStart}',
    'harness.workdir:${harness.workingDirectory}',
    'harness.executable:${harness.executablePath}',
    'harness.health:${harness.sessionsUrl}',
    ...harnessArgumentsForProfile(profile).map((value) => 'harness.arg:$value'),
  ];
}

/// Returns launch-affecting workflow values.
List<String> _workflowLaunchSignature(RuntimeProfile profile) {
  final workflow = profile.workflow;
  return <String>[
    'workflow:${agentRuntimeServiceId(profile, workflow.id)}',
    'workflow.enabled:${workflow.enabled}',
    'workflow.hosted:${workflow.hostedByHarness}',
    'workflow.auto:${workflow.autoStart}',
    'workflow.workdir:${workflow.workingDirectory}',
    'workflow.executable:${workflow.executablePath}',
    'workflow.health:${workflow.healthUrl}',
    ...workflowArgumentsForProfile(
      profile,
    ).map((value) => 'workflow.arg:$value'),
  ];
}

/// Returns launch-affecting gateway values.
List<String> _gatewayLaunchSignature(RuntimeProfile profile) {
  final gateway = profile.gateway;
  return <String>[
    'gateway:${agentRuntimeServiceId(profile, gateway.id)}',
    'gateway.enabled:${gateway.enabled}',
    'gateway.auto:${gateway.autoStart}',
    'gateway.workdir:${gateway.workingDirectory}',
    'gateway.executable:${gateway.executablePath}',
    'gateway.health:${gateway.healthUrl}',
    ...gatewayArgumentsForProfile(profile).map((value) => 'gateway.arg:$value'),
  ];
}

/// Returns launch-affecting MCP server values.
List<String> _mcpServerLaunchSignature(
  RuntimeProfile profile,
  McpServerRuntime server,
) {
  return <String>[
    'mcp:${agentRuntimeServiceId(profile, server.id)}',
    'mcp.kind:${server.kind}',
    'mcp.auto:${server.autoStart}',
    'mcp.endpoint:${server.endpoint}',
    'mcp.health:${server.healthUrl}',
    'mcp.workdir:${server.workingDirectory}',
    'mcp.executable:${server.executablePath}',
    'mcp.db:${server.dbPath}',
    'mcp.data:${server.dataDir}',
    for (final argument in server.arguments) 'mcp.arg:$argument',
  ];
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
