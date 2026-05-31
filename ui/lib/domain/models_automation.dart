/// Defines runbook authoring and runtime models for the Automations UI.
library;

/// AutomationActionType describes one runbook action the builder can place.
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

  /// Registered runbook action name.
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

/// AutomationDefinition stores one installed runbook definition snapshot.
class AutomationDefinition {
  /// Creates an immutable installed runbook definition.
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

  /// Runbook kind.
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

/// AutomationDraft stores one editable runbook draft.
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

  /// Draft runbook kind.
  final String kind;

  /// User-facing draft name.
  final String name;

  /// Draft description.
  final String description;

  /// Draft lifecycle status.
  final String status;

  /// Editable canonical runbook body.
  final Map<String, dynamic> body;

  /// Last validation result.
  final Map<String, dynamic> validation;

  /// Creation timestamp.
  final String createdAt;

  /// Last update timestamp.
  final String updatedAt;
}

/// AutomationRun stores one runbook run state.
class AutomationRun {
  /// Creates an immutable runbook run state.
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

  /// Runbook kind.
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

/// AutomationRunSetup stores one saved Launch.
class AutomationRunSetup {
  /// Creates an immutable saved Launch.
  const AutomationRunSetup({
    required this.id,
    required this.definitionId,
    required this.name,
    this.description = '',
    this.codebaseId = '',
    this.runtimeTargetId = '',
    this.agentProfileId = '',
    this.input = const <String, dynamic>{},
    this.policy = const <String, dynamic>{},
    this.schedule = const <String, dynamic>{},
    this.createdAt = '',
    this.updatedAt = '',
  });

  /// Launch id.
  final String id;

  /// Runbook definition this Launch starts.
  final String definitionId;

  /// User-facing Launch name.
  final String name;

  /// Optional Launch description.
  final String description;

  /// Bound codebase catalog id.
  final String codebaseId;

  /// Bound Computer or Server target id.
  final String runtimeTargetId;

  /// Bound agent profile id.
  final String agentProfileId;

  /// Saved Launch default input values.
  final Map<String, dynamic> input;

  /// Saved Launch safety policy.
  final Map<String, dynamic> policy;

  /// Saved Launch schedule.
  final Map<String, dynamic> schedule;

  /// Creation timestamp.
  final String createdAt;

  /// Last update timestamp.
  final String updatedAt;

  /// Creates a copy with selected fields replaced.
  AutomationRunSetup copyWith({
    String? id,
    String? definitionId,
    String? name,
    String? description,
    String? codebaseId,
    String? runtimeTargetId,
    String? agentProfileId,
    Map<String, dynamic>? input,
    Map<String, dynamic>? policy,
    Map<String, dynamic>? schedule,
    String? createdAt,
    String? updatedAt,
  }) {
    return AutomationRunSetup(
      id: id ?? this.id,
      definitionId: definitionId ?? this.definitionId,
      name: name ?? this.name,
      description: description ?? this.description,
      codebaseId: codebaseId ?? this.codebaseId,
      runtimeTargetId: runtimeTargetId ?? this.runtimeTargetId,
      agentProfileId: agentProfileId ?? this.agentProfileId,
      input: input ?? this.input,
      policy: policy ?? this.policy,
      schedule: schedule ?? this.schedule,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// AutomationLaunchPreview stores display-safe Launch dry-run output.
class AutomationLaunchPreview {
  /// Creates an immutable Launch preview.
  const AutomationLaunchPreview({
    required this.launch,
    required this.status,
    required this.policyDecision,
    this.resolvedInput = const <String, dynamic>{},
    this.resolution = const <String, dynamic>{},
    this.missingSetup = const <String>[],
  });

  /// Launch being previewed.
  final AutomationRunSetup launch;

  /// Preview status such as ready, needs_input, or blocked.
  final String status;

  /// Display-safe resolved runbook input.
  final Map<String, dynamic> resolvedInput;

  /// Resolver provenance and diagnostics.
  final Map<String, dynamic> resolution;

  /// Required fields still missing.
  final List<String> missingSetup;

  /// Policy decision for this run.
  final AutomationLaunchPolicyDecision policyDecision;
}

/// AutomationLaunchRunSnapshot stores immutable Launch run audit data.
class AutomationLaunchRunSnapshot {
  /// Creates immutable Launch run audit metadata.
  const AutomationLaunchRunSnapshot({
    required this.runId,
    required this.launchId,
    this.launchVersion = 0,
    this.runbookId = '',
    this.runbookVersion = '',
    this.resolvedInput = const <String, dynamic>{},
    this.resolution = const <String, dynamic>{},
    this.target = const <String, dynamic>{},
    this.policy = const <String, dynamic>{},
    this.secretRefs = const <Map<String, dynamic>>[],
    this.createdAt = '',
  });

  /// Runbook run id.
  final String runId;

  /// Saved Launch id.
  final String launchId;

  /// Launch version captured at start.
  final int launchVersion;

  /// Runbook definition id.
  final String runbookId;

  /// Runbook version captured at start.
  final String runbookVersion;

  /// Resolved runbook input.
  final Map<String, dynamic> resolvedInput;

  /// Input provenance and diagnostics.
  final Map<String, dynamic> resolution;

  /// Runtime target binding.
  final Map<String, dynamic> target;

  /// Policy captured at start.
  final Map<String, dynamic> policy;

  /// Secret references captured at start.
  final List<Map<String, dynamic>> secretRefs;

  /// Snapshot creation timestamp.
  final String createdAt;
}

/// AutomationLaunchPolicyDecision stores preview safety status.
class AutomationLaunchPolicyDecision {
  /// Creates an immutable Launch policy decision.
  const AutomationLaunchPolicyDecision({
    required this.status,
    this.reasons = const <String>[],
  });

  /// Decision status.
  final String status;

  /// Display-safe policy reasons.
  final List<String> reasons;
}

/// AutomationCodebase stores one typed repository catalog record.
class AutomationCodebase {
  /// Creates an immutable codebase catalog record.
  const AutomationCodebase({
    required this.id,
    required this.name,
    this.aliases = const <String>[],
    this.repositoryPath = '',
    this.defaultRemote = '',
    this.defaultBranch = '',
    this.provider = '',
    this.providerRepository = '',
    this.runtimeTargetId = '',
    this.agentProfileId = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  /// Stable codebase id.
  final String id;

  /// User-facing codebase name.
  final String name;

  /// Alternate names used for conversational resolution.
  final List<String> aliases;

  /// Local repository path for this codebase.
  final String repositoryPath;

  /// Default Git remote.
  final String defaultRemote;

  /// Default branch or pull request base.
  final String defaultBranch;

  /// Repository provider id.
  final String provider;

  /// Provider repository in owner/name form.
  final String providerRepository;

  /// Preferred runtime target id.
  final String runtimeTargetId;

  /// Preferred agent profile id.
  final String agentProfileId;

  /// Creation timestamp.
  final String createdAt;

  /// Last update timestamp.
  final String updatedAt;

  /// Returns a copy with selected fields replaced.
  AutomationCodebase copyWith({
    String? id,
    String? name,
    List<String>? aliases,
    String? repositoryPath,
    String? defaultRemote,
    String? defaultBranch,
    String? provider,
    String? providerRepository,
    String? runtimeTargetId,
    String? agentProfileId,
    String? createdAt,
    String? updatedAt,
  }) {
    return AutomationCodebase(
      id: id ?? this.id,
      name: name ?? this.name,
      aliases: aliases ?? this.aliases,
      repositoryPath: repositoryPath ?? this.repositoryPath,
      defaultRemote: defaultRemote ?? this.defaultRemote,
      defaultBranch: defaultBranch ?? this.defaultBranch,
      provider: provider ?? this.provider,
      providerRepository: providerRepository ?? this.providerRepository,
      runtimeTargetId: runtimeTargetId ?? this.runtimeTargetId,
      agentProfileId: agentProfileId ?? this.agentProfileId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Converts this record to the memory codebase API payload.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'aliases': aliases,
      'repository_path': repositoryPath,
      'default_remote': defaultRemote,
      'default_branch': defaultBranch,
      'provider': provider,
      'provider_repository': providerRepository,
      'runtime_target_id': runtimeTargetId,
      'agent_profile_id': agentProfileId,
    };
  }
}

/// AutomationCapability stores one normalized harness capability.
class AutomationCapability {
  /// Creates an immutable capability registry record.
  const AutomationCapability({
    required this.id,
    required this.kind,
    required this.name,
    required this.label,
    this.description = '',
    this.usableInChat = false,
    this.usableInRunbooks = false,
    this.invocation = const <String, dynamic>{},
    this.contract = const <String, dynamic>{},
    this.risk = const <String, dynamic>{},
    this.availability = const AutomationCapabilityAvailability(),
    this.testResults = const <AutomationCapabilityTestResult>[],
    this.metadata = const <String, dynamic>{},
  });

  /// Stable capability id.
  final String id;

  /// Capability kind.
  final String kind;

  /// Technical capability name.
  final String name;

  /// User-facing capability label.
  final String label;

  /// Short capability description.
  final String description;

  /// Whether the capability can be used from chat.
  final bool usableInChat;

  /// Whether the capability can be used in runbooks.
  final bool usableInRunbooks;

  /// Invocation metadata for direct and runbook calls.
  final Map<String, dynamic> invocation;

  /// Schema and confirmation metadata.
  final Map<String, dynamic> contract;

  /// User-facing risk metadata.
  final Map<String, dynamic> risk;

  /// Display-safe availability state.
  final AutomationCapabilityAvailability availability;

  /// Latest lab check results.
  final List<AutomationCapabilityTestResult> testResults;

  /// Additional display-safe metadata.
  final Map<String, dynamic> metadata;
}

/// AutomationCapabilityAvailability stores display-safe capability status.
class AutomationCapabilityAvailability {
  /// Creates immutable availability metadata.
  const AutomationCapabilityAvailability({
    this.status = '',
    this.reasons = const <String>[],
  });

  /// Availability status.
  final String status;

  /// Display-safe reason strings.
  final List<String> reasons;
}

/// AutomationCapabilityTestResult stores one lab check result.
class AutomationCapabilityTestResult {
  /// Creates an immutable lab result.
  const AutomationCapabilityTestResult({
    required this.type,
    required this.status,
    this.message = '',
    this.checkedAt = '',
  });

  /// Lab test type.
  final String type;

  /// Lab test status.
  final String status;

  /// Display-safe result message.
  final String message;

  /// Check timestamp.
  final String checkedAt;
}

/// AutomationRuntimeTarget stores one Computer or Server target.
class AutomationRuntimeTarget {
  /// Creates an immutable Runtime Target record.
  const AutomationRuntimeTarget({
    required this.id,
    required this.name,
    required this.kind,
    required this.status,
    this.version = '',
    this.capabilities = const <String>[],
    this.allowedCodebaseIds = const <String>[],
    this.secretRefCount = 0,
    this.lastSeenAt = '',
    this.currentRunCount = 0,
    this.os = '',
    this.hostname = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  /// Stable target id.
  final String id;

  /// User-facing target name.
  final String name;

  /// Target kind.
  final String kind;

  /// Health status.
  final String status;

  /// Runtime version.
  final String version;

  /// Capability ids advertised by this target.
  final List<String> capabilities;

  /// Codebase ids allowed on this target.
  final List<String> allowedCodebaseIds;

  /// Number of target-local secret references.
  final int secretRefCount;

  /// Last heartbeat timestamp.
  final String lastSeenAt;

  /// Active run count.
  final int currentRunCount;

  /// Target OS label.
  final String os;

  /// Target host name.
  final String hostname;

  /// Creation timestamp.
  final String createdAt;

  /// Last update timestamp.
  final String updatedAt;
}

/// AutomationTargetHealth stores target health metadata.
class AutomationTargetHealth {
  /// Creates immutable target health metadata.
  const AutomationTargetHealth({
    required this.targetId,
    required this.status,
    this.message = '',
    this.version = '',
    this.os = '',
    this.hostname = '',
    this.currentRunCount = 0,
    this.checkedAt = '',
  });

  /// Target id.
  final String targetId;

  /// Health status.
  final String status;

  /// Display-safe health message.
  final String message;

  /// Runtime version.
  final String version;

  /// OS label.
  final String os;

  /// Host name.
  final String hostname;

  /// Active run count.
  final int currentRunCount;

  /// Health check timestamp.
  final String checkedAt;
}

/// AutomationTargetLogEntry stores one target log row.
class AutomationTargetLogEntry {
  /// Creates an immutable target log row.
  const AutomationTargetLogEntry({
    required this.id,
    required this.targetId,
    required this.level,
    required this.message,
    this.createdAt = '',
  });

  /// Log row id.
  final int id;

  /// Target id.
  final String targetId;

  /// Log level.
  final String level;

  /// Display-safe message.
  final String message;

  /// Creation timestamp.
  final String createdAt;
}

/// AutomationTargetSecretMetadata stores target secret reference metadata.
class AutomationTargetSecretMetadata {
  /// Creates immutable target secret metadata.
  const AutomationTargetSecretMetadata({
    required this.targetId,
    required this.count,
  });

  /// Target id.
  final String targetId;

  /// Secret reference count.
  final int count;
}

/// AutomationEvent stores one durable run event.
class AutomationEvent {
  /// Creates an immutable runbook event.
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

/// AutomationPendingItem stores one user-visible runbook inbox item.
class AutomationPendingItem {
  /// Creates an immutable pending runbook item.
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

/// Parses one saved Launch from JSON.
AutomationRunSetup parseAutomationRunSetup(dynamic value) {
  final map = _map(value);
  final runbookId = _string(map['runbook_id']);
  final defaults = _map(map['defaults']);
  return AutomationRunSetup(
    id: _string(map['id']),
    definitionId: runbookId.isNotEmpty
        ? runbookId
        : _string(map['definition_id']),
    name: _string(map['name']),
    description: _string(map['description']),
    codebaseId: _string(map['codebase_id']),
    runtimeTargetId: _string(map['runtime_target_id']),
    agentProfileId: _string(map['agent_profile_id']),
    input: defaults.isNotEmpty ? defaults : _map(map['input']),
    policy: _map(map['policy']),
    schedule: _map(map['schedule']),
    createdAt: _string(map['created_at']),
    updatedAt: _string(map['updated_at']),
  );
}

/// Parses one Launch dry-run preview from JSON.
AutomationLaunchPreview parseAutomationLaunchPreview(dynamic value) {
  final map = _map(value);
  return AutomationLaunchPreview(
    launch: parseAutomationRunSetup(map['launch']),
    status: _string(map['status']),
    resolvedInput: _map(map['resolved_input']),
    resolution: _map(map['resolution']),
    missingSetup: _stringList(map['missing_setup']),
    policyDecision: parseAutomationLaunchPolicyDecision(
      map['policy_decision'],
    ),
  );
}

/// Parses one immutable Launch run snapshot from JSON.
AutomationLaunchRunSnapshot parseAutomationLaunchRunSnapshot(
  dynamic value,
) {
  final map = _map(value);
  return AutomationLaunchRunSnapshot(
    runId: _string(map['run_id']),
    launchId: _string(map['launch_id']),
    launchVersion: _int(map['launch_version']),
    runbookId: _string(map['runbook_id']),
    runbookVersion: _string(map['runbook_version']),
    resolvedInput: _map(map['resolved_input']),
    resolution: _map(map['resolution']),
    target: _map(map['target']),
    policy: _map(map['policy']),
    secretRefs: <Map<String, dynamic>>[
      for (final item in _list(map['secret_refs'])) _map(item),
    ],
    createdAt: _string(map['created_at']),
  );
}

/// Parses one Launch policy decision from JSON.
AutomationLaunchPolicyDecision parseAutomationLaunchPolicyDecision(
  dynamic value,
) {
  final map = _map(value);
  return AutomationLaunchPolicyDecision(
    status: _string(map['status']),
    reasons: _stringList(map['reasons']),
  );
}

/// Parses one typed codebase catalog record from JSON.
AutomationCodebase parseAutomationCodebase(dynamic value) {
  final map = _map(value);
  return AutomationCodebase(
    id: _string(map['id']),
    name: _string(map['name']),
    aliases: _stringList(map['aliases']),
    repositoryPath: _string(map['repository_path']),
    defaultRemote: _string(map['default_remote']),
    defaultBranch: _string(map['default_branch']),
    provider: _string(map['provider']),
    providerRepository: _string(map['provider_repository']),
    runtimeTargetId: _string(map['runtime_target_id']),
    agentProfileId: _string(map['agent_profile_id']),
    createdAt: _string(map['created_at']),
    updatedAt: _string(map['updated_at']),
  );
}

/// Parses a codebase list response from memory MCP structured content.
List<AutomationCodebase> parseAutomationCodebases(dynamic value) {
  if (value is List) {
    return value.map(parseAutomationCodebase).toList();
  }
  final map = _map(value);
  return _list(map['codebases']).map(parseAutomationCodebase).toList();
}

/// Parses one capability registry record from JSON.
AutomationCapability parseAutomationCapability(dynamic value) {
  final map = _map(value);
  return AutomationCapability(
    id: _string(map['id']),
    kind: _string(map['kind']),
    name: _string(map['name']),
    label: _string(map['label']),
    description: _string(map['description']),
    usableInChat: map['usable_in_chat'] == true,
    usableInRunbooks: map['usable_in_runbooks'] == true,
    invocation: _map(map['invocation']),
    contract: _map(map['contract']),
    risk: _map(map['risk']),
    availability: parseAutomationCapabilityAvailability(map['availability']),
    testResults: _list(
      map['test_results'],
    ).map(parseAutomationCapabilityTestResult).toList(),
    metadata: _map(map['metadata']),
  );
}

/// Parses capability availability metadata from JSON.
AutomationCapabilityAvailability parseAutomationCapabilityAvailability(
  dynamic value,
) {
  final map = _map(value);
  return AutomationCapabilityAvailability(
    status: _string(map['status']),
    reasons: _stringList(map['reasons']),
  );
}

/// Parses one capability lab test result from JSON.
AutomationCapabilityTestResult parseAutomationCapabilityTestResult(
  dynamic value,
) {
  final map = _map(value);
  return AutomationCapabilityTestResult(
    type: _string(map['type']),
    status: _string(map['status']),
    message: _string(map['message']),
    checkedAt: _string(map['checked_at']),
  );
}

/// Parses one Runtime Target record from JSON.
AutomationRuntimeTarget parseAutomationRuntimeTarget(dynamic value) {
  final map = _map(value);
  return AutomationRuntimeTarget(
    id: _string(map['id']),
    name: _string(map['name']),
    kind: _string(map['kind']),
    status: _string(map['status']),
    version: _string(map['version']),
    capabilities: _stringList(map['capabilities']),
    allowedCodebaseIds: _stringList(map['allowed_codebase_ids']),
    secretRefCount: _int(map['secret_ref_count']),
    lastSeenAt: _string(map['last_seen_at']),
    currentRunCount: _int(map['current_run_count']),
    os: _string(map['os']),
    hostname: _string(map['hostname']),
    createdAt: _string(map['created_at']),
    updatedAt: _string(map['updated_at']),
  );
}

/// Parses a Runtime Target list response from JSON.
List<AutomationRuntimeTarget> parseAutomationRuntimeTargets(dynamic value) {
  if (value is List) {
    return value.map(parseAutomationRuntimeTarget).toList();
  }
  final map = _map(value);
  return _list(map['targets']).map(parseAutomationRuntimeTarget).toList();
}

/// Parses Runtime Target health metadata from JSON.
AutomationTargetHealth parseAutomationTargetHealth(dynamic value) {
  final map = _map(value);
  return AutomationTargetHealth(
    targetId: _string(map['target_id']),
    status: _string(map['status']),
    message: _string(map['message']),
    version: _string(map['version']),
    os: _string(map['os']),
    hostname: _string(map['hostname']),
    currentRunCount: _int(map['current_run_count']),
    checkedAt: _string(map['checked_at']),
  );
}

/// Parses one Runtime Target log row from JSON.
AutomationTargetLogEntry parseAutomationTargetLogEntry(dynamic value) {
  final map = _map(value);
  return AutomationTargetLogEntry(
    id: _int(map['id']),
    targetId: _string(map['target_id']),
    level: _string(map['level']),
    message: _string(map['message']),
    createdAt: _string(map['created_at']),
  );
}

/// Parses Runtime Target log rows from JSON.
List<AutomationTargetLogEntry> parseAutomationTargetLogs(dynamic value) {
  if (value is List) {
    return value.map(parseAutomationTargetLogEntry).toList();
  }
  final map = _map(value);
  return _list(map['logs']).map(parseAutomationTargetLogEntry).toList();
}

/// Parses target secret reference metadata from JSON.
AutomationTargetSecretMetadata parseAutomationTargetSecretMetadata(
  dynamic value,
) {
  final map = _map(value);
  return AutomationTargetSecretMetadata(
    targetId: _string(map['target_id']),
    count: _int(map['count']),
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
