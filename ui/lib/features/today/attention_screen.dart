/// Renders the focused Today attention queue with explanation-first details.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/date_formatting.dart';
import '../../domain/executive_summary.dart';
import '../../domain/models.dart';
import 'widgets/executive_summary_explanation_drawer.dart';
import 'widgets/today_card.dart';
import 'widgets/today_lanes.dart';

/// TodayAttentionScreen explains why projected tasks need attention now.
class TodayAttentionScreen extends StatefulWidget {
  /// Creates a Today-owned attention detail surface.
  const TodayAttentionScreen({
    super.key,
    required this.controller,
    this.route = '/attention',
    this.onOpenToday,
    this.onOpenBacklogTask,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Reserved Today projection route that scoped this screen.
  final String route;

  /// Returns to the main Today dashboard.
  final VoidCallback? onOpenToday;

  /// Opens the backing task in the Backlog inspector.
  final ValueChanged<String>? onOpenBacklogTask;

  @override
  State<TodayAttentionScreen> createState() => _TodayAttentionScreenState();
}

/// _TodayAttentionScreenState stores local filters for the attention surface.
class _TodayAttentionScreenState extends State<TodayAttentionScreen> {
  _AttentionFilter _filter = _AttentionFilter.all;
  String _selectedItemId = '';

  /// Seeds local selection from the initial route.
  @override
  void initState() {
    super.initState();
    _selectedItemId = _attentionScopeForRoute(widget.route).itemId;
  }

  /// Keeps local selection aligned when the shell opens a new attention route.
  @override
  void didUpdateWidget(covariant TodayAttentionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route == widget.route) {
      return;
    }
    final scope = _attentionScopeForRoute(widget.route);
    setState(() {
      _filter = _AttentionFilter.all;
      _selectedItemId = scope.itemId;
    });
  }

  /// Builds the attention queue and details panel.
  @override
  Widget build(BuildContext context) {
    final projection = widget.controller.todayState.projection;
    final scope = _attentionScopeForRoute(widget.route);
    final scopedItems = _itemsForScope(projection.attention.items, scope);
    final filteredItems = _itemsForFilter(scopedItems, _filter);
    final selected = _selectedItem(filteredItems, scopedItems, _selectedItemId);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _AttentionHeader(
            title: _titleForScope(scope, scopedItems.length),
            subtitle: _subtitleForScope(scope),
            busy: widget.controller.todayState.busy,
            updatedAt: projection.generatedAt,
            onBack: widget.onOpenToday,
            onRefresh: () => unawaited(widget.controller.refreshTodayFromUi()),
            onExplain: selected == null
                ? null
                : () => unawaited(_showExplanation(selected)),
          ),
          const SizedBox(height: 18),
          _AttentionFilterBar(
            items: scopedItems,
            selected: _filter,
            onSelected: (filter) {
              setState(() {
                _filter = filter;
              });
            },
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1080;
              final list = _AttentionList(
                items: filteredItems,
                selected: selected,
                onSelected: (item) {
                  setState(() {
                    _selectedItemId = item.id;
                  });
                },
                onOpenBacklogTask: _openBacklogTask,
                onComplete: _completeItem,
              );
              final details = _AttentionDetailsPanel(
                item: selected,
                task: selected == null ? null : _workspaceTaskForItem(selected),
                onOpenBacklogTask: selected == null
                    ? null
                    : () => _openBacklogTask(selected),
                onComplete: selected == null
                    ? null
                    : () => _completeItem(selected),
              );
              if (!wide) {
                return Column(
                  children: <Widget>[list, const SizedBox(height: 14), details],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 7, child: list),
                  const SizedBox(width: 18),
                  SizedBox(width: 390, child: details),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Opens the existing item explanation drawer for one attention item.
  Future<void> _showExplanation(ExecutiveSummaryItem item) async {
    await widget.controller.explainTodayItem(item.id);
    if (!mounted) {
      return;
    }
    final explanation = widget.controller.todayState.explanation;
    if (explanation.itemId != item.id && explanation.reason.isEmpty) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.agentAwesomeColors.surface,
      builder: (context) {
        return ExecutiveSummaryExplanationDrawer(explanation: explanation);
      },
    );
    widget.controller.clearTodayExplanation();
  }

  /// Opens the backing task in the Backlog inspector when one is linked.
  void _openBacklogTask(ExecutiveSummaryItem item) {
    final taskId = _taskIdForItem(item);
    if (taskId.isEmpty) {
      return;
    }
    widget.onOpenBacklogTask?.call(taskId);
  }

  /// Completes the linked task through the existing task controller API.
  void _completeItem(ExecutiveSummaryItem item) {
    final taskId = _taskIdForItem(item);
    if (taskId.isEmpty) {
      return;
    }
    unawaited(widget.controller.completeTaskFromUi(taskId));
  }

  /// Returns the workspace task linked to an attention item, if loaded.
  WorkspaceTask? _workspaceTaskForItem(ExecutiveSummaryItem item) {
    final taskId = _taskIdForItem(item);
    if (taskId.isEmpty) {
      return null;
    }
    for (final task in widget.controller.workspace.tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }
}

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
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: colors.softShadow,
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
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

/// _AttentionDetailsPanel renders the selected item's explanation details.
class _AttentionDetailsPanel extends StatelessWidget {
  /// Creates the right-side attention details panel.
  const _AttentionDetailsPanel({
    required this.item,
    required this.task,
    required this.onOpenBacklogTask,
    required this.onComplete,
  });

  /// Selected attention item.
  final ExecutiveSummaryItem? item;

  /// Backing workspace task, when loaded.
  final WorkspaceTask? task;

  /// Backlog open callback.
  final VoidCallback? onOpenBacklogTask;

  /// Completion callback.
  final VoidCallback? onComplete;

  /// Builds the details panel.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final selected = item;
    if (selected == null) {
      return Container(
        height: 320,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'No attention item selected',
          style: TextStyle(color: colors.muted),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'ATTENTION DETAILS',
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Icon(Icons.expand_less, color: colors.muted, size: 20),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _LanePill(lane: selected.lane),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      selected.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (_taskIdForItem(selected).isNotEmpty)
                      Text(
                        _taskIdForItem(selected),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _DetailBlock(
            title: 'Required attention',
            child: Text(
              _requiredAttention(selected),
              style: TextStyle(color: colors.ink, fontWeight: FontWeight.w700),
            ),
          ),
          _DetailBlock(
            title: 'Why this surfaced',
            child: Text(
              _reasonText(selected),
              style: TextStyle(color: colors.ink, height: 1.35),
            ),
          ),
          _DetailBlock(
            title: 'Suggested next action',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.greenSoft.withValues(alpha: 0.72),
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: <Widget>[
                  TodayIconBadge(
                    icon: todayLaneIcon(selected.lane),
                    severity: todayLaneSeverity(selected.lane),
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _primaryActionLabel(selected),
                          style: TextStyle(
                            color: colors.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (selected.estimateMinutes > 0)
                          Text(
                            _formatMinutes(selected.estimateMinutes),
                            style: TextStyle(color: colors.muted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _SourceBlock(item: selected),
          _ConfidenceBlock(confidence: selected.confidence),
          _TaskDetailsBlock(item: selected, task: task),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: <Widget>[
              if (_canCompleteItem(selected))
                FilledButton.icon(
                  onPressed: onComplete,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Mark done'),
                ),
              OutlinedButton.icon(
                onPressed: onOpenBacklogTask,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open in Backlog'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// _DetailBlock renders a titled block in the details panel.
class _DetailBlock extends StatelessWidget {
  /// Creates one detail block.
  const _DetailBlock({required this.title, required this.child});

  /// Block title.
  final String title;

  /// Block content.
  final Widget child;

  /// Builds the detail block.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(color: colors.ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// _SourceBlock renders source handles and derived attention factors.
class _SourceBlock extends StatelessWidget {
  /// Creates the source section.
  const _SourceBlock({required this.item});

  /// Selected attention item.
  final ExecutiveSummaryItem item;

  /// Builds source bullets.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final bullets = _sourceBullets(item);
    if (bullets.isEmpty) {
      return const SizedBox.shrink();
    }
    return _DetailBlock(
      title: 'Sources',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final bullet in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('• ', style: TextStyle(color: colors.ink)),
                  Expanded(
                    child: Text(
                      bullet,
                      style: TextStyle(color: colors.ink, height: 1.28),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// _ConfidenceBlock renders projection confidence as a compact meter.
class _ConfidenceBlock extends StatelessWidget {
  /// Creates a confidence meter block.
  const _ConfidenceBlock({required this.confidence});

  /// Normalized confidence value.
  final double confidence;

  /// Builds the confidence block.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final percent = _confidencePercent(confidence);
    final normalized = confidence <= 0 ? 0.01 : confidence.clamp(0, 1);
    return _DetailBlock(
      title: 'Confidence',
      child: Row(
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: normalized.toDouble(),
                minHeight: 6,
                color: colors.green,
                backgroundColor: colors.panel,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$percent%',
            style: TextStyle(color: colors.green, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

/// _TaskDetailsBlock renders task metadata available to explain the item.
class _TaskDetailsBlock extends StatelessWidget {
  /// Creates a task details block.
  const _TaskDetailsBlock({required this.item, required this.task});

  /// Selected attention item.
  final ExecutiveSummaryItem item;

  /// Backing workspace task, when loaded.
  final WorkspaceTask? task;

  /// Builds compact metadata rows.
  @override
  Widget build(BuildContext context) {
    final topics = task?.topics ?? const <String>[];
    return _DetailBlock(
      title: 'Task details',
      child: Column(
        children: <Widget>[
          _DetailRow(label: 'Status', value: _statusText(item, task)),
          _DetailRow(label: 'Priority', value: _priorityText(item, task)),
          _DetailRow(
            label: 'Due',
            value: formatOptionalLocalDate(
              item.dueAt ?? task?.dueAt,
              fallback: '-',
            ),
          ),
          _DetailRow(
            label: 'Scheduled',
            value: formatOptionalLocalDate(
              item.scheduledAt ?? task?.scheduledAt,
              fallback: '-',
            ),
          ),
          _DetailRow(
            label: 'Project',
            value: _fallbackText(item.project, task?.project ?? '-'),
          ),
          _DetailRow(
            label: 'Topics',
            value: topics.isEmpty ? '-' : topics.join(', '),
          ),
        ],
      ),
    );
  }
}

/// _DetailRow renders one label-value metadata row.
class _DetailRow extends StatelessWidget {
  /// Creates a metadata row.
  const _DetailRow({required this.label, required this.value});

  /// Row label.
  final String label;

  /// Row value.
  final String value;

  /// Builds the metadata row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                color: colors.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: colors.ink, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// _AttentionScope stores route-derived filtering context.
class _AttentionScope {
  /// Creates an attention scope from a reserved route.
  const _AttentionScope({
    required this.metric,
    required this.lanes,
    required this.itemId,
  });

  /// Metric name that opened the screen.
  final String metric;

  /// Attention lanes included in the scope.
  final Set<String> lanes;

  /// Optional selected item or task id from the route.
  final String itemId;
}

/// _AttentionFilter defines local attention view categories.
enum _AttentionFilter {
  /// Shows every item in the route scope.
  all,

  /// Shows concrete execution and protection work.
  execute,

  /// Shows items missing enough detail to act cleanly.
  clarify,

  /// Shows items lacking due, scheduled, or follow-up dates.
  schedule,

  /// Shows decision or review items.
  review,
}

/// _attentionScopeForRoute parses a reserved Today attention route.
_AttentionScope _attentionScopeForRoute(String route) {
  final uri = _safeUri(route);
  final metric = uri.queryParameters['metric'] ?? '';
  final lane = uri.queryParameters['lane'] ?? '';
  final itemId = uri.queryParameters['item'] ?? '';
  if (metric == 'actions') {
    return _AttentionScope(
      metric: metric,
      lanes: const <String>{'protect', 'do'},
      itemId: itemId,
    );
  }
  if (metric == 'decisions') {
    return _AttentionScope(
      metric: metric,
      lanes: const <String>{'decide'},
      itemId: itemId,
    );
  }
  if (metric == 'relationships') {
    return _AttentionScope(
      metric: metric,
      lanes: const <String>{'follow_up'},
      itemId: itemId,
    );
  }
  if (lane == 'do') {
    return _AttentionScope(
      metric: 'actions',
      lanes: const <String>{'protect', 'do'},
      itemId: itemId,
    );
  }
  if (lane.isNotEmpty) {
    return _AttentionScope(metric: lane, lanes: <String>{lane}, itemId: itemId);
  }
  return _AttentionScope(
    metric: metric,
    lanes: const <String>{},
    itemId: itemId,
  );
}

/// _safeUri parses route strings without throwing during UI builds.
Uri _safeUri(String route) {
  try {
    return Uri.parse(route.isEmpty ? '/attention' : route);
  } catch (_) {
    return Uri.parse('/attention');
  }
}

/// _itemsForScope filters attention items by route scope.
List<ExecutiveSummaryItem> _itemsForScope(
  List<ExecutiveSummaryItem> items,
  _AttentionScope scope,
) {
  if (scope.lanes.isEmpty) {
    return items;
  }
  return items.where((item) => scope.lanes.contains(item.lane)).toList();
}

/// _itemsForFilter filters attention items by local category.
List<ExecutiveSummaryItem> _itemsForFilter(
  List<ExecutiveSummaryItem> items,
  _AttentionFilter filter,
) {
  switch (filter) {
    case _AttentionFilter.all:
      return items;
    case _AttentionFilter.execute:
      return items.where((item) {
        return item.lane == 'do' || item.lane == 'protect';
      }).toList();
    case _AttentionFilter.clarify:
      return items.where(_itemNeedsClarification).toList();
    case _AttentionFilter.schedule:
      return items.where(_itemNeedsSchedule).toList();
    case _AttentionFilter.review:
      return items.where((item) {
        return item.lane == 'decide' || item.lane == 'monitor';
      }).toList();
  }
}

/// _selectedItem resolves the details selection from filtered items and route.
ExecutiveSummaryItem? _selectedItem(
  List<ExecutiveSummaryItem> filteredItems,
  List<ExecutiveSummaryItem> scopedItems,
  String selectedItemId,
) {
  for (final item in filteredItems) {
    if (_itemMatchesSelection(item, selectedItemId)) {
      return item;
    }
  }
  for (final item in scopedItems) {
    if (_itemMatchesSelection(item, selectedItemId)) {
      return item;
    }
  }
  return filteredItems.isEmpty ? null : filteredItems.first;
}

/// _itemMatchesSelection compares item id, task id, and projection link ids.
bool _itemMatchesSelection(ExecutiveSummaryItem item, String selectedItemId) {
  if (selectedItemId.isEmpty) {
    return false;
  }
  if (item.id == selectedItemId || item.taskId == selectedItemId) {
    return true;
  }
  return item.links.any((link) {
    final routeItem = _safeUri(link.route).queryParameters['item'] ?? '';
    return routeItem == selectedItemId;
  });
}

/// _itemNeedsClarification identifies items with missing action context.
bool _itemNeedsClarification(ExecutiveSummaryItem item) {
  return item.project.isEmpty ||
      item.reason.toLowerCase().contains('missing') ||
      item.subtitle.toLowerCase().contains('missing');
}

/// _itemNeedsSchedule identifies unscheduled items.
bool _itemNeedsSchedule(ExecutiveSummaryItem item) {
  return item.dueAt == null &&
      item.scheduledAt == null &&
      item.followUpAt == null;
}

/// _titleForScope creates the page title for the current route scope.
String _titleForScope(_AttentionScope scope, int count) {
  switch (scope.metric) {
    case 'actions':
      return '$count ${_plural(count, 'item')} ready to execute';
    case 'decisions':
    case 'decide':
      return '$count ${_plural(count, 'decision')} require your input';
    case 'relationships':
    case 'follow_up':
      return '$count ${_plural(count, 'follow-up')} need your care';
    default:
      return '$count attention ${_plural(count, 'item')} need your attention';
  }
}

/// _subtitleForScope returns supporting copy for the current route scope.
String _subtitleForScope(_AttentionScope scope) {
  switch (scope.metric) {
    case 'actions':
      return 'These tasks are ready for concrete execution today or soon.';
    case 'decisions':
    case 'decide':
      return 'These tasks need a choice before work can move cleanly.';
    case 'relationships':
    case 'follow_up':
      return 'These loops involve a person, promise, reply, or check-in.';
    default:
      return 'These items are ranked by what most needs your attention now.';
  }
}

/// _plural returns a singular or plural noun.
String _plural(int count, String noun) {
  return count == 1 ? noun : '${noun}s';
}

/// _filterLabel returns the display label for a local filter.
String _filterLabel(_AttentionFilter filter) {
  switch (filter) {
    case _AttentionFilter.all:
      return 'All';
    case _AttentionFilter.execute:
      return 'Execute now';
    case _AttentionFilter.clarify:
      return 'Clarify';
    case _AttentionFilter.schedule:
      return 'Schedule';
    case _AttentionFilter.review:
      return 'Review';
  }
}

/// _filterSubtitle returns the supporting label for a local filter.
String _filterSubtitle(_AttentionFilter filter) {
  switch (filter) {
    case _AttentionFilter.all:
      return 'Everything';
    case _AttentionFilter.execute:
      return 'Concrete action';
    case _AttentionFilter.clarify:
      return 'Needs more info';
    case _AttentionFilter.schedule:
      return 'Plan it';
    case _AttentionFilter.review:
      return 'Needs review';
  }
}

/// _filterIcon returns the icon for a local filter.
IconData _filterIcon(_AttentionFilter filter) {
  switch (filter) {
    case _AttentionFilter.all:
      return Icons.inbox_outlined;
    case _AttentionFilter.execute:
      return Icons.task_alt;
    case _AttentionFilter.clarify:
      return Icons.edit_note;
    case _AttentionFilter.schedule:
      return Icons.calendar_today_outlined;
    case _AttentionFilter.review:
      return Icons.rate_review_outlined;
  }
}

/// _filterSeverity returns the semantic color for a local filter.
String _filterSeverity(_AttentionFilter filter) {
  switch (filter) {
    case _AttentionFilter.clarify:
    case _AttentionFilter.review:
      return 'attention';
    case _AttentionFilter.schedule:
      return 'warning';
    case _AttentionFilter.execute:
    case _AttentionFilter.all:
      return 'good';
  }
}

/// _updatedLabel formats the projection refresh timestamp.
String _updatedLabel(DateTime? timestamp) {
  if (timestamp == null) {
    return 'Updated just now';
  }
  final local = timestamp.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return 'Updated $hour:$minute';
}

/// _detailSubtitle returns the visible reason summary for an item.
String _detailSubtitle(ExecutiveSummaryItem item) {
  if (item.subtitle.trim().isNotEmpty) {
    return item.subtitle.trim();
  }
  return item.reason.trim();
}

/// _reasonText returns a non-empty item explanation.
String _reasonText(ExecutiveSummaryItem item) {
  final reason = item.reason.trim();
  if (reason.isNotEmpty) {
    return reason;
  }
  final subtitle = item.subtitle.trim();
  return subtitle.isEmpty ? 'Ranked by the Today attention policy.' : subtitle;
}

/// _primaryActionLabel returns the preferred action label for an item.
String _primaryActionLabel(ExecutiveSummaryItem item) {
  final action = item.primaryAction;
  if (action != null && action.label.trim().isNotEmpty) {
    return action.label.trim();
  }
  if (item.actions.isNotEmpty && item.actions.first.label.trim().isNotEmpty) {
    return item.actions.first.label.trim();
  }
  switch (item.lane) {
    case 'decide':
      return 'Make or defer the decision';
    case 'protect':
      return 'Protect time for this';
    case 'follow_up':
      return 'Follow up with the person';
    case 'delegate':
      return 'Delegate the next step';
    default:
      return 'Open the task';
  }
}

/// _requiredAttention summarizes what kind of attention is required.
String _requiredAttention(ExecutiveSummaryItem item) {
  switch (item.lane) {
    case 'decide':
      return 'Decide, defer, or split the work.';
    case 'protect':
      return 'Protect focus time or unblock the schedule.';
    case 'follow_up':
      return 'Reply, follow up, or close the loop.';
    case 'delegate':
      return 'Assign the next step or approve delegation.';
    case 'monitor':
      return 'Review the signal and keep it visible.';
    default:
      return 'Complete, schedule, or dismiss.';
  }
}

/// _itemTags creates compact metadata tags for one item.
List<String> _itemTags(ExecutiveSummaryItem item) {
  final tags = <String>[];
  if (item.status.trim().isNotEmpty) {
    tags.add(_titleCase(item.status));
  }
  if (_itemNeedsSchedule(item)) {
    tags.add('No date');
  }
  if (item.estimateMinutes > 0) {
    tags.add(_formatMinutes(item.estimateMinutes));
  }
  if (item.project.trim().isEmpty) {
    tags.add('No project');
  } else {
    tags.add(item.project.trim());
  }
  if (item.priority.trim().isNotEmpty && item.priority != 'normal') {
    tags.add(_titleCase(item.priority));
  }
  return tags;
}

/// _sourceBullets combines explicit source handles and attention factors.
List<String> _sourceBullets(ExecutiveSummaryItem item) {
  final bullets = <String>[
    for (final source in item.evidence)
      source.label.trim().isEmpty ? source.id.trim() : source.label.trim(),
  ]..removeWhere((value) => value.isEmpty);
  if (item.status.trim().isNotEmpty) {
    bullets.add('${_titleCase(item.status)} task');
  }
  if (item.dueAt == null) {
    bullets.add('No due date');
  }
  if (item.scheduledAt == null) {
    bullets.add('No scheduled date');
  }
  if (item.estimateMinutes > 0) {
    bullets.add(_formatMinutes(item.estimateMinutes));
  }
  if (item.project.trim().isEmpty) {
    bullets.add('No project relation');
  }
  return bullets;
}

/// _canCompleteItem reports whether a row can invoke complete_task safely.
bool _canCompleteItem(ExecutiveSummaryItem item) {
  final taskId = _taskIdForItem(item);
  if (taskId.isEmpty) {
    return false;
  }
  final action = item.primaryAction;
  if (action != null && action.tool == 'complete_task') {
    return true;
  }
  return item.lane == 'do';
}

/// _taskIdForItem returns the linked task id from item fields or action payload.
String _taskIdForItem(ExecutiveSummaryItem item) {
  if (item.taskId.trim().isNotEmpty) {
    return item.taskId.trim();
  }
  final payloadTask = item.primaryAction?.payload['task_id'];
  if (payloadTask is String && payloadTask.trim().isNotEmpty) {
    return payloadTask.trim();
  }
  for (final link in item.links) {
    final routeItem = _safeUri(link.route).queryParameters['item'] ?? '';
    if (routeItem.isNotEmpty) {
      return routeItem;
    }
  }
  return '';
}

/// _scorePercent converts a normalized score to an integer percent.
int _scorePercent(double score) {
  return (score.clamp(0, 1) * 100).round();
}

/// _scoreLabel maps a normalized score to a severity label.
String _scoreLabel(double score) {
  if (score >= 0.75) {
    return 'High';
  }
  if (score >= 0.45) {
    return 'Medium';
  }
  return 'Low';
}

/// _confidencePercent converts confidence to an integer percent.
int _confidencePercent(double confidence) {
  return (confidence.clamp(0, 1) * 100).round();
}

/// _statusText resolves item or task status.
String _statusText(ExecutiveSummaryItem item, WorkspaceTask? task) {
  return _fallbackText(item.status, task?.status ?? '-');
}

/// _priorityText resolves item or task priority.
String _priorityText(ExecutiveSummaryItem item, WorkspaceTask? task) {
  return _fallbackText(item.priority, task?.priority ?? '-');
}

/// _fallbackText returns a trimmed value or fallback.
String _fallbackText(String value, String fallback) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : _titleCase(trimmed);
}

/// _formatMinutes formats an estimate as compact effort text.
String _formatMinutes(int minutes) {
  if (minutes < 60) {
    return '$minutes min';
  }
  final hours = minutes / 60;
  return '${hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1)} hr';
}

/// _titleCase converts identifier-like text to human display text.
String _titleCase(String value) {
  final words = value
      .replaceAll('_', ' ')
      .split(' ')
      .where((word) => word.trim().isNotEmpty)
      .toList();
  return words
      .map((word) {
        final lower = word.toLowerCase();
        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
}
