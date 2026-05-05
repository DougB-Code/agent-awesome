/// Tests model-backed chat title generation.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentawesome_ui/clients/chat_title_client.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Runs chat title client tests.
void main() {
  test('generates openai compatible chat title from model config', () async {
    final file = await _writeModelConfig();
    final client = ChatTitleClient(
      environment: const <String, String>{'OPENAI_API_KEY': 'test-key'},
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.openai.com/v1/chat/completions',
        );
        expect(request.headers['Authorization'], 'Bearer test-key');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'gpt-5.4-mini');
        expect(body['max_completion_tokens'], 24);
        expect(body.containsKey('max_tokens'), isFalse);
        expect(jsonEncode(body['messages']), contains('Need to buy coffee'));
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <Map<String, dynamic>>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': '"Buy Coffee"'},
              },
            ],
          }),
          200,
        );
      }),
    );

    final title = await client.generateTitle(
      modelConfigPath: file.path,
      messages: <ChatMessage>[
        ChatMessage(
          id: '1',
          role: ChatRole.user,
          author: 'You',
          text: 'Need to buy coffee next Friday.',
          createdAt: _testTime,
        ),
      ],
    );

    expect(title, 'Buy Coffee');
    client.close();
  });

  test('generates chat title from selected provider model ref', () async {
    final file = await _writeModelConfig();
    final client = ChatTitleClient(
      environment: const <String, String>{'OPENAI_API_KEY': 'test-key'},
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'gpt-5.4-nano');
        expect(body['max_completion_tokens'], 24);
        expect(body.containsKey('max_tokens'), isFalse);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <Map<String, dynamic>>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': 'Coffee Errand'},
              },
            ],
          }),
          200,
        );
      }),
    );

    final title = await client.generateTitle(
      modelConfigPath: file.path,
      modelRef: 'openai:gpt-nano',
      messages: <ChatMessage>[
        ChatMessage(
          id: '1',
          role: ChatRole.user,
          author: 'You',
          text: 'Need to buy coffee next Friday.',
          createdAt: _testTime,
        ),
      ],
    );

    expect(title, 'Coffee Errand');
    client.close();
  });

  test('reports missing environment variable for configured api key', () async {
    final file = await _writeModelConfig();
    final client = ChatTitleClient(
      environment: const <String, String>{},
      httpClient: MockClient((request) async => http.Response('{}', 200)),
    );

    await expectLater(
      client.generateTitle(
        modelConfigPath: file.path,
        messages: <ChatMessage>[
          ChatMessage(
            id: '1',
            role: ChatRole.user,
            author: 'You',
            text: 'Need to buy coffee next Friday.',
            createdAt: _testTime,
          ),
        ],
      ),
      throwsA(isA<ChatTitleException>()),
    );
    client.close();
  });
}

/// Writes a temporary model config matching the app harness schema.
Future<File> _writeModelConfig() async {
  final directory = await Directory.systemTemp.createTemp('aurora-title-test-');
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
      - id: gpt-nano
        model: gpt-5.4-nano
''');
  return file;
}

final DateTime _testTime = DateTime(2026, 4, 30, 12);
