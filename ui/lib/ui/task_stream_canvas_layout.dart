/// Geometry model and layout builder for the task stream canvas.
part of 'task_stream_canvas.dart';

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
