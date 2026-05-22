/// Tests ADK-backed screen-command planning.
library;

import 'dart:convert';

import 'package:agentawesome_ui/clients/screen_command_client.dart';
import 'package:agentawesome_ui/domain/screen_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Runs screen-command client tests.
void main() {
  test('plans backlog command through ADK with default model ref', () async {
    late Map<String, dynamic> runBody;
    final client = ScreenCommandClient(
      baseUrl: _baseUrl,
      appName: _appName,
      userId: _userId,
      httpClient: _mockAdkClient(
        responseText:
            '{"intent":"change","confidence":0.9,"changes":[{"operation":"update_task","target":{"task_id":"task-1"},"summary":"Raise priority","confidence":0.95,"fields":{"priority":"high"}}]}',
        onRunBody: (body) => runBody = body,
      ),
    );

    final run = await client.planBacklogCommand(
      modelConfigContent: _modelConfig,
      command: 'make Draft schema high priority',
      snapshot: const BacklogScreenSnapshot(
        scopeLabel: 'Backlog / Queue',
        visibleTasks: <BacklogScreenTaskSnapshot>[
          BacklogScreenTaskSnapshot(
            id: 'task-1',
            title: 'Draft schema',
            priority: 'normal',
          ),
        ],
      ),
    );

    expect(run.intent, ScreenCommandIntent.change);
    expect(run.command, 'make Draft schema high priority');
    expect(run.changes.single.operation, ScreenChangeOperation.updateTask);
    expect(run.changes.single.fields['priority'], 'high');
    expect(runBody['stateDelta'], <String, dynamic>{
      'agentawesome.model_ref': 'openai:gpt-mini',
    });
    expect(jsonEncode(runBody), contains('Draft schema'));
    client.close();
  });
}

MockClient _mockAdkClient({
  required String responseText,
  required void Function(Map<String, dynamic> body) onRunBody,
}) {
  return MockClient((request) async {
    if (request.method == 'POST' &&
        request.url.toString() ==
            '$_baseUrl/apps/$_appName/users/$_userId/sessions') {
      return http.Response(
        jsonEncode(<String, dynamic>{'id': _sessionId}),
        200,
      );
    }
    if (request.method == 'POST' &&
        request.url.toString() == '$_baseUrl/run_sse') {
      onRunBody(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(_sseText(responseText), 200);
    }
    if (request.method == 'DELETE' &&
        request.url.toString() ==
            '$_baseUrl/apps/$_appName/users/$_userId/sessions/$_sessionId') {
      return http.Response('', 204);
    }
    return http.Response(
      'unexpected request ${request.method} ${request.url}',
      500,
    );
  });
}

String _sseText(String text) {
  return 'data: ${jsonEncode(<String, dynamic>{
    'id': 'event-1',
    'author': 'agent_awesome',
    'content': <String, dynamic>{
      'parts': <Map<String, dynamic>>[
        <String, dynamic>{'text': text},
      ],
    },
  })}\n\n';
}

const String _baseUrl = 'http://127.0.0.1:8070/api';
const String _appName = 'agent_awesome';
const String _userId = 'doug';
const String _sessionId = 'utility-session';

const String _modelConfig = '''
default: openai:gpt-mini
providers:
  openai:
    adapter: openai
    default: gpt-mini
    models:
      - id: gpt-mini
        model: gpt-5-mini
''';
