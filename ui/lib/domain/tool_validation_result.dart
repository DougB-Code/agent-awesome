/// Parses portable tool validation runner results.
library;

import 'json_value.dart';

/// ToolValidationLibraryResult stores validation output for many tool packages.
class ToolValidationLibraryResult {
  /// Creates an immutable tool package library result.
  const ToolValidationLibraryResult({
    required this.totalPackages,
    required this.passedPackages,
    required this.failedPackages,
    required this.unsupportedPackages,
    required this.total,
    required this.passed,
    required this.failed,
    required this.unsupported,
    required this.coverageRequired,
    required this.coverageCovered,
    required this.coverageMissing,
    required this.inputSchemaRequired,
    required this.inputSchemaCovered,
    required this.inputSchemaMissing,
    required this.missingAssertions,
    required this.packages,
  });

  /// Number of tool packages checked.
  final int totalPackages;

  /// Number of passing tool packages.
  final int passedPackages;

  /// Number of failed tool packages.
  final int failedPackages;

  /// Number of unsupported tool packages.
  final int unsupportedPackages;

  /// Number of validation cases checked.
  final int total;

  /// Number of passing validation cases.
  final int passed;

  /// Number of failed validation cases.
  final int failed;

  /// Number of unsupported validation cases.
  final int unsupported;

  /// Number of configured validation targets.
  final int coverageRequired;

  /// Number of configured validation targets covered by validations.
  final int coverageCovered;

  /// Number of configured validation targets missing validations.
  final int coverageMissing;

  /// Number of command operations that should declare input schemas.
  final int inputSchemaRequired;

  /// Number of command operations with declared input schemas.
  final int inputSchemaCovered;

  /// Number of command operations missing input schemas.
  final int inputSchemaMissing;

  /// Number of validations with no real assertions.
  final int missingAssertions;

  /// Per-tool package validation results.
  final List<ToolValidationPackageResult> packages;

  /// Parses a tool package library result from decoded JSON.
  factory ToolValidationLibraryResult.fromJson(Map<String, dynamic> json) {
    return ToolValidationLibraryResult(
      totalPackages: intValue(json['total_packages']),
      passedPackages: intValue(json['passed_packages']),
      failedPackages: intValue(json['failed_packages']),
      unsupportedPackages: intValue(json['unsupported_packages']),
      total: intValue(json['total']),
      passed: intValue(json['passed']),
      failed: intValue(json['failed']),
      unsupported: intValue(json['unsupported']),
      coverageRequired: intValue(json['coverage_required']),
      coverageCovered: intValue(json['coverage_covered']),
      coverageMissing: intValue(json['coverage_missing']),
      inputSchemaRequired: intValue(json['input_schema_required']),
      inputSchemaCovered: intValue(json['input_schema_covered']),
      inputSchemaMissing: intValue(json['input_schema_missing']),
      missingAssertions: intValue(json['missing_assertions']),
      packages: jsonObjectList(
        json['packages'],
      ).map(ToolValidationPackageResult.fromJson).toList(),
    );
  }

  /// Returns whether every tool package and validation passed.
  bool get passedAll {
    return totalPackages > 0 &&
        failedPackages == 0 &&
        unsupportedPackages == 0 &&
        failed == 0 &&
        unsupported == 0;
  }

  /// Agent-callable tool contracts exposed across every checked package.
  Map<String, ToolValidationAgentToolContractResult> get agentToolContracts {
    final contracts = <String, ToolValidationAgentToolContractResult>{};
    for (final package in packages) {
      contracts.addAll(package.result.agentToolContracts);
    }
    return contracts;
  }

  /// Number of distinct agent-callable tool contracts in the checked packages.
  int get agentToolContractCount => agentToolContracts.length;
}

/// ToolValidationPackageResult stores one package entry in a library run.
class ToolValidationPackageResult {
  /// Creates an immutable tool package result.
  const ToolValidationPackageResult({
    required this.path,
    required this.result,
    required this.error,
  });

  /// Tool package config path.
  final String path;

  /// Per-package suite result.
  final ToolValidationSuiteResult result;

  /// Package load or validation error.
  final String error;

  /// Parses one package result from decoded JSON.
  factory ToolValidationPackageResult.fromJson(Map<String, dynamic> json) {
    return ToolValidationPackageResult(
      path: stringValue(json['path'], trim: true),
      result: ToolValidationSuiteResult.fromJson(jsonObject(json['result'])),
      error: stringValue(json['error'], trim: true),
    );
  }
}

/// ToolValidationSuiteResult stores one package validation run.
class ToolValidationSuiteResult {
  /// Creates an immutable package validation result.
  const ToolValidationSuiteResult({
    required this.total,
    required this.passed,
    required this.failed,
    required this.unsupported,
    required this.coverage,
    required this.inputSchemaCoverage,
    required this.agentToolCalls,
    required this.agentToolContracts,
    required this.missingAssertions,
    required this.results,
  });

  /// Number of validations in the package.
  final int total;

  /// Number of passing validations.
  final int passed;

  /// Number of failed validations.
  final int failed;

  /// Number of unsupported validations.
  final int unsupported;

  /// Per-validation results.
  final List<ToolValidationRunResult> results;

  /// Configured callable surface coverage.
  final ToolValidationCoverageResult coverage;

  /// Command operation input-schema coverage.
  final ToolValidationCoverageResult inputSchemaCoverage;

  /// Agent-call ids exposed by this tool package.
  final List<String> agentToolCalls;

  /// Agent-callable tool contracts exposed by this package.
  final Map<String, ToolValidationAgentToolContractResult> agentToolContracts;

  /// Validation ids or labels with no real assertions.
  final List<String> missingAssertions;

  /// Parses a validation suite result from decoded JSON.
  factory ToolValidationSuiteResult.fromJson(Map<String, dynamic> json) {
    final agentToolCalls = stringList(json['agent_tool_calls'], trim: true);
    return ToolValidationSuiteResult(
      total: intValue(json['total']),
      passed: intValue(json['passed']),
      failed: intValue(json['failed']),
      unsupported: intValue(json['unsupported']),
      coverage: ToolValidationCoverageResult.fromJson(
        jsonObject(json['coverage']),
      ),
      inputSchemaCoverage: ToolValidationCoverageResult.fromJson(
        jsonObject(json['input_schema_coverage']),
      ),
      agentToolCalls: agentToolCalls,
      agentToolContracts: _agentToolContractsFromJson(
        jsonObject(json['agent_tool_contracts']),
        preferredOrder: agentToolCalls,
      ),
      missingAssertions: stringList(json['missing_assertions'], trim: true),
      results: jsonObjectList(
        json['results'],
      ).map(ToolValidationRunResult.fromJson).toList(),
    );
  }

  /// Encodes this suite result as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'total': total,
      'passed': passed,
      'failed': failed,
      'unsupported': unsupported,
      'coverage': coverage.toJson(),
      'input_schema_coverage': inputSchemaCoverage.toJson(),
      'agent_tool_calls': agentToolCalls,
      'agent_tool_contracts': <String, dynamic>{
        for (final entry in agentToolContracts.entries)
          entry.key: entry.value.toJson(),
      },
      'missing_assertions': missingAssertions,
      'results': results.map((result) => result.toJson()).toList(),
    };
  }

  /// Returns whether every validation passed.
  bool get passedAll => total > 0 && failed == 0 && unsupported == 0;
}

/// ToolValidationAgentToolContractResult stores one agent-callable contract.
class ToolValidationAgentToolContractResult {
  /// Creates an immutable agent-callable tool contract.
  const ToolValidationAgentToolContractResult({
    required this.id,
    required this.inputSchema,
  });

  /// Stable contract id, such as command:rg.search_text.
  final String id;

  /// Optional input schema for command-backed contracts.
  final Map<String, dynamic> inputSchema;

  /// Parses one agent-callable contract from decoded JSON.
  factory ToolValidationAgentToolContractResult.fromJson(
    String fallbackId,
    Map<String, dynamic> json,
  ) {
    final id = stringValue(json['id'], trim: true);
    return ToolValidationAgentToolContractResult(
      id: id.isEmpty ? fallbackId : id,
      inputSchema: jsonObject(json['input_schema']),
    );
  }

  /// Encodes this contract as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      if (inputSchema.isNotEmpty) 'input_schema': inputSchema,
    };
  }
}

/// Parses agent-callable tool contracts keyed by contract id.
Map<String, ToolValidationAgentToolContractResult> _agentToolContractsFromJson(
  Map<String, dynamic> json, {
  List<String> preferredOrder = const <String>[],
}) {
  final contracts = <String, ToolValidationAgentToolContractResult>{};
  final sortedKeys = json.keys.map((key) => key.trim()).where((key) {
    return key.isNotEmpty;
  }).toList()..sort();
  final orderedKeys = <String>[
    for (final key in preferredOrder)
      if (sortedKeys.contains(key)) key,
    for (final key in sortedKeys)
      if (!preferredOrder.contains(key)) key,
  ];
  for (final key in orderedKeys) {
    final value = json[key];
    if (value is Map<String, dynamic>) {
      contracts[key] = ToolValidationAgentToolContractResult.fromJson(
        key,
        value,
      );
    } else if (value is Map) {
      contracts[key] = ToolValidationAgentToolContractResult.fromJson(
        key,
        <String, dynamic>{
          for (final entry in value.entries) entry.key.toString(): entry.value,
        },
      );
    }
  }
  return contracts;
}

/// ToolValidationCoverageResult stores validation target coverage.
class ToolValidationCoverageResult {
  /// Creates an immutable target coverage summary.
  const ToolValidationCoverageResult({
    required this.required,
    required this.covered,
    required this.missing,
  });

  /// Number of configured targets that should have validations.
  final int required;

  /// Number of configured targets covered by validations.
  final int covered;

  /// Configured targets missing validation coverage.
  final List<ToolValidationCoverageItem> missing;

  /// Parses one coverage summary from decoded JSON.
  factory ToolValidationCoverageResult.fromJson(Map<String, dynamic> json) {
    return ToolValidationCoverageResult(
      required: intValue(json['required']),
      covered: intValue(json['covered']),
      missing: jsonObjectList(
        json['missing'],
      ).map(ToolValidationCoverageItem.fromJson).toList(),
    );
  }

  /// Encodes this coverage summary as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'required': required,
      'covered': covered,
      'missing': missing.map((item) => item.toJson()).toList(),
    };
  }
}

/// ToolValidationCoverageItem identifies one untested configured target.
class ToolValidationCoverageItem {
  /// Creates an immutable missing target record.
  const ToolValidationCoverageItem({
    required this.type,
    required this.id,
    required this.label,
  });

  /// Target type, such as command-operation, agent-tool-call, workflow-node, or mcp-tool.
  final String type;

  /// Stable target id.
  final String id;

  /// Human-readable target label.
  final String label;

  /// Parses one missing coverage item from decoded JSON.
  factory ToolValidationCoverageItem.fromJson(Map<String, dynamic> json) {
    return ToolValidationCoverageItem(
      type: stringValue(json['type'], trim: true),
      id: stringValue(json['id'], trim: true),
      label: stringValue(json['label'], trim: true),
    );
  }

  /// Encodes this coverage item as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'type': type, 'id': id, 'label': label};
  }
}

/// ToolValidationRunResult stores one validation case result.
class ToolValidationRunResult {
  /// Creates an immutable validation case result.
  const ToolValidationRunResult({
    required this.id,
    required this.label,
    required this.description,
    required this.mode,
    required this.status,
    required this.target,
    required this.command,
    required this.assertions,
    required this.diagnostics,
  });

  /// Validation id.
  final String id;

  /// Human-readable validation label.
  final String label;

  /// Human-readable validation description.
  final String description;

  /// Execution mode used by the runner.
  final String mode;

  /// Result status, such as passed, failed, or unsupported.
  final String status;

  /// Runtime target exercised by the validation.
  final ToolValidationTargetResult target;

  /// Command execution result captured for command-backed validations.
  final ToolValidationCommandResult? command;

  /// Assertion outcomes.
  final List<ToolValidationAssertionResult> assertions;

  /// Runner diagnostics.
  final List<ToolValidationDiagnostic> diagnostics;

  /// Parses one validation result from decoded JSON.
  factory ToolValidationRunResult.fromJson(Map<String, dynamic> json) {
    return ToolValidationRunResult(
      id: stringValue(json['id'], trim: true),
      label: stringValue(json['label'], trim: true),
      description: stringValue(json['description'], trim: true),
      mode: stringValue(json['mode'], trim: true),
      status: stringValue(json['status'], trim: true),
      target: ToolValidationTargetResult.fromJson(jsonObject(json['target'])),
      command: json['command'] is Map<String, dynamic>
          ? ToolValidationCommandResult.fromJson(jsonObject(json['command']))
          : null,
      assertions: jsonObjectList(
        json['assertions'],
      ).map(ToolValidationAssertionResult.fromJson).toList(),
      diagnostics: jsonObjectList(
        json['diagnostics'],
      ).map(ToolValidationDiagnostic.fromJson).toList(),
    );
  }

  /// Encodes this validation result as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'description': description,
      'mode': mode,
      'status': status,
      'target': target.toJson(),
      if (command != null) 'command': command!.toJson(),
      'assertions': assertions.map((assertion) => assertion.toJson()).toList(),
      'diagnostics': diagnostics
          .map((diagnostic) => diagnostic.toJson())
          .toList(),
    };
  }
}

/// ToolValidationTargetResult describes the runtime boundary under test.
class ToolValidationTargetResult {
  /// Creates an immutable validation target result.
  const ToolValidationTargetResult({
    required this.type,
    required this.presetId,
    required this.command,
    required this.operation,
    required this.mcpServer,
    required this.mcpTool,
    required this.templateId,
    required this.boundary,
  });

  /// Target type, such as command-operation or workflow-node.
  final String type;

  /// Workflow node preset id, when used.
  final String presetId;

  /// Command tool id, when used.
  final String command;

  /// Command operation id, when used.
  final String operation;

  /// MCP server id, when used.
  final String mcpServer;

  /// MCP tool id, when used.
  final String mcpTool;

  /// Command template id, when used.
  final String templateId;

  /// Runtime boundary exercised by the validation.
  final String boundary;

  /// Parses one validation target from decoded JSON.
  factory ToolValidationTargetResult.fromJson(Map<String, dynamic> json) {
    return ToolValidationTargetResult(
      type: stringValue(json['type'], trim: true),
      presetId: stringValue(json['preset_id'], trim: true),
      command: stringValue(json['command'], trim: true),
      operation: stringValue(json['operation'], trim: true),
      mcpServer: stringValue(json['mcp_server'], trim: true),
      mcpTool: stringValue(json['mcp_tool'], trim: true),
      templateId: stringValue(json['template_id'], trim: true),
      boundary: stringValue(json['boundary'], trim: true),
    );
  }

  /// Encodes this target result as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'preset_id': presetId,
      'command': command,
      'operation': operation,
      'mcp_server': mcpServer,
      'mcp_tool': mcpTool,
      'template_id': templateId,
      'boundary': boundary,
    };
  }
}

/// ToolValidationCommandResult stores one captured command invocation result.
class ToolValidationCommandResult {
  /// Creates an immutable command validation result.
  const ToolValidationCommandResult({
    required this.jobId,
    required this.status,
    required this.exitCode,
    required this.stdoutTail,
    required this.stderrTail,
    required this.truncated,
    required this.timedOut,
    required this.error,
    required this.startedAt,
    required this.endedAt,
    required this.output,
    required this.diagnostics,
    required this.artifacts,
    required this.validation,
  });

  /// Command job id.
  final String jobId;

  /// Command status.
  final String status;

  /// Process exit code.
  final int exitCode;

  /// Captured stdout tail.
  final String stdoutTail;

  /// Captured stderr tail.
  final String stderrTail;

  /// Whether output was truncated.
  final bool truncated;

  /// Whether the command timed out.
  final bool timedOut;

  /// Runtime error message.
  final String error;

  /// Command start timestamp.
  final String startedAt;

  /// Command end timestamp.
  final String endedAt;

  /// Parsed or raw command output payload.
  final dynamic output;

  /// Parser or command diagnostics.
  final List<ToolValidationCommandDiagnostic> diagnostics;

  /// Files emitted by the command.
  final List<ToolValidationCommandArtifact> artifacts;

  /// Output schema validation result.
  final ToolValidationCommandOutputValidation validation;

  /// Parses one command result from decoded JSON.
  factory ToolValidationCommandResult.fromJson(Map<String, dynamic> json) {
    return ToolValidationCommandResult(
      jobId: stringValue(json['job_id'], trim: true),
      status: stringValue(json['status'], trim: true),
      exitCode: intValue(json['exit_code']),
      stdoutTail: stringValue(json['stdout_tail']),
      stderrTail: stringValue(json['stderr_tail']),
      truncated: boolValue(json['truncated']),
      timedOut: boolValue(json['timed_out']),
      error: stringValue(json['error'], trim: true),
      startedAt: stringValue(json['started_at'], trim: true),
      endedAt: stringValue(json['ended_at'], trim: true),
      output: json['output'],
      diagnostics: jsonObjectList(
        json['diagnostics'],
      ).map(ToolValidationCommandDiagnostic.fromJson).toList(),
      artifacts: jsonObjectList(
        json['artifacts'],
      ).map(ToolValidationCommandArtifact.fromJson).toList(),
      validation: ToolValidationCommandOutputValidation.fromJson(
        jsonObject(json['validation']),
      ),
    );
  }

  /// Encodes this command result as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'job_id': jobId,
      'status': status,
      'exit_code': exitCode,
      'stdout_tail': stdoutTail,
      'stderr_tail': stderrTail,
      'truncated': truncated,
      'timed_out': timedOut,
      'error': error,
      'started_at': startedAt,
      'ended_at': endedAt,
      if (output != null) 'output': output,
      'diagnostics': diagnostics
          .map((diagnostic) => diagnostic.toJson())
          .toList(),
      'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
      'validation': validation.toJson(),
    };
  }
}

/// ToolValidationCommandDiagnostic stores parser diagnostics for a command.
class ToolValidationCommandDiagnostic {
  /// Creates an immutable command diagnostic.
  const ToolValidationCommandDiagnostic({
    required this.severity,
    required this.message,
  });

  /// Diagnostic severity.
  final String severity;

  /// Diagnostic message.
  final String message;

  /// Parses one command diagnostic from decoded JSON.
  factory ToolValidationCommandDiagnostic.fromJson(Map<String, dynamic> json) {
    return ToolValidationCommandDiagnostic(
      severity: stringValue(json['severity'], trim: true),
      message: stringValue(json['message'], trim: true),
    );
  }

  /// Encodes this diagnostic as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'severity': severity, 'message': message};
  }
}

/// ToolValidationCommandArtifact stores one command output artifact.
class ToolValidationCommandArtifact {
  /// Creates an immutable command artifact.
  const ToolValidationCommandArtifact({required this.path, required this.size});

  /// Artifact path.
  final String path;

  /// Artifact size in bytes.
  final int size;

  /// Parses one command artifact from decoded JSON.
  factory ToolValidationCommandArtifact.fromJson(Map<String, dynamic> json) {
    return ToolValidationCommandArtifact(
      path: stringValue(json['path'], trim: true),
      size: intValue(json['size']),
    );
  }

  /// Encodes this artifact as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'path': path, 'size': size};
  }
}

/// ToolValidationCommandOutputValidation stores output schema check results.
class ToolValidationCommandOutputValidation {
  /// Creates an immutable output validation result.
  const ToolValidationCommandOutputValidation({
    required this.checked,
    required this.valid,
    required this.errors,
  });

  /// Whether schema validation was checked.
  final bool checked;

  /// Whether schema validation passed.
  final bool valid;

  /// Schema validation errors.
  final List<String> errors;

  /// Parses one output validation result from decoded JSON.
  factory ToolValidationCommandOutputValidation.fromJson(
    Map<String, dynamic> json,
  ) {
    return ToolValidationCommandOutputValidation(
      checked: boolValue(json['checked']),
      valid: boolValue(json['valid']),
      errors: stringList(json['errors'], trim: true),
    );
  }

  /// Encodes this output validation result as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'checked': checked,
      'valid': valid,
      'errors': errors,
    };
  }
}

/// ToolValidationAssertionResult stores one assertion outcome.
class ToolValidationAssertionResult {
  /// Creates an immutable assertion result.
  const ToolValidationAssertionResult({
    required this.type,
    required this.path,
    required this.passed,
    required this.expected,
    required this.actual,
    required this.message,
  });

  /// Assertion type.
  final String type;

  /// Optional inspected path.
  final String path;

  /// Whether the assertion passed.
  final bool passed;

  /// Expected assertion value.
  final dynamic expected;

  /// Actual assertion value.
  final dynamic actual;

  /// Failure or diagnostic message.
  final String message;

  /// Parses one assertion result from decoded JSON.
  factory ToolValidationAssertionResult.fromJson(Map<String, dynamic> json) {
    return ToolValidationAssertionResult(
      type: stringValue(json['type'], trim: true),
      path: stringValue(json['path'], trim: true),
      passed: boolValue(json['passed']),
      expected: json['expected'],
      actual: json['actual'],
      message: stringValue(json['message'], trim: true),
    );
  }

  /// Encodes this assertion result as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'path': path,
      'passed': passed,
      'expected': expected,
      'actual': actual,
      'message': message,
    };
  }
}

/// ToolValidationDiagnostic stores one runner diagnostic message.
class ToolValidationDiagnostic {
  /// Creates an immutable validation diagnostic.
  const ToolValidationDiagnostic({
    required this.severity,
    required this.message,
  });

  /// Diagnostic severity.
  final String severity;

  /// Diagnostic message.
  final String message;

  /// Parses one diagnostic result from decoded JSON.
  factory ToolValidationDiagnostic.fromJson(Map<String, dynamic> json) {
    return ToolValidationDiagnostic(
      severity: stringValue(json['severity'], trim: true),
      message: stringValue(json['message'], trim: true),
    );
  }

  /// Encodes this runner diagnostic as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'severity': severity, 'message': message};
  }
}
