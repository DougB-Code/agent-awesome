/// Backlog task score, suggestion, and dialog field helpers.
part of 'backlog_section.dart';

/// Formats a normalized score for inspector display.
String _formatTaskScore(double value) {
  if (value <= 0) {
    return '';
  }
  return '${(value * 100).round()}%';
}

/// Summarizes proposed task metadata fields for the inspector.
String _metadataSuggestionSummary(TaskMetadataSuggestion suggestion) {
  final parts = <String>[
    if (suggestion.estimateMinutes > 0) '${suggestion.estimateMinutes} min',
    if (suggestion.energyRequired.isNotEmpty) suggestion.energyRequired,
    if (suggestion.context.isNotEmpty) suggestion.context,
    if (suggestion.domain.isNotEmpty) suggestion.domain,
    if (suggestion.location.isNotEmpty) suggestion.location,
    if (suggestion.effort > 0) 'effort ${_formatTaskScore(suggestion.effort)}',
    if (suggestion.value > 0) 'value ${_formatTaskScore(suggestion.value)}',
    if (suggestion.urgency > 0)
      'urgency ${_formatTaskScore(suggestion.urgency)}',
    if (suggestion.risk > 0) 'risk ${_formatTaskScore(suggestion.risk)}',
  ];
  if (parts.isEmpty) {
    return suggestion.explanation;
  }
  return parts.join(' • ');
}

/// Summarizes proposed commitment fields for the inspector.
String _commitmentSuggestionSummary(TaskCommitmentSuggestion suggestion) {
  final parts = <String>[
    if (suggestion.domain.isNotEmpty) suggestion.domain,
    if (suggestion.project.isNotEmpty) suggestion.project,
    if (suggestion.timeWindow.isNotEmpty) suggestion.timeWindow,
    if (suggestion.responsibility.isNotEmpty) suggestion.responsibility,
    if (suggestion.promiseSource.isNotEmpty) suggestion.promiseSource,
    if (suggestion.consequence.isNotEmpty) suggestion.consequence,
  ];
  if (parts.isEmpty) {
    return suggestion.explanation;
  }
  return parts.join(' • ');
}

/// Formats a normalized score for dialog input.
String _scoreInputText(double value) {
  if (value <= 0) {
    return '';
  }
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Parses a dialog score where blank means no explicit signal.
double? _parseDialogScore(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return 0;
  }
  final score = double.tryParse(text);
  if (score == null || score < 0 || score > 1) {
    return null;
  }
  return score;
}

/// Builds dialog field decoration consistent with context text fields.
InputDecoration _taskDialogDecoration(BuildContext context, String label) {
  final colors = context.agentAwesomeColors;
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: colors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.searchBorder),
    ),
  );
}
