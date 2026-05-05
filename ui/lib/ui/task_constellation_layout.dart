/// Computes anchor-first task constellation layouts from MCP projections.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../domain/models.dart';

/// TaskConstellationAnchorDimension identifies a mind-map starting dimension.
enum TaskConstellationAnchorDimension {
  /// Group tasks by supplied category or user-defined metadata label.
  category,

  /// Group tasks by backend time horizon.
  time,

  /// Group tasks by backend lifecycle status.
  status,

  /// Group tasks by responsible person.
  owner,

  /// Group tasks by project or domain.
  project,

  /// Group tasks by pressure inferred from urgency.
  pressure,

  /// Group tasks by derived risk from terrain projection data.
  risk,

  /// Group tasks by derived AI delegation fit from terrain projection data.
  aiDelegation,

  /// Group tasks by task size or graph importance.
  scale,
}

/// TaskConstellationLayoutStrategyKind identifies a graph placement algorithm.
enum TaskConstellationLayoutStrategyKind {
  /// Uses semantic anchor positions with local force constraints for children.
  anchoredForce,

  /// Uses the deterministic radial star layout retained for comparison.
  semanticRadial,
}

/// TaskConstellationLayout stores render-ready anchor and task geometry.
class TaskConstellationLayout {
  /// Creates a computed constellation mind-map layout.
  const TaskConstellationLayout({
    required this.size,
    required this.anchorDimension,
    required this.layoutStrategy,
    required this.anchors,
    required this.nodes,
    required this.visibleEdges,
    required this.totalEdgeCount,
    required this.expandedAnchorIds,
    required this.expandedTaskIds,
  });

  static const int _maxAnchorCount = 8;
  static const int _maxNodesPerAnchor = 18;
  static const int _expandedTaskNeighborLimit = 14;
  static const double _expansionCellWidth = 132;
  static const double _expansionCellHeight = 118;

  /// Canvas size used to resolve placements.
  final Size size;

  /// Current anchor grouping dimension.
  final TaskConstellationAnchorDimension anchorDimension;

  /// Current task placement strategy.
  final TaskConstellationLayoutStrategyKind layoutStrategy;

  /// Render-ready anchor placements.
  final List<TaskConstellationAnchorPlacement> anchors;

  /// Render-ready task node placements.
  final List<TaskConstellationNodePlacement> nodes;

  /// Edges visible among expanded task neighborhoods.
  final List<TaskConstellationEdge> visibleEdges;

  /// Total backend relation count.
  final int totalEdgeCount;

  /// Expanded anchor ids.
  final Set<String> expandedAnchorIds;

  /// Expanded task ids.
  final Set<String> expandedTaskIds;

  /// Builds an anchor-first constellation layout from a projection.
  static TaskConstellationLayout build(
    TaskConstellationProjection projection,
    Size size, {
    TaskConstellationAnchorDimension anchorDimension =
        TaskConstellationAnchorDimension.category,
    Set<String> expandedAnchorIds = const <String>{},
    Set<String> expandedTaskIds = const <String>{},
    Map<String, PriorityTerrainPoint> terrainPointsByTaskId =
        const <String, PriorityTerrainPoint>{},
    TaskConstellationLayoutStrategyKind layoutStrategy =
        TaskConstellationLayoutStrategyKind.anchoredForce,
  }) {
    final input = _ConstellationLayoutInput(
      projection: projection,
      size: Size(math.max(1, size.width), math.max(1, size.height)),
      anchorDimension: anchorDimension,
      layoutStrategy: layoutStrategy,
      expandedAnchorIds: expandedAnchorIds,
      expandedTaskIds: expandedTaskIds,
      terrainPointsByTaskId: terrainPointsByTaskId,
    );
    return _strategyFor(layoutStrategy).build(input);
  }

  /// Returns the virtual canvas size needed for a constellation state.
  static Size canvasSizeFor(
    TaskConstellationProjection projection,
    Size viewport, {
    TaskConstellationAnchorDimension anchorDimension =
        TaskConstellationAnchorDimension.category,
    Set<String> expandedAnchorIds = const <String>{},
    Set<String> expandedTaskIds = const <String>{},
    Map<String, PriorityTerrainPoint> terrainPointsByTaskId =
        const <String, PriorityTerrainPoint>{},
    TaskConstellationLayoutStrategyKind layoutStrategy =
        TaskConstellationLayoutStrategyKind.anchoredForce,
  }) {
    final boundedViewport = Size(
      math.max(1, viewport.width),
      math.max(1, viewport.height),
    );
    final input = _ConstellationLayoutInput(
      projection: projection,
      size: boundedViewport,
      anchorDimension: anchorDimension,
      layoutStrategy: layoutStrategy,
      expandedAnchorIds: expandedAnchorIds,
      expandedTaskIds: expandedTaskIds,
      terrainPointsByTaskId: terrainPointsByTaskId,
    );
    return _strategyFor(layoutStrategy).canvasSizeFor(input);
  }

  /// Returns a display label for a layout strategy.
  static String strategyLabel(TaskConstellationLayoutStrategyKind strategy) {
    return switch (strategy) {
      TaskConstellationLayoutStrategyKind.anchoredForce => 'Anchored',
      TaskConstellationLayoutStrategyKind.semanticRadial => 'Radial',
    };
  }

  /// Returns the active layout strategy implementation.
  static _ConstellationLayoutStrategy _strategyFor(
    TaskConstellationLayoutStrategyKind strategy,
  ) {
    return switch (strategy) {
      TaskConstellationLayoutStrategyKind.anchoredForce =>
        const _AnchoredForceConstellationLayoutStrategy(),
      TaskConstellationLayoutStrategyKind.semanticRadial =>
        const _SemanticRadialConstellationLayoutStrategy(),
    };
  }

  /// Returns shared graph and anchor preparation for all layout strategies.
  static _ConstellationLayoutContext _layoutContext(
    _ConstellationLayoutInput input,
  ) {
    final nodesById = <String, TaskConstellationNode>{
      for (final node in input.projection.nodes) node.taskId: node,
    };
    final validEdges = _validEdges(
      input.projection.edges,
      nodesById.keys.toSet(),
    );
    final degrees = _degrees(validEdges, nodesById.keys.toSet());
    final anchorModels = _anchorModels(
      input.projection.nodes,
      degrees,
      input.anchorDimension,
      input.terrainPointsByTaskId,
    );
    final anchorIds = anchorModels.map((anchor) => anchor.id).toSet();
    final activeAnchorIds = input.expandedAnchorIds.intersection(anchorIds);
    final activeTaskIds = input.expandedTaskIds.intersection(
      nodesById.keys.toSet(),
    );
    final anchors = _anchorPlacements(
      anchorModels,
      input.size,
      activeAnchorIds: activeAnchorIds,
      hasTaskFocus: activeTaskIds.isNotEmpty,
    );
    final placementSeeds = _placementSeeds(
      anchors,
      nodesById,
      validEdges,
      degrees,
      activeAnchorIds,
      activeTaskIds,
      input.size,
    );
    return _ConstellationLayoutContext(
      nodesById: nodesById,
      validEdges: validEdges,
      degrees: degrees,
      activeAnchorIds: activeAnchorIds,
      activeTaskIds: activeTaskIds,
      anchors: anchors,
      placementSeeds: placementSeeds,
    );
  }

  /// Returns a finished layout from shared context and strategy placements.
  static TaskConstellationLayout _finishLayout(
    _ConstellationLayoutInput input,
    _ConstellationLayoutContext context,
    List<TaskConstellationNodePlacement> placements,
  ) {
    final visibleTaskIds = placements
        .map((placement) => placement.node.taskId)
        .toSet();
    final visibleEdges = _visibleEdges(
      context.validEdges,
      visibleTaskIds,
      context.activeTaskIds,
    );
    return TaskConstellationLayout(
      size: input.size,
      anchorDimension: input.anchorDimension,
      layoutStrategy: input.layoutStrategy,
      anchors: context.anchors,
      nodes: placements,
      visibleEdges: visibleEdges,
      totalEdgeCount: input.projection.edges.length,
      expandedAnchorIds: context.activeAnchorIds,
      expandedTaskIds: context.activeTaskIds,
    );
  }

  /// Returns the virtual canvas size shared by strategy implementations.
  static Size _sharedCanvasSizeFor(_ConstellationLayoutInput input) {
    if (input.expandedAnchorIds.isEmpty && input.expandedTaskIds.isEmpty) {
      return input.size;
    }
    final nodeIds = input.projection.nodes.map((node) => node.taskId).toSet();
    final validEdges = _validEdges(input.projection.edges, nodeIds);
    final degrees = _degrees(validEdges, nodeIds);
    final anchors = _anchorPlacements(
      _anchorModels(
        input.projection.nodes,
        degrees,
        input.anchorDimension,
        input.terrainPointsByTaskId,
      ),
      input.size,
    );
    var visibleNodeBudget = 0;
    for (final anchor in anchors) {
      if (input.expandedAnchorIds.contains(anchor.id)) {
        visibleNodeBudget += math.min(
          _maxNodesPerAnchor,
          anchor.taskIds.length,
        );
      }
    }
    visibleNodeBudget +=
        input.expandedTaskIds.length * (_expandedTaskNeighborLimit + 1);
    final expansion = math.sqrt(math.max(1, visibleNodeBudget));
    return Size(
      math.max(
        input.size.width,
        input.size.width + expansion * _expansionCellWidth,
      ),
      math.max(
        input.size.height,
        input.size.height + expansion * _expansionCellHeight,
      ),
    );
  }

  /// Returns lookup placements by task id.
  Map<String, TaskConstellationNodePlacement> get nodeByTaskId {
    return <String, TaskConstellationNodePlacement>{
      for (final placement in nodes) placement.node.taskId: placement,
    };
  }

  /// Returns lookup placements by anchor id.
  Map<String, TaskConstellationAnchorPlacement> get anchorById {
    return <String, TaskConstellationAnchorPlacement>{
      for (final placement in anchors) placement.id: placement,
    };
  }

  /// Returns task ids that define the current focus neighborhood.
  Set<String> get focusTaskIds {
    if (expandedTaskIds.isNotEmpty) {
      final taskIds = Set<String>.from(expandedTaskIds);
      for (final edge in visibleEdges) {
        if (expandedTaskIds.contains(edge.fromTaskId) ||
            expandedTaskIds.contains(edge.toTaskId)) {
          taskIds
            ..add(edge.fromTaskId)
            ..add(edge.toTaskId);
        }
      }
      return taskIds;
    }
    if (expandedAnchorIds.isEmpty) {
      return const <String>{};
    }
    return <String>{
      for (final node in nodes)
        if (node.anchorId != null && expandedAnchorIds.contains(node.anchorId))
          node.node.taskId,
    };
  }

  /// Returns anchor ids that define the current focus neighborhood.
  Set<String> get focusAnchorIds {
    if (expandedTaskIds.isNotEmpty) {
      return const <String>{};
    }
    if (expandedAnchorIds.isNotEmpty) {
      return expandedAnchorIds;
    }
    return anchors.map((anchor) => anchor.id).toSet();
  }

  /// Returns the canvas rectangle the camera should keep visible.
  Rect focusBounds({double padding = 48}) {
    final focusNodeIds = focusTaskIds;
    final focusAnchors = focusAnchorIds;
    final rects = <Rect>[
      for (final anchor in anchors)
        if (focusAnchors.contains(anchor.id)) anchor.bounds,
      for (final node in nodes)
        if (focusNodeIds.contains(node.node.taskId)) node.bounds,
    ];
    if (rects.isEmpty) {
      rects.addAll(<Rect>[
        for (final anchor in anchors) anchor.bounds,
        for (final node in nodes) node.bounds,
      ]);
    }
    if (rects.isEmpty) {
      return Offset.zero & size;
    }
    final union = rects
        .skip(1)
        .fold<Rect>(
          rects.first,
          (bounds, rect) => bounds.expandToInclude(rect),
        );
    return _clampRect(union.inflate(padding), size);
  }

  /// Returns the nearest visible edge to a canvas point.
  TaskConstellationEdge? edgeAt(Offset point, {double tolerance = 12}) {
    final placements = nodeByTaskId;
    TaskConstellationEdge? nearestEdge;
    var nearestDistance = tolerance;
    for (final edge in visibleEdges) {
      final from = placements[edge.fromTaskId];
      final to = placements[edge.toTaskId];
      if (from == null || to == null) {
        continue;
      }
      final distance = _distanceToSegment(point, from.center, to.center);
      if (distance > nearestDistance) {
        continue;
      }
      nearestDistance = distance;
      nearestEdge = edge;
    }
    final anchors = anchorById;
    for (final node in nodes) {
      final anchorId = node.anchorId;
      if (anchorId == null || !expandedAnchorIds.contains(anchorId)) {
        continue;
      }
      final anchor = anchors[anchorId];
      if (anchor == null) {
        continue;
      }
      final distance = _distanceToSegment(point, anchor.center, node.center);
      if (distance > nearestDistance) {
        continue;
      }
      nearestDistance = distance;
      nearestEdge = anchorMembershipEdge(anchor, node);
    }
    return nearestEdge;
  }

  /// Reports whether a canvas point is inside an interactive node or anchor.
  bool containsNodeOrAnchorAt(Offset point) {
    for (final anchor in anchors) {
      if (anchor.bounds.contains(point)) {
        return true;
      }
    }
    for (final node in nodes) {
      if (node.bounds.contains(point)) {
        return true;
      }
    }
    return false;
  }

  /// Creates a selectable edge for an anchor-to-task membership spoke.
  TaskConstellationEdge anchorMembershipEdge(
    TaskConstellationAnchorPlacement anchor,
    TaskConstellationNodePlacement node,
  ) {
    final dimension = dimensionLabel(anchorDimension).toLowerCase();
    return TaskConstellationEdge(
      fromTaskId: 'anchor:${anchor.label}',
      toTaskId: node.node.taskId,
      relationType: 'anchor_membership',
      source: 'constellation_anchor',
      sourceKind: 'derived',
      confidence: 1,
      explanation:
          '${node.node.title} appears under ${anchor.label} because it belongs '
          'to that $dimension anchor.',
    );
  }

  /// Returns a display label for an anchor dimension.
  static String dimensionLabel(TaskConstellationAnchorDimension dimension) {
    return switch (dimension) {
      TaskConstellationAnchorDimension.category => 'Metadata',
      TaskConstellationAnchorDimension.time => 'Time',
      TaskConstellationAnchorDimension.status => 'Status',
      TaskConstellationAnchorDimension.owner => 'Owner',
      TaskConstellationAnchorDimension.project => 'Project',
      TaskConstellationAnchorDimension.pressure => 'Pressure',
      TaskConstellationAnchorDimension.risk => 'Risk',
      TaskConstellationAnchorDimension.aiDelegation => 'AI Fit',
      TaskConstellationAnchorDimension.scale => 'Scale',
    };
  }

  /// Returns valid graph edges whose endpoints are visible nodes.
  static List<TaskConstellationEdge> _validEdges(
    List<TaskConstellationEdge> edges,
    Set<String> nodeIds,
  ) {
    return <TaskConstellationEdge>[
      for (final edge in edges)
        if (nodeIds.contains(edge.fromTaskId) &&
            nodeIds.contains(edge.toTaskId))
          edge,
    ]..sort(_compareEdges);
  }

  /// Counts valid graph degree for every node.
  static Map<String, int> _degrees(
    List<TaskConstellationEdge> edges,
    Set<String> nodeIds,
  ) {
    final degrees = <String, int>{for (final id in nodeIds) id: 0};
    for (final edge in edges) {
      degrees[edge.fromTaskId] = (degrees[edge.fromTaskId] ?? 0) + 1;
      degrees[edge.toTaskId] = (degrees[edge.toTaskId] ?? 0) + 1;
    }
    return degrees;
  }

  /// Builds anchor models from nodes and a selected dimension.
  static List<_ConstellationAnchorModel> _anchorModels(
    List<TaskConstellationNode> nodes,
    Map<String, int> degrees,
    TaskConstellationAnchorDimension dimension,
    Map<String, PriorityTerrainPoint> terrainPointsByTaskId,
  ) {
    final buckets = <String, List<TaskConstellationNode>>{};
    for (final node in nodes) {
      final bucket = _bucketFor(
        node,
        dimension,
        terrainPointsByTaskId[node.taskId],
      );
      buckets.putIfAbsent(bucket.id, () => <TaskConstellationNode>[]).add(node);
    }
    final models = <_ConstellationAnchorModel>[
      for (final entry in buckets.entries)
        _ConstellationAnchorModel(
          id: entry.key,
          label: _bucketFor(
            entry.value.first,
            dimension,
            terrainPointsByTaskId[entry.value.first.taskId],
          ).label,
          subtitle: _bucketFor(
            entry.value.first,
            dimension,
            terrainPointsByTaskId[entry.value.first.taskId],
          ).subtitle,
          nodes: entry.value,
          weight: entry.value.fold<double>(
            0,
            (total, node) => total + 1 + math.sqrt(degrees[node.taskId] ?? 0),
          ),
        ),
    ]..sort((left, right) => right.weight.compareTo(left.weight));
    if (models.length <= _maxAnchorCount) {
      return models;
    }
    final visible = models.take(_maxAnchorCount - 1).toList();
    final overflow = models.skip(_maxAnchorCount - 1).toList();
    visible.add(
      _ConstellationAnchorModel(
        id: 'other',
        label: 'Other',
        subtitle: '${overflow.length} groups',
        nodes: <TaskConstellationNode>[
          for (final model in overflow) ...model.nodes,
        ],
        weight: overflow.fold<double>(
          0,
          (total, model) => total + model.weight,
        ),
      ),
    );
    return visible;
  }

  /// Returns one node's anchor bucket for a dimension.
  static _ConstellationBucket _bucketFor(
    TaskConstellationNode node,
    TaskConstellationAnchorDimension dimension,
    PriorityTerrainPoint? terrainPoint,
  ) {
    switch (dimension) {
      case TaskConstellationAnchorDimension.category:
        return _dynamicBucket(node.category, fallback: 'Uncategorized');
      case TaskConstellationAnchorDimension.time:
        return _dynamicBucket(node.timeHorizon, fallback: 'No horizon');
      case TaskConstellationAnchorDimension.status:
        return _dynamicBucket(node.status, fallback: 'Open');
      case TaskConstellationAnchorDimension.owner:
        return _dynamicBucket(node.owner, fallback: 'Unassigned');
      case TaskConstellationAnchorDimension.project:
        return _dynamicBucket(node.project, fallback: 'No project');
      case TaskConstellationAnchorDimension.pressure:
        if (node.urgency >= 0.72) {
          return const _ConstellationBucket(
            id: 'high-pressure',
            label: 'High pressure',
            subtitle: 'Needs attention',
          );
        }
        if (node.urgency >= 0.42) {
          return const _ConstellationBucket(
            id: 'medium-pressure',
            label: 'Medium pressure',
            subtitle: 'Watch timing',
          );
        }
        return const _ConstellationBucket(
          id: 'low-pressure',
          label: 'Low pressure',
          subtitle: 'Room to sequence',
        );
      case TaskConstellationAnchorDimension.risk:
        final risk = terrainPoint?.riskScore ?? node.urgency;
        if (risk >= 0.64) {
          return const _ConstellationBucket(
            id: 'high-risk',
            label: 'High risk',
            subtitle: 'Likely to slip',
          );
        }
        if (risk >= 0.36) {
          return const _ConstellationBucket(
            id: 'medium-risk',
            label: 'Medium risk',
            subtitle: 'Needs tracking',
          );
        }
        return const _ConstellationBucket(
          id: 'low-risk',
          label: 'Low risk',
          subtitle: 'Stable work',
        );
      case TaskConstellationAnchorDimension.aiDelegation:
        final agentFit = terrainPoint?.agentFitScore ?? 0;
        if (agentFit >= 0.66) {
          return const _ConstellationBucket(
            id: 'strong-ai-fit',
            label: 'Strong AI fit',
            subtitle: 'Good delegation',
          );
        }
        if (agentFit >= 0.34) {
          return const _ConstellationBucket(
            id: 'partial-ai-fit',
            label: 'Partial AI fit',
            subtitle: 'Assistable',
          );
        }
        return const _ConstellationBucket(
          id: 'human-led',
          label: 'Human led',
          subtitle: 'Low AI fit',
        );
      case TaskConstellationAnchorDimension.scale:
        if (node.size >= 0.68) {
          return const _ConstellationBucket(
            id: 'large',
            label: 'Large work',
            subtitle: 'Big surface area',
          );
        }
        if (node.size >= 0.34) {
          return const _ConstellationBucket(
            id: 'medium',
            label: 'Medium work',
            subtitle: 'Manageable chunk',
          );
        }
        return const _ConstellationBucket(
          id: 'small',
          label: 'Small work',
          subtitle: 'Quick inspect',
        );
    }
  }

  /// Returns a normalized dynamic metadata bucket.
  static _ConstellationBucket _dynamicBucket(
    String value, {
    required String fallback,
  }) {
    final label = value.trim().isEmpty ? fallback : value.trim();
    return _ConstellationBucket(
      id: _slug(label),
      label: _titleCase(label),
      subtitle: 'Backlog metadata',
    );
  }

  /// Places anchor nodes around the canvas as starting points.
  static List<TaskConstellationAnchorPlacement> _anchorPlacements(
    List<_ConstellationAnchorModel> models,
    Size size, {
    Set<String> activeAnchorIds = const <String>{},
    bool hasTaskFocus = false,
  }) {
    final center = Offset(size.width / 2, size.height / 2);
    final radiusX = math.max(96.0, size.width * 0.30);
    final radiusY = math.max(80.0, size.height * 0.28);
    final hasAnchorFocus = activeAnchorIds.isNotEmpty;
    final hasFocus = hasAnchorFocus || hasTaskFocus;
    return <TaskConstellationAnchorPlacement>[
      for (var index = 0; index < models.length; index++)
        _anchorPlacement(
          models[index],
          index,
          models.length,
          center,
          radiusX,
          radiusY,
          focused:
              !hasFocus ||
              (hasAnchorFocus && activeAnchorIds.contains(models[index].id)),
          hasFocus: hasFocus,
        ),
    ];
  }

  /// Places one anchor around the central orbit.
  static TaskConstellationAnchorPlacement _anchorPlacement(
    _ConstellationAnchorModel model,
    int index,
    int count,
    Offset center,
    double radiusX,
    double radiusY, {
    required bool focused,
    required bool hasFocus,
  }) {
    final angle = count == 1
        ? -math.pi / 2
        : -math.pi / 2 + index * math.pi * 2 / count;
    final radiusMultiplier = !hasFocus
        ? 1.0
        : focused
        ? 0.86
        : 1.72;
    final width = (124 + math.sqrt(model.nodes.length) * 16)
        .clamp(132, 192)
        .toDouble();
    const height = 78.0;
    return TaskConstellationAnchorPlacement(
      id: model.id,
      label: model.label,
      subtitle: model.subtitle,
      count: model.nodes.length,
      taskIds: model.nodes.map((node) => node.taskId).toSet(),
      size: Size(width, height),
      center: Offset(
        center.dx + math.cos(angle) * radiusX * radiusMultiplier,
        center.dy + math.sin(angle) * radiusY * radiusMultiplier,
      ),
      diameter: math.max(width, height),
    );
  }

  /// Builds origin seeds for expanded anchors and task neighborhoods.
  static List<_ConstellationPlacementSeed> _placementSeeds(
    List<TaskConstellationAnchorPlacement> anchors,
    Map<String, TaskConstellationNode> nodesById,
    List<TaskConstellationEdge> edges,
    Map<String, int> degrees,
    Set<String> expandedAnchorIds,
    Set<String> expandedTaskIds,
    Size size,
  ) {
    final seeds = <String, _ConstellationPlacementSeed>{};
    final criticalPathOrigins = _criticalPathOrigins(edges, size);
    for (final anchor in anchors) {
      if (!expandedAnchorIds.contains(anchor.id)) {
        continue;
      }
      final ranked = anchor.taskIds.toList()
        ..sort((left, right) {
          return (degrees[right] ?? 0).compareTo(degrees[left] ?? 0);
        });
      final radii = _starRadii(ranked.length);
      for (
        var index = 0;
        index < math.min(_maxNodesPerAnchor, ranked.length);
        index++
      ) {
        final taskId = ranked[index];
        seeds[taskId] = _ConstellationPlacementSeed(
          taskId: taskId,
          anchorId: anchor.id,
          origin:
              criticalPathOrigins[taskId] ??
              _starPoint(
                anchor.center,
                index,
                ranked.length,
                radii.$1,
                radii.$2,
              ),
        );
      }
    }
    for (final taskId in expandedTaskIds) {
      final source =
          seeds[taskId]?.origin ??
          criticalPathOrigins[taskId] ??
          _nodeFallback(nodesById[taskId]!, size);
      seeds[taskId] = _ConstellationPlacementSeed(
        taskId: taskId,
        anchorId: seeds[taskId]?.anchorId,
        origin: source,
      );
      final neighbors = _neighborIds(
        edges,
        taskId,
      ).take(_expandedTaskNeighborLimit).toList();
      for (var index = 0; index < neighbors.length; index++) {
        final neighborId = neighbors[index];
        final radii = _starRadii(neighbors.length);
        seeds.putIfAbsent(
          neighborId,
          () => _ConstellationPlacementSeed(
            taskId: neighborId,
            anchorId: null,
            origin: _starPoint(
              source,
              index,
              neighbors.length,
              radii.$1,
              radii.$2,
            ),
          ),
        );
      }
    }
    return seeds.values
        .where((seed) => nodesById.containsKey(seed.taskId))
        .toList();
  }

  /// Returns deterministic left-to-right origins for highlighted path edges.
  static Map<String, Offset> _criticalPathOrigins(
    List<TaskConstellationEdge> edges,
    Size size,
  ) {
    final path = _criticalPathOrder(edges);
    if (path.length < 2) {
      return const <String, Offset>{};
    }
    final left = math.max(112.0, size.width * 0.14);
    final right = math.min(size.width - 112.0, size.width * 0.86);
    final centerY = size.height * 0.52;
    final step = path.length == 1 ? 0.0 : (right - left) / (path.length - 1);
    return <String, Offset>{
      for (var index = 0; index < path.length; index++)
        path[index]: Offset(left + step * index, centerY),
    };
  }

  /// Returns the primary critical path from highlighted dependency edges.
  static List<String> _criticalPathOrder(List<TaskConstellationEdge> edges) {
    final criticalEdges = edges
        .where((edge) => edge.source == 'critical_path')
        .toList();
    if (criticalEdges.isEmpty) {
      return const <String>[];
    }
    final outgoing = <String, String>{};
    final incoming = <String, String>{};
    for (final edge in criticalEdges) {
      outgoing[edge.fromTaskId] = edge.toTaskId;
      incoming[edge.toTaskId] = edge.fromTaskId;
    }
    final starts = <String>[
      for (final edge in criticalEdges)
        if (!incoming.containsKey(edge.fromTaskId)) edge.fromTaskId,
    ]..sort();
    final start = starts.isNotEmpty
        ? starts.first
        : criticalEdges.first.fromTaskId;
    final path = <String>[];
    final seen = <String>{};
    var current = start;
    while (seen.add(current)) {
      path.add(current);
      final next = outgoing[current];
      if (next == null) {
        break;
      }
      current = next;
    }
    return path;
  }

  /// Returns neighbor task ids ranked by relation importance.
  static Iterable<String> _neighborIds(
    List<TaskConstellationEdge> edges,
    String taskId,
  ) {
    return edges
        .where((edge) => edge.fromTaskId == taskId || edge.toTaskId == taskId)
        .map((edge) {
          return edge.fromTaskId == taskId ? edge.toTaskId : edge.fromTaskId;
        });
  }

  /// Returns expanding inner and outer radii for a star group.
  static (double, double) _starRadii(int count) {
    final clamped = math.max(1, count);
    final inner = 132.0 + math.min(108.0, clamped * 5.5);
    final outer = inner + 86.0 + math.min(104.0, clamped * 6.5);
    return (inner, outer);
  }

  /// Returns a radial star point around a center.
  static Offset _starPoint(
    Offset center,
    int index,
    int count,
    double minRadius,
    double maxRadius,
  ) {
    final angle = -math.pi / 2 + index * math.pi * 2 / math.max(1, count);
    final radius = minRadius + (index % 3) * ((maxRadius - minRadius) / 2);
    return Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
  }

  /// Returns a fallback canvas point from backend normalized coordinates.
  static Offset _nodeFallback(TaskConstellationNode node, Size size) {
    return Offset(
      node.x.clamp(0.08, 0.92).toDouble() * size.width,
      node.y.clamp(0.08, 0.92).toDouble() * size.height,
    );
  }

  /// Returns collision-relaxed task placements from origin seeds.
  static List<TaskConstellationNodePlacement> _nodePlacements(
    List<_ConstellationPlacementSeed> seeds,
    Map<String, TaskConstellationNode> nodesById,
    Map<String, int> degrees,
    Size size,
    Set<String> expandedTaskIds,
  ) {
    final mutable = <_MutableConstellationNode>[
      for (final seed in seeds) _mutableNode(seed, nodesById, degrees, size),
    ];
    _relax(mutable, size);
    return <TaskConstellationNodePlacement>[
      for (final item in mutable)
        TaskConstellationNodePlacement(
          node: item.node,
          anchorId: item.anchorId,
          center: item.center,
          size: item.size,
          diameter: item.diameter,
          expanded: expandedTaskIds.contains(item.node.taskId),
        ),
    ];
  }

  /// Returns constrained force-directed placements from origin seeds.
  static List<TaskConstellationNodePlacement> _anchoredForceNodePlacements(
    List<_ConstellationPlacementSeed> seeds,
    Map<String, TaskConstellationNode> nodesById,
    Map<String, int> degrees,
    List<TaskConstellationEdge> edges,
    List<TaskConstellationAnchorPlacement> anchors,
    Size size,
    Set<String> expandedTaskIds,
    _ConstellationLayoutPolicy policy,
  ) {
    final mutable = <_MutableConstellationNode>[
      for (final seed in seeds) _mutableNode(seed, nodesById, degrees, size),
    ];
    final mutableById = <String, _MutableConstellationNode>{
      for (final node in mutable) node.node.taskId: node,
    };
    final relevantEdges = <TaskConstellationEdge>[
      for (final edge in edges)
        if (mutableById.containsKey(edge.fromTaskId) &&
            mutableById.containsKey(edge.toTaskId) &&
            (expandedTaskIds.isEmpty ||
                expandedTaskIds.contains(edge.fromTaskId) ||
                expandedTaskIds.contains(edge.toTaskId)))
          edge,
    ].take(policy.maxForceEdges).toList();
    for (var iteration = 0; iteration < policy.iterations; iteration++) {
      _applyEdgeAttraction(mutableById, relevantEdges, size, policy, iteration);
      _repelFromAnchors(mutable, anchors, size, policy);
      _resolveCardCollisions(mutable, size, policy.nodePadding);
      _pinToOrigins(mutable, size, policy);
    }
    return <TaskConstellationNodePlacement>[
      for (final item in mutable)
        TaskConstellationNodePlacement(
          node: item.node,
          anchorId: item.anchorId,
          center: item.center,
          size: item.size,
          diameter: item.diameter,
          expanded: expandedTaskIds.contains(item.node.taskId),
        ),
    ];
  }

  /// Creates mutable layout state for one task card.
  static _MutableConstellationNode _mutableNode(
    _ConstellationPlacementSeed seed,
    Map<String, TaskConstellationNode> nodesById,
    Map<String, int> degrees,
    Size size,
  ) {
    final node = nodesById[seed.taskId]!;
    final cardSize = _nodeSize(node, degrees[seed.taskId] ?? 0);
    final center = _clampCenter(seed.origin, cardSize, size);
    return _MutableConstellationNode(
      node: node,
      anchorId: seed.anchorId,
      center: center,
      origin: center,
      size: cardSize,
      diameter: cardSize.longestSide,
    );
  }

  /// Pulls related nodes together without allowing hard overlaps.
  static void _applyEdgeAttraction(
    Map<String, _MutableConstellationNode> nodesById,
    List<TaskConstellationEdge> edges,
    Size size,
    _ConstellationLayoutPolicy policy,
    int iteration,
  ) {
    if (edges.isEmpty) {
      return;
    }
    final cooling =
        1 -
        (iteration / math.max(1, policy.iterations - 1)) * policy.coolingDrop;
    for (final edge in edges) {
      final from = nodesById[edge.fromTaskId];
      final to = nodesById[edge.toTaskId];
      if (from == null || to == null) {
        continue;
      }
      final delta = to.center - from.center;
      final rawDistance = delta.distance;
      final distance = math.max(0.01, rawDistance);
      final direction = rawDistance < 0.01
          ? _fallbackDirection(edge.fromTaskId.hashCode, edge.toTaskId.hashCode)
          : delta / distance;
      final ideal = from.radius + to.radius + policy.edgeGap;
      final step = ((distance - ideal) * policy.edgeStrength * cooling)
          .clamp(-policy.maxStep, policy.maxStep)
          .toDouble();
      final adjustment = direction * (step / 2);
      from.center = _clampCenter(from.center + adjustment, from.size, size);
      to.center = _clampCenter(to.center - adjustment, to.size, size);
    }
  }

  /// Pushes task cards away from fixed anchor cards.
  static void _repelFromAnchors(
    List<_MutableConstellationNode> nodes,
    List<TaskConstellationAnchorPlacement> anchors,
    Size size,
    _ConstellationLayoutPolicy policy,
  ) {
    for (var nodeIndex = 0; nodeIndex < nodes.length; nodeIndex++) {
      final node = nodes[nodeIndex];
      for (var anchorIndex = 0; anchorIndex < anchors.length; anchorIndex++) {
        final anchor = anchors[anchorIndex];
        final nodeBounds = node.bounds.inflate(policy.nodePadding / 2);
        final anchorBounds = anchor.bounds.inflate(policy.anchorPadding);
        if (!nodeBounds.overlaps(anchorBounds)) {
          continue;
        }
        final delta = node.center - anchor.center;
        final distance = delta.distance;
        final direction = distance < 0.01
            ? _fallbackDirection(nodeIndex, anchorIndex)
            : delta / distance;
        final overlapX = math.min(
          nodeBounds.right - anchorBounds.left,
          anchorBounds.right - nodeBounds.left,
        );
        final overlapY = math.min(
          nodeBounds.bottom - anchorBounds.top,
          anchorBounds.bottom - nodeBounds.top,
        );
        final push =
            math.min(math.max(overlapX, overlapY), policy.maxAnchorStep) *
            policy.anchorRepulsionStrength;
        node.center = _clampCenter(
          node.center + direction * push,
          node.size,
          size,
        );
      }
    }
  }

  /// Resolves card-shaped collisions with axis-aligned separation.
  static void _resolveCardCollisions(
    List<_MutableConstellationNode> nodes,
    Size size,
    double padding,
  ) {
    for (var leftIndex = 0; leftIndex < nodes.length; leftIndex++) {
      for (
        var rightIndex = leftIndex + 1;
        rightIndex < nodes.length;
        rightIndex++
      ) {
        final left = nodes[leftIndex];
        final right = nodes[rightIndex];
        final leftBounds = left.bounds.inflate(padding / 2);
        final rightBounds = right.bounds.inflate(padding / 2);
        if (!leftBounds.overlaps(rightBounds)) {
          continue;
        }
        final overlapX = math.min(
          leftBounds.right - rightBounds.left,
          rightBounds.right - leftBounds.left,
        );
        final overlapY = math.min(
          leftBounds.bottom - rightBounds.top,
          rightBounds.bottom - leftBounds.top,
        );
        if (overlapX <= 0 || overlapY <= 0) {
          continue;
        }
        if (overlapX < overlapY) {
          final sign = left.center.dx <= right.center.dx ? -1.0 : 1.0;
          final shift = Offset(sign * (overlapX / 2 + 0.8), 0);
          left.center = _clampCenter(left.center + shift, left.size, size);
          right.center = _clampCenter(right.center - shift, right.size, size);
        } else {
          final sign = left.center.dy <= right.center.dy ? -1.0 : 1.0;
          final shift = Offset(0, sign * (overlapY / 2 + 0.8));
          left.center = _clampCenter(left.center + shift, left.size, size);
          right.center = _clampCenter(right.center - shift, right.size, size);
        }
      }
    }
  }

  /// Softly keeps cards near their deterministic semantic origins.
  static void _pinToOrigins(
    List<_MutableConstellationNode> nodes,
    Size size,
    _ConstellationLayoutPolicy policy,
  ) {
    for (final node in nodes) {
      node.center = _clampCenter(
        Offset.lerp(node.center, node.origin, policy.originStrength)!,
        node.size,
        size,
      );
    }
  }

  /// Returns a compact task card size from priority and graph degree.
  static Size _nodeSize(TaskConstellationNode node, int degree) {
    final importance = node.size.clamp(0, 1).toDouble();
    final width = 138 + importance * 28 + math.sqrt(math.max(0, degree)) * 2.2;
    final height = 76 + importance * 8;
    return Size(
      width.clamp(132, 184).toDouble(),
      height.clamp(74, 88).toDouble(),
    );
  }

  /// Mutates node centers to reduce overlap while preserving star structure.
  static void _relax(List<_MutableConstellationNode> nodes, Size size) {
    for (var iteration = 0; iteration < 64; iteration++) {
      for (var leftIndex = 0; leftIndex < nodes.length; leftIndex++) {
        for (
          var rightIndex = leftIndex + 1;
          rightIndex < nodes.length;
          rightIndex++
        ) {
          final left = nodes[leftIndex];
          final right = nodes[rightIndex];
          final delta = right.center - left.center;
          final rawDistance = delta.distance;
          final distance = math.max(0.01, rawDistance);
          final minimum = left.radius + right.radius + 18;
          if (distance >= minimum) {
            continue;
          }
          final push = (minimum - distance) / 2;
          final direction = rawDistance < 0.01
              ? _fallbackDirection(leftIndex, rightIndex)
              : delta / distance;
          left.center -= direction * push;
          right.center += direction * push;
        }
      }
      for (final node in nodes) {
        node.center = Offset.lerp(node.center, node.origin, 0.018)!;
        node.center = _clampCenter(node.center, node.size, size);
      }
    }
  }

  /// Returns a stable push direction for perfectly overlapping nodes.
  static Offset _fallbackDirection(int leftIndex, int rightIndex) {
    final angle = (leftIndex * 37 + rightIndex * 53) * math.pi / 89;
    return Offset(math.cos(angle), math.sin(angle));
  }

  /// Keeps one task card center inside the drawable canvas.
  static Offset _clampCenter(Offset center, Size nodeSize, Size size) {
    final halfWidth = nodeSize.width / 2 + 8;
    final halfHeight = nodeSize.height / 2 + 8;
    return Offset(
      center.dx
          .clamp(halfWidth, math.max(halfWidth, size.width - halfWidth))
          .toDouble(),
      center.dy
          .clamp(halfHeight, math.max(halfHeight, size.height - halfHeight))
          .toDouble(),
    );
  }

  /// Keeps a camera rectangle inside the virtual canvas when possible.
  static Rect _clampRect(Rect rect, Size size) {
    final canvas = Offset.zero & size;
    if (rect.width >= canvas.width || rect.height >= canvas.height) {
      return rect.intersect(canvas);
    }
    final dx = rect.left < canvas.left
        ? canvas.left - rect.left
        : rect.right > canvas.right
        ? canvas.right - rect.right
        : 0.0;
    final dy = rect.top < canvas.top
        ? canvas.top - rect.top
        : rect.bottom > canvas.bottom
        ? canvas.bottom - rect.bottom
        : 0.0;
    return rect.shift(Offset(dx, dy)).intersect(canvas);
  }

  /// Returns the shortest distance from a point to a line segment.
  static double _distanceToSegment(Offset point, Offset start, Offset end) {
    final segment = end - start;
    final lengthSquared = segment.distanceSquared;
    if (lengthSquared <= 0.0001) {
      return (point - start).distance;
    }
    final t =
        ((point.dx - start.dx) * segment.dx +
            (point.dy - start.dy) * segment.dy) /
        lengthSquared;
    final clampedT = t.clamp(0, 1).toDouble();
    final projection = start + segment * clampedT;
    return (point - projection).distance;
  }

  /// Returns visible graph edges among currently expanded task nodes.
  static List<TaskConstellationEdge> _visibleEdges(
    List<TaskConstellationEdge> edges,
    Set<String> visibleTaskIds,
    Set<String> expandedTaskIds,
  ) {
    return <TaskConstellationEdge>[
      for (final edge in edges)
        if (visibleTaskIds.contains(edge.fromTaskId) &&
            visibleTaskIds.contains(edge.toTaskId) &&
            (expandedTaskIds.isEmpty ||
                expandedTaskIds.contains(edge.fromTaskId) ||
                expandedTaskIds.contains(edge.toTaskId)))
          edge,
    ].take(96).toList();
  }

  /// Sorts edges by semantic value and confidence.
  static int _compareEdges(
    TaskConstellationEdge left,
    TaskConstellationEdge right,
  ) {
    final leftScore = _edgeScore(left);
    final rightScore = _edgeScore(right);
    return rightScore.compareTo(leftScore);
  }

  /// Scores one relation for overview visibility.
  static double _edgeScore(TaskConstellationEdge edge) {
    final relation = edge.relationType.toLowerCase();
    final relationBoost =
        relation.contains('block') || relation.contains('depend')
        ? 0.34
        : relation.contains('duplicate') || relation.contains('parent')
        ? 0.18
        : relation.contains('related')
        ? 0.02
        : 0.1;
    final sourceBoost = edge.source == 'explicit' ? 0.22 : 0;
    return edge.confidence.clamp(0, 1).toDouble() + relationBoost + sourceBoost;
  }

  /// Returns a lower-case stable id for a label.
  static String _slug(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Returns a readable title-cased label.
  static String _titleCase(String value) {
    return value
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }
}

/// TaskConstellationAnchorPlacement stores one mind-map starting point.
class TaskConstellationAnchorPlacement {
  /// Creates a render-ready anchor placement.
  const TaskConstellationAnchorPlacement({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.count,
    required this.taskIds,
    required this.size,
    required this.center,
    required this.diameter,
  });

  /// Stable anchor id.
  final String id;

  /// User-facing anchor label.
  final String label;

  /// Secondary anchor description.
  final String subtitle;

  /// Number of tasks represented by this anchor.
  final int count;

  /// Task ids represented by this anchor.
  final Set<String> taskIds;

  /// Anchor card size in logical pixels.
  final Size size;

  /// Canvas center.
  final Offset center;

  /// Legacy importance diameter for older radial calculations.
  final double diameter;

  /// Anchor card bounds used for rendering, focus, and hit testing.
  Rect get bounds {
    return Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );
  }
}

/// TaskConstellationNodePlacement stores one expanded task marker.
class TaskConstellationNodePlacement {
  /// Creates a render-ready constellation node placement.
  const TaskConstellationNodePlacement({
    required this.node,
    required this.anchorId,
    required this.center,
    required this.size,
    required this.diameter,
    required this.expanded,
  });

  /// Source task node.
  final TaskConstellationNode node;

  /// Anchor id that initially revealed this node, when available.
  final String? anchorId;

  /// Canvas center after collision relief.
  final Offset center;

  /// Task card size in logical pixels.
  final Size size;

  /// Legacy importance diameter used by older layout tests.
  final double diameter;

  /// Whether this task is currently expanded.
  final bool expanded;

  /// Task card bounds used for rendering, focus, and hit testing.
  Rect get bounds {
    return Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );
  }
}

/// _ConstellationLayoutStrategy places prepared constellation graph data.
abstract class _ConstellationLayoutStrategy {
  /// Creates a reusable layout strategy.
  const _ConstellationLayoutStrategy();

  /// Builds render-ready geometry from one projection input.
  TaskConstellationLayout build(_ConstellationLayoutInput input);

  /// Returns the virtual canvas size needed by this strategy.
  Size canvasSizeFor(_ConstellationLayoutInput input);
}

/// _AnchoredForceConstellationLayoutStrategy preserves anchors and solves children.
class _AnchoredForceConstellationLayoutStrategy
    extends _ConstellationLayoutStrategy {
  /// Creates the default constrained-force layout strategy.
  const _AnchoredForceConstellationLayoutStrategy();

  static const _ConstellationLayoutPolicy _policy =
      _ConstellationLayoutPolicy();

  /// Builds an anchored layout with local force constraints.
  @override
  TaskConstellationLayout build(_ConstellationLayoutInput input) {
    final context = TaskConstellationLayout._layoutContext(input);
    final placements = TaskConstellationLayout._anchoredForceNodePlacements(
      context.placementSeeds,
      context.nodesById,
      context.degrees,
      context.validEdges,
      context.anchors,
      input.size,
      context.activeTaskIds,
      _policy,
    );
    return TaskConstellationLayout._finishLayout(input, context, placements);
  }

  /// Returns the canvas size needed for an anchored-force expansion.
  @override
  Size canvasSizeFor(_ConstellationLayoutInput input) {
    return TaskConstellationLayout._sharedCanvasSizeFor(input);
  }
}

/// _SemanticRadialConstellationLayoutStrategy preserves the earlier star layout.
class _SemanticRadialConstellationLayoutStrategy
    extends _ConstellationLayoutStrategy {
  /// Creates the deterministic radial fallback layout strategy.
  const _SemanticRadialConstellationLayoutStrategy();

  /// Builds a radial layout with collision relaxation only.
  @override
  TaskConstellationLayout build(_ConstellationLayoutInput input) {
    final context = TaskConstellationLayout._layoutContext(input);
    final placements = TaskConstellationLayout._nodePlacements(
      context.placementSeeds,
      context.nodesById,
      context.degrees,
      input.size,
      context.activeTaskIds,
    );
    return TaskConstellationLayout._finishLayout(input, context, placements);
  }

  /// Returns the canvas size needed for a radial expansion.
  @override
  Size canvasSizeFor(_ConstellationLayoutInput input) {
    return TaskConstellationLayout._sharedCanvasSizeFor(input);
  }
}

/// _ConstellationLayoutInput stores immutable inputs for all strategies.
class _ConstellationLayoutInput {
  /// Creates shared layout input from projection and UI state.
  const _ConstellationLayoutInput({
    required this.projection,
    required this.size,
    required this.anchorDimension,
    required this.layoutStrategy,
    required this.expandedAnchorIds,
    required this.expandedTaskIds,
    required this.terrainPointsByTaskId,
  });

  /// Source projection read model.
  final TaskConstellationProjection projection;

  /// Virtual canvas size to solve within.
  final Size size;

  /// Selected anchor grouping dimension.
  final TaskConstellationAnchorDimension anchorDimension;

  /// Selected layout strategy.
  final TaskConstellationLayoutStrategyKind layoutStrategy;

  /// Requested expanded anchor ids.
  final Set<String> expandedAnchorIds;

  /// Requested expanded task ids.
  final Set<String> expandedTaskIds;

  /// Terrain insights keyed by task id.
  final Map<String, PriorityTerrainPoint> terrainPointsByTaskId;
}

/// _ConstellationLayoutContext stores prepared graph facts for strategies.
class _ConstellationLayoutContext {
  /// Creates reusable graph preparation output.
  const _ConstellationLayoutContext({
    required this.nodesById,
    required this.validEdges,
    required this.degrees,
    required this.activeAnchorIds,
    required this.activeTaskIds,
    required this.anchors,
    required this.placementSeeds,
  });

  /// Source nodes keyed by task id.
  final Map<String, TaskConstellationNode> nodesById;

  /// Valid task-to-task edges sorted by display priority.
  final List<TaskConstellationEdge> validEdges;

  /// Valid graph degree by task id.
  final Map<String, int> degrees;

  /// Existing expanded anchor ids.
  final Set<String> activeAnchorIds;

  /// Existing expanded task ids.
  final Set<String> activeTaskIds;

  /// Fixed anchor placements.
  final List<TaskConstellationAnchorPlacement> anchors;

  /// Initial task placement seeds.
  final List<_ConstellationPlacementSeed> placementSeeds;
}

/// _ConstellationLayoutPolicy tunes constrained-force placement behavior.
class _ConstellationLayoutPolicy {
  /// Creates a reusable policy for local graph expansion.
  const _ConstellationLayoutPolicy();

  /// Number of solver iterations.
  final int iterations = 96;

  /// Minimum visual gap between task cards.
  final double nodePadding = 20;

  /// Minimum visual gap around fixed anchor cards.
  final double anchorPadding = 34;

  /// Desired extra distance between related task cards.
  final double edgeGap = 72;

  /// Strength of task-to-task edge attraction.
  final double edgeStrength = 0.035;

  /// Strength of deterministic origin preservation.
  final double originStrength = 0.024;

  /// Strength of fixed anchor repulsion.
  final double anchorRepulsionStrength = 0.42;

  /// Percentage of force cooling over the simulation.
  final double coolingDrop = 0.38;

  /// Maximum per-edge movement step.
  final double maxStep = 10;

  /// Maximum per-anchor repulsion step.
  final double maxAnchorStep = 86;

  /// Maximum edges considered by the local force solver.
  final int maxForceEdges = 128;
}

/// _ConstellationAnchorModel stores grouped task metadata before placement.
class _ConstellationAnchorModel {
  const _ConstellationAnchorModel({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.nodes,
    required this.weight,
  });

  /// Stable anchor id.
  final String id;

  /// Display label.
  final String label;

  /// Display subtitle.
  final String subtitle;

  /// Tasks in the anchor.
  final List<TaskConstellationNode> nodes;

  /// Ordering and sizing weight.
  final double weight;
}

/// _ConstellationBucket stores one computed anchor bucket.
class _ConstellationBucket {
  const _ConstellationBucket({
    required this.id,
    required this.label,
    required this.subtitle,
  });

  /// Stable bucket id.
  final String id;

  /// Display label.
  final String label;

  /// Display subtitle.
  final String subtitle;
}

/// _ConstellationPlacementSeed stores one task's initial star position.
class _ConstellationPlacementSeed {
  const _ConstellationPlacementSeed({
    required this.taskId,
    required this.anchorId,
    required this.origin,
  });

  /// Source task id.
  final String taskId;

  /// Revealing anchor id when available.
  final String? anchorId;

  /// Preferred initial center.
  final Offset origin;
}

/// _MutableConstellationNode stores temporary collision-layout state.
class _MutableConstellationNode {
  _MutableConstellationNode({
    required this.node,
    required this.anchorId,
    required this.center,
    required this.origin,
    required this.size,
    required this.diameter,
  });

  /// Source task node.
  final TaskConstellationNode node;

  /// Revealing anchor id when available.
  final String? anchorId;

  /// Mutable canvas center.
  Offset center;

  /// Original canvas center.
  final Offset origin;

  /// Task card size in logical pixels.
  final Size size;

  /// Legacy importance diameter for tests and rough spacing.
  final double diameter;

  /// Bounding radius used by the simple overlap relaxation pass.
  double get radius {
    return math.sqrt(size.width * size.width + size.height * size.height) / 2;
  }

  /// Current task card bounds.
  Rect get bounds {
    return Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );
  }
}
