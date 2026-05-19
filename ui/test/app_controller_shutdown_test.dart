/// Tests Agent Awesome controller shutdown boundaries.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/chat_history.dart';
import 'package:agentawesome_ui/app/config_files.dart';
import 'package:agentawesome_ui/app/local_services.dart';
import 'package:agentawesome_ui/app/process_supervisor.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:agentawesome_ui/clients/assistant_client.dart';
import 'package:agentawesome_ui/domain/model_config.dart';
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

      expect(controller.selectedSessionId, 'stale-session');
      expect(controller.messages, isEmpty);
      expect(historyStore.saved, hasLength(1));
      expect(historyStore.saved.single.sessionId, 'stale-session');
    },
  );

  test(
    'selectHistoryChat keeps a cross-profile history card selected on failure',
    () async {
      const missingProfilePath = '/tmp/missing-personal-profile.json';
      const sessionId = 'stale-cross-profile-session';
      const chatKey = '$missingProfilePath::$sessionId';
      final historyStore = _MemoryChatHistoryStore(
        entries: <ChatHistoryEntry>[
          ChatHistoryEntry(
            profilePath: missingProfilePath,
            profileId: 'personal',
            profileLabel: 'Personal',
            sessionId: sessionId,
            title: 'Chat session-',
            createdAt: DateTime(2026, 5, 16, 9, 17),
            updatedAt: DateTime(2026, 5, 16, 9, 17),
          ),
        ],
      );
      final controller = AgentAwesomeAppController(
        config: _testConfig(),
        assistantClient: _RejectingAssistantClient(),
        chatHistoryStore: historyStore,
      );
      controller.runtimeProfile = _testProfile();
      controller.runtimeProfilePath = '/tmp/agent-awesome-profile.json';
      controller.chatHistory = await historyStore.load();
      controller.sessions = const <ChatSession>[];

      await controller.selectHistoryChat(chatKey);

      expect(controller.selectedChatKey, chatKey);
      expect(controller.selectedSessionId, sessionId);
      expect(controller.messages, isEmpty);
    },
  );

  test('selectSession restores the last routed chat model', () async {
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      assistantClient: _SessionEventsAssistantClient(
        events: <AssistantEvent>[
          const AssistantEvent(
            id: 'user-1',
            author: 'user',
            text: 'Use the mini model.',
            partial: false,
            modelRef: 'openai:gpt-5-mini',
          ),
          const AssistantEvent(
            id: 'assistant-1',
            author: 'agent_awesome',
            text: 'Done.',
            partial: false,
            modelRef: 'openai:gpt-5-pro',
          ),
        ],
      ),
    );
    controller.runtimeProfile = _testProfile();
    controller.runtimeProfilePath = '/tmp/personal.json';
    controller.availableModelConfigs = _testModelConfigs();

    await controller.selectSession('session-live');

    expect(controller.activeChatModelRef, 'openai:gpt-5-pro');
    expect(controller.messages.last.modelRef, 'openai:gpt-5-pro');
  });

  test('selectSession restores missing assistant route labels', () async {
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      assistantClient: _SessionEventsAssistantClient(
        events: <AssistantEvent>[
          const AssistantEvent(
            id: 'user-1',
            author: 'user',
            text: 'Use the pro model.',
            partial: false,
            modelRef: 'openai:gpt-5-pro',
          ),
          const AssistantEvent(
            id: 'assistant-1',
            author: 'agent_awesome',
            text: 'Done.',
            partial: false,
          ),
        ],
      ),
    );
    controller.runtimeProfile = _testProfile();
    controller.runtimeProfilePath = '/tmp/personal.json';
    controller.availableModelConfigs = _testModelConfigs();

    await controller.selectSession('session-live');

    expect(controller.activeChatModelRef, 'openai:gpt-5-pro');
    expect(controller.messages.last.modelRef, 'openai:gpt-5-pro');
  });
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

/// Rejecting client simulates a runtime session id missing after harness restart.
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

/// Session events client returns seeded events for controller tests.
class _SessionEventsAssistantClient extends AssistantClient {
  /// Creates a client backed by in-memory session events.
  _SessionEventsAssistantClient({required this.events})
    : super(baseUrl: 'http://127.0.0.1:1/api', appName: 'test', userId: 'user');

  /// Events returned for every loaded session.
  final List<AssistantEvent> events;

  /// Loads seeded session events.
  @override
  Future<List<AssistantEvent>> loadSessionEvents(String sessionId) async {
    return events;
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

/// Returns the model choices used by chat restoration tests.
List<ConfigFileEntry> _testModelConfigs() {
  return const <ConfigFileEntry>[
    ConfigFileEntry(
      path: '/tmp/model.yaml',
      kind: ConfigFileKind.model,
      assigned: true,
      displayName: 'Model',
      modelChoices: <ModelConfigChoice>[
        ModelConfigChoice(
          providerId: 'openai',
          providerName: 'OpenAI',
          modelId: 'gpt-5-mini',
          modelName: 'GPT-5 Mini',
          isDefault: true,
        ),
        ModelConfigChoice(
          providerId: 'openai',
          providerName: 'OpenAI',
          modelId: 'gpt-5-pro',
          modelName: 'GPT-5 Pro',
          isDefault: false,
        ),
      ],
    ),
  ];
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
    gateway: GatewayRuntime(
      id: 'gateway',
      label: 'Gateway',
      apiBaseUrl: 'http://127.0.0.1:2/api',
      healthUrl: 'http://127.0.0.1:2/healthz',
      workingDirectory: '/tmp/gateway',
      packagePath: './cmd/agent-gateway',
      harnessBaseUrl: 'http://127.0.0.1:1/api',
      contextBaseUrl: 'http://127.0.0.1:1/api/context',
      memoryMcpUrl: 'http://127.0.0.1:1/mcp',
      appName: 'test',
      userId: 'user',
      port: 2,
      autoStart: false,
      enabled: true,
    ),
    memoryDomains: <McpServerRuntime>[],
    agentMemory: AgentMemoryRuntime(
      actor: 'agent:test',
      readDomains: <String>['memory'],
      writeDomains: <String>['memory'],
      defaultWriteDomain: 'memory',
      allowedSensitivities: <String>['public', 'internal', 'private'],
    ),
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
