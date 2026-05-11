/// Today schedule overview content.
part of 'today_schedule_card.dart';

/// _ScheduleOverview renders horizon buckets and upcoming dated work.
class _ScheduleOverview extends StatelessWidget {
  /// Creates a schedule overview.
  const _ScheduleOverview({
    required this.entries,
    required this.timeHorizon,
    required this.now,
    required this.onOpenLink,
  });

  /// All dated schedule entries.
  final List<_ScheduleEntry> entries;

  /// Horizon bucket summary from the Today projection.
  final TimeHorizonProjection timeHorizon;

  /// Current clock used for upcoming-entry filtering.
  final DateTime now;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Builds the overview list.
  @override
  Widget build(BuildContext context) {
    final upcoming = entries
        .where((entry) => !entry.when.isBefore(_dayStart(now)))
        .take(4)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: <Widget>[
        HorizonBucketStrip(timeHorizon: timeHorizon, onOpenLink: onOpenLink),
        if (upcoming.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          for (final entry in upcoming)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ScheduleEntryRow(entry: entry, onOpenLink: onOpenLink),
            ),
        ],
      ],
    );
  }
}
