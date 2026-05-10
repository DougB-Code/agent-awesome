/// Resolves model file handling so chat can choose native or base64 transport.
library;

import 'model_config.dart';

/// ModelFileTransport names how files should be passed to the active model.
enum ModelFileTransport {
  /// The model/runtime can receive provider-native file or inline data parts.
  nativeParts,

  /// The file must be serialized into a text/base64 prompt envelope.
  base64Text,
}

/// ModelFileCapabilities describes the active model's file behavior.
class ModelFileCapabilities {
  /// Creates a resolved file capability decision.
  const ModelFileCapabilities({
    required this.providerId,
    required this.adapter,
    required this.modelId,
    required this.modelName,
    required this.nativeFileParts,
    required this.transport,
    required this.reason,
  });

  /// Provider id from the model config.
  final String providerId;

  /// Harness adapter from the model config.
  final String adapter;

  /// Model alias from the model config.
  final String modelId;

  /// Provider model name sent to the runtime.
  final String modelName;

  /// Whether the configured provider/model is known to accept native file parts.
  final bool nativeFileParts;

  /// Transport the UI should use today.
  final ModelFileTransport transport;

  /// Short human-readable explanation.
  final String reason;

  /// Returns whether chat must inline a base64/text file envelope.
  bool get usesBase64Fallback => transport == ModelFileTransport.base64Text;
}

/// ActiveModelFileSelection stores the provider and model chosen by config.
class ActiveModelFileSelection {
  /// Creates a resolved provider/model pair.
  const ActiveModelFileSelection({required this.provider, required this.model});

  /// Selected provider.
  final ModelProviderConfig provider;

  /// Selected model entry.
  final ModelConfigModel model;
}

/// Resolves the default provider:model pair from a model config document.
ActiveModelFileSelection? activeModelFileSelection(
  ModelConfigDocument document,
) {
  if (document.providers.isEmpty) {
    return null;
  }
  final parsed = _parseDefaultRef(document.defaultRef);
  final provider = parsed.providerId.isEmpty
      ? document.providers.first
      : document.providers.firstWhere(
          (candidate) => candidate.id == parsed.providerId,
          orElse: () => document.providers.first,
        );
  final model = _modelForProvider(provider, parsed.modelId);
  if (model == null) {
    return null;
  }
  return ActiveModelFileSelection(provider: provider, model: model);
}

/// Resolves native file support and the transport to use for chat payloads.
ModelFileCapabilities modelFileCapabilitiesFor({
  required ModelProviderConfig provider,
  required ModelConfigModel model,
}) {
  final explicitTransport = _stringExtra(
    model.extra,
    'file_transport',
    fallback: _stringExtra(provider.extra, 'file_transport'),
  );
  final explicitNative = _boolExtra(
    model.extra,
    'accepts_files',
    fallback: _boolExtra(
      model.extra,
      'supports_files',
      fallback: _boolExtra(
        provider.extra,
        'accepts_files',
        fallback: _boolExtra(provider.extra, 'supports_files'),
      ),
    ),
  );
  final adapter = provider.adapter.trim().toLowerCase();
  final modelName = model.model.trim().isEmpty ? model.id : model.model;
  final inferredNative =
      explicitNative ?? _knownNativeFileSupport(adapter, modelName);
  if (explicitTransport == 'native') {
    return ModelFileCapabilities(
      providerId: provider.id,
      adapter: adapter,
      modelId: model.id,
      modelName: modelName,
      nativeFileParts: inferredNative,
      transport: ModelFileTransport.nativeParts,
      reason: 'Model config explicitly enables native file transport.',
    );
  }
  if (explicitTransport == 'base64' || explicitTransport == 'text') {
    return ModelFileCapabilities(
      providerId: provider.id,
      adapter: adapter,
      modelId: model.id,
      modelName: modelName,
      nativeFileParts: inferredNative,
      transport: ModelFileTransport.base64Text,
      reason: 'Model config explicitly requests text/base64 file transport.',
    );
  }
  if (!inferredNative) {
    return ModelFileCapabilities(
      providerId: provider.id,
      adapter: adapter,
      modelId: model.id,
      modelName: modelName,
      nativeFileParts: false,
      transport: ModelFileTransport.base64Text,
      reason: 'This model is not known to accept native file parts.',
    );
  }
  return ModelFileCapabilities(
    providerId: provider.id,
    adapter: adapter,
    modelId: model.id,
    modelName: modelName,
    nativeFileParts: true,
    transport: ModelFileTransport.base64Text,
    reason:
        'The model appears file-capable, but this chat runtime uses text parts, so files are sent as base64 text.',
  );
}

/// Returns a safe fallback when the model config cannot be read.
ModelFileCapabilities fallbackModelFileCapabilities(String reason) {
  return ModelFileCapabilities(
    providerId: '',
    adapter: '',
    modelId: '',
    modelName: '',
    nativeFileParts: false,
    transport: ModelFileTransport.base64Text,
    reason: reason,
  );
}

/// Parses a provider:model default reference.
({String providerId, String modelId}) _parseDefaultRef(String value) {
  final parts = value.split(':');
  if (parts.length == 1) {
    return (providerId: parts.first.trim(), modelId: '');
  }
  return (
    providerId: parts.first.trim(),
    modelId: parts.sublist(1).join(':').trim(),
  );
}

/// Returns the selected model inside a provider config.
ModelConfigModel? _modelForProvider(
  ModelProviderConfig provider,
  String modelId,
) {
  if (provider.models.isEmpty) {
    return null;
  }
  final selectedId = modelId.trim().isEmpty
      ? provider.defaultModel
      : modelId.trim();
  if (selectedId.isEmpty) {
    return provider.models.first;
  }
  return provider.models.firstWhere(
    (candidate) => candidate.id == selectedId,
    orElse: () => provider.models.first,
  );
}

/// Infers native file support from known adapter/model families.
bool _knownNativeFileSupport(String adapter, String modelName) {
  final name = modelName.toLowerCase();
  if (adapter == 'google') {
    return name.contains('gemini');
  }
  if (adapter == 'anthropic') {
    return name.contains('claude-3') || name.contains('claude-4');
  }
  if (adapter == 'openai') {
    return name.contains('gpt-4o') ||
        name.contains('gpt-4.1') ||
        name.contains('gpt-5') ||
        name.contains('o3') ||
        name.contains('o4');
  }
  return false;
}

/// Reads a boolean from model config extra fields.
bool? _boolExtra(Map<String, dynamic> extra, String key, {bool? fallback}) {
  final value = extra[key] ?? extra[key.replaceAll('_', '-')];
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == 'no') {
      return false;
    }
  }
  return fallback;
}

/// Reads a normalized string from model config extra fields.
String _stringExtra(
  Map<String, dynamic> extra,
  String key, {
  String fallback = '',
}) {
  final value = extra[key] ?? extra[key.replaceAll('_', '-')];
  return value is String ? value.trim().toLowerCase() : fallback;
}
