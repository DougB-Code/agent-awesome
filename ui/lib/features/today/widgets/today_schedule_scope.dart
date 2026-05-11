/// Today schedule scope model and selector widget.
part of 'today_schedule_card.dart';

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
