/// Backlog task date and vocabulary formatting helpers.
part of 'backlog_section.dart';

/// Parses a human-entered task date.
DateTime? _parseTaskDateInput(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  final direct = DateTime.tryParse(text);
  if (direct != null) {
    return direct;
  }
  final spaced = DateTime.tryParse(text.replaceFirst(' ', 'T'));
  if (spaced != null) {
    return spaced;
  }
  final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (dateOnly == null) {
    return null;
  }
  return DateTime(
    int.parse(dateOnly.group(1)!),
    int.parse(dateOnly.group(2)!),
    int.parse(dateOnly.group(3)!),
  );
}

/// Converts controlled task vocabulary to readable labels.
String _taskLabel(String value) {
  if (value.isEmpty) {
    return '';
  }
  return value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}
