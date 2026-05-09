/// Tests app-owned settings serialization.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/app_settings.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs app settings tests.
void main() {
  test('serializes exact summary model selection', () {
    const settings = AgentAwesomeAppSettings(
      defaultChatProfilePath: '/tmp/profile.json',
      summaryModelConfigPath: '/tmp/models.yaml',
      summaryModelRef: 'openai:gpt-nano',
      chatTitleSummariesEnabled: true,
      gettingStartedCompleted: true,
    );

    final encoded = settings.toJson();
    final decoded = AgentAwesomeAppSettings.fromJson(encoded);

    expect(encoded['summary_model_ref'], 'openai:gpt-nano');
    expect(decoded.summaryModelConfigPath, '/tmp/models.yaml');
    expect(decoded.summaryModelRef, 'openai:gpt-nano');
    expect(encoded['getting_started_completed'], isTrue);
    expect(decoded.gettingStartedCompleted, isTrue);
  });

  test('defaults first launch guide to visible', () {
    final decoded = AgentAwesomeAppSettings.fromJson(const <String, dynamic>{});

    expect(decoded.gettingStartedCompleted, isFalse);
  });

  test('chat title model falls back to active profile model config', () {
    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.appSettings = const AgentAwesomeAppSettings(
      chatTitleSummariesEnabled: true,
    );
    controller.runtimeProfile = _testProfile('/tmp/general-model.yaml');

    expect(controller.summaryModelConfigPath, '/tmp/general-model.yaml');
    expect(controller.summaryModelRef, '');
  });
}

/// Builds a minimal app config for settings-derived controller tests.
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
