/// Tests runtime profile parsing for harness and MCP topologies.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs runtime profile tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads profile with harness and default memory domain', () async {
    final profile = await RuntimeProfileLoader(_testConfig()).load();

    expect(profile.harness.toolConfigPath, contains('tool.local.yaml'));
    expect(profile.memoryDomains.single.id, 'memory');
    expect(profile.agentMemory.actor, 'agent:agent-awesome');
    expect(profile.agentMemory.readDomains, <String>['memory']);
    expect(profile.agentMemory.writeDomains, <String>['memory']);
    expect(profile.toJson(), isNot(contains('mcp_servers')));
    final harnessArguments = harnessArgumentsForProfile(profile);
    expect(
      harnessArguments,
      containsAllInOrder(<String>[
        '--workflow-api-addr',
        '127.0.0.1:8092',
        '--workflow-definitions',
        defaultWorkflowDefinitionsDirectoryPath(),
        '--workflow-db',
        defaultWorkflowDatabasePath(),
        '--command-data-dir',
        defaultCommandDataDirectoryPath(),
        '--command-parser-dir',
        defaultCommandParserDirectoryPath(),
      ]),
    );
    expect(
      harnessArguments.indexOf('--workflow-api-addr'),
      lessThan(harnessArguments.indexOf('--')),
    );
    expect(
      harnessArguments,
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
    expect(profile.workflow.enabled, isTrue);
    expect(profile.workflow.hostedByHarness, isTrue);
    expect(profile.workflow.autoStart, isFalse);
    expect(profile.workflow.apiBaseUrl, 'http://127.0.0.1:8092/api/workflows');
    expect(profile.workflow.mcpUrl, 'http://127.0.0.1:8092/mcp');
    final workflowArguments = workflowArgumentsForProfile(profile);
    expect(workflowArguments, isEmpty);
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
    expect(gatewayArguments, contains('--workflow-base-url'));
    expect(gatewayArguments, contains('http://127.0.0.1:8092/api/workflows'));
    expect(gatewayArguments, contains('--harness-embedded-services'));
    expect(gatewayArguments, contains('--memory-domains-json'));
    expect(gatewayArguments, contains('--memory-policy-json'));
    expect(gatewayArguments, contains('--agent-profiles-json'));
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
    final profilesJson = jsonDecode(
      gatewayArguments[gatewayArguments.indexOf('--agent-profiles-json') + 1],
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
    expect(profilesJson.single['id'], 'agent-awesome');
    expect(profilesJson.single['default_write_domain'], 'memory');
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

  test(
    'loads bundled default profile template without source workspace',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agentawesome-runtime-profile-',
      );
      addTearDown(() => root.delete(recursive: true));

      final loader = RuntimeProfileLoader(
        _testConfig(workspaceRoot: root.path),
      );
      final content = await loader.loadShippedRuntimeProfileTemplate();
      final file = File('${root.path}/agent_awesome.json');
      await file.writeAsString(content);

      final profile = await loader.loadFile(file);

      expect(profile.id, 'agent-awesome');
      expect(profile.workflow.id, 'agent-awesome-workflow');
      expect(profile.memoryDomains.single.id, 'memory');
      expect(profile.agentMemory.defaultWriteDomain, 'memory');
    },
  );

  test('loads app-managed profiles that predate workflow runtime', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-old-profile-',
    );
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/profile.json');
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'id': 'agent-awesome',
        'label': 'Agent Awesome',
        'harness': <String, dynamic>{..._harnessJson(), 'auto_start': true},
        'gateway': <String, dynamic>{..._gatewayJson(), 'auto_start': true},
        'memory_domains': <Map<String, dynamic>>[_memoryDomainJson('memory')],
        'agent_memory': <String, dynamic>{
          'actor': 'agent:test',
          'read_domains': <String>['memory'],
          'write_domains': <String>['memory'],
          'default_write_domain': 'memory',
          'allowed_sensitivities': <String>['public', 'internal', 'private'],
        },
      }),
    );

    final profile = await RuntimeProfileLoader(
      _testConfig(workspaceRoot: root.path, runtimeProfilePath: file.path),
    ).load();

    expect(profile.workflow.enabled, isTrue);
    expect(profile.workflow.hostedByHarness, isTrue);
    expect(profile.workflow.autoStart, isFalse);
    expect(profile.workflow.workingDirectory, isEmpty);
    expect(profile.workflow.packagePath, isEmpty);
    expect(
      profile.workflow.definitionsDir,
      defaultWorkflowDefinitionsDirectoryPath(),
    );
  });

  test('loads external gateway topology', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-external-profile-',
    );
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/external_gateway.json');
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'id': 'external-shared',
        'label': 'External Shared',
        'harness': <String, dynamic>{..._harnessJson(), 'auto_start': false},
        'gateway': <String, dynamic>{
          ..._gatewayJson(),
          'api_base_url': r'${AGENT_GATEWAY_BASE_URL}',
          'health_url': r'${AGENT_GATEWAY_HEALTH_URL}',
          'status_url': r'${AGENT_GATEWAY_STATUS_URL}',
          'memory_mcp_url': r'${AGENT_GATEWAY_MCP_URL}',
          'profile_id': 'shared',
          'auth_credential': 'AGENTAWESOME_GATEWAY_TOKEN',
          'auto_start': false,
        },
        'workflow': <String, dynamic>{
          ..._workflowJson(enabled: false),
          'working_directory': '',
          'package_path': '',
          'definitions_dir': '',
          'db_path': '',
        },
        'memory_domains': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'shared',
            'label': 'Shared Memory',
            'kind': 'memory',
            'endpoint': r'${AGENT_GATEWAY_MCP_URL}/shared',
            'health_url': r'${AGENT_GATEWAY_HEALTH_URL}',
            'working_directory': '',
            'package_path': '',
            'db_path': '',
            'data_dir': '',
            'arguments': <String>[],
            'auto_start': false,
            'enabled': true,
          },
        ],
        'agent_memory': <String, dynamic>{
          'actor': 'agent:shared',
          'read_domains': <String>['shared'],
          'write_domains': <String>['shared'],
          'default_write_domain': 'shared',
          'allowed_sensitivities': <String>['public', 'internal', 'private'],
        },
      }),
    );

    final profile = await RuntimeProfileLoader(
      _testConfig(
        agentGatewayBaseUrl: 'https://agent-awesome.com/api',
        autoStartLocalServices: false,
        runtimeProfilePath: file.path,
      ),
    ).load();

    expect(profile.gateway.apiBaseUrl, 'https://agent-awesome.com/api');
    expect(profile.gateway.memoryMcpUrl, 'https://agent-awesome.com/mcp');
    expect(profile.gateway.autoStart, isFalse);
    expect(profile.harness.autoStart, isFalse);
    expect(profile.gateway.profileId, 'shared');
    expect(profile.gateway.authCredential, 'AGENTAWESOME_GATEWAY_TOKEN');
    expect(profile.memoryServers.single.id, 'shared');
    expect(
      profile.memoryServers.single.endpoint,
      'https://agent-awesome.com/mcp/shared',
    );
    expect(profile.memoryServers.single.autoStart, isFalse);
    expect(profile.agentMemory.actor, 'agent:shared');
    expect(profile.agentMemory.readDomains, <String>['shared']);
  });

  test('uses one shared app model config path', () {
    expect(
      defaultModelConfigPath(),
      '${modelConfigsDirectoryPath()}/model.yaml',
    );
  });

  test('uses app-root package paths for tool and MCP configs', () {
    expect(
      toolConfigsDirectoryPath(),
      '${agentAwesomeAppConfigDirectoryPath()}/tools',
    );
    expect(
      mcpConfigsDirectoryPath(),
      '${agentAwesomeAppConfigDirectoryPath()}/mcp',
    );
    expect(
      toolPackageConfigPath('Agent Awesome!'),
      '${toolConfigsDirectoryPath()}/agent-awesome/tool.yaml',
    );
    expect(
      mcpPackageConfigPath('Memory Server!'),
      '${mcpConfigsDirectoryPath()}/memory-server/mcp.yaml',
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
        'workflow': _workflowJson(),
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
        'workflow': _workflowJson(),
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

  test('rejects agent memory grants for disabled domains', () {
    expect(
      () => RuntimeProfile.fromJson(<String, dynamic>{
        'id': 'disabled-grant',
        'label': 'Disabled Grant',
        'harness': _harnessJson(),
        'gateway': _gatewayJson(),
        'workflow': _workflowJson(),
        'memory_domains': <Map<String, dynamic>>[
          _memoryDomainJson('memory', enabled: false),
          _memoryDomainJson('shared_project', port: 8091),
        ],
        'agent_memory': <String, dynamic>{
          'actor': 'agent:test',
          'read_domains': <String>['memory'],
          'write_domains': <String>['shared_project'],
          'default_write_domain': 'shared_project',
          'allowed_sensitivities': <String>['public'],
        },
      }),
      throwsFormatException,
    );
  });

  test('rejects managed memory domains with duplicate storage paths', () {
    expect(
      () => RuntimeProfile.fromJson(<String, dynamic>{
        'id': 'duplicate-storage',
        'label': 'Duplicate Storage',
        'harness': _harnessJson(),
        'gateway': _gatewayJson(),
        'workflow': _workflowJson(),
        'memory_domains': <Map<String, dynamic>>[
          _memoryDomainJson(
            'memory',
            autoStart: true,
            dbPath: '/tmp/shared-memory.db',
            dataDir: '/tmp/memory-files',
          ),
          _memoryDomainJson(
            'shared_project',
            port: 8091,
            autoStart: true,
            dbPath: '/tmp/shared-memory.db',
            dataDir: '/tmp/project-files',
          ),
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

  test('rejects managed memory domains without launch package data', () {
    expect(
      () => RuntimeProfile.fromJson(<String, dynamic>{
        'id': 'missing-package',
        'label': 'Missing Package',
        'harness': _harnessJson(),
        'gateway': _gatewayJson(),
        'workflow': _workflowJson(),
        'memory_domains': <Map<String, dynamic>>[
          _memoryDomainJson('memory', autoStart: true, packagePath: ''),
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

  test('loads multiple user-defined memory domains', () {
    final profile = RuntimeProfile.fromJson(<String, dynamic>{
      'id': 'multi',
      'label': 'Multi Domain',
      'harness': _harnessJson(),
      'gateway': _gatewayJson(),
      'workflow': _workflowJson(),
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
        'workflow': _workflowJson(),
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
        'workflow': _workflowJson(),
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
        'workflow': _workflowJson(),
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
        'workflow': _workflowJson(),
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

/// Builds one memory-domain profile JSON fixture.
Map<String, dynamic> _memoryDomainJson(
  String id, {
  int port = 8090,
  bool autoStart = false,
  bool enabled = true,
  String workingDirectory = '/tmp/memory',
  String packagePath = './cmd/memoryd',
  String dbPath = '/tmp/memory.db',
  String dataDir = '/tmp/memory-files',
}) {
  return <String, dynamic>{
    'id': id,
    'label': 'Memory',
    'kind': 'memory',
    'endpoint': 'http://127.0.0.1:$port/mcp',
    'health_url': 'http://127.0.0.1:$port/healthz',
    'working_directory': workingDirectory,
    'package_path': packagePath,
    'db_path': dbPath,
    'data_dir': dataDir,
    'arguments': <String>[],
    'auto_start': autoStart,
    'enabled': enabled,
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

/// Builds one workflow runtime profile JSON fixture.
Map<String, dynamic> _workflowJson({bool enabled = true}) {
  return <String, dynamic>{
    'id': 'workflow',
    'label': 'Workflow',
    'api_base_url': 'http://127.0.0.1:8092/api/workflows',
    'health_url': 'http://127.0.0.1:8092/healthz',
    'working_directory': '/tmp/workflow',
    'package_path': './cmd/workflow-service',
    'definitions_dir': '/tmp/workflows',
    'db_path': '/tmp/workflow.db',
    'port': 8092,
    'auto_start': false,
    'enabled': enabled,
  };
}

/// Builds app config for runtime profile loader tests.
AppConfig _testConfig({
  String? workspaceRoot,
  String agentGatewayBaseUrl = 'http://127.0.0.1:8070/api',
  bool autoStartLocalServices = true,
  String? runtimeProfilePath,
}) {
  final uiRoot = Directory.current.path;
  final resolvedWorkspaceRoot = workspaceRoot ?? Directory.current.parent.path;
  return AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:8080/api',
    agentGatewayBaseUrl: agentGatewayBaseUrl,
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
    agentAppName: 'agent_awesome',
    agentUserId: 'doug',
    workspaceRoot: resolvedWorkspaceRoot,
    autoStartLocalServices: autoStartLocalServices,
    runtimeProfilePath:
        runtimeProfilePath ?? '$uiRoot/runtime_profiles/agent_awesome.json',
  );
}
