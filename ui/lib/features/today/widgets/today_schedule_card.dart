/// Renders a dated schedule view for the Today dashboard.
library;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../domain/executive_summary.dart';
import '../../../domain/models.dart';
import 'today_card.dart';

/// TodayScheduleCard displays dated work across today, week, and month scopes.
class TodayScheduleCard extends StatefulWidget {
  /// Creates the schedule card.
  const TodayScheduleCard({
    super.key,
    required this.workspace,
    required this.projection,
    this.onOpenLink,
  });

  /// Workspace tasks used as the primary source of scheduled work.
  final ProjectWorkspace workspace;

  /// Today projection used to supplement dated attention items.
  final ExecutiveSummaryProjection projection;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Returns the card height for the current viewport.
  static double preferredHeight({required double width}) {
    return width < 760 ? 430 : 360;
  }

  /// Creates mutable state for the selected schedule scope.
  @override
  State<TodayScheduleCard> createState() => _TodayScheduleCardState();
}

/// _TodayScheduleCardState stores the selected schedule scope.
class _TodayScheduleCardState extends State<TodayScheduleCard> {
  _ScheduleScope _scope = _ScheduleScope.today;

  /// Builds the schedule card.
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final entries = _scheduledEntries(
      workspace: widget.workspace,
      projection: widget.projection,
    );
    final visible = _entriesForScope(entries: entries, scope: _scope, now: now);
    return TodaySectionCard(
      title: 'Schedule',
      link: const ProjectionLink(label: 'Open backlog', route: '/backlog'),
      onOpenLink: widget.onOpenLink,
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          _ScheduleScopeSelector(scope: _scope, onChanged: _selectScope),
          Divider(height: 1, color: context.agentAwesomeColors.border),
          Expanded(
            child: visible.isEmpty
                ? _ScheduleEmptyState(scope: _scope)
                : _ScheduleEntryList(
                    entries: visible,
                    now: now,
                    onOpenLink: widget.onOpenLink,
                  ),
          ),
        ],
      ),
    );
  }

  /// Selects the visible schedule scope.
  void _selectScope(_ScheduleScope scope) {
    setState(() => _scope = scope);
  }
}

/// _ScheduleScope names the supported schedule ranges.
enum _ScheduleScope {
  /// Shows only items dated today.
  today('Today'),

  /// Shows the current calendar week.
  week('Week'),

  /// Shows the current calendar month.
  month('Month');

  /// Creates a scope with a compact display label.
  const _ScheduleScope(this.label);

  /// Display label.
  final String label;
}

/// _ScheduleScopeSelector renders the Today/Week/Month segmented control.
class _ScheduleScopeSelector extends StatelessWidget {
  /// Creates a scope selector.
  const _ScheduleScopeSelector({required this.scope, required this.onChanged});

  /// Currently selected scope.
  final _ScheduleScope scope;

  /// Selection callback.
  final ValueChanged<_ScheduleScope> onChanged;

  /// Builds the segmented scope control.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<_ScheduleScope>(
          segments: <ButtonSegment<_ScheduleScope>>[
            for (final scope in _ScheduleScope.values)
              ButtonSegment<_ScheduleScope>(
                value: scope,
                label: Text(scope.label),
                icon: Icon(_scopeIcon(scope), size: 16),
              ),
          ],
          selected: <_ScheduleScope>{scope},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.single),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

/// _ScheduleEntryList renders dated entries grouped by day.
class _ScheduleEntryList extends StatelessWidget {
  /// Creates a grouped schedule list.
  const _ScheduleEntryList({
    required this.entries,
    required this.now,
    required this.onOpenLink,
  });

  /// Visible schedule entries.
  final List<_ScheduleEntry> entries;

  /// Current clock used for relative labels.
  final DateTime now;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Builds the grouped schedule list.
  @override
  Widget build(BuildContext context) {
    final groups = _groupEntriesByDate(entries);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: groups.length,
      separatorBuilder: (context, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final group = groups[index];
        return _ScheduleDayGroup(
          date: group.date,
          entries: group.entries,
          now: now,
          onOpenLink: onOpenLink,
        );
      },
    );
  }
}

/// _ScheduleDayGroup renders one date heading and its entries.
class _ScheduleDayGroup extends StatelessWidget {
  /// Creates a day group.
  const _ScheduleDayGroup({
    required this.date,
    required this.entries,
    required this.now,
    required this.onOpenLink,
  });

  /// Calendar date represented by this group.
  final DateTime date;

  /// Entries within the date.
  final List<_ScheduleEntry> entries;

  /// Current clock used for labels.
  final DateTime now;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Builds the date group.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _dateHeading(date, now),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ScheduleEntryRow(entry: entry, onOpenLink: onOpenLink),
          ),
      ],
    );
  }
}

/// _ScheduleEntryRow renders one scheduled task or attention item.
class _ScheduleEntryRow extends StatelessWidget {
  /// Creates a schedule entry row.
  const _ScheduleEntryRow({required this.entry, required this.onOpenLink});

  /// Row entry.
  final _ScheduleEntry entry;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Builds the entry row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: entry.route.isEmpty || onOpenLink == null
          ? null
          : () => onOpenLink!(entry.route),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 58,
              child: Text(
                _timeLabel(context, entry.when),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            TodayIconBadge(
              icon: _entryIcon(entry.kind),
              severity: _entrySeverity(entry),
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (entry.detail.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      entry.detail,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _kindLabel(entry.kind),
              style: TextStyle(color: colors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// _ScheduleEmptyState renders an empty schedule message.
class _ScheduleEmptyState extends StatelessWidget {
  /// Creates an empty state.
  const _ScheduleEmptyState({required this.scope});

  /// Empty scope.
  final _ScheduleScope scope;

  /// Builds the empty state.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No scheduled items ${_emptyScopeLabel(scope)}',
        style: TextStyle(color: context.agentAwesomeColors.muted),
      ),
    );
  }
}

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
