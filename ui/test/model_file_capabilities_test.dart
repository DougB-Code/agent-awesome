/// Tests active model file capability resolution.
library;

import 'package:agentawesome_ui/domain/model_config.dart';
import 'package:agentawesome_ui/app/model_file_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs model file capability tests.
void main() {
  test('uses base64 fallback for models without known native files', () {
    final capabilities = modelFileCapabilitiesFor(
      provider: const ModelProviderConfig(
        id: 'litert-lm',
        name: 'LiteRT-LM',
        adapter: 'openai',
        apiKey: '',
        defaultModel: 'small',
        url: 'http://127.0.0.1:11666/v1/chat/completions',
        endpoints: <String, String>{},
        extra: <String, dynamic>{'auth': 'optional', 'runtime': 'litert-lm'},
        models: <ModelConfigModel>[
          ModelConfigModel(id: 'small', model: 'gemma-3n'),
        ],
      ),
      model: const ModelConfigModel(id: 'small', model: 'gemma-3n'),
    );

    expect(capabilities.nativeFileParts, isFalse);
    expect(capabilities.transport, ModelFileTransport.base64Text);
  });

  test('detects known native-capable providers but keeps runtime fallback', () {
    final capabilities = modelFileCapabilitiesFor(
      provider: const ModelProviderConfig(
        id: 'openai',
        name: 'OpenAI',
        adapter: 'openai',
        apiKey: 'env:OPENAI_API_KEY',
        defaultModel: 'main',
        url: '',
        endpoints: <String, String>{},
        models: <ModelConfigModel>[
          ModelConfigModel(id: 'main', model: 'gpt-5-mini'),
        ],
      ),
      model: const ModelConfigModel(id: 'main', model: 'gpt-5-mini'),
    );

    expect(capabilities.nativeFileParts, isTrue);
    expect(capabilities.transport, ModelFileTransport.base64Text);
    expect(capabilities.reason, contains('runtime uses text parts'));
  });

  test('respects explicit native transport override', () {
    final capabilities = modelFileCapabilitiesFor(
      provider: const ModelProviderConfig(
        id: 'google',
        name: 'Google',
        adapter: 'google',
        apiKey: 'env:GOOGLE_API_KEY',
        defaultModel: 'main',
        url: '',
        endpoints: <String, String>{},
        models: <ModelConfigModel>[
          ModelConfigModel(
            id: 'main',
            model: 'gemini-2.5-pro',
            extra: <String, dynamic>{'file_transport': 'native'},
          ),
        ],
      ),
      model: const ModelConfigModel(
        id: 'main',
        model: 'gemini-2.5-pro',
        extra: <String, dynamic>{'file_transport': 'native'},
      ),
    );

    expect(capabilities.nativeFileParts, isTrue);
    expect(capabilities.transport, ModelFileTransport.nativeParts);
  });
}
