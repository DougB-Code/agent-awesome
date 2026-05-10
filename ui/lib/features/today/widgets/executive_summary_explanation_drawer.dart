/// Renders the explanation drawer for Today projection items.
library;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../domain/executive_summary.dart';

/// ExecutiveSummaryExplanationDrawer displays item sources and reasoning.
class ExecutiveSummaryExplanationDrawer extends StatelessWidget {
  /// Creates an explanation drawer.
  const ExecutiveSummaryExplanationDrawer({
    super.key,
    required this.explanation,
  });

  /// Explanation content.
  final ExecutiveSummaryItemExplanation explanation;

  /// Builds the explanation drawer content.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  explanation.title.isEmpty ? 'Why this?' : explanation.title,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            explanation.reason,
            style: TextStyle(color: colors.ink, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 18),
          Text(
            'Sources',
            style: TextStyle(
              color: colors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (explanation.evidence.isEmpty)
            Text(
              'No additional source handles were returned.',
              style: TextStyle(color: colors.muted),
            )
          else
            for (final source in explanation.evidence)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.link, size: 16, color: colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${source.kind}:${source.id} ${source.label}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          if (explanation.limits.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              explanation.limits.join('\n'),
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
