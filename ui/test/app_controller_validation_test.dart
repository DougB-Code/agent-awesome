/// Tests validation command construction for app-controller workflows.
library;

import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/process_supervisor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs validation command helper tests.
void main() {
  test('builds strict tool validation command arguments', () {
    final arguments = buildToolValidationCommandArguments(
      toolPath: '/tmp/tool.yaml',
      validationId: ' curl_http_get ',
      requireAssertions: true,
      requireCoverage: true,
      requireInputSchemas: true,
    );

    expect(arguments, <String>[
      'tools',
      'validate',
      '--tool',
      '/tmp/tool.yaml',
      '--validation',
      'curl_http_get',
      '--require-assertions',
      '--require-coverage',
      '--require-input-schemas',
      '--json',
    ]);
  });

  test('builds tool validation command arguments with live agent runtime', () {
    final arguments = buildToolValidationCommandArguments(
      toolPath: '/tmp/tool.yaml',
      agentPath: '/tmp/agent.yaml',
      modelPath: '/tmp/model.yaml',
      validationId: ' agent_uses_rg ',
    );

    expect(arguments, <String>[
      'tools',
      'validate',
      '--tool',
      '/tmp/tool.yaml',
      '--agent',
      '/tmp/agent.yaml',
      '--model',
      '/tmp/model.yaml',
      '--validation',
      'agent_uses_rg',
      '--json',
    ]);
  });

  test('builds filtered tool validation command arguments', () {
    final arguments = buildToolValidationCommandArguments(
      toolPath: '/tmp/tool.yaml',
      mode: ' mocked ',
    );

    expect(arguments, <String>[
      'tools',
      'validate',
      '--tool',
      '/tmp/tool.yaml',
      '--mode',
      'mocked',
      '--json',
    ]);
  });

  test('builds multi-scenario tool validation command arguments', () {
    final arguments = buildToolValidationCommandArguments(
      toolPath: '/tmp/tool.yaml',
      validationIds: const <String>[
        ' curl_http_get_command ',
        'curl_http_get_agent',
      ],
      mode: 'all',
    );

    expect(arguments, <String>[
      'tools',
      'validate',
      '--tool',
      '/tmp/tool.yaml',
      '--validation',
      'curl_http_get_command',
      '--validation',
      'curl_http_get_agent',
      '--json',
    ]);
  });

  test('builds strict agent validation command arguments', () {
    final arguments = buildAgentValidationCommandArguments(
      agentPath: '/tmp/agent.yaml',
      toolPath: '/tmp/tool.yaml',
      validationId: ' asks_for_context ',
      requireValidations: true,
      requireAssertions: true,
      requireToolCalls: true,
      requireToolContracts: true,
    );

    expect(arguments, <String>[
      'agents',
      'validate',
      '--agent',
      '/tmp/agent.yaml',
      '--tool',
      '/tmp/tool.yaml',
      '--validation',
      'asks_for_context',
      '--require-validations',
      '--require-assertions',
      '--require-tool-calls',
      '--require-tool-contracts',
      '--json',
    ]);
  });

  test('builds live agent validation command arguments', () {
    final arguments = buildAgentValidationCommandArguments(
      agentPath: '/tmp/agent.yaml',
      validationId: ' live_check ',
      live: true,
      modelPath: '/tmp/model.yaml',
      toolPath: '/tmp/tool.yaml',
    );

    expect(arguments, <String>[
      'agents',
      'validate',
      '--agent',
      '/tmp/agent.yaml',
      '--live',
      '--model',
      '/tmp/model.yaml',
      '--tool',
      '/tmp/tool.yaml',
      '--validation',
      'live_check',
      '--json',
    ]);
  });

  test('builds filtered agent validation command arguments', () {
    final arguments = buildAgentValidationCommandArguments(
      agentPath: '/tmp/agent.yaml',
      mode: ' mocked ',
    );

    expect(arguments, <String>[
      'agents',
      'validate',
      '--agent',
      '/tmp/agent.yaml',
      '--mode',
      'mocked',
      '--json',
    ]);
  });

  test('builds strict library validation command arguments', () {
    final arguments = buildLibraryValidationCommandArguments(
      rootPath: '.',
      agentDirectory: 'agents',
      toolDirectory: 'tools',
      requireAgentValidations: true,
      requireAgentAssertions: true,
      requireAgentToolCalls: true,
      requireAgentToolContracts: true,
      requireToolInputSchemas: true,
      requireToolCoverage: true,
      requireToolAssertions: true,
    );

    expect(arguments, <String>[
      'library',
      'validate',
      '--root',
      '.',
      '--agent-dir',
      'agents',
      '--tool-dir',
      'tools',
      '--mcp-dir',
      'mcp',
      '--require-agent-validations',
      '--require-agent-assertions',
      '--require-agent-tool-calls',
      '--require-agent-tool-contracts',
      '--require-tool-input-schemas',
      '--require-tool-coverage',
      '--require-tool-assertions',
      '--json',
    ]);
  });

  test('builds filtered library validation command arguments', () {
    final arguments = buildLibraryValidationCommandArguments(
      rootPath: '.',
      agentDirectory: 'agents',
      toolDirectory: 'tools',
      agentMode: ' live ',
      toolMode: ' mocked ',
    );

    expect(arguments, <String>[
      'library',
      'validate',
      '--root',
      '.',
      '--agent-dir',
      'agents',
      '--tool-dir',
      'tools',
      '--mcp-dir',
      'mcp',
      '--agent-mode',
      'live',
      '--tool-mode',
      'mocked',
      '--json',
    ]);
  });

  test('builds live library agent validation command arguments', () {
    final arguments = buildLibraryValidationCommandArguments(
      rootPath: '.',
      agentDirectory: 'agents',
      toolDirectory: 'tools',
      liveAgents: true,
      modelPath: '/tmp/model.yaml',
      runtimeToolPath: '/tmp/runtime-tool.yaml',
    );

    expect(arguments, <String>[
      'library',
      'validate',
      '--root',
      '.',
      '--agent-dir',
      'agents',
      '--tool-dir',
      'tools',
      '--mcp-dir',
      'mcp',
      '--live-agents',
      '--model',
      '/tmp/model.yaml',
      '--runtime-tool',
      '/tmp/runtime-tool.yaml',
      '--json',
    ]);
  });

  test('builds live library tool validation runtime arguments', () {
    final arguments = buildLibraryValidationCommandArguments(
      rootPath: '.',
      agentDirectory: 'agents',
      toolDirectory: 'tools',
      toolMode: 'live',
      runtimeAgentPath: '/tmp/agent.yaml',
    );

    expect(arguments, <String>[
      'library',
      'validate',
      '--root',
      '.',
      '--agent-dir',
      'agents',
      '--tool-dir',
      'tools',
      '--mcp-dir',
      'mcp',
      '--tool-mode',
      'live',
      '--runtime-agent',
      '/tmp/agent.yaml',
      '--json',
    ]);
  });

  test('builds agent-only library validation command arguments', () {
    final arguments = buildLibraryValidationCommandArguments(
      rootPath: '/tmp/library',
      agentDirectory: 'agents',
      toolDirectory: '',
      mcpDirectory: '',
      requireAgentValidations: true,
      requireAgentAssertions: true,
    );

    expect(arguments, <String>[
      'library',
      'validate',
      '--root',
      '/tmp/library',
      '--agent-dir',
      'agents',
      '--tool-dir',
      '',
      '--mcp-dir',
      '',
      '--require-agent-validations',
      '--require-agent-assertions',
      '--json',
    ]);
  });

  test('builds single-file library validation command arguments', () {
    final arguments = buildLibraryValidationCommandArguments(
      rootPath: '/tmp/library',
      agentPath: 'agent.yaml',
      agentDirectory: 'agents',
      toolPath: 'tool.yaml',
      toolDirectory: 'tools',
      requireAgentToolContracts: true,
    );

    expect(arguments, <String>[
      'library',
      'validate',
      '--root',
      '/tmp/library',
      '--agent',
      'agent.yaml',
      '--tool',
      'tool.yaml',
      '--require-agent-tool-contracts',
      '--json',
    ]);
  });

  test('parses failed agent JSON artifacts from nonzero exits', () {
    final result = parseAgentValidationProcessResult(
      _failedValidationProcessResult('''
{
  "total": 1,
  "passed": 0,
  "failed": 1,
  "unsupported": 0,
  "validation_total": 0,
  "validation_passed": 0,
  "validation_failed": 0,
  "validation_unsupported": 0,
  "agents": [
    {
      "path": "agent.yaml",
      "passed": false,
      "error": "tool contract setup failed: missing-tool.yaml",
      "result": {}
    }
  ]
}
'''),
    );

    expect(result.failed, 1);
    expect(result.agents.single.error, contains('missing-tool.yaml'));
  });

  test('parses failed tool JSON artifacts from nonzero exits', () {
    final result = parseToolValidationProcessResult(
      _failedValidationProcessResult('''
{
  "total": 1,
  "passed": 0,
  "failed": 1,
  "unsupported": 0,
  "results": [
    {
      "id": "package.load",
      "status": "failed",
      "diagnostics": [
        {"severity": "error", "message": "decode tool.yaml: bad field"}
      ]
    }
  ]
}
'''),
    );

    expect(result.failed, 1);
    expect(result.results.single.id, 'package.load');
    expect(
      result.results.single.diagnostics.single.message,
      contains('bad field'),
    );
  });

  test('parses failed library JSON artifacts from nonzero exits', () {
    final result = parseLibraryValidationProcessResult(
      _failedValidationProcessResult('''
{
  "root": ".",
  "tool_dir": "./tools",
  "error": "required tool package directory not found: ./tools",
  "total": 1,
  "passed": 0,
  "failed": 1,
  "unsupported": 0
}
'''),
    );

    expect(result.failed, 1);
    expect(result.error, contains('required tool package directory'));
  });
}

/// Builds a nonzero validation process result with parseable JSON stdout.
ManagedProcessResult _failedValidationProcessResult(String stdout) {
  return ManagedProcessResult(
    id: 'validation',
    pid: 0,
    exitCode: 1,
    stdout: stdout,
    stderr: 'validation failed',
    timedOut: false,
  );
}
