/// Backlog task filter label and option helpers.
part of 'backlog_section.dart';

/// Reports whether the filter state matches the bundled Active view.
bool _isActiveTaskView(TaskFilterState filters) {
  return _sameFilterValues(filters.statuses, _activeTaskStatuses);
}

/// Returns the compact status filter summary.
String _statusFilterLabel(TaskFilterState filters) {
  if (filters.statuses.isEmpty) {
    return filters.overdueOnly ? 'Overdue' : 'Status';
  }
  final statusLabel = _joinedFilterLabels(filters.statuses, _taskLabel);
  return filters.overdueOnly ? '$statusLabel + overdue' : statusLabel;
}

/// Returns the compact priority filter summary.
String _priorityFilterLabel(TaskFilterState filters) {
  if (filters.priorities.isEmpty) {
    return 'Priority';
  }
  return _joinedFilterLabels(filters.priorities, _taskLabel);
}

/// Returns the compact topic filter summary.
String _topicFilterLabel(TaskFilterState filters) {
  if (filters.topics.isEmpty) {
    return 'Topics';
  }
  return _joinedFilterLabels(filters.topics, (topic) => topic);
}

/// Returns topic filter choices with selected topics kept visible.
List<String> _topicFilterOptions(
  TaskFilterState filters,
  Iterable<String> availableTopics,
) {
  final seen = <String>{};
  final topics = <String>[];
  for (final topic in <String>[
    ...filters.topics,
    ...availableTopics.take(16),
  ]) {
    final trimmed = topic.trim();
    if (trimmed.isNotEmpty && seen.add(trimmed)) {
      topics.add(trimmed);
    }
  }
  return topics;
}

/// Returns selected filter values as readable labels instead of counts.
String _joinedFilterLabels(
  List<String> values,
  String Function(String value) labelFor,
) {
  return values
      .map((value) => labelFor(value).trim())
      .where((label) => label.isNotEmpty)
      .join(', ');
}

/// Reports whether two filter value lists contain the same values.
bool _sameFilterValues(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  final rightValues = right.toSet();
  return left.every(rightValues.contains);
}
