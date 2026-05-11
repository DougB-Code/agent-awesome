/// Defines first-run model setup choices and result data.
library;

import '../domain/model_config.dart';
import 'local_model_runtime.dart';

/// OnboardingModelOption stores one selectable model for first-run setup.
class OnboardingModelOption {
  /// Creates a selectable first-run model.
  const OnboardingModelOption({
    required this.id,
    required this.name,
    required this.model,
    required this.detail,
  });

  /// Stable model id written into Agent Awesome config.
  final String id;

  /// User-facing model name.
  final String name;

  /// Provider-specific model name sent to the runtime adapter.
  final String model;

  /// Short user-facing description.
  final String detail;
}

/// OnboardingProviderOption stores one cloud provider setup choice.
class OnboardingProviderOption {
  /// Creates a selectable first-run provider.
  const OnboardingProviderOption({
    required this.id,
    required this.name,
    required this.adapter,
    required this.credentialReference,
    required this.url,
    required this.models,
  });

  /// Stable provider id written into Agent Awesome config.
  final String id;

  /// User-facing provider name.
  final String name;

  /// Harness model adapter name.
  final String adapter;

  /// OS keyring credential reference.
  final String credentialReference;

  /// Provider endpoint URL, when required by the adapter.
  final String url;

  /// Selectable models for this provider.
  final List<OnboardingModelOption> models;

  /// Returns this provider as an editable model provider config.
  ModelProviderConfig toProviderConfig({required String modelId}) {
    final selectedModel = modelForId(modelId);
    return ModelProviderConfig(
      id: id,
      name: name,
      adapter: adapter,
      apiKey: credentialReference,
      defaultModel: selectedModel.id,
      url: url,
      models: <ModelConfigModel>[
        ModelConfigModel(id: selectedModel.id, model: selectedModel.model),
      ],
    );
  }

  /// Returns a model choice by id, falling back to the first choice.
  OnboardingModelOption modelForId(String modelId) {
    for (final model in models) {
      if (model.id == modelId) {
        return model;
      }
    }
    return models.first;
  }
}

/// OnboardingModelSetupResult reports the outcome of first-run model setup.
class OnboardingModelSetupResult {
  /// Creates a first-run model setup result.
  const OnboardingModelSetupResult({
    required this.success,
    required this.message,
    this.providerName = '',
    this.modelId = '',
  });

  /// Whether setup completed.
  final bool success;

  /// User-facing status message.
  final String message;

  /// Provider configured during setup.
  final String providerName;

  /// Model id configured during setup.
  final String modelId;
}

/// Cloud providers supported by first-run setup.
const List<OnboardingProviderOption> onboardingCloudProviders =
    <OnboardingProviderOption>[
      OnboardingProviderOption(
        id: 'openai',
        name: 'OpenAI',
        adapter: 'openai',
        credentialReference: 'OPENAI_API_KEY',
        url: 'https://api.openai.com/v1/chat/completions',
        models: <OnboardingModelOption>[
          OnboardingModelOption(
            id: 'gpt-4.1-mini',
            name: 'GPT-4.1 mini',
            model: 'gpt-4.1-mini',
            detail: 'Fast everyday chat and setup help.',
          ),
          OnboardingModelOption(
            id: 'gpt-4.1',
            name: 'GPT-4.1',
            model: 'gpt-4.1',
            detail: 'Stronger reasoning for heavier tasks.',
          ),
        ],
      ),
      OnboardingProviderOption(
        id: 'anthropic',
        name: 'Anthropic',
        adapter: 'anthropic',
        credentialReference: 'ANTHROPIC_API_KEY',
        url: 'https://api.anthropic.com/v1/messages',
        models: <OnboardingModelOption>[
          OnboardingModelOption(
            id: 'claude-sonnet',
            name: 'Claude Sonnet',
            model: 'claude-sonnet-4-5',
            detail: 'Balanced reasoning and writing.',
          ),
          OnboardingModelOption(
            id: 'claude-haiku',
            name: 'Claude Haiku',
            model: 'claude-haiku-4-5',
            detail: 'Lower latency for quick work.',
          ),
        ],
      ),
      OnboardingProviderOption(
        id: 'google',
        name: 'Google',
        adapter: 'google',
        credentialReference: 'GOOGLE_API_KEY',
        url: '',
        models: <OnboardingModelOption>[
          OnboardingModelOption(
            id: 'gemini-flash',
            name: 'Gemini Flash',
            model: 'gemini-3.1-flash-preview',
            detail: 'Fast Gemini chat and tool use.',
          ),
          OnboardingModelOption(
            id: 'gemini-pro',
            name: 'Gemini Pro',
            model: 'gemini-3.1-pro-preview',
            detail: 'Stronger Gemini reasoning.',
          ),
        ],
      ),
    ];

/// Apache-licensed local LiteRT-LM model presets supported by setup.
const List<OnboardingModelOption> onboardingLocalModels =
    <OnboardingModelOption>[
      OnboardingModelOption(
        id: 'gemma-4-e2b-it',
        name: 'Gemma 4 E2B',
        model: 'gemma-4-E2B-it',
        detail: 'Apache-licensed LiteRT-LM model installed on this device.',
      ),
    ];

/// LiteRT-LM artifact used for first-run local setup.
const LocalModelDescriptor gemma4E2BLocalModel = LocalModelDescriptor(
  id: 'gemma-4-e2b-it',
  displayName: 'Gemma 4 E2B',
  modelName: 'gemma-4-E2B-it',
  repository: 'litert-community/gemma-4-E2B-it-litert-lm',
  revision: 'b4f4f4df93418ddb4aa7da8bf33b584602a5b9f8',
  fileName: 'gemma-4-E2B-it.litertlm',
  downloadUrl:
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b4f4f4df93418ddb4aa7da8bf33b584602a5b9f8/gemma-4-E2B-it.litertlm',
  expectedBytes: 2588147712,
  expectedSha256:
      '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
  license: 'Apache-2.0',
);

/// Returns a cloud provider by id, falling back to OpenAI.
OnboardingProviderOption onboardingCloudProviderById(String providerId) {
  for (final provider in onboardingCloudProviders) {
    if (provider.id == providerId) {
      return provider;
    }
  }
  return onboardingCloudProviders.first;
}

/// Returns a local model by id, falling back to the recommended model.
OnboardingModelOption onboardingLocalModelById(String modelId) {
  for (final model in onboardingLocalModels) {
    if (model.id == modelId) {
      return model;
    }
  }
  return onboardingLocalModels.first;
}

/// Returns local model artifact metadata by setup model id.
LocalModelDescriptor onboardingLocalModelDescriptor(String modelId) {
  final model = onboardingLocalModelById(modelId);
  return switch (model.id) {
    'gemma-4-e2b-it' => gemma4E2BLocalModel,
    _ => gemma4E2BLocalModel,
  };
}

/// Returns a local LiteRT provider config for first-run setup.
ModelProviderConfig onboardingLocalProviderConfig({
  required String modelId,
  required String executable,
  required String modelPath,
}) {
  final selected = onboardingLocalModelById(modelId);
  return ModelProviderConfig(
    id: 'local',
    name: 'Local model',
    adapter: 'litert',
    apiKey: '',
    defaultModel: selected.id,
    url: '',
    executable: executable,
    models: <ModelConfigModel>[
      ModelConfigModel(id: selected.id, model: selected.model, path: modelPath),
    ],
  );
}
