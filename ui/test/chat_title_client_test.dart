/// Tests ADK-backed chat title generation.
library;

import 'dart:convert';

import 'package:agentawesome_ui/clients/chat_title_client.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Runs chat title client tests.
void main() {
  test('generates chat title through ADK with default model ref', () async {
    late Map<String, dynamic> runBody;
    final client = ChatTitleClient(
      baseUrl: _baseUrl,
      appName: _appName,
      userId: _userId,
      httpClient: _mockAdkClient(
        responseText: '"Buy Coffee"',
        onRunBody: (body) => runBody = body,
      ),
    );

    final title = await client.generateTitle(
      modelConfigContent: _modelConfig,
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
    expect(runBody['appName'], _appName);
    expect(runBody['userId'], _userId);
    expect(runBody['stateDelta'], <String, dynamic>{
      'agentawesome.model_ref': 'openai:gpt-mini',
    });
    expect(jsonEncode(runBody), contains('Need to buy coffee'));
    client.close();
  });

  test('generates chat title from selected model ref', () async {
    late Map<String, dynamic> runBody;
    final client = ChatTitleClient(
      baseUrl: _baseUrl,
      appName: _appName,
      userId: _userId,
      httpClient: _mockAdkClient(
        responseText: 'Coffee Errand',
        onRunBody: (body) => runBody = body,
      ),
    );

    final title = await client.generateTitle(
      modelConfigContent: _modelConfig,
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
    expect(runBody['stateDelta'], <String, dynamic>{
      'agentawesome.model_ref': 'openai:gpt-nano',
    });
    client.close();
  });

  test('routes local model refs through ADK instead of local HTTP', () async {
    late Map<String, dynamic> runBody;
    final client = ChatTitleClient(
      baseUrl: _baseUrl,
      appName: _appName,
      userId: _userId,
      httpClient: _mockAdkClient(
        responseText: 'Migration Plan',
        onRunBody: (body) => runBody = body,
      ),
    );

    final title = await client.generateTitle(
      modelConfigContent: _localModelConfig,
      messages: <ChatMessage>[
        ChatMessage(
          id: '1',
          role: ChatRole.user,
          author: 'You',
          text: 'Plan the migration for the UI process supervisor.',
          createdAt: _testTime,
        ),
      ],
    );

    expect(title, 'Migration Plan');
    expect(runBody['stateDelta'], <String, dynamic>{
      'agentawesome.model_ref': 'litert-lm:gemma',
    });
    client.close();
  });

  test('reports missing model config before calling ADK', () async {
    final client = ChatTitleClient(
      baseUrl: _baseUrl,
      appName: _appName,
      userId: _userId,
      httpClient: MockClient((request) async {
        fail('ADK should not be called for a missing model config');
      }),
    );

    await expectLater(
      client.generateTitle(
        modelConfigContent: '',
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
      - id: gpt-nano
        model: gpt-5-nano
''';

const String _localModelConfig = '''
default: litert-lm:gemma
providers:
  litert-lm:
    name: LiteRT-LM
    adapter: openai
    auth: optional
    runtime: litert-lm
    url: http://127.0.0.1:11666/v1/chat/completions
    default: gemma
    models:
      - id: gemma
        model: gemma-4-E2B-it
''';

final DateTime _testTime = DateTime(2026, 4, 30, 12);
