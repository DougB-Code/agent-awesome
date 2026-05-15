/// Tests assistant and MCP response parsing used by the Agent Awesome UI.
library;

import 'dart:convert';

import 'package:agentawesome_ui/clients/assistant_client.dart';
import 'package:agentawesome_ui/clients/mcp_client.dart';
import 'package:agentawesome_ui/domain/executive_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Runs parser coverage for client helpers.
void main() {
  group('executive summary parsing', () {
    test('parses full v1 projection fixture', () {
      final projection = parseExecutiveSummaryProjection(<String, dynamic>{
        'schema_version': 'agent-awesome/executive-summary/v1',
        'generated_at': '2026-05-09T09:24:00Z',
        'horizon': 'today',
        'title': 'Today',
        'subtitle': 'Here is what matters now.',
        'metrics': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'decisions',
            'label': 'Decisions',
            'value': '2',
            'subtitle': 'Require your input',
            'severity': 'attention',
            'link': <String, dynamic>{'route': '/attention?lane=decide'},
          },
        ],
        'open_loops': <String, dynamic>{
          'categories': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'orphan_tasks',
              'label': 'Orphan tasks',
              'count': 3,
            },
          ],
        },
        'attention': <String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'attention:do:milk',
              'lane': 'do',
              'kind': 'task',
              'title': 'Buy milk',
              'reason': 'Small isolated task, easy to forget',
              'primary_action': <String, dynamic>{
                'label': 'Mark done',
                'tool': 'complete_task',
                'safety': 'safe',
                'payload': <String, dynamic>{'task_id': 'milk'},
              },
            },
            <String, dynamic>{
              'id': 'attention:unknown:x',
              'lane': 'surprise',
              'kind': 'task',
              'title': 'Watch this',
              'reason': 'Invalid lanes map to monitor',
            },
          ],
        },
        'delegation': <String, dynamic>{
          'buckets': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'can_do_now',
              'label': 'Agent can do now',
              'count': 4,
            },
          ],
        },
        'time_horizon': <String, dynamic>{
          'buckets': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'today',
              'label': 'Today',
              'count': 6,
              'summary': 'High focus',
            },
          ],
        },
        'risk_unblocks': <String, dynamic>{
          'chains': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'risk:budget',
              'nodes': <Map<String, dynamic>>[
                <String, dynamic>{'title': 'Collect forecast inputs'},
                <String, dynamic>{'title': 'Budget decision'},
              ],
              'suggested_action': <String, dynamic>{
                'label': 'Nudge Alex',
                'safety': 'safe',
              },
            },
          ],
        },
        'coverage': <String, dynamic>{
          'good': <String>['Tasks & projects'],
          'partial': <String>['Some missing due dates'],
          'not_connected': <String>['Calendar'],
          'promise': 'I only use information that is source-backed in memory.',
        },
      });

      expect(projection.metrics.single.label, 'Decisions');
      expect(projection.openLoops.categories.single.count, 3);
      expect(
        projection.attention.items.first.primaryAction?.tool,
        'complete_task',
      );
      expect(
        projection.attention.items.first.primaryAction?.payload['task_id'],
        'milk',
      );
      expect(projection.attention.items.last.lane, 'monitor');
      expect(projection.delegation.buckets.single.count, 4);
      expect(projection.timeHorizon.buckets.single.summary, 'High focus');
      expect(projection.riskUnblocks.chains.single.nodes.length, 2);
      expect(projection.coverage.notConnected, contains('Calendar'));
    });

    test('missing optional sections produce empty defaults', () {
      final projection = parseExecutiveSummaryProjection(<String, dynamic>{});

      expect(projection.title, 'Today');
      expect(projection.metrics, isEmpty);
      expect(projection.attention.items, isEmpty);
      expect(projection.coverage.promise, contains('source-backed'));
      expect(projection.quality.label, 'Sparse');
    });
  });

  group('assistant parsing', () {
    test('parses text events', () {
      final event = parseAssistantEvent(<String, dynamic>{
        'id': 'event-1',
        'author': 'assistant',
        'partial': true,
        'modelVersion': 'openai:gpt-mini',
        'content': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': 'Hello'},
          ],
        },
      });

      expect(event.id, 'event-1');
      expect(event.text, 'Hello');
      expect(event.partial, isTrue);
      expect(event.modelRef, 'openai:gpt-mini');
    });

    test('parses routed model refs from state delta', () {
      final event = parseAssistantEvent(<String, dynamic>{
        'id': 'event-user-route',
        'author': 'user',
        'actions': <String, dynamic>{
          'stateDelta': <String, dynamic>{
            runtimeModelRefStateKey: 'openai:gpt-5-pro',
          },
        },
        'content': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': 'Use the stronger model.'},
          ],
        },
      });

      expect(event.modelRef, 'openai:gpt-5-pro');
    });

    test('deletes sessions through the assistant endpoint', () async {
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

    test('requests non-streaming agent runs', () async {
      final client = AssistantClient(
        baseUrl: 'http://127.0.0.1:1',
        appName: 'test-app',
        userId: 'user-1',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/run_sse');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['streaming'], isFalse);
          final stateDelta = body['stateDelta'] as Map<String, dynamic>;
          expect(stateDelta[runtimeModelRefStateKey], 'openai:gpt-5-pro');
          return http.Response(
            'data: {"id":"event-1","author":"assistant","content":{"parts":[{"text":"ok"}]}}\n\n',
            200,
            headers: const <String, String>{
              'content-type': 'text/event-stream',
            },
          );
        }),
      );

      final events = await client
          .sendMessage(
            sessionId: 'session-1',
            text: 'hello',
            modelRef: 'openai:gpt-5-pro',
          )
          .toList();

      expect(events.single.text, 'ok');
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
      expect(event.errorMessage, contains('requires confirmation'));
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

    test('keeps outbound text raw and hides persisted runtime policy text', () {
      final outbound = messageTextForAgent('Remind me to buy milk.');
      expect(outbound, 'Remind me to buy milk.');

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

      final sessionScoped = messageTextForAgent(
        'Create a task.',
        sessionId: 'session-live',
      );
      expect(sessionScoped, 'Create a task.');
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

    test('hides persisted Agent Awesome runtime policy text', () {
      // AURORA markers are intentional old-transcript migration fixtures.
      final visible = parseAssistantEvent(<String, dynamic>{
        'id': 'event-legacy-policy',
        'author': 'user',
        'content': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{
              'text':
                  '[[AURORA_RUNTIME_POLICY: legacy persisted policy.]]\n\n'
                  '[[AURORA_SESSION_CONTEXT: Current chat session id is "session-live".]]\n\n'
                  'Make a reminder to buy milk',
            },
          ],
        },
      });

      expect(visible.text, 'Make a reminder to buy milk');
    });

    test('suppresses leaked local model tool markup', () {
      final event = parseAssistantEvent(<String, dynamic>{
        'id': 'event-local-tool-leak',
        'author': 'assistant',
        'content': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{
              'text':
                  '<|tool_call>call:tool_call{create_task{description:<|"|>Buy milk<|"|>,title:<|"|>Buy Milk<|"|>}}<tool_call|>',
            },
          ],
        },
      });

      expect(event.text, isEmpty);
      expect(event.toolActivity, isNull);
      expect(event.confirmation, isNull);
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
            'domain_id': 'memory',
            'firewall': 'acme-client',
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
      expect(records.single.domainId, 'memory');
      expect(records.single.firewall, 'acme-client');
      expect(records.single.evidenceId, 'ev-1');
      expect(records.single.trustLevel, 'user_asserted');
      expect(records.single.rawContent, 'Doug likes concise UI.');
      expect(records.single.sourceLabel, 'Chat: 1');
      expect(records.single.relationships.single.type, 'refers_to');
    });

    test('parses legacy chat memory sources without internal labels', () {
      final records = parseMemoryRecords(<String, dynamic>{
        'primary_memory': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'mem-1',
            'title': 'Chat message',
            'summary': 'Remember this.',
            'kind': 'conversation',
            'topics': <String>['adk_chat'],
            'source': <String, dynamic>{
              'system': 'google_adk_session',
              'id': 'event-1',
            },
          },
        ],
      });

      expect(records.single.sourceSystem, 'chat_session');
      expect(records.single.sourceLabel, 'Chat: event-1');
    });

    test('parses compiled memory pages', () {
      final page = parseCompiledMemoryPage(<String, dynamic>{
        'id': 'page-1',
        'domain_id': 'memory',
        'kind': 'timeline',
        'firewall': 'acme-client',
        'title': 'ui',
        'path': 'pages/page-1.md',
        'status': 'active',
        'source_ids': <String>['ev-1'],
        'content': '# UI',
        'stale': false,
      });

      expect(page.title, 'ui');
      expect(page.domainId, 'memory');
      expect(page.firewall, 'acme-client');
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
          'follow_up_at': '2026-05-15T12:00:00Z',
          'idempotency_key': 'agent_awesome:session-live:draft-brief',
          'topics': <String>['brief'],
          'estimate_minutes': 45,
          'urgency': 0.7,
          'risk': 0.2,
          'context': 'Focus',
          'location': 'Desk',
          'person': 'Doug',
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
      expect(tasks.first.followUpAt?.toUtc(), DateTime.utc(2026, 5, 15, 12));
      expect(tasks.first.estimateMinutes, 45);
      expect(tasks.first.workBreakdown.code, '1.2');
      expect(tasks.first.workBreakdown.acceptanceCriteria, <String>[
        'Rubric checked',
      ]);
      expect(tasks.first.workBreakdown.resources.single.name, 'Reviewer');
      expect(tasks.first.idempotencyKey, contains('session-live'));
      expect(tasks.first.memoryLinks.single.memoryId, 'mem-1');
      expect(tasks.last.done, isTrue);
    });

    test('parses task graph relations', () {
      final relations = parseTaskRelations(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'relation-1',
          'from_task_id': 'task-1',
          'to_task_id': 'task-2',
          'type': 'depends_on',
          'confidence': 0.75,
          'source': 'explicit',
          'explanation': 'Draft before review.',
        },
      ]);
      expect(relations.single.relationType, 'depends_on');
      expect(relations.single.confidence, 0.75);
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

    test('sends memory domain selector outside tool arguments', () async {
      final client = GatewayContextClient(
        baseUrl: 'http://127.0.0.1:1/api/context',
        domainId: 'family',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['name'], 'list_tasks');
          expect(body['domain_id'], 'family');
          expect(body['arguments'], <String, dynamic>{'limit': 5});
          return http.Response('{"structuredContent":{"tasks":[]}}', 200);
        }),
      );

      final content = await client.callTool('list_tasks', <String, dynamic>{
        'limit': 5,
      });

      expect(content, <String, dynamic>{'tasks': <dynamic>[]});
    });
  });
}
