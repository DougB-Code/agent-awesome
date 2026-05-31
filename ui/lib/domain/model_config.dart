/// Parses and writes harness model provider configuration files.
library;

import 'package:yaml/yaml.dart';

import 'agent_config.dart';
import 'json_value.dart';
import 'config_yaml.dart';

/// Model adapters supported by the local harness runtime.
const List<String> supportedModelAdapters = <String>[
  'openai',
  'anthropic',
  'google',
];

/// ModelConfigDocument represents one model config YAML file.
class ModelConfigDocument {
  /// Creates a model config document.
  const ModelConfigDocument({
    required this.defaultRef,
    required this.providers,
    this.validations = const <AgentValidationConfig>[],
    this.extra = const <String, dynamic>{},
  });

  /// Default provider:model reference.
  final String defaultRef;

  /// Provider definitions keyed by provider id.
  final List<ModelProviderConfig> providers;

  /// Model compatibility validations run through the active agent boundary.
  final List<AgentValidationConfig> validations;

  /// Top-level fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses YAML or JSON model config content.
  factory ModelConfigDocument.parse(String content) {
    final decoded = plainYamlValue(loadYaml(content));
    if (decoded is! Map<String, dynamic>) {
      return const ModelConfigDocument(defaultRef: '', providers: []);
    }
    final providersSource = decoded['providers'];
    final providers = <ModelProviderConfig>[];
    if (providersSource is Map<String, dynamic>) {
      for (final entry in providersSource.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          providers.add(ModelProviderConfig.fromMap(entry.key, value));
        }
      }
    }
    final extra = Map<String, dynamic>.from(decoded)
      ..remove('default')
      ..remove('providers')
      ..remove('validations');
    return ModelConfigDocument(
      defaultRef: stringValue(decoded['default'], trim: true),
      providers: providers,
      validations: jsonObjectList(
        decoded['validations'],
      ).map(AgentValidationConfig.fromMap).toList(),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  ModelConfigDocument copyWith({
    String? defaultRef,
    List<ModelProviderConfig>? providers,
    List<AgentValidationConfig>? validations,
    Map<String, dynamic>? extra,
  }) {
    return ModelConfigDocument(
      defaultRef: defaultRef ?? this.defaultRef,
      providers: providers ?? this.providers,
      validations: validations ?? this.validations,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the config document as deterministic JSON.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'default': defaultRef,
      'providers': <String, dynamic>{
        for (final provider in providers) provider.id: provider.toJson(),
      },
      if (validations.isNotEmpty)
        'validations': validations
            .map((validation) => validation.toJson())
            .toList(),
    };
  }

  /// Encodes the config document as YAML.
  String toYaml() {
    return encodeYamlMap(toJson());
  }
}

/// ModelProviderConfig represents one configured model provider.
class ModelProviderConfig {
  /// Creates a model provider config.
  const ModelProviderConfig({
    required this.id,
    required this.name,
    required this.adapter,
    required this.apiKey,
    required this.defaultModel,
    required this.url,
    required this.endpoints,
    required this.models,
    this.executable = '',
    this.extra = const <String, dynamic>{},
  });

  /// Provider id referenced by `default`.
  final String id;

  /// Human-readable provider name.
  final String name;

  /// Display name shown in settings surfaces.
  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? id : trimmed;
  }

  /// Harness adapter name.
  final String adapter;

  /// API key or environment variable reference.
  final String apiKey;

  /// Default model id inside this provider.
  final String defaultModel;

  /// Provider endpoint URL.
  final String url;

  /// Named provider endpoints for surfaces such as chat and images.
  final Map<String, String> endpoints;

  /// Provider-local executable path or command.
  final String executable;

  /// Models configured for this provider.
  final List<ModelConfigModel> models;

  /// Provider fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses one provider from a decoded YAML map.
  factory ModelProviderConfig.fromMap(String id, Map<String, dynamic> map) {
    final modelsSource = map['models'];
    final models = jsonObjectList(
      modelsSource,
    ).map(ModelConfigModel.fromMap).toList();
    final extra = Map<String, dynamic>.from(map)
      ..remove('adapter')
      ..remove('name')
      ..remove('api-key')
      ..remove('api_key')
      ..remove('default')
      ..remove('url')
      ..remove('endpoints')
      ..remove('executable')
      ..remove('models');
    return ModelProviderConfig(
      id: id,
      name: stringValue(map['name'], fallback: id, trim: true),
      adapter: stringValue(map['adapter'], fallback: 'openai', trim: true),
      apiKey: stringValue(map['api-key'] ?? map['api_key'], trim: true),
      defaultModel: stringValue(map['default'], trim: true),
      url: stringValue(map['url'], trim: true),
      endpoints: _stringMapValue(map['endpoints']),
      executable: stringValue(map['executable'], trim: true),
      models: models,
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  ModelProviderConfig copyWith({
    String? id,
    String? name,
    String? adapter,
    String? apiKey,
    String? defaultModel,
    String? url,
    Map<String, String>? endpoints,
    String? executable,
    List<ModelConfigModel>? models,
    Map<String, dynamic>? extra,
  }) {
    return ModelProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      adapter: adapter ?? this.adapter,
      apiKey: apiKey ?? this.apiKey,
      defaultModel: defaultModel ?? this.defaultModel,
      url: url ?? this.url,
      endpoints: endpoints ?? this.endpoints,
      executable: executable ?? this.executable,
      models: models ?? this.models,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the provider as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      if (name.isNotEmpty) 'name': name,
      'adapter': adapter,
      if (apiKey.isNotEmpty) 'api-key': apiKey,
      'default': defaultModel,
      if (url.isNotEmpty) 'url': url,
      if (endpoints.isNotEmpty) 'endpoints': endpoints,
      if (executable.isNotEmpty) 'executable': executable,
      'models': models.map((model) => model.toJson()).toList(),
    };
  }

  /// Returns the endpoint for a named provider surface.
  String endpoint(String key) {
    final normalized = key.trim();
    if (normalized.isEmpty) {
      return '';
    }
    return endpoints[normalized]?.trim() ?? '';
  }
}

/// ModelConfigModel represents one model alias inside a provider.
class ModelConfigModel {
  /// Creates a provider model config.
  const ModelConfigModel({
    required this.id,
    required this.model,
    this.path = '',
    this.extra = const <String, dynamic>{},
  });

  /// Local model alias.
  final String id;

  /// Provider-specific model name sent to the API.
  final String model;

  /// Local artifact path for file-backed model adapters.
  final String path;

  /// Model fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses one model from decoded YAML.
  factory ModelConfigModel.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('id')
      ..remove('model')
      ..remove('path');
    return ModelConfigModel(
      id: stringValue(map['id'], trim: true),
      model: stringValue(map['model'], trim: true),
      path: stringValue(map['path'], trim: true),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  ModelConfigModel copyWith({
    String? id,
    String? model,
    String? path,
    Map<String, dynamic>? extra,
  }) {
    return ModelConfigModel(
      id: id ?? this.id,
      model: model ?? this.model,
      path: path ?? this.path,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the model as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'model': model,
      if (path.isNotEmpty) 'path': path,
      ...extra,
    };
  }
}

/// ModelConfigChoice describes one selectable provider:model pair.
class ModelConfigChoice {
  /// Creates a selectable model choice for app-owned model settings.
  const ModelConfigChoice({
    required this.providerId,
    required this.providerName,
    required this.modelId,
    required this.modelName,
    required this.isDefault,
  });

  /// Provider id used in provider:model references.
  final String providerId;

  /// Human-readable provider display name.
  final String providerName;

  /// Model id used in provider:model references.
  final String modelId;

  /// Provider-specific wire model name.
  final String modelName;

  /// Whether this choice matches the config-level default.
  final bool isDefault;

  /// Provider:model reference for this choice.
  String get ref {
    return '$providerId:$modelId';
  }

  /// Human-readable provider/model label.
  String get label {
    final providerLabel = providerName.trim().isEmpty
        ? providerId
        : providerName.trim();
    return '$providerLabel / $modelId';
  }
}

/// ModelProviderRef stores a provider:model reference from config.
class ModelProviderRef {
  /// Creates a parsed provider/model reference.
  const ModelProviderRef({required this.providerId, required this.modelId});

  /// Provider id before the first colon.
  final String providerId;

  /// Model id after the first colon, when supplied.
  final String modelId;

  /// Encodes this reference in provider:model form.
  String get ref {
    if (modelId.isEmpty) {
      return providerId;
    }
    return '$providerId:$modelId';
  }
}

/// Returns a new provider with one starter model.
ModelProviderConfig newModelProviderConfig(String id) {
  final modelId = modelIdFromProviderModel(providerId: id, modelName: 'model');
  return ModelProviderConfig(
    id: id,
    name: _newProviderName(id),
    adapter: 'openai',
    apiKey: '',
    defaultModel: modelId,
    url: '',
    endpoints: const <String, String>{},
    executable: '',
    models: <ModelConfigModel>[ModelConfigModel(id: modelId, model: '')],
  );
}

/// Returns a stable hidden model id from provider id and wire model name.
String modelIdFromProviderModel({
  required String providerId,
  required String modelName,
}) {
  final combined = '${providerId.trim()} ${modelName.trim()}';
  final normalized = combined.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]+'),
    '-',
  );
  final trimmed = normalized
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  if (trimmed.isEmpty) {
    return 'model';
  }
  if (RegExp(r'^[a-z]').hasMatch(trimmed)) {
    return trimmed;
  }
  return 'model-$trimmed';
}

/// Returns a model config document containing exactly one provider.
ModelConfigDocument modelConfigDocumentForProvider(
  ModelProviderConfig provider, {
  List<AgentValidationConfig> validations = const <AgentValidationConfig>[],
  Map<String, dynamic> extra = const <String, dynamic>{},
}) {
  return ModelConfigDocument(
    defaultRef: modelProviderDefaultRef(provider),
    providers: <ModelProviderConfig>[provider],
    validations: validations,
    extra: extra,
  );
}

/// Returns a single-provider document scoped to the configured default.
ModelConfigDocument modelConfigDocumentForDefaultProvider(
  ModelConfigDocument document,
) {
  if (document.providers.length <= 1) {
    return document;
  }
  final parsed = parseModelProviderRef(document.defaultRef);
  final provider = parsed.providerId.isEmpty
      ? document.providers.first
      : document.providers.firstWhere(
          (candidate) => candidate.id == parsed.providerId,
          orElse: () => document.providers.first,
        );
  final defaultRef =
      provider.models.any(
        (model) => '${provider.id}:${model.id}' == document.defaultRef.trim(),
      )
      ? document.defaultRef.trim()
      : modelProviderDefaultRef(provider);
  return document.copyWith(
    defaultRef: defaultRef,
    providers: <ModelProviderConfig>[provider],
  );
}

/// Returns an empty model config for first-run provider setup.
ModelConfigDocument emptyModelConfigDocument() {
  return const ModelConfigDocument(defaultRef: '', providers: []);
}

/// Encodes one provider as YAML in the shape used under `providers`.
String modelProviderConfigYaml(ModelProviderConfig provider) {
  return encodeYamlMap(<String, dynamic>{provider.id: provider.toJson()});
}

/// Returns the top-level default reference for a provider.
String modelProviderDefaultRef(ModelProviderConfig provider) {
  return '${provider.id}:${provider.defaultModel}';
}

/// Parses a provider:model reference while preserving colons in model ids.
ModelProviderRef parseModelProviderRef(String value) {
  final parts = value.split(':');
  if (parts.length == 1) {
    return ModelProviderRef(providerId: parts.first.trim(), modelId: '');
  }
  return ModelProviderRef(
    providerId: parts.first.trim(),
    modelId: parts.sublist(1).join(':').trim(),
  );
}

/// Returns the selected model inside a provider config.
ModelConfigModel? modelConfigModelForProvider(
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

/// Returns every provider:model choice available in a model config file.
List<ModelConfigChoice> modelConfigChoices(String content) {
  final document = ModelConfigDocument.parse(content);
  return <ModelConfigChoice>[
    for (final provider in document.providers)
      for (final model in provider.models)
        ModelConfigChoice(
          providerId: provider.id,
          providerName: provider.displayName,
          modelId: model.id,
          modelName: model.model,
          isDefault: document.defaultRef == '${provider.id}:${model.id}',
        ),
  ];
}

/// Returns the editable display name for a newly generated provider.
String _newProviderName(String id) {
  final suffix = RegExp(r'^provider-(\d+)$').firstMatch(id)?.group(1);
  if (suffix != null) {
    return 'Provider $suffix';
  }
  return 'Provider';
}

/// Returns a validation error for invalid model config state.
String modelConfigValidationError(ModelConfigDocument document) {
  if (document.providers.length > 1) {
    return 'Model config files can contain only one provider';
  }
  final providerIds = <String>{};
  final defaultRefs = <String>{};
  for (final provider in document.providers) {
    if (provider.id.trim().isEmpty) {
      return 'Provider id is required';
    }
    if (provider.name.trim().isEmpty) {
      return 'Provider name is required for ${provider.id}';
    }
    if (!providerIds.add(provider.id)) {
      return 'Provider name "${provider.displayName}" is duplicated';
    }
    if (provider.adapter.trim().isEmpty) {
      return 'Adapter is required for ${provider.id}';
    }
    if (!supportedModelAdapters.contains(provider.adapter.trim())) {
      return 'Adapter "${provider.adapter}" is not supported for ${provider.id}';
    }
    if (provider.defaultModel.trim().isEmpty) {
      return 'Default model id is required for ${provider.id}';
    }
    if (provider.models.isEmpty) {
      return 'At least one model is required for ${provider.id}';
    }
    final modelIds = <String>{};
    for (final model in provider.models) {
      if (model.id.trim().isEmpty) {
        return 'Model id is required for ${provider.id}';
      }
      if (!modelIds.add(model.id)) {
        return 'Model id "${model.id}" is duplicated in ${provider.id}';
      }
      if (model.model.trim().isEmpty) {
        return 'Provider model is required for ${provider.id}:${model.id}';
      }
      defaultRefs.add('${provider.id}:${model.id}');
    }
    if (!modelIds.contains(provider.defaultModel)) {
      return 'Default model "${provider.defaultModel}" is not in ${provider.id}';
    }
  }
  if (document.defaultRef.trim().isNotEmpty &&
      !defaultRefs.contains(document.defaultRef)) {
    return 'Default model "${document.defaultRef}" is not configured';
  }
  return '';
}

/// Returns the human-readable display name for a model config file.
String modelConfigDisplayName(String content) {
  final document = ModelConfigDocument.parse(content);
  final defaultProviderId = parseModelProviderRef(
    document.defaultRef,
  ).providerId;
  if (defaultProviderId.isNotEmpty) {
    for (final provider in document.providers) {
      if (provider.id == defaultProviderId && provider.name.trim().isNotEmpty) {
        return provider.name.trim();
      }
    }
  }
  for (final provider in document.providers) {
    if (provider.name.trim().isNotEmpty) {
      return provider.name.trim();
    }
  }
  final topLevelName = stringValue(document.extra['name'], trim: true);
  return topLevelName;
}

/// Converts a decoded map to a trimmed string map.
Map<String, String> _stringMapValue(dynamic value) {
  if (value is! Map) {
    return const <String, String>{};
  }
  return <String, String>{
    for (final entry in value.entries)
      entry.key.toString().trim(): entry.value.toString().trim(),
  }..removeWhere((key, value) => key.isEmpty || value.isEmpty);
}
