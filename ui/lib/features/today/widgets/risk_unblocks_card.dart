/// Renders the Today risk and unblock section.
library;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../domain/executive_summary.dart';
import 'today_card.dart';

/// RiskUnblocksCard displays the top blocker chain and suggested action.
class RiskUnblocksCard extends StatelessWidget {
  /// Creates the risk and unblock card.
  const RiskUnblocksCard({
    super.key,
    required this.riskUnblocks,
    this.onOpenLink,
  });

  /// Risk and unblock projection data.
  final RiskUnblockProjection riskUnblocks;

  /// Route activation callback.
  final ValueChanged<String>? onOpenLink;

  /// Builds the risk and unblock section.
  @override
  Widget build(BuildContext context) {
    return TodaySectionCard(
      title: 'Risk & Unblocks',
      link: riskUnblocks.link.route.isEmpty
          ? const ProjectionLink(label: 'View risks', route: '/risks')
          : riskUnblocks.link,
      onOpenLink: onOpenLink,
      child: RiskUnblocksContent(riskUnblocks: riskUnblocks),
    );
  }
}

/// RiskUnblocksContent renders blocker chains without owning section chrome.
class RiskUnblocksContent extends StatelessWidget {
  /// Creates reusable risk and unblock content.
  const RiskUnblocksContent({
    super.key,
    required this.riskUnblocks,
    this.fillAvailableHeight = true,
  });

  /// Risk and unblock projection data.
  final RiskUnblockProjection riskUnblocks;

  /// Whether the chain should expand to fill its parent panel.
  final bool fillAvailableHeight;

  /// Builds blocker content for standalone and combined cards.
  @override
  Widget build(BuildContext context) {
    final chain = riskUnblocks.chains.isEmpty
        ? null
        : riskUnblocks.chains.first;
    if (chain == null) {
      return SizedBox(
        height: fillAvailableHeight ? double.infinity : 76,
        child: const _RiskEmptyState(),
      );
    }
    final chainContent = _RiskChain(chain: chain);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (fillAvailableHeight)
          Expanded(child: chainContent)
        else
          chainContent,
        if (chain.suggestedAction != null) ...<Widget>[
          const SizedBox(height: 12),
          _SuggestedUnblock(action: chain.suggestedAction!),
        ],
      ],
    );
  }
}

/// _RiskEmptyState shows a calm empty message when no blockers surface.
class _RiskEmptyState extends StatelessWidget {
  /// Creates a risk empty state.
  const _RiskEmptyState();

  /// Builds the empty state.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No blockers surfaced',
        style: TextStyle(color: context.agentAwesomeColors.muted),
      ),
    );
  }
}

/// _RiskChain renders a compact dependency chain.
class _RiskChain extends StatelessWidget {
  /// Creates a risk chain.
  const _RiskChain({required this.chain});

  /// Chain to render.
  final RiskUnblockChain chain;

  /// Builds the chain.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        if (compact) {
          return Column(
            children: <Widget>[
              for (final node in chain.nodes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RiskNode(node: node),
                ),
            ],
          );
        }
        return Row(
          children: <Widget>[
            for (
              var index = 0;
              index < chain.nodes.length;
              index++
            ) ...<Widget>[
              Expanded(child: _RiskNode(node: chain.nodes[index])),
              if (index < chain.nodes.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.arrow_forward,
                    color: context.agentAwesomeColors.muted,
                    size: 20,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// _RiskNode renders one node in a blocker chain.
class _RiskNode extends StatelessWidget {
  /// Creates a risk node.
  const _RiskNode({required this.node});

  /// Node to render.
  final RiskUnblockChainNode node;

  /// Builds the node.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      height: 58,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            node.title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            node.subtitle,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// _SuggestedUnblock renders the recommended next unblock action.
class _SuggestedUnblock extends StatelessWidget {
  /// Creates a suggested unblock row.
  const _SuggestedUnblock({required this.action});

  /// Suggested action to display.
  final ExecutiveSummaryAction action;

  /// Builds the suggested action row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      decoration: BoxDecoration(
        color: colors.warningSoft,
        border: Border.all(color: colors.warningBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.lightbulb_outline, color: colors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Suggested next unblock: ${action.label}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.ink, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.green,
              side: BorderSide(color: colors.border),
              minimumSize: const Size(92, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: action.safety == 'safe' ? () {} : null,
            child: const Text('Take action', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
