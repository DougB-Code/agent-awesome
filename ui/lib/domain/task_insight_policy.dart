/// Defines tunable thresholds for deterministic task insight queries.
library;

/// TaskInsightPolicy stores query and scoring thresholds outside UI widgets.
class TaskInsightPolicy {
  /// Creates a task insight policy.
  const TaskInsightPolicy({
    this.highRewardThreshold = 0.68,
    this.highRiskThreshold = 0.60,
    this.agentFitThreshold = 0.58,
    this.safeAgentThreshold = 0.60,
    this.safeAgentRiskCeiling = 0.55,
    this.lowHumanValueCeiling = 0.62,
    this.handoffReadinessThreshold = 0.55,
    this.obligationThreshold = 0.55,
    this.quickUnblockEffortCeiling = 0.40,
    this.quickUnblockDownstreamThreshold = 0.50,
    this.confidenceFloor = 0.45,
    this.metadataCompletenessFloor = 0.68,
    this.downstreamMaxDepth = 3,
    this.downstreamMaxVisited = 40,
    this.relationConfidenceFloor = 0.30,
  });

  /// Reward score that counts as high value.
  final double highRewardThreshold;

  /// Risk score that counts as high risk.
  final double highRiskThreshold;

  /// Agent-fit score that counts as agent-capable.
  final double agentFitThreshold;

  /// Agent-safety score that counts as safe enough to suggest handoff.
  final double safeAgentThreshold;

  /// Risk ceiling for ready handoff candidates.
  final double safeAgentRiskCeiling;

  /// Reward ceiling for low-to-medium human-value handoff work.
  final double lowHumanValueCeiling;

  /// Handoff-readiness score required for ready candidates.
  final double handoffReadinessThreshold;

  /// Obligation score required for must-do handoff candidates.
  final double obligationThreshold;

  /// Maximum blocker effort for quick unblock candidates.
  final double quickUnblockEffortCeiling;

  /// Minimum downstream value for quick unblock candidates.
  final double quickUnblockDownstreamThreshold;

  /// Minimum confidence for most insight candidates.
  final double confidenceFloor;

  /// Metadata completeness floor before a gap is emitted.
  final double metadataCompletenessFloor;

  /// Maximum traversal depth for downstream value.
  final int downstreamMaxDepth;

  /// Maximum relation nodes visited for downstream value.
  final int downstreamMaxVisited;

  /// Minimum inferred relation confidence for graph traversal.
  final double relationConfidenceFloor;
}
