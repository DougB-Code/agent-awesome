/// Today schedule labels, icons, and date formatting helpers.
part of 'today_schedule_card.dart';

/// Returns a heading for one grouped schedule date.
String _dateHeading(DateTime date, DateTime now) {
  if (_sameDay(date, now)) {
    return 'Today';
  }
  if (_sameDay(date, now.add(const Duration(days: 1)))) {
    return 'Tomorrow';
  }
  return '${_weekdayLabel(date)} ${_monthLabel(date)} ${date.day}';
}

/// Reports whether two timestamps share a calendar date.
bool _sameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

/// Formats a time label for a schedule entry.
String _timeLabel(BuildContext context, DateTime when) {
  if (when.hour == 0 && when.minute == 0) {
    return 'All day';
  }
  return TimeOfDay.fromDateTime(when).format(context);
}

/// Returns a compact display label for an entry kind.
String _kindLabel(String kind) {
  return switch (kind) {
    'scheduled' => 'Scheduled',
    'follow_up' => 'Follow-up',
    _ => 'Due',
  };
}

/// Returns an icon for an entry kind.
IconData _entryIcon(String kind) {
  return switch (kind) {
    'scheduled' => Icons.event_available_outlined,
    'follow_up' => Icons.forum_outlined,
    _ => Icons.flag_outlined,
  };
}

/// Returns a semantic severity for a schedule entry.
String _entrySeverity(_ScheduleEntry entry) {
  if (entry.done) {
    return 'normal';
  }
  return switch (entry.kind) {
    'scheduled' => 'good',
    'follow_up' => 'attention',
    _ => 'warning',
  };
}

/// Returns an icon for one scope segment.
IconData _scopeIcon(_ScheduleScope scope) {
  return switch (scope) {
    _ScheduleScope.today => Icons.today_outlined,
    _ScheduleScope.week => Icons.view_week_outlined,
    _ScheduleScope.month => Icons.calendar_month_outlined,
  };
}

/// Returns a sentence suffix for an empty schedule scope.
String _emptyScopeLabel(_ScheduleScope scope) {
  return switch (scope) {
    _ScheduleScope.today => 'today',
    _ScheduleScope.week => 'this week',
    _ScheduleScope.month => 'this month',
  };
}

/// Returns a short weekday label.
String _weekdayLabel(DateTime date) {
  return const <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ][date.weekday - 1];
}

/// Returns a short month label.
String _monthLabel(DateTime date) {
  return const <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][date.month - 1];
}
