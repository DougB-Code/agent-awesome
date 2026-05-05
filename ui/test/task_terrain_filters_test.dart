/// Verifies terrain filters overlay encoded task areas without changing atlas.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/ui/task_stream_axes.dart';
import 'package:agentawesome_ui/ui/task_terrain_filters.dart';

/// Exercises area overlay terrain filtering.
void main() {
  group('TaskTerrainFilterProjector', () {
    test('filters terrain points by encoded area overlays', () {
      final model = TaskTerrainFilterProjector.build(
        streamProjection: _streamProjection(),
        terrainProjection: _terrainProjection(),
      );
      final selection = const TaskTerrainFilterSelection()
          .withAreaFilter(TaskStreamAxisDimension.project, 'new-project')
          .withAreaFilter(TaskStreamAxisDimension.effort, 'medium');

      final filtered = model.apply(_terrainProjection(), selection);

      expect(filtered.points.map((point) => point.taskId), <String>['task-1']);
    });

    test('keeps spend separate from work effort', () {
      final model = TaskTerrainFilterProjector.build(
        streamProjection: _streamProjection(),
        terrainProjection: _terrainProjection(),
      );

      expect(
        _optionIds(model, TaskStreamAxisDimension.spend),
        contains('high-spend'),
      );
      expect(
        _optionIds(model, TaskStreamAxisDimension.effort),
        contains('deep'),
      );

      final spendSelection = const TaskTerrainFilterSelection().withAreaFilter(
        TaskStreamAxisDimension.spend,
        'high-spend',
      );
      final effortSelection = const TaskTerrainFilterSelection().withAreaFilter(
        TaskStreamAxisDimension.effort,
        'deep',
      );

      expect(
        model
            .apply(_terrainProjection(), spendSelection)
            .points
            .map((point) => point.taskId),
        <String>['task-3'],
      );
      expect(
        model
            .apply(_terrainProjection(), effortSelection)
            .points
            .map((point) => point.taskId),
        <String>['task-2'],
      );
    });

    test('keeps derived projection dimensions out of terrain overlays', () {
      expect(
        TaskTerrainFilterProjector.overlayDimensions,
        isNot(contains(TaskStreamAxisDimension.attention)),
      );
      expect(
        TaskTerrainFilterProjector.overlayDimensions,
        isNot(contains(TaskStreamAxisDimension.blockers)),
      );
    });
  });
}

/// Returns option ids for one terrain overlay dimension.
List<String> _optionIds(
  TaskTerrainFilterModel model,
  TaskStreamAxisDimension dimension,
) {
  return <String>[
    for (final option
        in model.areaOptionsByDimension[dimension] ??
            const <TaskTerrainFilterOption>[])
      option.id,
  ];
}

/// Builds task stream cards with mixed project, effort, and spend categories.
TaskStreamProjection _streamProjection() {
  return TaskStreamProjection(
    lanes: <TaskStreamLane>[
      TaskStreamLane(
        id: 'now',
        title: 'Now',
        cards: <TaskStreamCard>[
          _streamCard(
            taskId: 'task-1',
            title: 'Draft launch plan',
            flowLane: 'Deep focus',
            project: 'New Project',
            estimateMinutes: 45,
            spendScore: 0.2,
          ),
          _streamCard(
            taskId: 'task-2',
            title: 'Review migration notes',
            flowLane: 'Admin',
            project: 'New Project',
            estimateMinutes: 90,
            spendScore: 0.1,
          ),
          _streamCard(
            taskId: 'task-3',
            title: 'Approve vendor spend',
            flowLane: 'Admin',
            project: 'Operations',
            estimateMinutes: 20,
            spendScore: 0.82,
          ),
        ],
      ),
    ],
  );
}

/// Builds one stream card with shared defaults.
TaskStreamCard _streamCard({
  required String taskId,
  required String title,
  required String flowLane,
  required String project,
  required int estimateMinutes,
  required double spendScore,
}) {
  return TaskStreamCard(
    taskId: taskId,
    title: title,
    status: 'open',
    priority: 'normal',
    flowLane: flowLane,
    project: project,
    context: 'work',
    domain: 'Product',
    owner: 'Doug',
    estimateMinutes: estimateMinutes,
    spendScore: spendScore,
  );
}

/// Builds terrain points that can be narrowed by the stream categories.
PriorityTerrainProjection _terrainProjection() {
  return PriorityTerrainProjection(
    points: <PriorityTerrainPoint>[
      _terrainPoint(
        taskId: 'task-1',
        title: 'Draft launch plan',
        dueAt: DateTime(2026, 5, 6, 12),
        agentFitScore: 0.72,
        terrainZone: 'agent-opportunity',
      ),
      _terrainPoint(
        taskId: 'task-2',
        title: 'Review migration notes',
        dueAt: DateTime(2026, 5, 20, 12),
        agentFitScore: 0.2,
        terrainZone: 'quick-win',
      ),
      _terrainPoint(
        taskId: 'task-3',
        title: 'Approve vendor spend',
        dueAt: DateTime(2026, 5, 4, 12),
        agentFitScore: 0.42,
        terrainZone: 'high-value-risk',
      ),
    ],
  );
}

/// Builds one terrain point with stable scores.
PriorityTerrainPoint _terrainPoint({
  required String taskId,
  required String title,
  required DateTime dueAt,
  required double agentFitScore,
  required String terrainZone,
}) {
  return PriorityTerrainPoint(
    taskId: taskId,
    title: title,
    status: 'open',
    priority: 'normal',
    dueAt: dueAt,
    urgencyScore: 0.5,
    valueScore: 0.6,
    effortScore: 0.4,
    riskScore: 0.2,
    rewardScore: 0.64,
    timePressureScore: 0.54,
    agentFitScore: agentFitScore,
    humanEffortScore: 0.4,
    terrainZone: terrainZone,
    x: 0.5,
    y: 0.5,
    elevation: 0.6,
  );
}
