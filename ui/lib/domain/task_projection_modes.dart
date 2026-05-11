/// Insight projection mode enumerations.
part of 'task_projection_adapters.dart';

enum TaskTerrainInsightMode {
  /// Default reward and pressure planning mode.
  priorityFocus,

  /// Must-do work that is safe and useful for agent handoff.
  agentHandoff,

  /// High-value tasks due next week.
  nextWeekHighValue,

  /// Low-effort blockers with high downstream value.
  unblockLeverage,

  /// Risky tasks with low confidence or metadata gaps.
  riskConfidence,
}

/// TaskConstellationInsightMode identifies relationship diagnosis modes.
enum TaskConstellationInsightMode {
  /// General task relationship map.
  map,

  /// Deep dependency chain with the highest delivery risk.
  criticalPath,

  /// Blocker and dependency diagnosis.
  unblock,

  /// Risk ownership and materialized risk diagnosis.
  riskOwners,

  /// Agent handoff readiness graph.
  handoff,

  /// Downstream leverage graph.
  leverage,
}
