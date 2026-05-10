/// Tests shared model invocation config resolution.
library;

import 'dart:io';

import 'package:agentawesome_ui/clients/model_invocation_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs model invocation config tests.
void main() {
  test('resolves provider base url, api key, and wire model', () async {
    final file = await _writeModelConfig('''
default: openai:gpt-mini
providers:
  openai:
    adapter: openai
    api-key: OPENAI_API_KEY
    default: gpt-mini
    base_url: https://example.test/v1/
    models:
      - id: gpt-mini
        model: gpt-5.4-mini
''');

    final config = await resolveModelInvocationConfig(
      modelConfigPath: file.path,
      modelRef: '',
      environment: const <String, String>{'OPENAI_API_KEY': 'test-key'},
      messages: _messages,
    );

    expect(config.adapter, 'openai');
    expect(config.url, 'https://example.test/v1/chat/completions');
    expect(config.apiKey, 'test-key');
    expect(config.model, 'gpt-5.4-mini');
  });

  test('keeps explicit unknown model refs as direct wire models', () async {
    final file = await _writeModelConfig('''
default: openai:gpt-mini
providers:
  openai:
    adapter: openai
    default: gpt-mini
    url: https://api.openai.com/v1/chat/completions
    models:
      - id: gpt-mini
        model: gpt-5.4-mini
''');

    final config = await resolveModelInvocationConfig(
      modelConfigPath: file.path,
      modelRef: 'openai:gpt-custom',
      environment: const <String, String>{},
      messages: _messages,
    );

    expect(config.model, 'gpt-custom');
  });

  test('uses local chat completions URL for litert providers', () async {
    final file = await _writeModelConfig('''
default: local:gemma
providers:
  local:
    adapter: litert
    default: gemma
    models:
      - id: gemma
        model: gemma-4-E2B-it
''');

    final config = await resolveModelInvocationConfig(
      modelConfigPath: file.path,
      modelRef: '',
      environment: const <String, String>{},
      localModelChatCompletionsUrl: 'http://127.0.0.1:4321/v1/chat/completions',
      messages: _messages,
    );

    expect(config.url, 'http://127.0.0.1:4321/v1/chat/completions');
    expect(config.model, 'gemma-4-E2B-it');
  });

  test('detects completion token limit models', () {
    expect(usesCompletionTokenLimit('gpt-5.4-mini'), isTrue);
    expect(usesCompletionTokenLimit('o4-mini'), isTrue);
    expect(usesCompletionTokenLimit('gpt-4o'), isFalse);
  });
}

/// Writes a temporary model config fixture.
Future<File> _writeModelConfig(String content) async {
  final directory = await Directory.systemTemp.createTemp(
    'agentawesome-model-invocation-test-',
  );
  final file = File('${directory.path}/model.yaml');
  await file.writeAsString(content);
  return file;
}

const ModelInvocationConfigMessages _messages = ModelInvocationConfigMessages(
  missingSelection: 'Model config is not selected',
  missingFilePrefix: 'Model config is missing',
  missingProviders: 'Model config has no providers',
  missingDefaultModel: 'Model default model is missing',
);
