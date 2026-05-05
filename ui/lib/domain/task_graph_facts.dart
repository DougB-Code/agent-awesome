/// Defines canonical task graph facts before UI projections derive insights.
library;

/// TaskGraphEdgeKind describes a relationship between two task nodes.
enum TaskGraphEdgeKind {
  /// Source task must be completed before the target task can proceed.
  blocks,

  /// Source task depends on the target task.
  dependsOn,

  /// Source task is a child work package of the target task.
  partOf,

  /// Source task creates upside or unlocks value for the target task.
  enables,

  /// Source task is generally related to the target task.
  relatedTo,
}

/// TaskGraphNode stores direct measurable task facts.
class TaskGraphNode {
  /// Creates one canonical task graph node.
  const TaskGraphNode({
    required this.id,
    required this.title,
    this.description = '',
    this.person = '',
    this.estimateMinutes = 0,
    this.dueAt,
    this.scheduledAt,
    this.spendCents = 0,
    this.earnCents = 0,
    this.saveCents = 0,
    this.currency = '',
    this.project = '',
    this.view = '',
    this.priority = 'normal',
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.canceledAt,
  });

  /// Stable task identifier.
  final String id;

  /// Human-readable task title.
  final String title;

  /// Optional task detail.
  final String description;

  /// Responsible person or entity.
  final String person;

  /// Estimated effort in minutes.
  final int estimateMinutes;

  /// Commitment deadline for when the task must be done.
  final DateTime? dueAt;

  /// Planned time for starting or doing the task.
  final DateTime? scheduledAt;

  /// Expected spend in minor currency units.
  final int spendCents;

  /// Expected earned money in minor currency units.
  final int earnCents;

  /// Expected saved money in minor currency units.
  final int saveCents;

  /// Three-letter ISO currency code shared by spend, earn, and save values.
  final String currency;

  /// Owning project label.
  final String project;

  /// Global cross-cutting view label.
  final String view;

  /// User-authored priority value.
  final String priority;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;

  /// Completion timestamp.
  final DateTime? completedAt;

  /// Cancellation timestamp.
  final DateTime? canceledAt;

  /// Returns expected net money impact in minor currency units.
  int get netReturnCents => earnCents + saveCents - spendCents;
}

/// TaskGraphEdge stores one relationship between two task nodes.
class TaskGraphEdge {
  /// Creates one canonical task graph edge.
  const TaskGraphEdge({
    required this.fromTaskId,
    required this.toTaskId,
    required this.kind,
    this.confidence = 1,
    this.source = '',
    this.explanation = '',
  });

  /// Source task id.
  final String fromTaskId;

  /// Target task id.
  final String toTaskId;

  /// Relationship type.
  final TaskGraphEdgeKind kind;

  /// Confidence from 0 to 1 for inferred edges.
  final double confidence;

  /// Source system or actor that supplied the edge.
  final String source;

  /// Short explanation for inferred edges.
  final String explanation;
}

/// TaskGraphSnapshot stores direct task nodes and explicit relation edges.
class TaskGraphSnapshot {
  /// Creates one immutable task graph snapshot.
  const TaskGraphSnapshot({
    this.generatedAt,
    this.nodes = const <TaskGraphNode>[],
    this.edges = const <TaskGraphEdge>[],
  });

  /// Snapshot generation timestamp.
  final DateTime? generatedAt;

  /// Task nodes with direct quantifiable facts.
  final List<TaskGraphNode> nodes;

  /// Task relationship edges.
  final List<TaskGraphEdge> edges;
}
