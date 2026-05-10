/// Tests model-backed screen-command planning.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentawesome_ui/clients/screen_command_client.dart';
import 'package:agentawesome_ui/domain/screen_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Runs screen-command client tests.
void main() {
  test('plans backlog command from model config', () async {
    final file = await _writeModelConfig();
    final client = ScreenCommandClient(
      environment: const <String, String>{'OPENAI_API_KEY': 'test-key'},
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.openai.com/v1/chat/completions',
        );
        expect(request.headers['Authorization'], 'Bearer test-key');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'gpt-5.4-mini');
        expect(body['max_completion_tokens'], 1600);
        expect(body.containsKey('max_tokens'), isFalse);
        expect(jsonEncode(body['messages']), contains('Draft schema'));
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <Map<String, dynamic>>[
              <String, dynamic>{
                'message': <String, dynamic>{
                  'content':
                      '{"intent":"change","confidence":0.9,"changes":[{"operation":"update_task","target":{"task_id":"task-1"},"summary":"Raise priority","confidence":0.95,"fields":{"priority":"high"}}]}',
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final run = await client.planBacklogCommand(
      modelConfigPath: file.path,
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
    client.close();
  });
}

/// Writes a temporary model config for planner calls.
Future<File> _writeModelConfig() async {
  final directory = await Directory.systemTemp.createTemp(
    'agentawesome-screen-command-test-',
  );
  final file = File('${directory.path}/model.yaml');
  await file.writeAsString('''
default: openai:gpt-mini
providers:
  openai:
    adapter: openai
    api-key: OPENAI_API_KEY
    default: gpt-mini
    url: https://api.openai.com/v1/chat/completions
    models:
      - id: gpt-mini
        model: gpt-5.4-mini
''');
  return file;
}
