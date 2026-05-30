/// Task constellation projection widgets and query controls.
part of 'task_concept_views.dart';

class _TaskConstellationView extends StatefulWidget {
  const _TaskConstellationView({required this.controller});

  final AgentAwesomeAppController controller;

  /// Creates state for relationship focus toggling.
  @override
  State<_TaskConstellationView> createState() => _TaskConstellationViewState();
}

class _TaskConstellationViewState extends State<_TaskConstellationView>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _constellationQueryController;
  final TransformationController _constellationTransform =
      TransformationController();
  late final AnimationController _constellationCameraController;
  Animation<Matrix4>? _constellationCameraAnimation;
  String _constellationQuery = '';
  Set<String> _expandedAnchorIds = const <String>{};
  Set<String> _expandedTaskIds = const <String>{};
  bool _autoExpandQueryResults = true;
  Size? _constellationViewportSize;
  Rect? _constellationFocusBounds;
  Offset? _constellationPointerDownPosition;

  /// Creates animation state for constellation camera moves.
  @override
  void initState() {
    super.initState();
    _constellationQueryController = TextEditingController();
    _constellationCameraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(_applyConstellationCameraFrame);
  }

  /// Disposes the constellation viewport transform controller.
  @override
  void dispose() {
    _constellationCameraController.dispose();
    _constellationQueryController.dispose();
    _constellationTransform.dispose();
    super.dispose();
  }

  /// Builds the relationship-first constellation projection.
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final queryResult = TaskGraphConstellationQuery.run(
      controller.taskInsightIndex,
      _constellationQuery,
      selectedTaskId: controller.selectedGraphTaskId,
    );
    final queryHasText = _constellationQuery.trim().isNotEmpty;
    final projection = queryResult.projection.nodes.isEmpty && !queryHasText
        ? controller.taskConstellationProjection
        : queryResult.projection;
    final anchorDimension = _constellationAnchorDimensionForQuery(
      queryResult.group,
    );
    const layoutStrategy = TaskConstellationLayoutStrategyKind.anchoredForce;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ProjectionToolbar(
          left: <Widget>[
            _ConstellationQueryField(
              controller: _constellationQueryController,
              onChanged: _setConstellationQuery,
              onSubmitted: (_) => _scheduleConstellationRefocus(),
            ),
            _ConstellationSavedQueryMenu(
              onSelected: _applyConstellationExample,
            ),
            if (queryHasText)
              _IconBadgeButton(
                tooltip: 'Clear graph query',
                icon: Icons.close,
                onTap: _clearConstellationQuery,
              ),
            _IconBadgeButton(
              tooltip: 'Collapse constellation',
              icon: Icons.compress_outlined,
              onTap: () {
                setState(() {
                  _expandedAnchorIds = const <String>{};
                  _expandedTaskIds = const <String>{};
                  _autoExpandQueryResults = false;
                });
                _scheduleConstellationRefocus();
              },
            ),
          ],
        ),
        if (queryHasText) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            queryResult.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.agentAwesomeColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (queryResult.rows.isNotEmpty ||
              queryResult.paths.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _ConstellationQueryRows(
              rows: queryResult.rows,
              paths: queryResult.paths,
            ),
          ],
        ],
        const SizedBox(height: 12),
        Expanded(
          child: projection.nodes.isEmpty
              ? PanelEmptyBlock(
                  label: queryHasText
                      ? queryResult.summary
                      : _emptyProjectionLabel(controller, queryResult.summary),
                )
              : PanelSectionBlock(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final viewportSize = constraints.biggest;
                      final canvasSize = TaskConstellationLayout.canvasSizeFor(
                        projection,
                        viewportSize,
                        anchorDimension: anchorDimension,
                        layoutStrategy: layoutStrategy,
                      );
                      final baseLayout = TaskConstellationLayout.build(
                        projection,
                        canvasSize,
                        anchorDimension: anchorDimension,
                        layoutStrategy: layoutStrategy,
                      );
                      final effectiveExpandedAnchorIds =
                          _expandedAnchorIds.isEmpty &&
                              _expandedTaskIds.isEmpty &&
                              _autoExpandQueryResults &&
                              queryResult.expandResults
                          ? baseLayout.anchors
                                .map((anchor) => anchor.id)
                                .toSet()
                          : _expandedAnchorIds;
                      final expandedCanvasSize =
                          TaskConstellationLayout.canvasSizeFor(
                            projection,
                            viewportSize,
                            anchorDimension: anchorDimension,
                            expandedAnchorIds: effectiveExpandedAnchorIds,
                            expandedTaskIds: _expandedTaskIds,
                            layoutStrategy: layoutStrategy,
                          );
                      final layout = TaskConstellationLayout.build(
                        projection,
                        expandedCanvasSize,
                        anchorDimension: anchorDimension,
                        expandedAnchorIds: effectiveExpandedAnchorIds,
                        expandedTaskIds: _expandedTaskIds,
                        layoutStrategy: layoutStrategy,
                      );
                      _rememberConstellationFrame(viewportSize, layout);
                      return Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (event) {
                                _constellationPointerDownPosition =
                                    event.localPosition;
                              },
                              onPointerCancel: (_) {
                                _constellationPointerDownPosition = null;
                              },
                              onPointerUp: (event) {
                                _selectConstellationEdgeAt(
                                  layout,
                                  event.localPosition,
                                );
                              },
                              child: ClipRect(
                                child: InteractiveViewer(
                                  transformationController:
                                      _constellationTransform,
                                  constrained: false,
                                  minScale: 0.22,
                                  maxScale: 1.8,
                                  boundaryMargin: const EdgeInsets.all(640),
                                  onInteractionStart: (_) {
                                    _constellationCameraController.stop();
                                  },
                                  child: SizedBox(
                                    width: layout.size.width,
                                    height: layout.size.height,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: <Widget>[
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: _ConstellationPainter(
                                              layout: layout,
                                              selectedEdge: controller
                                                  .selectedConstellationEdge,
                                            ),
                                          ),
                                        ),
                                        for (final anchor in layout.anchors)
                                          _PositionedConstellationAnchor(
                                            anchor: anchor,
                                            expanded: layout.expandedAnchorIds
                                                .contains(anchor.id),
                                            onTap: () =>
                                                _toggleAnchor(anchor.id),
                                          ),
                                        for (final placement in layout.nodes)
                                          _PositionedConstellationNode(
                                            placement: placement,
                                            selected:
                                                controller
                                                    .selectedGraphTaskId ==
                                                placement.node.taskId,
                                            expanded: layout.expandedTaskIds
                                                .contains(
                                                  placement.node.taskId,
                                                ),
                                            onTap: () => _toggleTask(
                                              placement.node.taskId,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: _ConstellationOffscreenIndicators(
                                layout: layout,
                                viewportSize: viewportSize,
                                transform: _constellationTransform,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                _IconBadgeButton(
                                  tooltip: 'Zoom out',
                                  icon: Icons.remove,
                                  onTap: () => _zoomConstellation(0.9),
                                ),
                                const SizedBox(width: 6),
                                _IconBadgeButton(
                                  tooltip: 'Recenter constellation',
                                  icon: Icons.center_focus_strong_outlined,
                                  onTap: _fitConstellationToViewport,
                                ),
                                const SizedBox(width: 6),
                                _IconBadgeButton(
                                  tooltip: 'Zoom in',
                                  icon: Icons.add,
                                  onTap: () => _zoomConstellation(1.1),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// Toggles one mind-map anchor expansion.
  void _toggleAnchor(String anchorId) {
    setState(() {
      final next = Set<String>.from(_expandedAnchorIds);
      if (!next.add(anchorId)) {
        next.remove(anchorId);
      }
      _expandedAnchorIds = next;
      _autoExpandQueryResults = false;
    });
    _scheduleConstellationRefocus();
  }

  /// Toggles one task node expansion.
  void _toggleTask(String taskId) {
    setState(() {
      final next = Set<String>.from(_expandedTaskIds);
      if (!next.add(taskId)) {
        next.remove(taskId);
      }
      _expandedTaskIds = next;
      _autoExpandQueryResults = false;
    });
    widget.controller.selectTask(taskId);
    _scheduleConstellationRefocus();
  }

  /// Applies a graph query and resets the result expansion state.
  void _setConstellationQuery(String query) {
    setState(() {
      _constellationQuery = query;
      _expandedAnchorIds = const <String>{};
      _expandedTaskIds = const <String>{};
      _autoExpandQueryResults = true;
    });
    _scheduleConstellationRefocus();
  }

  /// Clears the graph query and returns to the overview constellation.
  void _clearConstellationQuery() {
    _constellationQueryController.clear();
    _setConstellationQuery('');
  }

  /// Applies one saved canonical query example.
  void _applyConstellationExample(String query) {
    _constellationQueryController
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    _setConstellationQuery(query);
  }

  /// Selects a visible constellation edge near the tapped viewport point.
  void _selectConstellationEdgeAt(
    TaskConstellationLayout layout,
    Offset viewportPosition,
  ) {
    final pointerDownPosition = _constellationPointerDownPosition;
    _constellationPointerDownPosition = null;
    final scale = _constellationScale();
    if (pointerDownPosition != null &&
        (viewportPosition - pointerDownPosition).distance > 8) {
      return;
    }
    final position = _constellationCanvasPointFor(viewportPosition);
    if (layout.containsNodeOrAnchorAt(position)) {
      return;
    }
    final edge = layout.edgeAt(
      position,
      tolerance: math.max(6, 8 / math.max(0.22, scale)),
    );
    if (edge == null) {
      widget.controller.clearConstellationEdgeSelection();
      return;
    }
    widget.controller.selectConstellationEdge(edge);
  }

  /// Converts a viewport pointer coordinate into virtual canvas coordinates.
  Offset _constellationCanvasPointFor(Offset viewportPosition) {
    final inverse = Matrix4.copy(_constellationTransform.value)..invert();
    return MatrixUtils.transformPoint(inverse, viewportPosition);
  }

  /// Returns the current constellation canvas scale factor.
  double _constellationScale() {
    final value = _constellationTransform.value.storage[0];
    if (value <= 0) {
      return 1;
    }
    return value;
  }

  /// Stores the latest visible and virtual constellation camera inputs.
  void _rememberConstellationFrame(
    Size viewportSize,
    TaskConstellationLayout layout,
  ) {
    _constellationViewportSize = viewportSize;
    _constellationFocusBounds = layout.focusBounds();
  }

  /// Refits the constellation after the next layout pass.
  void _scheduleConstellationRefocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _fitConstellationToViewport();
    });
  }

  /// Fits the current focus neighborhood within the visible viewport.
  void _fitConstellationToViewport() {
    final viewport = _constellationViewportSize;
    final bounds = _constellationFocusBounds;
    if (viewport == null || bounds == null) {
      return;
    }
    _animateConstellationTo(_constellationMatrixForBounds(viewport, bounds));
  }

  /// Returns a camera matrix that keeps one canvas rectangle visible.
  Matrix4 _constellationMatrixForBounds(Size viewport, Rect bounds) {
    final width = math.max(80.0, bounds.width);
    final height = math.max(80.0, bounds.height);
    final scale = math.min(
      1.36,
      math.max(
        0.28,
        math.min(viewport.width / width, viewport.height / height) * 0.94,
      ),
    );
    final center = bounds.center;
    final dx = viewport.width / 2 - center.dx * scale;
    final dy = viewport.height / 2 - center.dy * scale;
    return _constellationMatrix(scale: scale, dx: dx, dy: dy);
  }

  /// Zooms the constellation around the center of the viewport.
  void _zoomConstellation(double factor) {
    final viewport = _constellationViewportSize;
    if (viewport == null) {
      return;
    }
    final focalPoint = Offset(viewport.width / 2, viewport.height / 2);
    final current = _constellationTransform.value.storage;
    final currentScale = _constellationScale();
    final nextScale = (currentScale * factor).clamp(0.22, 1.8).toDouble();
    final scaleChange = nextScale / currentScale;
    final dx = focalPoint.dx - (focalPoint.dx - current[12]) * scaleChange;
    final dy = focalPoint.dy - (focalPoint.dy - current[13]) * scaleChange;
    _animateConstellationTo(
      _constellationMatrix(scale: nextScale, dx: dx, dy: dy),
      duration: const Duration(milliseconds: 260),
    );
  }

  /// Applies the current smooth camera animation frame.
  void _applyConstellationCameraFrame() {
    final animation = _constellationCameraAnimation;
    if (animation == null) {
      return;
    }
    _constellationTransform.value = animation.value;
  }

  /// Animates the constellation camera to a target transform.
  void _animateConstellationTo(
    Matrix4 target, {
    Duration duration = const Duration(milliseconds: 420),
  }) {
    _constellationCameraController
      ..stop()
      ..duration = duration;
    _constellationCameraAnimation =
        Matrix4Tween(
          begin: Matrix4.copy(_constellationTransform.value),
          end: target,
        ).animate(
          CurvedAnimation(
            parent: _constellationCameraController,
            curve: Curves.easeOutCubic,
          ),
        );
    _constellationCameraController.forward(from: 0);
  }

  /// Builds a two-dimensional pan/zoom matrix without deprecated mutators.
  Matrix4 _constellationMatrix({
    required double scale,
    required double dx,
    required double dy,
  }) {
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, dx)
      ..setEntry(1, 3, dy);
  }
}

/// Renders saved canonical graph queries for Constellation.
class _ConstellationSavedQueryMenu extends StatelessWidget {
  const _ConstellationSavedQueryMenu({required this.onSelected});

  final ValueChanged<String> onSelected;

  /// Builds the saved query picker.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: 'Saved graph queries',
      child: SizedBox(
        height: 34,
        width: 38,
        child: PopupMenuButton<String>(
          tooltip: '',
          icon: Icon(
            Icons.saved_search_outlined,
            size: 18,
            color: colors.green,
          ),
          color: colors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: colors.border),
          ),
          onSelected: onSelected,
          itemBuilder: (context) {
            return <PopupMenuEntry<String>>[
              for (final example in taskGraphConstellationQueryExamples)
                PopupMenuItem<String>(
                  value: example.query,
                  child: _ConstellationSavedQueryItem(example: example),
                ),
            ];
          },
        ),
      ),
    );
  }
}

/// Renders one saved graph query option.
class _ConstellationSavedQueryItem extends StatelessWidget {
  const _ConstellationSavedQueryItem({required this.example});

  final TaskGraphQueryExample example;

  /// Builds a compact saved query menu item.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            example.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            example.query,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the constellation canonical graph query input.
class _ConstellationQueryField extends StatelessWidget {
  const _ConstellationQueryField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  /// Builds a compact query field for canonical graph syntax.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 720),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          gradient: context.agentAwesomeControlGradient,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.search, size: 16, color: colors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText:
                      'MATCH task -[depends_on*1..3]-> task RETURN from.title, path.depth, to.title LIMIT 10',
                  hintStyle: TextStyle(color: colors.muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders compact row and path previews returned by a graph query.
class _ConstellationQueryRows extends StatelessWidget {
  const _ConstellationQueryRows({required this.rows, required this.paths});

  final List<Map<String, Object?>> rows;
  final List<TaskGraphQueryPath> paths;

  /// Builds a horizontal strip of deterministic query result values.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final previews = <_ConstellationQueryPreview>[
      for (final path in paths.take(3))
        _ConstellationQueryPreview(
          text: _constellationPathPreview(path),
          isPath: true,
        ),
      for (final row in rows.take(4))
        _ConstellationQueryPreview(
          text: _constellationRowPreview(row),
          isPath: false,
        ),
    ];
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: previews.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final preview = previews[index];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: preview.isPath
                  ? colors.coral.withValues(alpha: 0.1)
                  : colors.greenSoft.withValues(alpha: 0.26),
              border: Border.all(
                color: preview.isPath
                    ? colors.coral.withValues(alpha: 0.24)
                    : colors.green.withValues(alpha: 0.24),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              preview.text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// _ConstellationQueryPreview stores one compact query preview chip.
class _ConstellationQueryPreview {
  /// Creates one query preview chip description.
  const _ConstellationQueryPreview({required this.text, required this.isPath});

  /// Chip label.
  final String text;

  /// Whether the chip represents path metadata instead of row values.
  final bool isPath;
}

/// Returns compact text for one graph query path.
String _constellationPathPreview(TaskGraphQueryPath path) {
  final label = path.depth == 1 ? 'edge' : 'edges';
  final nodes = path.nodeIds.take(5).join(' > ');
  final overflow = path.nodeIds.length > 5 ? ' > ...' : '';
  return 'path ${path.rowIndex + 1}: ${path.depth} $label $nodes$overflow';
}

/// Returns compact text for one graph query row.
String _constellationRowPreview(Map<String, Object?> row) {
  return row.entries
      .take(3)
      .map((entry) {
        return '${entry.key}: ${_constellationRowValue(entry.value)}';
      })
      .join(' · ');
}

/// Returns compact text for one graph query row value.
String _constellationRowValue(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is DateTime) {
    return '${value.month}/${value.day}';
  }
  if (value is Iterable) {
    return value.join('>');
  }
  final text = value.toString();
  if (text.length <= 28) {
    return text;
  }
  return '${text.substring(0, 27)}…';
}

/// Renders a compact icon badge button.
class _IconBadgeButton extends StatelessWidget {
  const _IconBadgeButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  /// Builds an icon-only projection toolbar button.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.surface,
            gradient: context.agentAwesomeControlGradient,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: colors.green),
        ),
      ),
    );
  }
}

/// Renders one constellation mind-map anchor node.
class _PositionedConstellationAnchor extends StatelessWidget {
  const _PositionedConstellationAnchor({
    required this.anchor,
    required this.expanded,
    required this.onTap,
  });

  final TaskConstellationAnchorPlacement anchor;
  final bool expanded;
  final VoidCallback onTap;

  /// Builds one anchor node used as a constellation starting point.
  @override
  Widget build(BuildContext context) {
    final bounds = anchor.bounds;
    final colors = context.agentAwesomeColors;
    return Positioned(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
      child: Tooltip(
        message: '${anchor.label}\n${anchor.count} backlog items',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: expanded ? colors.greenSoft : colors.surface,
              border: Border.all(
                color: expanded ? colors.green : colors.border,
                width: expanded ? 2.2 : 1.2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  anchor.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 13,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${anchor.count} items',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PositionedConstellationNode extends StatelessWidget {
  const _PositionedConstellationNode({
    required this.placement,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final TaskConstellationNodePlacement placement;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  /// Builds a constellation node at a normalized projection position.
  @override
  Widget build(BuildContext context) {
    final node = placement.node;
    final bounds = placement.bounds;
    final color = _categoryColor(node.category);
    final colors = context.agentAwesomeColors;
    return Positioned(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
      child: Tooltip(
        message: node.explanation,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: selected || expanded ? colors.greenSoft : colors.surface,
              border: Border.all(
                color: selected || expanded ? colors.green : color,
                width: expanded
                    ? 2.3
                    : selected
                    ? 1.8
                    : 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  node.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 12,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _nodeMetaLabel(node),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns a concise metadata line for a constellation task card.
String _nodeMetaLabel(TaskConstellationNode node) {
  final parts = <String>[
    if (node.category.trim().isNotEmpty) _taskConceptLabel(node.category),
    if (node.owner.trim().isNotEmpty &&
        node.owner.toLowerCase() != node.category.toLowerCase())
      _taskConceptLabel(node.owner),
    if (node.project.trim().isNotEmpty &&
        node.project.toLowerCase() != node.category.toLowerCase())
      _taskConceptLabel(node.project),
    if (node.status.trim().isNotEmpty) _taskConceptLabel(node.status),
  ];
  if (parts.isEmpty) {
    return 'Task';
  }
  return parts.take(2).join(' • ');
}

/// Returns a readable label for compact task projection metadata.
String _taskConceptLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

/// Paints viewport-edge hints for constellation items outside the view.
class _ConstellationOffscreenIndicators extends StatelessWidget {
  const _ConstellationOffscreenIndicators({
    required this.layout,
    required this.viewportSize,
    required this.transform,
  });

  final TaskConstellationLayout layout;
  final Size viewportSize;
  final TransformationController transform;

  /// Builds indicators that move as the constellation is panned or zoomed.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: transform,
      builder: (context, _) {
        return CustomPaint(
          size: viewportSize,
          painter: _ConstellationOffscreenIndicatorPainter(
            layout: layout,
            transform: Matrix4.copy(transform.value),
          ),
        );
      },
    );
  }
}

/// Draws grouped edge bars for offscreen constellation items.
class _ConstellationOffscreenIndicatorPainter extends CustomPainter {
  const _ConstellationOffscreenIndicatorPainter({
    required this.layout,
    required this.transform,
  });

  final TaskConstellationLayout layout;
  final Matrix4 transform;

  /// Paints edge bars where offscreen items project onto the viewport edge.
  @override
  void paint(Canvas canvas, Size size) {
    final viewport = Offset.zero & size;
    final visible = viewport.deflate(16);
    final buckets =
        <_ConstellationIndicatorKey, _ConstellationIndicatorBucket>{};
    for (final anchor in layout.anchors) {
      _collectIndicator(
        buckets,
        size,
        visible,
        anchor.center,
        AgentAwesomeColors.green,
      );
    }
    for (final node in layout.nodes) {
      _collectIndicator(
        buckets,
        size,
        visible,
        node.center,
        _categoryColor(node.node.category),
      );
    }
    for (final bucket in buckets.values) {
      _paintBucket(canvas, size, bucket);
    }
  }

  /// Adds one offscreen item to a grouped edge indicator bucket.
  void _collectIndicator(
    Map<_ConstellationIndicatorKey, _ConstellationIndicatorBucket> buckets,
    Size size,
    Rect visible,
    Offset canvasPoint,
    Color color,
  ) {
    final viewportPoint = MatrixUtils.transformPoint(transform, canvasPoint);
    if (visible.contains(viewportPoint)) {
      return;
    }
    final hit = _edgeHit(size, viewportPoint);
    if (hit == null) {
      return;
    }
    final bucketIndex = hit.side.isVertical
        ? (hit.point.dy / 44).floor()
        : (hit.point.dx / 44).floor();
    final key = _ConstellationIndicatorKey(hit.side, bucketIndex);
    final bucket = buckets[key];
    if (bucket == null) {
      buckets[key] = _ConstellationIndicatorBucket(
        side: hit.side,
        point: hit.point,
        color: color,
      );
      return;
    }
    bucket.add(hit.point);
  }

  /// Returns the viewport-edge hit for a line from center to target.
  _ConstellationEdgeHit? _edgeHit(Size size, Offset target) {
    final center = Offset(size.width / 2, size.height / 2);
    final delta = target - center;
    if (delta.distance < 0.01) {
      return null;
    }
    final halfWidth = math.max(1.0, size.width / 2 - 8);
    final halfHeight = math.max(1.0, size.height / 2 - 8);
    final tx = delta.dx.abs() < 0.01
        ? double.infinity
        : halfWidth / delta.dx.abs();
    final ty = delta.dy.abs() < 0.01
        ? double.infinity
        : halfHeight / delta.dy.abs();
    final useVertical = tx < ty;
    final t = math.min(tx, ty);
    final raw = center + delta * t;
    if (useVertical) {
      final side = delta.dx < 0
          ? _ConstellationIndicatorSide.left
          : _ConstellationIndicatorSide.right;
      return _ConstellationEdgeHit(
        side: side,
        point: Offset(
          side == _ConstellationIndicatorSide.left ? 4 : size.width - 4,
          raw.dy.clamp(16, size.height - 16).toDouble(),
        ),
      );
    }
    final side = delta.dy < 0
        ? _ConstellationIndicatorSide.top
        : _ConstellationIndicatorSide.bottom;
    return _ConstellationEdgeHit(
      side: side,
      point: Offset(
        raw.dx.clamp(16, size.width - 16).toDouble(),
        side == _ConstellationIndicatorSide.top ? 4 : size.height - 4,
      ),
    );
  }

  /// Paints one grouped edge indicator.
  void _paintBucket(
    Canvas canvas,
    Size size,
    _ConstellationIndicatorBucket bucket,
  ) {
    final countBoost = math.min(28.0, bucket.count * 5.0);
    final length = 30.0 + countBoost;
    final thickness = math.min(12.0, 6.0 + bucket.count * 0.7);
    final center = bucket.edgeCenter(size);
    final rect = Rect.fromCenter(
      center: center,
      width: bucket.side.isVertical ? thickness : length,
      height: bucket.side.isVertical ? length : thickness,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(99));
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = bucket.color.withValues(alpha: 0.68);
    canvas.drawRRect(rrect, paint);
    if (bucket.count > 1) {
      _paintBucketCount(canvas, bucket, center);
    }
  }

  /// Paints a small count beside grouped indicators.
  void _paintBucketCount(
    Canvas canvas,
    _ConstellationIndicatorBucket bucket,
    Offset center,
  ) {
    final label = bucket.count.toString();
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  /// Reports whether the edge hints need repainting.
  @override
  bool shouldRepaint(
    covariant _ConstellationOffscreenIndicatorPainter oldDelegate,
  ) {
    return oldDelegate.layout != layout || oldDelegate.transform != transform;
  }
}

/// _ConstellationIndicatorSide identifies one viewport edge.
enum _ConstellationIndicatorSide {
  /// Top viewport edge.
  top,

  /// Right viewport edge.
  right,

  /// Bottom viewport edge.
  bottom,

  /// Left viewport edge.
  left;

  /// Returns true for left/right edge indicators.
  bool get isVertical {
    return this == _ConstellationIndicatorSide.left ||
        this == _ConstellationIndicatorSide.right;
  }
}

/// _ConstellationEdgeHit stores an offscreen projection edge hit.
class _ConstellationEdgeHit {
  /// Creates an edge hit from a projected offscreen item.
  const _ConstellationEdgeHit({required this.side, required this.point});

  /// Viewport side hit by the projected line.
  final _ConstellationIndicatorSide side;

  /// Viewport edge point.
  final Offset point;
}

/// _ConstellationIndicatorKey groups nearby offscreen item hints.
class _ConstellationIndicatorKey {
  /// Creates a stable indicator bucket key.
  const _ConstellationIndicatorKey(this.side, this.index);

  /// Viewport side.
  final _ConstellationIndicatorSide side;

  /// Quantized side position.
  final int index;

  /// Compares indicator keys by side and bucket index.
  @override
  bool operator ==(Object other) {
    return other is _ConstellationIndicatorKey &&
        other.side == side &&
        other.index == index;
  }

  /// Hashes the side and bucket index.
  @override
  int get hashCode => Object.hash(side, index);
}

/// _ConstellationIndicatorBucket stores grouped offscreen indicator state.
class _ConstellationIndicatorBucket {
  /// Creates a grouped offscreen indicator.
  _ConstellationIndicatorBucket({
    required this.side,
    required this.point,
    required this.color,
  });

  /// Viewport side for this group.
  final _ConstellationIndicatorSide side;

  /// Representative edge point.
  Offset point;

  /// Representative item color.
  final Color color;

  /// Number of grouped items.
  int count = 1;

  /// Adds another projected item to this group.
  void add(Offset nextPoint) {
    point = Offset.lerp(point, nextPoint, 1 / (count + 1))!;
    count++;
  }

  /// Returns the bar center nudged inside the viewport.
  Offset edgeCenter(Size size) {
    return switch (side) {
      _ConstellationIndicatorSide.left => Offset(6, point.dy),
      _ConstellationIndicatorSide.right => Offset(size.width - 6, point.dy),
      _ConstellationIndicatorSide.top => Offset(point.dx, 6),
      _ConstellationIndicatorSide.bottom => Offset(point.dx, size.height - 6),
    };
  }
}
