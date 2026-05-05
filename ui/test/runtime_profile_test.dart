/// Tests runtime profile parsing for harness and MCP topologies.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs runtime profile tests.
void main() {
  test('loads profile with harness and multiple MCP kinds', () async {
    final profile = await RuntimeProfileLoader(_testConfig()).load();

    expect(profile.harness.toolConfigPath, contains('tool.yaml'));
    expect(profile.memoryServerConfigPath, contains('/memory/'));
    expect(profile.toJson(), isNot(contains('mcp_servers')));
    expect(profile.toJson(), isNot(contains('mcp_server_configs')));
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
    expect(profile.gateway?.enabled, isTrue);
    expect(profile.gateway?.apiBaseUrl, 'http://127.0.0.1:8070/api');
    expect(
      profile.gateway?.arguments,
      containsAllInOrder(<String>[
        '--harness-base-url',
        'http://127.0.0.1:8080/api',
        '--memory-mcp-url',
        'http://127.0.0.1:8090/mcp',
      ]),
    );
    expect(profile.memoryServers.single.label, 'Personal Memory');
    expect(profile.memoryServers.single.endpoint, 'http://127.0.0.1:8090/mcp');
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
        'memory_server_config': '/tmp/memory.json',
      }),
      throwsFormatException,
    );
  });
}

AppConfig _testConfig() {
  return const AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:8080/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:8070/api',
    memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
    agentAppName: 'personal_pilot',
    agentUserId: 'doug',
    workspaceRoot: '/home/doug/dev/agentawesome/agent',
    autoStartLocalServices: true,
    runtimeProfilePath:
        '/home/doug/dev/agentawesome/agent/ui/runtime_profiles/personal_assistant.json',
  );
}
