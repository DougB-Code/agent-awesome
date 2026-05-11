/// Tests structured harness tool config parsing and serialization.
library;

import 'package:agentawesome_ui/domain/tool_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs tool config document tests.
void main() {
  test('parses local exec and mcp tool settings', () {
    final document = ToolConfigDocument.parse('''
local-exec:
  enabled: true
  allow-persistent-approvals: true
  default-timeout: 10s
  default-max-output-bytes: 65536
  allowed-workdirs:
    - .
  commands:
    - name: git_status
      executable: git
      description: Show repository status.
      args:
        - status
        - --short
      approval:
        always-allow-within-workspace: false
        always-allow-command-starts-with:
          - git status
        always-allow: false
mcp:
  enabled: true
  servers:
    - name: memory
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
      headers-from-env:
        Authorization: AGENTAWESOME_GATEWAY_AUTHORIZATION
      require-confirmation-tools:
        - save_memory_candidate
      tools:
        allow:
          - search_memory
          - save_memory_candidate
''');

    expect(document.localExec.enabled, isTrue);
    expect(document.localExec.allowPersistentApprovals, isTrue);
    expect(document.localExec.defaultTimeout, '10s');
    expect(document.localExec.commands.single.name, 'git_status');
    expect(document.localExec.commands.single.args, <String>[
      'status',
      '--short',
    ]);
    expect(
      document.localExec.commands.single.approval.alwaysAllowCommandPrefixes,
      <String>['git status'],
    );
    expect(document.mcp.enabled, isTrue);
    expect(document.mcp.servers.single.name, 'memory');
    expect(document.mcp.servers.single.headersFromEnv, <String, String>{
      'Authorization': 'AGENTAWESOME_GATEWAY_AUTHORIZATION',
    });
    expect(document.mcp.servers.single.tools.allow, <String>[
      'search_memory',
      'save_memory_candidate',
    ]);
  });

  test('serializes tool settings without dropping configured fields', () {
    final document = emptyToolConfigDocument().copyWith(
      localExec: emptyToolConfigDocument().localExec.copyWith(
        enabled: true,
        defaultTimeout: '5s',
        allowedWorkdirs: const <String>['.'],
        commands: <LocalExecCommandConfig>[
          newLocalExecCommandConfig(
            name: 'git_status',
            executable: 'git',
            description: 'Show repository status.',
          ).copyWith(args: const <String>['status', '--short']),
        ],
      ),
      mcp: McpToolConfig(
        enabled: true,
        servers: <McpServerToolConfig>[
          newHttpMcpServerToolConfig(
            name: 'memory',
            endpoint: 'http://127.0.0.1:8090/mcp',
            headersFromEnv: const <String, String>{
              'Authorization': 'AGENTAWESOME_GATEWAY_AUTHORIZATION',
            },
          ).copyWith(
            tools: const McpToolFilterConfig(
              allow: <String>['list_tasks', 'create_task'],
            ),
          ),
        ],
      ),
    );

    final encoded = document.toYaml();

    expect(encoded, contains('local-exec:'));
    expect(encoded, isNot(contains('allow-persistent-approvals')));
    expect(encoded, contains('default-timeout: 5s'));
    expect(encoded, contains('name: git_status'));
    expect(encoded, contains('executable: git'));
    expect(encoded, contains('mcp:'));
    expect(encoded, contains('endpoint: http://127.0.0.1:8090/mcp'));
    expect(encoded, contains('headers-from-env:'));
    expect(
      encoded,
      contains('Authorization: AGENTAWESOME_GATEWAY_AUTHORIZATION'),
    );
    expect(encoded, contains('create_task'));
  });

  test('creates target graph-backed memory MCP tool config', () {
    final document = graphBackedMemoryToolConfig(
      serverKind: 'memory',
      serverEndpoint: 'http://127.0.0.1:8090/mcp',
      localExec: emptyToolConfigDocument().localExec,
      headersFromEnv: const <String, String>{
        'Authorization': 'AGENTAWESOME_GATEWAY_AUTHORIZATION',
      },
    );

    expect(document.mcp.enabled, isTrue);
    expect(document.mcp.servers, hasLength(1));
    expect(document.mcp.servers.single.name, 'memory');
    expect(document.mcp.servers.single.endpoint, 'http://127.0.0.1:8090/mcp');
    expect(document.mcp.servers.single.headersFromEnv, <String, String>{
      'Authorization': 'AGENTAWESOME_GATEWAY_AUTHORIZATION',
    });
    expect(document.mcp.servers.single.tools.allow, graphBackedMcpToolNames);
    expect(
      document.mcp.servers.single.tools.allow,
      contains('project_executive_summary'),
    );
    expect(
      document.mcp.servers.single.tools.allow,
      contains('explain_executive_summary_item'),
    );
    expect(
      document.mcp.servers.single.requireConfirmationTools,
      graphBackedMcpConfirmationToolNames,
    );
    expect(
      document.mcp.servers.single.requireConfirmationTools,
      contains('create_task'),
    );
    expect(
      document.mcp.servers.single.requireConfirmationTools,
      contains('update_task'),
    );
  });

  test('validates local execution command requirements', () {
    final document = emptyToolConfigDocument().copyWith(
      localExec: emptyToolConfigDocument().localExec.copyWith(enabled: true),
    );

    expect(
      toolConfigValidationError(document),
      'local-exec commands must not be empty when enabled',
    );
  });

  test('validates mcp transport requirements', () {
    final document = emptyToolConfigDocument().copyWith(
      mcp: McpToolConfig(
        enabled: true,
        servers: <McpServerToolConfig>[
          newHttpMcpServerToolConfig(name: 'memory', endpoint: 'localhost/mcp'),
        ],
      ),
    );

    expect(
      toolConfigValidationError(document),
      'mcp server "memory" endpoint must be an absolute HTTP URL',
    );
  });
}
