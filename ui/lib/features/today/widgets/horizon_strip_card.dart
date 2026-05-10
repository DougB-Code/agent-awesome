/// Renders the Today horizon section.
library;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../domain/executive_summary.dart';
import 'today_card.dart';

/// HorizonStripCard displays fixed near-term timeline buckets.
class HorizonStripCard extends StatelessWidget {
  static const double _bucketHeight = 96;
  static const double _bucketSpacing = 10;
  static const double _minimumBucketWidth = 108;
  static const double _sectionHorizontalPadding = 32;
  static const double _sectionChromeHeight = 72;
  static const double _minimumCardHeight = 190;

  /// Creates the horizon card.
  const HorizonStripCard({
    super.key,
    required this.timeHorizon,
    this.onOpenLink,
  });

  /// Time horizon projection data.
  final TimeHorizonProjection timeHorizon;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Returns the card height needed for the current bucket wrapping.
  static double preferredHeight({
    required double width,
    required int bucketCount,
  }) {
    if (bucketCount <= 0) {
      return _minimumCardHeight;
    }
    final contentWidth = (width - _sectionHorizontalPadding).clamp(
      0.0,
      double.infinity,
    );
    final columns = _bucketColumnCount(contentWidth, bucketCount);
    final rows = (bucketCount / columns).ceil();
    final wrapHeight = rows * _bucketHeight + (rows - 1) * _bucketSpacing;
    return _minimumCardHeight > _sectionChromeHeight + wrapHeight
        ? _minimumCardHeight
        : _sectionChromeHeight + wrapHeight;
  }

  /// Builds the horizon section.
  @override
  Widget build(BuildContext context) {
    return TodaySectionCard(
      title: 'Horizon',
      link:
          timeHorizon.link.route.isEmpty ||
              timeHorizon.link.route.startsWith('/timeline')
          ? null
          : timeHorizon.link,
      onOpenLink: onOpenLink,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final buckets = timeHorizon.buckets;
          final columns = _bucketColumnCount(
            constraints.maxWidth,
            buckets.length,
          );
          const spacing = _bucketSpacing;
          final itemWidth = columns <= 0
              ? constraints.maxWidth
              : (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: <Widget>[
              for (final bucket in buckets)
                SizedBox(
                  width: itemWidth,
                  child: _HorizonBucket(bucket: bucket, onOpenLink: onOpenLink),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// _HorizonBucket renders one fixed timeline bucket.
class _HorizonBucket extends StatelessWidget {
  /// Creates a horizon bucket.
  const _HorizonBucket({required this.bucket, this.onOpenLink});

  /// Bucket to render.
  final TimeHorizonBucket bucket;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Builds the bucket.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: bucket.link.route.isEmpty || onOpenLink == null
          ? null
          : () => onOpenLink!(bucket.link.route),
      child: Container(
        height: HorizonStripCard._bucketHeight,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bucket.id == 'today' ? colors.greenSoft : colors.surface,
          border: Border.all(
            color: bucket.id == 'today' ? colors.green : colors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.event_note_outlined, size: 15, color: colors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    bucket.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              '${bucket.count} items',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.ink, fontSize: 12),
            ),
            Text(
              bucket.summary,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// _bucketColumnCount returns a stable bucket column count for a content width.
int _bucketColumnCount(double width, int bucketCount) {
  if (bucketCount <= 0) {
    return 1;
  }
  final raw =
      ((width + HorizonStripCard._bucketSpacing) /
              (HorizonStripCard._minimumBucketWidth +
                  HorizonStripCard._bucketSpacing))
          .floor();
  if (raw < 1) {
    return 1;
  }
  return raw > bucketCount ? bucketCount : raw;
}
