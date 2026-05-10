/// Renders the Today attention section.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../domain/executive_summary.dart';
import 'today_card.dart';
import 'today_lanes.dart';

/// TodaysAttentionCard displays lane-ranked items and explanation links.
class TodaysAttentionCard extends StatelessWidget {
  /// Creates the attention card.
  const TodaysAttentionCard({
    super.key,
    required this.attention,
    this.onExplain,
    this.onOpenLink,
  });

  /// Attention projection data.
  final AttentionProjection attention;

  /// Explanation callback.
  final Future<void> Function(ExecutiveSummaryItem item)? onExplain;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Builds the attention section.
  @override
  Widget build(BuildContext context) {
    final items = attention.items;
    final counts = _AttentionLaneCounts.fromItems(items);
    return TodaySectionCard(
      title: "Today's Attention",
      link: attention.link.route.isEmpty
          ? const ProjectionLink(label: 'View all', route: '/attention')
          : attention.link,
      onOpenLink: onOpenLink,
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          _AttentionSummaryStrip(counts: counts, onOpenLink: onOpenLink),
          Divider(height: 1, color: context.agentAwesomeColors.border),
          Expanded(
            child: items.isEmpty
                ? const _AttentionEmptyState()
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    separatorBuilder: (context, _) {
                      return Divider(
                        height: 1,
                        color: context.agentAwesomeColors.border,
                      );
                    },
                    itemBuilder: (context, index) {
                      return _AttentionRow(
                        item: items[index],
                        onExplain: onExplain,
                        onOpenLink: onOpenLink,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// _AttentionLaneCounts stores dashboard-level attention counts by action type.
class _AttentionLaneCounts {
  /// Creates lane counts for the attention summary.
  const _AttentionLaneCounts({
    required this.decide,
    required this.execute,
    required this.followUps,
  });

  /// Builds counts from the current attention items.
  factory _AttentionLaneCounts.fromItems(List<ExecutiveSummaryItem> items) {
    var decide = 0;
    var execute = 0;
    var followUps = 0;
    for (final item in items) {
      switch (item.lane) {
        case 'decide':
        case 'monitor':
          decide++;
          break;
        case 'do':
        case 'protect':
          execute++;
          break;
        case 'follow_up':
          followUps++;
          break;
      }
    }
    return _AttentionLaneCounts(
      decide: decide,
      execute: execute,
      followUps: followUps,
    );
  }

  /// Number of decisions or monitoring calls needing user judgment.
  final int decide;

  /// Number of actions ready to execute.
  final int execute;

  /// Number of relationship or promise follow-ups.
  final int followUps;
}

/// _AttentionSummaryStrip renders compact route targets inside attention.
class _AttentionSummaryStrip extends StatelessWidget {
  /// Creates a lane count strip for attention.
  const _AttentionSummaryStrip({
    required this.counts,
    required this.onOpenLink,
  });

  final _AttentionLaneCounts counts;
  final ValueChanged<String>? onOpenLink;

  /// Builds the count strip.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Row(
        children: <Widget>[
          _AttentionSummaryCell(
            label: 'Decide',
            count: counts.decide,
            icon: Icons.balance_outlined,
            severity: 'attention',
            route: '/attention?metric=decide',
            onOpenLink: onOpenLink,
          ),
          _AttentionSummaryCell(
            label: 'Execute',
            count: counts.execute,
            icon: Icons.check_box_outlined,
            severity: 'good',
            route: '/attention?metric=actions',
            onOpenLink: onOpenLink,
          ),
          _AttentionSummaryCell(
            label: 'Follow-ups',
            count: counts.followUps,
            icon: Icons.forum_outlined,
            severity: 'attention',
            route: '/attention?metric=relationships',
            onOpenLink: onOpenLink,
          ),
        ],
      ),
    );
  }
}

/// _AttentionSummaryCell renders one compact attention count target.
class _AttentionSummaryCell extends StatelessWidget {
  /// Creates one summary cell.
  const _AttentionSummaryCell({
    required this.label,
    required this.count,
    required this.icon,
    required this.severity,
    required this.route,
    required this.onOpenLink,
  });

  final String label;
  final int count;
  final IconData icon;
  final String severity;
  final String route;
  final ValueChanged<String>? onOpenLink;

  /// Builds the summary cell.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accent = todaySeverityColor(context, severity);
    return Expanded(
      child: InkWell(
        onTap: onOpenLink == null ? null : () => onOpenLink!(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: TextStyle(
                  color: accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// _AttentionEmptyState shows a calm empty message for attention rows.
class _AttentionEmptyState extends StatelessWidget {
  /// Creates an attention empty state.
  const _AttentionEmptyState();

  /// Builds the empty state.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Center(
      child: Text(
        'No attention items right now',
        style: TextStyle(color: colors.muted),
      ),
    );
  }
}

/// _AttentionRow renders one attention item with an explanation affordance.
class _AttentionRow extends StatelessWidget {
  /// Creates an attention row.
  const _AttentionRow({
    required this.item,
    required this.onExplain,
    required this.onOpenLink,
  });

  final ExecutiveSummaryItem item;
  final Future<void> Function(ExecutiveSummaryItem item)? onExplain;
  final ValueChanged<String>? onOpenLink;

  /// Builds the row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final route = item.links.isEmpty ? '/attention' : item.links.first.route;
    return InkWell(
      onTap: onOpenLink == null ? null : () => onOpenLink!(route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: <Widget>[
            TodayIconBadge(
              icon: todayLaneIcon(item.lane),
              severity: todayLaneSeverity(item.lane),
              size: 28,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 86,
              child: Text(
                todayLaneLabel(item.lane),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: Text(
                item.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.ink, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: colors.green,
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onExplain == null
                  ? null
                  : () => unawaited(onExplain!(item)),
              child: const Text('Why this?', style: TextStyle(fontSize: 11)),
            ),
            Icon(Icons.chevron_right, color: colors.muted, size: 18),
          ],
        ),
      ),
    );
  }
}
