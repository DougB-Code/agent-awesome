/// Tests Agent Awesome controller shutdown boundaries.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/chat_history.dart';
import 'package:agentawesome_ui/app/local_services.dart';
import 'package:agentawesome_ui/app/process_supervisor.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:agentawesome_ui/clients/assistant_client.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs controller shutdown tests.
void main() {
  test('closeClients leaves managed local services running', () {
    final processSupervisor = _testProcessSupervisor();
    final localServices = _TrackingLocalServiceSupervisor(processSupervisor);
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      processSupervisor: processSupervisor,
      localServices: localServices,
    );

    controller.closeClients();

    expect(localServices.closeCount, 0);
  });

  test('close stops managed local services once', () async {
    final processSupervisor = _testProcessSupervisor();
    final localServices = _TrackingLocalServiceSupervisor(processSupervisor);
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      processSupervisor: processSupervisor,
      localServices: localServices,
    );

    await controller.close();
    await controller.close();

    expect(localServices.closeCount, 1);
  });

  test('close reports shutdown progress', () async {
    final processSupervisor = _testProcessSupervisor();
    final localServices = _TrackingLocalServiceSupervisor(processSupervisor);
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      processSupervisor: processSupervisor,
      localServices: localServices,
    );
    final messages = <String>[];

    await controller.close(onStatus: messages.add);

    expect(messages, contains('Closing service clients'));
    expect(messages, contains('Stopping local model runtime'));
    expect(messages, contains('Stopping managed service processes'));
    expect(messages, contains('tracking supervisor closed'));
    expect(messages, contains('Stopping remaining subprocesses'));
    expect(messages, contains('Managed runtime stopped'));
  });

  test('close begins process supervisor shutdown before services', () async {
    final processSupervisor = _testProcessSupervisor();
    final localServices = _TrackingLocalServiceSupervisor(processSupervisor);
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      processSupervisor: processSupervisor,
      localServices: localServices,
    );

    await controller.close();

    expect(localServices.sawProcessSupervisorClosing, isTrue);
  });

  test(
    'selectSession preserves local history when harness rejects it',
    () async {
      final historyStore = _MemoryChatHistoryStore(
        entries: <ChatHistoryEntry>[
          ChatHistoryEntry(
            profilePath: '/tmp/personal.json',
            profileId: 'personal',
            profileLabel: 'Personal',
            sessionId: 'stale-session',
            title: 'Old chat',
            createdAt: DateTime(2026, 5, 7, 9),
            updatedAt: DateTime(2026, 5, 7, 10),
          ),
        ],
      );
      final controller = AgentAwesomeAppController(
        config: _testConfig(),
        assistantClient: _RejectingAssistantClient(),
        chatHistoryStore: historyStore,
      );
      controller.runtimeProfile = _testProfile();
      controller.runtimeProfilePath = '/tmp/personal.json';
      controller.chatHistory = await historyStore.load();
      controller.sessions = const <ChatSession>[];
      controller.selectedSessionId = 'stale-session';
      controller.messages = <ChatMessage>[
        ChatMessage(
          id: 'message-1',
          role: ChatRole.user,
          author: 'You',
          text: 'hello',
          createdAt: DateTime(2026, 5, 7, 10),
        ),
      ];

      await controller.selectSession('stale-session');

      expect(controller.selectedSessionId, isNull);
      expect(controller.messages, isEmpty);
      expect(historyStore.saved, hasLength(1));
      expect(historyStore.saved.single.sessionId, 'stale-session');
    },
  );
}

/// Tracking supervisor records whether service shutdown was requested.
class _TrackingLocalServiceSupervisor extends LocalServiceSupervisor {
  /// Creates a tracking local service supervisor.
  _TrackingLocalServiceSupervisor(this.processSupervisor)
    : super(config: _testConfig(), processSupervisor: processSupervisor);

  /// Shared process supervisor observed during shutdown.
  final ProcessSupervisor processSupervisor;

  /// Number of service shutdown requests.
  int closeCount = 0;

  /// Whether service close observed process supervisor shutdown already set.
  bool sawProcessSupervisorClosing = false;

  /// Records service shutdown without touching real processes.
  @override
  Future<void> close({void Function(String message)? onStatus}) async {
    closeCount++;
    sawProcessSupervisorClosing = processSupervisor.isClosing;
    onStatus?.call('tracking supervisor closed');
  }
}

/// Rejecting client simulates an ADK session id missing after harness restart.
class _RejectingAssistantClient extends AssistantClient {
  /// Creates a rejecting assistant client.
  _RejectingAssistantClient()
    : super(baseUrl: 'http://127.0.0.1:1/api', appName: 'test', userId: 'user');

  /// Rejects session event loads like the harness does for a stale session.
  @override
  Future<List<AssistantEvent>> loadSessionEvents(String sessionId) async {
    throw const AssistantException('HTTP 500 loading session');
  }
}

/// Memory-backed chat history store keeps controller tests away from disk.
class _MemoryChatHistoryStore extends ChatHistoryStore {
  /// Creates an in-memory store seeded with known entries.
  _MemoryChatHistoryStore({required List<ChatHistoryEntry> entries})
    : saved = entries;

  /// Latest saved entries.
  List<ChatHistoryEntry> saved;

  /// Loads saved in-memory chat metadata.
  @override
  Future<List<ChatHistoryEntry>> load() async {
    return saved;
  }

  /// Saves chat metadata to memory for assertions.
  @override
  Future<void> save(List<ChatHistoryEntry> entries) async {
    saved = entries;
  }
}

/// Builds a minimal app config for controller shutdown tests.
AppConfig _testConfig() {
  return const AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:8080/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:8070/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
    agentAppName: 'agent_awesome',
    agentUserId: 'doug',
    workspaceRoot: '/tmp/agentawesome-ui-test',
    autoStartLocalServices: true,
    runtimeProfilePath: '',
  );
}

/// Builds a minimal runtime profile for controller unit tests.
RuntimeProfile _testProfile() {
  return const RuntimeProfile(
    id: 'personal',
    label: 'Personal',
    harness: HarnessRuntime(
      id: 'harness',
      label: 'Harness',
      apiBaseUrl: 'http://127.0.0.1:1/api',
      contextApiBaseUrl: 'http://127.0.0.1:1/api/context',
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
    memoryServerConfigPath: '/tmp/memory.json',
    mcpServers: <McpServerRuntime>[],
  );
}

/// Builds a process supervisor for controller shutdown tests.
ProcessSupervisor _testProcessSupervisor() {
  final supervisor = ProcessSupervisor(
    logDirectory: '/tmp/agentawesome-ui-test/logs',
    workspaceRoot: '/tmp/agentawesome-ui-test',
  );
  addTearDown(supervisor.close);
  return supervisor;
}
