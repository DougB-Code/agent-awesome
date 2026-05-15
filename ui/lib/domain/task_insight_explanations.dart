/// Builds concise explanations for deterministic task insights.
library;

import 'models.dart';
import 'task_insight_query.dart';
import 'task_insight_scores.dart';

/// TaskInsightExplanations owns reusable human-readable insight language.
class TaskInsightExplanations {
  const TaskInsightExplanations._();

  /// Explains why a task appears in the agent handoff insight.
  static String agentHandoff({
    required WorkspaceTask? workspaceTask,
    required TaskProjectionTask? projectionTask,
    required TaskInsightScoreProfile scores,
  }) {
    final parts = <String>[];
    if (scores.obligation >= 0.70) {
      parts.add('must-do or committed');
    }
    if (scores.humanEffort <= 0.45) {
      parts.add('low human effort');
    }
    if (scores.agentFit >= 0.58) {
      parts.add('good agent fit');
    }
    if (scores.agentSafety < 0.70) {
      parts.add('needs safety review');
    } else {
      parts.add('safe enough for assisted work');
    }
    return _sentence(parts, fallback: 'Useful candidate for agent support.');
  }

  /// Explains why a task appears in next-week high value.
  static String nextWeekHighValue({
    required WorkspaceTask? workspaceTask,
    required TaskInsightScoreProfile scores,
  }) {
    final parts = <String>[
      'due next week',
      if (scores.reward >= 0.68) 'high reward',
      if (scores.consequence >= 0.60) 'meaningful consequence',
    ];
    return _sentence(parts, fallback: 'High-value work coming next week.');
  }

  /// Explains why a task appears in quick unblocks.
  static String quickUnblock({
    required int downstreamCount,
    required TaskInsightScoreProfile scores,
  }) {
    final minutes = (scores.blockerEffort * 180).round();
    return '$downstreamCount downstream task${downstreamCount == 1 ? '' : 's'} can move after about ${minutes == 0 ? 15 : minutes}m of unblock work.';
  }

  /// Returns a short generic task importance summary.
  static String whyThisMatters({
    required WorkspaceTask task,
    required TaskInsightScoreProfile? scores,
    required List<TaskInsightCandidate> candidates,
  }) {
    final matched = candidates.map((candidate) {
      return switch (candidate.insightId) {
        TaskInsightIds.todayDecisions => 'decision',
        TaskInsightIds.todayRelationships => 'follow-up',
        TaskInsightIds.agentHandoff => 'agent handoff',
        TaskInsightIds.nextWeekHighValue => 'next-week value',
        TaskInsightIds.quickUnblocks => 'quick unblock',
        TaskInsightIds.highRiskLowConfidence => 'risk gap',
        _ => 'task insight',
      };
    }).toSet();
    if (matched.isNotEmpty) {
      return 'This task is showing up for ${matched.join(', ')} because its graph signals need attention.';
    }
    return 'This task is available in the graph-backed queue and insight views.';
  }

  /// Joins explanation fragments into one readable sentence.
  static String _sentence(List<String> parts, {required String fallback}) {
    final cleaned = parts
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) {
      return fallback;
    }
    final text = cleaned.join(', ');
    return '${text.substring(0, 1).toUpperCase()}${text.substring(1)}.';
  }
}
