/// Shared task projection toolbar, painters, and utility helpers.
part of 'task_concept_views.dart';

class _ProjectionToolbar extends StatelessWidget {
  const _ProjectionToolbar({required this.left});

  final List<Widget> left;

  /// Builds compact projection controls above canvases.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: left)),
      ],
    );
  }
}

class _ConstellationPainter extends CustomPainter {
  const _ConstellationPainter({required this.layout, this.selectedEdge});

  final TaskConstellationLayout layout;
  final TaskConstellationEdge? selectedEdge;

  /// Paints anchor spokes and relation edges.
  @override
  void paint(Canvas canvas, Size size) {
    final anchors = layout.anchorById;
    final nodes = layout.nodeByTaskId;
    for (final node in layout.nodes) {
      final anchorId = node.anchorId;
      final anchor = anchorId == null ? null : anchors[anchorId];
      if (anchor == null || !layout.expandedAnchorIds.contains(anchor.id)) {
        continue;
      }
      final edge = layout.anchorMembershipEdge(anchor, node);
      final selected = _sameConstellationEdge(edge, selectedEdge);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3.2 : 1
        ..strokeCap = StrokeCap.round
        ..color = AgentAwesomeColors.green.withValues(
          alpha: selected ? 0.82 : 0.1,
        );
      if (selected) {
        final halo = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = AgentAwesomeColors.green.withValues(alpha: 0.14);
        canvas.drawLine(anchor.center, node.center, halo);
      }
      canvas.drawLine(anchor.center, node.center, paint);
    }
    final selectedEdges = <TaskConstellationEdge>[];
    for (final edge in layout.visibleEdges) {
      if (_sameConstellationEdge(edge, selectedEdge)) {
        selectedEdges.add(edge);
        continue;
      }
      final from = nodes[edge.fromTaskId];
      final to = nodes[edge.toTaskId];
      if (from == null || to == null) {
        continue;
      }
      final highlighted = _constellationEdgeIsHighlighted(edge);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlighted ? 3 : 1
        ..strokeCap = StrokeCap.round
        ..color = _edgeColor(edge).withValues(alpha: highlighted ? 0.76 : 0.18);
      if (highlighted) {
        final halo = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = _edgeColor(edge).withValues(alpha: 0.12);
        canvas.drawLine(from.center, to.center, halo);
      }
      canvas.drawLine(from.center, to.center, paint);
    }
    for (final edge in selectedEdges) {
      final from = nodes[edge.fromTaskId];
      final to = nodes[edge.toTaskId];
      if (from == null || to == null) {
        continue;
      }
      final color = _edgeColor(edge);
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.16);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.8
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.9);
      canvas
        ..drawLine(from.center, to.center, halo)
        ..drawLine(from.center, to.center, paint);
    }
  }

  /// Reports whether this painter needs repainting.
  @override
  bool shouldRepaint(covariant _ConstellationPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        !_sameConstellationEdge(oldDelegate.selectedEdge, selectedEdge);
  }
}

/// Returns an empty-state label with projection loading detail when available.
String _emptyProjectionLabel(
  AgentAwesomeAppController controller,
  String fallback,
) {
  final message = _firstNonEmpty(<String>[
    controller.taskInsightMessage.trim(),
    controller.taskProjectionMessage.trim(),
  ]);
  if (message.isEmpty) {
    return fallback;
  }
  return message;
}

/// Returns missing WBS fields for display diagnostics.
List<String> _wbsMissingFields(WorkspaceTask task) {
  final workBreakdown = task.workBreakdown;
  return <String>[
    if (workBreakdown.code.trim().isEmpty) 'code',
    if (workBreakdown.deliverable.trim().isEmpty) 'deliverable',
    if (workBreakdown.startCriteria.isEmpty) 'start',
    if (workBreakdown.acceptanceCriteria.isEmpty) 'done',
    if (workBreakdown.resources.isEmpty) 'resources',
    if (workBreakdown.requirementRefs.isEmpty) 'requirements',
    if (workBreakdown.rubricRefs.isEmpty) 'rubric',
    if (task.estimateMinutes <= 0) 'time',
    if (workBreakdown.estimatedCostCents <= 0) 'spend',
  ];
}

/// Summarizes one WBS resource for a table cell.
String _resourceSummary(TaskResourceRequirement resource) {
  final details = <String>[
    if (resource.type.isNotEmpty) resource.type,
    if (resource.quantity > 0)
      '${formatTaskQuantity(resource.quantity)} ${resource.unit}'.trim(),
    formatTaskResourceSpend(resource),
  ].where((item) => item.isNotEmpty).toList();
  if (details.isEmpty) {
    return resource.name;
  }
  return '${resource.name} · ${details.join(' · ')}';
}

/// Returns the layout grouping that best matches a graph query result.
TaskConstellationAnchorDimension _constellationAnchorDimensionForQuery(
  TaskGraphQueryGroup group,
) {
  return switch (group) {
    TaskGraphQueryGroup.project => TaskConstellationAnchorDimension.project,
    TaskGraphQueryGroup.owner => TaskConstellationAnchorDimension.owner,
    TaskGraphQueryGroup.status => TaskConstellationAnchorDimension.status,
    TaskGraphQueryGroup.time => TaskConstellationAnchorDimension.time,
    TaskGraphQueryGroup.metadata => TaskConstellationAnchorDimension.category,
  };
}

/// Returns the first non-empty text value.
String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

/// Returns a color for a constellation category.
Color _categoryColor(String category) {
  final normalized = category.toLowerCase();
  if (normalized.contains('errand') || normalized.contains('shopping')) {
    return const Color(0xffd99a22);
  }
  if (normalized.contains('work')) {
    return AgentAwesomeColors.green;
  }
  if (normalized.contains('health')) {
    return const Color(0xff5f87b4);
  }
  if (normalized.contains('personal')) {
    return const Color(0xff7b6398);
  }
  return AgentAwesomeColors.border;
}

/// Returns a color for a constellation edge.
Color _edgeColor(TaskConstellationEdge edge) {
  if (edge.source == 'query_path') {
    return AgentAwesomeColors.green;
  }
  if (edge.source == 'critical_path') {
    return AgentAwesomeColors.coral;
  }
  if (edge.source == 'materialized_risk') {
    return const Color(0xff7b6398);
  }
  if (edge.relationType == 'depends_on' || edge.relationType == 'blocks') {
    return AgentAwesomeColors.coral;
  }
  if (edge.source == 'explicit') {
    return AgentAwesomeColors.green;
  }
  return AgentAwesomeColors.muted;
}

/// Returns whether a constellation edge should be visually emphasized.
bool _constellationEdgeIsHighlighted(TaskConstellationEdge edge) {
  return edge.source == 'query_path' ||
      edge.source == 'critical_path' ||
      edge.source == 'materialized_risk';
}

/// Returns true when two constellation edges represent the same relation.
bool _sameConstellationEdge(
  TaskConstellationEdge? left,
  TaskConstellationEdge? right,
) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.fromTaskId == right.fromTaskId &&
      left.toTaskId == right.toTaskId &&
      left.relationType == right.relationType &&
      left.source == right.source &&
      left.explanation == right.explanation;
}
