/// Private route and filter models for the Today attention screen.
part of 'attention_screen.dart';

/// _AttentionScope stores route-derived filtering context.
class _AttentionScope {
  /// Creates an attention scope from a reserved route.
  const _AttentionScope({
    required this.metric,
    required this.lanes,
    required this.itemId,
  });

  /// Metric name that opened the screen.
  final String metric;

  /// Attention lanes included in the scope.
  final Set<String> lanes;

  /// Optional selected item or task id from the route.
  final String itemId;
}

/// _AttentionFilter defines local attention view categories.
enum _AttentionFilter {
  /// Shows every item in the route scope.
  all,

  /// Shows items missing enough detail to act cleanly.
  clarify,

  /// Shows items lacking due, scheduled, or follow-up dates.
  schedule,

  /// Shows decision or review items.
  review,
}
