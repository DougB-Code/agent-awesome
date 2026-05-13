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
    expect(
      decoded.memoryFirewalls.map((firewall) => firewall.id),
      contains('user'),
    );
    expect(decoded.memoryFirewalls.first.sharedWith, isNotEmpty);
  });

  test('defaults first launch guide and memory firewalls', () {
    final decoded = AgentAwesomeAppSettings.fromJson(const <String, dynamic>{});

    expect(decoded.gettingStartedCompleted, isFalse);
    expect(decoded.effectiveMemoryFirewalls.first.id, 'session');
    expect(
      decoded.effectiveMemoryFirewalls.map((firewall) => firewall.id),
      containsAll(<String>['user', 'project', 'global']),
    );
  });

  test('normalizes custom memory firewalls', () {
    final decoded = AgentAwesomeAppSettings.fromJson(<String, dynamic>{
      'memory_firewalls': <Map<String, dynamic>>[
        <String, dynamic>{'id': ' Acme Client ', 'label': 'Acme'},
        <String, dynamic>{
          'id': 'contoso-prod',
          'label': '',
          'shares': <Map<String, dynamic>>[
            <String, dynamic>{
              'kind': 'principal',
              'id': ' Pat ',
              'label': 'Pat',
            },
            <String, dynamic>{'kind': 'principal', 'id': 'pat', 'label': 'pat'},
            <String, dynamic>{
              'kind': 'principal',
              'id': 'Legal',
              'label': 'Legal',
            },
          ],
          'writers': <Map<String, dynamic>>[
            <String, dynamic>{'kind': 'project', 'id': 'ops', 'label': 'Ops'},
          ],
        },
        <String, dynamic>{'id': 'acme-client', 'label': 'Duplicate'},
      ],
    });

    expect(
      decoded.effectiveMemoryFirewalls.map((firewall) => firewall.id).toList(),
      <String>['acme-client', 'contoso-prod'],
    );
    expect(decoded.effectiveMemoryFirewalls.first.label, 'Acme');
    expect(decoded.effectiveMemoryFirewalls.last.label, 'Contoso Prod');
    expect(decoded.effectiveMemoryFirewalls.last.sharedWith, <String>[
      'Pat',
      'Legal',
    ]);
    expect(
      decoded.effectiveMemoryFirewalls.last.shares
          .map((share) => '${share.kind}:${share.id}')
          .toList(),
      <String>['principal:pat', 'principal:legal'],
    );
    expect(
      decoded.effectiveMemoryFirewalls.last.writers
          .map((share) => '${share.kind}:${share.id}')
          .toList(),
      <String>['project:ops'],
    );
  });

  test('encodes memory firewall policy for the local daemon', () {
    final policy = memoryFirewallPolicyJson(const <MemoryFirewall>[
      MemoryFirewall(
        id: 'acme-client',
        label: 'Acme Client',
        shares: <MemoryFirewallShare>[
          MemoryFirewallShare(
            kind: 'team',
            id: 'acme-legal',
            label: 'Acme Legal',
          ),
          MemoryFirewallShare(kind: 'public', id: 'everyone', label: 'Public'),
        ],
        writers: <MemoryFirewallShare>[
          MemoryFirewallShare(kind: 'person', id: 'pat', label: 'Pat'),
        ],
      ),
    ]);

    expect(policy['default_allow'], isFalse);
    final rules = policy['firewalls'] as List<Map<String, dynamic>>;
    expect(rules.single['firewall'], 'acme-client');
    expect(
      rules.single['readers'],
      containsAll(<String>[
        'agent',
        'agent_awesome_ui',
        'acme-legal',
        'team:acme-legal',
        '*',
      ]),
    );
    expect(
      rules.single['writers'],
      containsAll(<String>['agent', 'agent_awesome_ui', 'pat', 'person:pat']),
    );
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

  test('controller exposes memory firewall audience labels', () {
    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.appSettings = const AgentAwesomeAppSettings(
      memoryFirewalls: <MemoryFirewall>[
        MemoryFirewall(
          id: 'acme-client',
          label: 'Acme Client',
          shares: <MemoryFirewallShare>[
            MemoryFirewallShare(
              kind: 'team',
              id: 'acme-legal',
              label: 'Acme Legal',
            ),
            MemoryFirewallShare(kind: 'person', id: 'pat', label: 'Pat'),
          ],
          writers: <MemoryFirewallShare>[
            MemoryFirewallShare(kind: 'person', id: 'lee', label: 'Lee'),
          ],
        ),
      ],
    );

    expect(controller.memoryFirewallLabel('acme-client'), 'Acme Client');
    expect(
      controller.memoryFirewallAudienceLabel('acme-client'),
      'Acme Legal, Pat',
    );
    expect(
      controller.memoryFirewallPickerLabel('acme-client'),
      'Acme Client / Acme Legal, Pat',
    );
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
    gateway: const GatewayRuntime(
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
    memoryDomains: const <McpServerRuntime>[],
    agentMemory: const AgentMemoryRuntime(
      actor: 'agent:test',
      readDomains: <String>['memory'],
      writeDomains: <String>['memory'],
      defaultWriteDomain: 'memory',
      allowedSensitivities: <String>['public', 'internal', 'private'],
    ),
  );
}
