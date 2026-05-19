/// Provides shared Today screen card primitives.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme.dart';
import '../../../domain/executive_summary.dart';

/// TodaySectionCard renders one bordered Today dashboard panel.
class TodaySectionCard extends StatelessWidget {
  /// Creates a Today panel with an optional section link.
  const TodaySectionCard({
    super.key,
    required this.title,
    required this.child,
    this.link,
    this.onOpenLink,
    this.padding = const EdgeInsets.all(16),
  });

  /// Uppercase section title.
  final String title;

  /// Optional detail link.
  final ProjectionLink? link;

  /// Link activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Inner content padding.
  final EdgeInsetsGeometry padding;

  /// Panel child content.
  final Widget child;

  /// Builds the bordered Today panel.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeSurfaceGradient,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (link != null && link!.route.isNotEmpty)
                  TodayTextLink(
                    label: link!.label.isEmpty ? 'View all' : link!.label,
                    route: link!.route,
                    onOpenLink: onOpenLink,
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}

/// TodayTextLink renders one compact route link.
class TodayTextLink extends StatelessWidget {
  /// Creates a Today section link.
  const TodayTextLink({
    super.key,
    required this.label,
    required this.route,
    this.onOpenLink,
  });

  /// Link label.
  final String label;

  /// Route target.
  final String route;

  /// Link activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Builds the text link.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: colors.green,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onOpenLink == null ? null : () => onOpenLink!(route),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// TodayIconBadge renders a calm icon block used in Today rows and metrics.
class TodayIconBadge extends StatelessWidget {
  /// Creates an icon badge.
  const TodayIconBadge({
    super.key,
    required this.icon,
    this.severity = 'normal',
    this.size = 42,
  });

  /// Icon glyph.
  final IconData icon;

  /// Semantic severity.
  final String severity;

  /// Square badge size.
  final double size;

  /// Builds the semantic icon badge.
  @override
  Widget build(BuildContext context) {
    final foreground = todaySeverityColor(context, severity);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: foreground, size: size * 0.52),
    );
  }
}

/// todaySeverityColor maps semantic severity to the app palette.
Color todaySeverityColor(BuildContext context, String severity) {
  final colors = context.agentAwesomeColors;
  switch (severity) {
    case 'attention':
      return colors.coral;
    case 'warning':
      return context.agentAwesomeWarningAccent;
    case 'good':
      return context.agentAwesomeLowAccent;
    default:
      return colors.muted;
  }
}
