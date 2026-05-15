/// Defines stable task insight ids, presets, summaries, and candidates.
library;

/// TaskInsightIds centralizes named insight query identifiers.
class TaskInsightIds {
  const TaskInsightIds._();

  /// Operational all-tasks preset.
  static const String all = 'all';

  /// Today work that requires human judgment or approval.
  static const String todayDecisions = 'today_decisions';

  /// Today person, promise, reply, or check-in loops that are due.
  static const String todayRelationships = 'today_relationships';

  /// Candidate work that is safe and useful to hand to the agent.
  static const String agentHandoff = 'agent_handoff';

  /// High-value work due in the next calendar week.
  static const String nextWeekHighValue = 'next_week_high_value';

  /// Low-effort work that unlocks valuable downstream tasks.
  static const String quickUnblocks = 'quick_unblocks';

  /// Risky work with low metadata confidence.
  static const String highRiskLowConfidence = 'high_risk_low_confidence';

  /// Capacity collision warning in time-oriented views.
  static const String capacityCollision = 'capacity_collision';
}

/// TaskInsightPreset describes one selectable named query.
class TaskInsightPreset {
  /// Creates one named insight preset.
  const TaskInsightPreset({
    required this.id,
    required this.label,
    required this.question,
    required this.iconName,
  });

  /// Stable insight id.
  final String id;

  /// Short user-facing label.
  final String label;

  /// User question answered by the preset.
  final String question;

  /// Material icon name used by UI mapping.
  final String iconName;
}

/// TaskInsightCandidate stores one task match for an insight query.
class TaskInsightCandidate {
  /// Creates one ranked insight candidate.
  const TaskInsightCandidate({
    required this.insightId,
    required this.taskId,
    required this.rank,
    required this.score,
    this.severity = 'info',
    this.matchedRules = const <String>[],
    this.missingRules = const <String>[],
    this.explanation = '',
    this.evidenceIds = const <String>[],
    this.confidence = 0,
  });

  /// Insight id this task matched.
  final String insightId;

  /// Canonical task id.
  final String taskId;

  /// Zero-based rank inside the insight query.
  final int rank;

  /// Normalized ranking score.
  final double score;

  /// Severity such as info, warning, or critical.
  final String severity;

  /// Rules satisfied by this candidate.
  final List<String> matchedRules;

  /// Rules or metadata that remain missing.
  final List<String> missingRules;

  /// Human-readable candidate explanation.
  final String explanation;

  /// Source record ids supporting this candidate.
  final List<String> evidenceIds;

  /// Candidate confidence from 0 to 1.
  final double confidence;
}

/// TaskInsightQuerySummary stores derived counts for one named insight query.
class TaskInsightQuerySummary {
  /// Creates one derived query summary.
  const TaskInsightQuerySummary({
    required this.id,
    required this.label,
    required this.question,
    this.count = 0,
    this.warningCount = 0,
    this.estimatedMinutes = 0,
    this.primaryTaskIds = const <String>[],
    this.explanation = '',
  });

  /// Stable insight id.
  final String id;

  /// Short label.
  final String label;

  /// User question answered by the query.
  final String question;

  /// Matching task count.
  final int count;

  /// Warning-level match count.
  final int warningCount;

  /// Estimated minutes represented by matching tasks.
  final int estimatedMinutes;

  /// Top canonical task ids.
  final List<String> primaryTaskIds;

  /// Human-readable summary.
  final String explanation;
}
