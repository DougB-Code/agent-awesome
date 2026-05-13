/// Tests memory-domain settings controls.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/domain/runtime_profile.dart';
import 'package:agentawesome_ui/ui/settings/settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs memory settings widget tests.
void main() {
  testWidgets('memory settings expose structured domain access controls', (
    tester,
  ) async {
    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.runtimeProfile = _multiMemoryProfile();
    controller.runtimeProfilePath = '/tmp/runtime-profile.json';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: SettingsDetailsPanel(
              controller: controller,
              section: 'Memory',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EFFECTIVE ACCESS'), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Readable domains'), findsOneWidget);
    expect(find.text('Writable domains'), findsOneWidget);
    expect(find.text('Allowed sensitivities'), findsOneWidget);
    expect(find.text('Allowed flows'), findsOneWidget);
    expect(find.text('Default write domain'), findsOneWidget);
    expect(find.text('Personal Memory -> Project Memory'), findsOneWidget);
  });
}

/// Builds a minimal multi-memory runtime profile for settings rendering.
RuntimeProfile _multiMemoryProfile() {
  return const RuntimeProfile(
    id: 'multi',
    label: 'Multi',
    harness: HarnessRuntime(
      id: 'harness',
      label: 'Harness',
      apiBaseUrl: 'http://127.0.0.1:8080/api',
      contextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
      appName: 'test',
      userId: 'user',
      workingDirectory: '/tmp/harness',
      packagePath: './cmd/agent-awesome',
      modelConfigPath: '/tmp/model.yaml',
      agentConfigPath: '/tmp/agent.yaml',
      toolConfigPath: '/tmp/tool.yaml',
      port: 8080,
      autoStart: false,
    ),
    gateway: GatewayRuntime(
      id: 'gateway',
      label: 'Gateway',
      apiBaseUrl: 'http://127.0.0.1:8070/api',
      healthUrl: 'http://127.0.0.1:8070/healthz',
      workingDirectory: '/tmp/gateway',
      packagePath: './cmd/agent-gateway',
      harnessBaseUrl: 'http://127.0.0.1:8080/api',
      contextBaseUrl: 'http://127.0.0.1:8081/api/context',
      memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
      appName: 'test',
      userId: 'user',
      port: 8070,
      autoStart: false,
      enabled: true,
    ),
    memoryDomains: <McpServerRuntime>[
      McpServerRuntime(
        id: 'memory',
        label: 'Personal Memory',
        kind: 'memory',
        endpoint: 'http://127.0.0.1:8090/mcp',
        healthUrl: 'http://127.0.0.1:8090/healthz',
        workingDirectory: '/tmp/memory',
        packagePath: './cmd/memoryd',
        dbPath: '/tmp/memory.db',
        dataDir: '/tmp/memory-files',
        arguments: <String>[],
        autoStart: false,
        enabled: true,
      ),
      McpServerRuntime(
        id: 'project',
        label: 'Project Memory',
        kind: 'memory',
        endpoint: 'http://127.0.0.1:8091/mcp',
        healthUrl: 'http://127.0.0.1:8091/healthz',
        workingDirectory: '/tmp/memory',
        packagePath: './cmd/memoryd',
        dbPath: '/tmp/project.db',
        dataDir: '/tmp/project-files',
        arguments: <String>[],
        autoStart: false,
        enabled: true,
      ),
    ],
    agentMemory: AgentMemoryRuntime(
      actor: 'agent:test',
      readDomains: <String>['memory', 'project'],
      writeDomains: <String>['project'],
      defaultWriteDomain: 'project',
      allowedSensitivities: <String>['public', 'internal'],
      allowedFlows: <MemoryDomainFlow>[
        MemoryDomainFlow(fromDomain: 'memory', toDomain: 'project'),
      ],
    ),
  );
}

/// Builds app configuration that keeps network endpoints inert in widget tests.
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
