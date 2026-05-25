/// Tests combined package-library validation result parsing.
library;

import 'package:agentawesome_ui/domain/library_validation_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs package-library validation parser tests.
void main() {
  test('parses combined agent and tool library results', () {
    final result = LibraryValidationResult.fromJson(<String, dynamic>{
      'root': './packages',
      'agent_dir': 'packages/agents',
      'tool_dir': 'packages/tools',
      'mcp_dir': 'packages/mcp',
      'total': 2,
      'passed': 2,
      'failed': 0,
      'unsupported': 0,
      'agents': <String, dynamic>{
        'total': 1,
        'passed': 1,
        'failed': 0,
        'unsupported': 0,
        'validation_total': 1,
        'validation_passed': 1,
        'validation_failed': 0,
        'validation_unsupported': 0,
        'agents': <Map<String, dynamic>>[
          <String, dynamic>{
            'path': './packages/agents/default/agent.yaml',
            'name': 'default',
            'passed': true,
            'result': <String, dynamic>{
              'total': 1,
              'passed': 1,
              'failed': 0,
              'unsupported': 0,
              'results': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'asks_for_context',
                  'mode': 'mocked',
                  'prompt': 'Help me.',
                  'status': 'passed',
                },
              ],
            },
          },
        ],
      },
      'tools': <String, dynamic>{
        'total_packages': 1,
        'passed_packages': 1,
        'failed_packages': 0,
        'unsupported_packages': 0,
        'total': 1,
        'passed': 1,
        'failed': 0,
        'unsupported': 0,
        'coverage_required': 1,
        'coverage_covered': 1,
        'coverage_missing': 0,
        'packages': <Map<String, dynamic>>[
          <String, dynamic>{
            'path': './packages/tools/echo/tool.yaml',
            'result': <String, dynamic>{
              'total': 1,
              'passed': 1,
              'failed': 0,
              'unsupported': 0,
              'agent_tool_calls': <String>['command:echo.message'],
              'agent_tool_contracts': <String, dynamic>{
                'command:echo.message': <String, dynamic>{
                  'id': 'command:echo.message',
                  'input_schema': <String, dynamic>{
                    'type': 'object',
                    'properties': <String, dynamic>{
                      'message': <String, dynamic>{'type': 'string'},
                    },
                  },
                },
              },
              'coverage': <String, dynamic>{
                'required': 1,
                'covered': 1,
                'missing': <Map<String, dynamic>>[],
              },
              'results': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'echo_message_mocked',
                  'mode': 'mocked',
                  'status': 'passed',
                },
              ],
            },
          },
        ],
      },
    });

    expect(result.passedAll, isTrue);
    expect(result.agents, isNotNull);
    expect(result.tools, isNotNull);
    expect(result.mcpDir, 'packages/mcp');
    expect(result.agents!.validationTotal, 1);
    expect(result.tools!.coverageCovered, 1);
    expect(result.tools!.agentToolContractCount, 1);
    expect(
      result.tools!.agentToolContracts['command:echo.message']!.inputSchema,
      containsPair('type', 'object'),
    );
    expect(
      result.tools!.packages.single.path,
      './packages/tools/echo/tool.yaml',
    );
  });

  test('parses tool-only library results', () {
    final result = LibraryValidationResult.fromJson(<String, dynamic>{
      'root': './packages',
      'tool_dir': 'packages/tools',
      'total': 1,
      'passed': 1,
      'failed': 0,
      'unsupported': 0,
      'tools': <String, dynamic>{
        'total_packages': 1,
        'passed_packages': 1,
        'failed_packages': 0,
        'unsupported_packages': 0,
        'total': 0,
        'passed': 0,
        'failed': 0,
        'unsupported': 0,
        'coverage_required': 0,
        'coverage_covered': 0,
        'coverage_missing': 0,
        'packages': <Map<String, dynamic>>[
          <String, dynamic>{
            'path': './packages/tools/echo/tool.yaml',
            'result': <String, dynamic>{},
          },
        ],
      },
    });

    expect(result.agents, isNull);
    expect(result.tools, isNotNull);
    expect(result.tools!.totalPackages, 1);
  });

  test('parses single-file library result paths', () {
    final result = LibraryValidationResult.fromJson(<String, dynamic>{
      'root': '.',
      'agent_path': 'agent.yaml',
      'tool_path': 'tool.local.yaml',
      'mcp_dir': '',
      'total': 2,
      'passed': 2,
      'failed': 0,
      'unsupported': 0,
    });

    expect(result.agentPath, 'agent.yaml');
    expect(result.toolPath, 'tool.local.yaml');
    expect(result.agentDir, isEmpty);
    expect(result.toolDir, isEmpty);
    expect(result.mcpDir, isEmpty);
  });

  test('parses top-level setup errors', () {
    final result = LibraryValidationResult.fromJson(<String, dynamic>{
      'root': './packages',
      'agent_dir': './packages/agents',
      'tool_dir': './packages/tools',
      'mcp_dir': './packages/mcp',
      'error': 'required tool package directory not found: ./packages/tools',
      'total': 1,
      'passed': 0,
      'failed': 1,
      'unsupported': 0,
    });

    expect(result.passedAll, isFalse);
    expect(
      result.error,
      'required tool package directory not found: ./packages/tools',
    );
    expect(result.agents, isNull);
    expect(result.tools, isNull);
  });
}
