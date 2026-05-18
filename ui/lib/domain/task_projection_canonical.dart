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
      final card = TaskStreamCard(
        taskId: task.taskId,
        title: task.title,
        status: task.status,
        priority: task.priority,
        dueAt: task.dueAt,
        scheduledAt: task.scheduledAt,
        project: _firstNonEmpty(<String>[
          _facetLabelForTask(task, facets, 'project'),
          task.project,
          task.projectId,
        ]),
        owner: _firstNonEmpty(<String>[
          _facetLabelForTask(task, facets, 'person'),
          task.owner,
        ]),
        streamId: _streamId(task, facets),
        readyNow: task.status == 'open' && laneId == 'now',
        nextBestAction: _nextBestAction(task),
        batchScore: _clamp01((relationCounts[task.taskId] ?? 0) / 4),
        contextSwitchCost: task.scores.humanEffort,
        spendLabel: _spendLabelForProjectionTask(task),
        spendScore: _spendScoreForProjectionTask(task),
        bottleneckScore: task.scores.risk,
        confidence: task.confidence,
        explanation: 'Placed in $laneId from explicit task timing facts.',
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

  /// Builds the constellation projection from canonical task edges.
  static TaskConstellationProjection constellation(TaskProjectionGraph graph) {
    final facets = _facetsById(graph);
    final relationCounts = _relationCounts(graph.edges);
    final categoryCounts = <String, int>{};
    final nodes = <TaskConstellationNode>[];
    for (final task in graph.tasks) {
      final category = _firstNonEmpty(<String>[
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
          explanation: 'Placed by canonical time and sparse backlog relations.',
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
