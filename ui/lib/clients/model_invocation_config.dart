/// Resolves app-owned model config files into HTTP invocation targets.
library;

import 'dart:io';

import '../app/model_config.dart';

/// ModelInvocationConfig stores a resolved model endpoint and credential.
class ModelInvocationConfig {
  /// Creates a resolved model invocation config.
  const ModelInvocationConfig({
    required this.adapter,
    required this.url,
    required this.apiKey,
    required this.model,
  });

  /// Harness adapter name.
  final String adapter;

  /// HTTP endpoint used for generation.
  final String url;

  /// Resolved provider API key.
  final String apiKey;

  /// Provider-specific model identifier sent on the wire.
  final String model;
}

/// ModelInvocationConfigMessages stores caller-specific error text.
class ModelInvocationConfigMessages {
  /// Creates caller-specific model config failure messages.
  const ModelInvocationConfigMessages({
    required this.missingSelection,
    required this.missingFilePrefix,
    required this.missingProviders,
    required this.missingDefaultModel,
  });

  /// Message used when no config or provider was selected.
  final String missingSelection;

  /// Prefix used before the missing file path.
  final String missingFilePrefix;

  /// Message used when the config has no provider map.
  final String missingProviders;

  /// Message used when no model can be resolved.
  final String missingDefaultModel;
}

/// ModelInvocationConfigException reports model config resolution failures.
class ModelInvocationConfigException implements Exception {
  /// Creates a model invocation config exception.
  const ModelInvocationConfigException(this.message);

  /// Human-readable failure detail.
  final String message;

  @override
  String toString() => 'ModelInvocationConfigException: $message';
}

/// Resolves the provider, model, endpoint, and credential for one model call.
Future<ModelInvocationConfig> resolveModelInvocationConfig({
  required String modelConfigPath,
  required String modelRef,
  required Map<String, String> environment,
  required ModelInvocationConfigMessages messages,
  String localModelChatCompletionsUrl = '',
}) async {
  final path = modelConfigPath.trim();
  if (path.isEmpty) {
    throw ModelInvocationConfigException(messages.missingSelection);
  }
  final file = File(path);
  if (!await file.exists()) {
    throw ModelInvocationConfigException(
      '${messages.missingFilePrefix}: $path',
    );
  }
  final document = ModelConfigDocument.parse(await file.readAsString());
  if (document.providers.isEmpty) {
    throw ModelInvocationConfigException(messages.missingProviders);
  }
  final configuredRef = modelRef.trim();
  final parsedRef = parseModelProviderRef(
    configuredRef.isEmpty ? document.defaultRef : configuredRef,
  );
  if (parsedRef.providerId.isEmpty) {
    throw ModelInvocationConfigException(messages.missingSelection);
  }
  final provider = _providerFor(document, parsedRef.providerId);
  if (provider == null) {
    throw ModelInvocationConfigException(
      'Provider "${parsedRef.providerId}" is not configured',
    );
  }
  final modelId = parsedRef.modelId.isEmpty
      ? provider.defaultModel
      : parsedRef.modelId;
  final model = _wireModelForProvider(
    provider: provider,
    modelId: modelId,
    missingDefaultModel: messages.missingDefaultModel,
  );
  return ModelInvocationConfig(
    adapter: provider.adapter,
    url: modelInvocationProviderUrl(
      provider,
      localModelChatCompletionsUrl: localModelChatCompletionsUrl,
    ),
    apiKey: resolveModelInvocationApiKey(
      provider.apiKey,
      environment: environment,
    ),
    model: model,
  );
}

/// Returns the request URL for one configured provider.
String modelInvocationProviderUrl(
  ModelProviderConfig provider, {
  String localModelChatCompletionsUrl = '',
}) {
  if (provider.url.isNotEmpty) {
    return provider.url;
  }
  final adapter = provider.adapter;
  if (adapter == 'litert' && localModelChatCompletionsUrl.isNotEmpty) {
    return localModelChatCompletionsUrl.trim();
  }
  final base = _providerBaseUrl(provider);
  if (base.isEmpty) {
    if (adapter == 'openai') {
      return 'https://api.openai.com/v1/chat/completions';
    }
    if (adapter == 'anthropic') {
      return 'https://api.anthropic.com/v1/messages';
    }
    throw const ModelInvocationConfigException(
      'Provider url or base_url is required',
    );
  }
  final trimmed = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  return adapter == 'anthropic'
      ? '$trimmed/messages'
      : '$trimmed/chat/completions';
}

/// Resolves an API key reference from the configured environment.
String resolveModelInvocationApiKey(
  String reference, {
  required Map<String, String> environment,
}) {
  if (reference.isEmpty) {
    return '';
  }
  final fromEnvironment = environment[reference];
  if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
    return fromEnvironment;
  }
  if (RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(reference)) {
    throw ModelInvocationConfigException(
      'Environment variable $reference is not set',
    );
  }
  return reference;
}

/// Returns whether an OpenAI-compatible model requires max_completion_tokens.
bool usesCompletionTokenLimit(String model) {
  final normalized = model.trim().toLowerCase();
  return normalized.startsWith('gpt-5') ||
      normalized.startsWith('o1') ||
      normalized.startsWith('o3') ||
      normalized.startsWith('o4');
}

/// Clips long provider bodies for display and logs.
String clipProviderBody(String value) {
  const limit = 500;
  if (value.length <= limit) {
    return value;
  }
  return '${value.substring(0, limit)}...';
}

/// Converts a dynamic scalar to a trimmed string.
String modelInvocationString(dynamic value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

/// Returns a provider by id from a parsed config document.
ModelProviderConfig? _providerFor(
  ModelConfigDocument document,
  String providerId,
) {
  for (final provider in document.providers) {
    if (provider.id == providerId) {
      return provider;
    }
  }
  return null;
}

/// Returns the provider-native model name selected for invocation.
String _wireModelForProvider({
  required ModelProviderConfig provider,
  required String modelId,
  required String missingDefaultModel,
}) {
  final id = modelId.trim();
  final configuredModel = _exactModelForProvider(provider, id);
  if (configuredModel != null) {
    return modelInvocationString(configuredModel.model, fallback: id);
  }
  if (id.isNotEmpty) {
    return id;
  }
  throw ModelInvocationConfigException(missingDefaultModel);
}

/// Returns a model by exact provider-local id.
ModelConfigModel? _exactModelForProvider(
  ModelProviderConfig provider,
  String modelId,
) {
  for (final model in provider.models) {
    if (model.id == modelId) {
      return model;
    }
  }
  return null;
}

/// Reads the optional base_url field preserved in provider extras.
String _providerBaseUrl(ModelProviderConfig provider) {
  return modelInvocationString(
    provider.extra['base_url'] ?? provider.extra['base-url'],
  );
}
