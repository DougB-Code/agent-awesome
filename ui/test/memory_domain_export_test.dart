/// Tests reviewed memory-domain export behavior.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/clients/mcp_client.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/domain/runtime_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs controller tests for explicit memory-domain exports.
void main() {
  test('exports reviewed copy only through an allowed domain flow', () async {
    final rpc = _RecordingRpcClient();
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      memoryClient: MemoryClient(rpc: rpc),
    )..runtimeProfile = _profile(allowedFlow: true);
    final source = _sourceRecord();

    final exported = await controller.exportMemoryCopyFromUi(
      source,
      const MemoryExportDraft(
        title: 'Sanitized capital note',
        content: 'Approved project funding range is available.',
        firewall: 'project',
        sensitivity: 'internal',
      ),
    );

    expect(exported, isTrue);
    final save = rpc.calls.where(
      (call) => call.name == 'save_memory_candidate',
    );
    expect(save, hasLength(1));
    final args = save.single.arguments;
    expect(args['content'], 'Approved project funding range is available.');
    expect(args['title'], 'Sanitized capital note');
    expect(args['trust_level'], 'user_asserted');
    expect(args['firewall'], 'project');
    expect(args['sensitivity'], 'internal');
    expect(args['source'], <String, dynamic>{
      'system': 'agent_awesome_declassification',
      'id': 'marriage:liquid-capital:ev-capital',
    });
    expect(controller.memorySafetyEvents, hasLength(1));
    expect(controller.memorySafetyEvents.single.kind, 'approved_export');
    expect(controller.memorySafetyEvents.single.approved, isTrue);
    expect(controller.memorySafetyEvents.single.sourceDomain, 'marriage');
    expect(controller.memorySafetyEvents.single.targetDomain, 'side_project');
  });

  test('blocks reviewed export when no domain flow is configured', () async {
    final rpc = _RecordingRpcClient();
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      memoryClient: MemoryClient(rpc: rpc),
    )..runtimeProfile = _profile(allowedFlow: false);

    final exported = await controller.exportMemoryCopyFromUi(
      _sourceRecord(),
      const MemoryExportDraft(
        title: 'Sanitized capital note',
        content: 'Approved project funding range is available.',
        firewall: 'project',
        sensitivity: 'internal',
      ),
    );

    expect(exported, isFalse);
    expect(
      rpc.calls.where((call) => call.name == 'save_memory_candidate'),
      isEmpty,
    );
    expect(controller.memoryMessage, contains('Export blocked'));
    expect(controller.memorySafetyEvents, hasLength(1));
    expect(controller.memorySafetyEvents.single.kind, 'blocked_export');
    expect(controller.memorySafetyEvents.single.approved, isFalse);
  });
}

/// _ToolCall records one fake MCP tool invocation.
class _ToolCall {
  /// Creates a fake tool call record.
  const _ToolCall({required this.name, required this.arguments});

  /// MCP tool name.
  final String name;

  /// Tool arguments captured from the controller.
  final Map<String, dynamic> arguments;
}

/// _RecordingRpcClient captures memory MCP calls without network access.
class _RecordingRpcClient implements ToolRpcClient {
  /// Recorded tool calls.
  final List<_ToolCall> calls = <_ToolCall>[];

  /// Fake endpoint used by the injected memory client.
  @override
  String get endpoint => 'memory://test';

  /// Records the call and returns a valid structured payload.
  @override
  Future<dynamic> callTool(
    String name, [
    Map<String, dynamic>? arguments,
  ]) async {
    calls.add(
      _ToolCall(name: name, arguments: arguments ?? <String, dynamic>{}),
    );
    if (name == 'search_memory' || name == 'search_sources') {
      return <String, dynamic>{'primary_memory': <Map<String, dynamic>>[]};
    }
    return <String, dynamic>{'memory_id': 'mem-exported'};
  }

  /// Lists the memory tools exposed by this fake transport.
  @override
  Future<List<String>> listToolNames() async {
    return const <String>['save_memory_candidate', 'search_memory'];
  }

  /// Closes no resources because this fake owns no sockets.
  @override
  void close() {}
}

/// Builds a two-domain profile for export policy tests.
RuntimeProfile _profile({required bool allowedFlow}) {
  return RuntimeProfile(
    id: 'test',
    label: 'Test',
    harness: const HarnessRuntime(
      id: 'harness',
      label: 'Harness',
      apiBaseUrl: 'http://127.0.0.1:1/api',
      contextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
      appName: 'test',
      userId: 'user',
      workingDirectory: '/tmp/harness',
      packagePath: './cmd/agent-awesome',
      modelConfigPath: '/tmp/model.yaml',
      agentConfigPath: '/tmp/agent.yaml',
      toolConfigPath: '/tmp/tool.yaml',
      port: 1,
      autoStart: false,
    ),
    gateway: const GatewayRuntime(
      id: 'gateway',
      label: 'Gateway',
      apiBaseUrl: 'http://127.0.0.1:2/api',
      healthUrl: 'http://127.0.0.1:2/healthz',
      workingDirectory: '/tmp/gateway',
      packagePath: './cmd/agent-gateway',
      harnessBaseUrl: 'http://127.0.0.1:1/api',
      contextBaseUrl: 'http://127.0.0.1:8081/api/context',
      memoryMcpUrl: 'http://127.0.0.1:1/mcp',
      appName: 'test',
      userId: 'user',
      port: 2,
      autoStart: false,
      enabled: true,
    ),
    memoryDomains: const <McpServerRuntime>[
      McpServerRuntime(
        id: 'marriage',
        label: 'Marriage',
        kind: 'memory',
        endpoint: 'http://127.0.0.1:8101/mcp',
        healthUrl: 'http://127.0.0.1:8101/healthz',
        workingDirectory: '/tmp/memory',
        packagePath: './cmd/memoryd',
        dbPath: '/tmp/marriage.db',
        dataDir: '/tmp/marriage-files',
        arguments: <String>[],
        autoStart: false,
        enabled: true,
      ),
      McpServerRuntime(
        id: 'side_project',
        label: 'Side Project',
        kind: 'memory',
        endpoint: 'http://127.0.0.1:8102/mcp',
        healthUrl: 'http://127.0.0.1:8102/healthz',
        workingDirectory: '/tmp/memory',
        packagePath: './cmd/memoryd',
        dbPath: '/tmp/side-project.db',
        dataDir: '/tmp/side-project-files',
        arguments: <String>[],
        autoStart: false,
        enabled: true,
      ),
    ],
    agentMemory: AgentMemoryRuntime(
      actor: 'agent:test',
      readDomains: const <String>['marriage', 'side_project'],
      writeDomains: const <String>['side_project'],
      defaultWriteDomain: 'side_project',
      allowedSensitivities: const <String>['public', 'internal', 'private'],
      allowedFlows: allowedFlow
          ? const <MemoryDomainFlow>[
              MemoryDomainFlow(
                fromDomain: 'marriage',
                toDomain: 'side_project',
              ),
            ]
          : const <MemoryDomainFlow>[],
    ),
  );
}

/// Creates a source record owned by the sensitive domain.
MemoryRecord _sourceRecord() {
  return const MemoryRecord(
    id: 'liquid-capital',
    domainId: 'marriage',
    evidenceId: 'ev-capital',
    title: 'Liquid capital',
    summary: 'Private finance details.',
    kind: 'profile_fact',
    topics: <String>['finance'],
    sourceLabel: 'budget:sheet',
    firewall: 'user',
    sensitivity: 'private',
    subjects: <String>['finance'],
    entityNames: <String>['Doug'],
  );
}

/// Builds a test app config that never starts local services.
AppConfig _testConfig() {
  return const AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:1/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:2/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:1/mcp',
    agentAppName: 'test',
    agentUserId: 'user',
    workspaceRoot: '/tmp/agentawesome-memory-export-test',
    autoStartLocalServices: false,
    runtimeProfilePath: '',
  );
}
