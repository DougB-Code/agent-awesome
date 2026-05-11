/// Insight-index projection adapter entry points.
part of 'task_projection_adapters.dart';

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
