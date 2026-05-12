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
    await _refreshConfigCollections();
    _configureClientsForRuntimeProfile(profile);
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
    await _refreshConfigCollections();
    _configureClientsForRuntimeProfile(profile);
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
    await configFiles.delete(entry.path);
    await _refreshConfigCollections();
    _notifyControllerListeners();
  }

  /// Assigns a model or agent config file to the active profile.
  Future<void> assignConfigFile(ConfigFileEntry entry) async {
    await _assignConfigFile(entry.kind, entry.path);
  }

  /// Saves one required memory server config file.
  Future<void> saveRequiredServerRuntime({
    required String originalId,
    required McpServerRuntime server,
  }) async {
    final profile = _activeRuntimeProfile();
    final index = profile.mcpServers.indexWhere(
      (candidate) => candidate.id == originalId,
    );
    if (index < 0) {
      throw FileSystemException('MCP server is not referenced', originalId);
    }
    final servers = <McpServerRuntime>[
      for (var i = 0; i < profile.mcpServers.length; i++)
        i == index ? server : profile.mcpServers[i],
    ];
    await _saveRequiredServer(profile, server);
    _applyRuntimeProfileServers(profile.copyWith(mcpServers: servers));
    statusMessage = '${server.kind} server saved';
    _notifyControllerListeners();
  }

  /// Enables the selected MCP server for its runtime role.
  Future<void> assignMcpServerForKind(McpServerRuntime selected) async {
    final profile = _activeRuntimeProfile();
    final servers = <McpServerRuntime>[
      for (final server in profile.mcpServers)
        server.kind == selected.kind
            ? server.copyWith(enabled: server.id == selected.id)
            : server,
    ];
    for (var index = 0; index < servers.length; index++) {
      if (servers[index].enabled != profile.mcpServers[index].enabled) {
        await _saveRequiredServer(profile, servers[index]);
      }
    }
    _applyRuntimeProfileServers(profile.copyWith(mcpServers: servers));
    statusMessage = '${selected.kind} server assigned';
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
      targetDirectory: toolConfigsDirectoryPath(),
      targetName: '${profile.id}-tool.yaml',
    );
    final serverPaths = await _copyRequiredServerConfigsIntoAppDirectory(
      storageProfile,
    );
    final graphToolPath = await _writeDefaultGraphToolConfig(
      profile: storageProfile,
      requestedPath: toolPath ?? harness.toolConfigPath,
      targetName: '${profile.id}-tool.yaml',
    );
    final next = storageProfile.copyWith(
      harness: harness.copyWith(
        modelConfigPath: modelPath,
        agentConfigPath: agentPath ?? harness.agentConfigPath,
        toolConfigPath: graphToolPath,
      ),
      memoryServerConfigPath: serverPaths.memoryServerConfigPath,
    );
    if (next.harness.modelConfigPath != harness.modelConfigPath ||
        next.harness.agentConfigPath != harness.agentConfigPath ||
        next.harness.toolConfigPath != harness.toolConfigPath ||
        next.memoryServerConfigPath != profile.memoryServerConfigPath) {
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
      mcpServers: profile.mcpServers.map((server) {
        if (server.kind != 'memory' || !server.autoStart) {
          return server;
        }
        return server.copyWith(
          arguments: _memoryStorageArguments(server.arguments),
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
    if (provider.id == 'local') {
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
  List<String> _memoryStorageArguments(List<String> arguments) {
    final withoutStorageFlags = <String>[];
    for (var index = 0; index < arguments.length; index++) {
      final value = arguments[index];
      if (value == '--db' || value == '--data') {
        index++;
        continue;
      }
      withoutStorageFlags.add(value);
    }
    return <String>[
      ...withoutStorageFlags,
      '--db',
      defaultMemoryDatabasePath(),
      '--data',
      defaultMemoryDataDirectoryPath(),
    ];
  }

  /// Writes the target graph-backed MCP tool config before harness startup.
  Future<String> _writeDefaultGraphToolConfig({
    required RuntimeProfile profile,
    required String requestedPath,
    required String targetName,
  }) async {
    final graphServer = _serverForKind(profile, 'memory');
    if (graphServer == null) {
      throw FileSystemException('Memory MCP server is missing', profile.id);
    }
    var path = requestedPath.trim();
    var file = File(path);
    if (path.isEmpty || !await file.exists()) {
      final directory = Directory(toolConfigsDirectoryPath());
      await directory.create(recursive: true);
      path = '${directory.path}/$targetName';
      file = File(path);
    }

    final document = await file.exists()
        ? ToolConfigDocument.parse(await file.readAsString())
        : emptyToolConfigDocument();
    final target = graphBackedMemoryToolConfig(
      serverKind: graphServer.kind,
      serverEndpoint: graphServer.endpoint,
      localExec: document.localExec,
      headersFromEnv: _mcpHeadersFromEnv(profile, graphServer),
      extra: document.extra,
    );
    final validationError = toolConfigValidationError(target);
    if (validationError.isNotEmpty) {
      throw FileSystemException(validationError, path);
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(target.toYaml());
    await _log('wrote graph-backed MCP tool config $path');
    return path;
  }

  /// Persists one required app service server config.
  Future<void> _saveRequiredServer(
    RuntimeProfile profile,
    McpServerRuntime server,
  ) async {
    final path = _requiredServerConfigPath(profile, server.kind);
    if (path.isEmpty) {
      throw FileSystemException(
        'Server config reference is missing',
        server.id,
      );
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(encodeMcpServerRuntimeJson(server));
  }

  /// Applies changed server configs without rewriting the profile JSON.
  void _applyRuntimeProfileServers(RuntimeProfile profile) {
    runtimeProfile = profile;
    _configureClientsForRuntimeProfile(profile);
    _refreshEndpointSkeleton(profile);
  }

  /// Copies the default memory server config into the app config tree.
  Future<({String memoryServerConfigPath})>
  _copyRequiredServerConfigsIntoAppDirectory(RuntimeProfile profile) async {
    final memoryServer = _serverForKind(profile, 'memory');
    final memoryPath = await _copyConfigIntoAppDirectory(
      sourcePath: profile.memoryServerConfigPath,
      targetDirectory: memoryServerConfigsDirectoryPath(),
      targetName: '${_serverFileName(memoryServer, 'memory')}.json',
    );
    if (memoryServer != null && memoryPath != null) {
      await File(
        memoryPath,
      ).writeAsString(encodeMcpServerRuntimeJson(memoryServer));
    }
    return (
      memoryServerConfigPath: memoryPath ?? profile.memoryServerConfigPath,
    );
  }

  /// Rebuilds owned service clients from the active runtime profile.
  void _configureClientsForRuntimeProfile(RuntimeProfile profile) {
    if (!_assistantClientInjected) {
      final gateway = profile.gateway;
      final assistantBaseUrl = gateway != null && gateway.enabled
          ? gateway.apiBaseUrl
          : profile.harness.apiBaseUrl;
      assistantClient.close();
      assistantClient = AssistantClient(
        baseUrl: assistantBaseUrl,
        appName: profile.harness.appName,
        userId: profile.harness.userId,
        headers: _gatewayHeadersForProfile(profile),
        logger: logger,
      );
    }
    if (!_memoryClientInjected) {
      memoryClient.close();
      memoryClient = MemoryClient(
        rpc: GatewayContextClient(
          baseUrl: _contextBaseUrl(profile),
          headers: _gatewayHeadersForProfile(profile),
          logger: logger,
        ),
      );
    }
    if (!_tasksClientInjected) {
      tasksClient.close();
      tasksClient = TasksClient(
        rpc: GatewayContextClient(
          baseUrl: _contextBaseUrl(profile),
          headers: _gatewayHeadersForProfile(profile),
          logger: logger,
        ),
      );
    }
    if (!_executiveSummaryClientInjected) {
      executiveSummaryClient.close();
      executiveSummaryClient = ExecutiveSummaryClient(
        rpc: GatewayContextClient(
          baseUrl: _contextBaseUrl(profile),
          headers: _gatewayHeadersForProfile(profile),
          logger: logger,
        ),
      );
    }
  }

  String _contextBaseUrl(RuntimeProfile profile) {
    final gateway = profile.gateway;
    if (gateway != null && gateway.enabled) {
      final uri = Uri.parse(gateway.apiBaseUrl);
      return uri.replace(path: '/api/context', query: null).toString();
    }
    return profile.harness.contextApiBaseUrl;
  }

  Map<String, String> _gatewayHeadersForProfile(RuntimeProfile profile) {
    final gateway = profile.gateway;
    if (gateway == null || !gateway.enabled) {
      return const <String, String>{};
    }
    return config.gatewayAuthHeaders;
  }

  Map<String, String> _mcpHeadersFromEnv(
    RuntimeProfile profile,
    McpServerRuntime server,
  ) {
    final gateway = profile.gateway;
    if (gateway == null ||
        !gateway.enabled ||
        server.endpoint != gateway.mcpUrl) {
      return const <String, String>{};
    }
    return const <String, String>{
      'Authorization': 'AGENTAWESOME_GATEWAY_AUTHORIZATION',
    };
  }
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

Future<RuntimeProfileFileEntry> _profileEntryForPath(String path) async {
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
        active: false,
      );
    }
  } catch (_) {
    // Invalid profile files remain visible by filename so they can be repaired.
  }
  return RuntimeProfileFileEntry(
    path: path,
    id: _profileIdFromPath(path),
    label: _profileIdFromPath(path),
    active: false,
  );
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

/// Returns the config path for one required server kind.
String _requiredServerConfigPath(RuntimeProfile profile, String kind) {
  return switch (kind) {
    'memory' => profile.memoryServerConfigPath,
    _ => '',
  };
}

/// Returns the first profile server for a required kind.
McpServerRuntime? _serverForKind(RuntimeProfile profile, String kind) {
  for (final server in profile.mcpServers) {
    if (server.kind == kind) {
      return server;
    }
  }
  return null;
}

/// Returns a stable filename stem for one required server config.
String _serverFileName(McpServerRuntime? server, String fallback) {
  final id = server?.id.trim() ?? '';
  if (id.isNotEmpty) {
    return _sanitizeConfigFileStem(id);
  }
  return fallback;
}

/// Returns a filesystem-safe config filename stem.
String _sanitizeConfigFileStem(String value) {
  final sanitized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return sanitized.isEmpty ? 'config' : sanitized;
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
