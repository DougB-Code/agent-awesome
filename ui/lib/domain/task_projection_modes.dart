/// Insight projection mode enumerations.
part of 'task_projection_adapters.dart';

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
