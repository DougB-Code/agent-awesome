/// Tests structured model provider config parsing and serialization.
library;

import 'package:agentawesome_ui/app/model_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs model config document tests.
void main() {
  test('parses providers and models from harness model config', () {
    final document = ModelConfigDocument.parse('''
default: openai:gpt-mini
providers:
  openai:
    name: OpenAI
    adapter: openai
    api-key: OPENAI_API_KEY
    default: gpt-mini
    url: https://api.openai.com/v1/chat/completions
    models:
      - id: gpt-mini
        model: gpt-5.4-mini
      - id: gpt-nano
        model: gpt-5.4-nano
  cloudflare:
    name: Cloudflare
    adapter: openai
    api-key: CLOUDFLARE_API_KEY
    default: gemma
    url: \${CLOUDFLARE_GATEWAY_URL}
    models:
      - id: gemma
        model: workers-ai/@cf/google/gemma-4-26b-a4b-it
        capabilities:
          streaming: true
''');

    expect(document.defaultRef, 'openai:gpt-mini');
    expect(document.providers.map((provider) => provider.id), <String>[
      'openai',
      'cloudflare',
    ]);
    expect(document.providers.first.name, 'OpenAI');
    expect(document.providers.last.displayName, 'Cloudflare');
    expect(document.providers.first.models.last.model, 'gpt-5.4-nano');
    expect(document.providers.last.models.single.extra['capabilities'], {
      'streaming': true,
    });
  });

  test('serializes provider model changes without dropping extra fields', () {
    final document = ModelConfigDocument.parse('''
default: openai:gpt-mini
providers:
  openai:
    name: OpenAI
    adapter: openai
    api-key: OPENAI_API_KEY
    default: gpt-mini
    url: https://api.openai.com/v1/chat/completions
    models:
      - id: gpt-mini
        model: gpt-5.4-mini
        capabilities:
          streaming: true
''');
    final provider = document.providers.single;
    final next = document.copyWith(
      defaultRef: 'openai:gpt-nano',
      providers: <ModelProviderConfig>[
        provider.copyWith(
          defaultModel: 'gpt-nano',
          models: <ModelConfigModel>[
            ...provider.models,
            const ModelConfigModel(id: 'gpt-nano', model: 'gpt-5.4-nano'),
          ],
        ),
      ],
    );

    final encoded = next.toYaml();
    expect(encoded, contains('default: openai:gpt-nano'));
    expect(encoded, contains('name: OpenAI'));
    expect(
      encoded,
      contains('      - id: gpt-mini\n        model: gpt-5.4-mini'),
    );
    expect(
      encoded,
      contains('      - id: gpt-nano\n        model: gpt-5.4-nano'),
    );
    expect(encoded, isNot(contains('      -\n        id:')));
    expect(encoded, contains('id: gpt-nano'));
    expect(encoded, contains('capabilities:'));
    expect(encoded, contains('streaming: true'));
  });

  test('validates duplicate provider and model ids', () {
    final document = ModelConfigDocument.parse('''
default: openai:gpt-mini
providers:
  openai:
    adapter: openai
    default: gpt-mini
    models:
      - id: gpt-mini
        model: gpt-5.4-mini
      - id: gpt-mini
        model: gpt-5.4-nano
''');

    expect(
      modelConfigValidationError(document),
      'Model id "gpt-mini" is duplicated in openai',
    );
  });

  test('uses default provider name as config display name', () {
    final displayName = modelConfigDisplayName('''
default: openai:gpt-mini
providers:
  openai:
    name: OpenAI
    adapter: openai
    default: gpt-mini
    models:
      - id: gpt-mini
        model: gpt-5.4-mini
''');

    expect(displayName, 'OpenAI');
  });

  test('defaults missing provider name from provider id', () {
    final document = ModelConfigDocument.parse('''
default: openai:gpt-mini
providers:
  openai:
    adapter: openai
    default: gpt-mini
    models:
      - id: gpt-mini
        model: gpt-5.4-mini
''');

    expect(document.providers.single.id, 'openai');
    expect(document.providers.single.name, 'openai');
    expect(modelConfigDisplayName(document.toYaml()), 'openai');
    expect(document.toYaml(), contains('name: openai'));
  });

  test('creates generated providers with readable names', () {
    final provider = newModelProviderConfig('provider-2');

    expect(provider.id, 'provider-2');
    expect(provider.name, 'Provider 2');
    expect(provider.toJson()['name'], 'Provider 2');
  });

  test('appends generated provider without changing existing default', () {
    final document = ModelConfigDocument.parse('''
default: openai:gpt-mini
providers:
  openai:
    name: openai
    adapter: openai
    default: gpt-mini
    models:
      - id: gpt-mini
        model: gpt-5.4-mini
''');
    final provider = newModelProviderConfig('provider');
    final next = document.copyWith(
      providers: <ModelProviderConfig>[...document.providers, provider],
    );

    expect(next.defaultRef, 'openai:gpt-mini');
    expect(next.providers.last.name, 'Provider');
    expect(modelConfigDisplayName(next.toYaml()), 'openai');
  });

  test('encodes a selected provider preview without sibling providers', () {
    final document = ModelConfigDocument.parse('''
default: openai:gpt-mini
providers:
  openai:
    name: OpenAI
    adapter: openai
    default: gpt-mini
    models:
      - id: gpt-mini
        model: gpt-5.4-mini
  cloudflare:
    name: Cloudflare
    adapter: openai
    default: gemma
    models:
      - id: gemma
        model: workers-ai/@cf/google/gemma-4-26b-a4b-it
''');

    final preview = modelProviderConfigYaml(document.providers.first);

    expect(preview, startsWith('openai:\n'));
    expect(preview, contains('  name: OpenAI'));
    expect(preview, contains('    - id: gpt-mini'));
    expect(preview, isNot(contains('cloudflare')));
  });

  test('builds top-level default references from provider defaults', () {
    final provider = newModelProviderConfig('provider-2').copyWith(
      defaultModel: 'fast',
      models: const <ModelConfigModel>[
        ModelConfigModel(id: 'fast', model: 'provider-fast-model'),
      ],
    );

    expect(modelProviderDefaultRef(provider), 'provider-2:fast');
  });

  test('lists provider model choices with exact refs', () {
    final choices = modelConfigChoices('''
default: openai:gpt-nano
providers:
  openai:
    name: OpenAI
    adapter: openai
    default: gpt-mini
    models:
      - id: gpt-mini
        model: gpt-5.4-mini
      - id: gpt-nano
        model: gpt-5.4-nano
''');

    expect(choices.map((choice) => choice.ref), <String>[
      'openai:gpt-mini',
      'openai:gpt-nano',
    ]);
    expect(choices.last.label, 'OpenAI / gpt-nano');
    expect(choices.last.isDefault, isTrue);
  });
}
