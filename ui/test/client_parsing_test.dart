/// Tests ADK and MCP response parsing used by the Aurora UI.
library;

import 'package:agentawesome_ui/clients/assistant_client.dart';
import 'package:agentawesome_ui/clients/mcp_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Runs parser coverage for client helpers.
void main() {
  group('assistant parsing', () {
    test('parses text events', () {
      final event = parseAssistantEvent(<String, dynamic>{
        'id': 'event-1',
        'author': 'assistant',
        'partial': true,
        'content': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': 'Hello'},
          ],
        },
      });

      expect(event.id, 'event-1');
      expect(event.text, 'Hello');
      expect(event.partial, isTrue);
    });

    test('deletes sessions through the ADK endpoint', () async {
      final client = AssistantClient(
        baseUrl: 'http://127.0.0.1:1',
        appName: 'test-app',
        userId: 'user-1',
        headers: const <String, String>{'Authorization': 'Bearer gateway'},
        httpClient: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(
            request.url.path,
            '/apps/test-app/users/user-1/sessions/session-1',
          );
          expect(request.headers['Authorization'], 'Bearer gateway');
          return http.Response('', 204);
        }),
      );

      await client.deleteSession('session-1');
    });

    test('parses SSE error events', () {
      final event = parseSseAssistantEvent(
        'error',
        '{"error":"provider does not support streaming"}',
      );

      expect(event.author, 'Runtime');
      expect(event.errorMessage, 'provider does not support streaming');
    });

    test('creates sessions with gateway auth headers', () async {
      final client = AssistantClient(
        baseUrl: 'http://127.0.0.1:1',
        appName: 'test-app',
        userId: 'user-1',
        headers: const <String, String>{'Authorization': 'Bearer gateway'},
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], 'Bearer gateway');
          expect(request.headers['Content-Type'], 'application/json');
          return http.Response(
            '{"id":"session-1","appName":"test-app","userId":"user-1","events":[]}',
            200,
          );
        }),
      );

      final session = await client.createSession();

      expect(session.id, 'session-1');
    });

    test('parses tool activity events', () {
      final event = parseAssistantEvent(<String, dynamic>{
        'id': 'event-2',
        'author': 'assistant',
        'content': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{
              'functionCall': <String, dynamic>{
                'id': 'call-1',
                'name': 'search_memory',
                'args': <String, dynamic>{},
              },
            },
          ],
        },
      });

      expect(event.toolActivity?.name, 'search_memory');
      expect(event.confirmation, isNull);
    });

    test('parses tool response errors', () {
      final event = parseAssistantEvent(<String, dynamic>{
        'id': 'event-tool-error',
        'author': 'assistant',
        'content': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{
              'functionResponse': <String, dynamic>{
                'id': 'call-1',
                'name': 'create_task',
                'response': <String, dynamic>{
                  'error': 'tool requires confirmation',
                },
              },
            },
          ],
        },
      });

      expect(event.toolActivity?.name, 'create_task');
      expect(event.toolActivity?.status, 'failed');
      expect(event.toolActivity?.summary, contains('requires confirmation'));
    });

    test('parses confirmation events', () {
      final event = parseAssistantEvent(<String, dynamic>{
        'id': 'event-3',
        'author': 'assistant',
        'content': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{
              'functionCall': <String, dynamic>{
                'id': 'confirm-1',
                'name': 'adk_request_confirmation',
                'args': <String, dynamic>{
                  'originalFunctionCall': <String, dynamic>{
                    'id': 'call-1',
                    'name': 'create_task',
                  },
                  'toolConfirmation': <String, dynamic>{
                    'hint': 'Approve saving memory?',
                    'payload': <String, dynamic>{
                      'options': <Map<String, dynamic>>[
                        <String, dynamic>{'action': 'deny', 'label': 'Deny'},
                        <String, dynamic>{
                          'action': 'approve_once',
                          'label': 'Approve once',
                        },
                      ],
                    },
                  },
                },
              },
            },
          ],
        },
      });

      expect(event.confirmation?.callId, 'confirm-1');
      expect(event.confirmation?.hint, 'Approve saving memory?');
      expect(event.confirmation?.options.length, 2);
      expect(event.confirmation?.toolName, 'create_task');
    });

    test('adds and hides runtime task policy text', () {
      final outbound = messageTextWithRuntimePolicy('Remind me to buy milk.');
      expect(outbound, startsWith(runtimePolicyPrefix));

      final visible = parseAssistantEvent(<String, dynamic>{
        'id': 'event-policy',
        'author': 'user',
        'content': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': outbound},
          ],
        },
      });
      expect(visible.text, 'Remind me to buy milk.');

      final hidden = parseAssistantEvent(<String, dynamic>{
        'id': 'event-hidden-policy',
        'author': 'user',
        'content': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{
              'text':
                  '$runtimePolicyPrefix${hiddenRuntimeMessagePrefix}Create it.',
            },
          ],
        },
      });
      expect(hidden.text, isEmpty);

      final sessionScoped = messageTextWithRuntimePolicy(
        'Create a task.',
        sessionId: 'session-live',
      );
      expect(sessionScoped, contains('personal_pilot:session-live:'));
      final visibleSessionScoped = parseAssistantEvent(<String, dynamic>{
        'id': 'event-session-policy',
        'author': 'user',
        'content': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': sessionScoped},
          ],
        },
      });
      expect(visibleSessionScoped.text, 'Create a task.');
    });
  });

  group('mcp parsing', () {
    test('extracts structured tool content', () {
      final content = parseToolStructuredContent(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 1,
        'result': <String, dynamic>{
          'isError': false,
          'structuredContent': <String, dynamic>{'ok': true},
        },
      });

      expect(content, <String, dynamic>{'ok': true});
    });

    test('parses memory records', () {
      final records = parseMemoryRecords(<String, dynamic>{
        'primary_memory': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'mem-1',
            'evidence_id': 'ev-1',
            'title': 'Preference',
            'summary': 'Doug likes concise UI.',
            'kind': 'profile_fact',
            'scope': 'user',
            'trust_level': 'user_asserted',
            'sensitivity': 'private',
            'status': 'active',
            'subjects': <String>['preferences'],
            'topics': <String>['ui'],
            'entity_ids': <String>['ent-1'],
            'entity_names': <String>['Doug'],
            'source': <String, dynamic>{'system': 'chat', 'id': '1'},
            'raw': <String, dynamic>{
              'path': 'evidence/ev-1.txt',
              'checksum': 'abc',
              'media_type': 'text/plain; charset=utf-8',
              'content_text': 'Doug likes concise UI.',
            },
            'relationships': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'rel-1',
                'from_id': 'mem-1',
                'type': 'refers_to',
                'to_id': 'cat-0',
                'source_id': 'ev-1',
                'trust_level': 'user_asserted',
              },
            ],
          },
        ],
      });

      expect(records.single.title, 'Preference');
      expect(records.single.evidenceId, 'ev-1');
      expect(records.single.trustLevel, 'user_asserted');
      expect(records.single.rawContent, 'Doug likes concise UI.');
      expect(records.single.sourceLabel, 'chat:1');
      expect(records.single.relationships.single.type, 'refers_to');
    });

    test('parses compiled memory pages', () {
      final page = parseCompiledMemoryPage(<String, dynamic>{
        'id': 'page-1',
        'kind': 'timeline',
        'scope': 'user',
        'title': 'ui',
        'path': 'pages/page-1.md',
        'status': 'active',
        'source_ids': <String>['ev-1'],
        'content': '# UI',
        'stale': false,
      });

      expect(page.title, 'ui');
      expect(page.sourceIds, <String>['ev-1']);
      expect(page.content, '# UI');
    });

    test('parses workspace tasks', () {
      final tasks = parseWorkspaceTasks(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'task-1',
          'title': 'Draft brief',
          'status': 'open',
          'priority': 'high',
          'idempotency_key': 'personal_pilot:session-live:draft-brief',
          'topics': <String>['brief'],
          'estimate_minutes': 45,
          'energy_required': 'deep',
          'effort': 0.6,
          'value': 0.8,
          'urgency': 0.7,
          'risk': 0.2,
          'context': 'Focus',
          'view': 'Work',
          'location': 'Desk',
          'person': 'Doug',
          'source': 'Personal Tasks',
          'confidence': 0.9,
          'work_breakdown': <String, dynamic>{
            'code': '1.2',
            'deliverable': 'Draft brief',
            'start_criteria': <String>['Assignment parsed'],
            'acceptance_criteria': <String>['Rubric checked'],
            'requirement_refs': <String>['R1'],
            'rubric_refs': <String>['C2'],
            'spend_cents': 1250,
            'spend_currency': 'USD',
            'resources': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'Reviewer',
                'type': 'person',
                'quantity': 1,
                'unit': 'hour',
                'spend_cents': 5000,
                'spend_currency': 'USD',
              },
            ],
          },
          'memory_links': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'link-1',
              'memory_id': 'mem-1',
              'relationship': 'context',
            },
          ],
        },
        <String, dynamic>{
          'id': 'task-2',
          'title': 'Send brief',
          'status': 'done',
        },
      ]);

      expect(tasks.length, 2);
      expect(tasks.first.active, isTrue);
      expect(tasks.first.priority, 'high');
      expect(tasks.first.estimateMinutes, 45);
      expect(tasks.first.context, 'Focus');
      expect(tasks.first.confidence, 0.9);
      expect(tasks.first.workBreakdown.code, '1.2');
      expect(tasks.first.workBreakdown.acceptanceCriteria, <String>[
        'Rubric checked',
      ]);
      expect(tasks.first.workBreakdown.resources.single.name, 'Reviewer');
      expect(tasks.first.idempotencyKey, contains('session-live'));
      expect(tasks.first.memoryLinks.single.memoryId, 'mem-1');
      expect(tasks.last.done, isTrue);
    });

    test('parses task graph corrections', () {
      final relations = parseTaskRelations(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'relation-1',
          'from_task_id': 'task-1',
          'to_task_id': 'task-2',
          'relation_type': 'depends_on',
          'confidence': 0.75,
          'source': 'explicit',
          'explanation': 'Draft before review.',
        },
      ]);
      final suggestions = parseTaskRelationSuggestions(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'suggestion-1',
          'from_task_id': 'task-1',
          'to_task_id': 'task-3',
          'relation_type': 'same_context',
          'confidence': 0.65,
          'explanation': 'Both are focus work.',
        },
      ]);
      final metadataSuggestions = parseTaskMetadataSuggestions(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'suggestion-metadata-1',
            'task_id': 'task-1',
            'estimate_minutes': 45,
            'energy_required': 'deep',
            'context': 'Focus',
            'view': 'Work',
            'confidence': 0.72,
            'explanation': 'Inferred from task text.',
          },
        ],
      );
      final commitmentSuggestions = parseTaskCommitmentSuggestions(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'suggestion-commitment-1',
            'task_id': 'task-1',
            'people': <String>['Doug'],
            'view': 'Work',
            'project': 'Proposal',
            'time_window': 'This week',
            'responsibility': 'owned',
            'promise_source': 'Task',
            'hardness': 'soft',
            'consequence': 'Commitment may be forgotten.',
            'confidence': 0.64,
            'explanation': 'Inferred from due date.',
          },
        ],
      );
      final commitments = parseTaskCommitments(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'commitment-1',
          'task_id': 'task-1',
          'people': <String>['Doug', 'Family'],
          'view': 'Errands',
          'project': 'Groceries',
          'time_window': 'This week',
          'responsibility': 'owned',
          'promise_source': 'Personal Tasks',
          'hardness': 'soft',
          'consequence': 'No breakfast.',
        },
      ]);

      expect(relations.single.relationType, 'depends_on');
      expect(relations.single.confidence, 0.75);
      expect(suggestions.single.id, 'suggestion-1');
      expect(suggestions.single.relationType, 'same_context');
      expect(metadataSuggestions.single.context, 'Focus');
      expect(metadataSuggestions.single.estimateMinutes, 45);
      expect(commitmentSuggestions.single.project, 'Proposal');
      expect(commitmentSuggestions.single.confidence, 0.64);
      expect(commitments.single.people, <String>['Doug', 'Family']);
      expect(commitments.single.project, 'Groceries');
    });

    test('parses WBS rows from graph query results', () {
      final workBreakdowns = parseTaskWorkBreakdownRows(<String, dynamic>{
        'rows': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'task-1',
            'work_breakdown':
                '{"code":"1.2","deliverable":"Parser fix","start_criteria":["DB has WBS"],"acceptance_criteria":["WBS renders"]}',
          },
        ],
      });

      expect(workBreakdowns['task-1']?.code, '1.2');
      expect(workBreakdowns['task-1']?.deliverable, 'Parser fix');
      expect(workBreakdowns['task-1']?.acceptanceCriteria, <String>[
        'WBS renders',
      ]);
    });
  });

  group('context client', () {
    test('sends gateway auth headers', () async {
      final client = GatewayContextClient(
        baseUrl: 'http://127.0.0.1:1/api/context',
        headers: const <String, String>{'Authorization': 'Bearer gateway'},
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/context/tools/list');
          expect(request.headers['Authorization'], 'Bearer gateway');
          return http.Response('{"tools":["search_memory"]}', 200);
        }),
      );

      final tools = await client.listToolNames();

      expect(tools, <String>['search_memory']);
    });
  });
}
