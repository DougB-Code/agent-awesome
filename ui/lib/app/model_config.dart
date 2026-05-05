/// Parses and writes harness model provider configuration files.
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

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
    this.extra = const <String, dynamic>{},
  });

  /// Default provider:model reference.
  final String defaultRef;

  /// Provider definitions keyed by provider id.
  final List<ModelProviderConfig> providers;

  /// Top-level fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses YAML or JSON model config content.
  factory ModelConfigDocument.parse(String content) {
    final decoded = _plainConfig(loadYaml(content));
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
      ..remove('providers');
    return ModelConfigDocument(
      defaultRef: _configString(decoded['default']),
      providers: providers,
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  ModelConfigDocument copyWith({
    String? defaultRef,
    List<ModelProviderConfig>? providers,
    Map<String, dynamic>? extra,
  }) {
    return ModelConfigDocument(
      defaultRef: defaultRef ?? this.defaultRef,
      providers: providers ?? this.providers,
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
    };
  }

  /// Encodes the config document as YAML.
  String toYaml() {
    return _yamlMap(toJson());
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
    required this.models,
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

  /// Models configured for this provider.
  final List<ModelConfigModel> models;

  /// Provider fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses one provider from a decoded YAML map.
  factory ModelProviderConfig.fromMap(String id, Map<String, dynamic> map) {
    final modelsSource = map['models'];
    final models = modelsSource is List
        ? modelsSource
              .whereType<Map<String, dynamic>>()
              .map(ModelConfigModel.fromMap)
              .toList()
        : const <ModelConfigModel>[];
    final extra = Map<String, dynamic>.from(map)
      ..remove('adapter')
      ..remove('name')
      ..remove('api-key')
      ..remove('api_key')
      ..remove('default')
      ..remove('url')
      ..remove('models');
    return ModelProviderConfig(
      id: id,
      name: _configString(map['name'], fallback: id),
      adapter: _configString(map['adapter'], fallback: 'openai'),
      apiKey: _configString(map['api-key'] ?? map['api_key']),
      defaultModel: _configString(map['default']),
      url: _configString(map['url']),
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
      'models': models.map((model) => model.toJson()).toList(),
    };
  }
}

/// ModelConfigModel represents one model alias inside a provider.
class ModelConfigModel {
  /// Creates a provider model config.
  const ModelConfigModel({
    required this.id,
    required this.model,
    this.extra = const <String, dynamic>{},
  });

  /// Local model alias.
  final String id;

  /// Provider-specific model name sent to the API.
  final String model;

  /// Model fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses one model from decoded YAML.
  factory ModelConfigModel.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('id')
      ..remove('model');
    return ModelConfigModel(
      id: _configString(map['id']),
      model: _configString(map['model']),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  ModelConfigModel copyWith({
    String? id,
    String? model,
    Map<String, dynamic>? extra,
  }) {
    return ModelConfigModel(
      id: id ?? this.id,
      model: model ?? this.model,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the model as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'id': id, 'model': model, ...extra};
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

/// Returns a new provider with one starter model.
ModelProviderConfig newModelProviderConfig(String id) {
  return ModelProviderConfig(
    id: id,
    name: _newProviderName(id),
    adapter: 'openai',
    apiKey: '',
    defaultModel: 'model',
    url: '',
    models: const <ModelConfigModel>[
      ModelConfigModel(id: 'model', model: 'provider-model-name'),
    ],
  );
}

/// Encodes one provider as YAML in the shape used under `providers`.
String modelProviderConfigYaml(ModelProviderConfig provider) {
  return _yamlMap(<String, dynamic>{provider.id: provider.toJson()});
}

/// Returns the top-level default reference for a provider.
String modelProviderDefaultRef(ModelProviderConfig provider) {
  return '${provider.id}:${provider.defaultModel}';
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
  final defaultProviderId = document.defaultRef.split(':').first.trim();
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
  final topLevelName = _configString(document.extra['name']);
  return topLevelName;
}

/// Converts YAML package collection values to plain Dart values.
dynamic _plainConfig(dynamic value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _plainConfig(entry.value),
    };
  }
  if (value is YamlList) {
    return value.map(_plainConfig).toList();
  }
  return value;
}

/// Converts a decoded scalar to a config string.
String _configString(dynamic value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

/// Encodes a map as readable YAML.
String _yamlMap(Map<String, dynamic> map) {
  final buffer = StringBuffer();
  _writeYamlMap(buffer, map, 0);
  return buffer.toString();
}

/// Writes a YAML map with stable indentation.
void _writeYamlMap(StringBuffer buffer, Map<String, dynamic> map, int indent) {
  for (final entry in map.entries) {
    _writeYamlMapEntry(buffer, entry.key, entry.value, indent);
  }
}

/// Writes one YAML map entry, optionally prefixed by a list marker.
void _writeYamlMapEntry(
  StringBuffer buffer,
  String key,
  dynamic value,
  int indent, {
  String prefix = '',
}) {
  final padding = ' ' * indent;
  final entryPrefix = '$padding$prefix$key:';
  final childIndent = indent + prefix.length + 2;
  if (value is Map<String, dynamic>) {
    buffer.writeln(entryPrefix);
    _writeYamlMap(buffer, value, childIndent);
  } else if (value is List) {
    buffer.writeln(entryPrefix);
    _writeYamlList(buffer, value, childIndent);
  } else {
    buffer.writeln('$entryPrefix ${_yamlScalar(value)}');
  }
}

/// Writes a YAML list with stable indentation.
void _writeYamlList(StringBuffer buffer, List<dynamic> list, int indent) {
  for (final value in list) {
    final prefix = ' ' * indent;
    if (value is Map<String, dynamic>) {
      if (value.isEmpty) {
        buffer.writeln('$prefix- {}');
        continue;
      }
      final entries = value.entries.toList(growable: false);
      final first = entries.first;
      _writeYamlMapEntry(buffer, first.key, first.value, indent, prefix: '- ');
      for (final entry in entries.skip(1)) {
        _writeYamlMapEntry(buffer, entry.key, entry.value, indent + 2);
      }
    } else {
      buffer.writeln('$prefix- ${_yamlScalar(value)}');
    }
  }
}

/// Encodes one YAML scalar conservatively.
String _yamlScalar(dynamic value) {
  if (value is num || value is bool) {
    return value.toString();
  }
  if (value == null) {
    return 'null';
  }
  final text = value.toString();
  if (text.isEmpty ||
      text.contains(': ') ||
      text.startsWith('{') ||
      text.startsWith('[') ||
      text.contains('\n')) {
    return jsonEncode(text);
  }
  return text;
}
