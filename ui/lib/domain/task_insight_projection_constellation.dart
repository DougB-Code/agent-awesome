/// Constellation projection helpers for indexed task insights.
part of 'task_projection_adapters.dart';

List<String> _constellationTaskIds(
  TaskInsightIndex index,
  TaskConstellationInsightMode mode,
  String selectedTaskId,
) {
  if (mode == TaskConstellationInsightMode.unblock &&
      selectedTaskId.isNotEmpty) {
    return <String>{
      selectedTaskId,
      ...index.blockersFor(selectedTaskId),
      ...index.downstreamTasksFor(selectedTaskId),
      for (final blocker in index.blockersFor(selectedTaskId))
        ...index.downstreamTasksFor(blocker),
    }.where(index.isActiveTask).toList();
  }
  final ids = switch (mode) {
    TaskConstellationInsightMode.map => _activeTaskIds(index),
    TaskConstellationInsightMode.criticalPath =>
      _criticalPathTaskIds(index).isEmpty
          ? _dependencyTaskIds(index)
          : _criticalPathTaskIds(index),
    TaskConstellationInsightMode.unblock =>
      index
          .tasksForInsight(TaskInsightIds.quickUnblocks)
          .expand(
            (candidate) => <String>[
              candidate.taskId,
              ...index.downstreamTasksFor(candidate.taskId),
            ],
          )
          .toSet()
          .toList(),
    TaskConstellationInsightMode.handoff =>
      index
          .tasksForInsight(TaskInsightIds.agentHandoff)
          .map((candidate) => candidate.taskId)
          .toList(),
    TaskConstellationInsightMode.riskOwners => _riskOwnerTaskIds(index),
    TaskConstellationInsightMode.leverage =>
      index
          .tasksForInsight(TaskInsightIds.quickUnblocks)
          .map((candidate) => candidate.taskId)
          .toList(),
  };
  if (ids.isNotEmpty || mode == TaskConstellationInsightMode.map) {
    return ids;
  }
  return _activeTaskIds(index);
}

/// Builds task relation edges for one constellation lens.
List<TaskConstellationEdge> _constellationEdges(
  TaskInsightIndex index,
  TaskConstellationInsightMode mode,
  Set<String> visibleIds,
) {
  if (mode == TaskConstellationInsightMode.criticalPath) {
    return _criticalPathEdges(index, visibleIds);
  }
  if (mode == TaskConstellationInsightMode.riskOwners) {
    return _riskOwnerEdges(index, visibleIds);
  }
  return <TaskConstellationEdge>[
    for (final edge in index.edges)
      if (visibleIds.contains(edge.fromTaskId) &&
          visibleIds.contains(edge.toTaskId))
        _constellationEdge(edge),
  ];
}

/// Returns active task ids that participate in dependency relations.
List<String> _dependencyTaskIds(TaskInsightIndex index) {
  final ids = <String>{};
  for (final edge in index.edges) {
    if (!_isDependencyRelation(edge.relationType)) {
      continue;
    }
    if (index.isActiveTask(edge.fromTaskId)) {
      ids.add(edge.fromTaskId);
    }
    if (index.isActiveTask(edge.toTaskId)) {
      ids.add(edge.toTaskId);
    }
  }
  return ids.toList()..sort();
}

/// Returns the longest active dependency path by effort and risk.
List<String> _criticalPathTaskIds(TaskInsightIndex index) {
  final links = _dependencyLinks(index);
  if (links.isEmpty) {
    return const <String>[];
  }
  final byFrom = <String, List<_DependencyLink>>{};
  for (final link in links) {
    byFrom.putIfAbsent(link.fromTaskId, () => <_DependencyLink>[]).add(link);
  }
  final taskIds = <String>{
    for (final link in links) ...<String>[link.fromTaskId, link.toTaskId],
  };
  final memo = <String, _WeightedPath>{};
  final visiting = <String>{};
  _WeightedPath best = const _WeightedPath(taskIds: <String>[], score: 0);
  for (final taskId in taskIds) {
    final candidate = _bestDependencyPathFrom(
      index,
      taskId,
      byFrom,
      memo,
      visiting,
    );
    if (candidate.score > best.score) {
      best = candidate;
    }
  }
  return best.taskIds.length < 2 ? const <String>[] : best.taskIds;
}

/// Returns the critical path rank for deterministic lens placement.
double _criticalPathRank(TaskInsightIndex index, String taskId) {
  final path = _criticalPathTaskIds(index);
  final position = path.indexOf(taskId);
  if (position < 0 || path.length <= 1) {
    return 0.5;
  }
  return position / (path.length - 1);
}

/// Builds highlighted critical-path edges plus nearby dependency context.
List<TaskConstellationEdge> _criticalPathEdges(
  TaskInsightIndex index,
  Set<String> visibleIds,
) {
  final path = _criticalPathTaskIds(index);
  final pathPairs = <String>{
    for (var index = 0; index < path.length - 1; index++)
      '${path[index]}->${path[index + 1]}',
  };
  final output = <TaskConstellationEdge>[];
  final seen = <String>{};
  for (final link in _dependencyLinks(index)) {
    if (!visibleIds.contains(link.fromTaskId) ||
        !visibleIds.contains(link.toTaskId)) {
      continue;
    }
    final pair = '${link.fromTaskId}->${link.toTaskId}';
    final critical = pathPairs.contains(pair);
    if (!critical && output.length >= 96) {
      continue;
    }
    final edge = TaskConstellationEdge(
      id: link.id,
      fromTaskId: link.fromTaskId,
      toTaskId: link.toTaskId,
      relationType: link.originalRelationType,
      confidence: critical ? 1 : link.confidence,
      source: critical ? 'critical_path' : 'dependency_context',
      factSource: link.source,
      sourceKind: link.sourceKind,
      firewall: link.firewall,
      sensitivity: link.sensitivity,
      explanation: critical
          ? _criticalPathExplanation(index, link)
          : link.explanation,
      evidenceIds: link.evidenceIds,
      actor: link.actor,
      createdAt: link.createdAt,
      updatedAt: link.updatedAt,
      confirmedAt: link.confirmedAt,
      dismissedAt: link.dismissedAt,
    );
    final key =
        '${edge.fromTaskId}|${edge.toTaskId}|${edge.relationType}|${edge.source}';
    if (seen.add(key)) {
      output.add(edge);
    }
  }
  output.sort(
    (left, right) => _edgeSortKey(right).compareTo(_edgeSortKey(left)),
  );
  return output;
}

/// Returns high-risk task ids grouped by owner.
List<String> _riskOwnerTaskIds(TaskInsightIndex index) {
  final ids = <String>[];
  for (final taskId in _activeTaskIds(index)) {
    final scores = index.scoresFor(taskId);
    final risk = scores?.risk ?? index.workspaceTasksById[taskId]?.risk ?? 0;
    if (risk >= 0.55 || _materializedRisk(index, taskId)) {
      ids.add(taskId);
    }
  }
  ids.sort((left, right) {
    final rightScore = _riskOwnerScore(index, right);
    final leftScore = _riskOwnerScore(index, left);
    return rightScore.compareTo(leftScore);
  });
  return ids.take(36).toList();
}

/// Builds risk-owner edges that show where risk has become blockage.
List<TaskConstellationEdge> _riskOwnerEdges(
  TaskInsightIndex index,
  Set<String> visibleIds,
) {
  final output = <TaskConstellationEdge>[];
  for (final edge in index.edges) {
    if (!visibleIds.contains(edge.fromTaskId) ||
        !visibleIds.contains(edge.toTaskId) ||
        !_isDependencyRelation(edge.relationType)) {
      continue;
    }
    final materialized =
        _materializedRisk(index, edge.fromTaskId) ||
        _materializedRisk(index, edge.toTaskId);
    output.add(
      TaskConstellationEdge(
        id: edge.id,
        fromTaskId: edge.fromTaskId,
        toTaskId: edge.toTaskId,
        relationType: edge.relationType,
        confidence: materialized ? 1 : edge.confidence,
        source: materialized ? 'materialized_risk' : 'risk_context',
        factSource: edge.source,
        sourceKind: edge.sourceKind,
        firewall: edge.firewall,
        sensitivity: edge.sensitivity,
        explanation: materialized
            ? 'Risk has materialized on this dependency through blocked, waiting, or overdue work.'
            : edge.explanation,
        evidenceIds: edge.evidenceIds,
        actor: edge.actor,
        createdAt: edge.createdAt,
        updatedAt: edge.updatedAt,
        confirmedAt: edge.confirmedAt,
        dismissedAt: edge.dismissedAt,
      ),
    );
  }
  output.sort(
    (left, right) => _edgeSortKey(right).compareTo(_edgeSortKey(left)),
  );
  return output.take(96).toList();
}

/// Returns a constellation grouping category for one mode.
String _constellationCategory(
  TaskInsightIndex index,
  String taskId,
  TaskConstellationInsightMode mode,
) {
  final scores = index.scoresFor(taskId);
  return switch (mode) {
    TaskConstellationInsightMode.map => _firstNonEmpty(<String>[
      index.facetLabelForTask(taskId, 'context'),
      index.facetLabelForTask(taskId, 'attention'),
      'General',
    ]),
    TaskConstellationInsightMode.criticalPath => _projectForIndexedTask(
      index,
      taskId,
    ),
    TaskConstellationInsightMode.unblock =>
      index.downstreamTasksFor(taskId).isNotEmpty
          ? 'Unblocks Work'
          : index.blockersFor(taskId).isNotEmpty
          ? 'Blocked'
          : 'Related',
    TaskConstellationInsightMode.handoff =>
      (scores?.agentSafety ?? 0) >= index.policy.safeAgentThreshold &&
              (scores?.handoffReadiness ?? 0) >=
                  index.policy.handoffReadinessThreshold
          ? 'Ready for Agent'
          : 'Needs Review',
    TaskConstellationInsightMode.riskOwners => _ownerForIndexedTask(
      index,
      taskId,
    ),
    TaskConstellationInsightMode.leverage =>
      (scores?.unblockLeverage ?? 0) >= 0.66
          ? 'High Leverage'
          : (scores?.unblockLeverage ?? 0) >= 0.36
          ? 'Medium Leverage'
          : 'Low Leverage',
  };
}

/// Returns radius for constellation placement.
double _constellationRadius(
  TaskInsightIndex index,
  String taskId,
  TaskConstellationInsightMode mode,
  String selectedTaskId,
) {
  if (selectedTaskId == taskId) {
    return 0.02;
  }
  final scores = index.scoresFor(taskId);
  return switch (mode) {
    TaskConstellationInsightMode.map =>
      0.12 + (1 - (scores?.timePressure ?? 0)) * 0.26,
    TaskConstellationInsightMode.criticalPath =>
      0.08 + _criticalPathRank(index, taskId) * 0.045,
    TaskConstellationInsightMode.unblock =>
      index.blockersFor(selectedTaskId).contains(taskId) ? 0.18 : 0.32,
    TaskConstellationInsightMode.handoff =>
      0.18 + (1 - (scores?.handoffReadiness ?? 0)) * 0.22,
    TaskConstellationInsightMode.riskOwners =>
      0.12 + (scores?.risk ?? 0) * 0.26,
    TaskConstellationInsightMode.leverage =>
      0.14 + (1 - (scores?.unblockLeverage ?? 0)) * 0.30,
  };
}

/// Returns node size for constellation placement.
double _constellationSize(
  TaskInsightIndex index,
  String taskId,
  TaskConstellationInsightMode mode,
) {
  final scores = index.scoresFor(taskId);
  final relationScale = _clamp01(
    (index.blockersFor(taskId).length +
            index.downstreamTasksFor(taskId).length) /
        5,
  );
  return switch (mode) {
    TaskConstellationInsightMode.map =>
      0.18 + relationScale * 0.22 + (scores?.humanEffort ?? 0) * 0.12,
    TaskConstellationInsightMode.criticalPath =>
      0.22 + relationScale * 0.20 + (scores?.risk ?? 0) * 0.16,
    TaskConstellationInsightMode.unblock =>
      0.18 + (scores?.downstreamValue ?? 0) * 0.28,
    TaskConstellationInsightMode.handoff =>
      0.18 + (scores?.handoffReadiness ?? 0) * 0.22,
    TaskConstellationInsightMode.riskOwners =>
      0.20 + (scores?.risk ?? 0) * 0.28 + relationScale * 0.12,
    TaskConstellationInsightMode.leverage =>
      0.16 + (scores?.unblockLeverage ?? 0) * 0.30,
  };
}

/// Returns a constellation node explanation.
String _constellationExplanation(
  TaskInsightIndex index,
  String taskId,
  TaskConstellationInsightMode mode,
) {
  return switch (mode) {
    TaskConstellationInsightMode.map =>
      'Placed by context facets and sparse relations.',
    TaskConstellationInsightMode.criticalPath =>
      'Part of the longest active dependency path by estimated effort and risk.',
    TaskConstellationInsightMode.unblock => index.explainTaskInsight(
      taskId,
      TaskInsightIds.quickUnblocks,
    ),
    TaskConstellationInsightMode.handoff => index.explainTaskInsight(
      taskId,
      TaskInsightIds.agentHandoff,
    ),
    TaskConstellationInsightMode.riskOwners =>
      _materializedRisk(index, taskId)
          ? 'Risk has materialized through blocked, waiting, or overdue work.'
          : 'High-risk work grouped by responsible owner.',
    TaskConstellationInsightMode.leverage => index.explainTaskInsight(
      taskId,
      TaskInsightIds.quickUnblocks,
    ),
  };
}

/// Converts one projection edge into a constellation edge.
TaskConstellationEdge _constellationEdge(TaskProjectionEdge edge) {
  return TaskConstellationEdge(
    id: edge.id,
    fromTaskId: edge.fromTaskId,
    toTaskId: edge.toTaskId,
    relationType: edge.relationType,
    confidence: edge.confidence,
    source: edge.source,
    factSource: edge.source,
    sourceKind: edge.sourceKind,
    firewall: edge.firewall,
    sensitivity: edge.sensitivity,
    explanation: edge.explanation,
    evidenceIds: edge.evidenceIds,
    actor: edge.actor,
    createdAt: edge.createdAt,
    updatedAt: edge.updatedAt,
    confirmedAt: edge.confirmedAt,
    dismissedAt: edge.dismissedAt,
  );
}

/// Returns execution-order dependency links from normalized relation edges.
List<_DependencyLink> _dependencyLinks(TaskInsightIndex index) {
  final links = <_DependencyLink>[];
  for (final edge in index.edges) {
    final relation = edge.relationType.toLowerCase();
    if (relation == 'blocks' || relation == 'enables') {
      if (index.isActiveTask(edge.fromTaskId) &&
          index.isActiveTask(edge.toTaskId)) {
        links.add(
          _DependencyLink.fromEdge(edge, edge.fromTaskId, edge.toTaskId),
        );
      }
      continue;
    }
    if (relation == 'depends_on') {
      if (index.isActiveTask(edge.fromTaskId) &&
          index.isActiveTask(edge.toTaskId)) {
        links.add(
          _DependencyLink.fromEdge(edge, edge.toTaskId, edge.fromTaskId),
        );
      }
    }
  }
  return links;
}

/// Returns the best weighted path starting at one task.
_WeightedPath _bestDependencyPathFrom(
  TaskInsightIndex index,
  String taskId,
  Map<String, List<_DependencyLink>> byFrom,
  Map<String, _WeightedPath> memo,
  Set<String> visiting,
) {
  final cached = memo[taskId];
  if (cached != null) {
    return cached;
  }
  if (!visiting.add(taskId)) {
    return _WeightedPath(
      taskIds: <String>[taskId],
      score: _criticalPathNodeWeight(index, taskId),
    );
  }
  _WeightedPath bestChild = const _WeightedPath(taskIds: <String>[], score: 0);
  for (final link in byFrom[taskId] ?? const <_DependencyLink>[]) {
    final candidate = _bestDependencyPathFrom(
      index,
      link.toTaskId,
      byFrom,
      memo,
      visiting,
    );
    if (candidate.score > bestChild.score) {
      bestChild = candidate;
    }
  }
  visiting.remove(taskId);
  final result = _WeightedPath(
    taskIds: <String>[taskId, ...bestChild.taskIds],
    score: _criticalPathNodeWeight(index, taskId) + bestChild.score,
  );
  memo[taskId] = result;
  return result;
}

/// Returns one task's critical-path duration and risk weight.
double _criticalPathNodeWeight(TaskInsightIndex index, String taskId) {
  final workspaceTask = index.workspaceTasksById[taskId];
  final projectionTask = index.projectionTasksById[taskId];
  final estimateMinutes =
      workspaceTask?.estimateMinutes ?? projectionTask?.estimateMinutes ?? 0;
  final scores = index.scoresFor(taskId);
  return 1 +
      estimateMinutes / 120 +
      (scores?.risk ?? workspaceTask?.risk ?? 0) * 1.4 +
      (scores?.timePressure ?? 0) * 0.8;
}

/// Returns whether one relation should participate in dependency lenses.
bool _isDependencyRelation(String relationType) {
  final relation = relationType.toLowerCase();
  return relation == 'depends_on' ||
      relation == 'blocks' ||
      relation == 'enables';
}

/// Returns a critical-path edge explanation with project impact context.
String _criticalPathExplanation(TaskInsightIndex index, _DependencyLink link) {
  final fromProject = _projectForIndexedTask(index, link.fromTaskId);
  final toProject = _projectForIndexedTask(index, link.toTaskId);
  final impact = fromProject != toProject
      ? ' A delay can cross from $fromProject into $toProject.'
      : '';
  final original = link.explanation.trim();
  if (original.isEmpty) {
    return 'Critical path dependency.$impact';
  }
  return '$original$impact';
}

/// Returns whether task risk has become active blockage or lateness.
bool _materializedRisk(TaskInsightIndex index, String taskId) {
  final status = _statusFor(index, taskId).toLowerCase();
  final dueAt = _dueAtFor(index, taskId);
  return status == 'blocked' ||
      status == 'waiting' ||
      index.blockersFor(taskId).isNotEmpty ||
      (dueAt != null && dueAt.isBefore(DateTime.now()));
}

/// Returns a sort score for risk-owner task ranking.
double _riskOwnerScore(TaskInsightIndex index, String taskId) {
  final scores = index.scoresFor(taskId);
  return (scores?.risk ?? index.workspaceTasksById[taskId]?.risk ?? 0) +
      (_materializedRisk(index, taskId) ? 0.8 : 0) +
      index.downstreamTasksFor(taskId).length * 0.12;
}

/// Returns a sort score for relation lens edges.
double _edgeSortKey(TaskConstellationEdge edge) {
  final sourceBoost = switch (edge.source) {
    'critical_path' => 2.0,
    'materialized_risk' => 1.6,
    'dependency_context' => 0.6,
    'risk_context' => 0.4,
    _ => 0.0,
  };
  return sourceBoost + edge.confidence.clamp(0, 1).toDouble();
}

/// _DependencyLink stores a relation in prerequisite-to-dependent order.
class _DependencyLink {
  /// Creates one execution-order dependency link.
  const _DependencyLink({
    required this.id,
    required this.fromTaskId,
    required this.toTaskId,
    required this.originalRelationType,
    required this.source,
    required this.sourceKind,
    required this.firewall,
    required this.sensitivity,
    required this.confidence,
    required this.explanation,
    required this.evidenceIds,
    required this.actor,
    required this.createdAt,
    required this.updatedAt,
    required this.confirmedAt,
    required this.dismissedAt,
  });

  /// Creates one link from a projection edge and resolved direction.
  factory _DependencyLink.fromEdge(
    TaskProjectionEdge edge,
    String fromTaskId,
    String toTaskId,
  ) {
    return _DependencyLink(
      id: edge.id,
      fromTaskId: fromTaskId,
      toTaskId: toTaskId,
      originalRelationType: edge.relationType,
      source: edge.source,
      sourceKind: edge.sourceKind,
      firewall: edge.firewall,
      sensitivity: edge.sensitivity,
      confidence: edge.confidence,
      explanation: edge.explanation,
      evidenceIds: edge.evidenceIds,
      actor: edge.actor,
      createdAt: edge.createdAt,
      updatedAt: edge.updatedAt,
      confirmedAt: edge.confirmedAt,
      dismissedAt: edge.dismissedAt,
    );
  }

  /// Original relation id.
  final String id;

  /// Prerequisite or delay source task id.
  final String fromTaskId;

  /// Dependent or impacted task id.
  final String toTaskId;

  /// Original relation type from the graph.
  final String originalRelationType;

  /// Original relation source.
  final String source;

  /// Original relation source kind.
  final String sourceKind;

  /// Original relation access firewall.
  final String firewall;

  /// Original relation sensitivity.
  final String sensitivity;

  /// Original relation confidence.
  final double confidence;

  /// Original relation explanation.
  final String explanation;

  /// Source record ids supporting the original relation.
  final List<String> evidenceIds;

  /// Last actor on the original relation.
  final String actor;

  /// Creation timestamp for the original relation.
  final DateTime? createdAt;

  /// Update timestamp for the original relation.
  final DateTime? updatedAt;

  /// User confirmation timestamp for the original relation.
  final DateTime? confirmedAt;

  /// User dismissal timestamp for the original relation.
  final DateTime? dismissedAt;
}

/// _WeightedPath stores a dependency path and its criticality score.
class _WeightedPath {
  /// Creates one immutable weighted dependency path.
  const _WeightedPath({required this.taskIds, required this.score});

  /// Ordered task ids from prerequisite to dependent.
  final List<String> taskIds;

  /// Aggregate path score.
  final double score;
}
