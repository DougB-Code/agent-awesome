/// Backlog task score and dialog field helpers.
part of 'backlog_section.dart';

/// Formats a normalized score for inspector display.
String _formatTaskScore(double value) {
  if (value <= 0) {
    return '';
  }
  return '${(value * 100).round()}%';
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

/// Builds dialog field decoration consistent with task text fields.
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
