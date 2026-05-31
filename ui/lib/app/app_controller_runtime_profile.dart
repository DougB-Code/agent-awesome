/// Agent runtime and config-file runbooks for AgentAwesomeAppController.
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

  /// Exports the active runtime configuration as a remote Docker bundle.
  Future<RemoteRuntimeDockerBundle> exportRemoteDockerBundle({
    String outputDirectory = '',
    String imageTag = 'agent-awesome/remote-runtime:latest',
    String gatewayBaseUrl = '',
    String localModelPath = '',
    String localModelServerExecutablePath = '',
  }) async {
    final profile = runtimeProfile;
    if (profile == null) {
      throw StateError('No runtime profile is loaded');
    }
    final bundleRoot = outputDirectory.trim().isEmpty
        ? '${config.workspaceRoot}/${remoteDockerBundleDirectoryPath(profile.id)}'
        : outputDirectory.trim();
    final bundleDirectory = Directory(bundleRoot);
    final configDirectory = Directory('${bundleDirectory.path}/config');
    final runbookDirectory = Directory('${configDirectory.path}/runbooks');
    final scriptsDirectory = Directory('${bundleDirectory.path}/scripts');
    final binDirectory = Directory('${configDirectory.path}/bin');
    await configDirectory.create(recursive: true);
    await runbookDirectory.create(recursive: true);
    await scriptsDirectory.create(recursive: true);
    final bundledModelServerPath = await _copyLocalModelServerExecutable(
      localModelServerExecutablePath,
      binDirectory,
    );

    await _copyBundleFile(
      profile.harness.agentConfigPath,
      '${configDirectory.path}/agent.yaml',
      'agent config',
    );
    await _copyBundleFile(
      profile.harness.toolConfigPath,
      '${configDirectory.path}/tool.yaml',
      'tool config',
    );
    await _copyRemoteModelConfig('${configDirectory.path}/model.yaml');
    await _copyRunbookDefinitionsForRemoteBundle(profile, runbookDirectory);

    final remoteProfilePath = '${bundleDirectory.path}/runtime-profile.json';
    final remoteProfile = _remoteGatewayProfile(
      profile,
      gatewayBaseUrl: gatewayBaseUrl.trim().isEmpty
          ? profile.gateway.apiBaseUrl
          : gatewayBaseUrl.trim(),
    );
    await File(
      remoteProfilePath,
    ).writeAsString(encodeRuntimeProfileJson(remoteProfile));

    final dockerfilePath = '${bundleDirectory.path}/Dockerfile';
    final relativeBundle = _workspaceRelativePath(bundleDirectory.path);
    await File(dockerfilePath).writeAsString(
      _remoteDockerfileForBundle(
        relativeBundle,
        hasModelServerExecutable: bundledModelServerPath.isNotEmpty,
      ),
    );

    final tag = imageTag.trim().isEmpty
        ? 'agent-awesome/remote-runtime:latest'
        : imageTag.trim();
    final buildCommand = <String>[
      'docker',
      'build',
      '-f',
      dockerfilePath,
      '-t',
      tag,
      config.workspaceRoot,
    ];
    final runCommand = _remoteDockerRunCommand(
      tag,
      gatewayBaseUrl: remoteProfile.gateway.apiBaseUrl,
      profileId: remoteProfile.gateway.profileId,
      appName: remoteProfile.harness.appName,
      userId: remoteProfile.harness.userId,
      localModelPath: localModelPath,
      modelServerExecutablePath: _containerModelServerExecutablePath(
        bundledModelServerPath,
      ),
    );
    final buildScriptPath = '${scriptsDirectory.path}/build-image.sh';
    final runScriptPath = '${scriptsDirectory.path}/run-container.sh';
    final deployScriptPath = '${scriptsDirectory.path}/deploy-remote.sh';
    await _writeExecutableScript(
      buildScriptPath,
      _shellScriptForCommand(buildCommand),
    );
    await _writeExecutableScript(
      runScriptPath,
      _shellScriptForCommand(runCommand),
    );
    await _writeExecutableScript(
      deployScriptPath,
      _remoteDeployScript(
        imageTag: tag,
        runCommand: runCommand,
        localModelPath: localModelPath,
      ),
    );
    statusMessage = 'Remote Docker bundle ready';
    _notifyControllerListeners();
    return RemoteRuntimeDockerBundle(
      rootPath: bundleDirectory.path,
      dockerfilePath: dockerfilePath,
      runtimeProfilePath: remoteProfilePath,
      buildScriptPath: buildScriptPath,
      runScriptPath: runScriptPath,
      remoteDeployScriptPath: deployScriptPath,
      imageTag: tag,
      buildCommand: buildCommand,
      runCommand: runCommand,
      remoteDeployCommand: <String>['bash', deployScriptPath],
      localModelPath: localModelPath.trim(),
      remoteModelPath: _containerModelPath(localModelPath),
      localModelServerExecutablePath: localModelServerExecutablePath.trim(),
      remoteModelServerExecutablePath: _containerModelServerExecutablePath(
        bundledModelServerPath,
      ),
    );
  }

  /// Returns the active app-managed local model artifact path for bundle mounts.
  Future<String> activeLocalModelArtifactPath() async {
    final provider = await _activeLocalProviderConfig();
    if (provider == null) {
      return '';
    }
    return _configuredLocalModelPath(provider);
  }

  /// Returns the active llama.cpp server executable path for Docker bundles.
  Future<String> activeLocalLlamaServerExecutablePath() async {
    final provider = await _activeLocalProviderConfig();
    if (provider == null) {
      return '';
    }
    final descriptor = _localModelDescriptorForProvider(provider);
    if (descriptor.runtimeKind != LocalModelRuntimeKind.llamaCpp) {
      return '';
    }
    final configured = provider.executable.trim();
    if (configured.isNotEmpty && await File(configured).exists()) {
      return configured;
    }
    return await _localModelExecutableForConfig(descriptor) ?? '';
  }

  /// Builds a generated remote Docker runtime image through the UI process boundary.
  Future<ManagedProcessResult> buildRemoteDockerBundleImage(
    RemoteRuntimeDockerBundle bundle, {
    String dockerExecutable = 'docker',
  }) async {
    final result = await processSupervisor.run(
      ManagedProcessSpec(
        id: 'remote-docker-build-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Remote Docker build',
        executable: dockerExecutable,
        arguments: _commandArgumentsForExecutable(
          bundle.buildCommand,
          dockerExecutable,
        ),
        workingDirectory: config.workspaceRoot,
        kind: ManagedProcessKind.oneShotCommand,
        shutdownMode: ManagedProcessShutdownMode.processOnly,
        timeout: const Duration(minutes: 30),
        scope: 'remote-runtime',
      ),
    );
    _throwIfRemoteDockerCommandFailed(result, 'Remote Docker image build');
    statusMessage = 'Remote Docker image built';
    _notifyControllerListeners();
    return result;
  }

  /// Starts a generated remote Docker runtime container under UI supervision.
  Future<ManagedProcessHandle> startRemoteDockerBundleContainer(
    RemoteRuntimeDockerBundle bundle, {
    String dockerExecutable = 'docker',
    String gatewayToken = '',
  }) async {
    final arguments = _dockerRunArgumentsForUI(
      bundle.runCommand,
      dockerExecutable: dockerExecutable,
      gatewayToken: gatewayToken,
    );
    final handle = await processSupervisor.start(
      ManagedProcessSpec(
        id: 'remote-docker-container',
        name: 'Remote Docker runtime',
        executable: dockerExecutable,
        arguments: arguments,
        workingDirectory: config.workspaceRoot,
        kind: ManagedProcessKind.longRunningService,
        shutdownMode: ManagedProcessShutdownMode.processGroup,
        persistence: ManagedProcessPersistence.pidRecord,
        scope: 'remote-runtime',
        outputLogPath: '${config.serviceLogDirectory}/remote-docker.log',
      ),
    );
    statusMessage = 'Remote Docker runtime started';
    _notifyControllerListeners();
    return handle;
  }

  /// Transfers a built Docker image and optional model to a remote Docker host.
  Future<ManagedProcessResult> deployRemoteDockerBundle(
    RemoteRuntimeDockerBundle bundle, {
    required String remoteHost,
    String gatewayToken = '',
    String bashExecutable = 'bash',
  }) async {
    final host = remoteHost.trim();
    if (host.isEmpty) {
      throw ArgumentError.value(
        remoteHost,
        'remoteHost',
        'Remote host is required',
      );
    }
    final environment = <String, String>{
      'AA_REMOTE_HOST': host,
      if (gatewayToken.trim().isNotEmpty)
        'AGENTAWESOME_GATEWAY_TOKEN': gatewayToken.trim(),
    };
    final result = await processSupervisor.run(
      ManagedProcessSpec(
        id: 'remote-docker-deploy-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Remote Docker deploy',
        executable: bashExecutable,
        arguments: <String>[bundle.remoteDeployScriptPath],
        workingDirectory: config.workspaceRoot,
        environment: environment,
        kind: ManagedProcessKind.oneShotCommand,
        shutdownMode: ManagedProcessShutdownMode.processOnly,
        timeout: const Duration(minutes: 30),
        scope: 'remote-runtime',
      ),
    );
    _throwIfRemoteDockerCommandFailed(result, 'Remote Docker deploy');
    statusMessage = 'Remote Docker runtime deployed';
    _notifyControllerListeners();
    return result;
  }

  /// Copies the remote-model template used by generated Docker bundles.
  Future<void> _copyRemoteModelConfig(String targetPath) async {
    final source = File(
      '${config.workspaceRoot}/deploy/docker/config/model.local-gemma.yaml',
    );
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    if (await source.exists()) {
      await source.copy(target.path);
      return;
    }
    await target.writeAsString(_defaultRemoteGemmaModelConfig());
  }

  /// Copies a configured local model-server executable into the bundle.
  Future<String> _copyLocalModelServerExecutable(
    String executablePath,
    Directory binDirectory,
  ) async {
    final sourcePath = executablePath.trim();
    if (sourcePath.isEmpty) {
      return '';
    }
    final source = File(sourcePath);
    if (!await source.exists()) {
      return '';
    }
    await binDirectory.create(recursive: true);
    final fileName = source.uri.pathSegments.last;
    final target = File('${binDirectory.path}/$fileName');
    await source.copy(target.path);
    return target.path;
  }

  /// Returns a path that Docker can COPY from the workspace build context.
  String _workspaceRelativePath(String path) {
    final root = Directory(
      config.workspaceRoot,
    ).absolute.path.replaceAll('\\', '/');
    final absolute = Directory(path).absolute.path.replaceAll('\\', '/');
    if (absolute == root) {
      return '.';
    }
    final prefix = '$root/';
    if (!absolute.startsWith(prefix)) {
      throw StateError('Remote Docker bundle output must be inside workspace');
    }
    return absolute.substring(prefix.length);
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

  /// Verifies one model provider by running the harness model smoke check.
  Future<ModelProviderVerificationResult> verifyModelProviderConnection({
    required String modelPath,
    required ModelProviderConfig provider,
  }) async {
    final selectedModel = modelConfigModelForProvider(
      provider,
      provider.defaultModel,
    );
    if (selectedModel == null) {
      throw StateError(
        'Provider ${provider.id} has no default model to verify.',
      );
    }
    final harness = runtimeProfile?.harness;
    final workingDirectory = harness?.workingDirectory.trim().isNotEmpty == true
        ? harness!.workingDirectory
        : '${config.workspaceRoot}/harness';
    final executablePath = harness?.executablePath.trim().isNotEmpty == true
        ? harness!.executablePath
        : 'agent-awesome';
    final result = await processSupervisor.run(
      ManagedProcessSpec(
        id: 'model-check-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Model provider check',
        executable: executablePath,
        arguments: buildModelCheckCommandArguments(
          modelPath: modelPath,
          providerId: provider.id,
          modelId: selectedModel.id,
          prompt: 'Reply with OK.',
        ),
        workingDirectory: workingDirectory,
        environment: await _modelProviderVerificationEnvironment(provider),
        kind: ManagedProcessKind.oneShotCommand,
        shutdownMode: ManagedProcessShutdownMode.processOnly,
        timeout: const Duration(minutes: 2),
        scope: 'model-checks',
      ),
    );
    return parseModelProviderVerificationProcessResult(result);
  }

  /// Returns child-process environment for credential-backed model checks.
  Future<Map<String, String>> _modelProviderVerificationEnvironment(
    ModelProviderConfig provider,
  ) async {
    final reference = provider.apiKey.trim();
    if (!_isEnvironmentCredentialReference(reference)) {
      return const <String, String>{};
    }
    final lookup = await credentialStore.lookup(reference);
    if (!lookup.found || lookup.secretValue.trim().isEmpty) {
      return const <String, String>{};
    }
    return <String, String>{reference: lookup.secretValue.trim()};
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
    final memoryService = _primaryMemoryService(profile);
    final domain = McpServerRuntime(
      id: id,
      label: _memoryDomainLabel(id),
      kind: 'memory',
      endpoint: memoryService.endpoint,
      healthUrl: memoryService.healthUrl,
      workingDirectory: '',
      executablePath: '',
      dbPath: '',
      dataDir: '',
      arguments: const <String>[],
      autoStart: false,
      enabled: true,
    );
    await _upsertMemoryDomainPolicy(domain);
    final next = profile.copyWith(
      memoryDomains: <McpServerRuntime>[...profile.memoryDomains, domain],
    );
    await _saveRuntimeProfileAndGeneratedToolConfig(_validatedProfile(next));
    await _reloadControlPlaneForMemoryTopology(_activeRuntimeProfile());
    await _withMemoryClientForServer(
      domain,
      (client) => client.createMemoryDomain(actor: _memoryActor()),
    );
    statusMessage = '${domain.label} domain created';
    _notifyControllerListeners();
    return domain;
  }

  /// Creates an externally hosted memory domain from a user-provided MCP URL.
  Future<McpServerRuntime> createExternalMemoryDomainRuntime({
    required String label,
    required String endpoint,
    String healthUrl = '',
  }) async {
    final profile = _activeRuntimeProfile();
    final parsedEndpoint = _validatedHttpURL(endpoint, 'memory MCP endpoint');
    final id = _uniqueMemoryDomainId(profile, _safeMemoryDomainPrefix(label));
    final resolvedHealthUrl = healthUrl.trim().isEmpty
        ? _externalMemoryHealthUrl(parsedEndpoint)
        : _validatedHttpURL(healthUrl, 'memory health URL').toString();
    final domain = McpServerRuntime(
      id: id,
      label: label.trim().isEmpty ? _memoryDomainLabel(id) : label.trim(),
      kind: 'memory',
      endpoint: parsedEndpoint.toString(),
      healthUrl: resolvedHealthUrl,
      workingDirectory: '',
      executablePath: '',
      dbPath: '',
      dataDir: '',
      arguments: const <String>[],
      autoStart: false,
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
    final memoryService = _primaryMemoryService(profile);
    final domain = source.copyWith(
      id: id,
      label: '${source.label.trim().isEmpty ? source.id : source.label} Copy',
      endpoint: memoryService.endpoint,
      healthUrl: memoryService.healthUrl,
      workingDirectory: '',
      executablePath: '',
      dbPath: '',
      dataDir: '',
      arguments: const <String>[],
      autoStart: false,
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
    final source = profile.memoryDomains.firstWhere(
      (domain) => domain.id == domainId,
      orElse: () => throw FileSystemException(
        'Memory domain is not referenced',
        domainId,
      ),
    );
    if (source.autoStart) {
      throw FileSystemException(
        'Cannot delete the managed memory service domain',
        domainId,
      );
    }
    await _withMemoryClientForServer(
      source,
      (client) => client.removeMemoryDomain(actor: _memoryActor()),
    );
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
    await _removeMemoryDomainPolicy(domainId);
    await _saveRuntimeProfileAndGeneratedToolConfig(_validatedProfile(next));
    await _reloadControlPlaneForMemoryTopology(_activeRuntimeProfile());
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
    final runbookProfile = _withAgentOwnedRunbookDefinitions(storageProfile);
    await _copyRunbookDefinitionsForRuntimeAgent(profile, runbookProfile);
    final harness = runbookProfile.harness;
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
      profile: runbookProfile,
      requestedPath: toolPath ?? harness.toolConfigPath,
      targetName: aaToolPackageConfigFilename,
    );
    final next = runbookProfile.copyWith(
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
        final dataDir = server.dataDir.trim().isEmpty
            ? defaultMemoryDataDirectoryPath()
            : server.dataDir;
        return server.copyWith(
          dbPath: '',
          dataDir: dataDir,
          arguments: _memoryStorageArguments(
            server.arguments,
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
    required String dataDir,
  }) {
    final withoutStorageFlags = <String>[];
    for (var index = 0; index < arguments.length; index++) {
      final value = arguments[index];
      if (value == '--db' ||
          value == '--data' ||
          value == '--firewall-policy' ||
          value == '--domain-policy') {
        index++;
        continue;
      }
      withoutStorageFlags.add(value);
    }
    return <String>[
      ...withoutStorageFlags,
      '--data',
      dataDir,
      '--domain-policy',
      memoryDomainPolicyPath(),
    ];
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
      runbook: profile.runbook,
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

  /// Returns the managed memory service that owns the pooled domain database root.
  McpServerRuntime _primaryMemoryService(RuntimeProfile profile) {
    for (final domain in profile.memoryDomains) {
      if (domain.kind == 'memory' && domain.autoStart) {
        return domain;
      }
    }
    for (final domain in profile.memoryDomains) {
      if (domain.kind == 'memory') {
        return domain;
      }
    }
    throw StateError('Memory service is not configured');
  }

  /// Adds or refreshes the daemon policy entry for one memory domain.
  Future<void> _upsertMemoryDomainPolicy(McpServerRuntime domain) async {
    final current = appSettings.effectiveMemoryFirewalls;
    final replacement = MemoryFirewall(
      id: domain.id,
      label: domain.label.trim().isEmpty
          ? _memoryDomainLabel(domain.id)
          : domain.label,
    );
    final next = <MemoryFirewall>[
      for (final firewall in current)
        if (firewall.id == domain.id) replacement else firewall,
      if (!current.any((firewall) => firewall.id == domain.id)) replacement,
    ];
    await saveAppSettings(appSettings.copyWith(memoryFirewalls: next));
  }

  /// Removes the daemon policy entry for a deleted memory domain.
  Future<void> _removeMemoryDomainPolicy(String domainId) async {
    final id = domainId.trim();
    if (id.isEmpty) {
      return;
    }
    final next = appSettings.effectiveMemoryFirewalls
        .where((firewall) => firewall.id != id)
        .toList();
    await saveAppSettings(appSettings.copyWith(memoryFirewalls: next));
  }

  /// Restarts gateway and harness routing without touching the memory pool.
  Future<void> _reloadControlPlaneForMemoryTopology(
    RuntimeProfile profile,
  ) async {
    if (!config.autoStartLocalServices || _isClosing) {
      return;
    }
    localProcessStatuses = await _startRequiredRuntimeServices(
      profile,
      includeMcpServers: false,
    );
    for (final status in localProcessStatuses) {
      await _log(
        'memory topology reload ${status.name} ${status.state.name}: ${status.message}',
      );
    }
  }

  /// Formats a generated label for a domain id.
  String _memoryDomainLabel(String id) {
    return id
        .split(RegExp(r'[-_]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  /// Returns a safe id prefix derived from a user-facing memory domain label.
  String _safeMemoryDomainPrefix(String label) {
    final normalized = label
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'memory' : normalized;
  }

  /// Parses and validates an absolute HTTP URL for runtime profile storage.
  Uri _validatedHttpURL(String value, String label) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw FormatException('$label must be an absolute HTTP URL');
    }
    return uri;
  }

  /// Returns the conventional health-check URL beside an external MCP route.
  String _externalMemoryHealthUrl(Uri endpoint) {
    return endpoint.replace(path: '/healthz', query: null).toString();
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
        baseUrl: _runbookBaseUrl(profile.gateway.apiBaseUrl),
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

/// ModelProviderVerificationResult summarizes one provider smoke-check run.
class ModelProviderVerificationResult {
  /// Creates an immutable model provider verification result.
  const ModelProviderVerificationResult({
    required this.providerId,
    required this.modelId,
    required this.modelName,
    required this.responseText,
  });

  /// Provider id reported by the harness model check.
  final String providerId;

  /// Model alias reported by the harness model check.
  final String modelId;

  /// Provider-specific model name sent to the runtime.
  final String modelName;

  /// First non-empty smoke-check response text.
  final String responseText;
}

/// Builds harness CLI arguments for one model provider smoke check.
List<String> buildModelCheckCommandArguments({
  required String modelPath,
  required String providerId,
  required String modelId,
  String prompt = '',
}) {
  return <String>[
    'models',
    'check',
    '--model',
    modelPath,
    '--provider',
    providerId.trim(),
    '--model-id',
    modelId.trim(),
    if (prompt.trim().isNotEmpty) ...<String>['--prompt', prompt.trim()],
  ];
}

/// Parses the harness CLI output from a successful model provider check.
ModelProviderVerificationResult parseModelProviderVerificationProcessResult(
  ManagedProcessResult result,
) {
  if (result.exitCode != 0) {
    final detail = _processFailureDetail(result);
    throw StateError(
      detail.isEmpty ? 'Model provider verification failed' : detail,
    );
  }
  final output = result.stdout.trim();
  final match = RegExp(
    r'Model check passed: provider=(.*?) model_id=(.*?) model=(.*?) response=(.*)$',
  ).firstMatch(output);
  if (match == null) {
    throw StateError('Model provider verification returned unexpected output');
  }
  return ModelProviderVerificationResult(
    providerId: match.group(1)!.trim(),
    modelId: match.group(2)!.trim(),
    modelName: match.group(3)!.trim(),
    responseText: _unquoteModelCheckResponse(match.group(4)!.trim()),
  );
}

/// Reports whether a credential reference can be injected as an env var.
bool _isEnvironmentCredentialReference(String reference) {
  return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(reference.trim());
}

/// Returns a concise failure detail from a completed model-check process.
String _processFailureDetail(ManagedProcessResult result) {
  final stderr = result.stderr.trim();
  if (stderr.isNotEmpty) {
    return stderr;
  }
  return result.stdout.trim();
}

/// Decodes the CLI's quoted smoke-check response enough for UI display.
String _unquoteModelCheckResponse(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
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

/// Returns a profile whose runbook files belong to this runtime agent bundle.
RuntimeProfile _withAgentOwnedRunbookDefinitions(RuntimeProfile profile) {
  return profile.copyWith(
    runbook: profile.runbook.copyWith(
      definitionsDir: agentRunbookDefinitionsDirectoryPath(profile.id),
    ),
  );
}

/// Copies runbook definition files into a newly created runtime agent bundle.
Future<void> _copyRunbookDefinitionsForRuntimeAgent(
  RuntimeProfile source,
  RuntimeProfile target,
) async {
  final sourcePath = _runbookDefinitionsCopySourcePath(source);
  final targetPath = runbookDefinitionsDirectoryPathForProfile(target);
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

/// Copies runbook definitions into a generated remote Docker bundle.
Future<void> _copyRunbookDefinitionsForRemoteBundle(
  RuntimeProfile source,
  Directory targetDirectory,
) async {
  final sourceDirectory = Directory(_runbookDefinitionsCopySourcePath(source));
  if (!await sourceDirectory.exists()) {
    await targetDirectory.create(recursive: true);
    return;
  }
  await _copyDirectoryContents(
    sourceDirectory,
    targetDirectory,
    overwriteExisting: true,
  );
}

/// Copies one required bundle config file while rejecting symlink sources.
Future<void> _copyBundleFile(
  String sourcePath,
  String targetPath,
  String label,
) async {
  final source = File(sourcePath.trim());
  if (source.path.trim().isEmpty || !await source.exists()) {
    throw StateError('Remote Docker bundle requires $label');
  }
  final sourceType = await FileSystemEntity.type(
    source.path,
    followLinks: false,
  );
  if (sourceType == FileSystemEntityType.link) {
    throw FileSystemException(
      'Remote Docker bundle files cannot include symbolic links',
      source.path,
    );
  }
  final target = File(targetPath);
  await target.parent.create(recursive: true);
  await source.copy(target.path);
}

/// Returns the source runbook folder to copy when bundling a runtime agent.
String _runbookDefinitionsCopySourcePath(RuntimeProfile source) {
  final configured = source.runbook.definitionsDir.trim();
  if (configured.isEmpty) {
    return runbookDefinitionsDirectoryPathForProfile(source);
  }
  final normalized = configured.replaceAll('\\', '/');
  final agentRoot =
      '${agentRuntimeConfigRootDirectoryPath().replaceAll('\\', '/')}/';
  if (normalized.startsWith(agentRoot) && normalized.endsWith('/runbooks')) {
    return runbookDefinitionsDirectoryPathForProfile(source);
  }
  return configured;
}

/// Returns a remote-gateway UI profile for a generated Docker runtime.
RuntimeProfile _remoteGatewayProfile(
  RuntimeProfile source, {
  required String gatewayBaseUrl,
}) {
  final gatewayApi = _normalizeAPIBaseUrl(gatewayBaseUrl);
  final gatewayHealth = _gatewayHealthUrl(gatewayApi);
  final gatewayContext = _gatewayContextBaseUrl(gatewayApi);
  final gatewayMcp = _gatewayMcpUrl(gatewayApi);
  return source.copyWith(
    id: '${source.id}-remote',
    label: '${source.label} Remote',
    harness: source.harness.copyWith(
      id: '${source.harness.id}-remote',
      label: 'Remote Harness',
      apiBaseUrl: gatewayApi,
      contextApiBaseUrl: gatewayContext,
      workingDirectory: '/opt/agent-awesome',
      executablePath: '/usr/local/bin/agent-awesome',
      modelConfigPath: '/opt/agent-awesome/config/model.yaml',
      agentConfigPath: '/opt/agent-awesome/config/agent.yaml',
      toolConfigPath: '/opt/agent-awesome/config/tool.yaml',
      autoStart: false,
    ),
    gateway: source.gateway.copyWith(
      id: '${source.gateway.id}-remote',
      label: 'Remote Gateway',
      apiBaseUrl: gatewayApi,
      healthUrl: gatewayHealth,
      statusUrl: _gatewayStatusUrl(gatewayApi),
      workingDirectory: '/opt/agent-awesome',
      executablePath: '/usr/local/bin/agent-gateway',
      harnessBaseUrl: gatewayApi,
      contextBaseUrl: gatewayContext,
      memoryMcpUrl: gatewayMcp,
      profileId: source.gateway.profileId.trim().isEmpty
          ? source.id
          : source.gateway.profileId,
      authCredential: source.gateway.authCredential.trim().isEmpty
          ? 'AGENTAWESOME_GATEWAY_TOKEN'
          : source.gateway.authCredential,
      modelProviderId: 'local-gemma',
      modelId: 'gemma',
      autoStart: false,
      enabled: true,
    ),
    runbook: source.runbook.copyWith(
      id: '${source.runbook.id}-remote',
      label: 'Remote Runbook',
      apiBaseUrl: _gatewayRunbookBaseUrl(gatewayApi),
      healthUrl: gatewayHealth,
      hostedByHarness: false,
      workingDirectory: '',
      executablePath: '',
      definitionsDir: '',
      dbPath: '',
      autoStart: false,
      enabled: source.runbook.enabled,
    ),
    memoryDomains: source.memoryDomains.map((domain) {
      return domain.copyWith(
        label: domain.label.trim().isEmpty
            ? 'Remote Memory'
            : '${domain.label} Remote',
        endpoint: _gatewayMcpDomainUrl(gatewayApi, domain.id),
        healthUrl: gatewayHealth,
        workingDirectory: '',
        executablePath: '',
        dbPath: '',
        dataDir: '',
        arguments: const <String>[],
        autoStart: false,
      );
    }).toList(),
  );
}

/// Returns Dockerfile text for a generated configured remote runtime image.
String _remoteDockerfileForBundle(
  String relativeBundle, {
  required bool hasModelServerExecutable,
}) {
  final bundle = relativeBundle.replaceAll('\\', '/');
  final modelServerCopy = hasModelServerExecutable
      ? '''
COPY $bundle/config/bin /opt/agent-awesome/bin
'''
      : '';
  final modelServerChmod = hasModelServerExecutable
      ? '''
    && find /opt/agent-awesome/bin -type f -exec chmod +x {} \\; \\
'''
      : '';
  return '''
# Builds a configured Agent Awesome remote runtime image.
FROM golang:1.26-bookworm AS build

WORKDIR /src

COPY platform ./platform
COPY harness ./harness
COPY gateway ./gateway
COPY memory ./memory

RUN cd harness && go build -trimpath -buildvcs=false -o /out/agent-awesome ./cmd/agent-awesome
RUN cd harness && go build -trimpath -buildvcs=false -o /out/runbook-service ./cmd/runbook-service
RUN cd gateway && go build -trimpath -buildvcs=false -o /out/agent-gateway ./cmd/agent-gateway
RUN cd memory && go build -trimpath -buildvcs=false -o /out/memoryd ./cmd/memoryd

FROM debian:bookworm-slim

RUN apt-get update \\
    && apt-get install -y --no-install-recommends ca-certificates curl tini \\
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/agent-awesome

COPY --from=build /out/agent-awesome /usr/local/bin/agent-awesome
COPY --from=build /out/runbook-service /usr/local/bin/runbook-service
COPY --from=build /out/agent-gateway /usr/local/bin/agent-gateway
COPY --from=build /out/memoryd /usr/local/bin/memoryd
COPY $bundle/config/agent.yaml /opt/agent-awesome/config/agent.yaml
COPY $bundle/config/tool.yaml /opt/agent-awesome/config/tool.yaml
COPY $bundle/config/model.yaml /opt/agent-awesome/config/model.yaml
COPY $bundle/config/runbooks /opt/agent-awesome/config/runbooks
$modelServerCopy
COPY deploy/docker/entrypoint.sh /usr/local/bin/agent-awesome-container

RUN chmod +x /usr/local/bin/agent-awesome-container \\
$modelServerChmod    && mkdir -p /var/lib/agent-awesome /var/log/agent-awesome

EXPOSE 8070

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \\
  CMD curl -fsS "http://127.0.0.1:8070/healthz" >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/agent-awesome-container"]
''';
}

/// Returns a fallback OpenAI-compatible Gemma model config.
String _defaultRemoteGemmaModelConfig() {
  return '''
# This model config routes the remote container to an OpenAI-compatible Gemma server.
default: local-gemma:gemma
providers:
  local-gemma:
    adapter: openai
    auth: optional
    default: gemma
    url: \${AA_LOCAL_MODEL_CHAT_URL}
    models:
      - id: gemma
        model: \${AA_LOCAL_MODEL_NAME}
''';
}

/// Builds a local Docker run command for one generated remote runtime image.
List<String> _remoteDockerRunCommand(
  String imageTag, {
  required String gatewayBaseUrl,
  required String profileId,
  required String appName,
  required String userId,
  required String localModelPath,
  required String modelServerExecutablePath,
}) {
  final modelPath = localModelPath.trim();
  final modelDirectory = modelPath.isEmpty ? '' : File(modelPath).parent.path;
  final containerModelPath = _containerModelPath(modelPath);
  return <String>[
    'docker',
    'run',
    '--rm',
    '--name',
    'agent-awesome',
    '-p',
    '8070:8070',
    '-e',
    'AGENTAWESOME_GATEWAY_TOKEN',
    '-e',
    'AA_GATEWAY_PUBLIC_BASE_URL=$gatewayBaseUrl',
    '-e',
    'AA_PROFILE_ID=$profileId',
    '-e',
    'AA_APP_NAME=$appName',
    '-e',
    'AA_USER_ID=$userId',
    if (containerModelPath.isNotEmpty) ...<String>[
      '-e',
      'AA_LOCAL_MODEL_PATH=$containerModelPath',
    ],
    if (modelServerExecutablePath.trim().isNotEmpty) ...<String>[
      '-e',
      'AA_LLAMA_SERVER=${modelServerExecutablePath.trim()}',
    ],
    '-e',
    'AA_LOCAL_MODEL_CHAT_URL=http://127.0.0.1:11667/v1/chat/completions',
    '-e',
    'AA_LOCAL_MODEL_NAME=gemma',
    '-v',
    '/srv/agent-awesome/data:/var/lib/agent-awesome',
    '-v',
    '/srv/agent-awesome/logs:/var/log/agent-awesome',
    if (modelDirectory.isNotEmpty) ...<String>[
      '-v',
      '$modelDirectory:/models:ro',
    ],
    imageTag,
  ];
}

/// Returns the in-container model path for a selected local model artifact.
String _containerModelPath(String localModelPath) {
  final trimmed = localModelPath.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return '/models/${File(trimmed).uri.pathSegments.last}';
}

/// Returns the in-container executable path for a bundled model server.
String _containerModelServerExecutablePath(String bundledExecutablePath) {
  final trimmed = bundledExecutablePath.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return '/opt/agent-awesome/bin/${File(trimmed).uri.pathSegments.last}';
}

/// Writes a shell script and makes it executable on Unix hosts.
Future<void> _writeExecutableScript(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  if (!Platform.isWindows) {
    await Process.run('chmod', <String>['+x', file.path]);
  }
}

/// Builds a strict shell script for a generated command.
String _shellScriptForCommand(List<String> command) {
  final escaped = command.map(_shellQuote).join(' \\\n  ');
  return '''
#!/usr/bin/env bash
# Runs a generated Agent Awesome remote Docker command.
set -euo pipefail

$escaped
''';
}

/// Builds a deploy script that loads the image and optional model on a remote host.
String _remoteDeployScript({
  required String imageTag,
  required List<String> runCommand,
  required String localModelPath,
}) {
  final remoteRun = _remoteHostRunCommand(
    runCommand,
  ).map(_shellQuote).join(' \\\n  ');
  final modelPath = localModelPath.trim();
  final modelCopy = modelPath.isEmpty
      ? ''
      : '''
scp ${_shellQuote(modelPath)} "\$AA_REMOTE_HOST:\$AA_REMOTE_ROOT/models/"
''';
  return '''
#!/usr/bin/env bash
# Deploys the generated Agent Awesome runtime image to a remote Docker host.
set -euo pipefail

: "\${AA_REMOTE_HOST:?Set AA_REMOTE_HOST to user@host before deploying.}"
AA_REMOTE_ROOT="\${AA_REMOTE_ROOT:-/srv/agent-awesome}"

ssh "\$AA_REMOTE_HOST" "mkdir -p '\$AA_REMOTE_ROOT/data' '\$AA_REMOTE_ROOT/logs' '\$AA_REMOTE_ROOT/models'"
docker save ${_shellQuote(imageTag)} | ssh "\$AA_REMOTE_HOST" docker load
$modelCopy
ssh "\$AA_REMOTE_HOST" ${_shellQuote('docker rm -f agent-awesome >/dev/null 2>&1 || true')}
ssh "\$AA_REMOTE_HOST" $remoteRun
''';
}

/// Converts local run arguments to remote-host mount paths.
List<String> _remoteHostRunCommand(List<String> command) {
  final args = <String>[];
  for (final arg in command) {
    if (arg.endsWith(':/models:ro')) {
      args.add('/srv/agent-awesome/models:/models:ro');
    } else {
      args.add(arg);
    }
  }
  return args;
}

/// Quotes one shell argument.
String _shellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

/// Returns command arguments after replacing the executable if requested.
List<String> _commandArgumentsForExecutable(
  List<String> command,
  String executable,
) {
  if (command.isEmpty) {
    return const <String>[];
  }
  final first = command.first.trim();
  if (first == executable.trim() || first == 'docker') {
    return command.sublist(1);
  }
  return command;
}

/// Converts the generated Docker run command into UI process arguments.
List<String> _dockerRunArgumentsForUI(
  List<String> command, {
  required String dockerExecutable,
  required String gatewayToken,
}) {
  final args = _commandArgumentsForExecutable(command, dockerExecutable);
  final token = gatewayToken.trim();
  if (token.isEmpty) {
    return args;
  }
  final next = <String>[];
  for (final arg in args) {
    if (arg == 'AGENTAWESOME_GATEWAY_TOKEN' ||
        arg.startsWith('AGENTAWESOME_GATEWAY_TOKEN=')) {
      next.add('AGENTAWESOME_GATEWAY_TOKEN=$token');
    } else {
      next.add(arg);
    }
  }
  return next;
}

/// Reports failed Docker build or run commands with captured diagnostics.
void _throwIfRemoteDockerCommandFailed(
  ManagedProcessResult result,
  String label,
) {
  if (!result.timedOut && result.exitCode == 0) {
    return;
  }
  final detail = result.stderr.trim().isEmpty
      ? result.stdout.trim()
      : result.stderr.trim();
  if (result.timedOut) {
    throw StateError('$label timed out${detail.isEmpty ? '' : ': $detail'}');
  }
  throw StateError(
    '$label failed with exit ${result.exitCode}${detail.isEmpty ? '' : ': $detail'}',
  );
}

/// Normalizes a gateway URL to the API base path.
String _normalizeAPIBaseUrl(String value) {
  final trimmed = value.trim().isEmpty ? 'http://127.0.0.1:8070/api' : value;
  final uri = Uri.parse(trimmed);
  if (uri.path == '/api') {
    return uri.toString();
  }
  return uri.replace(path: '/api', query: null).toString();
}

/// Returns the gateway health URL for an API base URL.
String _gatewayHealthUrl(String gatewayApi) {
  final uri = Uri.parse(gatewayApi);
  return uri.replace(path: '/healthz', query: null).toString();
}

/// Returns the gateway beta status URL for an API base URL.
String _gatewayStatusUrl(String gatewayApi) {
  final uri = Uri.parse(gatewayApi);
  return uri.replace(path: '/api/gateway/beta-status', query: null).toString();
}

/// Returns the gateway context API URL for an API base URL.
String _gatewayContextBaseUrl(String gatewayApi) {
  final uri = Uri.parse(gatewayApi);
  return uri.replace(path: '/api/context', query: null).toString();
}

/// Returns the gateway memory MCP URL for an API base URL.
String _gatewayMcpUrl(String gatewayApi) {
  final uri = Uri.parse(gatewayApi);
  return uri.replace(path: '/mcp', query: null).toString();
}

/// Returns the gateway-routed runbook API URL.
String _gatewayRunbookBaseUrl(String gatewayApi) {
  final uri = Uri.parse(gatewayApi);
  return uri.replace(path: '/api/runbooks', query: null).toString();
}

/// Returns the gateway-routed MCP URL for one memory domain.
String _gatewayMcpDomainUrl(String gatewayApi, String domainId) {
  final uri = Uri.parse(_gatewayMcpUrl(gatewayApi));
  final base = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return uri.replace(path: '$base/${domainId.trim()}').toString();
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
    ..._runbookLaunchSignature(profile),
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

/// Returns launch-affecting runbook values.
List<String> _runbookLaunchSignature(RuntimeProfile profile) {
  final runbook = profile.runbook;
  return <String>[
    'runbook:${agentRuntimeServiceId(profile, runbook.id)}',
    'runbook.enabled:${runbook.enabled}',
    'runbook.hosted:${runbook.hostedByHarness}',
    'runbook.auto:${runbook.autoStart}',
    'runbook.workdir:${runbook.workingDirectory}',
    'runbook.executable:${runbook.executablePath}',
    'runbook.health:${runbook.healthUrl}',
    ...runbookArgumentsForProfile(profile).map((value) => 'runbook.arg:$value'),
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
