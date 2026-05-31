/// Tests structured harness tool config parsing and serialization.
library;

import 'dart:io';

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
  commands:
    - name: git
      executable: git
      description: Run documented Git CLI subcommands.
      installation:
        verified: true
        checked-at: 2026-05-25T12:00:00Z
        executable: git
        path: /usr/bin/git
        version: git version 2.45.0
      surface:
        global-flags:
          - name: -C
            description: Run as if Git started in the given path.
        subcommands:
          - name: status
            description: Show working tree status.
            flags:
              - name: --short
                description: Use short status output.
          - name: create
            description: Create Kubernetes resources.
            subcommands:
              - name: secret
                description: Create a secret.
                subcommands:
                  - name: docker-registry
                    description: Create a Docker registry secret.
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
node-presets:
  - id: go_build_all
    label: Go build all
    surface: command
    action: command.execute
    arguments:
      template_id: go_build_all
validations:
  - id: go_build_all_success
    label: Go build success
    mode: mocked
    target:
      type: runbook-node
      preset-id: go_build_all
    expected:
      status: succeeded
''');

    expect(document.localExec.enabled, isTrue);
    expect(document.localExec.defaultTimeout, '10s');
    expect(document.localExec.commands.single.name, 'git');
    expect(document.localExec.commands.single.installation.verified, isTrue);
    expect(
      document.localExec.commands.single.installation.path,
      '/usr/bin/git',
    );
    expect(
      document.localExec.commands.single.surface.globalFlags.single.name,
      '-C',
    );
    expect(
      document.localExec.commands.single.surface.subcommands
          .firstWhere((item) => item.name == 'status')
          .name,
      'status',
    );
    expect(
      document.localExec.commands.single.surface.subcommands
          .firstWhere((item) => item.name == 'status')
          .flags
          .single
          .name,
      '--short',
    );
    expect(
      document
          .localExec
          .commands
          .single
          .surface
          .subcommands[1]
          .subcommands
          .single
          .subcommands
          .single
          .name,
      'docker-registry',
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
    expect(document.nodePresets.single.action, 'command.execute');
    expect(
      document.nodePresets.single.arguments['template_id'],
      'go_build_all',
    );
    expect(document.validations.single.target.presetId, 'go_build_all');
  });

  test('adds approved MCP tool to unambiguous server config', () {
    final document = ToolConfigDocument.parse('''
mcp:
  enabled: true
  servers:
    - name: memory
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
      require-confirmation-tools:
        - remember
      tools:
        allow:
          - remember
          - search_memory
''');

    final update = toolConfigWithApprovedMcpTool(
      document: document,
      toolName: 'create_task',
    );

    expect(update.changed, isTrue);
    expect(
      update.document.mcp.servers.single.requireConfirmationTools,
      <String>['remember', 'create_task'],
    );
    expect(update.document.mcp.servers.single.tools.allow, <String>[
      'remember',
      'search_memory',
      'create_task',
    ]);
    expect(toolConfigValidationError(update.document), isEmpty);
  });

  test('skips approved MCP tool when the target server is ambiguous', () {
    final document = ToolConfigDocument.parse('''
mcp:
  enabled: true
  servers:
    - name: memory
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
      tools:
        allow:
          - remember
    - name: project
      transport: streamable-http
      endpoint: http://127.0.0.1:8091/mcp
      tools:
        allow:
          - remember
''');

    final update = toolConfigWithApprovedMcpTool(
      document: document,
      toolName: 'remember',
    );

    expect(update.changed, isFalse);
    expect(update.reason, 'mcp server is ambiguous');
    expect(update.document, same(document));
  });

  test('adds approved MCP tool to explicit server when multiple match', () {
    final document = ToolConfigDocument.parse('''
mcp:
  enabled: true
  servers:
    - name: memory
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
      tools:
        allow:
          - remember
    - name: project
      transport: streamable-http
      endpoint: http://127.0.0.1:8091/mcp
      tools:
        allow:
          - remember
''');

    final update = toolConfigWithApprovedMcpTool(
      document: document,
      toolName: 'create_task',
      serverName: 'project',
    );

    expect(update.changed, isTrue);
    expect(update.document.mcp.servers[0].requireConfirmationTools, isEmpty);
    expect(update.document.mcp.servers[1].requireConfirmationTools, <String>[
      'create_task',
    ]);
  });

  test('parses shipped Linux utility operations for UI editing', () {
    final file = File('${_repoRoot().path}/harness/tool.yaml');
    final document = ToolConfigDocument.parse(file.readAsStringSync());
    final commands = document.localExec.commands;
    final names = commands.map((command) => command.name).toList();

    expect(document.extra['name'], 'Linux Tools');
    expect(names, <String>[
      'curl',
      'jq',
      'yq',
      'pdftotext',
      'libreoffice',
      'rg',
      'find',
      'grep',
      'tar',
      'du',
      'df',
      'ps',
      'netstat',
      'kubectl',
    ]);
    expect(commands, everyElement(isA<LocalExecCommandConfig>()));
    final kubectl = commands.firstWhere((command) => command.name == 'kubectl');
    expect(
      kubectl.surface.subcommands.map((item) => item.name),
      contains('create'),
    );
    expect(
      kubectl.surface.subcommands
          .firstWhere((item) => item.name == 'create')
          .subcommands
          .firstWhere((item) => item.name == 'secret')
          .subcommands
          .map((item) => item.name),
      contains('docker-registry'),
    );
    expect(commands.every((command) => command.operations.isNotEmpty), isTrue);
    expect(document.validations.length, 60);
    expect(
      document.validations.where(
        (validation) => validation.target.type == 'command-operation',
      ),
      hasLength(20),
    );
    expect(
      document.validations.where(
        (validation) => validation.target.type == 'agent-tool-call',
      ),
      hasLength(20),
    );
    expect(
      document.validations.where(
        (validation) => validation.target.type == 'runbook-node',
      ),
      hasLength(20),
    );
    expect(
      commands
          .expand((command) => command.operations)
          .map((operation) => operation.output.format),
      containsAll(<String>['text', 'json']),
    );
  });

  test('serializes tool settings without dropping configured fields', () {
    final document = emptyToolConfigDocument().copyWith(
      localExec: emptyToolConfigDocument().localExec.copyWith(
        enabled: true,
        defaultTimeout: '5s',
        commands: <LocalExecCommandConfig>[
          newLocalExecCommandConfig(
            name: 'git',
            executable: 'git',
            description: 'Run documented Git CLI subcommands.',
          ).copyWith(
            installation: const LocalExecInstallationConfig(
              verified: true,
              checkedAt: '2026-05-25T12:00:00Z',
              executable: 'git',
              path: '/usr/bin/git',
              version: 'git version 2.45.0',
              error: '',
            ),
            surface: const LocalExecCommandSurfaceConfig(
              globalFlags: <LocalExecCommandFlagConfig>[
                LocalExecCommandFlagConfig(
                  name: '-C',
                  description: 'Run as if Git started in the given path.',
                ),
              ],
              subcommands: <LocalExecSubcommandConfig>[
                LocalExecSubcommandConfig(
                  name: 'status',
                  description: 'Show working tree status.',
                  flags: <LocalExecCommandFlagConfig>[
                    LocalExecCommandFlagConfig(
                      name: '--short',
                      description: 'Use short status output.',
                    ),
                  ],
                  subcommands: <LocalExecSubcommandConfig>[],
                ),
                LocalExecSubcommandConfig(
                  name: 'create',
                  description: 'Create Kubernetes resources.',
                  flags: <LocalExecCommandFlagConfig>[],
                  subcommands: <LocalExecSubcommandConfig>[
                    LocalExecSubcommandConfig(
                      name: 'secret',
                      description: 'Create a secret.',
                      flags: <LocalExecCommandFlagConfig>[],
                      subcommands: <LocalExecSubcommandConfig>[
                        LocalExecSubcommandConfig(
                          name: 'docker-registry',
                          description: 'Create a Docker registry secret.',
                          flags: <LocalExecCommandFlagConfig>[],
                          subcommands: <LocalExecSubcommandConfig>[],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            operations: const <LocalExecOperationConfig>[
              LocalExecOperationConfig(
                name: 'status',
                description: 'Read repository status.',
                args: <String>['status', '--short'],
                inputSchema: <String, dynamic>{},
                output: LocalExecOperationOutputConfig(
                  format: 'text',
                  source: 'stdout',
                ),
                outputSchema: <String, dynamic>{},
                timeout: '',
                maxOutputBytes: 0,
              ),
            ],
          ),
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
    expect(encoded, contains('name: git'));
    expect(encoded, contains('executable: git'));
    expect(encoded, contains('installation:'));
    expect(encoded, contains('verified: true'));
    expect(encoded, contains('checked-at: "2026-05-25T12:00:00Z"'));
    expect(encoded, contains('path: /usr/bin/git'));
    expect(encoded, contains('surface:'));
    expect(encoded, contains('global-flags:'));
    expect(encoded, contains('subcommands:'));
    expect(encoded, contains('docker-registry'));
    expect(encoded, contains('operations:'));
    expect(encoded, contains('name: status'));
    expect(encoded, contains('format: text'));
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
          executablePath: '/tmp/bin/memoryd',
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

  test('adds runbook MCP server when runbook runtime is enabled', () {
    final document = graphBackedMemoryToolConfigForDomains(
      memoryDomains: const <McpServerRuntime>[
        McpServerRuntime(
          id: 'memory',
          label: 'Memory',
          kind: 'memory',
          endpoint: 'http://127.0.0.1:8090/mcp',
          healthUrl: 'http://127.0.0.1:8090/healthz',
          workingDirectory: '/tmp/memory',
          executablePath: '/tmp/bin/memoryd',
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
      runbook: const RunbookRuntime(
        id: 'runbook',
        label: 'Runbook',
        apiBaseUrl: 'http://127.0.0.1:8092/api/runbooks',
        healthUrl: 'http://127.0.0.1:8092/healthz',
        workingDirectory: '/tmp/runbook',
        executablePath: '/tmp/bin/runbook-service',
        definitionsDir: '/tmp/runbooks',
        dbPath: '/tmp/runbook.db',
        port: 8092,
        autoStart: false,
        enabled: true,
      ),
      localExec: emptyToolConfigDocument().localExec,
    );

    final runbookServer = document.mcp.servers.firstWhere(
      (server) => server.name == 'runbook',
    );
    expect(runbookServer.endpoint, 'http://127.0.0.1:8092/mcp');
    expect(runbookServer.tools.allow, runbookMcpToolNames);
  });

  test(
    'adds generic source-control MCP server from agent runtime topology',
    () {
      final document = graphBackedMemoryToolConfigForDomains(
        memoryDomains: const <McpServerRuntime>[
          McpServerRuntime(
            id: 'memory',
            label: 'Memory',
            kind: 'memory',
            endpoint: 'http://127.0.0.1:8090/mcp',
            healthUrl: 'http://127.0.0.1:8090/healthz',
            workingDirectory: '/tmp/memory',
            executablePath: '/tmp/bin/memoryd',
            dbPath: '/tmp/memory.db',
            dataDir: '/tmp/memory-files',
            arguments: <String>[],
            autoStart: false,
            enabled: true,
          ),
        ],
        mcpServers: const <McpServerRuntime>[
          McpServerRuntime(
            id: 'sourcecontrol',
            label: 'Source Control',
            kind: 'sourcecontrol',
            endpoint: 'http://127.0.0.1:8095/mcp',
            healthUrl: 'http://127.0.0.1:8095/healthz',
            workingDirectory: '/tmp/sourcecontrol',
            executablePath: '/tmp/bin/sourcecontrold',
            dbPath: '',
            dataDir: '',
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
        localExec: emptyToolConfigDocument().localExec,
      );

      final sourceControl = document.mcp.servers.firstWhere(
        (server) => server.name == 'sourcecontrol',
      );
      expect(sourceControl.endpoint, 'http://127.0.0.1:8095/mcp');
      expect(sourceControl.tools.allow, sourceControlMcpToolNames);
    },
  );

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
          executablePath: '/tmp/bin/memoryd',
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
          executablePath: '/tmp/bin/memoryd',
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

  test('validates agent tool-call command targets', () {
    final document = ToolConfigDocument.parse('''
local-exec:
  enabled: true
  commands:
    - name: rg
      executable: rg
      description: Search text.
      operations:
        - name: search_text
          description: Search a path for text.
          args:
            - "{{pattern}}"
            - "{{path}}"
validations:
  - id: agent_uses_rg
    mode: mocked
    prompt: Find TODO comments.
    target:
      type: agent-tool-call
      command: rg
      operation: search_text
    mocks:
      agent.tool_call:
        status: succeeded
''');

    expect(toolConfigValidationError(document), isEmpty);
  });

  test('validates runbook node command targets', () {
    final document = ToolConfigDocument.parse('''
local-exec:
  enabled: true
  commands:
    - name: rg
      executable: rg
      description: Search text.
      operations:
        - name: search_text
          description: Search a path for text.
          args:
            - "{{pattern}}"
            - "{{path}}"
validations:
  - id: runbook_uses_rg
    mode: mocked
    target:
      type: runbook-node
      command: rg
      operation: search_text
    mocks:
      command.execute:
        status: succeeded
''');

    expect(toolConfigValidationError(document), isEmpty);
  });

  test('validates runbook node mcp targets', () {
    final document = ToolConfigDocument.parse('''
mcp:
  enabled: false
  servers:
    - name: memory
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
      tools:
        allow:
          - search_memory
validations:
  - id: runbook_uses_memory
    mode: mocked
    target:
      type: runbook-node
      mcp-server: memory
      mcp-tool: search_memory
    mocks:
      mcp.call:
        status: succeeded
''');

    expect(toolConfigValidationError(document), isEmpty);
  });

  test('rejects mixed runbook node targets', () {
    final document = ToolConfigDocument.parse('''
local-exec:
  enabled: true
  commands:
    - name: rg
      executable: rg
      description: Search text.
      operations:
        - name: search_text
          description: Search a path for text.
          args:
            - "{{pattern}}"
            - "{{path}}"
node-presets:
  - id: rg_search
    label: RG search
    action: command.execute
    arguments:
      template_id: rg.search_text
validations:
  - id: mixed_runbook_target
    mode: mocked
    target:
      type: runbook-node
      preset-id: rg_search
      command: rg
      operation: search_text
    mocks:
      command.execute:
        status: succeeded
''');

    expect(
      toolConfigValidationError(document),
      'validation "mixed_runbook_target" runbook-node target must choose preset-id, command-operation, or mcp-tool',
    );
  });

  test('rejects unknown command preset templates', () {
    final document = ToolConfigDocument.parse('''
local-exec:
  enabled: true
  commands:
    - name: rg
      executable: rg
      description: Search text.
      operations:
        - name: search_text
          description: Search a path for text.
node-presets:
  - id: rg_missing
    label: RG missing
    action: command.execute
    arguments:
      template_id: rg.missing
''');

    expect(
      toolConfigValidationError(document),
      'node preset "rg_missing" references unknown command template "rg.missing"',
    );
  });

  test('accepts legacy command preset templates', () {
    final document = ToolConfigDocument.parse('''
local-exec:
  enabled: true
  commands:
    - name: go_build_all
      executable: go
      description: Build every package.
      args:
        - build
        - ./...
node-presets:
  - id: go_build_all
    label: Go build all
    action: command.execute
    arguments:
      template_id: go_build_all
''');

    expect(toolConfigValidationError(document), isEmpty);
  });

  test('rejects unknown mcp preset tools', () {
    final document = ToolConfigDocument.parse('''
mcp:
  enabled: true
  servers:
    - name: memory
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
      tools:
        allow:
          - remember
node-presets:
  - id: memory_missing
    label: Memory missing
    action: mcp.call
    arguments:
      server_id: memory
      tool: missing
''');

    expect(
      toolConfigValidationError(document),
      'node preset "memory_missing" references unknown MCP tool "missing" on server "memory"',
    );
  });

  test('rejects unknown agent tool-call command targets', () {
    final document = ToolConfigDocument.parse('''
local-exec:
  enabled: true
  commands:
    - name: rg
      executable: rg
      description: Search text.
      operations:
        - name: search_text
          description: Search a path for text.
          args:
            - "{{pattern}}"
            - "{{path}}"
validations:
  - id: agent_uses_missing
    mode: mocked
    prompt: Find TODO comments.
    target:
      type: agent-tool-call
      command: rg
      operation: missing
    mocks:
      agent.tool_call:
        status: succeeded
''');

    expect(
      toolConfigValidationError(document),
      'validation "agent_uses_missing" references unknown operation "missing" on command "rg"',
    );
  });
}

/// Returns the repository root when tests run from either repo or ui.
Directory _repoRoot() {
  var current = Directory.current;
  while (true) {
    if (File('${current.path}/harness/tool.yaml').existsSync() &&
        File('${current.path}/ui/pubspec.yaml').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('repository root not found from ${Directory.current}');
    }
    current = parent;
  }
}
