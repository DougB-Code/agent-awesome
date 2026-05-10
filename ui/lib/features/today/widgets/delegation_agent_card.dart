/// Renders the Today delegation and agent section.
library;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../domain/executive_summary.dart';
import 'today_card.dart';

/// DelegationAgentCard displays agent readiness buckets.
class DelegationAgentCard extends StatelessWidget {
  /// Creates the delegation and agent card.
  const DelegationAgentCard({
    super.key,
    required this.delegation,
    this.onOpenLink,
  });

  /// Delegation projection data.
  final DelegationProjection delegation;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Builds the delegation card.
  @override
  Widget build(BuildContext context) {
    final buckets = delegation.buckets
        .where(
          (bucket) => bucket.id != 'needs_context' && bucket.id != 'failed',
        )
        .toList();
    return TodaySectionCard(
      title: 'Delegation & Agent',
      link: delegation.link.route.isEmpty
          ? const ProjectionLink(label: 'View all', route: '/delegation')
          : delegation.link,
      onOpenLink: onOpenLink,
      padding: EdgeInsets.zero,
      child: buckets.isEmpty
          ? const _DelegationEmptyState()
          : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: buckets.length,
              separatorBuilder: (context, _) {
                return Divider(
                  height: 1,
                  color: context.agentAwesomeColors.border,
                );
              },
              itemBuilder: (context, index) {
                return _DelegationBucketRow(
                  bucket: buckets[index],
                  onOpenLink: onOpenLink,
                );
              },
            ),
    );
  }
}

/// _DelegationEmptyState shows a calm empty message for delegation rows.
class _DelegationEmptyState extends StatelessWidget {
  /// Creates a delegation empty state.
  const _DelegationEmptyState();

  /// Builds the empty state.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No delegation buckets yet',
        style: TextStyle(color: context.agentAwesomeColors.muted),
      ),
    );
  }
}

/// _DelegationBucketRow renders one agent readiness bucket.
class _DelegationBucketRow extends StatelessWidget {
  /// Creates a delegation bucket row.
  const _DelegationBucketRow({required this.bucket, this.onOpenLink});

  final DelegationBucket bucket;
  final ValueChanged<String>? onOpenLink;

  /// Builds the row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final sample = bucket.items
        .take(3)
        .map((item) => item.title)
        .where((title) => title.isNotEmpty)
        .join('\n');
    return InkWell(
      onTap: bucket.link.route.isEmpty || onOpenLink == null
          ? null
          : () => onOpenLink!(bucket.link.route),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TodayIconBadge(
              icon: _bucketIcon(bucket.id),
              severity: bucket.severity,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    bucket.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sample.isEmpty ? _bucketFallback(bucket.id) : sample,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _CountPill(count: bucket.count, severity: bucket.severity),
          ],
        ),
      ),
    );
  }
}

/// _CountPill renders the bucket count.
class _CountPill extends StatelessWidget {
  /// Creates a count pill.
  const _CountPill({required this.count, required this.severity});

  final int count;
  final String severity;

  /// Builds the count pill.
  @override
  Widget build(BuildContext context) {
    final color = todaySeverityColor(context, severity);
    return Container(
      constraints: const BoxConstraints(minWidth: 34),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// _bucketIcon maps delegation bucket ids to familiar Material icons.
IconData _bucketIcon(String id) {
  switch (id) {
    case 'can_do_now':
      return Icons.smart_toy_outlined;
    case 'needs_approval':
      return Icons.balance_outlined;
    case 'running':
      return Icons.sync;
    case 'done':
      return Icons.check_box_outlined;
    default:
      return Icons.info_outline;
  }
}

/// _bucketFallback provides empty sample text for a delegation bucket.
String _bucketFallback(String id) {
  switch (id) {
    case 'can_do_now':
      return 'Ready to act';
    case 'needs_approval':
      return 'Needs your approval';
    case 'running':
      return 'In progress or waiting';
    case 'done':
      return 'Completed recently';
    default:
      return 'Needs more context';
  }
}
