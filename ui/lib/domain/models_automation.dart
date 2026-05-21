/// Defines workflow authoring and runtime models for the Automations UI.
library;

/// AutomationActionType describes one workflow action the builder can place.
class AutomationActionType {
  /// Creates an immutable automation action type.
  const AutomationActionType({
    required this.name,
    required this.label,
    required this.description,
    required this.risk,
    required this.available,
    this.inputSchema = const <String, dynamic>{},
    this.outputSchema = const <String, dynamic>{},
    this.inputContracts = const <String>[],
    this.outputContracts = const <String>[],
  });

  /// Registered workflow action name.
  final String name;

  /// User-facing action label.
  final String label;

  /// Short action description.
  final String description;

  /// Risk category shown in safety views.
  final String risk;

  /// Whether this action can be published in v1.
  final bool available;

  /// JSON schema-like input descriptor.
  final Map<String, dynamic> inputSchema;

  /// JSON schema-like output descriptor.
  final Map<String, dynamic> outputSchema;

  /// Generic input contract ids accepted by this action.
  final List<String> inputContracts;

  /// Generic output contract ids emitted by this action.
  final List<String> outputContracts;
}

/// AutomationDefinition stores one installed workflow definition snapshot.
class AutomationDefinition {
  /// Creates an immutable installed workflow definition.
  const AutomationDefinition({
    required this.id,
    required this.kind,
    required this.name,
    required this.hash,
    this.body = const <String, dynamic>{},
    this.updatedAt = '',
  });

  /// Definition id.
  final String id;

  /// Workflow kind.
  final String kind;

  /// User-facing definition name.
  final String name;

  /// Stable body hash.
  final String hash;

  /// Canonical definition body.
  final Map<String, dynamic> body;

  /// Last update timestamp.
  final String updatedAt;
}

/// AutomationDraft stores one editable workflow draft.
class AutomationDraft {
  /// Creates an immutable automation draft.
  const AutomationDraft({
    required this.id,
    required this.kind,
    required this.name,
    required this.status,
    this.description = '',
    this.body = const <String, dynamic>{},
    this.validation = const <String, dynamic>{},
    this.createdAt = '',
    this.updatedAt = '',
  });

  /// Draft id.
  final String id;

  /// Draft workflow kind.
  final String kind;

  /// User-facing draft name.
  final String name;

  /// Draft description.
  final String description;

  /// Draft lifecycle status.
  final String status;

  /// Editable canonical workflow body.
  final Map<String, dynamic> body;

  /// Last validation result.
  final Map<String, dynamic> validation;

  /// Creation timestamp.
  final String createdAt;

  /// Last update timestamp.
  final String updatedAt;
}

/// AutomationRun stores one workflow run state.
class AutomationRun {
  /// Creates an immutable workflow run state.
  const AutomationRun({
    required this.id,
    required this.definitionId,
    required this.kind,
    required this.status,
    required this.state,
    this.input = const <String, dynamic>{},
    this.output = const <String, dynamic>{},
    this.createdAt = '',
    this.updatedAt = '',
  });

  /// Run id.
  final String id;

  /// Installed definition id.
  final String definitionId;

  /// Workflow kind.
  final String kind;

  /// Runtime status.
  final String status;

  /// Current state label.
  final String state;

  /// Run input payload.
  final Map<String, dynamic> input;

  /// Run output payload.
  final Map<String, dynamic> output;

  /// Creation timestamp.
  final String createdAt;

  /// Last update timestamp.
  final String updatedAt;
}

/// AutomationEvent stores one durable run event.
class AutomationEvent {
  /// Creates an immutable workflow event.
  const AutomationEvent({
    required this.id,
    required this.runId,
    required this.type,
    required this.message,
    this.data = const <String, dynamic>{},
    this.createdAt = '',
  });

  /// Event id.
  final int id;

  /// Run id.
  final String runId;

  /// Event type.
  final String type;

  /// Display message.
  final String message;

  /// Event payload.
  final Map<String, dynamic> data;

  /// Creation timestamp.
  final String createdAt;
}

/// AutomationPendingItem stores one user-visible workflow inbox item.
class AutomationPendingItem {
  /// Creates an immutable pending workflow item.
  const AutomationPendingItem({
    required this.id,
    required this.runId,
    required this.stepId,
    required this.status,
    required this.prompt,
    this.payload = const <String, dynamic>{},
    this.response = const <String, dynamic>{},
    this.createdAt = '',
    this.updatedAt = '',
  });

  /// Pending item id.
  final String id;

  /// Run id.
  final String runId;

  /// Step id that requested the item.
  final String stepId;

  /// Pending status.
  final String status;

  /// User-facing prompt.
  final String prompt;

  /// Display-safe payload.
  final Map<String, dynamic> payload;

  /// User response payload.
  final Map<String, dynamic> response;

  /// Creation timestamp.
  final String createdAt;

  /// Last update timestamp.
  final String updatedAt;
}

/// AutomationTemplate stores one workflow template.
class AutomationTemplate {
  /// Creates an immutable workflow template.
  const AutomationTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.tags = const <String>[],
    this.parameters = const <Map<String, dynamic>>[],
    this.requirements = const <String, dynamic>{},
    this.body = const <String, dynamic>{},
  });

  /// Template id.
  final String id;

  /// User-facing template name.
  final String name;

  /// Template description.
  final String description;

  /// Template category.
  final String category;

  /// Search tags.
  final List<String> tags;

  /// Parameter descriptors.
  final List<Map<String, dynamic>> parameters;

  /// Required tools, credentials, or permissions.
  final Map<String, dynamic> requirements;

  /// Draft body used when instantiated.
  final Map<String, dynamic> body;
}

/// AutomationPackage stores one importable automation package.
class AutomationPackage {
  /// Creates an immutable automation package.
  const AutomationPackage({
    required this.id,
    required this.name,
    required this.version,
    this.description = '',
    this.body = const <String, dynamic>{},
  });

  /// Package id.
  final String id;

  /// User-facing package name.
  final String name;

  /// Package version.
  final String version;

  /// Package description.
  final String description;

  /// Package body.
  final Map<String, dynamic> body;
}

/// AutomationValidationResult stores draft validation diagnostics.
class AutomationValidationResult {
  /// Creates an immutable validation result.
  const AutomationValidationResult({
    required this.valid,
    required this.publishable,
    this.diagnostics = const <AutomationValidationDiagnostic>[],
    this.definition = const <String, dynamic>{},
  });

  /// Whether the draft compiles to a definition.
  final bool valid;

  /// Whether the compiled definition may be published.
  final bool publishable;

  /// Validation diagnostics.
  final List<AutomationValidationDiagnostic> diagnostics;

  /// Compiled definition shape, if valid.
  final Map<String, dynamic> definition;
}

/// AutomationValidationDiagnostic describes one validation message.
class AutomationValidationDiagnostic {
  /// Creates an immutable validation diagnostic.
  const AutomationValidationDiagnostic({
    required this.severity,
    required this.path,
    required this.message,
  });

  /// Diagnostic severity.
  final String severity;

  /// JSON path or logical location.
  final String path;

  /// Human-readable message.
  final String message;
}

/// Parses one automation action type from JSON.
AutomationActionType parseAutomationActionType(dynamic value) {
  final map = _map(value);
  return AutomationActionType(
    name: _string(map['name']),
    label: _string(map['label']),
    description: _string(map['description']),
    risk: _string(map['risk']),
    available: map['available'] == true,
    inputSchema: _map(map['input_schema']),
    outputSchema: _map(map['output_schema']),
    inputContracts: _stringList(map['input_contracts']),
    outputContracts: _stringList(map['output_contracts']),
  );
}

/// Parses one installed automation definition from JSON.
AutomationDefinition parseAutomationDefinition(dynamic value) {
  final map = _map(value);
  return AutomationDefinition(
    id: _string(map['id']),
    kind: _string(map['kind']),
    name: _string(map['name']),
    hash: _string(map['hash']),
    body: _map(map['body']),
    updatedAt: _string(map['updated_at']),
  );
}

/// Parses one automation draft from JSON.
AutomationDraft parseAutomationDraft(dynamic value) {
  final map = _map(value);
  return AutomationDraft(
    id: _string(map['id']),
    kind: _string(map['kind']),
    name: _string(map['name']),
    description: _string(map['description']),
    status: _string(map['status']),
    body: _map(map['body']),
    validation: _map(map['validation']),
    createdAt: _string(map['created_at']),
    updatedAt: _string(map['updated_at']),
  );
}

/// Parses one automation run from JSON.
AutomationRun parseAutomationRun(dynamic value) {
  final map = _map(value);
  return AutomationRun(
    id: _string(map['id']),
    definitionId: _string(map['definition_id']),
    kind: _string(map['kind']),
    status: _string(map['status']),
    state: _string(map['state']),
    input: _map(map['input']),
    output: _map(map['output']),
    createdAt: _string(map['created_at']),
    updatedAt: _string(map['updated_at']),
  );
}

/// Parses one automation event from JSON.
AutomationEvent parseAutomationEvent(dynamic value) {
  final map = _map(value);
  return AutomationEvent(
    id: _int(map['id']),
    runId: _string(map['run_id']),
    type: _string(map['type']),
    message: _string(map['message']),
    data: _map(map['data']),
    createdAt: _string(map['created_at']),
  );
}

/// Parses one pending automation item from JSON.
AutomationPendingItem parseAutomationPendingItem(dynamic value) {
  final map = _map(value);
  return AutomationPendingItem(
    id: _string(map['id']),
    runId: _string(map['run_id']),
    stepId: _string(map['step_id']),
    status: _string(map['status']),
    prompt: _string(map['prompt']),
    payload: _map(map['payload']),
    response: _map(map['response']),
    createdAt: _string(map['created_at']),
    updatedAt: _string(map['updated_at']),
  );
}

/// Parses one automation template from JSON.
AutomationTemplate parseAutomationTemplate(dynamic value) {
  final map = _map(value);
  return AutomationTemplate(
    id: _string(map['id']),
    name: _string(map['name']),
    description: _string(map['description']),
    category: _string(map['category']),
    tags: _stringList(map['tags']),
    parameters: _mapList(map['parameters']),
    requirements: _map(map['requirements']),
    body: _map(map['body']),
  );
}

/// Parses one automation package from JSON.
AutomationPackage parseAutomationPackage(dynamic value) {
  final map = _map(value);
  return AutomationPackage(
    id: _string(map['id']),
    name: _string(map['name']),
    version: _string(map['version']),
    description: _string(map['description']),
    body: _map(map['body']),
  );
}

/// Parses one automation validation result from JSON.
AutomationValidationResult parseAutomationValidationResult(dynamic value) {
  final map = _map(value);
  return AutomationValidationResult(
    valid: map['valid'] == true,
    publishable: map['publishable'] == true,
    diagnostics: _list(
      map['diagnostics'],
    ).map(parseAutomationValidationDiagnostic).toList(),
    definition: _map(map['definition']),
  );
}

/// Parses one automation validation diagnostic from JSON.
AutomationValidationDiagnostic parseAutomationValidationDiagnostic(
  dynamic value,
) {
  final map = _map(value);
  return AutomationValidationDiagnostic(
    severity: _string(map['severity']),
    path: _string(map['path']),
    message: _string(map['message']),
  );
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return const <String, dynamic>{};
}

List<dynamic> _list(dynamic value) {
  if (value is List) {
    return value;
  }
  return const <dynamic>[];
}

List<String> _stringList(dynamic value) {
  return _list(value).map((item) => '$item').toList();
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  return _list(value).map(_map).toList();
}

String _string(dynamic value) {
  return value == null ? '' : '$value';
}

int _int(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(_string(value)) ?? 0;
}
