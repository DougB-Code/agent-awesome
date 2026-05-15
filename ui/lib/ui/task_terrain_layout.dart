/// Computes readable priority terrain atlas layouts from task projections.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../domain/models.dart';

/// TaskTerrainViewMode controls how much terrain detail is represented.
enum TaskTerrainViewMode {
  /// Show the most important tasks as pins or clusters.
  focus,

  /// Show every projected task as a pin or cluster.
  all,
}

/// TaskTerrainZoneKind identifies one named terrain insight region.
enum TaskTerrainZoneKind {
  /// Valuable work with meaningful pressure or risk.
  highValueRisk,

  /// Valuable work the agent can likely help complete.
  agentOpportunity,

  /// Useful work with low human effort.
  quickWin,

  /// Blocked or uncertain work that may fail without attention.
  risk,

  /// Worthwhile work without immediate danger.
  steadyProgress,

  /// Low-pressure work that should not dominate attention.
  backlog,

  /// Work ready to delegate to an agent.
  readyForAgent,

  /// Work that needs review before delegation.
  needsReview,

  /// Work that should stay with a human.
  humanJudgment,

  /// Work that could become an agent handoff later.
  agentCandidate,

  /// Risky work with low confidence.
  riskBlindSpot,

  /// Risky work with enough confidence to act on.
  knownRisk,

  /// Lower-risk work with weak metadata.
  confidenceGap,

  /// Lower-risk work with enough confidence.
  stableKnown,

  /// Valuable work coming next week.
  highValueNextWeek,

  /// Valuable work that can be prepared early.
  prepareEarly,

  /// Next-week work that needs risk watch.
  watchRisk,

  /// Low-leverage next-week work.
  nextWeekBacklog,

  /// Blocker with high leverage and low effort.
  quickUnblock,

  /// Blocker with high leverage but more effort.
  highLeverageBlocker,

  /// Blocker with low effort but lower leverage.
  simpleBlocker,

  /// Blocker that is expensive for the value unlocked.
  costlyBlocker,
}

/// TaskTerrainAtlas defines the visible terrain vocabulary and score mapping.
class TaskTerrainAtlas {
  const TaskTerrainAtlas._();

  static const Color _coral = Color(0xffe95d4f);
  static const Color _green = Color(0xff2f6f3f);
  static const Color _teal = Color(0xff3d8f7a);
  static const Color _amber = Color(0xffd28b24);
  static const Color _purple = Color(0xff7b6398);
  static const Color _slate = Color(0xff746c5f);

  /// Priority-overview definitions used by layout, paint, and task markers.
  static const List<TaskTerrainZoneDefinition> priorityZones =
      <TaskTerrainZoneDefinition>[
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.risk,
          id: 'risk',
          label: 'Risk & blockers',
          description: 'Uncertain, waiting, or stuck work',
          color: _purple,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.highValueRisk,
          id: 'high-value-risk',
          label: 'High value + pressure',
          description: 'Costly to miss, worth doing soon',
          color: _coral,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.steadyProgress,
          id: 'steady-progress',
          label: 'Steady progress',
          description: 'Important work with room to sequence',
          color: _green,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.backlog,
          id: 'backlog',
          label: 'Backlog',
          description: 'Low-pressure work to keep bounded',
          color: _slate,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.quickWin,
          id: 'quick-win',
          label: 'Quick wins',
          description: 'Low effort, useful lift',
          color: _amber,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.agentOpportunity,
          id: 'agent-opportunity',
          label: 'Agent opportunity',
          description: 'High reward with good agent fit',
          color: _teal,
        ),
      ];

  /// Agent delegation definitions for the handoff insight atlas.
  static const List<TaskTerrainZoneDefinition> agentHandoffZones =
      <TaskTerrainZoneDefinition>[
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.agentCandidate,
          id: 'agent-candidate',
          label: 'Candidate later',
          description: 'Possible handoff after better context',
          color: _slate,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.readyForAgent,
          id: 'ready-for-agent',
          label: 'Ready for agent',
          description: 'Clear enough to delegate',
          color: _teal,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.needsReview,
          id: 'needs-review',
          label: 'Needs review',
          description: 'Clarify safety, context, or scope',
          color: _amber,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.humanJudgment,
          id: 'human-judgment',
          label: 'Human judgment',
          description: 'Keep with a person for now',
          color: _purple,
        ),
      ];

  /// Risk definitions for the risk insight atlas.
  static const List<TaskTerrainZoneDefinition> riskFocusZones =
      <TaskTerrainZoneDefinition>[
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.confidenceGap,
          id: 'low-risk',
          label: 'Low risk',
          description: 'Lower due-date risk',
          color: _amber,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.stableKnown,
          id: 'rising-risk',
          label: 'Watch risk',
          description: 'Timing pressure is rising',
          color: _green,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.riskBlindSpot,
          id: 'high-risk',
          label: 'High risk',
          description: 'Due-date risk is high',
          color: _coral,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.knownRisk,
          id: 'urgent-risk',
          label: 'Urgent risk',
          description: 'Immediate timing pressure',
          color: _purple,
        ),
      ];

  /// Next-week value definitions for upcoming work.
  static const List<TaskTerrainZoneDefinition> nextWeekZones =
      <TaskTerrainZoneDefinition>[
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.nextWeekBacklog,
          id: 'next-week-backlog',
          label: 'Lower value',
          description: 'Keep bounded or defer',
          color: _slate,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.prepareEarly,
          id: 'prepare-early',
          label: 'Prepare early',
          description: 'Valuable with scheduling room',
          color: _green,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.watchRisk,
          id: 'watch-risk',
          label: 'Watch risk',
          description: 'Valuable but vulnerable',
          color: _amber,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.highValueNextWeek,
          id: 'high-value-next-week',
          label: 'High value',
          description: 'High consequence next week',
          color: _coral,
        ),
      ];

  /// Unblock leverage definitions for dependency work.
  static const List<TaskTerrainZoneDefinition> unblockZones =
      <TaskTerrainZoneDefinition>[
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.simpleBlocker,
          id: 'simple-blocker',
          label: 'Simple blockers',
          description: 'Low effort with modest leverage',
          color: _green,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.quickUnblock,
          id: 'quick-unblock',
          label: 'Quick unblocks',
          description: 'Low effort, high downstream value',
          color: _teal,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.costlyBlocker,
          id: 'costly-blocker',
          label: 'Costly blockers',
          description: 'High effort for limited leverage',
          color: _purple,
        ),
        TaskTerrainZoneDefinition(
          kind: TaskTerrainZoneKind.highLeverageBlocker,
          id: 'high-leverage-blocker',
          label: 'High leverage',
          description: 'Worth effort because it unlocks work',
          color: _coral,
        ),
      ];

  /// Returns the atlas zones implied by a terrain projection.
  static List<TaskTerrainZoneDefinition> zonesFor(
    PriorityTerrainProjection projection,
  ) {
    final ids = projection.bands.map((band) => band.id).toSet();
    if (ids.contains('high-risk') || ids.contains('urgent-risk')) {
      return riskFocusZones;
    }
    if (ids.contains('ready-for-agent') || ids.contains('human-judgment')) {
      return agentHandoffZones;
    }
    if (ids.contains('high-value-next-week')) {
      return nextWeekZones;
    }
    if (ids.contains('quick-unblock') ||
        ids.contains('high-leverage-blocker')) {
      return unblockZones;
    }
    return priorityZones;
  }

  /// Returns the shared zone definition for a task in a projection.
  static TaskTerrainZoneDefinition definitionForPointInProjection(
    PriorityTerrainPoint point,
    PriorityTerrainProjection projection,
  ) {
    return definitionForKind(zoneFor(point), zonesFor(projection));
  }

  /// Returns the drawable score plot area inside a terrain canvas.
  static Rect plotArea(Size size) {
    return Offset.zero &
        Size(math.max(1.0, size.width), math.max(1.0, size.height));
  }

  /// Returns the shared zone definition for a task.
  static TaskTerrainZoneDefinition definitionForPoint(
    PriorityTerrainPoint point,
  ) {
    return definitionForKind(zoneFor(point), priorityZones);
  }

  /// Returns the shared zone definition for a zone kind.
  static TaskTerrainZoneDefinition definitionFor(TaskTerrainZoneKind kind) {
    return definitionForKind(kind, priorityZones);
  }

  /// Returns a zone definition from one atlas.
  static TaskTerrainZoneDefinition definitionForKind(
    TaskTerrainZoneKind kind,
    List<TaskTerrainZoneDefinition> definitions,
  ) {
    final allDefinitions = <TaskTerrainZoneDefinition>[
      ...priorityZones,
      ...agentHandoffZones,
      ...riskFocusZones,
      ...nextWeekZones,
      ...unblockZones,
    ];
    return definitions.firstWhere(
      (definition) => definition.kind == kind,
      orElse: () {
        return allDefinitions.firstWhere(
          (definition) => definition.kind == kind,
        );
      },
    );
  }

  /// Returns a task's semantic terrain zone.
  static TaskTerrainZoneKind zoneFor(PriorityTerrainPoint point) {
    switch (point.terrainZone) {
      case 'high-value-risk':
        return TaskTerrainZoneKind.highValueRisk;
      case 'agent-opportunity':
        return TaskTerrainZoneKind.agentOpportunity;
      case 'quick-win':
        return TaskTerrainZoneKind.quickWin;
      case 'risk':
        return TaskTerrainZoneKind.risk;
      case 'steady-progress':
        return TaskTerrainZoneKind.steadyProgress;
      case 'backlog':
        return TaskTerrainZoneKind.backlog;
      case 'ready-for-agent':
        return TaskTerrainZoneKind.readyForAgent;
      case 'needs-review':
        return TaskTerrainZoneKind.needsReview;
      case 'human-judgment':
        return TaskTerrainZoneKind.humanJudgment;
      case 'agent-candidate':
        return TaskTerrainZoneKind.agentCandidate;
      case 'high-risk':
        return TaskTerrainZoneKind.riskBlindSpot;
      case 'urgent-risk':
        return TaskTerrainZoneKind.knownRisk;
      case 'low-risk':
        return TaskTerrainZoneKind.confidenceGap;
      case 'rising-risk':
        return TaskTerrainZoneKind.stableKnown;
      case 'high-value-next-week':
        return TaskTerrainZoneKind.highValueNextWeek;
      case 'prepare-early':
        return TaskTerrainZoneKind.prepareEarly;
      case 'watch-risk':
        return TaskTerrainZoneKind.watchRisk;
      case 'next-week-backlog':
        return TaskTerrainZoneKind.nextWeekBacklog;
      case 'quick-unblock':
        return TaskTerrainZoneKind.quickUnblock;
      case 'high-leverage-blocker':
        return TaskTerrainZoneKind.highLeverageBlocker;
      case 'simple-blocker':
        return TaskTerrainZoneKind.simpleBlocker;
      case 'costly-blocker':
        return TaskTerrainZoneKind.costlyBlocker;
    }
    final reward = _scoreOr(point.rewardScore, point.valueScore, fallback: 0);
    final pressure = _scoreOr(
      point.urgencyScore,
      point.timePressureScore,
      fallback: 0,
    );
    final risk = point.riskScore.clamp(0, 1).toDouble();
    final effort = point.humanEffortScore > 0
        ? point.humanEffortScore
        : point.effortScore;
    final agentFit = point.agentFitScore.clamp(0, 1).toDouble();
    if (reward >= 0.64 && (risk >= 0.58 || pressure >= 0.66)) {
      return TaskTerrainZoneKind.highValueRisk;
    }
    if (reward >= 0.62 && agentFit >= 0.58 && risk < 0.58) {
      return TaskTerrainZoneKind.agentOpportunity;
    }
    if (reward >= 0.50 && effort <= 0.36 && risk < 0.52) {
      return TaskTerrainZoneKind.quickWin;
    }
    if (risk >= 0.60 || point.status == 'blocked') {
      return TaskTerrainZoneKind.risk;
    }
    if (reward >= 0.54) {
      return TaskTerrainZoneKind.steadyProgress;
    }
    return TaskTerrainZoneKind.backlog;
  }

  /// Returns a compact explanation cue for one task card.
  static String cueFor(PriorityTerrainPoint point) {
    final reward = _scoreOr(point.rewardScore, point.valueScore, fallback: 0);
    final pressure = _scoreOr(
      point.urgencyScore,
      point.timePressureScore,
      fallback: 0,
    );
    final risk = point.riskScore.clamp(0, 1).toDouble();
    final effort = point.humanEffortScore > 0
        ? point.humanEffortScore
        : point.effortScore;
    if (point.status == 'blocked' || risk >= 0.64) {
      return 'Risk ${_percent(risk)} · needs unblock';
    }
    if (point.agentFitScore >= 0.58 && reward >= 0.56) {
      return 'Agent fit ${_percent(point.agentFitScore)} · reward ${_percent(reward)}';
    }
    if (effort <= 0.36 && reward >= 0.42) {
      return 'Low effort · reward ${_percent(reward)}';
    }
    if (pressure >= 0.68) {
      return 'Pressure ${_percent(pressure)} · reward ${_percent(reward)}';
    }
    if (reward >= 0.56) {
      return 'Reward ${_percent(reward)} · pressure ${_percent(pressure)}';
    }
    return 'Pressure ${_percent(pressure)} · effort ${_percent(effort)}';
  }

  /// Returns a normalized score with fallback handling.
  static double _scoreOr(
    double primary,
    double secondary, {
    required double fallback,
  }) {
    if (primary > 0) {
      return primary.clamp(0, 1).toDouble();
    }
    if (secondary > 0) {
      return secondary.clamp(0, 1).toDouble();
    }
    return fallback;
  }

  /// Spreads normalized scores away from hard edges.
  static double spread01(double value) {
    final clamped = value.clamp(0, 1).toDouble();
    return 0.08 + clamped * 0.84;
  }

  /// Formats a normalized score as a compact percentage.
  static String _percent(double value) {
    return '${(value.clamp(0, 1) * 100).round()}%';
  }
}

/// TaskTerrainZoneDefinition configures one named insight region.
class TaskTerrainZoneDefinition {
  /// Creates a terrain zone definition.
  const TaskTerrainZoneDefinition({
    required this.kind,
    required this.id,
    required this.label,
    required this.description,
    required this.color,
  });

  /// Semantic terrain zone kind.
  final TaskTerrainZoneKind kind;

  /// Stable terrain zone id.
  final String id;

  /// User-facing region label.
  final String label;

  /// User-facing short region description.
  final String description;

  /// Region color.
  final Color color;
}

/// TaskTerrainLayout stores all render-ready terrain geometry.
class TaskTerrainLayout {
  /// Creates a computed terrain layout.
  const TaskTerrainLayout({
    required this.size,
    required this.mapArea,
    required this.mode,
    required this.xAxisLabel,
    required this.yAxisLabel,
    required this.totalCount,
    required this.visibleCount,
    required this.zones,
    required this.cards,
    required this.pins,
    required this.clusters,
  });

  static const int _focusMarkerLimit = 28;
  static const double _padding = 10;

  /// Canvas size used by the layout.
  final Size size;

  /// Score plot area used for terrain regions.
  final Rect mapArea;

  /// Active terrain view mode.
  final TaskTerrainViewMode mode;

  /// Label for the horizontal score axis.
  final String xAxisLabel;

  /// Label for the vertical score axis.
  final String yAxisLabel;

  /// Total terrain task count before filtering.
  final int totalCount;

  /// Count of points represented in this layout.
  final int visibleCount;

  /// Named semantic terrain regions.
  final List<TaskTerrainZoneRegion> zones;

  /// Hover cards for visible tasks.
  final List<TaskTerrainCardPlacement> cards;

  /// Individual task pin placements.
  final List<TaskTerrainPinPlacement> pins;

  /// Clustered low-detail task placements.
  final List<TaskTerrainClusterPlacement> clusters;

  /// Builds a pin-first terrain layout for a projection.
  static TaskTerrainLayout build(
    PriorityTerrainProjection projection,
    Size size, {
    TaskTerrainViewMode mode = TaskTerrainViewMode.focus,
  }) {
    final viewport = Size(math.max(1, size.width), math.max(1, size.height));
    final sorted = projection.points.toList()
      ..sort((left, right) {
        return _importance(right).compareTo(_importance(left));
      });
    final visible = _visiblePoints(sorted, mode);
    final zones = _zoneRegions(projection, visible, viewport);
    final zoneMap = <TaskTerrainZoneKind, TaskTerrainZoneRegion>{
      for (final zone in zones) zone.definition.kind: zone,
    };
    final totals = <TaskTerrainZoneKind, int>{
      for (final zone in zones) zone.definition.kind: zone.taskCount,
    };
    final indexes = <TaskTerrainZoneKind, int>{};
    final anchors = <String, Offset>{};
    for (final point in visible) {
      final zone = _zoneForPoint(point, zoneMap);
      final ordinal = indexes[zone] ?? 0;
      indexes[zone] = ordinal + 1;
      anchors[point.taskId] = _anchorInZone(
        point,
        zoneMap,
        ordinal: ordinal,
        totalInZone: math.max(1, totals[zone] ?? 1),
      );
    }
    final groupedPins = _placePins(visible, anchors, zoneMap, viewport);
    final cards = _placeCards(visible, anchors, zoneMap, viewport);
    return TaskTerrainLayout(
      size: viewport,
      mapArea: TaskTerrainAtlas.plotArea(viewport),
      mode: mode,
      xAxisLabel: _axisLabels(projection).x,
      yAxisLabel: _axisLabels(projection).y,
      totalCount: projection.points.length,
      visibleCount: visible.length,
      zones: zones,
      cards: cards,
      pins: groupedPins.pins,
      clusters: groupedPins.clusters,
    );
  }

  /// Returns points visible in the requested view mode.
  static List<PriorityTerrainPoint> _visiblePoints(
    List<PriorityTerrainPoint> sorted,
    TaskTerrainViewMode mode,
  ) {
    if (mode == TaskTerrainViewMode.all) {
      return sorted;
    }
    final important = <PriorityTerrainPoint>[
      for (final point in sorted)
        if (_importance(point) >= 0.42 ||
            point.priority == 'urgent' ||
            point.priority == 'high' ||
            point.status == 'blocked')
          point,
    ];
    if (important.length >= 12) {
      return important.take(_focusMarkerLimit).toList();
    }
    return sorted.take(math.min(_focusMarkerLimit, sorted.length)).toList();
  }

  /// Returns mode-aware axis labels for the terrain projection.
  static ({String x, String y}) _axisLabels(
    PriorityTerrainProjection projection,
  ) {
    final ids = projection.bands.map((band) => band.id).toSet();
    if (ids.contains('high-risk') || ids.contains('urgent-risk')) {
      return (x: 'Time pressure', y: 'Risk');
    }
    if (ids.contains('ready-for-agent') || ids.contains('human-judgment')) {
      return (x: 'Handoff readiness', y: 'Obligation');
    }
    if (ids.contains('high-value-next-week')) {
      return (x: 'Reward', y: 'Consequence');
    }
    if (ids.contains('quick-unblock') ||
        ids.contains('high-leverage-blocker')) {
      return (x: 'Unblock leverage', y: 'Blocker effort');
    }
    return (x: 'Reward', y: 'Pressure');
  }

  /// Returns a point zone that exists in the current atlas.
  static TaskTerrainZoneKind _zoneForPoint(
    PriorityTerrainPoint point,
    Map<TaskTerrainZoneKind, TaskTerrainZoneRegion> zones,
  ) {
    return _zoneForPointKind(point, zones.keys.toSet());
  }

  /// Returns a point zone for an atlas definition set.
  static TaskTerrainZoneKind _zoneForPointKind(
    PriorityTerrainPoint point,
    Set<TaskTerrainZoneKind> available,
  ) {
    final semantic = TaskTerrainAtlas.zoneFor(point);
    if (available.contains(semantic)) {
      return semantic;
    }
    final highX = point.x >= 0.5;
    final highY = point.y >= 0.5;
    if (available.contains(TaskTerrainZoneKind.riskBlindSpot)) {
      if (!highX && highY) {
        return TaskTerrainZoneKind.riskBlindSpot;
      }
      if (highX && highY) {
        return TaskTerrainZoneKind.knownRisk;
      }
      return highX
          ? TaskTerrainZoneKind.stableKnown
          : TaskTerrainZoneKind.confidenceGap;
    }
    if (available.contains(TaskTerrainZoneKind.readyForAgent)) {
      if (highX && !highY) {
        return TaskTerrainZoneKind.readyForAgent;
      }
      if (highX && highY) {
        return TaskTerrainZoneKind.humanJudgment;
      }
      return highY
          ? TaskTerrainZoneKind.needsReview
          : TaskTerrainZoneKind.agentCandidate;
    }
    if (available.contains(TaskTerrainZoneKind.highValueNextWeek)) {
      if (highX && highY) {
        return TaskTerrainZoneKind.highValueNextWeek;
      }
      if (highX) {
        return TaskTerrainZoneKind.prepareEarly;
      }
      return highY
          ? TaskTerrainZoneKind.watchRisk
          : TaskTerrainZoneKind.nextWeekBacklog;
    }
    if (available.contains(TaskTerrainZoneKind.quickUnblock)) {
      if (highX && !highY) {
        return TaskTerrainZoneKind.quickUnblock;
      }
      if (highX && highY) {
        return TaskTerrainZoneKind.highLeverageBlocker;
      }
      return highY
          ? TaskTerrainZoneKind.costlyBlocker
          : TaskTerrainZoneKind.simpleBlocker;
    }
    return available.isEmpty ? semantic : available.first;
  }

  /// Returns fixed, touching terrain zone rectangles for the projection atlas.
  static List<TaskTerrainZoneRegion> _zoneRegions(
    PriorityTerrainProjection projection,
    List<PriorityTerrainPoint> points,
    Size size,
  ) {
    final counts = <TaskTerrainZoneKind, int>{};
    final definitions = TaskTerrainAtlas.zonesFor(projection);
    final definitionKinds = definitions
        .map((definition) => definition.kind)
        .toSet();
    for (final point in points) {
      final zone = _zoneForPointKind(point, definitionKinds);
      counts[zone] = (counts[zone] ?? 0) + 1;
    }
    final area = TaskTerrainAtlas.plotArea(size);
    final rects = _fixedRectsForDefinitions(definitions, area);
    return <TaskTerrainZoneRegion>[
      for (final definition in definitions)
        TaskTerrainZoneRegion(
          definition: definition,
          rect: rects[definition.kind]!,
          taskCount: counts[definition.kind] ?? 0,
        ),
    ];
  }

  /// Returns stable rectangles for one qualitative atlas.
  static Map<TaskTerrainZoneKind, Rect> _fixedRectsForDefinitions(
    List<TaskTerrainZoneDefinition> definitions,
    Rect area,
  ) {
    final kinds = definitions.map((definition) => definition.kind).toSet();
    if (kinds.contains(TaskTerrainZoneKind.riskBlindSpot)) {
      return _quadrantRects(
        area,
        topLeft: TaskTerrainZoneKind.confidenceGap,
        topRight: TaskTerrainZoneKind.stableKnown,
        bottomLeft: TaskTerrainZoneKind.riskBlindSpot,
        bottomRight: TaskTerrainZoneKind.knownRisk,
      );
    }
    if (kinds.contains(TaskTerrainZoneKind.readyForAgent)) {
      return _quadrantRects(
        area,
        topLeft: TaskTerrainZoneKind.agentCandidate,
        topRight: TaskTerrainZoneKind.readyForAgent,
        bottomLeft: TaskTerrainZoneKind.needsReview,
        bottomRight: TaskTerrainZoneKind.humanJudgment,
      );
    }
    if (kinds.contains(TaskTerrainZoneKind.highValueNextWeek)) {
      return _quadrantRects(
        area,
        topLeft: TaskTerrainZoneKind.nextWeekBacklog,
        topRight: TaskTerrainZoneKind.prepareEarly,
        bottomLeft: TaskTerrainZoneKind.watchRisk,
        bottomRight: TaskTerrainZoneKind.highValueNextWeek,
      );
    }
    if (kinds.contains(TaskTerrainZoneKind.quickUnblock)) {
      return _quadrantRects(
        area,
        topLeft: TaskTerrainZoneKind.simpleBlocker,
        topRight: TaskTerrainZoneKind.quickUnblock,
        bottomLeft: TaskTerrainZoneKind.costlyBlocker,
        bottomRight: TaskTerrainZoneKind.highLeverageBlocker,
      );
    }
    final top = Rect.fromLTWH(
      area.left,
      area.top,
      area.width,
      area.height * 0.42,
    );
    final middle = Rect.fromLTWH(
      area.left,
      top.bottom,
      area.width,
      area.height * 0.20,
    );
    final bottom = Rect.fromLTRB(
      area.left,
      middle.bottom,
      area.right,
      area.bottom,
    );
    return <TaskTerrainZoneKind, Rect>{
      TaskTerrainZoneKind.backlog: Rect.fromLTWH(
        top.left,
        top.top,
        top.width * 0.18,
        top.height,
      ),
      TaskTerrainZoneKind.quickWin: Rect.fromLTWH(
        top.left + top.width * 0.18,
        top.top,
        top.width * 0.42,
        top.height,
      ),
      TaskTerrainZoneKind.agentOpportunity: Rect.fromLTRB(
        top.left + top.width * 0.60,
        top.top,
        top.right,
        top.bottom,
      ),
      TaskTerrainZoneKind.steadyProgress: middle,
      TaskTerrainZoneKind.risk: Rect.fromLTWH(
        bottom.left,
        bottom.top,
        bottom.width * 0.35,
        bottom.height,
      ),
      TaskTerrainZoneKind.highValueRisk: Rect.fromLTRB(
        bottom.left + bottom.width * 0.35,
        bottom.top,
        bottom.right,
        bottom.bottom,
      ),
    };
  }

  /// Splits the map area into four stable insight quadrants.
  static Map<TaskTerrainZoneKind, Rect> _quadrantRects(
    Rect area, {
    required TaskTerrainZoneKind topLeft,
    required TaskTerrainZoneKind topRight,
    required TaskTerrainZoneKind bottomLeft,
    required TaskTerrainZoneKind bottomRight,
  }) {
    final midX = area.left + area.width / 2;
    final midY = area.top + area.height / 2;
    return <TaskTerrainZoneKind, Rect>{
      topLeft: Rect.fromLTRB(area.left, area.top, midX, midY),
      topRight: Rect.fromLTRB(midX, area.top, area.right, midY),
      bottomLeft: Rect.fromLTRB(area.left, midY, midX, area.bottom),
      bottomRight: Rect.fromLTRB(midX, midY, area.right, area.bottom),
    };
  }

  /// Returns a point's visual anchor inside its semantic zone.
  static Offset _anchorInZone(
    PriorityTerrainPoint point,
    Map<TaskTerrainZoneKind, TaskTerrainZoneRegion> zones, {
    required int ordinal,
    required int totalInZone,
  }) {
    final region = zones[_zoneForPoint(point, zones)]!;
    final xScore = point.x > 0
        ? point.x.clamp(0, 1).toDouble()
        : _scoreOr(point.rewardScore, point.valueScore, fallback: 0.5);
    final yScore = point.y > 0
        ? point.y.clamp(0, 1).toDouble()
        : _scoreOr(point.urgencyScore, point.timePressureScore, fallback: 0.5);
    final padding = math.min(
      26.0,
      math.max(10.0, region.rect.shortestSide * 0.12),
    );
    final width = math.max(1.0, region.rect.width - padding * 2);
    final height = math.max(1.0, region.rect.height - padding * 2);
    final scoreX = TaskTerrainAtlas.spread01(xScore);
    final scoreY = TaskTerrainAtlas.spread01(yScore);
    final dispersed = _dispersedUnit(point, ordinal, totalInZone);
    final dispersion = totalInZone < 3
        ? 0.22
        : math.min(0.82, 0.50 + totalInZone * 0.024);
    final xUnit = _lerp(scoreX, dispersed.dx, dispersion);
    final yUnit = _lerp(scoreY, dispersed.dy, dispersion);
    return Offset(
      region.rect.left + padding + xUnit.clamp(0.06, 0.94) * width,
      region.rect.top + padding + yUnit.clamp(0.06, 0.94) * height,
    );
  }

  /// Places task pins and nearby count clusters.
  static _TerrainPinGroups _placePins(
    List<PriorityTerrainPoint> points,
    Map<String, Offset> anchors,
    Map<TaskTerrainZoneKind, TaskTerrainZoneRegion> zones,
    Size size,
  ) {
    final groups = <_MutablePinGroup>[];
    final threshold = math.max(38.0, math.min(size.shortestSide * 0.06, 48.0));
    for (final point in points) {
      final zoneKind = _zoneForPoint(point, zones);
      final anchor = anchors[point.taskId]!;
      _MutablePinGroup? target;
      var nearest = double.infinity;
      for (final group in groups) {
        if (group.zoneKind != zoneKind) {
          continue;
        }
        final distance = (anchor - group.center).distance;
        if (distance < threshold && distance < nearest) {
          target = group;
          nearest = distance;
        }
      }
      if (target == null) {
        groups.add(
          _MutablePinGroup(
            zoneKind: zoneKind,
            center: anchor,
            points: <PriorityTerrainPoint>[point],
          ),
        );
      } else {
        target.add(point, anchor);
      }
    }
    final pins = <TaskTerrainPinPlacement>[];
    final clusters = <TaskTerrainClusterPlacement>[];
    for (final group in groups) {
      final region = zones[group.zoneKind]!;
      final definition = region.definition;
      if (group.points.length >= 3) {
        clusters.add(
          TaskTerrainClusterPlacement(
            points: List<PriorityTerrainPoint>.unmodifiable(group.points),
            center: group.center,
            zone: definition,
            color: definition.color,
          ),
        );
      } else {
        final centers = _pinCentersForGroup(group, anchors, region.rect);
        for (var index = 0; index < group.points.length; index++) {
          final point = group.points[index];
          pins.add(
            TaskTerrainPinPlacement(
              point: point,
              center: centers[index],
              zone: definition,
              color: definition.color,
              label: _pinLabel(point),
            ),
          );
        }
      }
    }
    return _TerrainPinGroups(pins: pins, clusters: clusters);
  }

  /// Returns non-overlapping pin centers for a small nearby marker group.
  static List<Offset> _pinCentersForGroup(
    _MutablePinGroup group,
    Map<String, Offset> anchors,
    Rect zoneRect,
  ) {
    if (group.points.length == 1) {
      return <Offset>[anchors[group.points.single.taskId]!];
    }
    final first = anchors[group.points.first.taskId]!;
    final second = anchors[group.points[1].taskId]!;
    final delta = second - first;
    final distance = delta.distance;
    final direction = distance <= 0.01
        ? _angleDirection(_hashUnit(group.points.first.taskId) * math.pi * 2)
        : Offset(-delta.dy / distance, delta.dx / distance);
    final radius = math.max(16.0, math.min(19.0, zoneRect.shortestSide * 0.08));
    final safeRect = _safeMarkerRect(zoneRect);
    return <Offset>[
      _clampPoint(group.center - direction * radius, safeRect),
      _clampPoint(group.center + direction * radius, safeRect),
    ];
  }

  /// Returns a direction vector from an angle.
  static Offset _angleDirection(double angle) {
    return Offset(math.cos(angle), math.sin(angle));
  }

  /// Returns the usable pin center bounds inside a terrain zone.
  static Rect _safeMarkerRect(Rect rect) {
    final inset = math.min(18.0, rect.shortestSide / 3);
    return Rect.fromLTRB(
      rect.left + inset,
      rect.top + inset,
      rect.right - inset,
      rect.bottom - inset,
    );
  }

  /// Clamps a point inside a rectangle.
  static Offset _clampPoint(Offset point, Rect rect) {
    return Offset(
      point.dx.clamp(rect.left, rect.right).toDouble(),
      point.dy.clamp(rect.top, rect.bottom).toDouble(),
    );
  }

  /// Returns hover card placements for every visible task.
  static List<TaskTerrainCardPlacement> _placeCards(
    List<PriorityTerrainPoint> points,
    Map<String, Offset> anchors,
    Map<TaskTerrainZoneKind, TaskTerrainZoneRegion> zones,
    Size size,
  ) {
    return <TaskTerrainCardPlacement>[
      for (final point in points)
        _cardFor(point, anchors[point.taskId]!, zones, size),
    ];
  }

  /// Returns one hover card placement.
  static TaskTerrainCardPlacement _cardFor(
    PriorityTerrainPoint point,
    Offset anchor,
    Map<TaskTerrainZoneKind, TaskTerrainZoneRegion> zones,
    Size size,
  ) {
    final zoneKind = TaskTerrainAtlas.zoneFor(point);
    final resolvedZoneKind = zones.containsKey(zoneKind)
        ? zoneKind
        : _zoneForPoint(point, zones);
    final definition = zones[resolvedZoneKind]!.definition;
    final cardSize = _cardSize(point);
    final target = _cardTarget(anchor, resolvedZoneKind);
    return TaskTerrainCardPlacement(
      point: point,
      rect: _clampRect(
        Rect.fromCenter(
          center: target,
          width: cardSize.width,
          height: cardSize.height,
        ),
        size,
      ),
      anchor: anchor,
      zone: definition,
      color: definition.color,
      cue: TaskTerrainAtlas.cueFor(point),
    );
  }

  /// Returns the preferred hover-card center near a pin.
  static Offset _cardTarget(Offset anchor, TaskTerrainZoneKind zone) {
    return anchor + _cardDirection(zone) * 72;
  }

  /// Returns the preferred card offset direction for one zone.
  static Offset _cardDirection(TaskTerrainZoneKind zone) {
    return switch (zone) {
      TaskTerrainZoneKind.highValueRisk => const Offset(-0.80, 0.44),
      TaskTerrainZoneKind.agentOpportunity => const Offset(-0.74, -0.50),
      TaskTerrainZoneKind.quickWin => const Offset(0.60, -0.58),
      TaskTerrainZoneKind.risk => const Offset(0.72, 0.48),
      TaskTerrainZoneKind.steadyProgress => const Offset(0.26, 0.72),
      TaskTerrainZoneKind.backlog => const Offset(0.72, -0.46),
      TaskTerrainZoneKind.readyForAgent => const Offset(-0.72, -0.48),
      TaskTerrainZoneKind.needsReview => const Offset(0.70, 0.46),
      TaskTerrainZoneKind.humanJudgment => const Offset(-0.72, 0.46),
      TaskTerrainZoneKind.agentCandidate => const Offset(0.70, -0.46),
      TaskTerrainZoneKind.riskBlindSpot => const Offset(0.74, 0.48),
      TaskTerrainZoneKind.knownRisk => const Offset(-0.74, 0.48),
      TaskTerrainZoneKind.confidenceGap => const Offset(0.70, -0.46),
      TaskTerrainZoneKind.stableKnown => const Offset(-0.70, -0.46),
      TaskTerrainZoneKind.highValueNextWeek => const Offset(-0.76, 0.44),
      TaskTerrainZoneKind.prepareEarly => const Offset(-0.70, -0.48),
      TaskTerrainZoneKind.watchRisk => const Offset(0.72, 0.48),
      TaskTerrainZoneKind.nextWeekBacklog => const Offset(0.70, -0.46),
      TaskTerrainZoneKind.quickUnblock => const Offset(-0.72, -0.48),
      TaskTerrainZoneKind.highLeverageBlocker => const Offset(-0.76, 0.44),
      TaskTerrainZoneKind.simpleBlocker => const Offset(0.70, -0.46),
      TaskTerrainZoneKind.costlyBlocker => const Offset(0.72, 0.48),
    };
  }

  /// Returns a visual card size based on human effort.
  static Size _cardSize(PriorityTerrainPoint point) {
    final effort =
        (point.humanEffortScore > 0
                ? point.humanEffortScore
                : point.effortScore)
            .clamp(0, 1)
            .toDouble();
    return Size(160 + effort * 48, 94 + effort * 12);
  }

  /// Clamps a card rectangle within the canvas.
  static Rect _clampRect(Rect rect, Size size) {
    final left = rect.left.clamp(
      _padding,
      math.max(_padding, size.width - rect.width - _padding),
    );
    final top = rect.top.clamp(
      _padding,
      math.max(_padding, size.height - rect.height - _padding),
    );
    return Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      rect.width,
      rect.height,
    );
  }

  /// Returns a normalized score with secondary fallback handling.
  static double _scoreOr(
    double primary,
    double secondary, {
    required double fallback,
  }) {
    if (primary > 0) {
      return primary.clamp(0, 1).toDouble();
    }
    if (secondary > 0) {
      return secondary.clamp(0, 1).toDouble();
    }
    return fallback;
  }

  /// Returns a deterministic low-discrepancy coordinate inside a zone.
  static Offset _dispersedUnit(
    PriorityTerrainPoint point,
    int ordinal,
    int totalInZone,
  ) {
    final salt = (_hashUnit(point.taskId) * 13).floor();
    final index = ordinal + salt + 1;
    final ring = math.sqrt((ordinal + 0.5) / totalInZone).clamp(0.0, 1.0);
    final angle =
        ordinal * math.pi * (3 - math.sqrt(5)) +
        _hashUnit(point.title) * math.pi;
    final radial = Offset(
      0.5 + math.cos(angle) * ring * 0.36,
      0.5 + math.sin(angle) * ring * 0.56,
    );
    final halton = Offset(
      0.12 + _halton(index, 2) * 0.76,
      0.02 + _halton(index, 3) * 0.96,
    );
    return Offset(
      _lerp(radial.dx, halton.dx, 0.52),
      _lerp(radial.dy, halton.dy, 0.52),
    );
  }

  /// Returns one Halton sequence value for a positive index and base.
  static double _halton(int index, int base) {
    var result = 0.0;
    var fraction = 1.0 / base;
    var value = index;
    while (value > 0) {
      result += fraction * (value % base);
      value = value ~/ base;
      fraction /= base;
    }
    return result;
  }

  /// Linearly interpolates between two doubles.
  static double _lerp(double start, double end, double amount) {
    return start + (end - start) * amount;
  }

  /// Returns a deterministic fractional value for a string.
  static double _hashUnit(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = 0x1fffffff & (hash + unit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return (hash & 0x0fffffff) / 0x0fffffff;
  }

  /// Returns a compact pin label for one task.
  static String _pinLabel(PriorityTerrainPoint point) {
    return (point.elevation * 9 + 1).round().clamp(1, 10).toString();
  }

  /// Returns an importance score used for focus filtering.
  static double _importance(PriorityTerrainPoint point) {
    final priorityBoost = switch (point.priority) {
      'urgent' => 0.18,
      'high' => 0.1,
      'low' => -0.04,
      _ => 0.0,
    };
    final statusBoost = point.status == 'blocked' ? 0.1 : 0.0;
    return (point.urgencyScore * 0.3 +
            point.valueScore * 0.28 +
            point.riskScore * 0.16 +
            point.elevation * 0.16 +
            (1 - point.effortScore.clamp(0, 1)) * 0.06 +
            priorityBoost +
            statusBoost)
        .clamp(0, 1)
        .toDouble();
  }
}

/// TaskTerrainZoneRegion stores one resolved visible zone.
class TaskTerrainZoneRegion {
  /// Creates a resolved terrain zone region.
  const TaskTerrainZoneRegion({
    required this.definition,
    required this.rect,
    required this.taskCount,
  });

  /// Shared zone definition.
  final TaskTerrainZoneDefinition definition;

  /// Rectangle on the current canvas.
  final Rect rect;

  /// Visible tasks classified into this zone.
  final int taskCount;
}

/// TaskTerrainCardPlacement stores one hover task card rectangle.
class TaskTerrainCardPlacement {
  /// Creates a hover terrain card placement.
  const TaskTerrainCardPlacement({
    required this.point,
    required this.rect,
    required this.anchor,
    required this.zone,
    required this.color,
    required this.cue,
  });

  /// Projected terrain point.
  final PriorityTerrainPoint point;

  /// Card rectangle after readability layout.
  final Rect rect;

  /// Exact visible anchor for the task.
  final Offset anchor;

  /// Semantic terrain zone for this task.
  final TaskTerrainZoneDefinition zone;

  /// Zone color for this task.
  final Color color;

  /// Short derived insight cue.
  final String cue;
}

/// TaskTerrainPinPlacement stores one low-detail task marker.
class TaskTerrainPinPlacement {
  /// Creates a low-detail terrain pin.
  const TaskTerrainPinPlacement({
    required this.point,
    required this.center,
    required this.zone,
    required this.color,
    required this.label,
  });

  /// Projected terrain point.
  final PriorityTerrainPoint point;

  /// Marker center.
  final Offset center;

  /// Semantic terrain zone for this task.
  final TaskTerrainZoneDefinition zone;

  /// Zone color for this task.
  final Color color;

  /// Compact marker label.
  final String label;
}

/// TaskTerrainClusterPlacement stores one grouped low-detail marker.
class TaskTerrainClusterPlacement {
  /// Creates a terrain cluster placement.
  const TaskTerrainClusterPlacement({
    required this.points,
    required this.center,
    required this.zone,
    required this.color,
  });

  /// Points represented by the cluster.
  final List<PriorityTerrainPoint> points;

  /// Average marker center of the grouped points.
  final Offset center;

  /// Semantic terrain zone for this cluster.
  final TaskTerrainZoneDefinition zone;

  /// Zone color for this cluster.
  final Color color;
}

/// _TerrainPinGroups returns grouped pin placement output.
class _TerrainPinGroups {
  const _TerrainPinGroups({required this.pins, required this.clusters});

  /// Individual pins.
  final List<TaskTerrainPinPlacement> pins;

  /// Cluster markers.
  final List<TaskTerrainClusterPlacement> clusters;
}

/// _MutablePinGroup accumulates nearby terrain points.
class _MutablePinGroup {
  _MutablePinGroup({
    required this.zoneKind,
    required this.center,
    required this.points,
  });

  /// Terrain zone kind for this group.
  final TaskTerrainZoneKind zoneKind;

  /// Current group center.
  Offset center;

  /// Grouped terrain points.
  final List<PriorityTerrainPoint> points;

  /// Adds a point and updates the group center.
  void add(PriorityTerrainPoint point, Offset pointCenter) {
    final nextCount = points.length + 1;
    center = Offset(
      (center.dx * points.length + pointCenter.dx) / nextCount,
      (center.dy * points.length + pointCenter.dy) / nextCount,
    );
    points.add(point);
  }
}
