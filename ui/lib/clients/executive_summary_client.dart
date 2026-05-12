/// Provides the UI client for the memory-owned Today projection tools.
library;

import '../domain/executive_summary.dart';
import 'mcp_client.dart';

/// ExecutiveSummaryClient calls canonical executive summary MCP tools.
class ExecutiveSummaryClient {
  /// Creates a Today projection client from a common tool RPC client.
  const ExecutiveSummaryClient({required ToolRpcClient rpc}) : _rpc = rpc;

  final ToolRpcClient _rpc;

  /// Tool endpoint used by this client.
  String get endpoint => _rpc.endpoint;

  /// Loads the canonical executive summary projection.
  Future<ExecutiveSummaryProjection> projectExecutiveSummary({
    String firewall = 'user',
    String horizon = 'today',
    DateTime? now,
    int maxItems = 12,
    String channel = 'ui',
  }) async {
    final content = await _rpc
        .callTool('project_executive_summary', <String, dynamic>{
          'firewall': firewall,
          'horizon': horizon,
          if (now != null) 'now': now.toUtc().toIso8601String(),
          'max_items': maxItems,
          'include_evidence': true,
          'include_actions': true,
          'channel': channel,
        });
    return parseExecutiveSummaryProjection(content);
  }

  /// Loads a source-backed explanation for one surfaced projection item.
  Future<ExecutiveSummaryItemExplanation> explainExecutiveSummaryItem(
    String itemId, {
    bool includeSources = true,
  }) async {
    final content = await _rpc.callTool(
      'explain_executive_summary_item',
      <String, dynamic>{'item_id': itemId, 'include_sources': includeSources},
    );
    return parseExecutiveSummaryItemExplanation(content);
  }

  /// Closes the underlying RPC client.
  void close() {
    _rpc.close();
  }
}
