/// Renders the canonical Today dashboard from the memory projection.
library;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/executive_summary.dart';
import 'widgets/confidence_coverage_card.dart';
import 'widgets/delegation_agent_card.dart';
import 'widgets/executive_summary_explanation_drawer.dart';
import 'widgets/horizon_strip_card.dart';
import 'widgets/open_loop_radar_card.dart';
import 'widgets/risk_unblocks_card.dart';
import 'widgets/today_schedule_card.dart';
import 'widgets/todays_attention_card.dart';

/// TodayScreen presents the server-owned executive summary projection.
class TodayScreen extends StatelessWidget {
  /// Creates the Today screen.
  const TodayScreen({super.key, required this.controller, this.onOpenRoute});

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Opens a reserved projection route.
  final ValueChanged<String>? onOpenRoute;

  /// Builds the Today dashboard.
  @override
  Widget build(BuildContext context) {
    final state = controller.todayState;
    final projection = state.projection;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (state.error.isNotEmpty) ...<Widget>[
            _TodayErrorBanner(message: state.error),
            const SizedBox(height: 14),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                height: ConfidenceCoverageCard.preferredHeight(
                  width: constraints.maxWidth,
                  coverage: projection.coverage,
                ),
                child: ConfidenceCoverageCard(
                  coverage: projection.coverage,
                  quality: projection.quality,
                  onOpenLink: _openRoute,
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          _PrimarySections(
            projection: projection,
            onExplain: (item) => _showExplanation(context, item),
            onOpenLink: _openRoute,
          ),
          const SizedBox(height: 14),
          _SecondarySections(projection: projection, onOpenLink: _openRoute),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                height: TodayScheduleCard.preferredHeight(
                  width: constraints.maxWidth,
                ),
                child: TodayScheduleCard(
                  workspace: controller.workspace,
                  projection: projection,
                  onOpenLink: _openRoute,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Loads and displays the explanation drawer for one Today item.
  Future<void> _showExplanation(
    BuildContext context,
    ExecutiveSummaryItem item,
  ) async {
    await controller.explainTodayItem(item.id);
    if (!context.mounted) {
      return;
    }
    final explanation = controller.todayState.explanation;
    if (explanation.itemId != item.id && explanation.reason.isEmpty) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.agentAwesomeColors.surface,
      builder: (context) {
        return ExecutiveSummaryExplanationDrawer(
          explanation: controller.todayState.explanation,
        );
      },
    );
    controller.clearTodayExplanation();
  }

  /// Opens the existing app section that owns a reserved projection route.
  void _openRoute(String route) {
    onOpenRoute?.call(route);
  }
}

/// _PrimarySections arranges the three main Today panels.
class _PrimarySections extends StatelessWidget {
  /// Creates the primary Today section layout.
  const _PrimarySections({
    required this.projection,
    required this.onExplain,
    required this.onOpenLink,
  });

  final ExecutiveSummaryProjection projection;
  final Future<void> Function(ExecutiveSummaryItem item) onExplain;
  final ValueChanged<String> onOpenLink;

  /// Builds the responsive primary section layout.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1060;
        final cards = <Widget>[
          OpenLoopRadarCard(
            openLoops: projection.openLoops,
            onOpenLink: onOpenLink,
          ),
          TodaysAttentionCard(
            attention: projection.attention,
            onExplain: onExplain,
            onOpenLink: onOpenLink,
          ),
          DelegationAgentCard(
            delegation: projection.delegation,
            onOpenLink: onOpenLink,
          ),
        ];
        if (!wide) {
          return Column(
            children: <Widget>[
              for (final card in cards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(height: 330, child: card),
                ),
            ],
          );
        }
        return SizedBox(
          height: 330,
          child: Row(
            children: <Widget>[
              Expanded(flex: 5, child: cards[0]),
              const SizedBox(width: 14),
              Expanded(flex: 7, child: cards[1]),
              const SizedBox(width: 14),
              Expanded(flex: 6, child: cards[2]),
            ],
          ),
        );
      },
    );
  }
}

/// _SecondarySections arranges the horizon and risk panels.
class _SecondarySections extends StatelessWidget {
  /// Creates the secondary Today section layout.
  const _SecondarySections({
    required this.projection,
    required this.onOpenLink,
  });

  final ExecutiveSummaryProjection projection;
  final ValueChanged<String> onOpenLink;

  /// Builds the responsive secondary section layout.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final horizon = HorizonStripCard(
          timeHorizon: projection.timeHorizon,
          onOpenLink: onOpenLink,
        );
        final risks = RiskUnblocksCard(
          riskUnblocks: projection.riskUnblocks,
          onOpenLink: onOpenLink,
        );
        final horizonHeight = HorizonStripCard.preferredHeight(
          width: wide
              ? (constraints.maxWidth - 14) * 5 / 11
              : constraints.maxWidth,
          bucketCount: projection.timeHorizon.buckets.length,
        );
        if (!wide) {
          return Column(
            children: <Widget>[
              SizedBox(height: horizonHeight, child: horizon),
              const SizedBox(height: 12),
              SizedBox(height: 190, child: risks),
            ],
          );
        }
        final rowHeight = horizonHeight > 190 ? horizonHeight : 190.0;
        return SizedBox(
          height: rowHeight,
          child: Row(
            children: <Widget>[
              Expanded(flex: 5, child: horizon),
              const SizedBox(width: 14),
              Expanded(flex: 6, child: risks),
            ],
          ),
        );
      },
    );
  }
}

/// _TodayErrorBanner displays Today loading failures without blocking the page.
class _TodayErrorBanner extends StatelessWidget {
  /// Creates an error banner.
  const _TodayErrorBanner({required this.message});

  /// Error message to display.
  final String message;

  /// Builds the banner.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.warningSoft,
        border: Border.all(color: colors.warningBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(color: colors.warningText, fontSize: 13),
      ),
    );
  }
}
