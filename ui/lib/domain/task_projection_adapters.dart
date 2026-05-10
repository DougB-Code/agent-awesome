/// Converts canonical task projection graphs into UI-specific view models.
library;

import 'dart:math' as math;

import 'models.dart';
import 'task_insight_index.dart';
import 'task_insight_query.dart';
import 'task_insight_scores.dart';

/// TaskProjectionAdapters owns client-side grouping for task visualizations.
class TaskProjectionAdapters {
  const TaskProjectionAdapters._();

  /// Builds the stream projection from canonical facts and facets.
  static TaskStreamProjection stream(TaskProjectionGraph graph) {
    final lanes = <TaskStreamLane>[
      const TaskStreamLane(id: 'now', title: 'Now', subtitle: 'Ready work'),
      const TaskStreamLane(id: 'next', title: 'Next', subtitle: 'Soon'),
      const TaskStreamLane(id: 'later', title: 'Later', subtitle: 'This week'),
      const TaskStreamLane(
        id: 'upcoming',
        title: 'Upcoming',
        subtitle: 'Beyond',
      ),
    ];
    final facets = _facetsById(graph);
    final relationCounts = _relationCounts(graph.edges);
    final visibleCards = <String, TaskStreamCard>{};
    for (final task in graph.tasks) {
      final laneId = _facetIDSuffixForTask(task, facets, 'time', 'next');
      final context = _firstNonEmpty(<String>[
        _facetLabelForTask(task, facets, 'context'),
        task.context,
      ]);
      final flowLane = _firstNonEmpty(<String>[
        _facetLabelForTask(task, facets, 'attention'),
        'Personal',
      ]);
      final card = TaskStreamCard(
        taskId: task.taskId,
        title: task.title,
        status: task.status,
        priority: task.priority,
        dueAt: task.dueAt,
        scheduledAt: task.scheduledAt,
        context: context,
        domain: _firstNonEmpty(<String>[
          _facetLabelForTask(task, facets, 'view'),
          task.domain,
        ]),
        project: _firstNonEmpty(<String>[
          _facetLabelForTask(task, facets, 'project'),
          task.project,
          task.projectId,
        ]),
        owner: _firstNonEmpty(<String>[
          _facetLabelForTask(task, facets, 'person'),
          task.owner,
        ]),
        flowLane: flowLane,
        streamId: _streamId(task, facets, context),
        readyNow: task.status == 'open' && laneId == 'now',
        nextBestAction: _nextBestAction(task),
        batchScore: _clamp01((relationCounts[task.taskId] ?? 0) / 4),
        contextSwitchCost: task.scores.humanEffort,
        spendLabel: _spendLabelForProjectionTask(task),
        spendScore: _spendScoreForProjectionTask(task),
        bottleneckScore: task.scores.risk,
        confidence: task.confidence,
        explanation:
            'Placed in $laneId as $flowLane from canonical context facets.',
        relatedTaskCount: relationCounts[task.taskId] ?? 0,
        estimateMinutes: task.estimateMinutes,
      );
      visibleCards[card.taskId] = card;
      final laneIndex = lanes.indexWhere((lane) => lane.id == laneId);
      if (laneIndex >= 0) {
        final lane = lanes[laneIndex];
        lanes[laneIndex] = TaskStreamLane(
          id: lane.id,
          title: lane.title,
          subtitle: lane.subtitle,
          cards: <TaskStreamCard>[...lane.cards, card],
        );
      }
    }
    final sortedLanes = <TaskStreamLane>[
      for (final lane in lanes)
        TaskStreamLane(
          id: lane.id,
          title: lane.title,
          subtitle: lane.subtitle,
          cards: lane.cards.toList()..sort(_compareStreamCards),
        ),
    ];
    return TaskStreamProjection(
      generatedAt: graph.generatedAt,
      lanes: sortedLanes,
      links: _streamLinks(graph.edges, visibleCards),
    );
  }

  /// Builds terrain points from canonical insight scores.
  static PriorityTerrainProjection terrain(TaskProjectionGraph graph) {
    final points = <PriorityTerrainPoint>[
      for (final task in graph.tasks)
        PriorityTerrainPoint(
          taskId: task.taskId,
          title: task.title,
          status: task.status,
          priority: task.priority,
          dueAt: task.dueAt,
          urgencyScore: task.scores.pressure,
          valueScore: task.scores.reward,
          effortScore: task.scores.humanEffort,
          riskScore: task.scores.risk,
          rewardScore: task.scores.reward,
          timePressureScore: task.scores.timePressure,
          agentFitScore: task.scores.agentFit,
          humanEffortScore: task.scores.humanEffort,
          terrainZone: task.scores.terrainZone,
          x: task.scores.reward,
          y: task.scores.pressure,
          elevation: task.scores.elevation,
          recommendedNextStep: _nextBestAction(task),
          confidence: task.confidence,
          explanation: task.explanation,
        ),
    ]..sort(_compareTerrainPoints);
    return PriorityTerrainProjection(
      generatedAt: graph.generatedAt,
      points: points,
      bands: const <PriorityTerrainBand>[
        PriorityTerrainBand(
          id: 'high-value-risk',
          title: 'High Value + Pressure',
          description: 'High impact work that is costly to miss.',
        ),
        PriorityTerrainBand(
          id: 'quick-win',
          title: 'Quick Wins',
          description: 'Useful low-effort work worth clearing.',
        ),
        PriorityTerrainBand(
          id: 'agent-opportunity',
          title: 'Agent Opportunity',
          description: 'High-reward work the agent can likely help complete.',
        ),
        PriorityTerrainBand(
          id: 'steady-progress',
          title: 'Steady Progress',
          description: 'Important work without immediate pressure.',
        ),
        PriorityTerrainBand(
          id: 'risk',
          title: 'Risk & Blockers',
          description: 'Blocked, waiting, or uncertain work.',
        ),
        PriorityTerrainBand(
          id: 'backlog',
          title: 'Backlog',
          description: 'Low-pressure work to keep bounded.',
        ),
      ],
    );
  }

  /// Builds the constellation projection from canonical task edges.
  static TaskConstellationProjection constellation(TaskProjectionGraph graph) {
    final facets = _facetsById(graph);
    final relationCounts = _relationCounts(graph.edges);
    final categoryCounts = <String, int>{};
    final nodes = <TaskConstellationNode>[];
    for (final task in graph.tasks) {
      final category = _firstNonEmpty(<String>[
        _facetLabelForTask(task, facets, 'context'),
        _facetLabelForTask(task, facets, 'attention'),
        'General',
      ]);
      final index = (categoryCounts[category] ?? 0) + 1;
      categoryCounts[category] = index;
      final angle = _categoryAngle(category) + index * 0.38;
      final radius = 0.12 + (1 - task.scores.timePressure) * 0.26;
      nodes.add(
        TaskConstellationNode(
          taskId: task.taskId,
          title: task.title,
          status: task.status,
          category: category,
          timeHorizon: _firstNonEmpty(<String>[
            _facetLabelForTask(task, facets, 'time'),
            'Next',
          ]),
          x: _clamp01(0.5 + math.cos(angle) * radius),
          y: _clamp01(0.5 + math.sin(angle) * radius),
          size:
              0.18 +
              _clamp01((relationCounts[task.taskId] ?? 0) / 5) * 0.22 +
              task.scores.humanEffort * 0.12,
          urgency: task.scores.pressure,
          confidence: task.confidence,
          explanation:
              'Placed by canonical time, context, and sparse backlog relations.',
        ),
      );
    }
    final edges = <TaskConstellationEdge>[
      for (final edge in graph.edges) _constellationEdge(edge),
    ];
    return TaskConstellationProjection(
      generatedAt: graph.generatedAt,
      nodes: nodes,
      edges: edges,
    );
  }
}

/// TaskTerrainInsightMode identifies the portfolio question terrain answers.
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

/// TaskInsightProjectionAdapters converts the insight index into UI projections.
class TaskInsightProjectionAdapters {
  const TaskInsightProjectionAdapters._();

  /// Builds the stream projection from the shared insight index.
  static TaskStreamProjection stream(TaskInsightIndex index) {
    final lanes = <TaskStreamLane>[
      const TaskStreamLane(id: 'now', title: 'Now', subtitle: 'Ready work'),
      const TaskStreamLane(id: 'next', title: 'Next', subtitle: 'Soon'),
      const TaskStreamLane(id: 'later', title: 'Later', subtitle: 'This week'),
      const TaskStreamLane(
        id: 'upcoming',
        title: 'Upcoming',
        subtitle: 'Beyond',
      ),
    ];
    final visibleCards = <String, TaskStreamCard>{};
    for (final taskId in _activeTaskIds(index)) {
      final scores = index.scoresFor(taskId);
      final workspaceTask = index.workspaceTasksById[taskId];
      final projectionTask = index.projectionTasksById[taskId];
      final laneId = _laneIdFor(index, taskId);
      final context = _firstNonEmpty(<String>[
        index.facetLabelForTask(taskId, 'context'),
        workspaceTask?.context ?? '',
        projectionTask?.context ?? '',
      ]);
      final flowLane = _firstNonEmpty(<String>[
        index.facetLabelForTask(taskId, 'attention'),
        context,
        'Personal',
      ]);
      final card = TaskStreamCard(
        taskId: taskId,
        title: index.titleForTaskId(taskId),
        status: _statusFor(index, taskId),
        priority: _priorityFor(index, taskId),
        dueAt: _dueAtFor(index, taskId),
        scheduledAt: _scheduledAtFor(index, taskId),
        context: context,
        domain: _firstNonEmpty(<String>[
          index.facetLabelForTask(taskId, 'view'),
          workspaceTask?.domain ?? '',
          projectionTask?.domain ?? '',
        ]),
        project: _firstNonEmpty(<String>[
          index.facetLabelForTask(taskId, 'project'),
          workspaceTask?.project ?? '',
          projectionTask?.project ?? '',
          projectionTask?.projectId ?? '',
        ]),
        owner: _firstNonEmpty(<String>[
          index.facetLabelForTask(taskId, 'person'),
          workspaceTask?.owner ?? '',
          projectionTask?.owner ?? '',
        ]),
        flowLane: flowLane,
        streamId: _normalizeId(
          _firstNonEmpty(<String>[
            index.workspaceTasksById[taskId]?.sourceLabel ?? '',
            index.projectionTasksById[taskId]?.source ?? '',
            context,
            'general',
          ]),
        ),
        readyNow: _statusFor(index, taskId) == 'open' && laneId == 'now',
        nextBestAction: _indexNextBestAction(index, taskId),
        batchScore: _clamp01(index.downstreamTasksFor(taskId).length / 4),
        contextSwitchCost: scores?.humanEffort ?? 0,
        spendLabel: _spendLabelForIndexedTask(workspaceTask, projectionTask),
        spendScore: _spendScoreForIndexedTask(workspaceTask, projectionTask),
        bottleneckScore: scores?.unblockLeverage ?? scores?.risk ?? 0,
        confidence: scores?.confidence ?? 0,
        explanation: index.explainTaskInsight(
          taskId,
          _primaryInsightId(index, taskId),
        ),
        relatedTaskCount:
            index.downstreamTasksFor(taskId).length +
            index.blockersFor(taskId).length,
        estimateMinutes:
            workspaceTask?.estimateMinutes ??
            projectionTask?.estimateMinutes ??
            0,
      );
      visibleCards[taskId] = card;
      final laneIndex = lanes.indexWhere((lane) => lane.id == laneId);
      if (laneIndex >= 0) {
        final lane = lanes[laneIndex];
        lanes[laneIndex] = TaskStreamLane(
          id: lane.id,
          title: lane.title,
          subtitle: lane.subtitle,
          cards: <TaskStreamCard>[...lane.cards, card],
        );
      }
    }
    return TaskStreamProjection(
      generatedAt: index.generatedAt,
      lanes: <TaskStreamLane>[
        for (final lane in lanes)
          TaskStreamLane(
            id: lane.id,
            title: lane.title,
            subtitle: lane.subtitle,
            cards: lane.cards.toList()..sort(_compareStreamCards),
          ),
      ],
      links: _streamLinks(index.edges, visibleCards),
    );
  }

  /// Builds a mode-specific terrain projection from the shared insight index.
  static PriorityTerrainProjection terrain(
    TaskInsightIndex index, {
    TaskTerrainInsightMode mode = TaskTerrainInsightMode.priorityFocus,
  }) {
    final taskIds = _terrainTaskIds(index, mode);
    final points = <PriorityTerrainPoint>[
      for (final taskId in taskIds) _terrainPoint(index, taskId, mode),
    ]..sort(_compareTerrainPoints);
    return PriorityTerrainProjection(
      generatedAt: index.generatedAt,
      points: points,
      bands: _terrainBandsForMode(mode),
    );
  }

  /// Builds a mode-specific constellation projection from the insight index.
  static TaskConstellationProjection constellation(
    TaskInsightIndex index, {
    TaskConstellationInsightMode mode = TaskConstellationInsightMode.map,
    String selectedTaskId = '',
  }) {
    final selectedGraphTaskId = selectedTaskId;
    final taskIds = _constellationTaskIds(index, mode, selectedGraphTaskId);
    final nodes = <TaskConstellationNode>[];
    final categoryCounts = <String, int>{};
    for (final taskId in taskIds) {
      final category = _constellationCategory(index, taskId, mode);
      final indexInCategory = (categoryCounts[category] ?? 0) + 1;
      categoryCounts[category] = indexInCategory;
      final scores = index.scoresFor(taskId);
      final angle = _categoryAngle(category) + indexInCategory * 0.38;
      final radius = _constellationRadius(
        index,
        taskId,
        mode,
        selectedGraphTaskId,
      );
      nodes.add(
        TaskConstellationNode(
          taskId: taskId,
          title: index.titleForTaskId(taskId),
          status: _statusFor(index, taskId),
          category: category,
          timeHorizon: _firstNonEmpty(<String>[
            index.facetLabelForTask(taskId, 'time'),
            _laneIdFor(index, taskId),
          ]),
          owner: _ownerForIndexedTask(index, taskId),
          project: _projectForIndexedTask(index, taskId),
          x: _clamp01(0.5 + math.cos(angle) * radius),
          y: _clamp01(0.5 + math.sin(angle) * radius),
          size: _constellationSize(index, taskId, mode),
          urgency: scores?.pressure ?? 0,
          confidence: scores?.confidence ?? 0,
          explanation: _constellationExplanation(index, taskId, mode),
        ),
      );
    }
    final visibleIds = taskIds.toSet();
    final edges = _constellationEdges(index, mode, visibleIds);
    return TaskConstellationProjection(
      generatedAt: index.generatedAt,
      nodes: nodes,
      edges: edges,
    );
  }
}

/// Returns active task ids in stable title order.
List<String> _activeTaskIds(TaskInsightIndex index) {
  final taskIds = <String>{
    ...index.workspaceTasksById.keys,
    ...index.projectionTasksById.keys,
  }.where(index.isActiveTask).toList();
  taskIds.sort((left, right) {
    return index.titleForTaskId(left).compareTo(index.titleForTaskId(right));
  });
  return taskIds;
}

/// Returns the stream lane id for one task.
String _laneIdFor(TaskInsightIndex index, String taskId) {
  final facet = index.facetLabelForTask(taskId, 'time').toLowerCase();
  if (facet.contains('now') ||
      facet.contains('today') ||
      facet.contains('overdue')) {
    return 'now';
  }
  if (facet.contains('next') || facet.contains('tomorrow')) {
    return 'next';
  }
  final window = _dueWindow(_dueAtFor(index, taskId), DateTime.now());
  return switch (window) {
    'overdue' || 'today' => 'now',
    'tomorrow' => 'next',
    'this-week' => 'later',
    _ => 'upcoming',
  };
}

/// Returns a task status from queue or projection facts.
String _statusFor(TaskInsightIndex index, String taskId) {
  return _firstNonEmpty(<String>[
    index.workspaceTasksById[taskId]?.status ?? '',
    index.projectionTasksById[taskId]?.status ?? '',
    'open',
  ]);
}

/// Returns a task priority from queue or projection facts.
String _priorityFor(TaskInsightIndex index, String taskId) {
  return _firstNonEmpty(<String>[
    index.workspaceTasksById[taskId]?.priority ?? '',
    index.projectionTasksById[taskId]?.priority ?? '',
    'normal',
  ]);
}

/// Returns a task due date from queue or projection facts.
DateTime? _dueAtFor(TaskInsightIndex index, String taskId) {
  return index.workspaceTasksById[taskId]?.dueAt ??
      index.projectionTasksById[taskId]?.dueAt;
}

/// Returns a task scheduled date from queue or projection facts.
DateTime? _scheduledAtFor(TaskInsightIndex index, String taskId) {
  return index.workspaceTasksById[taskId]?.scheduledAt ??
      index.projectionTasksById[taskId]?.scheduledAt;
}

/// Returns the best owner label for an indexed task.
String _ownerForIndexedTask(TaskInsightIndex index, String taskId) {
  return _firstNonEmpty(<String>[
    index.facetLabelForTask(taskId, 'person'),
    index.workspaceTasksById[taskId]?.owner ?? '',
    index.projectionTasksById[taskId]?.owner ?? '',
    'Unassigned',
  ]);
}

/// Returns the best project label for an indexed task.
String _projectForIndexedTask(TaskInsightIndex index, String taskId) {
  final workspaceTask = index.workspaceTasksById[taskId];
  final projectionTask = index.projectionTasksById[taskId];
  final contextLabel = _firstNonEmpty(<String>[
    index.facetLabelForTask(taskId, 'context'),
    workspaceTask?.context ?? '',
    projectionTask?.context ?? '',
    index.facetLabelForTask(taskId, 'attention'),
  ]);
  return _firstNonEmpty(<String>[
    _projectLabelUnlessContext(workspaceTask?.project ?? '', contextLabel),
    _projectLabelUnlessContext(projectionTask?.project ?? '', contextLabel),
    projectionTask?.projectId ?? '',
    workspaceTask?.sourceLabel ?? '',
    workspaceTask?.source ?? '',
    projectionTask?.source ?? '',
    index.facetLabelForTask(taskId, 'view'),
    _projectLabelUnlessContext(
      index.facetLabelForTask(taskId, 'project'),
      contextLabel,
    ),
    'No project',
  ]);
}

/// Returns a project label only when it adds information beyond context.
String _projectLabelUnlessContext(String value, String contextLabel) {
  final label = value.trim();
  if (label.isEmpty) {
    return '';
  }
  if (contextLabel.trim().isNotEmpty &&
      label.toLowerCase() == contextLabel.trim().toLowerCase()) {
    return '';
  }
  return label;
}

/// Returns the best insight-aware next action for one task.
String _indexNextBestAction(TaskInsightIndex index, String taskId) {
  final plan = index.unblockPlanFor(taskId);
  if (plan.hasExplicitBlocker || _statusFor(index, taskId) == 'blocked') {
    return plan.smallestNextAction;
  }
  final candidate = index.candidateForTask(taskId, TaskInsightIds.agentHandoff);
  if (candidate != null && candidate.severity != 'warning') {
    return 'Prepare an agent handoff brief.';
  }
  final projectionTask = index.projectionTasksById[taskId];
  if (projectionTask != null) {
    return _nextBestAction(projectionTask);
  }
  final workspaceTask = index.workspaceTasksById[taskId];
  if (workspaceTask != null && workspaceTask.description.isNotEmpty) {
    return 'Open the context notes and continue.';
  }
  return 'Start with the context title as the next action.';
}

/// Returns the most specific insight id for explaining one task.
String _primaryInsightId(TaskInsightIndex index, String taskId) {
  for (final insightId in const <String>[
    TaskInsightIds.quickUnblocks,
    TaskInsightIds.agentHandoff,
    TaskInsightIds.nextWeekHighValue,
    TaskInsightIds.highRiskLowConfidence,
    TaskInsightIds.metadataGaps,
  ]) {
    if (index.candidateForTask(taskId, insightId) != null) {
      return insightId;
    }
  }
  return TaskInsightIds.all;
}

/// Returns mode-specific terrain task ids.
List<String> _terrainTaskIds(
  TaskInsightIndex index,
  TaskTerrainInsightMode mode,
) {
  final ids = switch (mode) {
    TaskTerrainInsightMode.priorityFocus => _activeTaskIds(index),
    TaskTerrainInsightMode.agentHandoff =>
      index
          .tasksForInsight(TaskInsightIds.agentHandoff)
          .map((candidate) => candidate.taskId)
          .toList(),
    TaskTerrainInsightMode.nextWeekHighValue =>
      index
          .tasksForInsight(TaskInsightIds.nextWeekHighValue)
          .map((candidate) => candidate.taskId)
          .toList(),
    TaskTerrainInsightMode.unblockLeverage =>
      index
          .tasksForInsight(TaskInsightIds.quickUnblocks)
          .map((candidate) => candidate.taskId)
          .toList(),
    TaskTerrainInsightMode.riskConfidence => <String>{
      ...index
          .tasksForInsight(TaskInsightIds.highRiskLowConfidence)
          .map((candidate) => candidate.taskId),
      ...index
          .tasksForInsight(TaskInsightIds.metadataGaps)
          .map((candidate) => candidate.taskId),
    }.toList(),
  };
  if (ids.isNotEmpty || mode == TaskTerrainInsightMode.priorityFocus) {
    return ids;
  }
  return _activeTaskIds(index);
}

/// Builds one terrain point for a mode.
PriorityTerrainPoint _terrainPoint(
  TaskInsightIndex index,
  String taskId,
  TaskTerrainInsightMode mode,
) {
  final scores =
      index.scoresFor(taskId) ??
      TaskInsightScoreProfile.fromTask(
        taskId: taskId,
        workspaceTask: index.workspaceTasksById[taskId],
        projectionTask: index.projectionTasksById[taskId],
      );
  final coordinates = _terrainCoordinates(scores, mode);
  return PriorityTerrainPoint(
    taskId: taskId,
    title: index.titleForTaskId(taskId),
    status: _statusFor(index, taskId),
    priority: _priorityFor(index, taskId),
    dueAt: _dueAtFor(index, taskId),
    urgencyScore: scores.pressure,
    valueScore: scores.reward,
    effortScore: scores.humanEffort,
    riskScore: scores.risk,
    rewardScore: scores.reward,
    timePressureScore: scores.timePressure,
    agentFitScore: scores.agentFit,
    humanEffortScore: scores.humanEffort,
    terrainZone: _terrainZoneForMode(index, taskId, scores, mode),
    x: coordinates.x,
    y: coordinates.y,
    elevation: _terrainElevation(scores, mode),
    recommendedNextStep: _indexNextBestAction(index, taskId),
    confidence: scores.confidence,
    explanation: _terrainExplanation(index, taskId, mode),
  );
}

/// Returns mode-specific terrain coordinates.
math.Point<double> _terrainCoordinates(
  TaskInsightScoreProfile scores,
  TaskTerrainInsightMode mode,
) {
  return switch (mode) {
    TaskTerrainInsightMode.priorityFocus => math.Point<double>(
      scores.reward,
      scores.pressure,
    ),
    TaskTerrainInsightMode.agentHandoff => math.Point<double>(
      scores.handoffReadiness,
      scores.obligation,
    ),
    TaskTerrainInsightMode.nextWeekHighValue => math.Point<double>(
      scores.reward,
      math.max(scores.consequence, scores.timePressure),
    ),
    TaskTerrainInsightMode.unblockLeverage => math.Point<double>(
      scores.unblockLeverage,
      scores.blockerEffort,
    ),
    TaskTerrainInsightMode.riskConfidence => math.Point<double>(
      scores.confidence,
      scores.risk,
    ),
  };
}

/// Returns the terrain zone id for a mode.
String _terrainZoneForMode(
  TaskInsightIndex index,
  String taskId,
  TaskInsightScoreProfile scores,
  TaskTerrainInsightMode mode,
) {
  return switch (mode) {
    TaskTerrainInsightMode.priorityFocus =>
      index.projectionTasksById[taskId]?.scores.terrainZone ?? '',
    TaskTerrainInsightMode.agentHandoff => _agentHandoffZone(
      scores,
      index.policy.safeAgentThreshold,
    ),
    TaskTerrainInsightMode.nextWeekHighValue => _nextWeekZone(scores),
    TaskTerrainInsightMode.unblockLeverage => _unblockZone(scores),
    TaskTerrainInsightMode.riskConfidence => _riskConfidenceZone(scores),
  };
}

/// Returns the agent-handoff atlas zone for one task.
String _agentHandoffZone(
  TaskInsightScoreProfile scores,
  double safeAgentThreshold,
) {
  if (scores.humanJudgmentNeed >= 0.58 ||
      scores.agentSafety < safeAgentThreshold) {
    return 'human-judgment';
  }
  if (scores.handoffReadiness >= 0.58 && scores.agentSafety >= 0.58) {
    return 'ready-for-agent';
  }
  if (scores.agentFit >= 0.45 || scores.contextReadiness >= 0.45) {
    return 'agent-candidate';
  }
  return 'needs-review';
}

/// Returns the next-week value atlas zone for one task.
String _nextWeekZone(TaskInsightScoreProfile scores) {
  final consequence = math.max(scores.consequence, scores.timePressure);
  if (scores.reward >= 0.58 && scores.risk >= 0.58) {
    return 'watch-risk';
  }
  if (scores.reward >= 0.62 && consequence >= 0.50) {
    return 'high-value-next-week';
  }
  if (scores.reward >= 0.46 || consequence >= 0.44) {
    return 'prepare-early';
  }
  return 'next-week-backlog';
}

/// Returns the unblock leverage atlas zone for one task.
String _unblockZone(TaskInsightScoreProfile scores) {
  final ease = 1 - scores.blockerEffort.clamp(0, 1).toDouble();
  if (scores.unblockLeverage >= 0.58 && ease >= 0.50) {
    return 'quick-unblock';
  }
  if (scores.unblockLeverage >= 0.58) {
    return 'high-leverage-blocker';
  }
  if (ease >= 0.55) {
    return 'simple-blocker';
  }
  return 'costly-blocker';
}

/// Returns the risk-confidence atlas zone for one task.
String _riskConfidenceZone(TaskInsightScoreProfile scores) {
  final confidence = scores.confidence;
  final risk = scores.risk;
  if (risk >= 0.58 && confidence < 0.58) {
    return 'risk-blind-spot';
  }
  if (risk >= 0.58) {
    return 'known-risk';
  }
  if (confidence < 0.58) {
    return 'confidence-gap';
  }
  return 'stable-known';
}

/// Returns mode-specific point elevation.
double _terrainElevation(
  TaskInsightScoreProfile scores,
  TaskTerrainInsightMode mode,
) {
  return switch (mode) {
    TaskTerrainInsightMode.priorityFocus => _clamp01(
      0.45 * scores.reward + 0.35 * scores.pressure + 0.20 * scores.risk,
    ),
    TaskTerrainInsightMode.agentHandoff => _clamp01(
      0.40 * scores.handoffReadiness +
          0.25 * scores.obligation +
          0.20 * scores.agentSafety +
          0.15 * scores.agentFit,
    ),
    TaskTerrainInsightMode.nextWeekHighValue => _clamp01(
      0.45 * scores.reward +
          0.30 * scores.consequence +
          0.15 * scores.commitmentHardness +
          0.10 * scores.pressure,
    ),
    TaskTerrainInsightMode.unblockLeverage => _clamp01(
      0.60 * scores.unblockLeverage + 0.25 * scores.downstreamValue,
    ),
    TaskTerrainInsightMode.riskConfidence => _clamp01(
      scores.risk * (1 - scores.confidence + 0.25),
    ),
  };
}

/// Returns a mode-specific terrain explanation.
String _terrainExplanation(
  TaskInsightIndex index,
  String taskId,
  TaskTerrainInsightMode mode,
) {
  final insightId = switch (mode) {
    TaskTerrainInsightMode.agentHandoff => TaskInsightIds.agentHandoff,
    TaskTerrainInsightMode.nextWeekHighValue =>
      TaskInsightIds.nextWeekHighValue,
    TaskTerrainInsightMode.unblockLeverage => TaskInsightIds.quickUnblocks,
    TaskTerrainInsightMode.riskConfidence =>
      TaskInsightIds.highRiskLowConfidence,
    TaskTerrainInsightMode.priorityFocus => _primaryInsightId(index, taskId),
  };
  return index.explainTaskInsight(taskId, insightId);
}

/// Returns mode-specific terrain band labels.
List<PriorityTerrainBand> _terrainBandsForMode(TaskTerrainInsightMode mode) {
  return switch (mode) {
    TaskTerrainInsightMode.priorityFocus => const <PriorityTerrainBand>[
      PriorityTerrainBand(
        id: 'high-value-risk',
        title: 'High Value + Pressure',
        description: 'High impact work that is costly to miss.',
      ),
      PriorityTerrainBand(
        id: 'quick-win',
        title: 'Quick Wins',
        description: 'Useful low-effort work worth clearing.',
      ),
      PriorityTerrainBand(
        id: 'agent-opportunity',
        title: 'Agent Opportunity',
        description: 'High-reward work the agent can likely help complete.',
      ),
      PriorityTerrainBand(
        id: 'steady-progress',
        title: 'Steady Progress',
        description: 'Important work without immediate pressure.',
      ),
      PriorityTerrainBand(
        id: 'risk',
        title: 'Risk & Blockers',
        description: 'Blocked, waiting, or uncertain work.',
      ),
      PriorityTerrainBand(
        id: 'backlog',
        title: 'Backlog',
        description: 'Low-pressure work to keep bounded.',
      ),
    ],
    TaskTerrainInsightMode.agentHandoff => const <PriorityTerrainBand>[
      PriorityTerrainBand(
        id: 'agent-candidate',
        title: 'Candidate Later',
        description: 'Possible handoff after better context.',
      ),
      PriorityTerrainBand(
        id: 'ready-for-agent',
        title: 'Ready for Agent',
        description: 'Clear, safe work that can be delegated.',
      ),
      PriorityTerrainBand(
        id: 'needs-review',
        title: 'Needs Review',
        description: 'Could be delegated after scope or context review.',
      ),
      PriorityTerrainBand(
        id: 'human-judgment',
        title: 'Human Judgment',
        description: 'Risky, sensitive, or judgment-heavy work.',
      ),
    ],
    TaskTerrainInsightMode.nextWeekHighValue => const <PriorityTerrainBand>[
      PriorityTerrainBand(
        id: 'next-week-backlog',
        title: 'Lower Value',
        description: 'Keep bounded or defer.',
      ),
      PriorityTerrainBand(
        id: 'prepare-early',
        title: 'Prepare Early',
        description: 'Valuable work with room to schedule.',
      ),
      PriorityTerrainBand(
        id: 'watch-risk',
        title: 'Watch Risk',
        description: 'Valuable work that could slip.',
      ),
      PriorityTerrainBand(
        id: 'high-value-next-week',
        title: 'High Value',
        description: 'High-consequence work coming next week.',
      ),
    ],
    TaskTerrainInsightMode.unblockLeverage => const <PriorityTerrainBand>[
      PriorityTerrainBand(
        id: 'simple-blocker',
        title: 'Simple Blockers',
        description: 'Low effort with modest leverage.',
      ),
      PriorityTerrainBand(
        id: 'quick-unblock',
        title: 'Quick Unblocks',
        description: 'Low effort with downstream payoff.',
      ),
      PriorityTerrainBand(
        id: 'costly-blocker',
        title: 'Costly Blockers',
        description: 'High effort for limited leverage.',
      ),
      PriorityTerrainBand(
        id: 'high-leverage-blocker',
        title: 'High Leverage',
        description: 'Worth effort because it unlocks work.',
      ),
    ],
    TaskTerrainInsightMode.riskConfidence => const <PriorityTerrainBand>[
      PriorityTerrainBand(
        id: 'confidence-gap',
        title: 'Confidence Gaps',
        description: 'Low-confidence, lower immediate risk work.',
      ),
      PriorityTerrainBand(
        id: 'stable-known',
        title: 'Known Stable',
        description: 'Higher confidence and lower risk.',
      ),
      PriorityTerrainBand(
        id: 'risk-blind-spot',
        title: 'Risk Blind Spots',
        description: 'Risky work with weak confidence.',
      ),
      PriorityTerrainBand(
        id: 'known-risk',
        title: 'Known Risks',
        description: 'Risky enough to act on.',
      ),
    ],
  };
}

/// Returns mode-specific task ids for constellation.
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
      scope: link.scope,
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
        scope: edge.scope,
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
    scope: edge.scope,
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
    required this.scope,
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
      scope: edge.scope,
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

  /// Original relation access scope.
  final String scope;

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

/// Returns a coarse due window for adapter fallback grouping.
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

/// Returns projection facets keyed by stable id.
Map<String, TaskProjectionFacet> _facetsById(TaskProjectionGraph graph) {
  return <String, TaskProjectionFacet>{
    for (final facet in graph.facets) facet.id: facet,
  };
}

/// Returns the first facet label for a task and dimension.
String _facetLabelForTask(
  TaskProjectionTask task,
  Map<String, TaskProjectionFacet> facets,
  String dimension,
) {
  for (final facetId in task.facetIds) {
    final facet = facets[facetId];
    if (facet != null && facet.dimension == dimension) {
      return facet.label;
    }
  }
  return '';
}

/// Returns the first facet id suffix for a task and dimension.
String _facetIDSuffixForTask(
  TaskProjectionTask task,
  Map<String, TaskProjectionFacet> facets,
  String dimension,
  String fallback,
) {
  for (final facetId in task.facetIds) {
    final facet = facets[facetId];
    if (facet == null || facet.dimension != dimension) {
      continue;
    }
    final index = facet.id.indexOf(':');
    return index >= 0 ? facet.id.substring(index + 1) : facet.id;
  }
  return fallback;
}

/// Counts sparse edges touching each task.
Map<String, int> _relationCounts(List<TaskProjectionEdge> edges) {
  final counts = <String, int>{};
  for (final edge in edges) {
    counts[edge.fromTaskId] = (counts[edge.fromTaskId] ?? 0) + 1;
    counts[edge.toTaskId] = (counts[edge.toTaskId] ?? 0) + 1;
  }
  return counts;
}

/// Builds visible stream links from sparse task edges.
List<TaskStreamLink> _streamLinks(
  List<TaskProjectionEdge> edges,
  Map<String, TaskStreamCard> visibleCards,
) {
  final links = <TaskStreamLink>[];
  for (final edge in edges) {
    final link = _streamLink(edge, visibleCards);
    if (link != null) {
      links.add(link);
    }
  }
  links.sort((left, right) {
    final fromCompare = left.fromTaskId.compareTo(right.fromTaskId);
    if (fromCompare != 0) {
      return fromCompare;
    }
    return left.toTaskId.compareTo(right.toTaskId);
  });
  return links;
}

/// Converts one sparse graph edge into a stream transition.
TaskStreamLink? _streamLink(
  TaskProjectionEdge edge,
  Map<String, TaskStreamCard> visibleCards,
) {
  var fromTaskId = edge.fromTaskId;
  var toTaskId = edge.toTaskId;
  final transition = switch (edge.relationType) {
    'depends_on' => 'enables',
    'blocks' => 'blocks',
    'enables' => 'enables',
    'part_of' => 'contributes',
    _ => '',
  };
  if (transition.isEmpty) {
    return null;
  }
  if (edge.relationType == 'depends_on') {
    fromTaskId = edge.toTaskId;
    toTaskId = edge.fromTaskId;
  }
  final fromCard = visibleCards[fromTaskId];
  final toCard = visibleCards[toTaskId];
  if (fromCard == null || toCard == null) {
    return null;
  }
  return TaskStreamLink(
    fromTaskId: fromTaskId,
    toTaskId: toTaskId,
    relationType: edge.relationType,
    transitionType: transition,
    streamId: _streamLinkID(fromCard, toCard, edge),
    confidence: edge.confidence,
    explanation: edge.explanation,
  );
}

/// Chooses a stable route identity for a stream transition.
String _streamLinkID(
  TaskStreamCard from,
  TaskStreamCard to,
  TaskProjectionEdge edge,
) {
  if (from.streamId.isNotEmpty && from.streamId == to.streamId) {
    return from.streamId;
  }
  if (edge.relationType == 'blocks') {
    return 'blockers';
  }
  if (from.flowLane.isNotEmpty &&
      to.flowLane.isNotEmpty &&
      from.flowLane != to.flowLane) {
    return _normalizeId('${from.flowLane}-to-${to.flowLane}');
  }
  return _firstNonEmpty(<String>[
    from.streamId,
    to.streamId,
    edge.relationType,
  ]);
}

/// Returns a stable stream id from task source, domain, context, or topic.
String _streamId(
  TaskProjectionTask task,
  Map<String, TaskProjectionFacet> facets,
  String context,
) {
  return _normalizeId(
    _firstNonEmpty(<String>[
      task.source,
      task.domain,
      context,
      _facetLabelForTask(task, facets, 'topic'),
      'general',
    ]),
  );
}

/// Orders stream cards by date, priority, then title.
int _compareStreamCards(TaskStreamCard left, TaskStreamCard right) {
  final leftDue = left.dueAt;
  final rightDue = right.dueAt;
  if (leftDue != null && rightDue != null && leftDue != rightDue) {
    return leftDue.compareTo(rightDue);
  }
  if (leftDue != null && rightDue == null) {
    return -1;
  }
  if (leftDue == null && rightDue != null) {
    return 1;
  }
  final priorityCompare = _priorityRank(
    left.priority,
  ).compareTo(_priorityRank(right.priority));
  if (priorityCompare != 0) {
    return priorityCompare;
  }
  return left.title.compareTo(right.title);
}

/// Orders terrain points by elevation and title.
int _compareTerrainPoints(
  PriorityTerrainPoint left,
  PriorityTerrainPoint right,
) {
  final elevationCompare = right.elevation.compareTo(left.elevation);
  if (elevationCompare != 0) {
    return elevationCompare;
  }
  return left.title.compareTo(right.title);
}

/// Maps priority labels to a compact sort rank.
int _priorityRank(String priority) {
  return switch (priority) {
    'urgent' => 0,
    'high' => 1,
    'normal' => 2,
    'low' => 3,
    _ => 4,
  };
}

/// Returns the generic next best action for a canonical task.
String _nextBestAction(TaskProjectionTask task) {
  if (task.status == 'waiting') {
    return 'Check what you are waiting on.';
  }
  if (task.status == 'blocked') {
    return 'Remove the blocker or clarify the dependency.';
  }
  if (task.description.isNotEmpty) {
    return 'Open the context notes and continue.';
  }
  return 'Start with the context title as the next action.';
}

/// Returns the explicit spend label for a projection-only task.
String _spendLabelForProjectionTask(TaskProjectionTask task) {
  return _moneyLabel(
    task.workBreakdown.estimatedCostCents,
    task.workBreakdown.costCurrency,
  );
}

/// Returns the spend bucket score for a projection-only task.
double _spendScoreForProjectionTask(TaskProjectionTask task) {
  return _spendScoreFromCents(task.workBreakdown.estimatedCostCents);
}

/// Returns the explicit spend label for a merged insight task.
String _spendLabelForIndexedTask(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? projectionTask,
) {
  return _moneyLabel(
    _spendCentsForIndexedTask(workspaceTask, projectionTask),
    _currencyForIndexedTask(workspaceTask, projectionTask),
  );
}

/// Returns the spend bucket score for a merged insight task.
double _spendScoreForIndexedTask(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? projectionTask,
) {
  return _spendScoreFromCents(
    _spendCentsForIndexedTask(workspaceTask, projectionTask),
  );
}

/// Returns the first explicit spend amount from task facts.
int _spendCentsForIndexedTask(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? projectionTask,
) {
  final workspaceSpend = workspaceTask?.spendCents ?? 0;
  if (workspaceSpend > 0) {
    return workspaceSpend;
  }
  final workspaceWbsSpend =
      workspaceTask?.workBreakdown.estimatedCostCents ?? 0;
  if (workspaceWbsSpend > 0) {
    return workspaceWbsSpend;
  }
  return projectionTask?.workBreakdown.estimatedCostCents ?? 0;
}

/// Returns the currency attached to the selected spend amount.
String _currencyForIndexedTask(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? projectionTask,
) {
  if ((workspaceTask?.spendCents ?? 0) > 0) {
    return workspaceTask?.currency ?? '';
  }
  if ((workspaceTask?.workBreakdown.estimatedCostCents ?? 0) > 0) {
    return workspaceTask?.workBreakdown.costCurrency ?? '';
  }
  return projectionTask?.workBreakdown.costCurrency ?? '';
}

/// Converts an explicit spend amount into a normalized display bucket score.
double _spendScoreFromCents(int cents) {
  if (cents <= 0) {
    return 0;
  }
  if (cents <= 2500) {
    return 0.2;
  }
  if (cents <= 10000) {
    return 0.5;
  }
  return 0.85;
}

/// Formats a minor-unit money amount for compact card metadata.
String _moneyLabel(int cents, String currency) {
  if (cents <= 0) {
    return '';
  }
  final amount = (cents / 100).toStringAsFixed(2);
  final code = currency.trim();
  return code.isEmpty ? '$amount spend' : '$amount $code spend';
}

/// Returns a deterministic angle for a text category.
double _categoryAngle(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return (hash % 628) / 100;
}

/// Returns the first non-empty string from a list.
String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

/// Normalizes a display label into a stable id.
String _normalizeId(String value) {
  final trimmed = value.trim().toLowerCase();
  final buffer = StringBuffer();
  var previousDash = false;
  for (final codeUnit in trimmed.codeUnits) {
    final isAlphaNumeric =
        (codeUnit >= 48 && codeUnit <= 57) ||
        (codeUnit >= 97 && codeUnit <= 122);
    if (isAlphaNumeric) {
      buffer.writeCharCode(codeUnit);
      previousDash = false;
    } else if (!previousDash) {
      buffer.write('-');
      previousDash = true;
    }
  }
  final normalized = buffer.toString();
  return normalized.replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Clamps a numeric value into the 0-1 range.
double _clamp01(num value) {
  return value.clamp(0, 1).toDouble();
}
