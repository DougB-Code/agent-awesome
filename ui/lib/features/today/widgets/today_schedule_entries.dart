/// Today schedule entry derivation and grouping helpers.
part of 'today_schedule_card.dart';

/// Builds schedule entries from workspace tasks and Today projection items.
List<_ScheduleEntry> _scheduledEntries({
  required ProjectWorkspace workspace,
  required ExecutiveSummaryProjection projection,
}) {
  final entries = <String, _ScheduleEntry>{};
  for (final task in workspace.tasks) {
    if (task.status == 'canceled') {
      continue;
    }
    _addTaskEntry(entries, task, task.scheduledAt, 'scheduled');
    _addTaskEntry(entries, task, task.dueAt, 'due');
    _addTaskEntry(entries, task, task.followUpAt, 'follow_up');
  }
  for (final item in projection.attention.items) {
    _addProjectionEntry(entries, item, item.scheduledAt, 'scheduled');
    _addProjectionEntry(entries, item, item.dueAt, 'due');
    _addProjectionEntry(entries, item, item.followUpAt, 'follow_up');
  }
  return entries.values.toList()..sort(_compareEntries);
}

/// Adds one task date to the schedule map.
void _addTaskEntry(
  Map<String, _ScheduleEntry> entries,
  WorkspaceTask task,
  DateTime? when,
  String kind,
) {
  if (when == null) {
    return;
  }
  final key = '${task.id}:$kind:${_dayStart(when).toIso8601String()}';
  entries[key] = _ScheduleEntry(
    id: key,
    title: task.title,
    when: when,
    kind: kind,
    detail: _taskDetail(task),
    priority: task.priority,
    done: task.done,
    route: '/backlog',
  );
}

/// Adds one projection item date when no matching task entry exists.
void _addProjectionEntry(
  Map<String, _ScheduleEntry> entries,
  ExecutiveSummaryItem item,
  DateTime? when,
  String kind,
) {
  if (when == null) {
    return;
  }
  final identity = item.taskId.isEmpty ? item.id : item.taskId;
  final key = '$identity:$kind:${_dayStart(when).toIso8601String()}';
  entries.putIfAbsent(key, () {
    return _ScheduleEntry(
      id: key,
      title: item.title,
      when: when,
      kind: kind,
      detail: _projectionDetail(item),
      priority: item.priority,
      done: item.status == 'done',
      route: item.links.isEmpty ? '/backlog' : item.links.first.route,
    );
  });
}

/// Filters entries to the selected schedule scope.
List<_ScheduleEntry> _entriesForScope({
  required List<_ScheduleEntry> entries,
  required _ScheduleScope scope,
  required DateTime now,
}) {
  final start = switch (scope) {
    _ScheduleScope.today => _dayStart(now),
    _ScheduleScope.week => _weekStart(now),
    _ScheduleScope.month => DateTime(now.year, now.month),
  };
  final end = switch (scope) {
    _ScheduleScope.today => start.add(const Duration(days: 1)),
    _ScheduleScope.week => start.add(const Duration(days: 7)),
    _ScheduleScope.month => DateTime(now.year, now.month + 1),
  };
  return entries.where((entry) {
    return !entry.when.isBefore(start) && entry.when.isBefore(end);
  }).toList();
}

/// Groups sorted entries by calendar date.
List<_ScheduleDayEntries> _groupEntriesByDate(List<_ScheduleEntry> entries) {
  final groups = <DateTime, List<_ScheduleEntry>>{};
  for (final entry in entries) {
    final date = _dayStart(entry.when);
    groups.putIfAbsent(date, () => <_ScheduleEntry>[]).add(entry);
  }
  return groups.entries.map((entry) {
    return _ScheduleDayEntries(date: entry.key, entries: entry.value);
  }).toList();
}

/// Compares entries by date, completion, and title.
int _compareEntries(_ScheduleEntry left, _ScheduleEntry right) {
  final time = left.when.compareTo(right.when);
  if (time != 0) {
    return time;
  }
  if (left.done != right.done) {
    return left.done ? 1 : -1;
  }
  return left.title.compareTo(right.title);
}

/// Returns the display detail for one workspace task.
String _taskDetail(WorkspaceTask task) {
  final parts = <String>[
    if (task.project.trim().isNotEmpty) task.project.trim(),
    if (task.owner.trim().isNotEmpty) task.owner.trim(),
    if (task.priority.trim().isNotEmpty && task.priority != 'normal')
      task.priority.trim(),
  ];
  return parts.join(' / ');
}

/// Returns the display detail for one projection item.
String _projectionDetail(ExecutiveSummaryItem item) {
  final parts = <String>[
    if (item.project.trim().isNotEmpty) item.project.trim(),
    if (item.person.trim().isNotEmpty) item.person.trim(),
    if (item.priority.trim().isNotEmpty && item.priority != 'normal')
      item.priority.trim(),
  ];
  return parts.join(' / ');
}

/// Returns midnight for a date.
DateTime _dayStart(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

/// Returns the start of the current Sunday-based calendar week.
DateTime _weekStart(DateTime value) {
  final start = _dayStart(value);
  return start.subtract(Duration(days: start.weekday % 7));
}
