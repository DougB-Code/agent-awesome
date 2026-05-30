/// Attention queue list, cards, tags, scores, and row actions.
part of 'attention_screen.dart';

/// _AttentionList renders the left-hand queue of attention items.
class _AttentionList extends StatelessWidget {
  /// Creates the attention item list.
  const _AttentionList({
    required this.items,
    required this.selected,
    required this.onSelected,
    required this.onOpenBacklogTask,
    required this.onComplete,
  });

  /// Filtered attention items.
  final List<ExecutiveSummaryItem> items;

  /// Currently selected item.
  final ExecutiveSummaryItem? selected;

  /// Selection callback.
  final ValueChanged<ExecutiveSummaryItem> onSelected;

  /// Backlog open callback.
  final ValueChanged<ExecutiveSummaryItem> onOpenBacklogTask;

  /// Task completion callback.
  final ValueChanged<ExecutiveSummaryItem> onComplete;

  /// Builds the list or its empty state.
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _AttentionEmptyPanel();
    }
    return Column(
      children: <Widget>[
        for (var index = 0; index < items.length; index++) ...<Widget>[
          _AttentionItemCard(
            item: items[index],
            selected: selected?.id == items[index].id,
            onTap: () => onSelected(items[index]),
            onOpenBacklogTask: () => onOpenBacklogTask(items[index]),
            onComplete: () => onComplete(items[index]),
          ),
          if (index < items.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// _AttentionEmptyPanel reports that no items match the current filters.
class _AttentionEmptyPanel extends StatelessWidget {
  /// Creates an empty attention panel.
  const _AttentionEmptyPanel();

  /// Builds the empty panel.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      height: 220,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'No attention items in this view',
        style: TextStyle(color: colors.muted),
      ),
    );
  }
}

/// _AttentionItemCard renders one explainable attention row.
class _AttentionItemCard extends StatelessWidget {
  /// Creates an attention queue card.
  const _AttentionItemCard({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onOpenBacklogTask,
    required this.onComplete,
  });

  /// Projected attention item.
  final ExecutiveSummaryItem item;

  /// Whether this item drives the details panel.
  final bool selected;

  /// Selection callback.
  final VoidCallback onTap;

  /// Backlog open callback.
  final VoidCallback onOpenBacklogTask;

  /// Completion callback.
  final VoidCallback onComplete;

  /// Builds the item card.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accent = todaySeverityColor(context, todayLaneSeverity(item.lane));
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? colors.greenSoft.withValues(alpha: 0.5)
              : colors.surface,
          gradient: selected
              ? context.agentAwesomeSelectedGradient
              : context.agentAwesomeCardGradient,
          border: Border.all(color: selected ? colors.green : colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Icon(
                              Icons.check_box_outline_blank,
                              size: 20,
                              color: colors.muted,
                            ),
                          ),
                          const SizedBox(width: 14),
                          TodayIconBadge(
                            icon: todayLaneIcon(item.lane),
                            severity: todayLaneSeverity(item.lane),
                            size: 36,
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: _AttentionItemSummary(item: item)),
                          const SizedBox(width: 12),
                          _AttentionScore(score: item.score),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: colors.border),
                      const SizedBox(height: 10),
                      _AttentionItemActions(
                        item: item,
                        onComplete: onComplete,
                        onOpenBacklogTask: onOpenBacklogTask,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// _AttentionItemSummary renders the text and metadata tags for a row.
class _AttentionItemSummary extends StatelessWidget {
  /// Creates a summary block for one attention item.
  const _AttentionItemSummary({required this.item});

  /// Projected attention item.
  final ExecutiveSummaryItem item;

  /// Builds the summary block.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final subtitle = _detailSubtitle(item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _LanePill(lane: item.lane),
        const SizedBox(height: 8),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subtitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: colors.muted)),
        ],
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: 'Suggested next action: ',
                style: TextStyle(
                  color: colors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: _primaryActionLabel(item),
                style: TextStyle(
                  color: colors.green,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final tag in _itemTags(item)) _AttentionTag(label: tag),
          ],
        ),
      ],
    );
  }
}

/// _LanePill renders a compact lane label.
class _LanePill extends StatelessWidget {
  /// Creates a lane pill.
  const _LanePill({required this.lane});

  /// Today lane id.
  final String lane;

  /// Builds the lane pill.
  @override
  Widget build(BuildContext context) {
    final severity = todayLaneSeverity(lane);
    final foreground = todaySeverityColor(context, severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        todayLaneLabel(lane),
        style: TextStyle(color: foreground, fontWeight: FontWeight.w900),
      ),
    );
  }
}

/// _AttentionTag renders one item metadata tag.
class _AttentionTag extends StatelessWidget {
  /// Creates a metadata tag.
  const _AttentionTag({required this.label});

  /// Tag text.
  final String label;

  /// Builds the tag.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.65),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.green,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// _AttentionScore renders score value and severity label.
class _AttentionScore extends StatelessWidget {
  /// Creates an attention score block.
  const _AttentionScore({required this.score});

  /// Normalized attention score.
  final double score;

  /// Builds the score block.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final percent = _scorePercent(score);
    final label = _scoreLabel(score);
    final labelColor = score >= 0.75
        ? colors.coral
        : score >= 0.45
        ? context.agentAwesomeWarningAccent
        : context.agentAwesomeLowAccent;
    return SizedBox(
      width: 92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            'Attention score',
            textAlign: TextAlign.end,
            style: TextStyle(
              color: colors.ink,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$percent',
            style: TextStyle(
              color: colors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// _AttentionItemActions renders safe row-level commands.
class _AttentionItemActions extends StatelessWidget {
  /// Creates row-level actions for an attention item.
  const _AttentionItemActions({
    required this.item,
    required this.onComplete,
    required this.onOpenBacklogTask,
  });

  /// Projected attention item.
  final ExecutiveSummaryItem item;

  /// Completion callback.
  final VoidCallback onComplete;

  /// Backlog open callback.
  final VoidCallback onOpenBacklogTask;

  /// Builds the command row.
  @override
  Widget build(BuildContext context) {
    final canComplete = _canCompleteItem(item);
    final hasTask = _taskIdForItem(item).isNotEmpty;
    return Row(
      children: <Widget>[
        if (canComplete)
          FilledButton.icon(
            onPressed: onComplete,
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Mark done'),
          ),
        if (canComplete) const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: hasTask ? onOpenBacklogTask : null,
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Open in Backlog'),
        ),
      ],
    );
  }
}
