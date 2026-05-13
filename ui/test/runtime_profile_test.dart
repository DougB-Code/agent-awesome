/// Tests runtime profile parsing for harness and MCP topologies.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs runtime profile tests.
void main() {
  test('loads profile with harness and default memory domain', () async {
    final profile = await RuntimeProfileLoader(_testConfig()).load();

    expect(profile.harness.toolConfigPath, contains('tool.local.yaml'));
    expect(profile.memoryDomains.single.id, 'memory');
    expect(profile.agentMemory.actor, 'agent:agent-awesome');
    expect(profile.agentMemory.readDomains, <String>['memory']);
    expect(profile.agentMemory.writeDomains, <String>['memory']);
    expect(profile.toJson(), isNot(contains('mcp_servers')));
    expect(
      profile.harness.arguments,
      containsAllInOrder(<String>[
        'web',
        '--port',
        '8080',
        'api',
        '--webui_address',
        '127.0.0.1:8080',
      ]),
    );
    expect(profile.gateway.enabled, isTrue);
    expect(profile.gateway.apiBaseUrl, 'http://127.0.0.1:8070/api');
    expect(
      profile.gateway.effectiveStatusUrl,
      'http://127.0.0.1:8070/api/gateway/beta-status',
    );
    expect(
      profile.gateway.arguments,
      containsAllInOrder(<String>[
        '--harness-base-url',
        'http://127.0.0.1:8080/api',
        '--context-base-url',
        'http://127.0.0.1:8081/api/context',
        '--memory-mcp-url',
        'http://127.0.0.1:8090/mcp',
        '--model-provider-id',
        'openai',
        '--model-id',
        'gpt-mini',
      ]),
    );
    final gatewayArguments = gatewayArgumentsForProfile(profile);
    expect(gatewayArguments, contains('--memory-domains-json'));
    expect(gatewayArguments, contains('--memory-policy-json'));
    expect(gatewayArguments, contains('--memory-services-json'));
    final domainsJson = jsonDecode(
      gatewayArguments[gatewayArguments.indexOf('--memory-domains-json') + 1],
    );
    final policyJson = jsonDecode(
      gatewayArguments[gatewayArguments.indexOf('--memory-policy-json') + 1],
    );
    final servicesJson = jsonDecode(
      gatewayArguments[gatewayArguments.indexOf('--memory-services-json') + 1],
    );
    expect(domainsJson, isA<List<dynamic>>());
    expect(domainsJson.single['id'], 'memory');
    expect(domainsJson.single['endpoint'], 'http://127.0.0.1:8090/mcp');
    expect(policyJson['actor'], 'agent:agent-awesome');
    expect(
      (policyJson['read_domains'] as List<dynamic>).cast<String>(),
      <String>['memory'],
    );
    expect(servicesJson.single['domain_id'], 'memory');
    expect(servicesJson.single['auto_start'], isFalse);
    expect(profile.memoryServers.single.label, 'Memory');
    expect(profile.memoryServers.single.endpoint, 'http://127.0.0.1:8090/mcp');
    expect(
      profile.memoryServers.single.dbPath,
      '${agentAwesomeDataDirectoryPath()}/memory/memory.db',
    );
    expect(
      profile.memoryServers.single.arguments,
      containsAllInOrder(<String>[
        '--db',
        '${agentAwesomeDataDirectoryPath()}/memory/memory.db',
        '--data',
        '${agentAwesomeDataDirectoryPath()}/memory/files',
        '--firewall-policy',
        memoryFirewallPolicyPath(),
      ]),
    );
  });

  test('uses one shared app model config path', () {
    expect(
      defaultModelConfigPath(),
      '${modelConfigsDirectoryPath()}/model.yaml',
    );
  });

  test('rejects configured profile with missing harness config', () {
    expect(
      () => RuntimeProfile.fromJson(<String, dynamic>{
        'id': 'bad',
        'label': 'Bad',
        'harness': <String, dynamic>{
          'id': 'bad-harness',
          'label': 'Bad Harness',
        },
        'gateway': _gatewayJson(),
        'memory_domains': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'memory',
            'label': 'Memory',
            'kind': 'memory',
            'endpoint': 'http://127.0.0.1:8090/mcp',
            'health_url': 'http://127.0.0.1:8090/healthz',
            'working_directory': '/tmp/memory',
            'package_path': './cmd/memoryd',
            'db_path': '/tmp/memory.db',
            'data_dir': '/tmp/memory-files',
            'arguments': <String>[],
            'auto_start': false,
            'enabled': true,
          },
        ],
        'agent_memory': <String, dynamic>{
          'actor': 'agent:test',
          'read_domains': <String>['memory'],
          'write_domains': <String>['memory'],
          'default_write_domain': 'memory',
          'allowed_sensitivities': <String>['public', 'internal', 'private'],
        },
      }),
      throwsFormatException,
    );
  });

  test('rejects agent memory grants for unknown domains', () {
    expect(
      () => RuntimeProfile.fromJson(<String, dynamic>{
        'id': 'bad',
        'label': 'Bad',
        'harness': _harnessJson(),
        'gateway': _gatewayJson(),
        'memory_domains': <Map<String, dynamic>>[_memoryDomainJson('memory')],
        'agent_memory': <String, dynamic>{
          'actor': 'agent:test',
          'read_domains': <String>['other'],
          'write_domains': <String>['memory'],
          'default_write_domain': 'memory',
          'allowed_sensitivities': <String>['public', 'internal', 'private'],
        },
      }),
      throwsFormatException,
    );
  });

  test('loads multiple user-defined memory domains', () {
    final profile = RuntimeProfile.fromJson(<String, dynamic>{
      'id': 'multi',
      'label': 'Multi Domain',
      'harness': _harnessJson(),
      'gateway': _gatewayJson(),
      'memory_domains': <Map<String, dynamic>>[
        _memoryDomainJson('memory'),
        _memoryDomainJson('shared_project'),
      ],
      'agent_memory': <String, dynamic>{
        'actor': 'agent:project-planner',
        'read_domains': <String>['memory', 'shared_project'],
        'write_domains': <String>['shared_project'],
        'default_write_domain': 'shared_project',
        'allowed_sensitivities': <String>['public', 'internal'],
        'allowed_flows': <Map<String, dynamic>>[
          <String, dynamic>{'from': 'memory', 'to': 'shared_project'},
        ],
      },
    });

    expect(profile.memoryDomains.map((domain) => domain.id), <String>[
      'memory',
      'shared_project',
    ]);
    expect(profile.agentMemory.readDomains, <String>[
      'memory',
      'shared_project',
    ]);
    expect(profile.agentMemory.defaultWriteDomain, 'shared_project');
    expect(profile.agentMemory.allowedFlows.single.fromDomain, 'memory');
  });

  test('rejects memory flows to domains outside write grants', () {
    expect(
      () => RuntimeProfile.fromJson(<String, dynamic>{
        'id': 'bad-flow',
        'label': 'Bad Flow',
        'harness': _harnessJson(),
        'gateway': _gatewayJson(),
        'memory_domains': <Map<String, dynamic>>[
          _memoryDomainJson('memory'),
          _memoryDomainJson('shared_project'),
        ],
        'agent_memory': <String, dynamic>{
          'actor': 'agent:project-planner',
          'read_domains': <String>['memory', 'shared_project'],
          'write_domains': <String>['shared_project'],
          'default_write_domain': 'shared_project',
          'allowed_sensitivities': <String>['public', 'internal'],
          'allowed_flows': <Map<String, dynamic>>[
            <String, dynamic>{'from': 'shared_project', 'to': 'memory'},
          ],
        },
      }),
      throwsFormatException,
    );
  });

  test('rejects duplicate memory domain ids', () {
    expect(
      () => RuntimeProfile.fromJson(<String, dynamic>{
        'id': 'bad',
        'label': 'Bad',
        'harness': _harnessJson(),
        'gateway': _gatewayJson(),
        'memory_domains': <Map<String, dynamic>>[
          _memoryDomainJson('memory'),
          _memoryDomainJson('memory'),
        ],
        'agent_memory': <String, dynamic>{
          'actor': 'agent:test',
          'read_domains': <String>['memory'],
          'write_domains': <String>['memory'],
          'default_write_domain': 'memory',
          'allowed_sensitivities': <String>['public'],
        },
      }),
      throwsFormatException,
    );
  });

  test('rejects profiles without a gateway boundary', () {
    expect(
      () => RuntimeProfile.fromJson(<String, dynamic>{
        'id': 'bad',
        'label': 'Bad',
        'harness': _harnessJson(),
        'memory_domains': <Map<String, dynamic>>[_memoryDomainJson('memory')],
        'agent_memory': <String, dynamic>{
          'actor': 'agent:test',
          'read_domains': <String>['memory'],
          'write_domains': <String>['memory'],
          'default_write_domain': 'memory',
          'allowed_sensitivities': <String>['public'],
        },
      }),
      throwsFormatException,
    );
  });

  test('rejects disabled gateway profiles', () {
    expect(
      () => RuntimeProfile.fromJson(<String, dynamic>{
        'id': 'bad',
        'label': 'Bad',
        'harness': _harnessJson(),
        'gateway': _gatewayJson(enabled: false),
        'memory_domains': <Map<String, dynamic>>[_memoryDomainJson('memory')],
        'agent_memory': <String, dynamic>{
          'actor': 'agent:test',
          'read_domains': <String>['memory'],
          'write_domains': <String>['memory'],
          'default_write_domain': 'memory',
          'allowed_sensitivities': <String>['public'],
        },
      }),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _harnessJson() {
  return <String, dynamic>{
    'id': 'harness',
    'label': 'Harness',
    'api_base_url': 'http://127.0.0.1:8080/api',
    'context_api_base_url': 'http://127.0.0.1:8081/api/context',
    'app_name': 'agent_awesome',
    'user_id': 'doug',
    'working_directory': '/tmp/harness',
    'package_path': './cmd/agent-awesome',
    'model_config': '/tmp/model.yaml',
    'agent_config': '/tmp/agent.yaml',
    'tool_config': '/tmp/tool.yaml',
    'port': 8080,
    'auto_start': false,
  };
}

Map<String, dynamic> _memoryDomainJson(String id) {
  return <String, dynamic>{
    'id': id,
    'label': 'Memory',
    'kind': 'memory',
    'endpoint': 'http://127.0.0.1:8090/mcp',
    'health_url': 'http://127.0.0.1:8090/healthz',
    'working_directory': '/tmp/memory',
    'package_path': './cmd/memoryd',
    'db_path': '/tmp/memory.db',
    'data_dir': '/tmp/memory-files',
    'arguments': <String>[],
    'auto_start': false,
    'enabled': true,
  };
}

Map<String, dynamic> _gatewayJson({bool enabled = true}) {
  return <String, dynamic>{
    'id': 'gateway',
    'label': 'Gateway',
    'api_base_url': 'http://127.0.0.1:8070/api',
    'health_url': 'http://127.0.0.1:8070/healthz',
    'working_directory': '/tmp/gateway',
    'package_path': './cmd/agent-gateway',
    'harness_base_url': 'http://127.0.0.1:8080/api',
    'context_base_url': 'http://127.0.0.1:8081/api/context',
    'memory_mcp_url': 'http://127.0.0.1:8090/mcp',
    'app_name': 'agent_awesome',
    'user_id': 'doug',
    'port': 8070,
    'auto_start': false,
    'enabled': enabled,
  };
}

AppConfig _testConfig() {
  final uiRoot = Directory.current.path;
  final workspaceRoot = Directory.current.parent.path;
  return AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:8080/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:8070/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
    agentAppName: 'agent_awesome',
    agentUserId: 'doug',
    workspaceRoot: workspaceRoot,
    autoStartLocalServices: true,
    runtimeProfilePath: '$uiRoot/runtime_profiles/agent_awesome.json',
  );
}
