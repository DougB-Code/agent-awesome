/// Parses portable agent validation runner results.
library;

import 'json_value.dart';

/// AgentValidationResult stores validation output for one or more agent packages.
class AgentValidationResult {
  /// Creates an immutable agent validation result.
  const AgentValidationResult({
    required this.total,
    required this.passed,
    required this.failed,
    required this.unsupported,
    required this.validationTotal,
    required this.validationPassed,
    required this.validationFailed,
    required this.validationUnsupported,
    required this.toolCallReferences,
    required this.agents,
  });

  /// Number of agent packages checked.
  final int total;

  /// Number of passing agent packages.
  final int passed;

  /// Number of failed agent packages.
  final int failed;

  /// Number of unsupported agent packages.
  final int unsupported;

  /// Number of validation cases checked.
  final int validationTotal;

  /// Number of passing validation cases.
  final int validationPassed;

  /// Number of failed validation cases.
  final int validationFailed;

  /// Number of unsupported validation cases.
  final int validationUnsupported;

  /// Agent tool-call contract ids proven by validation cases.
  final List<String> toolCallReferences;

  /// Per-agent package results.
  final List<AgentValidationFileResult> agents;

  /// Parses a validation result from decoded JSON.
  factory AgentValidationResult.fromJson(Map<String, dynamic> json) {
    return AgentValidationResult(
      total: intValue(json['total']),
      passed: intValue(json['passed']),
      failed: intValue(json['failed']),
      unsupported: intValue(json['unsupported']),
      validationTotal: intValue(json['validation_total']),
      validationPassed: intValue(json['validation_passed']),
      validationFailed: intValue(json['validation_failed']),
      validationUnsupported: intValue(json['validation_unsupported']),
      toolCallReferences: stringList(json['tool_call_references'], trim: true),
      agents: jsonObjectList(
        json['agents'],
      ).map(AgentValidationFileResult.fromJson).toList(),
    );
  }

  /// Returns whether every package and validation passed.
  bool get passedAll => total > 0 && failed == 0 && unsupported == 0;
}

/// AgentValidationFileResult stores one agent package result.
class AgentValidationFileResult {
  /// Creates an immutable file-level validation result.
  const AgentValidationFileResult({
    required this.path,
    required this.name,
    required this.passed,
    required this.unsupported,
    required this.error,
    required this.missingAssertions,
    required this.missingToolCalls,
    required this.unknownToolCalls,
    required this.invalidToolArguments,
    required this.result,
  });

  /// Agent config path.
  final String path;

  /// Agent name.
  final String name;

  /// Whether the agent package passed.
  final bool passed;

  /// Whether the package contains unsupported validation behavior.
  final bool unsupported;

  /// Package load or validation error.
  final String error;

  /// Validation ids that failed because they have no concrete assertions.
  final List<String> missingAssertions;

  /// Agent packages that failed because validations prove no tool selection.
  final List<String> missingToolCalls;

  /// Validation tool-call references that did not resolve to packaged tools.
  final List<String> unknownToolCalls;

  /// Validation tool calls with arguments that do not match package schemas.
  final List<String> invalidToolArguments;

  /// Per-validation suite result.
  final AgentValidationSuiteResult result;

  /// Parses one file-level result from decoded JSON.
  factory AgentValidationFileResult.fromJson(Map<String, dynamic> json) {
    return AgentValidationFileResult(
      path: stringValue(json['path'], trim: true),
      name: stringValue(json['name'], trim: true),
      passed: boolValue(json['passed']),
      unsupported: boolValue(json['unsupported']),
      error: stringValue(json['error'], trim: true),
      missingAssertions: stringList(json['missing_assertions'], trim: true),
      missingToolCalls: stringList(json['missing_tool_calls'], trim: true),
      unknownToolCalls: stringList(json['unknown_tool_calls'], trim: true),
      invalidToolArguments: stringList(
        json['invalid_tool_arguments'],
        trim: true,
      ),
      result: AgentValidationSuiteResult.fromJson(jsonObject(json['result'])),
    );
  }
}

/// AgentValidationSuiteResult stores one agent package validation suite.
class AgentValidationSuiteResult {
  /// Creates an immutable suite result.
  const AgentValidationSuiteResult({
    required this.total,
    required this.passed,
    required this.failed,
    required this.unsupported,
    required this.toolCallReferences,
    required this.results,
  });

  /// Number of validation cases.
  final int total;

  /// Number of passing cases.
  final int passed;

  /// Number of failed cases.
  final int failed;

  /// Number of unsupported cases.
  final int unsupported;

  /// Agent tool-call contract ids proven by validation cases.
  final List<String> toolCallReferences;

  /// Per-validation results.
  final List<AgentValidationRunResult> results;

  /// Parses one suite result from decoded JSON.
  factory AgentValidationSuiteResult.fromJson(Map<String, dynamic> json) {
    return AgentValidationSuiteResult(
      total: intValue(json['total']),
      passed: intValue(json['passed']),
      failed: intValue(json['failed']),
      unsupported: intValue(json['unsupported']),
      toolCallReferences: stringList(json['tool_call_references'], trim: true),
      results: jsonObjectList(
        json['results'],
      ).map(AgentValidationRunResult.fromJson).toList(),
    );
  }
}

/// AgentValidationRunResult stores one behavior validation result.
class AgentValidationRunResult {
  /// Creates an immutable validation case result.
  const AgentValidationRunResult({
    required this.id,
    required this.label,
    required this.mode,
    required this.prompt,
    required this.input,
    required this.fixtures,
    required this.status,
    required this.response,
    required this.assertions,
    required this.diagnostics,
  });

  /// Validation id.
  final String id;

  /// Human-readable label.
  final String label;

  /// Execution mode.
  final String mode;

  /// Prompt under test.
  final String prompt;

  /// Scenario input supplied to the validation.
  final Map<String, dynamic> input;

  /// Scenario fixtures supplied to the validation.
  final Map<String, dynamic> fixtures;

  /// Result status.
  final String status;

  /// Captured agent response.
  final AgentValidationResponseResult response;

  /// Assertion outcomes.
  final List<AgentValidationAssertionResult> assertions;

  /// Runner diagnostics.
  final List<AgentValidationDiagnostic> diagnostics;

  /// Parses one validation case result from decoded JSON.
  factory AgentValidationRunResult.fromJson(Map<String, dynamic> json) {
    return AgentValidationRunResult(
      id: stringValue(json['id'], trim: true),
      label: stringValue(json['label'], trim: true),
      mode: stringValue(json['mode'], trim: true),
      prompt: stringValue(json['prompt'], trim: true),
      input: jsonObject(json['input']),
      fixtures: jsonObject(json['fixtures']),
      status: stringValue(json['status'], trim: true),
      response: AgentValidationResponseResult.fromJson(
        jsonObject(json['response']),
      ),
      assertions: jsonObjectList(
        json['assertions'],
      ).map(AgentValidationAssertionResult.fromJson).toList(),
      diagnostics: jsonObjectList(
        json['diagnostics'],
      ).map(AgentValidationDiagnostic.fromJson).toList(),
    );
  }
}

/// AgentValidationResponseResult stores a captured agent response.
class AgentValidationResponseResult {
  /// Creates an immutable agent response result.
  const AgentValidationResponseResult({
    required this.text,
    required this.toolCalls,
    required this.output,
  });

  /// Response text.
  final String text;

  /// Tool calls selected by the agent.
  final List<AgentValidationToolCallResult> toolCalls;

  /// Structured output returned by the agent host, when available.
  final dynamic output;

  /// Parses one response result from decoded JSON.
  factory AgentValidationResponseResult.fromJson(Map<String, dynamic> json) {
    return AgentValidationResponseResult(
      text: stringValue(json['text'], trim: true),
      toolCalls: jsonObjectList(
        json['tool_calls'],
      ).map(AgentValidationToolCallResult.fromJson).toList(),
      output: json['output'],
    );
  }
}

/// AgentValidationToolCallResult stores one selected tool call.
class AgentValidationToolCallResult {
  /// Creates an immutable tool call result.
  const AgentValidationToolCallResult({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// Stable tool call id.
  final String id;

  /// Tool name.
  final String name;

  /// Tool arguments.
  final Map<String, dynamic> arguments;

  /// Parses one tool call result from decoded JSON.
  factory AgentValidationToolCallResult.fromJson(Map<String, dynamic> json) {
    return AgentValidationToolCallResult(
      id: stringValue(json['id'], trim: true),
      name: stringValue(json['name'], trim: true),
      arguments: jsonObject(json['arguments']),
    );
  }
}

/// AgentValidationAssertionResult stores one assertion outcome.
class AgentValidationAssertionResult {
  /// Creates an immutable assertion result.
  const AgentValidationAssertionResult({
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
  factory AgentValidationAssertionResult.fromJson(Map<String, dynamic> json) {
    return AgentValidationAssertionResult(
      type: stringValue(json['type'], trim: true),
      path: stringValue(json['path'], trim: true),
      passed: boolValue(json['passed']),
      expected: json['expected'],
      actual: json['actual'],
      message: stringValue(json['message'], trim: true),
    );
  }
}

/// AgentValidationDiagnostic stores one runner diagnostic.
class AgentValidationDiagnostic {
  /// Creates an immutable diagnostic.
  const AgentValidationDiagnostic({
    required this.severity,
    required this.message,
  });

  /// Diagnostic severity.
  final String severity;

  /// Diagnostic message.
  final String message;

  /// Parses one diagnostic from decoded JSON.
  factory AgentValidationDiagnostic.fromJson(Map<String, dynamic> json) {
    return AgentValidationDiagnostic(
      severity: stringValue(json['severity'], trim: true),
      message: stringValue(json['message'], trim: true),
    );
  }
}
