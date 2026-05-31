/// Tests controller persistence for approved conversational tool usage.
library;

import 'dart:async';
import 'dart:io';

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/config_files.dart';
import 'package:agentawesome_ui/clients/assistant_client.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/domain/runtime_profile.dart';
import 'package:agentawesome_ui/domain/tool_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs approved tool config persistence tests.
void main() {
  test('approved confirmation updates active tool config allowlist', () async {
    const toolPath = '/tmp/tools/memory/tool.yaml';
    final store = _MemoryConfigFileStore(<String, String>{
      toolPath: '''
mcp:
  enabled: true
  servers:
    - name: memory
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
      require-confirmation-tools:
        - remember
      tools:
        allow:
          - remember
          - search_memory
''',
    });
    final client = _RecordingAssistantClient();
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      assistantClient: client,
      configFiles: store,
    );
    controller
      ..runtimeProfile = _runtimeProfile(toolPath)
      ..selectedSessionId = 'session-1'
      ..pendingConfirmation = const ConfirmationRequest(
        callId: 'confirm-1',
        hint: 'Approve task write?',
        toolName: 'mcp.call',
        mcpServerName: 'memory',
        mcpToolName: 'create_task',
        options: <ConfirmationOption>[
          ConfirmationOption(action: 'deny', label: 'Deny'),
          ConfirmationOption(action: 'approve_once', label: 'Approve once'),
        ],
      );

    await controller.answerConfirmation(
      const ConfirmationOption(action: 'approve_once', label: 'Approve once'),
    );

    expect(client.confirmations.single.callId, 'confirm-1');
    final saved = ToolConfigDocument.parse(store.files[toolPath]!);
    expect(saved.mcp.servers.single.requireConfirmationTools, <String>[
      'remember',
      'create_task',
    ]);
    expect(saved.mcp.servers.single.tools.allow, <String>[
      'remember',
      'search_memory',
      'create_task',
    ]);
  });

  test('stream failures write a runtime message into the chat', () async {
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      assistantClient: _ThrowingAssistantClient(),
    );
    controller
      ..selectedSessionId = 'session-1'
      ..sending = true
      ..pendingConfirmation = const ConfirmationRequest(
        callId: 'confirm-1',
        hint: 'Approve task write?',
        toolName: 'mcp.call',
        mcpServerName: 'memory',
        mcpToolName: 'create_task',
        options: <ConfirmationOption>[
          ConfirmationOption(action: 'deny', label: 'Deny'),
        ],
      );

    await controller.answerConfirmation(
      const ConfirmationOption(action: 'deny', label: 'Deny'),
    );

    expect(controller.sending, isFalse);
    expect(controller.messages, hasLength(1));
    expect(controller.messages.single.role, ChatRole.tool);
    expect(
      controller.messages.single.text,
      contains('Agent Awesome could not complete the run'),
    );
  });
}

/// _RecordingAssistantClient records confirmation replies without networking.
class _RecordingAssistantClient extends AssistantClient {
  _RecordingAssistantClient()
    : super(baseUrl: 'http://127.0.0.1:1/api', appName: 'test', userId: 'user');

  /// Confirmation replies received by the fake runtime.
  final List<ConfirmationReply> confirmations = <ConfirmationReply>[];

  /// Records the confirmation reply and yields no runtime events.
  @override
  Stream<AssistantEvent> sendMessage({
    required String sessionId,
    String text = '',
    ConfirmationReply? confirmation,
    String modelRef = '',
  }) async* {
    if (confirmation != null) {
      confirmations.add(confirmation);
    }
  }
}

/// _ThrowingAssistantClient simulates a streaming runtime failure.
class _ThrowingAssistantClient extends AssistantClient {
  _ThrowingAssistantClient()
    : super(baseUrl: 'http://127.0.0.1:1/api', appName: 'test', userId: 'user');

  /// Throws before yielding any runtime events.
  @override
  Stream<AssistantEvent> sendMessage({
    required String sessionId,
    String text = '',
    ConfirmationReply? confirmation,
    String modelRef = '',
  }) async* {
    throw const AssistantException('stream failed');
  }
}

/// _MemoryConfigFileStore stores config files in memory for controller tests.
class _MemoryConfigFileStore extends ConfigFileStore {
  const _MemoryConfigFileStore(this.files);

  /// In-memory file contents keyed by path.
  final Map<String, String> files;

  /// Reads a test config file.
  @override
  Future<String> read(String path) async {
    final content = files[path];
    if (content == null) {
      throw FileSystemException('Missing config file', path);
    }
    return content;
  }

  /// Writes a test config file.
  @override
  Future<void> write(String path, String content) async {
    files[path] = content;
  }

  /// Lists in-memory config entries.
  @override
  Future<List<ConfigFileEntry>> list({
    required ConfigFileKind kind,
    String assignedPath = '',
  }) async {
    return <ConfigFileEntry>[
      for (final path in files.keys)
        ConfigFileEntry(
          path: path,
          kind: kind,
          assigned: path == assignedPath,
          displayName: path.split('/').last,
        ),
    ];
  }
}

/// Builds a minimal app config for controller tests.
AppConfig _testConfig() {
  return const AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:8080/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:8070/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
    agentAppName: 'test',
    agentUserId: 'user',
    workspaceRoot: '/tmp',
    autoStartLocalServices: false,
    runtimeProfilePath: '/tmp/runtime-profile.json',
  );
}

/// Builds a minimal runtime profile with one assigned tool config.
RuntimeProfile _runtimeProfile(String toolPath) {
  return RuntimeProfile(
    id: 'personal',
    label: 'Personal',
    harness: HarnessRuntime(
      id: 'harness',
      label: 'Harness',
      apiBaseUrl: 'http://127.0.0.1:8080/api',
      contextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
      appName: 'test',
      userId: 'user',
      workingDirectory: '/tmp/harness',
      executablePath: '/tmp/bin/agent-awesome',
      modelConfigPath: '/tmp/model.yaml',
      agentConfigPath: '/tmp/agent.yaml',
      toolConfigPath: toolPath,
      port: 8080,
      autoStart: false,
    ),
    gateway: const GatewayRuntime(
      id: 'gateway',
      label: 'Gateway',
      apiBaseUrl: 'http://127.0.0.1:8070/api',
      healthUrl: 'http://127.0.0.1:8070/healthz',
      workingDirectory: '/tmp/gateway',
      executablePath: '/tmp/bin/agent-gateway',
      harnessBaseUrl: 'http://127.0.0.1:8080/api',
      contextBaseUrl: 'http://127.0.0.1:8081/api/context',
      memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
      appName: 'test',
      userId: 'user',
      port: 8070,
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
        executablePath: '/tmp/bin/memoryd',
        dbPath: '/tmp/memory.db',
        dataDir: '/tmp/memory-files',
        arguments: <String>[],
        autoStart: false,
        enabled: true,
      ),
    ],
    agentMemory: const AgentMemoryRuntime(
      actor: 'agent:test',
      readDomains: <String>['memory'],
      writeDomains: <String>['memory'],
      defaultWriteDomain: 'memory',
      allowedSensitivities: <String>['public'],
    ),
  );
}
