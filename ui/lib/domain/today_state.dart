/// Defines state used by the Today screen presenter.
library;

import 'executive_summary.dart';

/// TodayState stores loading, error, projection, and explanation UI state.
class TodayState {
  /// Creates Today screen state.
  const TodayState({
    this.busy = false,
    this.error = '',
    this.projection = const ExecutiveSummaryProjection.empty(),
    this.selectedExplanationItemId = '',
    this.explanation = const ExecutiveSummaryItemExplanation(),
  });

  /// Whether a projection or explanation request is running.
  final bool busy;

  /// Last Today-specific error.
  final String error;

  /// Latest canonical projection.
  final ExecutiveSummaryProjection projection;

  /// Item currently selected for explanation.
  final String selectedExplanationItemId;

  /// Latest explanation payload.
  final ExecutiveSummaryItemExplanation explanation;

  /// Returns a state copy with selected fields changed.
  TodayState copyWith({
    bool? busy,
    String? error,
    ExecutiveSummaryProjection? projection,
    String? selectedExplanationItemId,
    ExecutiveSummaryItemExplanation? explanation,
  }) {
    return TodayState(
      busy: busy ?? this.busy,
      error: error ?? this.error,
      projection: projection ?? this.projection,
      selectedExplanationItemId:
          selectedExplanationItemId ?? this.selectedExplanationItemId,
      explanation: explanation ?? this.explanation,
    );
  }
}
