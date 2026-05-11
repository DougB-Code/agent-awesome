/// Painter for task stream rows, ribbons, and relation curves.
part of 'task_stream_canvas.dart';

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
