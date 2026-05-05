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
    memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
    agentAppName: 'personal_pilot',
    agentUserId: 'doug',
    workspaceRoot: '/home/doug/dev/agentawesome',
    autoStartLocalServices: true,
    runtimeProfilePath:
        '/home/doug/dev/agentawesome/ui/runtime_profiles/personal_assistant.json',
  );
}
