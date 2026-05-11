/// Canonical graph-to-view projection adapters.
part of 'task_projection_adapters.dart';

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
