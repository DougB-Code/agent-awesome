/// Backlog task filter label and option helpers.
part of 'backlog_section.dart';

/// Returns a preset label with candidate count when the preset is semantic.
String _presetLabel(
  AgentAwesomeAppController controller,
  TaskInsightPreset preset,
) {
  if (preset.id == TaskInsightIds.all) {
    return preset.label;
  }
  final count = controller.taskInsightIndex.tasksForInsight(preset.id).length;
  return '${preset.label} $count';
}

/// Returns the visible insight dropdown label.
String _presetButtonLabel(
  AgentAwesomeAppController controller,
  TaskInsightPreset preset,
) {
  if (preset.id == TaskInsightIds.all) {
    return preset.label;
  }
  return _presetLabel(controller, preset);
}

/// Reports whether the filter state matches the bundled Active view.
bool _isActiveTaskView(TaskFilterState filters) {
  return _sameFilterValues(filters.statuses, _activeTaskStatuses);
}

/// Returns the visible icon for the bundled task view control.
IconData _taskViewIcon(TaskFilterState filters) {
  if (_isActiveTaskView(filters)) {
    return Icons.playlist_play;
  }
  if (filters.statuses.isEmpty) {
    return Icons.all_inbox_outlined;
  }
  return Icons.tune;
}

/// Returns the visible label for the bundled task view control.
String _taskViewLabel(TaskFilterState filters) {
  if (_isActiveTaskView(filters)) {
    return 'Active tasks';
  }
  if (filters.statuses.isEmpty) {
    return 'All tasks';
  }
  return 'Custom tasks';
}

/// Returns the compact status filter summary.
String _statusFilterLabel(TaskFilterState filters) {
  if (filters.statuses.isEmpty || _isActiveTaskView(filters)) {
    return filters.overdueOnly ? 'Overdue' : 'Status';
  }
  final statusLabel = filters.statuses.length == 1
      ? _taskLabel(filters.statuses.first)
      : 'Status ${filters.statuses.length}';
  return filters.overdueOnly ? '$statusLabel + overdue' : statusLabel;
}

/// Returns the compact priority filter summary.
String _priorityFilterLabel(TaskFilterState filters) {
  if (filters.priorities.isEmpty) {
    return 'Priority';
  }
  if (filters.priorities.length == 1) {
    return _taskLabel(filters.priorities.first);
  }
  return 'Priority ${filters.priorities.length}';
}

/// Returns the compact topic filter summary.
String _topicFilterLabel(TaskFilterState filters) {
  if (filters.topics.isEmpty) {
    return 'Topics';
  }
  if (filters.topics.length == 1) {
    return filters.topics.first;
  }
  return 'Topics ${filters.topics.length}';
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

/// Reports whether two filter value lists contain the same values.
bool _sameFilterValues(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  final rightValues = right.toSet();
  return left.every(rightValues.contains);
}
