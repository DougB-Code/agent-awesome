/// Today schedule card shell and selected-scope state.
part of 'today_schedule_card.dart';

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
