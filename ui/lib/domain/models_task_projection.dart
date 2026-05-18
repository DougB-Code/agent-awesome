/// Task projection, stream, and constellation data models.
part of 'models.dart';

/// TaskProjectionGraph stores canonical task facts for client-owned projections.
class TaskProjectionGraph {
  /// Creates a canonical task projection graph.
  const TaskProjectionGraph({
    this.schemaVersion = '1.0',
    this.generatedAt,
    this.tasks = const <TaskProjectionTask>[],
    this.facets = const <TaskProjectionFacet>[],
    this.memberships = const <TaskProjectionMembership>[],
    this.edges = const <TaskProjectionEdge>[],
    this.insightSummaries = const <TaskInsightSummary>[],
    this.quality = const TaskProjectionQuality(),
  });

  /// Schema version returned by the projection graph service.
  final String schemaVersion;

  /// Projection generation timestamp.
  final DateTime? generatedAt;

  /// Canonical projected task records.
  final List<TaskProjectionTask> tasks;

  /// Reusable grouping facets.
  final List<TaskProjectionFacet> facets;

  /// Task-to-facet membership records.
  final List<TaskProjectionMembership> memberships;

  /// Sparse meaningful task-to-task edges.
  final List<TaskProjectionEdge> edges;

  /// Precomputed insight summaries included in v2 graph responses.
  final List<TaskInsightSummary> insightSummaries;

  /// Graph quality and coverage metrics.
  final TaskProjectionQuality quality;
}

/// TaskProjectionQuality stores graph-level trust and completeness metrics.
class TaskProjectionQuality {
  /// Creates graph quality metrics.
  const TaskProjectionQuality({
    this.schemaConfidence = 0,
    this.relationCoverage = 0,
    this.warnings = const <String>[],
  });

  /// Confidence that the graph matches the expected schema.
  final double schemaConfidence;

  /// Aggregate relation coverage from 0 to 1.
  final double relationCoverage;

  /// Human-readable graph warnings.
  final List<String> warnings;
}

/// TaskProjectionTask stores one task with derived scores and facets.
class TaskProjectionTask {
  /// Creates a canonical projected task.
  const TaskProjectionTask({
    required this.taskId,
    required this.title,
    required this.status,
    required this.priority,
    this.description = '',
    this.dueAt,
    this.scheduledAt,
    this.topics = const <String>[],
    this.estimateMinutes = 0,
    this.project = '',
    this.location = '',
    this.owner = '',
    this.workBreakdown = const TaskWorkBreakdown(),
    this.projectId = '',
    this.scores = const TaskProjectionScores(),
    this.scoreComponents = const <String, List<TaskScoreComponent>>{},
    this.facetIds = const <String>[],
    this.evidenceIds = const <String>[],
    this.missingFields = const <String>[],
    this.confidence = 0,
    this.explanation = '',
  });

  /// Referenced task id.
  final String taskId;

  /// Display title.
  final String title;

  /// Task notes.
  final String description;

  /// Backend lifecycle status.
  final String status;

  /// Backend task priority.
  final String priority;

  /// Optional due timestamp.
  final DateTime? dueAt;

  /// Optional scheduled timestamp.
  final DateTime? scheduledAt;

  /// Task topics.
  final List<String> topics;

  /// Estimated duration in minutes.
  final int estimateMinutes;

  /// Project name from explicit task metadata.
  final String project;

  /// Location requirement.
  final String location;

  /// Responsible person.
  final String owner;

  /// Optional WBS planning metadata.
  final TaskWorkBreakdown workBreakdown;

  /// Normalized owning project id.
  final String projectId;

  /// Derived projection scores.
  final TaskProjectionScores scores;

  /// Per-score explanation components keyed by score name.
  final Map<String, List<TaskScoreComponent>> scoreComponents;

  /// Stable facet ids associated with this task.
  final List<String> facetIds;

  /// Source records that support task classifications.
  final List<String> evidenceIds;

  /// Missing fields that lower insight confidence.
  final List<String> missingFields;

  /// Projection confidence from 0 to 1.
  final double confidence;

  /// Human-readable projection explanation.
  final String explanation;

  /// Returns this task with selected graph fields replaced.
  TaskProjectionTask copyWith({
    String? taskId,
    String? title,
    String? status,
    String? priority,
    String? description,
    DateTime? dueAt,
    DateTime? scheduledAt,
    List<String>? topics,
    int? estimateMinutes,
    String? project,
    String? location,
    String? owner,
    TaskWorkBreakdown? workBreakdown,
    String? projectId,
    TaskProjectionScores? scores,
    Map<String, List<TaskScoreComponent>>? scoreComponents,
    List<String>? facetIds,
    List<String>? evidenceIds,
    List<String>? missingFields,
    double? confidence,
    String? explanation,
  }) {
    return TaskProjectionTask(
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      description: description ?? this.description,
      dueAt: dueAt ?? this.dueAt,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      topics: topics ?? this.topics,
      estimateMinutes: estimateMinutes ?? this.estimateMinutes,
      project: project ?? this.project,
      location: location ?? this.location,
      owner: owner ?? this.owner,
      workBreakdown: workBreakdown ?? this.workBreakdown,
      projectId: projectId ?? this.projectId,
      scores: scores ?? this.scores,
      scoreComponents: scoreComponents ?? this.scoreComponents,
      facetIds: facetIds ?? this.facetIds,
      evidenceIds: evidenceIds ?? this.evidenceIds,
      missingFields: missingFields ?? this.missingFields,
      confidence: confidence ?? this.confidence,
      explanation: explanation ?? this.explanation,
    );
  }
}

/// TaskProjectionScores stores derived insight scores for one task.
class TaskProjectionScores {
  /// Creates derived task projection scores.
  const TaskProjectionScores({
    this.reward = 0,
    this.pressure = 0,
    this.risk = 0,
    this.timePressure = 0,
    this.humanEffort = 0,
    this.agentFit = 0,
    this.obligation = 0,
    this.consequenceSeverity = 0,
    this.agentSafety = 0,
    this.handoffReadiness = 0,
    this.contextReadiness = 0,
    this.humanJudgmentNeed = 0,
    this.downstreamValue = 0,
    this.blockerEffort = 0,
    this.unblockLeverage = 0,
    this.staleness = 0,
    this.elevation = 0,
  });

  /// Reward or upside score.
  final double reward;

  /// Combined pressure score.
  final double pressure;

  /// Failure or delay risk score.
  final double risk;

  /// Deadline pressure score.
  final double timePressure;

  /// Human attention cost score.
  final double humanEffort;

  /// Agent delegation fit score.
  final double agentFit;

  /// Obligation or must-do score.
  final double obligation;

  /// Consequence severity score.
  final double consequenceSeverity;

  /// Agent safety score.
  final double agentSafety;

  /// Handoff readiness score.
  final double handoffReadiness;

  /// Context readiness score.
  final double contextReadiness;

  /// Human judgment requirement score.
  final double humanJudgmentNeed;

  /// Downstream value unlocked by this task.
  final double downstreamValue;

  /// Estimated effort to clear this blocker.
  final double blockerEffort;

  /// Downstream value per unit of blocker effort.
  final double unblockLeverage;

  /// Staleness score.
  final double staleness;

  /// Overall importance score.
  final double elevation;
}

/// TaskScoreComponent explains one component of a derived score.
class TaskScoreComponent {
  /// Creates one score component.
  const TaskScoreComponent({
    required this.name,
    required this.value,
    this.explanation = '',
  });

  /// Machine-readable component name.
  final String name;

  /// Component contribution or normalized value.
  final double value;

  /// Human-readable score explanation.
  final String explanation;
}

/// TaskProjectionFacet stores one reusable grouping entity.
class TaskProjectionFacet {
  /// Creates a canonical task grouping facet.
  const TaskProjectionFacet({
    required this.id,
    required this.dimension,
    required this.label,
    this.description = '',
    this.source = '',
    this.version = '',
    this.sourceField = '',
    this.provenance = '',
    this.confidence = 0,
  });

  /// Stable facet id.
  final String id;

  /// Facet dimension such as time, project, or person.
  final String dimension;

  /// User-facing label.
  final String label;

  /// Short dimension explanation.
  final String description;

  /// Fact source such as task, relation, or derived.
  final String source;

  /// Controlled vocabulary version.
  final String version;

  /// Source field used to derive this facet.
  final String sourceField;

  /// Short provenance label.
  final String provenance;

  /// Facet confidence from 0 to 1.
  final double confidence;

  /// Returns this facet with selected identity fields replaced.
  TaskProjectionFacet copyWith({
    String? id,
    String? dimension,
    String? label,
    String? description,
    String? source,
    String? version,
    String? sourceField,
    String? provenance,
    double? confidence,
  }) {
    return TaskProjectionFacet(
      id: id ?? this.id,
      dimension: dimension ?? this.dimension,
      label: label ?? this.label,
      description: description ?? this.description,
      source: source ?? this.source,
      version: version ?? this.version,
      sourceField: sourceField ?? this.sourceField,
      provenance: provenance ?? this.provenance,
      confidence: confidence ?? this.confidence,
    );
  }
}

/// TaskProjectionMembership links a task to a facet.
class TaskProjectionMembership {
  /// Creates a task-to-facet membership.
  const TaskProjectionMembership({
    required this.taskId,
    required this.facetId,
    required this.dimension,
    this.source = '',
    this.confidence = 0,
    this.explanation = '',
  });

  /// Referenced task id.
  final String taskId;

  /// Referenced facet id.
  final String facetId;

  /// Facet dimension.
  final String dimension;

  /// Membership source.
  final String source;

  /// Membership confidence from 0 to 1.
  final double confidence;

  /// Human-readable membership explanation.
  final String explanation;

  /// Returns this membership with selected identity fields replaced.
  TaskProjectionMembership copyWith({
    String? taskId,
    String? facetId,
    String? dimension,
    String? source,
    double? confidence,
    String? explanation,
  }) {
    return TaskProjectionMembership(
      taskId: taskId ?? this.taskId,
      facetId: facetId ?? this.facetId,
      dimension: dimension ?? this.dimension,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      explanation: explanation ?? this.explanation,
    );
  }
}

/// TaskProjectionEdge stores one sparse meaningful task relation.
class TaskProjectionEdge {
  /// Creates a canonical task projection edge.
  const TaskProjectionEdge({
    required this.fromTaskId,
    required this.toTaskId,
    required this.relationType,
    this.id = '',
    this.directionSemantics = '',
    this.source = '',
    this.sourceKind = '',
    this.firewall = '',
    this.sensitivity = '',
    this.confidence = 0,
    this.explanation = '',
    this.evidenceIds = const <String>[],
    this.actor = '',
    this.createdAt,
    this.updatedAt,
    this.confirmedAt,
    this.dismissedAt,
  });

  /// Stable relation id.
  final String id;

  /// Source task id.
  final String fromTaskId;

  /// Target task id.
  final String toTaskId;

  /// Relationship type.
  final String relationType;

  /// Edge source.
  final String source;

  /// Explicit direction semantics for graph analytics.
  final String directionSemantics;

  /// Source kind such as explicit, inferred, or system-derived.
  final String sourceKind;

  /// Access firewall attached to the edge's source graph fact.
  final String firewall;

  /// Sensitivity attached to the edge's source graph fact.
  final String sensitivity;

  /// Edge confidence from 0 to 1.
  final double confidence;

  /// Human-readable edge explanation.
  final String explanation;

  /// Source records that support this relation.
  final List<String> evidenceIds;

  /// Last actor.
  final String actor;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;

  /// User confirmation timestamp.
  final DateTime? confirmedAt;

  /// User dismissal timestamp.
  final DateTime? dismissedAt;

  /// Returns this edge with selected identity fields replaced.
  TaskProjectionEdge copyWith({
    String? id,
    String? fromTaskId,
    String? toTaskId,
    String? relationType,
    String? directionSemantics,
    String? source,
    String? sourceKind,
    String? firewall,
    String? sensitivity,
    double? confidence,
    String? explanation,
    List<String>? evidenceIds,
    String? actor,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? confirmedAt,
    DateTime? dismissedAt,
  }) {
    return TaskProjectionEdge(
      id: id ?? this.id,
      fromTaskId: fromTaskId ?? this.fromTaskId,
      toTaskId: toTaskId ?? this.toTaskId,
      relationType: relationType ?? this.relationType,
      directionSemantics: directionSemantics ?? this.directionSemantics,
      source: source ?? this.source,
      sourceKind: sourceKind ?? this.sourceKind,
      firewall: firewall ?? this.firewall,
      sensitivity: sensitivity ?? this.sensitivity,
      confidence: confidence ?? this.confidence,
      explanation: explanation ?? this.explanation,
      evidenceIds: evidenceIds ?? this.evidenceIds,
      actor: actor ?? this.actor,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      dismissedAt: dismissedAt ?? this.dismissedAt,
    );
  }
}

/// TaskInsightSummary stores one precomputed or derived insight count.
class TaskInsightSummary {
  /// Creates one insight summary.
  const TaskInsightSummary({
    required this.id,
    required this.title,
    this.question = '',
    this.count = 0,
    this.estimatedMinutes = 0,
    this.primaryTaskIds = const <String>[],
    this.warningCount = 0,
    this.explanation = '',
  });

  /// Stable insight id.
  final String id;

  /// User-facing title.
  final String title;

  /// User-facing question.
  final String question;

  /// Matching task count.
  final int count;

  /// Estimated human minutes represented by the insight.
  final int estimatedMinutes;

  /// Primary task ids represented by the insight.
  final List<String> primaryTaskIds;

  /// Warning count represented by the insight.
  final int warningCount;

  /// Human-readable summary explanation.
  final String explanation;
}

/// TaskStreamProjection groups tasks into fact lanes with relationship links.
class TaskStreamProjection {
  /// Creates a task stream projection.
  const TaskStreamProjection({
    this.generatedAt,
    this.lanes = const <TaskStreamLane>[],
    this.links = const <TaskStreamLink>[],
  });

  /// Projection generation timestamp.
  final DateTime? generatedAt;

  /// Ordered stream lanes.
  final List<TaskStreamLane> lanes;

  /// Visible relation links between projected stream cards.
  final List<TaskStreamLink> links;
}

/// TaskStreamLane stores one stream time column.
class TaskStreamLane {
  /// Creates a task stream lane.
  const TaskStreamLane({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.cards = const <TaskStreamCard>[],
  });

  /// Stable lane id.
  final String id;

  /// Display title.
  final String title;

  /// Secondary display text.
  final String subtitle;

  /// Projected task cards.
  final List<TaskStreamCard> cards;
}

/// TaskStreamCard stores one projected task card.
class TaskStreamCard {
  /// Creates a task stream card.
  const TaskStreamCard({
    required this.taskId,
    required this.title,
    required this.status,
    required this.priority,
    this.dueAt,
    this.scheduledAt,
    this.project = '',
    this.owner = '',
    this.streamId = '',
    this.readyNow = false,
    this.nextBestAction = '',
    this.batchScore = 0,
    this.contextSwitchCost = 0,
    this.spendLabel = '',
    this.spendScore = 0,
    this.bottleneckScore = 0,
    this.confidence = 0,
    this.explanation = '',
    this.relatedTaskCount = 0,
    this.estimateMinutes = 0,
  });

  /// Referenced task id.
  final String taskId;

  /// Display task title.
  final String title;

  /// Backend task status.
  final String status;

  /// Backend task priority.
  final String priority;

  /// Optional due timestamp.
  final DateTime? dueAt;

  /// Optional scheduled timestamp.
  final DateTime? scheduledAt;

  /// Owning project when supplied by the task stream backend.
  final String project;

  /// Responsible person when supplied by the task stream backend.
  final String owner;

  /// Stable route identifier for coloring related flow edges.
  final String streamId;

  /// Whether the task can be acted on now.
  final bool readyNow;

  /// Suggested next action.
  final String nextBestAction;

  /// Batching score from 0 to 1.
  final double batchScore;

  /// Human effort or context-switch cost from 0 to 1.
  final double contextSwitchCost;

  /// Human-readable explicit spend label when supplied by the backend.
  final String spendLabel;

  /// Normalized explicit spend score from 0 to 1 when supplied by the backend.
  final double spendScore;

  /// Bottleneck score from 0 to 1.
  final double bottleneckScore;

  /// Projection confidence from 0 to 1.
  final double confidence;

  /// Human-readable placement explanation.
  final String explanation;

  /// Number of related task edges.
  final int relatedTaskCount;

  /// Estimated duration in minutes.
  final int estimateMinutes;
}

/// TaskStreamLink stores a relation that can be drawn across stream rows.
class TaskStreamLink {
  /// Creates a stream relation link.
  const TaskStreamLink({
    required this.fromTaskId,
    required this.toTaskId,
    required this.relationType,
    this.transitionType = '',
    this.streamId = '',
    this.confidence = 0,
    this.explanation = '',
  });

  /// Source projected task id.
  final String fromTaskId;

  /// Target projected task id.
  final String toTaskId;

  /// Relation type from the task graph.
  final String relationType;

  /// Relationship transition type.
  final String transitionType;

  /// Stable route identifier for coloring this transition.
  final String streamId;

  /// Relation confidence from 0 to 1.
  final double confidence;

  /// Human-readable relation explanation.
  final String explanation;
}

/// TaskConstellationProjection stores spatial task graph nodes and edges.
class TaskConstellationProjection {
  /// Creates a task constellation projection.
  const TaskConstellationProjection({
    this.generatedAt,
    this.nodes = const <TaskConstellationNode>[],
    this.edges = const <TaskConstellationEdge>[],
  });

  /// Projection generation timestamp.
  final DateTime? generatedAt;

  /// Spatial task nodes.
  final List<TaskConstellationNode> nodes;

  /// Visual relation edges.
  final List<TaskConstellationEdge> edges;
}

/// TaskConstellationNode stores one spatial task node.
class TaskConstellationNode {
  /// Creates a task constellation node.
  const TaskConstellationNode({
    required this.taskId,
    required this.title,
    required this.status,
    this.category = '',
    this.timeHorizon = '',
    this.owner = '',
    this.project = '',
    this.x = 0,
    this.y = 0,
    this.size = 0,
    this.urgency = 0,
    this.confidence = 0,
    this.explanation = '',
  });

  /// Referenced task id.
  final String taskId;

  /// Display title.
  final String title;

  /// Backend task status.
  final String status;

  /// Context or category label.
  final String category;

  /// Time horizon label.
  final String timeHorizon;

  /// Responsible person or owner label.
  final String owner;

  /// Project or delivery stream label.
  final String project;

  /// Normalized x coordinate.
  final double x;

  /// Normalized y coordinate.
  final double y;

  /// Normalized node size.
  final double size;

  /// Normalized urgency.
  final double urgency;

  /// Projection confidence.
  final double confidence;

  /// Placement explanation.
  final String explanation;
}

/// TaskConstellationEdge stores one task relation edge.
class TaskConstellationEdge {
  /// Creates a task constellation edge.
  const TaskConstellationEdge({
    required this.fromTaskId,
    required this.toTaskId,
    required this.relationType,
    this.id = '',
    this.confidence = 0,
    this.source = '',
    this.factSource = '',
    this.sourceKind = '',
    this.firewall = '',
    this.sensitivity = '',
    this.explanation = '',
    this.evidenceIds = const <String>[],
    this.actor = '',
    this.createdAt,
    this.updatedAt,
    this.confirmedAt,
    this.dismissedAt,
  });

  /// Stable relation id when backed by a graph fact.
  final String id;

  /// Source task id.
  final String fromTaskId;

  /// Target task id.
  final String toTaskId;

  /// Relationship type.
  final String relationType;

  /// Edge confidence.
  final double confidence;

  /// Edge source.
  final String source;

  /// Original graph fact source when the display source is a visual role.
  final String factSource;

  /// Source kind such as explicit, inferred, or system-derived.
  final String sourceKind;

  /// Access firewall attached to the edge's source graph fact.
  final String firewall;

  /// Sensitivity attached to the edge's source graph fact.
  final String sensitivity;

  /// Edge explanation.
  final String explanation;

  /// Source records that support this relation.
  final List<String> evidenceIds;

  /// Last actor.
  final String actor;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;

  /// User confirmation timestamp.
  final DateTime? confirmedAt;

  /// User dismissal timestamp.
  final DateTime? dismissedAt;
}
