/// Tests controller-owned chat title refresh orchestration.
library;

import 'dart:async';
import 'dart:io';

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/app_settings.dart';
import 'package:agentawesome_ui/app/chat_history.dart';
import 'package:agentawesome_ui/app/config_files.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:agentawesome_ui/clients/assistant_client.dart';
import 'package:agentawesome_ui/clients/chat_title_client.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs app controller chat title tests.
void main() {
  test(
    'selectSession refreshes fallback chat title from loaded transcript',
    () async {
      final historyStore = _MemoryChatHistoryStore(
        entries: <ChatHistoryEntry>[
          ChatHistoryEntry(
            profilePath: '/tmp/personal.json',
            profileId: 'personal',
            profileLabel: 'Personal',
            sessionId: 'session-12345678',
            title: 'Chat session-',
            createdAt: DateTime(2026, 5, 8, 12),
            updatedAt: DateTime(2026, 5, 8, 12),
          ),
        ],
      );
      final titleClient = _FakeChatTitleClient(title: 'UI Regression Fix');
      final tempRoot = await Directory.systemTemp.createTemp(
        'agentawesome-title-controller-test-',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final configFiles = ConfigFileStore(
        configDirectoryPath: '${tempRoot.path}/config',
      );
      final modelConfigPath = await configFiles.create(ConfigFileKind.model);
      const modelConfigContent = 'default: local:test\nproviders: {}\n';
      await configFiles.write(modelConfigPath, modelConfigContent);
      final controller = AgentAwesomeAppController(
        config: _testConfig(),
        assistantClient: _TranscriptAssistantClient(),
        chatHistoryStore: historyStore,
        configFiles: configFiles,
        titleClient: titleClient,
      );
      controller.appSettings = const AgentAwesomeAppSettings(
        chatTitleSummariesEnabled: true,
      );
      controller.runtimeProfile = _testProfile(modelConfigPath);
      controller.runtimeProfilePath = '/tmp/personal.json';
      controller.chatHistory = await historyStore.load();
      controller.sessions = <ChatSession>[
        ChatSession(
          id: 'session-12345678',
          title: 'Chat session-',
          updatedAt: DateTime(2026, 5, 8, 12),
        ),
      ];

      await controller.selectSession('session-12345678');
      await titleClient.completed.future;
      await Future<void>.delayed(Duration.zero);

      expect(titleClient.modelConfigContent, modelConfigContent);
      expect(historyStore.saved.single.title, 'UI Regression Fix');
      expect(historyStore.saved.single.titleStatus, 'generated');
    },
  );
}

/// Transcript client returns one visible user and assistant exchange.
class _TranscriptAssistantClient extends AssistantClient {
  /// Creates a transcript assistant client.
  _TranscriptAssistantClient()
    : super(baseUrl: 'http://127.0.0.1:1/api', appName: 'test', userId: 'user');

  /// Loads a transcript without reaching a real ADK service.
  @override
  Future<List<AssistantEvent>> loadSessionEvents(String sessionId) async {
    return const <AssistantEvent>[
      AssistantEvent(
        id: 'user-1',
        author: 'user',
        text: 'The chat title is not updating.',
        partial: false,
      ),
      AssistantEvent(
        id: 'assistant-1',
        author: 'agent_awesome',
        text: 'I will inspect the logs and fix the regression.',
        partial: false,
      ),
    ];
  }
}

/// Fake title client records the selected model config and returns a title.
class _FakeChatTitleClient extends ChatTitleClient {
  /// Creates a fake title client.
  _FakeChatTitleClient({required this.title});

  /// Title returned to the controller.
  final String title;

  /// Completes when title generation has been requested and returned.
  final Completer<bool> completed = Completer<bool>();

  /// Model config content observed by the fake.
  String modelConfigContent = '';

  /// Generates a deterministic title for assertions.
  @override
  Future<String> generateTitle({
    required String modelConfigContent,
    String modelRef = '',
    required List<ChatMessage> messages,
  }) async {
    this.modelConfigContent = modelConfigContent;
    completed.complete(true);
    return title;
  }
}

/// Memory-backed chat history store keeps tests away from disk.
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

/// Builds a minimal app config for controller title tests.
AppConfig _testConfig() {
  return const AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:8080/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:8070/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
    agentAppName: 'agent_awesome',
    agentUserId: 'doug',
    workspaceRoot: '/tmp/agentawesome-ui-test',
    autoStartLocalServices: false,
    runtimeProfilePath: '',
  );
}

/// Builds a profile with the general chat model config selected.
RuntimeProfile _testProfile(String modelConfigPath) {
  return RuntimeProfile(
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
      modelConfigPath: modelConfigPath,
      agentConfigPath: '/tmp/agent.yaml',
      toolConfigPath: '/tmp/tool.yaml',
      port: 1,
      autoStart: false,
    ),
    memoryServerConfigPath: '/tmp/memory.json',
    mcpServers: const <McpServerRuntime>[],
  );
}
