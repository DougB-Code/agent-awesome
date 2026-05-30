/// Tests structured model provider config parsing and serialization.
library;

import 'package:agentawesome_ui/domain/model_config.dart';
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
        model: gpt-5-mini
      - id: gpt-nano
        model: gpt-5-nano
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
    expect(document.providers.first.models.last.model, 'gpt-5-nano');
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
        model: gpt-5-mini
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
            const ModelConfigModel(id: 'gpt-nano', model: 'gpt-5-nano'),
          ],
        ),
      ],
    );

    final encoded = next.toYaml();
    expect(encoded, contains('default: openai:gpt-nano'));
    expect(encoded, contains('name: OpenAI'));
    expect(
      encoded,
      contains('      - id: gpt-mini\n        model: gpt-5-mini'),
    );
    expect(
      encoded,
      contains('      - id: gpt-nano\n        model: gpt-5-nano'),
    );
    expect(encoded, isNot(contains('      -\n        id:')));
    expect(encoded, contains('id: gpt-nano'));
    expect(encoded, contains('capabilities:'));
    expect(encoded, contains('streaming: true'));
  });

  test('parses model compatibility validations from YAML', () {
    final document = ModelConfigDocument.parse('''
default: openai:gpt-mini
providers:
  openai:
    name: OpenAI
    adapter: openai
    default: gpt-mini
    models:
      - id: gpt-mini
        model: gpt-5-mini
validations:
  - id: follows_tools
    label: Follows tool contracts
    mode: mocked
    prompt: Use the configured tool.
    assertions:
      - type: response-contains
        contains: done
''');

    expect(document.validations.single.id, 'follows_tools');
    expect(document.validations.single.label, 'Follows tool contracts');
    expect(document.toYaml(), contains('validations:'));
    expect(document.toYaml(), contains('contains: done'));
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
        model: gpt-5-mini
      - id: gpt-mini
        model: gpt-5-nano
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
        model: gpt-5-mini
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
        model: gpt-5-mini
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

  test('scopes multi-provider documents to the default provider', () {
    final document = ModelConfigDocument.parse('''
default: openai:gpt-mini
providers:
  openai:
    name: openai
    adapter: openai
    default: gpt-mini
    models:
      - id: gpt-mini
        model: gpt-5-mini
  cloudflare:
    name: Cloudflare
    adapter: openai
    default: gemma
    models:
      - id: gemma
        model: workers-ai/@cf/google/gemma-4-26b-a4b-it
''');
    final next = modelConfigDocumentForDefaultProvider(document);

    expect(next.defaultRef, 'openai:gpt-mini');
    expect(next.providers.single.id, 'openai');
    expect(modelConfigDisplayName(next.toYaml()), 'openai');
  });

  test('validates one provider per model config file', () {
    final document = ModelConfigDocument.parse('''
default: openai:gpt-mini
providers:
  openai:
    name: openai
    adapter: openai
    default: gpt-mini
    models:
      - id: gpt-mini
        model: gpt-5-mini
  litert-lm:
    name: LiteRT-LM
    adapter: openai
    default: gemma-4-e2b-it
    models:
      - id: gemma-4-e2b-it
        model: gemma-4-E2B-it
''');

    expect(
      modelConfigValidationError(document),
      'Model config files can contain only one provider',
    );
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
        model: gpt-5-mini
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

  test('parses provider refs while preserving colons in model ids', () {
    final ref = parseModelProviderRef('openai:ft:gpt-mini:2026');

    expect(ref.providerId, 'openai');
    expect(ref.modelId, 'ft:gpt-mini:2026');
    expect(ref.ref, 'openai:ft:gpt-mini:2026');
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
        model: gpt-5-mini
      - id: gpt-nano
        model: gpt-5-nano
''');

    expect(choices.map((choice) => choice.ref), <String>[
      'openai:gpt-mini',
      'openai:gpt-nano',
    ]);
    expect(choices.last.label, 'OpenAI / gpt-nano');
    expect(choices.last.isDefault, isTrue);
  });
}
