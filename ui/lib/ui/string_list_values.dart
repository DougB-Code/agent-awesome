/// Provides shared string-list editing helpers for UI forms and filters.
library;

/// Toggles one string in a list, optionally preserving at least one value.
List<String> toggleStringValue(
  List<String> values,
  String value, {
  bool allowEmpty = true,
}) {
  if (values.contains(value)) {
    if (!allowEmpty && values.length == 1) {
      return values;
    }
    return values.where((item) => item != value).toList();
  }
  return <String>[...values, value];
}

/// Splits comma-delimited user input into non-empty trimmed values.
List<String> splitCommaSeparatedValues(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}
