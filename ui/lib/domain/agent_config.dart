/// Parses and writes harness agent configuration files.
library;

import 'package:yaml/yaml.dart';

import 'config_yaml.dart';
import 'json_value.dart';

/// AgentConfigDocument represents one agent behavior YAML file.
class AgentConfigDocument {
  /// Creates an immutable agent config document.
  const AgentConfigDocument({
    required this.name,
    required this.description,
    required this.instruction,
    required this.validations,
    this.extra = const <String, dynamic>{},
  });

  /// Agent display name.
  final String name;

  /// Agent package description.
  final String description;

  /// Agent instruction text.
  final String instruction;

  /// Portable behavior validations bundled with the agent.
  final List<AgentValidationConfig> validations;

  /// Top-level fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses YAML or JSON agent config content.
  factory AgentConfigDocument.parse(String content) {
    final decoded = plainYamlValue(loadYaml(content));
    if (decoded is! Map<String, dynamic>) {
      return emptyAgentConfigDocument();
    }
    final extra = Map<String, dynamic>.from(decoded)
      ..remove('name')
      ..remove('description')
      ..remove('instruction')
      ..remove('validations');
    return AgentConfigDocument(
      name: stringValue(decoded['name'], trim: true),
      description: stringValue(decoded['description'], trim: true),
      instruction: stringValue(decoded['instruction']),
      validations: jsonObjectList(
        decoded['validations'],
      ).map(AgentValidationConfig.fromMap).toList(),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  AgentConfigDocument copyWith({
    String? name,
    String? description,
    String? instruction,
    List<AgentValidationConfig>? validations,
    Map<String, dynamic>? extra,
  }) {
    return AgentConfigDocument(
      name: name ?? this.name,
      description: description ?? this.description,
      instruction: instruction ?? this.instruction,
      validations: validations ?? this.validations,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the config document as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'name': name,
      if (description.trim().isNotEmpty) 'description': description,
      'instruction': instruction,
      if (validations.isNotEmpty)
        'validations': validations
            .map((validation) => validation.toJson())
            .toList(),
    };
  }

  /// Encodes the config document as readable YAML.
  String toYaml() {
    return encodeYamlMap(toJson());
  }
}

/// AgentValidationConfig stores one configured agent behavior validation.
class AgentValidationConfig {
  /// Creates an immutable validation config.
  const AgentValidationConfig({
    required this.id,
    required this.label,
    required this.description,
    required this.mode,
    required this.prompt,
    required this.input,
    required this.fixtures,
    required this.mocks,
    required this.expected,
    required this.assertions,
    this.extra = const <String, dynamic>{},
  });

  /// Validation id.
  final String id;

  /// Human-readable validation label.
  final String label;

  /// Human-readable validation description.
  final String description;

  /// Validation execution mode.
  final String mode;

  /// Prompt submitted to the agent boundary.
  final String prompt;

  /// Input payload supplied to the validation.
  final Map<String, dynamic> input;

  /// Fixture payload supplied to the validation.
  final Map<String, dynamic> fixtures;

  /// Mock payload supplied to mocked validations.
  final Map<String, dynamic> mocks;

  /// Expected values supplied to assertions.
  final Map<String, dynamic> expected;

  /// Assertion definitions for this validation.
  final List<AgentValidationAssertionConfig> assertions;

  /// Fields preserved outside the known validation schema.
  final Map<String, dynamic> extra;

  /// Parses one validation config from decoded YAML.
  factory AgentValidationConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('id')
      ..remove('label')
      ..remove('description')
      ..remove('mode')
      ..remove('prompt')
      ..remove('input')
      ..remove('fixtures')
      ..remove('mocks')
      ..remove('expected')
      ..remove('assertions');
    return AgentValidationConfig(
      id: stringValue(map['id'], trim: true),
      label: stringValue(map['label'], trim: true),
      description: stringValue(map['description'], trim: true),
      mode: stringValue(map['mode'], trim: true),
      prompt: stringValue(map['prompt'], trim: true),
      input: jsonObject(map['input']),
      fixtures: jsonObject(map['fixtures']),
      mocks: jsonObject(map['mocks']),
      expected: jsonObject(map['expected']),
      assertions: jsonObjectList(
        map['assertions'],
      ).map(AgentValidationAssertionConfig.fromMap).toList(),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  AgentValidationConfig copyWith({
    String? id,
    String? label,
    String? description,
    String? mode,
    String? prompt,
    Map<String, dynamic>? input,
    Map<String, dynamic>? fixtures,
    Map<String, dynamic>? mocks,
    Map<String, dynamic>? expected,
    List<AgentValidationAssertionConfig>? assertions,
    Map<String, dynamic>? extra,
  }) {
    return AgentValidationConfig(
      id: id ?? this.id,
      label: label ?? this.label,
      description: description ?? this.description,
      mode: mode ?? this.mode,
      prompt: prompt ?? this.prompt,
      input: input ?? this.input,
      fixtures: fixtures ?? this.fixtures,
      mocks: mocks ?? this.mocks,
      expected: expected ?? this.expected,
      assertions: assertions ?? this.assertions,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the validation config as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'id': id,
      if (label.trim().isNotEmpty) 'label': label,
      if (description.trim().isNotEmpty) 'description': description,
      if (mode.trim().isNotEmpty) 'mode': mode,
      'prompt': prompt,
      if (input.isNotEmpty) 'input': input,
      if (fixtures.isNotEmpty) 'fixtures': fixtures,
      if (mocks.isNotEmpty) 'mocks': mocks,
      if (expected.isNotEmpty) 'expected': expected,
      if (assertions.isNotEmpty)
        'assertions': assertions
            .map((assertion) => assertion.toJson())
            .toList(),
    };
  }
}

/// AgentValidationAssertionConfig stores one configured assertion.
class AgentValidationAssertionConfig {
  /// Creates an immutable assertion config.
  const AgentValidationAssertionConfig({
    required this.type,
    required this.path,
    required this.contains,
    required this.equals,
    this.extra = const <String, dynamic>{},
  });

  /// Assertion type.
  final String type;

  /// Optional inspected path.
  final String path;

  /// Expected substring for contains-style assertions.
  final String contains;

  /// Expected exact value for equality-style assertions.
  final dynamic equals;

  /// Fields preserved outside the known assertion schema.
  final Map<String, dynamic> extra;

  /// Parses one assertion config from decoded YAML.
  factory AgentValidationAssertionConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('type')
      ..remove('path')
      ..remove('contains')
      ..remove('equals');
    return AgentValidationAssertionConfig(
      type: stringValue(map['type'], trim: true),
      path: stringValue(map['path'], trim: true),
      contains: stringValue(map['contains'], trim: true),
      equals: map['equals'],
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  AgentValidationAssertionConfig copyWith({
    String? type,
    String? path,
    String? contains,
    dynamic equals = _unchangedAgentAssertionValue,
    Map<String, dynamic>? extra,
  }) {
    return AgentValidationAssertionConfig(
      type: type ?? this.type,
      path: path ?? this.path,
      contains: contains ?? this.contains,
      equals: identical(equals, _unchangedAgentAssertionValue)
          ? this.equals
          : equals,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the assertion config as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'type': type,
      if (path.trim().isNotEmpty) 'path': path,
      if (contains.trim().isNotEmpty) 'contains': contains,
      if (equals != null) 'equals': equals,
    };
  }
}

const Object _unchangedAgentAssertionValue = Object();

/// Returns an empty agent config document.
AgentConfigDocument emptyAgentConfigDocument() {
  return const AgentConfigDocument(
    name: '',
    description: '',
    instruction: '',
    validations: <AgentValidationConfig>[],
  );
}
