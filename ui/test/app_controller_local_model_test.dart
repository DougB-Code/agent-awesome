/// Tests local model startup recovery in the app controller.
library;

import 'dart:io';

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/app_settings.dart';
import 'package:agentawesome_ui/app/config_files.dart';
import 'package:agentawesome_ui/app/local_model_runtime.dart';
import 'package:agentawesome_ui/app/local_services.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:agentawesome_ui/domain/local_models.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs controller-level local model recovery tests.
void main() {
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
      final memoryFile = File('${root.path}/memory.json');
      await memoryFile.writeAsString(
        encodeMcpServerRuntimeJson(_memoryServer(root.path)),
      );
      final profileFile = File('${root.path}/profile.json');
      await profileFile.writeAsString(
        encodeRuntimeProfileJson(
          _runtimeProfile(
            root.path,
            modelConfigPath: modelFile.path,
            memoryConfigPath: memoryFile.path,
          ),
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
      expect(modelConfig, contains('local'));
      expect(modelConfig, contains('gemma-4-e2b-it'));
    },
  );

  test(
    'startup reopens setup when restored local model cannot start',
    () async {
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
default: local:gemma-4-e2b-it
providers:
  local:
    name: Local model
    adapter: litert
    default: gemma-4-e2b-it
    executable: missing-litert-lm
    models:
      - id: gemma-4-e2b-it
        model: gemma-4-E2B-it
        path: ${root.path}/data/models/litert-lm/gemma-4-e2b-it/gemma-4-E2B-it.litertlm
''');
      final memoryFile = File('${root.path}/memory.json');
      await memoryFile.writeAsString(
        encodeMcpServerRuntimeJson(_memoryServer(root.path)),
      );
      final profileFile = File('${root.path}/profile.json');
      await profileFile.writeAsString(
        encodeRuntimeProfileJson(
          _runtimeProfile(
            root.path,
            modelConfigPath: modelFile.path,
            memoryConfigPath: memoryFile.path,
          ),
        ),
      );
      final settingsStore = _MemoryAppSettingsStore(
        saved: const AgentAwesomeAppSettings(gettingStartedCompleted: true),
      );
      final controller = AgentAwesomeAppController(
        config: _testConfig(
          workspaceRoot: root.path,
          runtimeProfilePath: profileFile.path,
          litertLmExecutable: 'missing-litert-lm',
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
      expect(controller.gettingStartedCompleted, isFalse);
      expect(settingsStore.saved.gettingStartedCompleted, isFalse);
      expect(
        controller.localProcessStatuses.any(
          (status) =>
              status.name == 'Local model' &&
              status.state == ConnectionStateKind.disconnected,
        ),
        isTrue,
      );
      expect(await controller.createChat(), isFalse);
      expect(controller.messages, isNotEmpty);
      expect(controller.messages.last.text, contains('local model'));
    },
  );
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
  Future<void> save(AgentAwesomeAppSettings settings) async {
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
      name: 'Local model',
      url: 'http://127.0.0.1:11666/health',
      state: startConnected
          ? ConnectionStateKind.connected
          : ConnectionStateKind.disconnected,
      message: startConnected ? 'Started locally' : 'Executable unavailable',
    );
  }

  LocalModelInstall _installFor(LocalModelDescriptor model) {
    final directory = '$root/data/models/litert-lm/${model.id}';
    return LocalModelInstall(
      model: model,
      directory: directory,
      modelPath: '$directory/${model.fileName}',
      manifestPath: '$directory/manifest.json',
    );
  }
}

RuntimeProfile _runtimeProfile(
  String root, {
  required String modelConfigPath,
  required String memoryConfigPath,
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
    memoryServerConfigPath: memoryConfigPath,
    mcpServers: <McpServerRuntime>[_memoryServer(root)],
  );
}

McpServerRuntime _memoryServer(String root) {
  return McpServerRuntime(
    id: 'memory',
    label: 'Personal Memory',
    kind: 'memory',
    endpoint: 'http://127.0.0.1:1/mcp',
    healthUrl: 'http://127.0.0.1:1/healthz',
    workingDirectory: '$root/memory',
    packagePath: './cmd/memoryd',
    arguments: const <String>[],
    autoStart: false,
    enabled: true,
  );
}

AppConfig _testConfig({
  required String workspaceRoot,
  required String runtimeProfilePath,
  String litertLmExecutable = 'litert-lm',
}) {
  return AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:1/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:2/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:1/mcp',
    agentAppName: 'test',
    agentUserId: 'user',
    workspaceRoot: workspaceRoot,
    autoStartLocalServices: false,
    runtimeProfilePath: runtimeProfilePath,
    litertLmExecutable: litertLmExecutable,
  );
}
