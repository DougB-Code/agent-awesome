/// Tests managed local service process launch planning.
library;

import 'dart:convert';

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/local_service_environment.dart';
import 'package:agentawesome_ui/app/local_services.dart';
import 'package:agentawesome_ui/app/process_supervisor.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs local service launch plan tests.
void main() {
  test('linux launch plan isolates service group and redirects output', () {
    final plan = buildManagedProcessLaunchPlan(
      executable: '/tmp/service-bin',
      arguments: const <String>['--addr', '127.0.0.1:9090'],
      outputLogPath: '/tmp/service.log',
      canStartProcessGroup: true,
      isWindows: false,
    );

    expect(plan.executable, 'setsid');
    expect(plan.ownsProcessGroup, isTrue);
    expect(plan.arguments, <String>[
      'sh',
      '-c',
      r'exec "$@" >> "$0" 2>&1',
      '/tmp/service.log',
      '/tmp/service-bin',
      '--addr',
      '127.0.0.1:9090',
    ]);
  });

  test('linux launch plan still redirects output without setsid support', () {
    final plan = buildManagedProcessLaunchPlan(
      executable: '/tmp/service-bin',
      arguments: const <String>['--flag'],
      outputLogPath: '/tmp/service.log',
      canStartProcessGroup: false,
      isWindows: false,
    );

    expect(plan.executable, 'sh');
    expect(plan.ownsProcessGroup, isFalse);
    expect(plan.arguments, <String>[
      '-c',
      r'exec "$@" >> "$0" 2>&1',
      '/tmp/service.log',
      '/tmp/service-bin',
      '--flag',
    ]);
  });

  test('windows launch plan keeps direct process command', () {
    final plan = buildManagedProcessLaunchPlan(
      executable: r'C:\service.exe',
      arguments: const <String>['--flag'],
      outputLogPath: r'C:\service.log',
      canStartProcessGroup: true,
      isWindows: true,
    );

    expect(plan.executable, r'C:\service.exe');
    expect(plan.ownsProcessGroup, isFalse);
    expect(plan.arguments, const <String>['--flag']);
  });

  test('managed service ids are scoped to the agent profile', () {
    final first = _testProfile().copyWith(id: 'agent-one');
    final second = _testProfile().copyWith(id: 'agent-two');

    expect(agentRuntimeServiceId(first, 'harness'), 'agent-one-harness');
    expect(
      agentRuntimeServiceId(first, 'harness'),
      isNot(agentRuntimeServiceId(second, 'harness')),
    );
  });

  test('managed gateway environment disables ambient Slack ingress', () {
    final environment = buildManagedGatewayEnvironment(
      config: _testConfig(),
      baseEnvironment: const <String, String>{
        'PATH': '/usr/bin',
        'SLACK_ENABLED': 'true',
        'SLACK_SOCKET_MODE': 'true',
        'SLACK_SIGNING_SECRET': 'secret',
        'SLACK_BOT_TOKEN': 'xoxb-secret',
        'SLACK_APP_TOKEN': 'xapp-secret',
        'SLACK_ALLOWED_TEAM_ID': 'T1',
        'SLACK_ALLOWED_USER_ID': 'U1',
        'SLACK_ALLOWED_CHANNEL_ID': 'C1',
      },
    );

    expect(environment['PATH'], '/usr/bin');
    expect(environment['SLACK_ENABLED'], 'false');
    expect(environment['SLACK_SOCKET_MODE'], 'false');
    expect(environment['SLACK_SIGNING_SECRET'], '');
    expect(environment['SLACK_BOT_TOKEN'], '');
    expect(environment['SLACK_APP_TOKEN'], '');
    expect(environment['SLACK_ALLOWED_TEAM_ID'], '');
    expect(environment['SLACK_ALLOWED_USER_ID'], '');
    expect(environment['SLACK_ALLOWED_CHANNEL_ID'], '');
  });

  test('local service environment preserves non-gateway Slack config', () {
    final environment = buildLocalServiceEnvironment(
      config: _testConfig(),
      baseEnvironment: const <String, String>{'SLACK_ENABLED': 'true'},
    );

    expect(environment['SLACK_ENABLED'], 'true');
  });

  test(
    'workspace managed executable detection is scoped to build profiles',
    () {
      expect(
        isWorkspaceManagedExecutablePath(
          executable: '/tmp/work/harness/build/profiles/personal/bin/harness',
          workspaceRoot: '/tmp/work',
        ),
        isTrue,
      );
      expect(
        isWorkspaceManagedExecutablePath(
          executable:
              '/tmp/work/harness/build/profiles-evil/personal/bin/harness',
          workspaceRoot: '/tmp/work',
        ),
        isFalse,
      );
      expect(
        isWorkspaceManagedExecutablePath(
          executable: '/usr/bin/unrelated',
          workspaceRoot: '/tmp/work',
        ),
        isFalse,
      );
    },
  );

  test('linux process group parser handles command names with spaces', () {
    final processGroupId = parseLinuxProcessGroupId(
      '12345 (agent awesome) S 1 12345 12345 0 -1 4194560',
    );

    expect(processGroupId, 12345);
  });

  test('process command line splitter removes trailing empty argument', () {
    final arguments = splitProcessCommandLineBytes(
      utf8.encode('/tmp/service\x00--flag\x00value\x00'),
    );

    expect(arguments, const <String>['/tmp/service', '--flag', 'value']);
  });

  test('proc net parser returns listening socket inode for matching port', () {
    final inode = listeningSocketInodeFromProcNetLine(
      '0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 '
      '00:00000000 00000000 1000 0 123456 1 0000000000000000',
      8080,
    );

    expect(inode, '123456');
    expect(
      listeningSocketInodeFromProcNetLine(
        '0: 0100007F:1F91 00000000:0000 0A 00000000:00000000 '
        '00:00000000 00000000 1000 0 123456',
        8080,
      ),
      isNull,
    );
  });

  test('startup log line includes pid, ports, binary, and log path', () {
    final line = serviceStartupLogLine(
      state: 'started',
      name: 'Agent Awesome Harness',
      pid: 123,
      executable: '/tmp/service-bin',
      ownsProcessGroup: true,
      health: Uri.parse(
        'http://127.0.0.1:8080/api/apps/app/users/user/sessions',
      ),
      arguments: const <String>[
        '--context-api-addr',
        '127.0.0.1:8081',
        '--',
        'web',
        '--port',
        '8080',
      ],
      outputLogPath: '/tmp/harness.log',
    );

    expect(line, contains('subprocess started'));
    expect(line, contains('pid=123'));
    expect(line, contains('health=127.0.0.1:8080'));
    expect(line, contains('context=127.0.0.1:8081'));
    expect(line, contains('api=:8080'));
    expect(line, contains('binary=/tmp/service-bin'));
    expect(line, contains('log=/tmp/harness.log'));
  });

  test('service local ports include health and argument listeners', () {
    final ports = serviceLocalPorts(
      health: Uri.parse(
        'http://127.0.0.1:8080/api/apps/app/users/user/sessions',
      ),
      arguments: const <String>[
        '--addr',
        '127.0.0.1:8070',
        '--context-api-addr',
        '[::1]:8081',
        '--runbook-api-addr',
        '127.0.0.1:8092',
        '--',
        'web',
        '--port',
        '8080',
      ],
    );

    expect(ports, <int>{8070, 8080, 8081, 8092});
  });

  test('closed supervisor refuses later service startup', () async {
    final processSupervisor = _testProcessSupervisor();
    final supervisor = LocalServiceSupervisor(
      config: _testConfig(),
      processSupervisor: processSupervisor,
    );

    await supervisor.close();
    final statuses = await supervisor.startRequiredServices(_testProfile());

    expect(statuses, hasLength(1));
    expect(statuses.single.state, ConnectionStateKind.disconnected);
    expect(statuses.single.message, 'Supervisor is closed');
  });
}

/// Builds a minimal app config for local service supervisor tests.
AppConfig _testConfig() {
  return const AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:8080/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:8070/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
    agentAppName: 'test',
    agentUserId: 'user',
    workspaceRoot: '/tmp/agentawesome-local-services-test',
    autoStartLocalServices: true,
    runtimeProfilePath: '',
  );
}

/// Builds a minimal agent runtime topology for local service supervisor tests.
RuntimeProfile _testProfile() {
  return const RuntimeProfile(
    id: 'test-profile',
    label: 'Test Profile',
    harness: HarnessRuntime(
      id: 'harness',
      label: 'Harness',
      apiBaseUrl: 'http://127.0.0.1:1/api',
      contextApiBaseUrl: 'http://127.0.0.1:1/api/context',
      appName: 'test',
      userId: 'user',
      workingDirectory: '/tmp/harness',
      executablePath: '/tmp/bin/agent-awesome',
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
      executablePath: '/tmp/bin/agent-gateway',
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

ProcessSupervisor _testProcessSupervisor() {
  final supervisor = ProcessSupervisor(
    logDirectory: '/tmp/agentawesome-local-services-test/logs',
    workspaceRoot: '/tmp/agentawesome-local-services-test',
  );
  addTearDown(supervisor.close);
  return supervisor;
}
