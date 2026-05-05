/// Verifies readable terrain layout geometry and density controls.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/ui/task_terrain_layout.dart';

/// Exercises terrain layout density, spreading, and representation behavior.
void main() {
  group('TaskTerrainLayout', () {
    test('tiles terrain zones across the full map area', () {
      final layout = TaskTerrainLayout.build(
        _projection(count: 24),
        const Size(900, 560),
        mode: TaskTerrainViewMode.all,
      );

      final risk = _zoneRect(layout, TaskTerrainZoneKind.risk);
      final highValue = _zoneRect(layout, TaskTerrainZoneKind.highValueRisk);
      final steady = _zoneRect(layout, TaskTerrainZoneKind.steadyProgress);
      final backlog = _zoneRect(layout, TaskTerrainZoneKind.backlog);
      final quickWin = _zoneRect(layout, TaskTerrainZoneKind.quickWin);
      final agent = _zoneRect(layout, TaskTerrainZoneKind.agentOpportunity);

      expect(layout.mapArea, Offset.zero & layout.size);
      expect(risk.left, closeTo(layout.mapArea.left, 0.01));
      expect(highValue.right, closeTo(layout.mapArea.right, 0.01));
      expect(risk.right, closeTo(highValue.left, 0.01));
      expect(backlog.top, closeTo(layout.mapArea.top, 0.01));
      expect(backlog.bottom, closeTo(steady.top, 0.01));
      expect(steady.bottom, closeTo(risk.top, 0.01));
      expect(backlog.right, closeTo(quickWin.left, 0.01));
      expect(quickWin.right, closeTo(agent.left, 0.01));
      expect(agent.right, closeTo(layout.mapArea.right, 0.01));
      expect(risk.bottom, closeTo(layout.mapArea.bottom, 0.01));
    });

    test('focus mode limits clutter while representing visible tasks', () {
      final layout = TaskTerrainLayout.build(
        _projection(count: 32),
        const Size(960, 560),
      );

      expect(layout.totalCount, 32);
      expect(layout.visibleCount, lessThanOrEqualTo(28));
      expect(_representedCount(layout), layout.visibleCount);
      expect(layout.cards, hasLength(layout.visibleCount));
      expect(layout.zones, isNotEmpty);
    });

    test('exposes all atlas zones with visible task counts', () {
      final layout = TaskTerrainLayout.build(
        _projection(count: 30),
        const Size(960, 560),
        mode: TaskTerrainViewMode.all,
      );

      expect(
        layout.zones.map((zone) => zone.definition.id),
        containsAll(<String>[
          'high-value-risk',
          'agent-opportunity',
          'quick-win',
          'risk',
          'steady-progress',
          'backlog',
        ]),
      );
      expect(
        layout.zones.fold<int>(0, (total, zone) => total + zone.taskCount),
        layout.visibleCount,
      );
    });

    test('uses a stable risk-confidence insight atlas', () {
      final layout = TaskTerrainLayout.build(
        PriorityTerrainProjection(
          bands: const <PriorityTerrainBand>[
            PriorityTerrainBand(id: 'confidence-gap', title: 'Confidence Gaps'),
            PriorityTerrainBand(id: 'stable-known', title: 'Known Stable'),
            PriorityTerrainBand(
              id: 'risk-blind-spot',
              title: 'Risk Blind Spots',
            ),
            PriorityTerrainBand(id: 'known-risk', title: 'Known Risks'),
          ],
          points: <PriorityTerrainPoint>[
            _point(
              1,
              urgency: 0.2,
              value: 0.2,
              effort: 0.2,
              risk: 0.8,
              elevation: 0.7,
              terrainZone: 'risk-blind-spot',
            ),
            _point(
              2,
              urgency: 0.2,
              value: 0.2,
              effort: 0.2,
              risk: 0.8,
              elevation: 0.7,
              terrainZone: 'known-risk',
            ),
          ],
        ),
        const Size(960, 560),
        mode: TaskTerrainViewMode.all,
      );

      expect(layout.xAxisLabel, 'Confidence');
      expect(layout.yAxisLabel, 'Risk');
      expect(
        _zoneRect(layout, TaskTerrainZoneKind.riskBlindSpot).top,
        _zoneRect(layout, TaskTerrainZoneKind.knownRisk).top,
      );
      expect(
        _zoneRect(layout, TaskTerrainZoneKind.riskBlindSpot).left,
        lessThan(_zoneRect(layout, TaskTerrainZoneKind.knownRisk).left),
      );
    });

    test('keeps hover-card anchors inside their semantic regions', () {
      final layout = TaskTerrainLayout.build(
        PriorityTerrainProjection(
          points: <PriorityTerrainPoint>[
            _point(
              1,
              urgency: 0.78,
              value: 0.82,
              effort: 0.56,
              risk: 0.34,
              elevation: 0.76,
              priority: 'urgent',
            ),
          ],
        ),
        const Size(960, 560),
      );

      final card = layout.cards.single;
      final zoneRect = _zoneRect(layout, TaskTerrainAtlas.zoneFor(card.point));
      expect(zoneRect.contains(card.anchor), isTrue);
      expect((card.rect.center - card.anchor).distance, greaterThan(8));
    });

    test('keeps atlas regions stable as task counts change', () {
      final layout = TaskTerrainLayout.build(
        PriorityTerrainProjection(
          points: <PriorityTerrainPoint>[
            for (var index = 0; index < 14; index++)
              _point(
                index,
                urgency: 0.35,
                value: 0.54,
                effort: 0.18,
                risk: 0.1,
                elevation: 0.52,
                terrainZone: 'quick-win',
              ),
            _point(
              20,
              urgency: 0.2,
              value: 0.2,
              effort: 0.3,
              risk: 0.1,
              elevation: 0.3,
              terrainZone: 'backlog',
            ),
            _point(
              21,
              urgency: 0.46,
              value: 0.68,
              effort: 0.42,
              risk: 0.22,
              elevation: 0.58,
              terrainZone: 'agent-opportunity',
            ),
          ],
        ),
        const Size(960, 560),
        mode: TaskTerrainViewMode.all,
      );
      final sparseLayout = TaskTerrainLayout.build(
        PriorityTerrainProjection(
          points: <PriorityTerrainPoint>[
            _point(
              30,
              urgency: 0.48,
              value: 0.66,
              effort: 0.28,
              risk: 0.18,
              elevation: 0.58,
              terrainZone: 'quick-win',
            ),
          ],
        ),
        const Size(960, 560),
        mode: TaskTerrainViewMode.all,
      );

      expect(
        _zoneRect(layout, TaskTerrainZoneKind.quickWin).width,
        closeTo(
          _zoneRect(sparseLayout, TaskTerrainZoneKind.quickWin).width,
          0.01,
        ),
      );
    });

    test('spreads similar-score tasks within the same terrain zone', () {
      final layout = TaskTerrainLayout.build(
        PriorityTerrainProjection(
          points: <PriorityTerrainPoint>[
            for (var index = 0; index < 12; index++)
              _point(
                index,
                urgency: 0.48,
                value: 0.66,
                effort: 0.28,
                risk: 0.18,
                elevation: 0.58,
                terrainZone: 'quick-win',
              ),
          ],
        ),
        const Size(960, 560),
        mode: TaskTerrainViewMode.all,
      );

      final centers = <Offset>[
        for (final pin in layout.pins) pin.center,
        for (final cluster in layout.clusters) cluster.center,
      ];
      final minX = centers
          .map((center) => center.dx)
          .reduce((a, b) => a < b ? a : b);
      final maxX = centers
          .map((center) => center.dx)
          .reduce((a, b) => a > b ? a : b);
      final minY = centers
          .map((center) => center.dy)
          .reduce((a, b) => a < b ? a : b);
      final maxY = centers
          .map((center) => center.dy)
          .reduce((a, b) => a > b ? a : b);

      expect(maxX - minX, greaterThan(130));
      expect(maxY - minY, greaterThan(60));
    });

    test('separates close two-task pin groups', () {
      final layout = TaskTerrainLayout.build(
        PriorityTerrainProjection(
          points: <PriorityTerrainPoint>[
            _point(
              1,
              urgency: 0.48,
              value: 0.66,
              effort: 0.28,
              risk: 0.18,
              elevation: 0.58,
              terrainZone: 'quick-win',
            ),
            _point(
              2,
              urgency: 0.48,
              value: 0.66,
              effort: 0.28,
              risk: 0.18,
              elevation: 0.58,
              terrainZone: 'quick-win',
            ),
          ],
        ),
        const Size(960, 560),
        mode: TaskTerrainViewMode.all,
      );

      expect(layout.pins, hasLength(2));
      expect(layout.clusters, isEmpty);
      expect(
        (layout.pins.first.center - layout.pins.last.center).distance,
        greaterThanOrEqualTo(32),
      );
    });

    test('all mode represents every task with cards, pins, or clusters', () {
      final layout = TaskTerrainLayout.build(
        _projection(count: 30),
        const Size(960, 560),
        mode: TaskTerrainViewMode.all,
      );

      expect(layout.totalCount, 30);
      expect(layout.visibleCount, 30);
      expect(layout.cards, hasLength(30));
      expect(_representedCount(layout), 30);
    });
  });
}

/// Returns one terrain zone rectangle by kind.
Rect _zoneRect(TaskTerrainLayout layout, TaskTerrainZoneKind kind) {
  return layout.zones.firstWhere((zone) => zone.definition.kind == kind).rect;
}

/// Returns the count of tasks represented by visible markers.
int _representedCount(TaskTerrainLayout layout) {
  return layout.pins.length +
      layout.clusters.fold<int>(
        0,
        (count, cluster) => count + cluster.points.length,
      );
}

/// Builds a projection with varied priorities, scores, and statuses.
PriorityTerrainProjection _projection({required int count}) {
  return PriorityTerrainProjection(
    points: <PriorityTerrainPoint>[
      for (var index = 0; index < count; index++)
        _point(
          index,
          urgency: 0.18 + (index % 7) * 0.11,
          value: 0.16 + (index % 5) * 0.15,
          effort: 0.18 + (index % 6) * 0.13,
          risk: 0.12 + (index % 4) * 0.2,
          elevation: 0.24 + (index % 8) * 0.08,
          status: index % 9 == 0 ? 'blocked' : 'open',
          priority: switch (index % 6) {
            0 => 'urgent',
            1 => 'high',
            2 => 'normal',
            3 => 'low',
            _ => 'normal',
          },
        ),
    ],
  );
}

/// Builds one terrain point with explicit normalized scoring.
PriorityTerrainPoint _point(
  int index, {
  required double urgency,
  required double value,
  required double effort,
  required double risk,
  required double elevation,
  String status = 'open',
  String priority = 'normal',
  String terrainZone = '',
  double reward = 0,
  double timePressure = 0,
  double agentFit = 0,
  double humanEffort = 0,
}) {
  return PriorityTerrainPoint(
    taskId: 'task-$index',
    title: 'Terrain task $index',
    status: status,
    priority: priority,
    urgencyScore: urgency.clamp(0, 1).toDouble(),
    valueScore: value.clamp(0, 1).toDouble(),
    effortScore: effort.clamp(0, 1).toDouble(),
    riskScore: risk.clamp(0, 1).toDouble(),
    rewardScore: reward.clamp(0, 1).toDouble(),
    timePressureScore: timePressure.clamp(0, 1).toDouble(),
    agentFitScore: agentFit.clamp(0, 1).toDouble(),
    humanEffortScore: humanEffort.clamp(0, 1).toDouble(),
    terrainZone: terrainZone,
    x: 0.5,
    y: 0.5,
    elevation: elevation.clamp(0, 1).toDouble(),
    explanation: 'Synthetic terrain task $index.',
  );
}
