/// Tests structured harness tool config parsing and serialization.
library;

import 'package:agentawesome_ui/domain/tool_config.dart';
import 'package:agentawesome_ui/domain/runtime_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs tool config document tests.
void main() {
  test('parses local exec and mcp tool settings', () {
    final document = ToolConfigDocument.parse('''
local-exec:
  enabled: true
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
    expect(document.localExec.defaultTimeout, '10s');
    expect(document.localExec.commands.single.name, 'git_status');
    expect(document.localExec.commands.single.args, <String>[
      'status',
      '--short',
    ]);
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
    final document = graphBackedMemoryToolConfigForDomains(
      memoryDomains: const <McpServerRuntime>[
        McpServerRuntime(
          id: 'memory',
          label: 'Memory',
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
      ],
      agentMemory: const AgentMemoryRuntime(
        actor: 'agent:test',
        readDomains: <String>['memory'],
        writeDomains: <String>['memory'],
        defaultWriteDomain: 'memory',
        allowedSensitivities: <String>['public', 'internal', 'private'],
      ),
      localExec: emptyToolConfigDocument().localExec,
    );

    expect(document.mcp.enabled, isTrue);
    expect(document.mcp.servers, hasLength(1));
    expect(document.mcp.servers.single.name, 'memory_memory');
    expect(document.mcp.servers.single.endpoint, 'http://127.0.0.1:8090/mcp');
    expect(document.mcp.servers.single.tools.allow, graphBackedMcpToolNames);
    expect(document.extra['memory'], isA<Map<String, dynamic>>());
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

  test('adds workflow MCP server when workflow runtime is enabled', () {
    final document = graphBackedMemoryToolConfigForDomains(
      memoryDomains: const <McpServerRuntime>[
        McpServerRuntime(
          id: 'memory',
          label: 'Memory',
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
      ],
      agentMemory: const AgentMemoryRuntime(
        actor: 'agent:test',
        readDomains: <String>['memory'],
        writeDomains: <String>['memory'],
        defaultWriteDomain: 'memory',
        allowedSensitivities: <String>['public'],
      ),
      workflow: const WorkflowRuntime(
        id: 'workflow',
        label: 'Workflow',
        apiBaseUrl: 'http://127.0.0.1:8092/api/workflows',
        healthUrl: 'http://127.0.0.1:8092/healthz',
        workingDirectory: '/tmp/workflow',
        packagePath: './cmd/workflow-service',
        definitionsDir: '/tmp/workflows',
        dbPath: '/tmp/workflow.db',
        port: 8092,
        autoStart: false,
        enabled: true,
      ),
      localExec: emptyToolConfigDocument().localExec,
    );

    final workflowServer = document.mcp.servers.firstWhere(
      (server) => server.name == 'workflow',
    );
    expect(workflowServer.endpoint, 'http://127.0.0.1:8092/mcp');
    expect(workflowServer.tools.allow, workflowMcpToolNames);
  });

  test('limits model-exposed tools when profile reads multiple domains', () {
    final document = graphBackedMemoryToolConfigForDomains(
      memoryDomains: const <McpServerRuntime>[
        McpServerRuntime(
          id: 'memory',
          label: 'Memory',
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
          id: 'shared_project',
          label: 'Shared Project',
          kind: 'memory',
          endpoint: 'http://127.0.0.1:8091/mcp',
          healthUrl: 'http://127.0.0.1:8091/healthz',
          workingDirectory: '/tmp/memory',
          packagePath: './cmd/memoryd',
          dbPath: '/tmp/shared-project.db',
          dataDir: '/tmp/shared-project-files',
          arguments: <String>[],
          autoStart: false,
          enabled: true,
        ),
      ],
      agentMemory: const AgentMemoryRuntime(
        actor: 'agent:project-planner',
        readDomains: <String>['memory', 'shared_project'],
        writeDomains: <String>['shared_project'],
        defaultWriteDomain: 'shared_project',
        allowedSensitivities: <String>['public', 'internal'],
      ),
      localExec: emptyToolConfigDocument().localExec,
    );

    final memory = document.extra['memory']! as Map<String, dynamic>;
    expect(document.mcp.servers.single.name, 'memory_shared_project');
    expect(
      document.mcp.servers.single.tools.allow,
      graphBackedMcpReadOnlyToolNames,
    );
    expect(document.mcp.servers.single.requireConfirmationTools, isEmpty);
    expect(memory['default-write-domain'], 'shared_project');
    expect(memory['write-domains'], <String>['shared_project']);
    expect(memory['read-domains'], hasLength(2));
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
