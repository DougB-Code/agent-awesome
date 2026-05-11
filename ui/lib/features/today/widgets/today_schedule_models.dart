/// Today schedule entry data models.
part of 'today_schedule_card.dart';

/// _ScheduleEntry stores one dated item shown in the schedule.
class _ScheduleEntry {
  /// Creates a schedule entry.
  const _ScheduleEntry({
    required this.id,
    required this.title,
    required this.when,
    required this.kind,
    this.detail = '',
    this.priority = '',
    this.done = false,
    this.route = '',
  });

  /// Stable entry id.
  final String id;

  /// Display title.
  final String title;

  /// Scheduled instant.
  final DateTime when;

  /// Entry kind such as scheduled, due, or follow_up.
  final String kind;

  /// Supporting metadata.
  final String detail;

  /// Priority label.
  final String priority;

  /// Whether the entry is complete.
  final bool done;

  /// Optional navigation route.
  final String route;
}

/// _ScheduleDayEntries stores one grouped schedule date.
class _ScheduleDayEntries {
  /// Creates a grouped day.
  const _ScheduleDayEntries({required this.date, required this.entries});

  /// Group date.
  final DateTime date;

  /// Entries on that date.
  final List<_ScheduleEntry> entries;
}
