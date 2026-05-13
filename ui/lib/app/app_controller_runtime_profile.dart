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

  /// Saves agent-profile memory access grants.
  Future<void> saveAgentMemoryRuntime(AgentMemoryRuntime agentMemory) async {
    final profile = _activeRuntimeProfile().copyWith(agentMemory: agentMemory);
    await _saveRuntimeProfileAndGeneratedToolConfig(_validatedProfile(profile));
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
    );
    if (next.harness.modelConfigPath != harness.modelConfigPath ||
        next.harness.agentConfigPath != harness.agentConfigPath ||
        next.harness.toolConfigPath != harness.toolConfigPath) {
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
    final target = graphBackedMemoryToolConfigForDomains(
      memoryDomains: graphServers,
      agentMemory: profile.agentMemory,
      localExec: document.localExec,
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

  /// Saves profile JSON after regenerating the domain-aware tool config.
  Future<void> _saveRuntimeProfileAndGeneratedToolConfig(
    RuntimeProfile profile,
  ) async {
    final toolPath = await _writeDefaultGraphToolConfig(
      profile: profile,
      requestedPath: profile.harness.toolConfigPath,
      targetName: _pathFilename(profile.harness.toolConfigPath).isEmpty
          ? '${profile.id}-tool.yaml'
          : _pathFilename(profile.harness.toolConfigPath),
    );
    await saveRuntimeProfile(
      profile.copyWith(
        harness: profile.harness.copyWith(toolConfigPath: toolPath),
      ),
    );
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

  /// Returns the final path segment without importing UI helpers.
  String _pathFilename(String path) {
    return path.replaceAll('\\', '/').split('/').last;
  }

  /// Rebuilds owned service clients from the active runtime profile.
  void _configureClientsForRuntimeProfile(RuntimeProfile profile) {
    if (!_assistantClientInjected) {
      assistantClient.close();
      assistantClient = AssistantClient(
        baseUrl: profile.gateway.apiBaseUrl,
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

  /// Returns the gateway context route used by all UI context clients.
  String _contextBaseUrl(RuntimeProfile profile) {
    final uri = Uri.parse(profile.gateway.apiBaseUrl);
    return uri.replace(path: '/api/context', query: null).toString();
  }

  /// Returns headers needed to call protected gateway routes.
  Map<String, String> _gatewayHeadersForProfile(RuntimeProfile profile) {
    return config.gatewayAuthHeaders;
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
