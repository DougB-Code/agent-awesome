/// Tests remote Docker runtime bundle generation.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/process_supervisor.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:agentawesome_ui/domain/automation_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs remote runtime bundle tests.
void main() {
  test('exports active runtime configuration into a Docker bundle', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-remote-bundle-',
    );
    addTearDown(() => root.delete(recursive: true));
    await _writeBundleFixture(root);

    final controller = AgentAwesomeAppController(config: _testConfig(root));
    addTearDown(controller.close);
    controller.runtimeProfile = _testProfile(root);

    final bundle = await controller.exportRemoteDockerBundle(
      imageTag: 'agent-awesome/remote-runtime:test',
      gatewayBaseUrl: 'https://agent.example.com/api',
    );

    expect(bundle.rootPath, '${root.path}/build/remote-runtime/personal');
    expect(await File('${bundle.rootPath}/config/agent.yaml').exists(), isTrue);
    expect(await File('${bundle.rootPath}/config/tool.yaml').exists(), isTrue);
    expect(await File('${bundle.rootPath}/config/model.yaml').exists(), isTrue);
    expect(
      await File('${bundle.rootPath}/config/runbooks/demo.yaml').exists(),
      isTrue,
    );
    final dockerfile = await File(bundle.dockerfilePath).readAsString();
    expect(
      dockerfile,
      contains('COPY build/remote-runtime/personal/config/agent.yaml'),
    );
    expect(bundle.buildCommand, <String>[
      'docker',
      'build',
      '-f',
      bundle.dockerfilePath,
      '-t',
      'agent-awesome/remote-runtime:test',
      root.path,
    ]);
    expect(
      bundle.runCommand,
      contains('AA_GATEWAY_PUBLIC_BASE_URL=https://agent.example.com/api'),
    );
    expect(bundle.runCommand, contains('AA_PROFILE_ID=personal'));
    expect(bundle.runCommand, contains('AA_APP_NAME=Agent Awesome'));
    expect(bundle.runCommand, contains('AA_USER_ID=doug'));

    final profileJson =
        jsonDecode(await File(bundle.runtimeProfilePath).readAsString())
            as Map<String, dynamic>;
    final remote = RuntimeProfile.fromJson(profileJson);
    expect(remote.gateway.apiBaseUrl, 'https://agent.example.com/api');
    expect(remote.gateway.profileId, 'personal');
    expect(remote.gateway.authCredential, 'AGENTAWESOME_GATEWAY_TOKEN');
    expect(
      remote.memoryServers.single.endpoint,
      'https://agent.example.com/mcp/memory',
    );
    expect(controller.statusMessage, 'Remote Docker bundle ready');
  });

  test('exports local model mount and remote deploy script', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-remote-model-bundle-',
    );
    addTearDown(() => root.delete(recursive: true));
    await _writeBundleFixture(root);

    final controller = AgentAwesomeAppController(config: _testConfig(root));
    addTearDown(controller.close);
    controller.runtimeProfile = _testProfile(root);

    final localModelPath = await controller.activeLocalModelArtifactPath();
    expect(localModelPath, '${root.path}/models/gemma.gguf');
    final localModelServerExecutablePath = await controller
        .activeLocalLlamaServerExecutablePath();
    expect(localModelServerExecutablePath, '${root.path}/bin/llama-server');

    final bundle = await controller.exportRemoteDockerBundle(
      imageTag: 'agent-awesome/remote-runtime:model',
      gatewayBaseUrl: 'https://agent.example.com/api',
      localModelPath: localModelPath,
      localModelServerExecutablePath: localModelServerExecutablePath,
    );

    expect(bundle.localModelPath, localModelPath);
    expect(bundle.remoteModelPath, '/models/gemma.gguf');
    expect(
      bundle.localModelServerExecutablePath,
      localModelServerExecutablePath,
    );
    expect(
      bundle.remoteModelServerExecutablePath,
      '/opt/agent-awesome/bin/llama-server',
    );
    expect(
      bundle.runCommand,
      contains('AA_LOCAL_MODEL_PATH=/models/gemma.gguf'),
    );
    expect(
      bundle.runCommand,
      contains('AA_LLAMA_SERVER=/opt/agent-awesome/bin/llama-server'),
    );
    expect(bundle.runCommand, contains('${root.path}/models:/models:ro'));
    final dockerfile = await File(bundle.dockerfilePath).readAsString();
    expect(
      dockerfile,
      contains('COPY build/remote-runtime/personal/config/bin'),
    );
    expect(dockerfile, contains('find /opt/agent-awesome/bin -type f'));

    final deployScript = await File(
      bundle.remoteDeployScriptPath,
    ).readAsString();
    expect(deployScript, contains('docker save'));
    expect(deployScript, contains('scp'));
    expect(deployScript, contains('/srv/agent-awesome/models:/models:ro'));
    expect(deployScript, contains('agent-awesome/remote-runtime:model'));
  });

  test('configures UI clients through remote gateway profile', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-remote-clients-',
    );
    addTearDown(() => root.delete(recursive: true));
    await _writeBundleFixture(root);

    final controller = AgentAwesomeAppController(
      config: _testConfig(
        root,
        gatewayAuthorizationHeader: 'Bearer direct-token',
        runtimeProfilePath: '${root.path}/runtime-profile.json',
      ),
    );
    addTearDown(controller.close);
    final localProfile = _testProfile(root);
    final remoteProfile = localProfile.copyWith(
      gateway: localProfile.gateway.copyWith(
        apiBaseUrl: 'https://agent.example.com/api',
        profileId: 'personal',
        authCredential: 'AGENTAWESOME_GATEWAY_TOKEN',
      ),
    );

    await controller.saveRuntimeProfile(remoteProfile);

    expect(controller.assistantClient.baseUrl, 'https://agent.example.com/api');
    expect(controller.assistantClient.appName, 'Agent Awesome');
    expect(controller.assistantClient.userId, 'doug');
    expect(
      controller.assistantClient.headers['Authorization'],
      'Bearer direct-token',
    );
    expect(
      controller.assistantClient.headers['X-Agent-Awesome-Profile'],
      'personal',
    );
    expect(
      controller.memoryClient.endpoint,
      'https://agent.example.com/api/context',
    );
    expect(
      controller.automationsClient.baseUrl,
      'https://agent.example.com/api/runbooks',
    );
    expect(
      controller.automationsClient.headers['X-Agent-Awesome-Profile'],
      'personal',
    );
  });

  test('uses gateway runbook API for remote-profile draft authoring', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-remote-draft-api-',
    );
    addTearDown(() => root.delete(recursive: true));
    await _writeBundleFixture(root);
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    final requests = <String>[];
    final draft = <String, dynamic>{
      'id': 'draft_remote',
      'kind': automationRunbookKind,
      'name': 'Remote Draft',
      'description': '',
      'status': 'draft',
      'body': <String, dynamic>{
        'apiVersion': automationRunbookApiVersion,
        'kind': 'state_machine',
        'id': 'remote_draft',
        'states': const <Object>[],
      },
      'validation': <String, dynamic>{},
    };
    server.listen((request) async {
      requests.add(
        '${request.method} ${request.uri.path} '
        '${request.headers.value('X-Agent-Awesome-Profile') ?? ''}',
      );
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'POST' &&
          request.uri.path == '/api/runbooks/drafts') {
        request.response.write(jsonEncode(<String, dynamic>{'draft': draft}));
      } else if (request.method == 'GET' &&
          request.uri.path == '/api/runbooks/drafts') {
        request.response.write(
          jsonEncode(<String, dynamic>{
            'drafts': [draft],
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode(<String, dynamic>{'error': 'nope'}));
      }
      await request.response.close();
    });
    final gatewayBaseUrl = 'http://127.0.0.1:${server.port}/api';
    final controller = AgentAwesomeAppController(
      config: _testConfig(
        root,
        gatewayAuthorizationHeader: 'Bearer direct-token',
        runtimeProfilePath: '${root.path}/runtime-profile.json',
      ),
    );
    addTearDown(controller.close);
    final localProfile = _testProfile(root);
    final remoteProfile = localProfile.copyWith(
      gateway: localProfile.gateway.copyWith(
        apiBaseUrl: gatewayBaseUrl,
        profileId: 'personal',
      ),
      runbook: localProfile.runbook.copyWith(
        apiBaseUrl: '$gatewayBaseUrl/runbooks',
        workingDirectory: '',
        executablePath: '',
        definitionsDir: '',
        dbPath: '',
        autoStart: false,
        enabled: true,
      ),
    );
    await controller.saveRuntimeProfile(remoteProfile);

    await controller.createAutomationDraftFromUi(
      kind: automationRunbookKind,
      name: 'Remote Draft',
    );

    expect(controller.automationDrafts.single.id, 'draft_remote');
    expect(
      requests,
      containsAll(<String>[
        'POST /api/runbooks/drafts personal',
        'GET /api/runbooks/drafts personal',
      ]),
    );
    expect(
      await Directory('${root.path}/config/agents/personal/runbooks').exists(),
      isFalse,
    );
  });

  test(
    'builds and starts generated Docker bundle through supervisor',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agentawesome-remote-docker-run-',
      );
      addTearDown(() => root.delete(recursive: true));
      await _writeBundleFixture(root);
      final processSupervisor = ProcessSupervisor(
        logDirectory: '${root.path}/logs',
        workspaceRoot: root.path,
      );
      addTearDown(processSupervisor.close);
      final controller = AgentAwesomeAppController(
        config: _testConfig(root),
        processSupervisor: processSupervisor,
      );
      addTearDown(controller.close);
      controller.runtimeProfile = _testProfile(root);
      final bundle = await controller.exportRemoteDockerBundle(
        imageTag: 'agent-awesome/remote-runtime:test',
        gatewayBaseUrl: 'https://agent.example.com/api',
      );
      final buildArgs = File('${root.path}/build-args.txt');
      final runArgs = File('${root.path}/run-args.txt');
      final buildDocker = await _script(root, 'docker-build.sh', '''
#!/bin/sh
printf '%s\\n' "\$@" > "${buildArgs.path}"
exit 0
''');
      final runDocker = await _script(root, 'docker-run.sh', '''
#!/bin/sh
printf '%s\\n' "\$@" > "${runArgs.path}"
sleep 30
''');

      final result = await controller.buildRemoteDockerBundleImage(
        bundle,
        dockerExecutable: buildDocker.path,
      );
      expect(result.exitCode, 0);
      expect(await buildArgs.readAsString(), contains('build\n-f\n'));
      expect(controller.statusMessage, 'Remote Docker image built');

      final handle = await controller.startRemoteDockerBundleContainer(
        bundle,
        dockerExecutable: runDocker.path,
        gatewayToken: 'verify-token',
      );
      addTearDown(() => processSupervisor.stop(handle));

      expect(await _waitForFile(runArgs), isTrue);
      final args = await runArgs.readAsString();
      expect(args, contains('run\n--rm\n'));
      expect(args, contains('AGENTAWESOME_GATEWAY_TOKEN=verify-token'));
      expect(args, contains('AA_PROFILE_ID=personal'));
      expect(controller.statusMessage, 'Remote Docker runtime started');
    },
  );

  test('deploys generated bundle through supervisor script boundary', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-remote-deploy-',
    );
    addTearDown(() => root.delete(recursive: true));
    await _writeBundleFixture(root);
    final processSupervisor = ProcessSupervisor(
      logDirectory: '${root.path}/logs',
      workspaceRoot: root.path,
    );
    addTearDown(processSupervisor.close);
    final controller = AgentAwesomeAppController(
      config: _testConfig(root),
      processSupervisor: processSupervisor,
    );
    addTearDown(controller.close);
    controller.runtimeProfile = _testProfile(root);
    final bundle = await controller.exportRemoteDockerBundle(
      imageTag: 'agent-awesome/remote-runtime:deploy',
      gatewayBaseUrl: 'https://agent.example.com/api',
    );
    final deployArgs = File('${root.path}/deploy-args.txt');
    final fakeBash = await _script(root, 'bash.sh', '''
#!/bin/sh
printf '%s\\n' "\$AA_REMOTE_HOST" "\$AGENTAWESOME_GATEWAY_TOKEN" "\$@" > "${deployArgs.path}"
exit 0
''');

    final result = await controller.deployRemoteDockerBundle(
      bundle,
      remoteHost: 'deploy@example.com',
      gatewayToken: 'deploy-token',
      bashExecutable: fakeBash.path,
    );

    expect(result.exitCode, 0);
    final args = await deployArgs.readAsString();
    expect(args, contains('deploy@example.com'));
    expect(args, contains('deploy-token'));
    expect(args, contains(bundle.remoteDeployScriptPath));
    expect(controller.statusMessage, 'Remote Docker runtime deployed');
  });
}

/// Writes minimal source config files for one remote bundle test.
Future<void> _writeBundleFixture(Directory root) async {
  await File('${root.path}/harness/agent.yaml').create(recursive: true);
  await File('${root.path}/harness/agent.yaml').writeAsString('''
name: personal_agent
description: Personal agent.
instruction: Help with configured work.
''');
  await File('${root.path}/harness/tool.yaml').writeAsString('''
name: Test Tools
mcp:
  enabled: true
  servers:
    - name: memory
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
''');
  await File('${root.path}/models/gemma.gguf').create(recursive: true);
  await File('${root.path}/models/gemma.gguf').writeAsString('model');
  await File('${root.path}/bin/llama-server').create(recursive: true);
  await File('${root.path}/bin/llama-server').writeAsString('#!/bin/sh\n');
  await Process.run('chmod', <String>['+x', '${root.path}/bin/llama-server']);
  await File('${root.path}/harness/model.yaml').writeAsString('''
default: llama-cpp:llama-gemma-4-e2b-it-q8
providers:
  llama-cpp:
    adapter: openai
    auth: optional
    default: llama-gemma-4-e2b-it-q8
    url: http://127.0.0.1:11667/v1/chat/completions
    executable: ${root.path}/bin/llama-server
    runtime: llama-cpp
    models:
      - id: llama-gemma-4-e2b-it-q8
        model: bartowski/google_gemma-3-4b-it-GGUF
        path: ${root.path}/models/gemma.gguf
''');
  await File('${root.path}/runbooks/demo.yaml').create(recursive: true);
  await File('${root.path}/runbooks/demo.yaml').writeAsString('''
id: demo
name: Demo
states: []
''');
  await File(
    '${root.path}/deploy/docker/config/model.local-gemma.yaml',
  ).create(recursive: true);
  await File(
    '${root.path}/deploy/docker/config/model.local-gemma.yaml',
  ).writeAsString('''
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
''');
}

/// Writes an executable shell script in the temporary workspace.
Future<File> _script(Directory root, String name, String content) async {
  final file = File('${root.path}/$name');
  await file.writeAsString(content);
  await Process.run('chmod', <String>['+x', file.path]);
  return file;
}

/// Waits until a subprocess-created file is visible.
Future<bool> _waitForFile(File file) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (await file.exists()) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return false;
}

/// Builds app config rooted in a temporary workspace.
AppConfig _testConfig(
  Directory root, {
  String gatewayAuthorizationHeader = '',
  String runtimeProfilePath = '',
}) {
  return AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:8080/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:8070/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
    agentAppName: 'Agent Awesome',
    agentUserId: 'doug',
    workspaceRoot: root.path,
    autoStartLocalServices: false,
    runtimeProfilePath: runtimeProfilePath,
    gatewayAuthorizationHeader: gatewayAuthorizationHeader,
  );
}

/// Builds a minimal runtime profile with local config files.
RuntimeProfile _testProfile(Directory root) {
  return RuntimeProfile(
    id: 'personal',
    label: 'Personal',
    harness: HarnessRuntime(
      id: 'harness',
      label: 'Harness',
      apiBaseUrl: 'http://127.0.0.1:8080/api',
      contextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
      appName: 'Agent Awesome',
      userId: 'doug',
      workingDirectory: '${root.path}/harness',
      executablePath: '${root.path}/harness/build/bin/agent-awesome',
      modelConfigPath: '${root.path}/harness/model.yaml',
      agentConfigPath: '${root.path}/harness/agent.yaml',
      toolConfigPath: '${root.path}/harness/tool.yaml',
      port: 8080,
      autoStart: false,
    ),
    gateway: GatewayRuntime(
      id: 'gateway',
      label: 'Gateway',
      apiBaseUrl: 'http://127.0.0.1:8070/api',
      healthUrl: 'http://127.0.0.1:8070/healthz',
      workingDirectory: '${root.path}/gateway',
      executablePath: '${root.path}/gateway/build/agent-gateway',
      harnessBaseUrl: 'http://127.0.0.1:8080/api',
      contextBaseUrl: 'http://127.0.0.1:8081/api/context',
      memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
      appName: 'Agent Awesome',
      userId: 'doug',
      port: 8070,
      autoStart: false,
      enabled: true,
    ),
    runbook: RunbookRuntime(
      id: 'runbook',
      label: 'Runbook',
      apiBaseUrl: 'http://127.0.0.1:8092/api/runbooks',
      healthUrl: 'http://127.0.0.1:8092/healthz',
      workingDirectory: '${root.path}/harness',
      executablePath: '${root.path}/harness/build/bin/runbook-service',
      definitionsDir: '${root.path}/runbooks',
      dbPath: '${root.path}/data/runbook.db',
      port: 8092,
      autoStart: false,
      enabled: true,
    ),
    memoryDomains: const <McpServerRuntime>[
      McpServerRuntime(
        id: 'memory',
        label: 'Memory',
        kind: 'memory',
        endpoint: 'http://127.0.0.1:8090/mcp',
        healthUrl: 'http://127.0.0.1:8090/healthz',
        workingDirectory: '/tmp/memory',
        executablePath: '/tmp/memoryd',
        dbPath: '/tmp/memory.db',
        dataDir: '/tmp/memory-files',
        arguments: <String>[],
        autoStart: false,
        enabled: true,
      ),
    ],
    agentMemory: const AgentMemoryRuntime(
      actor: 'agent:personal',
      readDomains: <String>['memory'],
      writeDomains: <String>['memory'],
      defaultWriteDomain: 'memory',
      allowedSensitivities: <String>['public', 'internal', 'private'],
    ),
  );
}
