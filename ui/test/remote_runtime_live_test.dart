/// Exercises the Flutter controller against a live remote Docker runtime.
library;

import 'dart:io';

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs guarded live remote-runtime tests.
void main() {
  final enabled =
      Platform.environment['RUN_AGENTAWESOME_REMOTE_LIVE_TEST'] == '1';

  test(
    'creates chat and runs Launchpad through the remote gateway',
    () async {
      final runModelChat =
          Platform.environment['RUN_AGENTAWESOME_REMOTE_MODEL_CHAT'] == '1';
      final profilePath =
          Platform.environment['AGENTAWESOME_REMOTE_LIVE_PROFILE'] ?? '';
      final gatewayBaseUrl =
          Platform.environment['AGENT_GATEWAY_BASE_URL'] ??
          'http://127.0.0.1:18070/api';
      final gatewayToken =
          Platform.environment['AGENTAWESOME_GATEWAY_TOKEN'] ?? 'smoke-token';
      final appName = Platform.environment['AGENT_APP_NAME'] ?? 'agent_awesome';
      final userId = Platform.environment['AGENT_USER_ID'] ?? 'doug';
      final workspace = await Directory.systemTemp.createTemp(
        'agentawesome-remote-live-ui-',
      );
      addTearDown(() async {
        if (await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
      });

      expect(profilePath, isNotEmpty);
      expect(await File(profilePath).exists(), isTrue);
      final controller = AgentAwesomeAppController(
        config: AppConfig(
          agentApiBaseUrl: gatewayBaseUrl,
          agentGatewayBaseUrl: gatewayBaseUrl,
          agentContextApiBaseUrl: _contextBaseUrl(gatewayBaseUrl),
          memoryMcpUrl: _mcpBaseUrl(gatewayBaseUrl),
          agentAppName: appName,
          agentUserId: userId,
          workspaceRoot: workspace.path,
          autoStartLocalServices: false,
          runtimeProfilePath: profilePath,
          gatewayAuthorizationHeader: 'Bearer $gatewayToken',
        ),
        appSettingsStore: _MemoryAppSettingsStore(
          saved: const AgentAwesomeAppSettings(gettingStartedCompleted: true),
        ),
      );
      addTearDown(controller.close);

      await controller.initialize();
      expect(controller.runtimeProfile, isNotNull);
      expect(await controller.createChat(), isTrue);
      expect(controller.selectedSessionId, isNotEmpty);
      if (runModelChat) {
        await controller.sendUserMessage(
          'Reply with exactly: remote gemma ready',
        );
        expect(
          controller.messages.any(
            (message) =>
                message.author != 'You' &&
                message.text.toLowerCase().contains('remote gemma ready'),
          ),
          isTrue,
          reason: controller.messages.map((message) => message.text).join('\n'),
        );
      }

      await controller.refreshAutomationsFromUi();
      final definition = controller.automationDefinitions
          .where((candidate) => candidate.id == 'smoke_noop')
          .firstOrNull;
      expect(definition, isNotNull, reason: controller.automationsMessage);

      await controller.createAutomationRunSetupFromUi(
        definition: definition!,
        name: 'Smoke Noop Launch From UI',
      );
      final setup = controller.selectedAutomationRunSetup;
      expect(setup, isNotNull, reason: controller.automationsMessage);

      await controller.previewAutomationRunSetupFromUi(setup!);
      expect(controller.selectedAutomationLaunchPreview?.status, 'ready');

      await controller.startAutomationRunSetupFromUi(setup);
      expect(controller.selectedAutomationRun?.id, isNotEmpty);
      await controller.loadSelectedAutomationRunSnapshot();
      expect(
        controller.selectedAutomationLaunchRunSnapshot?.runId,
        controller.selectedAutomationRun?.id,
      );
    },
    skip: enabled
        ? false
        : 'Set RUN_AGENTAWESOME_REMOTE_LIVE_TEST=1 with a live gateway.',
  );
}

/// Returns the gateway-routed context API base URL.
String _contextBaseUrl(String gatewayBaseUrl) {
  final uri = Uri.parse(gatewayBaseUrl);
  return uri.replace(path: '/api/context', query: null).toString();
}

/// Returns the gateway-routed MCP base URL.
String _mcpBaseUrl(String gatewayBaseUrl) {
  final uri = Uri.parse(gatewayBaseUrl);
  return uri.replace(path: '/mcp', query: null).toString();
}

/// Keeps app settings in memory for live smoke tests.
class _MemoryAppSettingsStore extends AgentAwesomeAppSettingsStore {
  /// Creates an in-memory settings store seeded with [saved].
  _MemoryAppSettingsStore({required this.saved});

  AgentAwesomeAppSettings saved;

  /// Loads the latest in-memory app settings.
  @override
  Future<AgentAwesomeAppSettings> load() async {
    return saved;
  }

  /// Saves app settings in memory for subsequent reads.
  @override
  Future<void> save(
    AgentAwesomeAppSettings settings, {
    Iterable<String> extraPolicyActors = const <String>[],
  }) async {
    saved = settings;
  }
}
