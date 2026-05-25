/// Tests portable tool validation result parsing.
library;

import 'package:agentawesome_ui/domain/tool_validation_result.dart';
import 'package:agentawesome_ui/domain/tool_validation_merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs validation result parser tests.
void main() {
  test('parses library results from CLI JSON', () {
    final result = ToolValidationLibraryResult.fromJson(<String, dynamic>{
      'total_packages': 1,
      'passed_packages': 1,
      'failed_packages': 0,
      'unsupported_packages': 0,
      'total': 1,
      'passed': 1,
      'failed': 0,
      'unsupported': 0,
      'coverage_required': 2,
      'coverage_covered': 1,
      'coverage_missing': 1,
      'input_schema_required': 1,
      'input_schema_covered': 1,
      'input_schema_missing': 0,
      'missing_assertions': 1,
      'packages': <Map<String, dynamic>>[
        <String, dynamic>{
          'path': './tools/curl/tool.yaml',
          'result': <String, dynamic>{
            'total': 1,
            'passed': 1,
            'failed': 0,
            'unsupported': 0,
            'agent_tool_calls': <String>['command:curl.http_get'],
            'agent_tool_contracts': <String, dynamic>{
              'command:curl.http_get': <String, dynamic>{
                'id': 'command:curl.http_get',
                'input_schema': <String, dynamic>{
                  'type': 'object',
                  'properties': <String, dynamic>{
                    'url': <String, dynamic>{'type': 'string'},
                  },
                },
              },
            },
            'missing_assertions': <String>['curl_probe'],
            'coverage': <String, dynamic>{
              'required': 2,
              'covered': 1,
              'missing': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'workflow-node',
                  'id': 'curl_http_get',
                  'label': 'curl HTTP GET',
                },
              ],
            },
            'input_schema_coverage': <String, dynamic>{
              'required': 1,
              'covered': 1,
              'missing': <Map<String, dynamic>>[],
            },
            'results': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'curl_http_get_mocked',
                'label': 'curl HTTP GET',
                'description': 'Fetch a URL.',
                'mode': 'mocked',
                'status': 'passed',
                'target': <String, dynamic>{
                  'type': 'command-operation',
                  'command': 'curl',
                  'operation': 'http_get',
                  'template_id': 'curl.http_get',
                  'boundary': 'command.execute',
                },
                'command': <String, dynamic>{
                  'job_id': 'mock:curl_http_get_mocked',
                  'status': 'succeeded',
                  'exit_code': 0,
                  'stdout_tail': 'ok',
                  'stderr_tail': '',
                  'truncated': false,
                  'timed_out': false,
                  'output': <String, dynamic>{'text': 'ok'},
                  'validation': <String, dynamic>{
                    'checked': true,
                    'valid': true,
                  },
                },
              },
            ],
          },
        },
      ],
    });

    expect(result.passedAll, isTrue);
    expect(result.coverageRequired, 2);
    expect(result.coverageMissing, 1);
    expect(result.inputSchemaCovered, 1);
    expect(result.missingAssertions, 1);
    expect(result.packages.single.path, './tools/curl/tool.yaml');
    expect(
      result.packages.single.result.results.single.id,
      'curl_http_get_mocked',
    );
    final validation = result.packages.single.result.results.single;
    expect(validation.description, 'Fetch a URL.');
    expect(validation.target.templateId, 'curl.http_get');
    expect(result.packages.single.result.agentToolCalls, <String>[
      'command:curl.http_get',
    ]);
    expect(result.packages.single.result.agentToolContracts.keys, <String>[
      'command:curl.http_get',
    ]);
    expect(
      result
          .packages
          .single
          .result
          .agentToolContracts['command:curl.http_get']!
          .inputSchema['type'],
      'object',
    );
    expect(result.packages.single.result.missingAssertions, <String>[
      'curl_probe',
    ]);
    expect(result.packages.single.result.inputSchemaCoverage.covered, 1);
    expect(validation.command!.stdoutTail, 'ok');
    expect(validation.command!.validation.checked, isTrue);
  });

  test('parses suite results from CLI JSON', () {
    final result = ToolValidationSuiteResult.fromJson(<String, dynamic>{
      'total': 1,
      'passed': 1,
      'failed': 0,
      'unsupported': 0,
      'agent_tool_calls': <String>['command:curl.http_get'],
      'agent_tool_contracts': <String, dynamic>{
        'command:curl.http_get': <String, dynamic>{
          'id': 'command:curl.http_get',
          'input_schema': <String, dynamic>{'type': 'object'},
        },
      },
      'missing_assertions': <String>['curl_probe'],
      'coverage': <String, dynamic>{
        'required': 2,
        'covered': 1,
        'missing': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'workflow-node',
            'id': 'curl_http_get',
            'label': 'curl HTTP GET',
          },
        ],
      },
      'input_schema_coverage': <String, dynamic>{
        'required': 1,
        'covered': 0,
        'missing': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'command-operation-input-schema',
            'id': 'curl.http_get',
            'label': 'curl HTTP GET',
          },
        ],
      },
      'results': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'curl_http_get_mocked',
          'label': 'curl HTTP GET',
          'mode': 'mocked',
          'status': 'passed',
          'target': <String, dynamic>{
            'type': 'command-operation',
            'command': 'curl',
            'operation': 'http_get',
            'template_id': 'curl.http_get',
            'boundary': 'command.execute',
          },
          'command': <String, dynamic>{
            'job_id': 'mock:curl_http_get_mocked',
            'status': 'succeeded',
            'exit_code': 0,
            'stdout_tail': 'ok',
            'output': <String, dynamic>{'text': 'ok'},
          },
          'assertions': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'stdout-contains',
              'passed': true,
              'expected': 'ok',
              'actual': 'ok',
            },
          ],
          'diagnostics': <Map<String, dynamic>>[
            <String, dynamic>{'severity': 'info', 'message': 'ok'},
          ],
        },
      ],
    });

    expect(result.total, 1);
    expect(result.passedAll, isTrue);
    expect(result.coverage.required, 2);
    expect(result.agentToolCalls, <String>['command:curl.http_get']);
    expect(
      result.agentToolContracts['command:curl.http_get']!.id,
      'command:curl.http_get',
    );
    expect(
      result.agentToolContracts['command:curl.http_get']!.inputSchema['type'],
      'object',
    );
    expect(result.missingAssertions, <String>['curl_probe']);
    expect(result.inputSchemaCoverage.missing.single.id, 'curl.http_get');
    expect(result.coverage.missing.single.id, 'curl_http_get');
    expect(result.results.single.id, 'curl_http_get_mocked');
    expect(result.results.single.target.boundary, 'command.execute');
    expect(result.results.single.command!.output['text'], 'ok');
    expect(result.results.single.assertions.single.type, 'stdout-contains');
    expect(result.results.single.assertions.single.expected, 'ok');
    expect(result.results.single.assertions.single.actual, 'ok');
    expect(result.results.single.diagnostics.single.message, 'ok');
  });

  test('merges selected reruns without dropping suite metadata', () {
    final previous = ToolValidationSuiteResult.fromJson(<String, dynamic>{
      'total': 2,
      'passed': 1,
      'failed': 1,
      'unsupported': 0,
      'agent_tool_calls': <String>['command:curl.http_get'],
      'agent_tool_contracts': <String, dynamic>{
        'command:curl.http_get': <String, dynamic>{
          'id': 'command:curl.http_get',
          'input_schema': <String, dynamic>{'type': 'object'},
        },
      },
      'missing_assertions': <String>['old_missing'],
      'coverage': <String, dynamic>{
        'required': 3,
        'covered': 2,
        'missing': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'workflow-node', 'id': 'curl.http_get'},
        ],
      },
      'input_schema_coverage': <String, dynamic>{
        'required': 2,
        'covered': 1,
        'missing': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'command-operation-input-schema',
            'id': 'curl.download_file',
          },
        ],
      },
      'results': <Map<String, dynamic>>[
        _toolValidationJson('curl_http_get_agent', 'failed'),
        _toolValidationJson('curl_http_get_workflow', 'passed'),
      ],
    });
    final next = ToolValidationSuiteResult.fromJson(<String, dynamic>{
      'total': 1,
      'passed': 1,
      'failed': 0,
      'unsupported': 0,
      'agent_tool_calls': <String>[
        'command:curl.http_get',
        'command:curl.download_file',
      ],
      'agent_tool_contracts': <String, dynamic>{
        'command:curl.http_get': <String, dynamic>{
          'id': 'command:curl.http_get',
        },
        'command:curl.download_file': <String, dynamic>{
          'id': 'command:curl.download_file',
          'input_schema': <String, dynamic>{'type': 'object'},
        },
      },
      'missing_assertions': <String>['next_missing'],
      'coverage': <String, dynamic>{
        'required': 3,
        'covered': 3,
        'missing': <Map<String, dynamic>>[],
      },
      'input_schema_coverage': <String, dynamic>{
        'required': 2,
        'covered': 2,
        'missing': <Map<String, dynamic>>[],
      },
      'results': <Map<String, dynamic>>[
        _toolValidationJson('curl_http_get_agent', 'passed'),
      ],
    });

    final merged = mergeToolValidationSuiteResults(previous, next);

    expect(merged.total, 2);
    expect(merged.passed, 2);
    expect(merged.failed, 0);
    expect(merged.coverage.covered, 3);
    expect(merged.inputSchemaCoverage.covered, 2);
    expect(merged.inputSchemaCoverage.missing, isEmpty);
    expect(merged.agentToolCalls, <String>[
      'command:curl.http_get',
      'command:curl.download_file',
    ]);
    expect(merged.agentToolContracts.keys, <String>[
      'command:curl.http_get',
      'command:curl.download_file',
    ]);
    expect(
      merged.agentToolContracts['command:curl.download_file']!.inputSchema,
      <String, dynamic>{'type': 'object'},
    );
    expect(merged.missingAssertions, <String>['next_missing']);
    expect(merged.results.first.status, 'passed');
  });
}

/// Builds a minimal tool validation result JSON object for parser tests.
Map<String, dynamic> _toolValidationJson(String id, String status) {
  return <String, dynamic>{
    'id': id,
    'mode': 'mocked',
    'status': status,
    'target': <String, dynamic>{
      'type': 'agent-tool-call',
      'command': 'curl',
      'operation': 'http_get',
      'boundary': 'agent.tool_call',
    },
  };
}
