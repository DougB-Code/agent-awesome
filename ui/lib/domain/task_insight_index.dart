/// Builds the client-side task insight read model used by task views.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'models.dart';
import 'task_insight_explanations.dart';
import 'task_insight_policy.dart';
import 'task_insight_query.dart';
import 'task_insight_scores.dart';
import 'task_unblock_plan.dart';

/// TaskInsightIndex is the central query-side read model for task insights.
class TaskInsightIndex {
  /// Creates an immutable task insight index.
  const TaskInsightIndex({
    this.generatedAt,
    this.schemaVersion = '1.0',
    this.policy = const TaskInsightPolicy(),
    this.workspaceTasksById = const <String, WorkspaceTask>{},
    this.projectionTasksById = const <String, TaskProjectionTask>{},
    this.facetsById = const <String, TaskProjectionFacet>{},
    this.facetsByDimension = const <String, List<TaskProjectionFacet>>{},
    this.membershipsByTaskId = const <String, List<TaskProjectionMembership>>{},
    this.edges = const <TaskProjectionEdge>[],
    this.outgoingRelationsByTaskId = const <String, List<TaskProjectionEdge>>{},
    this.incomingRelationsByTaskId = const <String, List<TaskProjectionEdge>>{},
    this.blockersByTaskId = const <String, List<String>>{},
    this.blockedByTaskId = const <String, List<String>>{},
    this.commitmentsByTaskId = const <String, List<TaskCommitment>>{},
    this.metadataGapsByTaskId = const <String, List<TaskMetadataGapRecord>>{},
    this.scoresByTaskId = const <String, TaskInsightScoreProfile>{},
    this.insightCandidatesByInsightId =
        const <String, List<TaskInsightCandidate>>{},
    this.insightSummaries = const <TaskInsightQuerySummary>[],
    this.projectionCoverageMessage = '',
  });

  /// Empty index used before task data is loaded.
  static const TaskInsightIndex empty = TaskInsightIndex();

  /// Index build time.
  final DateTime? generatedAt;

  /// Projection graph schema version.
  final String schemaVersion;

  /// Query and score thresholds.
  final TaskInsightPolicy policy;

  /// Workspace tasks keyed by graph task id.
  final Map<String, WorkspaceTask> workspaceTasksById;

  /// Projection tasks keyed by graph task id.
  final Map<String, TaskProjectionTask> projectionTasksById;

  /// Facets keyed by facet id.
  final Map<String, TaskProjectionFacet> facetsById;

  /// Facets grouped by controlled dimension.
  final Map<String, List<TaskProjectionFacet>> facetsByDimension;

  /// Facet memberships keyed by graph task id.
  final Map<String, List<TaskProjectionMembership>> membershipsByTaskId;

  /// Normalized relation edges.
  final List<TaskProjectionEdge> edges;

  /// Outgoing relation edges keyed by graph task id.
  final Map<String, List<TaskProjectionEdge>> outgoingRelationsByTaskId;

  /// Incoming relation edges keyed by graph task id.
  final Map<String, List<TaskProjectionEdge>> incomingRelationsByTaskId;

  /// Direct blocker task ids keyed by blocked task id.
  final Map<String, List<String>> blockersByTaskId;

  /// Direct downstream blocked task ids keyed by blocker task id.
  final Map<String, List<String>> blockedByTaskId;

  /// Commitments keyed by graph task id.
  final Map<String, List<TaskCommitment>> commitmentsByTaskId;

  /// Metadata gaps keyed by graph task id.
  final Map<String, List<TaskMetadataGapRecord>> metadataGapsByTaskId;

  /// Query-ready normalized scores keyed by graph task id.
  final Map<String, TaskInsightScoreProfile> scoresByTaskId;

  /// Ranked candidates keyed by insight id.
  final Map<String, List<TaskInsightCandidate>> insightCandidatesByInsightId;

  /// Derived insight summaries.
  final List<TaskInsightQuerySummary> insightSummaries;

  /// Coverage warning when queue tasks and projection tasks diverge.
  final String projectionCoverageMessage;

  /// Builds an insight index from queue tasks, projection graph, and graph facts.
  factory TaskInsightIndex.build({
    required List<WorkspaceTask> workspaceTasks,
    required TaskProjectionGraph graph,
    List<TaskRelationRecord> taskRelations = const <TaskRelationRecord>[],
    List<TaskCommitment> taskCommitments = const <TaskCommitment>[],
    List<TaskMetadataSuggestion> metadataSuggestions =
        const <TaskMetadataSuggestion>[],
    TaskInsightPolicy policy = const TaskInsightPolicy(),
    DateTime? now,
  }) {
    final referenceTime = now ?? DateTime.now();
    final workspaceTasksById = <String, WorkspaceTask>{
      for (final task in workspaceTasks) task.id: task,
    };
    final projectionTasksById = <String, TaskProjectionTask>{
      for (final task in graph.tasks) task.taskId: task,
    };
    final facetsById = <String, TaskProjectionFacet>{
      for (final facet in graph.facets) facet.id: facet,
    };
    final facetsByDimension = <String, List<TaskProjectionFacet>>{};
    for (final facet in graph.facets) {
      facetsByDimension
          .putIfAbsent(facet.dimension, () => <TaskProjectionFacet>[])
          .add(facet);
    }
    final membershipsByTaskId = <String, List<TaskProjectionMembership>>{};
    for (final membership in graph.memberships) {
      membershipsByTaskId
          .putIfAbsent(membership.taskId, () => <TaskProjectionMembership>[])
          .add(membership);
    }
    final normalizedEdges = _normalizeRelationRecords(
      graphEdges: graph.edges,
      taskRelations: taskRelations,
    );
    final outgoing = <String, List<TaskProjectionEdge>>{};
    final incoming = <String, List<TaskProjectionEdge>>{};
    final blockers = <String, LinkedHashSet<String>>{};
    final blocked = <String, LinkedHashSet<String>>{};
    for (final edge in normalizedEdges) {
      outgoing
          .putIfAbsent(edge.fromTaskId, () => <TaskProjectionEdge>[])
          .add(edge);
      incoming
          .putIfAbsent(edge.toTaskId, () => <TaskProjectionEdge>[])
          .add(edge);
      _indexBlockingDirection(edge, blockers, blocked, policy);
    }
    final cycleTaskIds = _dependencyCycleTaskIds(normalizedEdges, policy);
    final allCommitments = <TaskCommitment>[
      ...graph.commitments,
      ...taskCommitments,
    ];
    final commitmentsByTaskId = <String, List<TaskCommitment>>{};
    for (final commitment in allCommitments) {
      commitmentsByTaskId
          .putIfAbsent(commitment.taskId, () => <TaskCommitment>[])
          .add(commitment);
    }
    final downstreamValues = <String, double>{};
    for (final taskId in _allTaskIds(workspaceTasksById, projectionTasksById)) {
      downstreamValues[taskId] = _downstreamValue(
        taskId: taskId,
        blockedByTaskId: blocked,
        projectionTasksById: projectionTasksById,
        policy: policy,
      );
    }
    final scoreProfiles = <String, TaskInsightScoreProfile>{};
    for (final taskId in _allTaskIds(workspaceTasksById, projectionTasksById)) {
      final commitmentHardness = _commitmentHardness(
        commitmentsByTaskId[taskId] ?? const <TaskCommitment>[],
      );
      final blockerEffort = _blockerEffort(
        workspaceTasksById[taskId],
        projectionTasksById[taskId],
      );
      final downstream = downstreamValues[taskId] ?? 0;
      final leverage = _clamp01(downstream / math.max(blockerEffort, 0.10));
      scoreProfiles[taskId] = TaskInsightScoreProfile.fromTask(
        taskId: taskId,
        workspaceTask: workspaceTasksById[taskId],
        projectionTask: projectionTasksById[taskId],
        downstreamValue: downstream,
        unblockLeverage: leverage,
        commitmentHardness: commitmentHardness,
      );
    }
    final gapsByTaskId = _metadataGapsByTaskId(
      graphGaps: graph.metadataGaps,
      metadataSuggestions: metadataSuggestions,
      workspaceTasksById: workspaceTasksById,
      projectionTasksById: projectionTasksById,
      scoresByTaskId: scoreProfiles,
      policy: policy,
      cycleTaskIds: cycleTaskIds,
    );
    final candidates = _buildCandidates(
      workspaceTasksById: workspaceTasksById,
      projectionTasksById: projectionTasksById,
      scoresByTaskId: scoreProfiles,
      blockedByTaskId: blocked,
      blockersByTaskId: blockers,
      metadataGapsByTaskId: gapsByTaskId,
      policy: policy,
      now: referenceTime,
    );
    final summaries = _buildSummaries(
      candidatesByInsightId: candidates,
      workspaceTasksById: workspaceTasksById,
    );
    return TaskInsightIndex(
      generatedAt: graph.generatedAt ?? referenceTime,
      schemaVersion: graph.schemaVersion,
      policy: policy,
      workspaceTasksById: Map<String, WorkspaceTask>.unmodifiable(
        workspaceTasksById,
      ),
      projectionTasksById: Map<String, TaskProjectionTask>.unmodifiable(
        projectionTasksById,
      ),
      facetsById: Map<String, TaskProjectionFacet>.unmodifiable(facetsById),
      facetsByDimension: Map<String, List<TaskProjectionFacet>>.unmodifiable(
        facetsByDimension,
      ),
      membershipsByTaskId:
          Map<String, List<TaskProjectionMembership>>.unmodifiable(
            membershipsByTaskId,
          ),
      edges: List<TaskProjectionEdge>.unmodifiable(normalizedEdges),
      outgoingRelationsByTaskId:
          Map<String, List<TaskProjectionEdge>>.unmodifiable(outgoing),
      incomingRelationsByTaskId:
          Map<String, List<TaskProjectionEdge>>.unmodifiable(incoming),
      blockersByTaskId: _freezeSetMap(blockers),
      blockedByTaskId: _freezeSetMap(blocked),
      commitmentsByTaskId: Map<String, List<TaskCommitment>>.unmodifiable(
        commitmentsByTaskId,
      ),
      metadataGapsByTaskId:
          Map<String, List<TaskMetadataGapRecord>>.unmodifiable(gapsByTaskId),
      scoresByTaskId: Map<String, TaskInsightScoreProfile>.unmodifiable(
        scoreProfiles,
      ),
      insightCandidatesByInsightId:
          Map<String, List<TaskInsightCandidate>>.unmodifiable(candidates),
      insightSummaries: List<TaskInsightQuerySummary>.unmodifiable(summaries),
      projectionCoverageMessage: _coverageMessage(
        _activeWorkspaceTaskIds(workspaceTasksById, projectionTasksById),
        projectionTasksById.keys.toSet(),
      ),
    );
  }

  /// Returns the workspace task represented by a graph task id.
  WorkspaceTask? workspaceTaskForId(String? taskId) {
    if (taskId == null || taskId.isEmpty) {
      return null;
    }
    return workspaceTasksById[taskId];
  }

  /// Returns the best display title for a graph task or anchor id.
  String titleForTaskId(String taskId) {
    if (taskId.startsWith('anchor:')) {
      return taskId.substring('anchor:'.length);
    }
    return workspaceTasksById[taskId]?.title ??
        projectionTasksById[taskId]?.title ??
        taskId;
  }

  /// Returns all ranked candidates for one insight id.
  List<TaskInsightCandidate> tasksForInsight(String insightId) {
    return insightCandidatesByInsightId[insightId] ??
        const <TaskInsightCandidate>[];
  }

  /// Returns all candidates associated with a task.
  List<TaskInsightCandidate> candidatesForTask(String taskId) {
    return <TaskInsightCandidate>[
      for (final candidates in insightCandidatesByInsightId.values)
        for (final candidate in candidates)
          if (candidate.taskId == taskId) candidate,
    ];
  }

  /// Returns the candidate for one task and insight, when present.
  TaskInsightCandidate? candidateForTask(String taskId, String insightId) {
    for (final candidate in tasksForInsight(insightId)) {
      if (candidate.taskId == taskId) {
        return candidate;
      }
    }
    return null;
  }

  /// Returns metadata gaps for a task.
  List<TaskMetadataGapRecord> metadataGapsFor(String taskId) {
    return metadataGapsByTaskId[taskId] ?? const <TaskMetadataGapRecord>[];
  }

  /// Returns blockers for a task.
  List<String> blockersFor(String taskId) {
    return blockersByTaskId[taskId] ?? const <String>[];
  }

  /// Returns downstream tasks blocked by a task.
  List<String> downstreamTasksFor(String taskId) {
    return blockedByTaskId[taskId] ?? const <String>[];
  }

  /// Returns a selected-task unblock plan.
  TaskUnblockPlan unblockPlanFor(String taskId) {
    final workspaceTask = workspaceTasksById[taskId];
    final projectionTask = projectionTasksById[taskId];
    final status = workspaceTask?.status ?? projectionTask?.status ?? '';
    final blockers = blockersFor(taskId);
    final relationEdges = <TaskProjectionEdge>[
      for (final edge
          in incomingRelationsByTaskId[taskId] ?? const <TaskProjectionEdge>[])
        if (_edgeBlocksTask(edge, taskId)) edge,
      for (final edge
          in outgoingRelationsByTaskId[taskId] ?? const <TaskProjectionEdge>[])
        if (_edgeMakesTaskWait(edge, taskId)) edge,
    ];
    final primaryBlockerId = _primaryBlocker(
      blockers,
      scoresByTaskId,
      projectionTasksById,
    );
    final downstream = primaryBlockerId.isEmpty
        ? downstreamTasksFor(taskId)
        : downstreamTasksFor(primaryBlockerId);
    final gaps = metadataGapsFor(taskId);
    final agentOptions = _agentAssistOptions(
      scoresByTaskId[primaryBlockerId] ?? scoresByTaskId[taskId],
    );
    return TaskUnblockPlan(
      taskId: taskId,
      status: status,
      primaryBlockerId: primaryBlockerId,
      blockerType: relationEdges.isEmpty
          ? ''
          : relationEdges.first.relationType,
      blockerOwner: _ownerFor(
        primaryBlockerId,
        workspaceTasksById,
        projectionTasksById,
      ),
      blockingRelations: relationEdges,
      downstreamTaskIds: downstream,
      smallestNextAction: _smallestNextAction(
        workspaceTasksById[primaryBlockerId],
        projectionTasksById[primaryBlockerId],
        workspaceTask,
        status,
      ),
      agentAssistOptions: agentOptions,
      missingContext: gaps.map((gap) => gap.field).toList(),
      evidenceIds: <String>{
        for (final edge in relationEdges) ...edge.evidenceIds,
        ...?projectionTask?.evidenceIds,
      }.toList(),
      confidence: _planConfidence(relationEdges, scoresByTaskId[taskId]),
      explanation: _planExplanation(
        taskTitle: titleForTaskId(taskId),
        primaryBlockerTitle: primaryBlockerId.isEmpty
            ? ''
            : titleForTaskId(primaryBlockerId),
        downstreamCount: downstream.length,
      ),
    );
  }

  /// Returns a concise explanation for one task and insight.
  String explainTaskInsight(String taskId, String insightId) {
    final candidate = candidateForTask(taskId, insightId);
    if (candidate != null && candidate.explanation.isNotEmpty) {
      return candidate.explanation;
    }
    final gaps = metadataGapsFor(taskId);
    if (gaps.isNotEmpty) {
      return TaskInsightExplanations.metadataGap(gaps.first);
    }
    return 'No specific insight explanation is available for this backlog item yet.';
  }

  /// Returns a score profile for a graph task id.
  TaskInsightScoreProfile? scoresFor(String taskId) {
    return scoresByTaskId[taskId];
  }

  /// Returns true when the id resolves to a visible task or an anchor.
  bool isVisibleEndpoint(String endpointId) {
    return endpointId.startsWith('anchor:') ||
        workspaceTaskForId(endpointId) != null ||
        projectionTasksById.containsKey(endpointId);
  }

  /// Returns a task's first facet label for a dimension.
  String facetLabelForTask(String taskId, String dimension) {
    final projectionTask = projectionTasksById[taskId];
    if (projectionTask == null) {
      return '';
    }
    for (final facetId in projectionTask.facetIds) {
      final facet = facetsById[facetId];
      if (facet != null && facet.dimension == dimension) {
        return facet.label;
      }
    }
    return '';
  }

  /// Returns whether a task should appear in active insight queries.
  bool isActiveTask(String taskId) {
    final workspaceTask = workspaceTasksById[taskId];
    final projectionTask = projectionTasksById[taskId];
    final status = workspaceTask?.status ?? projectionTask?.status ?? '';
    return status != 'done' &&
        status != 'canceled' &&
        workspaceTask?.done != true;
  }
}

/// Returns every task id known to either queue or projection graph.
Set<String> _allTaskIds(
  Map<String, WorkspaceTask> workspaceTasksById,
  Map<String, TaskProjectionTask> projectionTasksById,
) {
  return <String>{...workspaceTasksById.keys, ...projectionTasksById.keys};
}

/// Converts explicit relation records into canonical projection edges.
List<TaskProjectionEdge> _normalizeRelationRecords({
  required List<TaskProjectionEdge> graphEdges,
  required List<TaskRelationRecord> taskRelations,
}) {
  final output = <TaskProjectionEdge>[...graphEdges];
  for (final relation in taskRelations) {
    if (relation.fromTaskId.isEmpty || relation.toTaskId.isEmpty) {
      continue;
    }
    output.add(
      TaskProjectionEdge(
        id: relation.id,
        fromTaskId: relation.fromTaskId,
        toTaskId: relation.toTaskId,
        relationType: relation.relationType,
        source: relation.source.isEmpty ? 'explicit' : relation.source,
        sourceKind: 'explicit',
        confidence: relation.confidence,
        explanation: relation.explanation,
        actor: relation.actor,
        createdAt: relation.createdAt,
        updatedAt: relation.updatedAt,
      ),
    );
  }
  return output;
}

/// Records relation direction in blocker and downstream adjacency maps.
void _indexBlockingDirection(
  TaskProjectionEdge edge,
  Map<String, LinkedHashSet<String>> blockersByTaskId,
  Map<String, LinkedHashSet<String>> blockedByTaskId,
  TaskInsightPolicy policy,
) {
  if (edge.confidence > 0 &&
      edge.confidence < policy.relationConfidenceFloor &&
      edge.source != 'explicit') {
    return;
  }
  void add(String blockerId, String blockedId) {
    if (blockerId.isEmpty || blockedId.isEmpty || blockerId == blockedId) {
      return;
    }
    blockersByTaskId
        .putIfAbsent(blockedId, () => LinkedHashSet<String>())
        .add(blockerId);
    blockedByTaskId
        .putIfAbsent(blockerId, () => LinkedHashSet<String>())
        .add(blockedId);
  }

  switch (edge.relationType) {
    case 'blocks':
      add(edge.fromTaskId, edge.toTaskId);
      break;
    case 'depends_on':
      add(edge.toTaskId, edge.fromTaskId);
      break;
    case 'unblocks':
    case 'enables':
      add(edge.fromTaskId, edge.toTaskId);
      break;
    case 'waiting_on':
    case 'requires_context_from':
      add(edge.toTaskId, edge.fromTaskId);
      break;
  }
}

/// Returns task ids that participate in a blocking dependency cycle.
Set<String> _dependencyCycleTaskIds(
  List<TaskProjectionEdge> edges,
  TaskInsightPolicy policy,
) {
  final graph = <String, List<String>>{};
  void add(String fromTaskId, String toTaskId, TaskProjectionEdge edge) {
    if (fromTaskId.isEmpty ||
        toTaskId.isEmpty ||
        fromTaskId == toTaskId ||
        (edge.confidence > 0 &&
            edge.confidence < policy.relationConfidenceFloor &&
            edge.source != 'explicit')) {
      return;
    }
    graph.putIfAbsent(fromTaskId, () => <String>[]).add(toTaskId);
  }

  for (final edge in edges) {
    switch (edge.relationType) {
      case 'depends_on':
      case 'waiting_on':
      case 'requires_context_from':
        add(edge.fromTaskId, edge.toTaskId, edge);
        break;
      case 'blocks':
      case 'unblocks':
      case 'enables':
        add(edge.toTaskId, edge.fromTaskId, edge);
        break;
    }
  }

  final visiting = <String>{};
  final visited = <String>{};
  final cycles = <String>{};
  void visit(String taskId, List<String> path) {
    if (visiting.contains(taskId)) {
      final start = path.indexOf(taskId);
      if (start >= 0) {
        cycles.addAll(path.skip(start));
      }
      cycles.add(taskId);
      return;
    }
    if (visited.contains(taskId)) {
      return;
    }
    visiting.add(taskId);
    for (final next in graph[taskId] ?? const <String>[]) {
      visit(next, <String>[...path, taskId]);
    }
    visiting.remove(taskId);
    visited.add(taskId);
  }

  for (final taskId in graph.keys) {
    visit(taskId, const <String>[]);
  }
  return cycles;
}

/// Returns downstream value unlocked by a task.
double _downstreamValue({
  required String taskId,
  required Map<String, LinkedHashSet<String>> blockedByTaskId,
  required Map<String, TaskProjectionTask> projectionTasksById,
  required TaskInsightPolicy policy,
}) {
  final visited = <String>{};
  final queue = Queue<_TraversalNode>();
  for (final next in blockedByTaskId[taskId] ?? const <String>{}) {
    queue.add(_TraversalNode(next, 1));
  }
  var total = 0.0;
  while (queue.isNotEmpty && visited.length < policy.downstreamMaxVisited) {
    final current = queue.removeFirst();
    if (current.depth > policy.downstreamMaxDepth ||
        !visited.add(current.taskId)) {
      continue;
    }
    final projection = projectionTasksById[current.taskId];
    final reward = projection?.scores.reward ?? 0.35;
    final pressure = projection?.scores.pressure ?? 0.35;
    total += reward * pressure / current.depth;
    for (final next in blockedByTaskId[current.taskId] ?? const <String>{}) {
      queue.add(_TraversalNode(next, current.depth + 1));
    }
  }
  return _clamp01(total / 1.6);
}

/// _TraversalNode stores a bounded graph traversal queue item.
class _TraversalNode {
  const _TraversalNode(this.taskId, this.depth);

  final String taskId;
  final int depth;
}

/// Returns a numeric commitment hardness score.
double _commitmentHardness(List<TaskCommitment> commitments) {
  var score = 0.0;
  for (final commitment in commitments) {
    final hardness = commitment.hardness.toLowerCase();
    final consequence = commitment.consequence.toLowerCase();
    if (hardness.contains('hard') || hardness.contains('must')) {
      score = math.max(score, 0.82);
    } else if (hardness.contains('soft')) {
      score = math.max(score, 0.48);
    }
    if (consequence.contains('legal') || consequence.contains('client')) {
      score = math.max(score, 0.76);
    } else if (consequence.isNotEmpty) {
      score = math.max(score, 0.55);
    }
  }
  return score;
}

/// Returns blocker effort from estimate and projection score.
double _blockerEffort(WorkspaceTask? workspaceTask, TaskProjectionTask? task) {
  final score = task?.scores.blockerEffort ?? task?.scores.humanEffort ?? 0;
  if (score > 0) {
    return _clamp01(score);
  }
  final estimate = workspaceTask?.estimateMinutes ?? task?.estimateMinutes ?? 0;
  if (estimate <= 0) {
    return 0.30;
  }
  return _clamp01(estimate / 180);
}

/// Builds metadata gap maps from source and derived gaps.
Map<String, List<TaskMetadataGapRecord>> _metadataGapsByTaskId({
  required List<TaskMetadataGapRecord> graphGaps,
  required List<TaskMetadataSuggestion> metadataSuggestions,
  required Map<String, WorkspaceTask> workspaceTasksById,
  required Map<String, TaskProjectionTask> projectionTasksById,
  required Map<String, TaskInsightScoreProfile> scoresByTaskId,
  required TaskInsightPolicy policy,
  required Set<String> cycleTaskIds,
}) {
  final gaps = <String, List<TaskMetadataGapRecord>>{};
  for (final gap in graphGaps) {
    gaps.putIfAbsent(gap.taskId, () => <TaskMetadataGapRecord>[]).add(gap);
  }
  for (final taskId in cycleTaskIds) {
    gaps
        .putIfAbsent(taskId, () => <TaskMetadataGapRecord>[])
        .add(
          TaskMetadataGapRecord(
            id: 'gap:$taskId:dependency_cycle',
            taskId: taskId,
            field: 'dependency_cycle',
            severity: 'high',
            blocksInsights: const <String>[TaskInsightIds.quickUnblocks],
            message: 'Dependency cycle prevents reliable unblock analysis.',
            proposedAction: 'Review dependency directions and break the cycle.',
            confidence: 0.90,
          ),
        );
  }
  for (final suggestion in metadataSuggestions) {
    final taskId = suggestion.taskId;
    if (suggestion.owner.isNotEmpty ||
        suggestion.context.isNotEmpty ||
        suggestion.domain.isNotEmpty) {
      gaps
          .putIfAbsent(taskId, () => <TaskMetadataGapRecord>[])
          .add(
            TaskMetadataGapRecord(
              id: 'gap:$taskId:suggested_metadata',
              taskId: taskId,
              field: 'metadata_review',
              severity: 'info',
              blocksInsights: const <String>[TaskInsightIds.metadataGaps],
              message: suggestion.explanation,
              proposedAction: 'Review suggested context metadata.',
              confidence: suggestion.confidence,
            ),
          );
    }
  }
  for (final entry in scoresByTaskId.entries) {
    final taskId = entry.key;
    final score = entry.value;
    final workspaceTask = workspaceTasksById[taskId];
    final projectionTask = projectionTasksById[taskId];
    if (score.metadataCompleteness < policy.metadataCompletenessFloor) {
      for (final field in _missingFields(workspaceTask, projectionTask)) {
        gaps
            .putIfAbsent(taskId, () => <TaskMetadataGapRecord>[])
            .add(
              TaskMetadataGapRecord(
                id: 'gap:$taskId:$field',
                taskId: taskId,
                field: field,
                severity: field == 'agent_safety' ? 'medium' : 'info',
                blocksInsights: _insightsBlockedByField(field),
                message:
                    'Missing ${field.replaceAll('_', ' ')} limits insight quality.',
                proposedAction: 'Add ${field.replaceAll('_', ' ')} metadata.',
                confidence: 0.70,
              ),
            );
      }
    }
  }
  return gaps;
}

/// Returns derived missing fields for known task models.
List<String> _missingFields(
  WorkspaceTask? task,
  TaskProjectionTask? projection,
) {
  final missing = <String>[];
  if ((task?.owner ?? projection?.owner ?? '').isEmpty) {
    missing.add('person');
  }
  if ((task?.context ?? projection?.context ?? '').isEmpty) {
    missing.add('context');
  }
  if ((task?.estimateMinutes ?? projection?.estimateMinutes ?? 0) <= 0) {
    missing.add('estimate_minutes');
  }
  if ((projection?.valueType ?? '').isEmpty) {
    missing.add('value_type');
  }
  if ((projection?.obligationLevel ?? '').isEmpty) {
    missing.add('obligation');
  }
  if ((projection?.agentSafety ?? '').isEmpty) {
    missing.add('agent_safety');
  }
  return missing;
}

/// Returns insight ids blocked by one metadata field.
List<String> _insightsBlockedByField(String field) {
  return switch (field) {
    'person' => const <String>[TaskInsightIds.quickUnblocks],
    'estimate_minutes' => const <String>[
      TaskInsightIds.agentHandoff,
      TaskInsightIds.quickUnblocks,
    ],
    'value_type' => const <String>[TaskInsightIds.nextWeekHighValue],
    'obligation' => const <String>[TaskInsightIds.agentHandoff],
    'agent_safety' => const <String>[TaskInsightIds.agentHandoff],
    _ => const <String>[TaskInsightIds.metadataGaps],
  };
}

/// Builds all named insight candidates.
Map<String, List<TaskInsightCandidate>> _buildCandidates({
  required Map<String, WorkspaceTask> workspaceTasksById,
  required Map<String, TaskProjectionTask> projectionTasksById,
  required Map<String, TaskInsightScoreProfile> scoresByTaskId,
  required Map<String, LinkedHashSet<String>> blockedByTaskId,
  required Map<String, LinkedHashSet<String>> blockersByTaskId,
  required Map<String, List<TaskMetadataGapRecord>> metadataGapsByTaskId,
  required TaskInsightPolicy policy,
  required DateTime now,
}) {
  final agent = <TaskInsightCandidate>[];
  final nextWeek = <TaskInsightCandidate>[];
  final unblocks = <TaskInsightCandidate>[];
  final gaps = <TaskInsightCandidate>[];
  final highRisk = <TaskInsightCandidate>[];
  for (final taskId in _allTaskIds(workspaceTasksById, projectionTasksById)) {
    final workspaceTask = workspaceTasksById[taskId];
    final projectionTask = projectionTasksById[taskId];
    final scores = scoresByTaskId[taskId];
    if (scores == null || !_isActive(workspaceTask, projectionTask)) {
      continue;
    }
    if (_isAgentHandoffCandidate(scores, policy)) {
      agent.add(
        _candidate(
          insightId: TaskInsightIds.agentHandoff,
          taskId: taskId,
          score: _agentHandoffRank(scores),
          severity:
              scores.agentSafety >= policy.safeAgentThreshold &&
                  scores.handoffReadiness >= policy.handoffReadinessThreshold
              ? 'info'
              : 'warning',
          matchedRules: <String>[
            'must_do',
            'agent_fit',
            if (scores.humanEffort <= 0.45) 'low_human_effort',
          ],
          missingRules: <String>[
            if (scores.agentSafety < policy.safeAgentThreshold) 'agent_safety',
            if (scores.handoffReadiness < policy.handoffReadinessThreshold)
              'handoff_context',
          ],
          explanation: TaskInsightExplanations.agentHandoff(
            workspaceTask: workspaceTask,
            projectionTask: projectionTask,
            scores: scores,
          ),
          confidence: scores.confidence,
        ),
      );
    }
    if (_dueWindow(workspaceTask?.dueAt ?? projectionTask?.dueAt, now) ==
            'next-week' &&
        _isHighValue(scores, projectionTask, policy)) {
      nextWeek.add(
        _candidate(
          insightId: TaskInsightIds.nextWeekHighValue,
          taskId: taskId,
          score: _nextWeekRank(scores),
          severity: scores.consequence >= 0.70 ? 'warning' : 'info',
          matchedRules: <String>['next_week', 'high_value'],
          explanation: TaskInsightExplanations.nextWeekHighValue(
            workspaceTask: workspaceTask,
            projectionTask: projectionTask,
            scores: scores,
          ),
          confidence: scores.confidence,
        ),
      );
    }
    final downstream = blockedByTaskId[taskId] ?? <String>{};
    if (downstream.isNotEmpty &&
        scores.blockerEffort <= policy.quickUnblockEffortCeiling &&
        scores.downstreamValue >= policy.quickUnblockDownstreamThreshold &&
        scores.confidence >= policy.confidenceFloor) {
      unblocks.add(
        _candidate(
          insightId: TaskInsightIds.quickUnblocks,
          taskId: taskId,
          score: _quickUnblockRank(scores),
          severity: downstream.length >= 3 ? 'warning' : 'info',
          matchedRules: const <String>['blocks_downstream', 'low_effort'],
          explanation: TaskInsightExplanations.quickUnblock(
            downstreamCount: downstream.length,
            scores: scores,
          ),
          confidence: scores.confidence,
        ),
      );
    }
    final taskGaps =
        metadataGapsByTaskId[taskId] ?? const <TaskMetadataGapRecord>[];
    if (taskGaps.isNotEmpty) {
      gaps.add(
        _candidate(
          insightId: TaskInsightIds.metadataGaps,
          taskId: taskId,
          score: 1 - scores.metadataCompleteness,
          severity: taskGaps.any((gap) => gap.severity == 'medium')
              ? 'warning'
              : 'info',
          matchedRules: const <String>['missing_metadata'],
          missingRules: taskGaps.map((gap) => gap.field).toSet().toList(),
          explanation: TaskInsightExplanations.metadataGap(taskGaps.first),
          confidence: scores.confidence,
        ),
      );
    }
    if (scores.risk >= policy.highRiskThreshold &&
        scores.confidence < policy.confidenceFloor + 0.10) {
      highRisk.add(
        _candidate(
          insightId: TaskInsightIds.highRiskLowConfidence,
          taskId: taskId,
          score: scores.risk * (1 - scores.confidence),
          severity: 'warning',
          matchedRules: const <String>['high_risk', 'low_confidence'],
          explanation:
              'High risk with low confidence. Confirm context metadata before relying on downstream insights.',
          confidence: scores.confidence,
        ),
      );
    }
  }
  return <String, List<TaskInsightCandidate>>{
    TaskInsightIds.agentHandoff: _rank(agent),
    TaskInsightIds.nextWeekHighValue: _rank(nextWeek),
    TaskInsightIds.quickUnblocks: _rank(unblocks),
    TaskInsightIds.metadataGaps: _rank(gaps),
    TaskInsightIds.highRiskLowConfidence: _rank(highRisk),
  };
}

/// Returns whether task status is non-terminal.
bool _isActive(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? projectionTask,
) {
  final status = workspaceTask?.status ?? projectionTask?.status ?? '';
  return workspaceTask?.done != true &&
      status != 'done' &&
      status != 'canceled';
}

/// Returns whether scores satisfy agent handoff matching.
bool _isAgentHandoffCandidate(
  TaskInsightScoreProfile scores,
  TaskInsightPolicy policy,
) {
  return scores.obligation >= policy.obligationThreshold &&
      (scores.reward <= policy.lowHumanValueCeiling ||
          scores.humanEffort <= 0.45) &&
      scores.agentFit >= policy.agentFitThreshold &&
      scores.risk <= 0.70 &&
      scores.confidence >= policy.confidenceFloor;
}

/// Returns whether scores or controlled values indicate high value.
bool _isHighValue(
  TaskInsightScoreProfile scores,
  TaskProjectionTask? projectionTask,
  TaskInsightPolicy policy,
) {
  final valueType = projectionTask?.valueType ?? '';
  return scores.reward >= policy.highRewardThreshold ||
      scores.consequence >= 0.70 ||
      scores.commitmentHardness >= 0.70 ||
      const <String>{
        'revenue',
        'legal',
        'client',
        'safety',
        'reputation',
      }.contains(valueType);
}

/// Builds an unranked candidate.
TaskInsightCandidate _candidate({
  required String insightId,
  required String taskId,
  required double score,
  required String severity,
  List<String> matchedRules = const <String>[],
  List<String> missingRules = const <String>[],
  String explanation = '',
  double confidence = 0,
}) {
  return TaskInsightCandidate(
    insightId: insightId,
    taskId: taskId,
    rank: 0,
    score: _clamp01(score),
    severity: severity,
    matchedRules: matchedRules,
    missingRules: missingRules,
    explanation: explanation,
    confidence: confidence,
  );
}

/// Returns candidates sorted by score with stable ranks.
List<TaskInsightCandidate> _rank(List<TaskInsightCandidate> candidates) {
  final sorted = candidates.toList()
    ..sort((left, right) {
      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return left.taskId.compareTo(right.taskId);
    });
  return <TaskInsightCandidate>[
    for (var index = 0; index < sorted.length; index++)
      TaskInsightCandidate(
        insightId: sorted[index].insightId,
        taskId: sorted[index].taskId,
        rank: index,
        score: sorted[index].score,
        severity: sorted[index].severity,
        matchedRules: sorted[index].matchedRules,
        missingRules: sorted[index].missingRules,
        explanation: sorted[index].explanation,
        evidenceIds: sorted[index].evidenceIds,
        confidence: sorted[index].confidence,
      ),
  ];
}

/// Ranks agent handoff candidates.
double _agentHandoffRank(TaskInsightScoreProfile scores) {
  return _clamp01(
    0.30 * scores.obligation +
        0.25 * scores.handoffReadiness +
        0.20 * scores.agentSafety +
        0.15 * scores.agentFit +
        0.10 * scores.timePressure -
        0.20 * scores.reward -
        0.15 * scores.risk,
  );
}

/// Ranks next-week high-value candidates.
double _nextWeekRank(TaskInsightScoreProfile scores) {
  return _clamp01(
    0.35 * scores.reward +
        0.25 * scores.consequence +
        0.20 * scores.commitmentHardness +
        0.10 * scores.pressure +
        0.10 * scores.downstreamValue,
  );
}

/// Ranks quick unblock candidates.
double _quickUnblockRank(TaskInsightScoreProfile scores) {
  return _clamp01(
    0.45 * scores.unblockLeverage +
        0.25 * scores.downstreamValue +
        0.15 * scores.pressure +
        0.10 * scores.confidence -
        0.15 * scores.blockerEffort,
  );
}

/// Builds summaries for each named insight query.
List<TaskInsightQuerySummary> _buildSummaries({
  required Map<String, List<TaskInsightCandidate>> candidatesByInsightId,
  required Map<String, WorkspaceTask> workspaceTasksById,
}) {
  const labels = <String, String>{
    TaskInsightIds.agentHandoff: 'Agent handoff',
    TaskInsightIds.nextWeekHighValue: 'Next week high value',
    TaskInsightIds.quickUnblocks: 'Quick unblocks',
    TaskInsightIds.metadataGaps: 'Metadata gaps',
    TaskInsightIds.highRiskLowConfidence: 'Risk gaps',
  };
  const questions = <String, String>{
    TaskInsightIds.agentHandoff:
        'What low-value must-do work can I safely hand off?',
    TaskInsightIds.nextWeekHighValue:
        'What high-value work is coming up next week?',
    TaskInsightIds.quickUnblocks: 'What can I unblock quickly?',
    TaskInsightIds.metadataGaps:
        'What prevents Agent Awesome from giving better insights?',
    TaskInsightIds.highRiskLowConfidence: 'What looks risky but uncertain?',
  };
  return <TaskInsightQuerySummary>[
    for (final entry in labels.entries)
      _summary(
        id: entry.key,
        label: entry.value,
        question: questions[entry.key] ?? '',
        candidates:
            candidatesByInsightId[entry.key] ?? const <TaskInsightCandidate>[],
        workspaceTasksById: workspaceTasksById,
      ),
  ];
}

/// Builds one insight summary.
TaskInsightQuerySummary _summary({
  required String id,
  required String label,
  required String question,
  required List<TaskInsightCandidate> candidates,
  required Map<String, WorkspaceTask> workspaceTasksById,
}) {
  final minutes = candidates.fold<int>(0, (total, candidate) {
    return total + (workspaceTasksById[candidate.taskId]?.estimateMinutes ?? 0);
  });
  final warningCount = candidates
      .where((candidate) => candidate.severity == 'warning')
      .length;
  return TaskInsightQuerySummary(
    id: id,
    label: label,
    question: question,
    count: candidates.length,
    warningCount: warningCount,
    estimatedMinutes: minutes,
    primaryTaskIds: candidates
        .take(5)
        .map((candidate) => candidate.taskId)
        .toList(),
    explanation: _summaryExplanation(
      label,
      candidates.length,
      warningCount,
      minutes,
    ),
  );
}

/// Builds short text for an insight summary.
String _summaryExplanation(String label, int count, int warnings, int minutes) {
  final parts = <String>[
    '$count ${count == 1 ? 'backlog item' : 'backlog items'}',
  ];
  if (warnings > 0) {
    parts.add('$warnings need review');
  }
  if (minutes > 0) {
    parts.add('${minutes}m estimated');
  }
  return '$label: ${parts.join(' · ')}';
}

/// Returns a coarse due window.
String _dueWindow(DateTime? dueAt, DateTime now) {
  if (dueAt == null) {
    return 'no-due-date';
  }
  final localDue = DateTime(dueAt.year, dueAt.month, dueAt.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = localDue.difference(today).inDays;
  if (days < 0) {
    return 'overdue';
  }
  if (days == 0) {
    return 'today';
  }
  if (days == 1) {
    return 'tomorrow';
  }
  if (days < 7) {
    return 'this-week';
  }
  if (days < 14) {
    return 'next-week';
  }
  return 'later';
}

/// Freezes a linked-hash-set adjacency map.
Map<String, List<String>> _freezeSetMap(
  Map<String, LinkedHashSet<String>> input,
) {
  return Map<String, List<String>>.unmodifiable(
    input.map(
      (key, value) => MapEntry<String, List<String>>(key, value.toList()),
    ),
  );
}

/// Builds a projection coverage warning.
String _coverageMessage(
  Set<String> queueTaskIds,
  Set<String> projectionTaskIds,
) {
  if (queueTaskIds.isEmpty || projectionTaskIds.isEmpty) {
    return '';
  }
  final missingFromProjection = queueTaskIds.difference(projectionTaskIds);
  final missingFromQueue = projectionTaskIds.difference(queueTaskIds);
  if (missingFromProjection.isEmpty && missingFromQueue.isEmpty) {
    return '';
  }
  final parts = <String>[];
  if (missingFromProjection.isNotEmpty) {
    parts.add(
      '${missingFromProjection.length} queue backlog items are missing from insight views',
    );
  }
  if (missingFromQueue.isNotEmpty) {
    parts.add(
      '${missingFromQueue.length} insight backlog items are hidden from Queue',
    );
  }
  return 'Projection coverage warning: ${parts.join('; ')}.';
}

/// Returns queue task ids that should be represented by insight projections.
Set<String> _activeWorkspaceTaskIds(
  Map<String, WorkspaceTask> workspaceTasksById,
  Map<String, TaskProjectionTask> projectionTasksById,
) {
  return <String>{
    for (final entry in workspaceTasksById.entries)
      if (_isActive(entry.value, projectionTasksById[entry.key])) entry.key,
  };
}

/// Returns whether an incoming edge blocks the selected task.
bool _edgeBlocksTask(TaskProjectionEdge edge, String taskId) {
  return (edge.relationType == 'blocks' && edge.toTaskId == taskId) ||
      (edge.relationType == 'depends_on' && edge.fromTaskId == taskId) ||
      (edge.relationType == 'waiting_on' && edge.fromTaskId == taskId) ||
      (edge.relationType == 'requires_context_from' &&
          edge.fromTaskId == taskId);
}

/// Returns whether an outgoing edge makes the selected task wait.
bool _edgeMakesTaskWait(TaskProjectionEdge edge, String taskId) {
  return edge.fromTaskId == taskId &&
      (edge.relationType == 'depends_on' ||
          edge.relationType == 'waiting_on' ||
          edge.relationType == 'requires_context_from');
}

/// Chooses the highest-value blocker.
String _primaryBlocker(
  List<String> blockerIds,
  Map<String, TaskInsightScoreProfile> scoresByTaskId,
  Map<String, TaskProjectionTask> projectionTasksById,
) {
  if (blockerIds.isEmpty) {
    return '';
  }
  final sorted = blockerIds.toList()
    ..sort((left, right) {
      final leftScore =
          scoresByTaskId[left]?.unblockLeverage ??
          projectionTasksById[left]?.scores.elevation ??
          0;
      final rightScore =
          scoresByTaskId[right]?.unblockLeverage ??
          projectionTasksById[right]?.scores.elevation ??
          0;
      return rightScore.compareTo(leftScore);
    });
  return sorted.first;
}

/// Returns owner label for a canonical blocker.
String _ownerFor(
  String taskId,
  Map<String, WorkspaceTask> workspaceTasksById,
  Map<String, TaskProjectionTask> projectionTasksById,
) {
  return workspaceTasksById[taskId]?.owner ??
      projectionTasksById[taskId]?.owner ??
      '';
}

/// Builds agent assist options for an unblock plan.
List<String> _agentAssistOptions(TaskInsightScoreProfile? scores) {
  if (scores == null || scores.agentFit < 0.45) {
    return const <String>[];
  }
  return const <String>[
    'Draft a concise blocker request.',
    'Collect linked notes into a handoff brief.',
    'Prepare a checklist for human review.',
  ];
}

/// Builds the smallest next action for an unblock plan.
String _smallestNextAction(
  WorkspaceTask? blockerTask,
  TaskProjectionTask? blockerProjection,
  WorkspaceTask? selectedTask,
  String selectedStatus,
) {
  final blockerTitle = blockerTask?.title ?? blockerProjection?.title ?? '';
  if (blockerTitle.isNotEmpty) {
    return 'Clear or clarify "$blockerTitle" first.';
  }
  if (selectedStatus == 'waiting') {
    return 'Confirm what you are waiting on and who owns the next response.';
  }
  if (selectedStatus == 'blocked') {
    return 'Name the blocker and add or confirm the dependency relation.';
  }
  if ((selectedTask?.description ?? '').isNotEmpty) {
    return 'Use the context notes to choose the next concrete action.';
  }
  return 'Start by turning the title into one concrete next action.';
}

/// Computes unblock plan confidence.
double _planConfidence(
  List<TaskProjectionEdge> relations,
  TaskInsightScoreProfile? scores,
) {
  if (relations.isEmpty) {
    return scores?.confidence ?? 0.35;
  }
  final relationConfidence = relations
      .map((edge) => edge.confidence == 0 ? 0.60 : edge.confidence)
      .reduce(math.max);
  return math.min(relationConfidence, scores?.confidence ?? relationConfidence);
}

/// Builds a compact unblock plan explanation.
String _planExplanation({
  required String taskTitle,
  required String primaryBlockerTitle,
  required int downstreamCount,
}) {
  if (primaryBlockerTitle.isNotEmpty) {
    return '$taskTitle is blocked by $primaryBlockerTitle and affects $downstreamCount downstream ${downstreamCount == 1 ? 'backlog item' : 'backlog items'}.';
  }
  return 'No explicit blocker is known yet; add blocker metadata to improve this plan.';
}

/// Clamps a score into the 0-1 range.
double _clamp01(num value) {
  return value.clamp(0, 1).toDouble();
}
