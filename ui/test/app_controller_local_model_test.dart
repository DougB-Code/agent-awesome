/// Tests local model startup recovery in the app controller.
library;

import 'dart:io';

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/app_settings.dart';
import 'package:agentawesome_ui/app/config_files.dart';
import 'package:agentawesome_ui/app/local_model_runtime.dart';
import 'package:agentawesome_ui/app/local_services.dart';
import 'package:agentawesome_ui/app/process_supervisor.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:agentawesome_ui/domain/local_models.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs controller-level local model recovery tests.
void main() {
  test(
    'startup waits for first-run setup before starting harness services',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agentawesome-controller-first-run-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final configDirectory = Directory('${root.path}/config');
      final modelFile = File('${configDirectory.path}/models/model.yaml');
      await modelFile.parent.create(recursive: true);
      await modelFile.writeAsString('');
      final profileFile = File('${root.path}/profile.json');
      await profileFile.writeAsString(
        encodeRuntimeProfileJson(
          _runtimeProfile(root.path, modelConfigPath: modelFile.path),
        ),
      );
      final processSupervisor = ProcessSupervisor(
        logDirectory: '${root.path}/logs',
        workspaceRoot: root.path,
      );
      final localServices = _TrackingLocalServiceSupervisor(
        config: _testConfig(
          workspaceRoot: root.path,
          runtimeProfilePath: profileFile.path,
          autoStartLocalServices: true,
        ),
        processSupervisor: processSupervisor,
      );
      final controller = AgentAwesomeAppController(
        config: _testConfig(
          workspaceRoot: root.path,
          runtimeProfilePath: profileFile.path,
          autoStartLocalServices: true,
        ),
        appSettingsStore: _MemoryAppSettingsStore(),
        configFiles: ConfigFileStore(configDirectoryPath: configDirectory.path),
        localModels: const _MissingLocalModelRuntime(),
        localServices: localServices,
        processSupervisor: processSupervisor,
      );
      addTearDown(() async {
        await controller.close();
      });

      await controller.initialize();

      expect(controller.shellDecisionReady, isTrue);
      expect(controller.gettingStartedCompleted, isFalse);
      expect(controller.statusMessage, 'Model setup required');
      expect(localServices.startCount, 0);
    },
  );

  test(
    'startup completes setup for externally configured gateway profiles',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agentawesome-controller-external-gateway-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final profileFile = File('${root.path}/profile.json');
      await profileFile.writeAsString(
        encodeRuntimeProfileJson(
          _runtimeProfile(
            root.path,
            modelConfigPath: '${root.path}/external-model.yaml',
            externalGatewayModel: true,
          ),
        ),
      );
      final settingsStore = _MemoryAppSettingsStore();
      final processSupervisor = ProcessSupervisor(
        logDirectory: '${root.path}/logs',
        workspaceRoot: root.path,
      );
      final localServices = _TrackingLocalServiceSupervisor(
        config: _testConfig(
          workspaceRoot: root.path,
          runtimeProfilePath: profileFile.path,
        ),
        processSupervisor: processSupervisor,
      );
      final controller = AgentAwesomeAppController(
        config: _testConfig(
          workspaceRoot: root.path,
          runtimeProfilePath: profileFile.path,
        ),
        appSettingsStore: settingsStore,
        localModels: const _MissingLocalModelRuntime(),
        localServices: localServices,
        processSupervisor: processSupervisor,
      );
      addTearDown(() async {
        await controller.close();
      });

      await controller.initialize();

      expect(controller.gettingStartedCompleted, isTrue);
      expect(settingsStore.saved.gettingStartedCompleted, isTrue);
      expect(controller.hasConfiguredModel, isTrue);
      expect(controller.statusMessage, isNot('Model setup required'));
      expect(localServices.startCount, 1);
    },
  );

  test(
    'startup completes setup when the managed local model verifies',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agentawesome-controller-local-model-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final configDirectory = Directory('${root.path}/config');
      final modelFile = File('${configDirectory.path}/models/model.yaml');
      await modelFile.parent.create(recursive: true);
      await modelFile.writeAsString('');
      final profileFile = File('${root.path}/profile.json');
      await profileFile.writeAsString(
        encodeRuntimeProfileJson(
          _runtimeProfile(root.path, modelConfigPath: modelFile.path),
        ),
      );
      final settingsStore = _MemoryAppSettingsStore();
      final controller = AgentAwesomeAppController(
        config: _testConfig(
          workspaceRoot: root.path,
          runtimeProfilePath: profileFile.path,
          litertLmExecutable: Platform.resolvedExecutable,
        ),
        appSettingsStore: settingsStore,
        configFiles: ConfigFileStore(configDirectoryPath: configDirectory.path),
        localModels: _RecoveringLocalModelRuntime(root.path),
      );
      addTearDown(() async {
        await controller.close();
      });

      await controller.initialize();

      expect(controller.gettingStartedCompleted, isTrue);
      expect(settingsStore.saved.gettingStartedCompleted, isTrue);
      expect(controller.hasConfiguredModel, isTrue);
      final modelConfig = await modelFile.readAsString();
      expect(modelConfig, contains('default: litert-lm:gemma-4-e2b-it'));
      expect(modelConfig, contains('name: LiteRT-LM'));
      expect(modelConfig, contains('adapter: openai'));
      expect(modelConfig, contains('auth: optional'));
      expect(modelConfig, contains('runtime: litert-lm'));
      expect(
        modelConfig,
        contains('url: http://127.0.0.1:11666/v1/chat/completions'),
      );
      expect(modelConfig, contains('gemma-4-e2b-it'));
    },
  );

  test(
    'local model setup validates runtime profile before installing',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agentawesome-controller-local-model-preflight-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final localModels = _CountingLocalModelRuntime();
      final controller = AgentAwesomeAppController(
        config: _testConfig(workspaceRoot: root.path, runtimeProfilePath: ''),
        localModels: localModels,
      );
      addTearDown(() async {
        await controller.close();
      });

      final result = await controller.configureOnboardingLocalModel(
        modelId: 'gemma-4-e2b-it',
      );

      expect(result.success, isFalse);
      expect(result.message, 'Runtime profile is not loaded');
      expect(localModels.installAttempts, 0);
      expect(localModels.runtimeInstallAttempts, 0);
    },
  );

  test('startup keeps setup complete when LiteRT-LM cannot start', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-controller-local-model-bad-runtime-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final configDirectory = Directory('${root.path}/config');
    final modelFile = File('${configDirectory.path}/models/model.yaml');
    await modelFile.parent.create(recursive: true);
    await modelFile.writeAsString('''
default: litert-lm:gemma-4-e2b-it
providers:
  litert-lm:
    name: LiteRT-LM
    adapter: openai
    auth: optional
    runtime: litert-lm
    url: http://127.0.0.1:11666/v1/chat/completions
    default: gemma-4-e2b-it
    executable: missing-litert-lm
    models:
      - id: gemma-4-e2b-it
        model: gemma-4-E2B-it
        path: ${root.path}/data/models/litert-lm/gemma-4-e2b-it/gemma-4-E2B-it.litertlm
''');
    final profileFile = File('${root.path}/profile.json');
    await profileFile.writeAsString(
      encodeRuntimeProfileJson(
        _runtimeProfile(root.path, modelConfigPath: modelFile.path),
      ),
    );
    final settingsStore = _MemoryAppSettingsStore(
      saved: const AgentAwesomeAppSettings(gettingStartedCompleted: true),
    );
    final controller = AgentAwesomeAppController(
      config: _testConfig(
        workspaceRoot: root.path,
        runtimeProfilePath: profileFile.path,
        litertLmExecutable: Platform.resolvedExecutable,
      ),
      appSettingsStore: settingsStore,
      configFiles: ConfigFileStore(configDirectoryPath: configDirectory.path),
      localModels: _RecoveringLocalModelRuntime(
        root.path,
        startConnected: false,
      ),
    );
    addTearDown(() async {
      await controller.close();
    });

    await controller.initialize();

    expect(controller.shellDecisionReady, isTrue);
    expect(controller.gettingStartedCompleted, isTrue);
    expect(settingsStore.saved.gettingStartedCompleted, isTrue);
    expect(
      controller.localProcessStatuses.any(
        (status) =>
            status.name == 'LiteRT-LM' &&
            status.state == ConnectionStateKind.disconnected &&
            status.message.contains('Executable unavailable'),
      ),
      isTrue,
    );
    expect(await controller.createChat(), isFalse);
    expect(controller.messages, isNotEmpty);
    expect(controller.messages.last.text, contains('local model'));
    final repairedConfig = await modelFile.readAsString();
    expect(repairedConfig, contains('default: litert-lm:gemma-4-e2b-it'));
    expect(repairedConfig, contains('name: LiteRT-LM'));
    expect(repairedConfig, contains('adapter: openai'));
    expect(repairedConfig, contains('auth: optional'));
    expect(repairedConfig, contains('runtime: litert-lm'));
    expect(
      repairedConfig,
      contains('executable: ${Platform.resolvedExecutable}'),
    );
    expect(repairedConfig, isNot(contains('adapter: litert')));
    expect(repairedConfig, isNot(contains('name: Local model')));
  });

  test('local model setup writes llama.cpp provider config', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-controller-llama-model-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final configDirectory = Directory('${root.path}/config');
    final modelFile = File('${configDirectory.path}/models/model.yaml');
    await modelFile.parent.create(recursive: true);
    await modelFile.writeAsString('');
    final profileFile = File('${root.path}/profile.json');
    await profileFile.writeAsString(
      encodeRuntimeProfileJson(
        _runtimeProfile(root.path, modelConfigPath: modelFile.path),
      ),
    );
    final localModels = _SetupLocalModelRuntime(root.path);
    final controller = AgentAwesomeAppController(
      config: _testConfig(
        workspaceRoot: root.path,
        runtimeProfilePath: profileFile.path,
        llamaCppExecutable: Platform.resolvedExecutable,
      ),
      appSettingsStore: _MemoryAppSettingsStore(),
      configFiles: ConfigFileStore(configDirectoryPath: configDirectory.path),
      localModels: localModels,
    );
    addTearDown(() async {
      await controller.close();
    });

    await controller.initialize();
    final result = await controller.configureOnboardingLocalModel(
      modelId: 'llama-gemma-4-e2b-it-q8',
    );

    expect(result.success, isTrue);
    expect(result.providerName, 'Llama.cpp');
    expect(
      localModels.runtimeModel?.runtimeKind,
      LocalModelRuntimeKind.llamaCpp,
    );
    final modelConfig = await modelFile.readAsString();
    expect(modelConfig, contains('default: llama-cpp:llama-gemma-4-e2b-it-q8'));
    expect(modelConfig, contains('name: Llama.cpp'));
    expect(modelConfig, contains('adapter: openai'));
    expect(modelConfig, contains('auth: optional'));
    expect(modelConfig, contains('runtime: llama-cpp'));
    expect(modelConfig, contains('hf-repo: ggml-org/gemma-4-E2B-it-GGUF:Q8_0'));
    expect(
      modelConfig,
      contains('url: http://127.0.0.1:11667/v1/chat/completions'),
    );
  });
}

class _MemoryAppSettingsStore extends AgentAwesomeAppSettingsStore {
  _MemoryAppSettingsStore({this.saved = const AgentAwesomeAppSettings()});

  AgentAwesomeAppSettings saved;

  /// Loads the latest in-memory app settings.
  @override
  Future<AgentAwesomeAppSettings> load() async {
    return saved;
  }

  /// Saves app settings in memory for assertions.
  @override
  Future<void> save(
    AgentAwesomeAppSettings settings, {
    Iterable<String> extraPolicyActors = const <String>[],
  }) async {
    saved = settings;
  }
}

class _RecoveringLocalModelRuntime implements LocalModelRuntime {
  const _RecoveringLocalModelRuntime(this.root, {this.startConnected = true});

  final String root;
  final bool startConnected;

  /// Closes no resources because the fake starts no process.
  @override
  Future<void> close() async {}

  /// Returns a synthetic install for setup fallback paths.
  @override
  Future<LocalModelInstall> ensureInstalled(
    LocalModelDescriptor model, {
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    return _installFor(model);
  }

  /// Reports the synthetic model as installed after recovery.
  @override
  Future<bool> isInstalled(LocalModelDescriptor model) async {
    return true;
  }

  /// Returns a synthetic executable for local setup configuration.
  @override
  Future<String> ensureRuntimeInstalled({
    LocalModelDescriptor? model,
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    return Platform.resolvedExecutable;
  }

  /// Returns a synthetic recovered install.
  @override
  Future<LocalModelInstall?> recoverInstalled(
    LocalModelDescriptor model, {
    List<String> candidatePaths = const <String>[],
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    return _installFor(model);
  }

  /// Reports a connected local model without launching a process.
  @override
  Future<ServiceProcessStatus> start(LocalModelDescriptor model) async {
    return ServiceProcessStatus(
      name: model.providerName,
      url: model.runtimeKind == LocalModelRuntimeKind.llamaCpp
          ? 'http://127.0.0.1:11667/health'
          : 'http://127.0.0.1:11666/health',
      state: startConnected
          ? ConnectionStateKind.connected
          : ConnectionStateKind.disconnected,
      message: startConnected ? 'Started locally' : 'Executable unavailable',
    );
  }

  LocalModelInstall _installFor(LocalModelDescriptor model) {
    final runtimeDirectory = model.runtimeKind == LocalModelRuntimeKind.llamaCpp
        ? 'llama-cpp'
        : 'litert-lm';
    final directory = '$root/data/models/$runtimeDirectory/${model.id}';
    return LocalModelInstall(
      model: model,
      directory: directory,
      modelPath: '$directory/${model.fileName}',
      manifestPath: '$directory/manifest.json',
    );
  }
}

class _MissingLocalModelRuntime implements LocalModelRuntime {
  const _MissingLocalModelRuntime();

  /// Closes no resources because the fake starts no process.
  @override
  Future<void> close() async {}

  /// Returns no install because this fake models a fresh user machine.
  @override
  Future<LocalModelInstall> ensureInstalled(
    LocalModelDescriptor model, {
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) {
    throw UnimplementedError('install should not run during startup');
  }

  /// Reports that no local model is currently installed.
  @override
  Future<bool> isInstalled(LocalModelDescriptor model) async {
    return false;
  }

  /// Returns no runtime because setup has not selected local models.
  @override
  Future<String> ensureRuntimeInstalled({
    LocalModelDescriptor? model,
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) {
    throw UnimplementedError('runtime install should not run during startup');
  }

  /// Finds no recovered install on a fresh machine.
  @override
  Future<LocalModelInstall?> recoverInstalled(
    LocalModelDescriptor model, {
    List<String> candidatePaths = const <String>[],
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    return null;
  }

  /// Does not start because no local model exists.
  @override
  Future<ServiceProcessStatus> start(LocalModelDescriptor model) {
    throw UnimplementedError('local model should not start before setup');
  }
}

class _CountingLocalModelRuntime implements LocalModelRuntime {
  /// Number of model install attempts.
  int installAttempts = 0;

  /// Number of runtime executable install attempts.
  int runtimeInstallAttempts = 0;

  /// Closes no resources because this fake never starts a process.
  @override
  Future<void> close() async {}

  /// Records unexpected install attempts.
  @override
  Future<LocalModelInstall> ensureInstalled(
    LocalModelDescriptor model, {
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    installAttempts++;
    return _installFor(model);
  }

  /// Reports no installed model.
  @override
  Future<bool> isInstalled(LocalModelDescriptor model) async {
    return false;
  }

  /// Records unexpected runtime install attempts.
  @override
  Future<String> ensureRuntimeInstalled({
    LocalModelDescriptor? model,
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    runtimeInstallAttempts++;
    return Platform.resolvedExecutable;
  }

  /// Returns no recovered model.
  @override
  Future<LocalModelInstall?> recoverInstalled(
    LocalModelDescriptor model, {
    List<String> candidatePaths = const <String>[],
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    return null;
  }

  /// Does not start because the setup preflight should fail first.
  @override
  Future<ServiceProcessStatus> start(LocalModelDescriptor model) {
    throw UnimplementedError('local model should not start before setup');
  }

  LocalModelInstall _installFor(LocalModelDescriptor model) {
    return LocalModelInstall(
      model: model,
      directory: '/tmp/${model.id}',
      modelPath: '/tmp/${model.id}/${model.fileName}',
      manifestPath: '/tmp/${model.id}/manifest.json',
    );
  }
}

class _SetupLocalModelRuntime implements LocalModelRuntime {
  _SetupLocalModelRuntime(this.root);

  final String root;
  LocalModelDescriptor? runtimeModel;

  /// Closes no resources because the fake starts no process.
  @override
  Future<void> close() async {}

  /// Returns a synthetic install for the selected setup model.
  @override
  Future<LocalModelInstall> ensureInstalled(
    LocalModelDescriptor model, {
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    return _installFor(model);
  }

  /// Reports no installed model before setup writes the config.
  @override
  Future<bool> isInstalled(LocalModelDescriptor model) async {
    return false;
  }

  /// Records which runtime setup requested.
  @override
  Future<String> ensureRuntimeInstalled({
    LocalModelDescriptor? model,
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    runtimeModel = model;
    return Platform.resolvedExecutable;
  }

  /// Returns no recovered model so setup exercises ensureInstalled.
  @override
  Future<LocalModelInstall?> recoverInstalled(
    LocalModelDescriptor model, {
    List<String> candidatePaths = const <String>[],
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    return null;
  }

  /// Does not start because setup only writes configuration.
  @override
  Future<ServiceProcessStatus> start(LocalModelDescriptor model) {
    throw UnimplementedError('local model should not start during setup');
  }

  LocalModelInstall _installFor(LocalModelDescriptor model) {
    final runtimeDirectory = model.runtimeKind == LocalModelRuntimeKind.llamaCpp
        ? 'llama-cpp'
        : 'litert-lm';
    final directory = '$root/data/models/$runtimeDirectory/${model.id}';
    return LocalModelInstall(
      model: model,
      directory: directory,
      modelPath: '$directory/${model.fileName}',
      manifestPath: '$directory/manifest.json',
    );
  }
}

class _TrackingLocalServiceSupervisor extends LocalServiceSupervisor {
  /// Creates a local service supervisor that records startup requests.
  _TrackingLocalServiceSupervisor({
    required super.config,
    required super.processSupervisor,
  });

  /// Number of service startup requests.
  int startCount = 0;

  /// Records startup requests without launching subprocesses.
  @override
  Future<List<ServiceProcessStatus>> startRequiredServices(
    RuntimeProfile profile, {
    bool restartAutoStarted = false,
  }) async {
    startCount++;
    return const <ServiceProcessStatus>[];
  }
}

RuntimeProfile _runtimeProfile(
  String root, {
  required String modelConfigPath,
  bool externalGatewayModel = false,
}) {
  return RuntimeProfile(
    id: 'personal',
    label: 'Personal',
    harness: HarnessRuntime(
      id: 'harness',
      label: 'Local Harness',
      apiBaseUrl: 'http://127.0.0.1:1/api',
      contextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
      appName: 'test',
      userId: 'user',
      workingDirectory: '$root/harness',
      packagePath: './cmd/agent-awesome',
      modelConfigPath: modelConfigPath,
      agentConfigPath: '$root/agent.yaml',
      toolConfigPath: '$root/tool.yaml',
      port: 1,
      autoStart: false,
    ),
    gateway: GatewayRuntime(
      id: 'gateway',
      label: 'Gateway',
      apiBaseUrl: 'http://127.0.0.1:2/api',
      healthUrl: 'http://127.0.0.1:2/healthz',
      workingDirectory: '$root/gateway',
      packagePath: './cmd/agent-gateway',
      harnessBaseUrl: 'http://127.0.0.1:1/api',
      contextBaseUrl: 'http://127.0.0.1:8081/api/context',
      memoryMcpUrl: 'http://127.0.0.1:1/mcp',
      appName: 'test',
      userId: 'user',
      profileId: externalGatewayModel ? 'personal' : '',
      modelProviderId: externalGatewayModel ? 'openai' : '',
      modelId: externalGatewayModel ? 'gpt-5.4-mini' : '',
      port: 2,
      autoStart: false,
      enabled: true,
    ),
    memoryDomains: <McpServerRuntime>[_memoryServer(root)],
    agentMemory: const AgentMemoryRuntime(
      actor: 'agent:test',
      readDomains: <String>['memory'],
      writeDomains: <String>['memory'],
      defaultWriteDomain: 'memory',
      allowedSensitivities: <String>['public', 'internal', 'private'],
    ),
  );
}

McpServerRuntime _memoryServer(String root) {
  return McpServerRuntime(
    id: 'memory',
    label: 'Memory',
    kind: 'memory',
    endpoint: 'http://127.0.0.1:1/mcp',
    healthUrl: 'http://127.0.0.1:1/healthz',
    workingDirectory: '$root/memory',
    packagePath: './cmd/memoryd',
    dbPath: '$root/memory.db',
    dataDir: '$root/memory-files',
    arguments: const <String>[],
    autoStart: false,
    enabled: true,
  );
}

AppConfig _testConfig({
  required String workspaceRoot,
  required String runtimeProfilePath,
  String litertLmExecutable = 'litert-lm',
  String llamaCppExecutable = 'llama-server',
  bool autoStartLocalServices = false,
}) {
  return AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:1/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:2/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:1/mcp',
    agentAppName: 'test',
    agentUserId: 'user',
    workspaceRoot: workspaceRoot,
    autoStartLocalServices: autoStartLocalServices,
    runtimeProfilePath: runtimeProfilePath,
    litertLmExecutable: litertLmExecutable,
    llamaCppExecutable: llamaCppExecutable,
  );
}
