/// Renders the Today open-loop radar section.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/theme.dart';
import '../../../domain/executive_summary.dart';
import 'today_card.dart';

/// OpenLoopRadarCard shows compact category counts around a mini radar chart.
class OpenLoopRadarCard extends StatelessWidget {
  /// Creates the open-loop radar card.
  const OpenLoopRadarCard({
    super.key,
    required this.openLoops,
    this.onOpenLink,
  });

  /// Open-loop projection data.
  final OpenLoopProjection openLoops;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Builds the open-loop radar section.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final categories = openLoops.categories;
    return TodaySectionCard(
      title: 'Open Loop Radar',
      link: openLoops.link.route.isEmpty
          ? const ProjectionLink(label: 'View open loops', route: '/open-loops')
          : openLoops.link,
      onOpenLink: onOpenLink,
      child: Column(
        children: <Widget>[
          Expanded(
            child: CustomPaint(
              painter: _RadarPainter(categories, colors.green, colors.border),
              child: Center(
                child: SizedBox(
                  width: 230,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final category in categories.take(6))
                        _RadarLabel(category: category),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Snapshot of open loops across your system.',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// _RadarLabel renders one open-loop category label and count.
class _RadarLabel extends StatelessWidget {
  /// Creates a radar label.
  const _RadarLabel({required this.category});

  /// Category to label.
  final OpenLoopCategory category;

  /// Builds the category label.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SizedBox(
      width: 94,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            category.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.ink, fontSize: 11),
          ),
          Text(
            '${category.count}',
            style: TextStyle(
              color: colors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// _RadarPainter paints the open-loop category polygon.
class _RadarPainter extends CustomPainter {
  /// Creates a radar painter.
  _RadarPainter(this.categories, this.accent, this.border);

  /// Categories to plot.
  final List<OpenLoopCategory> categories;

  /// Fill and stroke accent color.
  final Color accent;

  /// Grid border color.
  final Color border;

  /// Paints the radar grid and values.
  @override
  void paint(Canvas canvas, Size size) {
    if (categories.length < 3) {
      return;
    }
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.32;
    final gridPaint = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final fillPaint = Paint()
      ..color = accent.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var ring = 1; ring <= 3; ring++) {
      canvas.drawPath(
        _radarPath(
          center,
          radius * ring / 3,
          List<double>.filled(categories.length, 1),
        ),
        gridPaint,
      );
    }
    final maxCount = categories
        .map((category) => category.count)
        .fold<int>(1, math.max)
        .toDouble();
    final values = categories
        .map((category) => (category.count / maxCount).clamp(0.08, 1.0))
        .toList();
    final path = _radarPath(center, radius, values);
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  /// Reports whether the chart must repaint.
  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.categories != categories ||
        oldDelegate.accent != accent ||
        oldDelegate.border != border;
  }
}

/// _radarPath builds one scaled radar polygon path.
Path _radarPath(Offset center, double radius, List<double> values) {
  final path = Path();
  for (var index = 0; index < values.length; index++) {
    final angle = -math.pi / 2 + index * 2 * math.pi / values.length;
    final point = Offset(
      center.dx + math.cos(angle) * radius * values[index],
      center.dy + math.sin(angle) * radius * values[index],
    );
    if (index == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  path.close();
  return path;
}
