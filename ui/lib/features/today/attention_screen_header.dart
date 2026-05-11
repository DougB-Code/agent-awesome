/// Header and filter controls for the Today attention screen.
part of 'attention_screen.dart';

/// _AttentionHeader renders the breadcrumb, title, and refresh controls.
class _AttentionHeader extends StatelessWidget {
  /// Creates the top header for the attention route.
  const _AttentionHeader({
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.updatedAt,
    required this.onBack,
    required this.onRefresh,
    required this.onExplain,
  });

  /// Page headline.
  final String title;

  /// Page subheading.
  final String subtitle;

  /// Whether the Today projection is refreshing.
  final bool busy;

  /// Projection generation timestamp.
  final DateTime? updatedAt;

  /// Callback for returning to Today.
  final VoidCallback? onBack;

  /// Refresh callback.
  final VoidCallback onRefresh;

  /// Explanation callback for the selected row.
  final VoidCallback? onExplain;

  /// Builds the header area.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.muted,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onBack,
                    child: const Text('Today'),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: colors.muted),
                  Text(
                    'Attention',
                    style: TextStyle(
                      color: colors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(title, style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: colors.muted)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                _updatedLabel(updatedAt),
                style: TextStyle(
                  color: colors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            Tooltip(
              message: 'Refresh Attention',
              child: IconButton(
                onPressed: busy ? null : onRefresh,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onExplain,
              icon: const Icon(Icons.help_outline, size: 17),
              label: const Text('Why these?'),
            ),
          ],
        ),
      ],
    );
  }
}

/// _AttentionFilterBar renders category chips and their item counts.
class _AttentionFilterBar extends StatelessWidget {
  /// Creates a horizontal attention filter bar.
  const _AttentionFilterBar({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  /// Items visible in the current route scope.
  final List<ExecutiveSummaryItem> items;

  /// Currently selected filter.
  final _AttentionFilter selected;

  /// Filter selection callback.
  final ValueChanged<_AttentionFilter> onSelected;

  /// Builds responsive category chips.
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        for (final filter in _AttentionFilter.values)
          _AttentionFilterChip(
            filter: filter,
            count: _itemsForFilter(items, filter).length,
            selected: selected == filter,
            onTap: () => onSelected(filter),
          ),
      ],
    );
  }
}

/// _AttentionFilterChip renders one attention category selector.
class _AttentionFilterChip extends StatelessWidget {
  /// Creates one category chip.
  const _AttentionFilterChip({
    required this.filter,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  /// Filter category.
  final _AttentionFilter filter;

  /// Number of matching items.
  final int count;

  /// Whether this chip is active.
  final bool selected;

  /// Tap callback.
  final VoidCallback onTap;

  /// Builds the chip as a stable-width card control.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final foreground = selected ? colors.green : colors.ink;
    final border = selected ? colors.green : colors.border;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 218,
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? colors.greenSoft : colors.surface,
          gradient: selected
              ? context.agentAwesomeSelectedGradient
              : context.agentAwesomeCardGradient,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            TodayIconBadge(
              icon: _filterIcon(filter),
              severity: _filterSeverity(filter),
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _filterLabel(filter),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '$count',
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _filterSubtitle(filter),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
