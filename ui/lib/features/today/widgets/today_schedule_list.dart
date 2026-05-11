/// Today schedule grouped list, day, row, and empty-state widgets.
part of 'today_schedule_card.dart';

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
