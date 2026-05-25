/// Merges partial portable tool validation runs without losing suite metadata.
library;

import 'tool_validation_result.dart';

/// Returns a suite result with selected validation reruns folded into history.
ToolValidationSuiteResult mergeToolValidationSuiteResults(
  ToolValidationSuiteResult? previous,
  ToolValidationSuiteResult next,
) {
  if (previous == null || previous.results.isEmpty) {
    return next;
  }
  final replacements = <String, ToolValidationRunResult>{
    for (final result in next.results) result.id: result,
  };
  final merged = <ToolValidationRunResult>[];
  for (final result in previous.results) {
    merged.add(replacements.remove(result.id) ?? result);
  }
  merged.addAll(replacements.values);
  return toolValidationSuiteFromResults(
    merged,
    coverage: next.coverage,
    inputSchemaCoverage: next.inputSchemaCoverage,
    agentToolCalls: next.agentToolCalls,
    agentToolContracts: next.agentToolContracts,
    missingAssertions: next.missingAssertions,
  );
}

/// Builds suite counters from validation rows and explicit suite metadata.
ToolValidationSuiteResult toolValidationSuiteFromResults(
  List<ToolValidationRunResult> results, {
  required ToolValidationCoverageResult coverage,
  required ToolValidationCoverageResult inputSchemaCoverage,
  required List<String> agentToolCalls,
  required Map<String, ToolValidationAgentToolContractResult>
  agentToolContracts,
  required List<String> missingAssertions,
}) {
  var passed = 0;
  var failed = 0;
  var unsupported = 0;
  for (final result in results) {
    switch (result.status) {
      case 'passed':
        passed++;
      case 'unsupported':
        unsupported++;
      default:
        failed++;
    }
  }
  return ToolValidationSuiteResult(
    total: results.length,
    passed: passed,
    failed: failed,
    unsupported: unsupported,
    coverage: coverage,
    inputSchemaCoverage: inputSchemaCoverage,
    agentToolCalls: agentToolCalls,
    agentToolContracts: agentToolContracts,
    missingAssertions: missingAssertions,
    results: results,
  );
}
