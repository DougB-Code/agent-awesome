/// Stateful task stream canvas shell and scroll synchronization.
part of 'task_stream_canvas.dart';

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
                              left: layout.endX - 7,
                              top: row.centerY - 7,
                              width: 14,
                              height: 14,
                              child: _StreamContinuationMarker(row: row),
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
