/// Renders the Today confidence and coverage section.
library;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../domain/executive_summary.dart';
import 'risk_unblocks_card.dart';
import 'today_card.dart';

/// ConfidenceCoverageCard displays source coverage and unknown integrations.
class ConfidenceCoverageCard extends StatelessWidget {
  static const double _cardChromeHeight = 96;
  static const double _compactColumnGap = 14;
  static const double _columnBaseHeight = 42;
  static const double _lineHeight = 18;
  static const int _maxVisibleItems = 4;

  /// Creates the confidence and coverage card.
  const ConfidenceCoverageCard({
    super.key,
    required this.coverage,
    required this.quality,
    this.onOpenLink,
  });

  /// Coverage projection data.
  final CoverageProjection coverage;

  /// Projection quality data.
  final ProjectionQualitySummary quality;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Returns the card height needed for the current coverage layout.
  static double preferredHeight({
    required double width,
    required CoverageProjection coverage,
  }) {
    final columnHeights = <double>[
      _coverageColumnHeight(coverage.good),
      _coverageColumnHeight(coverage.partial),
      _coverageColumnHeight(coverage.notConnected),
    ];
    if (width < 980) {
      return _cardChromeHeight +
          columnHeights.reduce((total, height) => total + height) +
          (_compactColumnGap * (columnHeights.length - 1));
    }
    return _cardChromeHeight +
        columnHeights.reduce((highest, height) {
          return height > highest ? height : highest;
        });
  }

  /// Builds the confidence and coverage section.
  @override
  Widget build(BuildContext context) {
    return TodaySectionCard(
      title: 'Confidence & Coverage',
      child: _CoverageColumns(coverage: coverage, quality: quality),
    );
  }
}

/// RisksCoverageCard displays risk, blocker, and source coverage posture.
class RisksCoverageCard extends StatelessWidget {
  /// Creates the combined risk and coverage card.
  const RisksCoverageCard({
    super.key,
    required this.coverage,
    required this.quality,
    required this.riskUnblocks,
    this.onOpenLink,
  });

  /// Coverage projection data.
  final CoverageProjection coverage;

  /// Projection quality data.
  final ProjectionQualitySummary quality;

  /// Risk and unblock projection data.
  final RiskUnblockProjection riskUnblocks;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Returns the card height needed for the combined coverage layout.
  static double preferredHeight({
    required double width,
    required CoverageProjection coverage,
    required RiskUnblockProjection riskUnblocks,
  }) {
    final coverageHeight = ConfidenceCoverageCard.preferredHeight(
      width: width,
      coverage: coverage,
    );
    final riskHeight = riskUnblocks.chains.isEmpty ? 96.0 : 142.0;
    return coverageHeight + riskHeight + 24;
  }

  /// Builds the combined risk and coverage section.
  @override
  Widget build(BuildContext context) {
    return TodaySectionCard(
      title: 'Risks & Coverage',
      link: riskUnblocks.link.route.isEmpty
          ? const ProjectionLink(label: 'View risks', route: '/risks')
          : riskUnblocks.link,
      onOpenLink: onOpenLink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CoverageColumns(coverage: coverage, quality: quality),
          const SizedBox(height: 14),
          Divider(height: 1, color: context.agentAwesomeColors.border),
          const SizedBox(height: 14),
          RiskUnblocksContent(
            riskUnblocks: riskUnblocks,
            fillAvailableHeight: false,
          ),
        ],
      ),
    );
  }
}

/// _CoverageColumns lays out the three source confidence columns.
class _CoverageColumns extends StatelessWidget {
  /// Creates coverage columns.
  const _CoverageColumns({required this.coverage, required this.quality});

  /// Coverage projection data.
  final CoverageProjection coverage;

  /// Projection quality data.
  final ProjectionQualitySummary quality;

  /// Builds the responsive coverage column group.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;
        final columns = <Widget>[
          _CoverageColumn(
            icon: Icons.check_circle_outline,
            title: quality.label == 'Good' ? 'Good coverage' : quality.label,
            items: coverage.good,
            severity: 'good',
          ),
          _CoverageColumn(
            icon: Icons.pending_outlined,
            title: 'Partial',
            items: coverage.partial,
            severity: 'warning',
          ),
          _CoverageColumn(
            icon: Icons.error_outline,
            title: 'Not connected',
            items: coverage.notConnected,
            severity: 'attention',
          ),
        ];
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final column in columns)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: column,
                ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var index = 0; index < columns.length; index++) ...<Widget>[
              Expanded(child: columns[index]),
              if (index < columns.length - 1) const SizedBox(width: 18),
            ],
          ],
        );
      },
    );
  }
}

/// _CoverageColumn renders one coverage quality column.
class _CoverageColumn extends StatelessWidget {
  /// Creates a coverage column.
  const _CoverageColumn({
    required this.icon,
    required this.title,
    required this.items,
    required this.severity,
  });

  final IconData icon;
  final String title;
  final List<String> items;
  final String severity;

  /// Builds the coverage column.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final visible = items.isEmpty
        ? <String>['No source-backed data yet']
        : items;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TodayIconBadge(icon: icon, severity: severity, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                visible
                    .take(ConfidenceCoverageCard._maxVisibleItems)
                    .join('\n'),
                maxLines: ConfidenceCoverageCard._maxVisibleItems,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Returns the height needed by one coverage column.
double _coverageColumnHeight(List<String> items) {
  final visibleCount = items.isEmpty
      ? 1
      : items.take(ConfidenceCoverageCard._maxVisibleItems).length;
  return ConfidenceCoverageCard._columnBaseHeight +
      (visibleCount * ConfidenceCoverageCard._lineHeight);
}
