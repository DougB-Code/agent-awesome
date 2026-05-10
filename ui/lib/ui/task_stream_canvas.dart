/// Renders the colorful task stream task-fact projection.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app/theme.dart';
import '../domain/models.dart';
import 'task_stream_axes.dart';

/// TaskStreamCanvas renders task stream lanes as flowing task-fact bands.
class TaskStreamCanvas extends StatefulWidget {
  /// Creates a task stream canvas bound to the shared app controller.
  const TaskStreamCanvas({
    super.key,
    required this.lanes,
    required this.links,
    required this.controller,
    this.rowAxis = TaskStreamAxisDimension.project,
    this.rowBucketsByTaskId = const <String, TaskStreamAxisBucket>{},
  });

  /// Ordered backend stream lanes used as timeline columns.
  final List<TaskStreamLane> lanes;

  /// Visible task relation links used for branch and convergence drawing.
  final List<TaskStreamLink> links;

  /// Shared app controller for task selection.
  final AgentAwesomeAppController controller;

  /// Dimension used for left-side row ordering.
  final TaskStreamAxisDimension rowAxis;

  /// Row bucket lookup keyed by task id for the selected left axis.
  final Map<String, TaskStreamAxisBucket> rowBucketsByTaskId;

  /// Creates state for synchronized sticky stream scrolling.
  @override
  State<TaskStreamCanvas> createState() => _TaskStreamCanvasState();
}

class _TaskStreamCanvasState extends State<TaskStreamCanvas> {
  final ScrollController _bodyHorizontal = ScrollController();
  final ScrollController _headerHorizontal = ScrollController();
  final ScrollController _bodyVertical = ScrollController();
  final ScrollController _labelVertical = ScrollController();
  TaskStreamFocus? _focus;
  bool _compactFocus = false;
  bool _syncingScroll = false;

  /// Connects scroll controllers for sticky headers and labels.
  @override
  void initState() {
    super.initState();
    _bodyHorizontal.addListener(_syncHeaderScroll);
    _bodyVertical.addListener(_syncLabelScroll);
  }

  /// Disposes sticky scroll controllers.
  @override
  void dispose() {
    _bodyHorizontal.dispose();
    _headerHorizontal.dispose();
    _bodyVertical.dispose();
    _labelVertical.dispose();
    super.dispose();
  }

  /// Builds the stream canvas and positioned task overlays.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = TaskStreamCanvasLayout.build(
          widget.lanes,
          widget.links,
          constraints,
          rowAxis: widget.rowAxis,
          rowBucketsByTaskId: widget.rowBucketsByTaskId,
          compact: _compactFocus && _focus != null,
          focus: _compactFocus ? _focus : null,
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              gradient: context.agentAwesomeCardGradient,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: <Widget>[
                SizedBox(
                  height: TaskStreamCanvasLayout._headerHeight,
                  child: Row(
                    children: <Widget>[
                      SizedBox(width: layout.labelWidth),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _headerHorizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: layout.size.width,
                            height: TaskStreamCanvasLayout._headerHeight,
                            child: Stack(
                              children: <Widget>[
                                for (final column in layout.columns)
                                  Positioned(
                                    left: column.left + 18,
                                    top: 18,
                                    width: column.width - 36,
                                    height: 46,
                                    child: _StreamColumnHeader(column: column),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.border),
                Expanded(child: _buildScrollableBody(layout)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Builds synchronized row labels and scrollable stream content.
  Widget _buildScrollableBody(TaskStreamCanvasLayout layout) {
    return Stack(
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(
              width: layout.labelWidth,
              child: SingleChildScrollView(
                controller: _labelVertical,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: layout.labelWidth,
                  height: layout.size.height,
                  child: Stack(
                    children: <Widget>[
                      for (final row in layout.rows)
                        Positioned(
                          left: 20,
                          top: row.centerY - 25,
                          width: layout.labelWidth - 32,
                          height: 52,
                          child: _StreamRowLabel(row: row),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            VerticalDivider(width: 1, color: context.agentAwesomeColors.border),
            Expanded(
              child: Scrollbar(
                controller: _bodyHorizontal,
                child: SingleChildScrollView(
                  controller: _bodyHorizontal,
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _bodyVertical,
                    child: SizedBox(
                      width: layout.size.width,
                      height: layout.size.height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          Positioned.fill(
                            child: CustomPaint(
                              painter: TaskStreamCanvasPainter(
                                layout: layout,
                                focus: _focus,
                                colors: context.agentAwesomeColors,
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTapDown: (details) {
                                _applyFocus(
                                  layout.focusAt(details.localPosition),
                                  additive: _isAdditiveFocusGesture(),
                                );
                              },
                            ),
                          ),
                          for (final placement in layout.placements)
                            Positioned.fromRect(
                              rect: placement.rect,
                              child: _StreamTaskCard(
                                placement: placement,
                                selected:
                                    widget.controller.selectedTask?.id ==
                                    placement.card.taskId,
                                focused: _isFocusedCard(layout, placement),
                                faded: _isFadedCard(layout, placement),
                                compact: layout.compact,
                                onTap: () {
                                  widget.controller.selectTask(
                                    placement.card.taskId,
                                  );
                                  _applyFocus(
                                    TaskStreamFocus.card(placement.card),
                                    additive: _isAdditiveFocusGesture(),
                                  );
                                },
                              ),
                            ),
                          for (final row in layout.rows)
                            Positioned(
                              left: layout.endX - 17,
                              top: row.centerY - 17,
                              width: 34,
                              height: 34,
                              child: _StreamContinuationButton(row: row),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_focus != null)
          Positioned(
            top: 10,
            right: 14,
            child: _StreamFocusControls(
              compact: _compactFocus,
              onToggleCompact: _toggleCompactFocus,
              onClear: () => _setFocus(null),
            ),
          ),
      ],
    );
  }

  /// Mirrors body horizontal scrolling into the sticky column header.
  void _syncHeaderScroll() {
    _syncScrollOffset(_bodyHorizontal, _headerHorizontal);
  }

  /// Mirrors body vertical scrolling into the sticky row labels.
  void _syncLabelScroll() {
    _syncScrollOffset(_bodyVertical, _labelVertical);
  }

  /// Copies a scroll offset between controllers without feedback loops.
  void _syncScrollOffset(ScrollController source, ScrollController target) {
    if (_syncingScroll || !source.hasClients || !target.hasClients) {
      return;
    }
    final targetPosition = target.position;
    final offset = source.offset.clamp(
      targetPosition.minScrollExtent,
      targetPosition.maxScrollExtent,
    );
    if ((target.offset - offset).abs() < 0.5) {
      return;
    }
    _syncingScroll = true;
    target.jumpTo(offset);
    _syncingScroll = false;
  }

  /// Sets the active visual focus for stream dimming.
  void _setFocus(TaskStreamFocus? focus) {
    if (_focus == focus) {
      return;
    }
    setState(() => _focus = focus);
  }

  /// Applies either replacement or additive focus selection.
  void _applyFocus(TaskStreamFocus? focus, {required bool additive}) {
    if (!additive) {
      _setFocus(focus);
      return;
    }
    if (focus == null || focus.isEmpty) {
      return;
    }
    final current = _focus ?? const TaskStreamFocus();
    final next = current.toggled(focus);
    _setFocus(next.isEmpty ? null : next);
  }

  /// Returns whether the current pointer action should toggle focus targets.
  bool _isAdditiveFocusGesture() {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
  }

  /// Toggles compact focus mode, isolating the focused graph neighborhood.
  void _toggleCompactFocus() {
    setState(() => _compactFocus = !_compactFocus);
  }

  /// Returns whether the placed card belongs to the active focus.
  bool _isFocusedCard(
    TaskStreamCanvasLayout layout,
    TaskStreamCardPlacement placement,
  ) {
    final focus = _focus;
    if (focus == null) {
      return false;
    }
    return layout.isFocusedCard(placement, focus);
  }

  /// Returns whether the placed card should fade behind the active focus.
  bool _isFadedCard(
    TaskStreamCanvasLayout layout,
    TaskStreamCardPlacement placement,
  ) {
    final focus = _focus;
    if (focus == null) {
      return false;
    }
    return !layout.isFocusedCard(placement, focus);
  }
}

/// TaskStreamFocus describes the currently emphasized route, row, or task.
class TaskStreamFocus {
  /// Creates a task stream focus target.
  const TaskStreamFocus({
    this.taskId = '',
    this.streamId = '',
    this.rowId = '',
    this.taskIds = const <String>{},
    this.streamIds = const <String>{},
    this.rowIds = const <String>{},
  });

  /// Creates focus around one card and its immediate graph neighborhood.
  factory TaskStreamFocus.card(TaskStreamCard card) {
    return TaskStreamFocus(taskId: card.taskId);
  }

  /// Creates focus around one link and its route.
  factory TaskStreamFocus.link(TaskStreamLink link) {
    return TaskStreamFocus(
      taskId: link.streamId.isEmpty ? link.fromTaskId : '',
      streamId: link.streamId,
    );
  }

  /// Focused task id.
  final String taskId;

  /// Focused stream route id.
  final String streamId;

  /// Focused row id.
  final String rowId;

  /// Additional focused task ids.
  final Set<String> taskIds;

  /// Additional focused stream route ids.
  final Set<String> streamIds;

  /// Additional focused row ids.
  final Set<String> rowIds;

  /// Whether this focus has no target.
  bool get isEmpty {
    return taskId.isEmpty &&
        streamId.isEmpty &&
        rowId.isEmpty &&
        taskIds.isEmpty &&
        streamIds.isEmpty &&
        rowIds.isEmpty;
  }

  /// Returns whether a task id is directly selected.
  bool hasTaskId(String id) {
    return id.isNotEmpty && (taskId == id || taskIds.contains(id));
  }

  /// Returns whether a stream route id is directly selected.
  bool hasStreamId(String id) {
    return id.isNotEmpty && (streamId == id || streamIds.contains(id));
  }

  /// Returns whether a row id is directly selected.
  bool hasRowId(String id) {
    return id.isNotEmpty && (rowId == id || rowIds.contains(id));
  }

  /// Returns a new focus with the provided target toggled in this focus set.
  TaskStreamFocus toggled(TaskStreamFocus target) {
    final nextTaskIds = effectiveTaskIds();
    final nextStreamIds = effectiveStreamIds();
    final nextRowIds = effectiveRowIds();
    _toggleIds(nextTaskIds, target.effectiveTaskIds());
    _toggleIds(nextStreamIds, target.effectiveStreamIds());
    _toggleIds(nextRowIds, target.effectiveRowIds());
    return TaskStreamFocus(
      taskIds: nextTaskIds,
      streamIds: nextStreamIds,
      rowIds: nextRowIds,
    );
  }

  /// Returns all focused task ids, including the primary single-value field.
  Set<String> effectiveTaskIds() {
    return <String>{...taskIds, if (taskId.isNotEmpty) taskId};
  }

  /// Returns all focused stream ids, including the primary single-value field.
  Set<String> effectiveStreamIds() {
    return <String>{...streamIds, if (streamId.isNotEmpty) streamId};
  }

  /// Returns all focused row ids, including the primary single-value field.
  Set<String> effectiveRowIds() {
    return <String>{...rowIds, if (rowId.isNotEmpty) rowId};
  }

  /// Compares focus values.
  @override
  bool operator ==(Object other) {
    return other is TaskStreamFocus &&
        other.taskId == taskId &&
        other.streamId == streamId &&
        other.rowId == rowId &&
        _stringSetsEqual(other.taskIds, taskIds) &&
        _stringSetsEqual(other.streamIds, streamIds) &&
        _stringSetsEqual(other.rowIds, rowIds);
  }

  /// Hashes focus values.
  @override
  int get hashCode {
    return Object.hash(
      taskId,
      streamId,
      rowId,
      Object.hashAllUnordered(taskIds),
      Object.hashAllUnordered(streamIds),
      Object.hashAllUnordered(rowIds),
    );
  }
}

/// Toggles all requested ids inside a mutable id set.
void _toggleIds(Set<String> selected, Set<String> requested) {
  for (final id in requested) {
    if (!selected.remove(id)) {
      selected.add(id);
    }
  }
}

/// Returns whether two string sets contain identical values.
bool _stringSetsEqual(Set<String> left, Set<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final value in left) {
    if (!right.contains(value)) {
      return false;
    }
  }
  return true;
}

/// TaskStreamCanvasLayout stores computed stream geometry.
class TaskStreamCanvasLayout {
  /// Creates a computed stream canvas layout.
  const TaskStreamCanvasLayout({
    required this.size,
    required this.labelWidth,
    required this.endX,
    required this.compact,
    required this.cardWidth,
    required this.cardHeight,
    required this.cardStackStep,
    required this.columns,
    required this.rows,
    required this.placements,
    required this.links,
  });

  static const double _minimumColumnWidth = 220;
  static const double _labelWidth = 150;
  static const double _rightGutter = 92;
  static const double _headerHeight = 72;
  static const double _rowPadding = 34;
  static const double _regularCardWidth = 178;
  static const double _regularCardHeight = 92;
  static const double _regularCardStackStep = 104;
  static const double _compactCardWidth = 156;
  static const double _compactCardHeight = 76;
  static const double _compactCardStackStep = 82;
  static const double _linkHitSlop = 16;
  static const int _linkHitSamples = 32;

  /// Full canvas size.
  final Size size;

  /// Width reserved for row labels.
  final double labelWidth;

  /// X-coordinate of the continuation endpoint column.
  final double endX;

  /// Whether this layout uses reduced-density focus geometry.
  final bool compact;

  /// Width used for positioned task cards.
  final double cardWidth;

  /// Height used for positioned task cards.
  final double cardHeight;

  /// Vertical offset between stacked cards in the same row and column.
  final double cardStackStep;

  /// Timeline columns.
  final List<TaskStreamColumnLayout> columns;

  /// Colored stream rows.
  final List<TaskStreamRowLayout> rows;

  /// Positioned task cards.
  final List<TaskStreamCardPlacement> placements;

  /// Positioned cross-row task relation links.
  final List<TaskStreamLinkPlacement> links;

  /// Builds canvas geometry from backend stream lanes and viewport constraints.
  static TaskStreamCanvasLayout build(
    List<TaskStreamLane> lanes,
    List<TaskStreamLink> links,
    BoxConstraints constraints, {
    TaskStreamAxisDimension rowAxis = TaskStreamAxisDimension.project,
    Map<String, TaskStreamAxisBucket> rowBucketsByTaskId =
        const <String, TaskStreamAxisBucket>{},
    bool compact = false,
    TaskStreamFocus? focus,
  }) {
    final visibleLinks = compact && focus != null
        ? _focusedStreamLinks(links, focus)
        : links;
    final visibleLanes = compact && focus != null
        ? _focusedStreamLanes(lanes, links, focus, rowBucketsByTaskId)
        : lanes;
    final cardWidth = compact ? _compactCardWidth : _regularCardWidth;
    final cardHeight = compact ? _compactCardHeight : _regularCardHeight;
    final cardStackStep = compact
        ? _compactCardStackStep
        : _regularCardStackStep;
    final columns = _buildColumns(visibleLanes, constraints);
    final rows = _buildRows(
      visibleLanes,
      rowBucketsByTaskId,
      rowAxis,
      compact: compact,
    );
    final rowHeights = _rowHeights(
      rows,
      visibleLanes,
      rowBucketsByTaskId,
      cardStackStep,
      cardHeight,
    );
    final canvasWidth =
        columns.fold<double>(0, (width, column) => width + column.width) +
        _rightGutter;
    final contentHeight =
        rowHeights.fold<double>(0, (height, rowHeight) => height + rowHeight) +
        _rowPadding;
    final viewportHeight = constraints.maxHeight.isFinite
        ? math.max(0.0, constraints.maxHeight - _headerHeight - 1)
        : 568.0;
    final canvasHeight = math.max(contentHeight, viewportHeight);
    final laidOutRows = <TaskStreamRowLayout>[];
    var rowTop = 0.0;
    for (var index = 0; index < rows.length; index++) {
      final base = rows[index];
      final height = rowHeights[index];
      laidOutRows.add(
        base.copyWith(
          top: rowTop,
          height: height,
          centerY: rowTop + height / 2,
        ),
      );
      rowTop += height;
    }
    final placements = _buildPlacements(
      lanes: visibleLanes,
      rows: laidOutRows,
      columns: columns,
      rowBucketsByTaskId: rowBucketsByTaskId,
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      cardStackStep: cardStackStep,
    );
    final linkPlacements = _buildLinkPlacements(
      links: visibleLinks,
      placements: placements,
    );
    return TaskStreamCanvasLayout(
      size: Size(canvasWidth, canvasHeight),
      labelWidth: _labelWidth,
      endX: canvasWidth - 48,
      compact: compact,
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      cardStackStep: cardStackStep,
      columns: columns,
      rows: laidOutRows,
      placements: placements,
      links: linkPlacements,
    );
  }

  /// Builds visible timeline columns from backend lanes.
  static List<TaskStreamColumnLayout> _buildColumns(
    List<TaskStreamLane> lanes,
    BoxConstraints constraints,
  ) {
    final columnCount = math.max(lanes.length, 1);
    final availableWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth - _labelWidth - _rightGutter - 1
        : 980.0;
    final columnWidth = math.max(
      _minimumColumnWidth,
      availableWidth / columnCount,
    );
    var left = 0.0;
    return <TaskStreamColumnLayout>[
      for (final lane in lanes)
        TaskStreamColumnLayout(
          laneId: lane.id,
          title: lane.title,
          subtitle: lane.subtitle,
          left: () {
            final value = left;
            left += columnWidth;
            return value;
          }(),
          width: columnWidth,
        ),
    ];
  }

  /// Builds row geometry from the selected left-axis buckets.
  static List<TaskStreamRowLayout> _buildRows(
    List<TaskStreamLane> lanes,
    Map<String, TaskStreamAxisBucket> rowBucketsByTaskId,
    TaskStreamAxisDimension rowAxis, {
    required bool compact,
  }) {
    final rows = <String, TaskStreamRowLayout>{};
    for (final lane in lanes) {
      for (final card in lane.cards) {
        final bucket = _rowBucket(card, rowBucketsByTaskId);
        rows.putIfAbsent(bucket.id, () {
          return TaskStreamRowLayout(
            id: bucket.id,
            title: bucket.title,
            subtitle: bucket.subtitle,
            color: bucket.color,
            icon: bucket.icon,
            top: 0,
            height: 0,
            centerY: 0,
          );
        });
      }
    }
    final orderedRows = rows.values.toList();
    if (TaskStreamAxisProjector.hasOrderedBuckets(rowAxis)) {
      orderedRows.sort((left, right) {
        return TaskStreamAxisProjector.bucketSortKey(
          left.id,
          rowAxis,
        ).compareTo(TaskStreamAxisProjector.bucketSortKey(right.id, rowAxis));
      });
    }
    return orderedRows;
  }

  /// Computes a row height large enough for stacked cards.
  static List<double> _rowHeights(
    List<TaskStreamRowLayout> rows,
    List<TaskStreamLane> lanes,
    Map<String, TaskStreamAxisBucket> rowBucketsByTaskId,
    double cardStackStep,
    double cardHeight,
  ) {
    return <double>[
      for (final row in rows)
        math.max(
          cardHeight + 20,
          _maxCardsInRowColumn(row, lanes, rowBucketsByTaskId) * cardStackStep +
              26,
        ),
    ];
  }

  /// Returns the densest card stack count for a row.
  static int _maxCardsInRowColumn(
    TaskStreamRowLayout row,
    List<TaskStreamLane> lanes,
    Map<String, TaskStreamAxisBucket> rowBucketsByTaskId,
  ) {
    var maxCount = 1;
    for (final lane in lanes) {
      final count = lane.cards
          .where((card) => _rowBucket(card, rowBucketsByTaskId).id == row.id)
          .length;
      maxCount = math.max(maxCount, count);
    }
    return maxCount;
  }

  /// Places task cards in their selected column and row buckets.
  static List<TaskStreamCardPlacement> _buildPlacements({
    required List<TaskStreamLane> lanes,
    required List<TaskStreamRowLayout> rows,
    required List<TaskStreamColumnLayout> columns,
    required Map<String, TaskStreamAxisBucket> rowBucketsByTaskId,
    required double cardWidth,
    required double cardHeight,
    required double cardStackStep,
  }) {
    final rowById = <String, TaskStreamRowLayout>{
      for (final row in rows) row.id: row,
    };
    final placements = <TaskStreamCardPlacement>[];
    for (var columnIndex = 0; columnIndex < lanes.length; columnIndex++) {
      final lane = lanes[columnIndex];
      final column = columns[columnIndex];
      final cardsByRow = <String, List<TaskStreamCard>>{};
      for (final card in lane.cards) {
        final bucket = _rowBucket(card, rowBucketsByTaskId);
        cardsByRow.putIfAbsent(bucket.id, () => <TaskStreamCard>[]);
        cardsByRow[bucket.id]!.add(card);
      }
      for (final entry in cardsByRow.entries) {
        final row = rowById[entry.key];
        if (row == null) {
          continue;
        }
        final cards = entry.value;
        for (var stackIndex = 0; stackIndex < cards.length; stackIndex++) {
          final stackHeight = cardHeight + (cards.length - 1) * cardStackStep;
          final top =
              row.centerY - stackHeight / 2 + stackIndex * cardStackStep;
          placements.add(
            TaskStreamCardPlacement(
              card: cards[stackIndex],
              row: row,
              column: column,
              rect: Rect.fromLTWH(
                column.centerX - cardWidth / 2,
                top,
                cardWidth,
                cardHeight,
              ),
            ),
          );
        }
      }
    }
    return placements;
  }

  /// Builds all drawable flow relation placements.
  static List<TaskStreamLinkPlacement> _buildLinkPlacements({
    required List<TaskStreamLink> links,
    required List<TaskStreamCardPlacement> placements,
  }) {
    final placementByTask = <String, TaskStreamCardPlacement>{
      for (final placement in placements) placement.card.taskId: placement,
    };
    final linkPlacements = <TaskStreamLinkPlacement>[];
    for (final link in links) {
      final placement = _linkPlacement(link, placementByTask);
      if (placement != null) {
        linkPlacements.add(placement);
      }
    }
    return linkPlacements;
  }

  /// Builds one flow placement when both linked cards are visible.
  static TaskStreamLinkPlacement? _linkPlacement(
    TaskStreamLink link,
    Map<String, TaskStreamCardPlacement> placementByTask,
  ) {
    final from = placementByTask[link.fromTaskId];
    final to = placementByTask[link.toTaskId];
    if (from == null || to == null || from.card.taskId == to.card.taskId) {
      return null;
    }
    return TaskStreamLinkPlacement(link: link, from: from, to: to);
  }

  /// Returns the focus target nearest a tap on the painted stream surface.
  TaskStreamFocus? focusAt(Offset position) {
    final link = _nearestLink(position);
    if (link != null) {
      return TaskStreamFocus.link(link.link);
    }
    final row = _nearestRow(position);
    if (row != null) {
      return TaskStreamFocus(rowId: row.id);
    }
    return null;
  }

  /// Returns whether a card belongs to the current focus target.
  bool isFocusedCard(TaskStreamCardPlacement placement, TaskStreamFocus focus) {
    if (focus.isEmpty) {
      return false;
    }
    if (focus.hasTaskId(placement.card.taskId)) {
      return true;
    }
    if (focus.hasRowId(placement.row.id)) {
      return true;
    }
    for (final link in links) {
      if (_isFocusedLink(link, focus) &&
          (link.from.card.taskId == placement.card.taskId ||
              link.to.card.taskId == placement.card.taskId)) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether a relation curve belongs to the current focus target.
  bool isFocusedLink(TaskStreamLinkPlacement link, TaskStreamFocus focus) {
    return _isFocusedLink(link, focus);
  }

  /// Returns the nearest relation curve when a tap is close enough.
  TaskStreamLinkPlacement? _nearestLink(Offset position) {
    TaskStreamLinkPlacement? nearest;
    var nearestDistance = double.infinity;
    for (final link in links) {
      final distance = _distanceToLink(position, link);
      if (distance < nearestDistance) {
        nearest = link;
        nearestDistance = distance;
      }
    }
    if (nearestDistance <= _linkHitSlop) {
      return nearest;
    }
    return null;
  }

  /// Returns the row ribbon under a tap position.
  TaskStreamRowLayout? _nearestRow(Offset position) {
    for (final row in rows) {
      final withinRow =
          position.dy >= row.top && position.dy <= row.top + row.height;
      final nearRibbon = (position.dy - row.centerY).abs() <= 20;
      final withinStream = position.dx >= 0 && position.dx <= endX;
      if (withinRow && nearRibbon && withinStream) {
        return row;
      }
    }
    return null;
  }

  /// Returns the shortest distance from a point to a sampled link curve.
  double _distanceToLink(Offset position, TaskStreamLinkPlacement link) {
    var previous = _linkStart(link);
    var nearest = double.infinity;
    for (var index = 1; index <= _linkHitSamples; index++) {
      final t = index / _linkHitSamples;
      final current = _linkPoint(link, t);
      nearest = math.min(
        nearest,
        _distanceToSegment(position, previous, current),
      );
      previous = current;
    }
    return nearest;
  }

  /// Returns the shortest distance from a point to a line segment.
  double _distanceToSegment(Offset point, Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) {
      return (point - start).distance;
    }
    final rawT =
        ((point.dx - start.dx) * dx + (point.dy - start.dy) * dy) /
        lengthSquared;
    final t = rawT.clamp(0.0, 1.0);
    final projection = Offset(start.dx + dx * t, start.dy + dy * t);
    return (point - projection).distance;
  }

  /// Returns focused links before they are assigned drawable placements.
  static List<TaskStreamLink> _focusedStreamLinks(
    List<TaskStreamLink> links,
    TaskStreamFocus focus,
  ) {
    return <TaskStreamLink>[
      for (final link in links)
        if (_isFocusedRawLink(link, focus)) link,
    ];
  }

  /// Returns lanes containing only cards in the focused graph neighborhood.
  static List<TaskStreamLane> _focusedStreamLanes(
    List<TaskStreamLane> lanes,
    List<TaskStreamLink> links,
    TaskStreamFocus focus,
    Map<String, TaskStreamAxisBucket> rowBucketsByTaskId,
  ) {
    final taskIds = _focusedTaskIds(lanes, links, focus, rowBucketsByTaskId);
    if (taskIds.isEmpty) {
      return lanes;
    }
    return <TaskStreamLane>[
      for (final lane in lanes)
        TaskStreamLane(
          id: lane.id,
          title: lane.title,
          subtitle: lane.subtitle,
          cards: <TaskStreamCard>[
            for (final card in lane.cards)
              if (taskIds.contains(card.taskId)) card,
          ],
        ),
    ];
  }

  /// Returns task ids belonging to a compact focus target.
  static Set<String> _focusedTaskIds(
    List<TaskStreamLane> lanes,
    List<TaskStreamLink> links,
    TaskStreamFocus focus,
    Map<String, TaskStreamAxisBucket> rowBucketsByTaskId,
  ) {
    final ids = <String>{};
    ids.addAll(focus.effectiveTaskIds());
    for (final link in links) {
      if (_isFocusedRawLink(link, focus)) {
        ids.add(link.fromTaskId);
        ids.add(link.toTaskId);
      }
    }
    final rowIds = focus.effectiveRowIds();
    if (rowIds.isNotEmpty) {
      for (final lane in lanes) {
        for (final card in lane.cards) {
          if (rowIds.contains(_rowBucket(card, rowBucketsByTaskId).id)) {
            ids.add(card.taskId);
          }
        }
      }
    }
    return ids;
  }
}

/// Returns the selected row bucket for a task card.
TaskStreamAxisBucket _rowBucket(
  TaskStreamCard card,
  Map<String, TaskStreamAxisBucket> rowBucketsByTaskId,
) {
  return rowBucketsByTaskId[card.taskId] ??
      TaskStreamAxisProjector.fallbackRowBucket(card);
}

/// Returns whether a raw link belongs to the active focus.
bool _isFocusedRawLink(TaskStreamLink link, TaskStreamFocus focus) {
  if (focus.isEmpty) {
    return false;
  }
  if (focus.hasStreamId(link.streamId)) {
    return true;
  }
  if (focus.hasTaskId(link.fromTaskId) || focus.hasTaskId(link.toTaskId)) {
    return true;
  }
  return false;
}

/// Returns whether a link should stay prominent for the active focus.
bool _isFocusedLink(TaskStreamLinkPlacement link, TaskStreamFocus focus) {
  if (focus.isEmpty) {
    return false;
  }
  if (focus.hasStreamId(link.link.streamId)) {
    return true;
  }
  if (focus.hasRowId(link.from.row.id) || focus.hasRowId(link.to.row.id)) {
    return true;
  }
  if (focus.hasTaskId(link.from.card.taskId) ||
      focus.hasTaskId(link.to.card.taskId)) {
    return true;
  }
  return false;
}

/// Returns the visible start point for a cross-row link.
Offset _linkStart(TaskStreamLinkPlacement link) {
  if (link.to.rect.center.dx >= link.from.rect.center.dx) {
    return Offset(link.from.rect.right - 2, link.from.rect.center.dy);
  }
  return Offset(link.from.rect.left + 2, link.from.rect.center.dy);
}

/// Returns the visible end point for a cross-row link.
Offset _linkEnd(TaskStreamLinkPlacement link) {
  if (link.to.rect.center.dx >= link.from.rect.center.dx) {
    return Offset(link.to.rect.left + 2, link.to.rect.center.dy);
  }
  return Offset(link.to.rect.right - 2, link.to.rect.center.dy);
}

/// Returns a sampled point along the rendered cubic link curve.
Offset _linkPoint(TaskStreamLinkPlacement link, double t) {
  final start = _linkStart(link);
  final end = _linkEnd(link);
  final horizontalGap = (end.dx - start.dx).abs();
  final controlOffset = math.max(58.0, horizontalGap * 0.42);
  final verticalLift = (end.dy - start.dy).sign * 14;
  final controlA = Offset(start.dx + controlOffset, start.dy + verticalLift);
  final controlB = Offset(end.dx - controlOffset, end.dy - verticalLift);
  final inverse = 1 - t;
  return Offset(
    inverse * inverse * inverse * start.dx +
        3 * inverse * inverse * t * controlA.dx +
        3 * inverse * t * t * controlB.dx +
        t * t * t * end.dx,
    inverse * inverse * inverse * start.dy +
        3 * inverse * inverse * t * controlA.dy +
        3 * inverse * t * t * controlB.dy +
        t * t * t * end.dy,
  );
}

/// TaskStreamColumnLayout stores one timeline column's geometry.
class TaskStreamColumnLayout {
  /// Creates timeline column geometry.
  const TaskStreamColumnLayout({
    required this.laneId,
    required this.title,
    required this.subtitle,
    required this.left,
    required this.width,
  });

  /// Source backend lane id.
  final String laneId;

  /// Column title.
  final String title;

  /// Column subtitle.
  final String subtitle;

  /// Left x-coordinate.
  final double left;

  /// Column width.
  final double width;

  /// Column center x-coordinate.
  double get centerX => left + width / 2;
}

/// TaskStreamRowLayout stores one colored stream row's geometry.
class TaskStreamRowLayout {
  /// Creates stream row geometry.
  const TaskStreamRowLayout({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.top,
    required this.height,
    required this.centerY,
  });

  /// Stable row id.
  final String id;

  /// Row title.
  final String title;

  /// Row subtitle.
  final String subtitle;

  /// Stream color.
  final Color color;

  /// Row icon.
  final IconData icon;

  /// Top y-coordinate.
  final double top;

  /// Row height.
  final double height;

  /// Center y-coordinate.
  final double centerY;

  /// Returns a copy with computed geometry.
  TaskStreamRowLayout copyWith({double? top, double? height, double? centerY}) {
    return TaskStreamRowLayout(
      id: id,
      title: title,
      subtitle: subtitle,
      color: color,
      icon: icon,
      top: top ?? this.top,
      height: height ?? this.height,
      centerY: centerY ?? this.centerY,
    );
  }
}

/// TaskStreamCardPlacement stores one positioned stream card.
class TaskStreamCardPlacement {
  /// Creates a task card placement.
  const TaskStreamCardPlacement({
    required this.card,
    required this.row,
    required this.column,
    required this.rect,
  });

  /// Projected task card.
  final TaskStreamCard card;

  /// Parent stream row.
  final TaskStreamRowLayout row;

  /// Parent timeline column.
  final TaskStreamColumnLayout column;

  /// Card rectangle.
  final Rect rect;
}

/// TaskStreamLinkPlacement stores geometry for one visible stream relation.
class TaskStreamLinkPlacement {
  /// Creates a cross-row relation placement.
  const TaskStreamLinkPlacement({
    required this.link,
    required this.from,
    required this.to,
  });

  /// Backend stream relation.
  final TaskStreamLink link;

  /// Source card placement.
  final TaskStreamCardPlacement from;

  /// Target card placement.
  final TaskStreamCardPlacement to;
}

/// TaskStreamCanvasPainter paints stream bands and timeline guides.
class TaskStreamCanvasPainter extends CustomPainter {
  /// Creates the stream canvas painter.
  const TaskStreamCanvasPainter({
    required this.layout,
    required this.colors,
    this.focus,
  });

  /// Computed stream layout.
  final TaskStreamCanvasLayout layout;

  /// Active app palette for canvas guide colors.
  final AgentAwesomePalette colors;

  /// Optional focus target used to fade unrelated stream content.
  final TaskStreamFocus? focus;

  /// Paints columns, stream ribbons, and continuation hints.
  @override
  void paint(Canvas canvas, Size size) {
    _paintColumnGuides(canvas);
    _paintRowBands(canvas);
    _paintStreams(canvas);
    _paintCrossLinks(canvas);
  }

  /// Paints vertical timeline dividers.
  void _paintColumnGuides(Canvas canvas) {
    final paint = Paint()
      ..color = colors.border.withValues(alpha: 0.56)
      ..strokeWidth = 1;
    for (final column in layout.columns) {
      canvas.drawLine(
        Offset(column.left, 0),
        Offset(column.left, layout.size.height),
        paint,
      );
    }
  }

  /// Paints subtle background bands for each stream row.
  void _paintRowBands(Canvas canvas) {
    for (final row in layout.rows) {
      final paint = Paint()
        ..color = row.color.withValues(alpha: 0.035)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(0, row.top + 8, layout.size.width, row.height - 16),
        paint,
      );
    }
  }

  /// Paints the horizontal row ribbons.
  void _paintStreams(Canvas canvas) {
    for (var index = 0; index < layout.rows.length; index++) {
      final row = layout.rows[index];
      final startX = 0.0;
      final solidEndX = _lastPlacementX(row);
      final focused = _isFocusedRow(row);
      final ribbonPaint = Paint()
        ..color = row.color.withValues(alpha: _focusedAlpha(0.12, focused))
        ..style = PaintingStyle.stroke
        ..strokeWidth = focused ? 7 : 6
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(startX, row.centerY);
      var currentX = startX;
      for (final column in layout.columns) {
        final nextX = math.min(column.centerX, solidEndX);
        if (nextX <= currentX) {
          continue;
        }
        final lift = (index.isEven ? -1 : 1) * 12;
        path.cubicTo(
          currentX + (nextX - currentX) * 0.45,
          row.centerY,
          currentX + (nextX - currentX) * 0.55,
          row.centerY + lift,
          nextX,
          row.centerY,
        );
        currentX = nextX;
        if (currentX >= solidEndX) {
          break;
        }
      }
      canvas.drawPath(path, ribbonPaint);
      _drawDashedLine(
        canvas,
        Offset(solidEndX + 20, row.centerY),
        Offset(layout.endX - 18, row.centerY),
        row.color.withValues(alpha: _focusedAlpha(0.18, focused)),
      );
    }
  }

  /// Paints relation curves that branch and converge across stream rows.
  void _paintCrossLinks(Canvas canvas) {
    for (final link in layout.links) {
      final active = _isFocusedLinkPlacement(link);
      final start = _linkStart(link);
      final end = _linkEnd(link);
      final color = _linkColor(link);
      final paint = Paint()
        ..color = color.withValues(
          alpha: _focusedAlpha(_linkAlpha(link), active),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? _linkWidth(link) + 1.5 : _linkWidth(link)
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(start.dx, start.dy);
      final horizontalGap = (end.dx - start.dx).abs();
      final controlOffset = math.max(58.0, horizontalGap * 0.42);
      final verticalLift = (end.dy - start.dy).sign * 14;
      path.cubicTo(
        start.dx + controlOffset,
        start.dy + verticalLift,
        end.dx - controlOffset,
        end.dy - verticalLift,
        end.dx,
        end.dy,
      );
      canvas.drawPath(path, paint);
      canvas.drawCircle(
        end,
        (active ? _linkWidth(link) + 2.5 : _linkWidth(link) + 1),
        Paint()..color = color.withValues(alpha: _focusedAlpha(0.52, active)),
      );
    }
  }

  /// Returns the semantic color for one relation curve.
  Color _linkColor(TaskStreamLinkPlacement link) {
    if (link.link.transitionType == 'blocks') {
      return colors.coral;
    }
    if (link.link.streamId.isNotEmpty) {
      return _streamRouteColor(link.link.streamId, link.from.row.color);
    }
    return Color.lerp(link.from.row.color, link.to.row.color, 0.48) ??
        link.from.row.color;
  }

  /// Returns the opacity for one relation curve.
  double _linkAlpha(TaskStreamLinkPlacement link) {
    if (link.link.transitionType == 'blocks') {
      return 0.56;
    }
    if (link.link.transitionType == 'batch_with') {
      return 0.34;
    }
    return 0.46 + (link.link.confidence.clamp(0, 1) * 0.18);
  }

  /// Returns the stroke width for one relation curve.
  double _linkWidth(TaskStreamLinkPlacement link) {
    if (link.link.transitionType == 'blocks') {
      return 8.0;
    }
    if (link.link.transitionType == 'batch_with') {
      return 5.5;
    }
    return 6.0 + (link.link.confidence.clamp(0, 1) * 2.0);
  }

  /// Returns whether a row belongs to the active focus.
  bool _isFocusedRow(TaskStreamRowLayout row) {
    final target = focus;
    if (target == null || target.isEmpty) {
      return true;
    }
    if (target.effectiveRowIds().isNotEmpty) {
      return target.hasRowId(row.id);
    }
    return layout.placements.any((placement) {
      return placement.row.id == row.id &&
          layout.isFocusedCard(placement, target);
    });
  }

  /// Returns whether a link belongs to the active focus.
  bool _isFocusedLinkPlacement(TaskStreamLinkPlacement link) {
    final target = focus;
    if (target == null || target.isEmpty) {
      return true;
    }
    return layout.isFocusedLink(link, target);
  }

  /// Returns the dimmed or normal alpha for a painted element.
  double _focusedAlpha(double normal, bool active) {
    final target = focus;
    if (target == null || target.isEmpty || active) {
      return normal;
    }
    return math.min(normal, 0.055);
  }

  /// Returns the right edge of the final card in a row.
  double _lastPlacementX(TaskStreamRowLayout row) {
    final rowPlacements = layout.placements.where(
      (placement) => placement.row.id == row.id,
    );
    if (rowPlacements.isEmpty) {
      return 0;
    }
    return rowPlacements
        .map((placement) => placement.rect.right)
        .reduce(math.max);
  }

  /// Paints a dashed continuation line beyond scheduled cards.
  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Color color) {
    if (end.dx <= start.dx) {
      return;
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    var x = start.dx;
    while (x < end.dx) {
      final nextX = math.min(x + 10, end.dx);
      canvas.drawLine(Offset(x, start.dy), Offset(nextX, end.dy), paint);
      x += 18;
    }
  }

  /// Reports whether this painter needs repainting.
  @override
  bool shouldRepaint(covariant TaskStreamCanvasPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.colors != colors ||
        oldDelegate.focus != focus;
  }
}

/// _StreamRowLabel renders the sticky label for one stream row.
class _StreamRowLabel extends StatelessWidget {
  const _StreamRowLabel({required this.row});

  final TaskStreamRowLayout row;

  /// Builds the label and icon for one stream row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final tooltip = row.subtitle.isEmpty
        ? row.title
        : '${row.title}\n${row.subtitle}';
    return Tooltip(
      message: tooltip,
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: row.color.withValues(alpha: 0.14),
            child: Icon(row.icon, size: 17, color: row.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (row.subtitle.isNotEmpty)
                  Text(
                    row.subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// _StreamColumnHeader renders one sticky timeline heading.
class _StreamColumnHeader extends StatelessWidget {
  const _StreamColumnHeader({required this.column});

  final TaskStreamColumnLayout column;

  /// Builds a timeline column heading.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          column.title.toUpperCase(),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.subtle,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
          ),
        ),
        if (column.subtitle.isNotEmpty)
          Text(
            column.subtitle,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
      ],
    );
  }
}

/// _StreamFocusControls renders contextual focus navigation actions.
class _StreamFocusControls extends StatelessWidget {
  const _StreamFocusControls({
    required this.compact,
    required this.onToggleCompact,
    required this.onClear,
  });

  /// Whether compact focus geometry is active.
  final bool compact;

  /// Callback to toggle compact focus geometry.
  final VoidCallback onToggleCompact;

  /// Callback to clear the current focus.
  final VoidCallback onClear;

  /// Builds a small canvas-local toolbar for focused stream inspection.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.94),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
        boxShadow: <BoxShadow>[
          BoxShadow(
            blurRadius: 16,
            offset: const Offset(0, 6),
            color: colors.shadow,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _StreamFocusButton(
              icon: Icons.compress,
              tooltip: compact ? 'Use full spacing' : 'Compact focus',
              selected: compact,
              onPressed: onToggleCompact,
            ),
            _StreamFocusButton(
              icon: Icons.close,
              tooltip: 'Clear focus',
              selected: false,
              onPressed: onClear,
            ),
          ],
        ),
      ),
    );
  }
}

/// _StreamFocusButton renders one icon-only focus toolbar action.
class _StreamFocusButton extends StatelessWidget {
  const _StreamFocusButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  /// Icon shown in the action button.
  final IconData icon;

  /// Tooltip text for the icon-only action.
  final String tooltip;

  /// Whether the action represents an active toggle.
  final bool selected;

  /// Callback fired when the action is pressed.
  final VoidCallback onPressed;

  /// Builds one compact icon action.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? colors.greenSoft : Colors.transparent,
            border: Border.all(
              color: selected ? colors.green : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 17,
            color: selected ? colors.green : colors.ink,
          ),
        ),
      ),
    );
  }
}

/// _StreamTaskCard renders one interactive task node.
class _StreamTaskCard extends StatelessWidget {
  const _StreamTaskCard({
    required this.placement,
    required this.selected,
    required this.focused,
    required this.faded,
    required this.compact,
    required this.onTap,
  });

  final TaskStreamCardPlacement placement;
  final bool selected;
  final bool focused;
  final bool faded;
  final bool compact;
  final VoidCallback onTap;

  /// Builds one selectable task card over the painted stream.
  @override
  Widget build(BuildContext context) {
    final card = placement.card;
    final row = placement.row;
    final colors = context.agentAwesomeColors;
    final emphasized = selected || focused;
    final borderColor = emphasized ? colors.borderStrong : row.color;
    return Tooltip(
      message: card.explanation,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: faded ? 0.24 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: emphasized ? colors.panelStrong : colors.surface,
              gradient: context.agentAwesomeCardGradient,
              border: Border.all(color: borderColor, width: emphasized ? 2 : 1),
              borderRadius: BorderRadius.circular(8),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  blurRadius: emphasized ? 16 : 12,
                  offset: const Offset(0, 4),
                  color: row.color.withValues(alpha: emphasized ? 0.16 : 0.1),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                Icon(_cardIcon(card), color: row.color, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        card.title,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _cardSubtitle(card),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (card.priority == 'urgent') ...<Widget>[
                  const SizedBox(width: 6),
                  const _StreamUrgentDot(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// _StreamContinuationButton renders a future-work endpoint.
class _StreamContinuationButton extends StatelessWidget {
  const _StreamContinuationButton({required this.row});

  final TaskStreamRowLayout row;

  /// Builds the continuation endpoint at the end of one stream.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: row.color.withValues(alpha: 0.88),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.add, color: Colors.white, size: 18),
    );
  }
}

/// _StreamUrgentDot renders the compact priority marker.
class _StreamUrgentDot extends StatelessWidget {
  const _StreamUrgentDot();

  /// Builds a small urgency indicator.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.agentAwesomeColors.coral,
        shape: BoxShape.circle,
      ),
      child: const SizedBox.square(dimension: 8),
    );
  }
}

/// Returns a stable route color for one stream id.
Color _streamRouteColor(String streamId, Color fallback) {
  const palette = <Color>[
    Color(0xff5f94c9),
    Color(0xff6f9b62),
    Color(0xffd7a246),
    Color(0xff9177c0),
    Color(0xffd8798c),
    Color(0xff7a9a91),
    Color(0xffc1844f),
  ];
  var hash = 0;
  for (final unit in streamId.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  if (hash == 0) {
    return fallback;
  }
  return palette[hash % palette.length];
}

/// Returns the leading icon for a task card.
IconData _cardIcon(TaskStreamCard card) {
  final priority = card.priority.trim().toLowerCase();
  if (priority == 'urgent' || priority == 'high') {
    return Icons.flag_outlined;
  }
  if (card.dueAt != null) {
    return Icons.event_available_outlined;
  }
  return Icons.task_alt_outlined;
}

/// Returns compact metadata text for a task card.
String _cardSubtitle(TaskStreamCard card) {
  final parts = <String>[
    if (card.context.isNotEmpty) taskStreamDisplayLabel(card.context),
    if (card.owner.isNotEmpty) taskStreamDisplayLabel(card.owner),
    if (card.estimateMinutes > 0) '${card.estimateMinutes}m',
    if (card.dueAt != null) 'Due ${_cardDate(card.dueAt!)}',
    if (card.dueAt == null && card.scheduledAt != null)
      'Scheduled ${_cardDate(card.scheduledAt!)}',
    if (card.spendLabel.isNotEmpty) card.spendLabel,
  ];
  if (parts.isEmpty) {
    return taskStreamDisplayLabel(card.priority);
  }
  return parts.join(' · ');
}

/// Formats a task card date as a compact local ISO day.
String _cardDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_cardTwoDigits(local.month)}-${_cardTwoDigits(local.day)}';
}

/// Formats one date component with two digits.
String _cardTwoDigits(int value) {
  return value.toString().padLeft(2, '0');
}
