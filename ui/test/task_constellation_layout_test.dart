/// Verifies readable task constellation graph layout behavior.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/ui/task_constellation_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises constellation edge filtering and node collision relief.
void main() {
  group('TaskConstellationLayout', () {
    test('starts from anchor nodes instead of every task', () {
      final viewport = const Size(900, 560);
      final layout = TaskConstellationLayout.build(
        _projection(nodeCount: 18, edgeCount: 120),
        viewport,
      );

      expect(
        TaskConstellationLayout.canvasSizeFor(
          _projection(nodeCount: 18, edgeCount: 120),
          viewport,
        ),
        viewport,
      );
      expect(layout.totalEdgeCount, 120);
      expect(layout.anchors, isNotEmpty);
      expect(layout.anchors.length, lessThanOrEqualTo(8));
      expect(layout.nodes, isEmpty);
      expect(layout.visibleEdges, isEmpty);
      expect(
        layout.layoutStrategy,
        TaskConstellationLayoutStrategyKind.anchoredForce,
      );
    });

    test('keeps semantic radial layout available as an alternate strategy', () {
      final base = TaskConstellationLayout.build(
        _projection(nodeCount: 16, edgeCount: 64),
        const Size(900, 560),
      );
      final layout = TaskConstellationLayout.build(
        _projection(nodeCount: 16, edgeCount: 64),
        const Size(900, 560),
        expandedAnchorIds: <String>{base.anchors.first.id},
        layoutStrategy: TaskConstellationLayoutStrategyKind.semanticRadial,
      );

      expect(
        layout.layoutStrategy,
        TaskConstellationLayoutStrategyKind.semanticRadial,
      );
      expect(layout.nodes, isNotEmpty);
      expect(_hasNodeOverlaps(layout), isFalse);
    });

    test('expanded anchor reveals representative task nodes', () {
      final base = TaskConstellationLayout.build(
        _projection(nodeCount: 18, edgeCount: 120),
        const Size(900, 560),
      );
      final layout = TaskConstellationLayout.build(
        _projection(nodeCount: 18, edgeCount: 120),
        const Size(900, 560),
        expandedAnchorIds: <String>{base.anchors.first.id},
      );
      final canvasSize = TaskConstellationLayout.canvasSizeFor(
        _projection(nodeCount: 18, edgeCount: 120),
        const Size(900, 560),
        expandedAnchorIds: <String>{base.anchors.first.id},
      );

      expect(layout.expandedAnchorIds, contains(base.anchors.first.id));
      expect(canvasSize.width, greaterThan(900));
      expect(canvasSize.height, greaterThan(560));
      expect(layout.nodes, isNotEmpty);
      expect(
        layout.nodes.every((placement) => placement.anchorId != null),
        isTrue,
      );
      expect(
        _minimumInactiveAnchorDistance(layout),
        greaterThan(_maximumActiveAnchorDistance(layout) * 1.5),
      );
    });

    test('expanded task adds direct graph neighbors', () {
      final layout = TaskConstellationLayout.build(
        _projection(nodeCount: 12, edgeCount: 80),
        const Size(900, 560),
        expandedTaskIds: const <String>{'task-0'},
      );

      expect(layout.expandedTaskIds, contains('task-0'));
      expect(
        layout.nodes.map((placement) => placement.node.taskId),
        contains('task-0'),
      );
      expect(layout.nodes.length, greaterThan(1));
      expect(
        layout.visibleEdges.every(
          (edge) => edge.fromTaskId == 'task-0' || edge.toTaskId == 'task-0',
        ),
        isTrue,
      );
    });

    test('focus bounds follow the expanded task neighborhood', () {
      final layout = TaskConstellationLayout.build(
        _projection(nodeCount: 18, edgeCount: 120),
        const Size(1500, 980),
        expandedTaskIds: const <String>{'task-0'},
      );
      final focusBounds = layout.focusBounds();

      expect(layout.focusTaskIds, contains('task-0'));
      expect(focusBounds.width, lessThan(layout.size.width));
      expect(focusBounds.height, lessThan(layout.size.height));
      for (final placement in layout.nodes) {
        if (!layout.focusTaskIds.contains(placement.node.taskId)) {
          continue;
        }
        expect(focusBounds.contains(placement.center), isTrue);
      }
    });

    test('finds visible edge near a tapped segment', () {
      final layout = TaskConstellationLayout.build(
        _projection(nodeCount: 12, edgeCount: 80),
        const Size(900, 560),
        expandedTaskIds: const <String>{'task-0'},
      );
      final edge = layout.visibleEdges.first;
      final from = layout.nodeByTaskId[edge.fromTaskId]!;
      final to = layout.nodeByTaskId[edge.toTaskId]!;
      final midpoint = Offset.lerp(from.center, to.center, 0.5)!;

      final selected = layout.edgeAt(midpoint);
      expect(selected, isNotNull);
      expect(
        <String>{selected!.fromTaskId, selected.toTaskId},
        <String>{edge.fromTaskId, edge.toTaskId},
      );
      expect(layout.edgeAt(const Offset(0, 0), tolerance: 2), isNull);
    });

    test('finds anchor membership edge near an expanded anchor spoke', () {
      final base = TaskConstellationLayout.build(
        _projection(nodeCount: 12, edgeCount: 0),
        const Size(900, 560),
      );
      final anchor = base.anchors.first;
      final layout = TaskConstellationLayout.build(
        _projection(nodeCount: 12, edgeCount: 0),
        const Size(900, 560),
        expandedAnchorIds: <String>{anchor.id},
      );
      final expandedAnchor = layout.anchorById[anchor.id]!;
      final node = layout.nodes.firstWhere(
        (placement) => placement.anchorId == anchor.id,
      );
      final midpoint = Offset.lerp(expandedAnchor.center, node.center, 0.5)!;

      final selected = layout.edgeAt(midpoint);
      expect(selected, isNotNull);
      expect(selected!.fromTaskId, startsWith('anchor:'));
      expect(selected.toTaskId, node.node.taskId);
      expect(selected.relationType, 'anchor_membership');
    });

    test('uses owner and project metadata as graph anchors', () {
      const projection = TaskConstellationProjection(
        nodes: <TaskConstellationNode>[
          TaskConstellationNode(
            taskId: 'task-a',
            title: 'Risk API',
            status: 'blocked',
            owner: 'Priya',
            project: 'Platform',
          ),
          TaskConstellationNode(
            taskId: 'task-b',
            title: 'Mobile release',
            status: 'open',
            owner: 'Mina',
            project: 'Mobile',
          ),
        ],
      );
      final ownerLayout = TaskConstellationLayout.build(
        projection,
        const Size(900, 560),
        anchorDimension: TaskConstellationAnchorDimension.owner,
      );
      final projectLayout = TaskConstellationLayout.build(
        projection,
        const Size(900, 560),
        anchorDimension: TaskConstellationAnchorDimension.project,
      );

      expect(
        ownerLayout.anchors.map((anchor) => anchor.label),
        contains('Priya'),
      );
      expect(
        ownerLayout.anchors.map((anchor) => anchor.label),
        contains('Mina'),
      );
      expect(
        projectLayout.anchors.map((anchor) => anchor.label),
        containsAll(<String>['Platform', 'Mobile']),
      );
    });

    test('places highlighted critical path edges as an ordered chain', () {
      const projection = TaskConstellationProjection(
        nodes: <TaskConstellationNode>[
          TaskConstellationNode(
            taskId: 'task-a',
            title: 'Wait for export',
            status: 'waiting',
            project: 'Analytics',
          ),
          TaskConstellationNode(
            taskId: 'task-b',
            title: 'Clean forecast',
            status: 'open',
            project: 'Analytics',
          ),
          TaskConstellationNode(
            taskId: 'task-c',
            title: 'Prepare readout',
            status: 'open',
            project: 'Leadership',
          ),
        ],
        edges: <TaskConstellationEdge>[
          TaskConstellationEdge(
            fromTaskId: 'task-a',
            toTaskId: 'task-b',
            relationType: 'depends_on',
            source: 'critical_path',
            confidence: 1,
          ),
          TaskConstellationEdge(
            fromTaskId: 'task-b',
            toTaskId: 'task-c',
            relationType: 'depends_on',
            source: 'critical_path',
            confidence: 1,
          ),
        ],
      );
      final base = TaskConstellationLayout.build(
        projection,
        const Size(1000, 620),
        anchorDimension: TaskConstellationAnchorDimension.project,
      );
      final layout = TaskConstellationLayout.build(
        projection,
        const Size(1000, 620),
        anchorDimension: TaskConstellationAnchorDimension.project,
        expandedAnchorIds: base.anchors.map((anchor) => anchor.id).toSet(),
      );
      final placements = layout.nodeByTaskId;

      expect(
        placements['task-a']!.center.dx,
        lessThan(placements['task-b']!.center.dx),
      );
      expect(
        placements['task-b']!.center.dx,
        lessThan(placements['task-c']!.center.dx),
      );
      expect(
        (placements['task-a']!.center.dy - placements['task-c']!.center.dy)
            .abs(),
        lessThan(150),
      );
    });

    test('relaxes overlapping backend node positions', () {
      final base = TaskConstellationLayout.build(
        TaskConstellationProjection(
          nodes: <TaskConstellationNode>[
            for (var index = 0; index < 6; index++)
              _node(index, x: 0.5, y: 0.5),
          ],
        ),
        const Size(640, 420),
      );
      final layout = TaskConstellationLayout.build(
        TaskConstellationProjection(
          nodes: <TaskConstellationNode>[
            for (var index = 0; index < 6; index++)
              _node(index, x: 0.5, y: 0.5),
          ],
        ),
        const Size(640, 420),
        expandedAnchorIds: <String>{base.anchors.first.id},
      );

      final centers = layout.nodes
          .map((placement) => placement.center)
          .toList();
      final uniqueCenters = <String>{
        for (final center in centers)
          '${center.dx.toStringAsFixed(1)},${center.dy.toStringAsFixed(1)}',
      };
      expect(uniqueCenters.length, greaterThan(1));
      expect(_hasNodeOverlaps(layout), isFalse);
    });
  });
}

/// Returns the shortest inactive-anchor distance from the canvas center.
double _minimumInactiveAnchorDistance(TaskConstellationLayout layout) {
  final center = Offset(layout.size.width / 2, layout.size.height / 2);
  return layout.anchors
      .where((anchor) => !layout.expandedAnchorIds.contains(anchor.id))
      .map((anchor) => (anchor.center - center).distance)
      .fold<double>(double.infinity, math.min);
}

/// Returns the furthest active-anchor distance from the canvas center.
double _maximumActiveAnchorDistance(TaskConstellationLayout layout) {
  final center = Offset(layout.size.width / 2, layout.size.height / 2);
  return layout.anchors
      .where((anchor) => layout.expandedAnchorIds.contains(anchor.id))
      .map((anchor) => (anchor.center - center).distance)
      .fold<double>(0, math.max);
}

/// Returns true when any two rendered task cards overlap.
bool _hasNodeOverlaps(TaskConstellationLayout layout) {
  for (var leftIndex = 0; leftIndex < layout.nodes.length; leftIndex++) {
    for (
      var rightIndex = leftIndex + 1;
      rightIndex < layout.nodes.length;
      rightIndex++
    ) {
      final left = layout.nodes[leftIndex];
      final right = layout.nodes[rightIndex];
      if (left.bounds.inflate(1).overlaps(right.bounds.inflate(1))) {
        return true;
      }
    }
  }
  return false;
}

/// Builds a synthetic constellation projection with many valid edges.
TaskConstellationProjection _projection({
  required int nodeCount,
  required int edgeCount,
}) {
  return TaskConstellationProjection(
    nodes: <TaskConstellationNode>[
      for (var index = 0; index < nodeCount; index++) _node(index),
    ],
    edges: <TaskConstellationEdge>[
      for (var index = 0; index < edgeCount; index++)
        TaskConstellationEdge(
          fromTaskId: 'task-${index % nodeCount}',
          toTaskId: 'task-${(index * 5 + 1) % nodeCount}',
          relationType: index % 4 == 0 ? 'depends_on' : 'related',
          confidence: 0.35 + (index % 7) * 0.08,
          source: index % 5 == 0 ? 'explicit' : 'derived',
        ),
    ],
  );
}

/// Builds one task constellation node.
TaskConstellationNode _node(int index, {double? x, double? y}) {
  return TaskConstellationNode(
    taskId: 'task-$index',
    title: 'Constellation task $index',
    status: 'open',
    category: index.isEven ? 'Work' : 'Errands',
    x: x ?? 0.18 + (index % 6) * 0.12,
    y: y ?? 0.2 + (index % 5) * 0.13,
    size: 0.3 + (index % 4) * 0.12,
    urgency: 0.2 + (index % 5) * 0.14,
    confidence: 0.7,
    explanation: 'Synthetic constellation node $index.',
  );
}
