/// Merges partial portable agent validation runs without losing suite metadata.
library;

import 'agent_validation_result.dart';

/// Returns a suite result with selected validation reruns folded into history.
AgentValidationSuiteResult mergeAgentValidationSuiteResults(
  AgentValidationSuiteResult? previous,
  AgentValidationSuiteResult next,
) {
  if (previous == null || previous.results.isEmpty) {
    return next;
  }
  final replacements = <String, AgentValidationRunResult>{
    for (final result in next.results) result.id: result,
  };
  final merged = <AgentValidationRunResult>[];
  for (final result in previous.results) {
    merged.add(replacements.remove(result.id) ?? result);
  }
  merged.addAll(replacements.values);
  return agentValidationSuiteFromResults(
    merged,
    toolCallReferences: next.toolCallReferences,
  );
}

/// Builds suite counters from validation rows and explicit suite metadata.
AgentValidationSuiteResult agentValidationSuiteFromResults(
  List<AgentValidationRunResult> results, {
  required List<String> toolCallReferences,
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
  return AgentValidationSuiteResult(
    total: results.length,
    passed: passed,
    failed: failed,
    unsupported: unsupported,
    toolCallReferences: toolCallReferences,
    results: results,
  );
}
