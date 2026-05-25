/// Tests portable agent validation result parsing.
library;

import 'package:agentawesome_ui/domain/agent_validation_result.dart';
import 'package:agentawesome_ui/domain/agent_validation_merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs agent validation result parser tests.
void main() {
  test('parses agent validation result from CLI JSON', () {
    final result = AgentValidationResult.fromJson(<String, dynamic>{
      'total': 1,
      'passed': 1,
      'failed': 0,
      'unsupported': 0,
      'validation_total': 1,
      'validation_passed': 1,
      'validation_failed': 0,
      'validation_unsupported': 0,
      'tool_call_references': <String>['command:rg.search_text'],
      'agents': <Map<String, dynamic>>[
        <String, dynamic>{
          'path': './agent.yaml',
          'name': 'agent_awesome',
          'passed': true,
          'missing_assertions': <String>['placeholder_case'],
          'missing_tool_calls': <String>['agent_awesome'],
          'unknown_tool_calls': <String>['uses_search: command:missing.search'],
          'invalid_tool_arguments': <String>[
            'uses_search: command:tar.create_archive',
          ],
          'result': <String, dynamic>{
            'total': 1,
            'passed': 1,
            'failed': 0,
            'unsupported': 0,
            'tool_call_references': <String>['command:rg.search_text'],
            'results': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'uses_search',
                'label': 'Uses search',
                'mode': 'mocked',
                'prompt': 'Find TODO references.',
                'input': <String, dynamic>{'pattern': 'TODO'},
                'fixtures': <String, dynamic>{
                  'files': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'path': 'src/example.go',
                      'content': '// TODO: add validation',
                    },
                  ],
                },
                'status': 'passed',
                'response': <String, dynamic>{
                  'text': 'I will search.',
                  'output': <String, dynamic>{'status': 'ready'},
                  'tool_calls': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 'command:rg.search_text',
                      'name': 'rg.search_text',
                      'arguments': <String, dynamic>{'pattern': 'TODO'},
                    },
                  ],
                },
                'assertions': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'type': 'tool-call',
                    'path': 'response.tool_calls',
                    'passed': true,
                    'expected': 'rg.search_text',
                    'actual': 'rg.search_text',
                  },
                ],
                'diagnostics': <Map<String, dynamic>>[
                  <String, dynamic>{'severity': 'info', 'message': 'ok'},
                ],
              },
            ],
          },
        },
      ],
    });

    expect(result.passedAll, isTrue);
    expect(result.validationTotal, 1);
    expect(result.toolCallReferences, <String>['command:rg.search_text']);
    expect(result.agents.single.name, 'agent_awesome');
    expect(result.agents.single.result.toolCallReferences, <String>[
      'command:rg.search_text',
    ]);
    expect(result.agents.single.missingAssertions, <String>[
      'placeholder_case',
    ]);
    expect(result.agents.single.missingToolCalls, <String>['agent_awesome']);
    expect(result.agents.single.unknownToolCalls, <String>[
      'uses_search: command:missing.search',
    ]);
    expect(result.agents.single.invalidToolArguments, <String>[
      'uses_search: command:tar.create_archive',
    ]);
    final validation = result.agents.single.result.results.single;
    expect(validation.id, 'uses_search');
    expect(validation.input['pattern'], 'TODO');
    expect(validation.fixtures['files'], isA<List<dynamic>>());
    expect(validation.response.text, 'I will search.');
    expect(validation.response.output['status'], 'ready');
    expect(validation.response.toolCalls.single.id, 'command:rg.search_text');
    expect(validation.response.toolCalls.single.arguments['pattern'], 'TODO');
    expect(validation.assertions.single.type, 'tool-call');
    expect(validation.assertions.single.expected, 'rg.search_text');
    expect(validation.assertions.single.actual, 'rg.search_text');
    expect(validation.diagnostics.single.message, 'ok');
  });

  test('merges selected reruns without dropping tool-call references', () {
    final previous = AgentValidationSuiteResult.fromJson(<String, dynamic>{
      'total': 2,
      'passed': 1,
      'failed': 1,
      'unsupported': 0,
      'tool_call_references': <String>['command:rg.search_text'],
      'results': <Map<String, dynamic>>[
        _agentValidationJson('uses_search', 'failed'),
        _agentValidationJson('answers', 'passed'),
      ],
    });
    final next = AgentValidationSuiteResult.fromJson(<String, dynamic>{
      'total': 1,
      'passed': 1,
      'failed': 0,
      'unsupported': 0,
      'tool_call_references': <String>[
        'command:rg.search_text',
        'mcp:memory.search_memory',
      ],
      'results': <Map<String, dynamic>>[
        _agentValidationJson('uses_search', 'passed'),
      ],
    });

    final merged = mergeAgentValidationSuiteResults(previous, next);

    expect(merged.total, 2);
    expect(merged.passed, 2);
    expect(merged.failed, 0);
    expect(merged.toolCallReferences, <String>[
      'command:rg.search_text',
      'mcp:memory.search_memory',
    ]);
    expect(merged.results.first.status, 'passed');
  });
}

/// Builds a minimal agent validation result JSON object for parser tests.
Map<String, dynamic> _agentValidationJson(String id, String status) {
  return <String, dynamic>{
    'id': id,
    'mode': 'mocked',
    'prompt': 'Answer.',
    'status': status,
    'response': <String, dynamic>{'text': 'ok'},
  };
}
