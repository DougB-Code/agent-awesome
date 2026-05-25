/// Parses combined package-library validation runner results.
library;

import 'agent_validation_result.dart';
import 'json_value.dart';
import 'tool_validation_result.dart';

/// LibraryValidationResult stores one combined agent/tool package library run.
class LibraryValidationResult {
  /// Creates an immutable combined package-library validation result.
  const LibraryValidationResult({
    required this.root,
    required this.agentPath,
    required this.agentDir,
    required this.toolPath,
    required this.toolDir,
    required this.mcpDir,
    required this.error,
    required this.total,
    required this.passed,
    required this.failed,
    required this.unsupported,
    required this.agents,
    required this.tools,
  });

  /// Package library root path.
  final String root;

  /// Single agent config file checked by the run.
  final String agentPath;

  /// Agent package directory checked by the run.
  final String agentDir;

  /// Single tool config file checked by the run.
  final String toolPath;

  /// Tool package directory checked by the run.
  final String toolDir;

  /// MCP package directory checked by the run.
  final String mcpDir;

  /// Top-level setup error, such as a missing required package directory.
  final String error;

  /// Number of packages checked across all package types.
  final int total;

  /// Number of passing packages across all package types.
  final int passed;

  /// Number of failed packages across all package types.
  final int failed;

  /// Number of unsupported packages across all package types.
  final int unsupported;

  /// Agent package validation aggregate when agent validation was run.
  final AgentValidationResult? agents;

  /// Tool package validation aggregate when tool validation was run.
  final ToolValidationLibraryResult? tools;

  /// Parses a combined package-library result from decoded JSON.
  factory LibraryValidationResult.fromJson(Map<String, dynamic> json) {
    final agentsJson = json['agents'];
    final toolsJson = json['tools'];
    return LibraryValidationResult(
      root: stringValue(json['root'], trim: true),
      agentPath: stringValue(json['agent_path'], trim: true),
      agentDir: stringValue(json['agent_dir'], trim: true),
      toolPath: stringValue(json['tool_path'], trim: true),
      toolDir: stringValue(json['tool_dir'], trim: true),
      mcpDir: stringValue(json['mcp_dir'], trim: true),
      error: stringValue(json['error'], trim: true),
      total: intValue(json['total']),
      passed: intValue(json['passed']),
      failed: intValue(json['failed']),
      unsupported: intValue(json['unsupported']),
      agents: agentsJson is Map<String, dynamic>
          ? AgentValidationResult.fromJson(agentsJson)
          : null,
      tools: toolsJson is Map<String, dynamic>
          ? ToolValidationLibraryResult.fromJson(toolsJson)
          : null,
    );
  }

  /// Returns whether every package in the library passed validation.
  bool get passedAll => total > 0 && failed == 0 && unsupported == 0;
}
