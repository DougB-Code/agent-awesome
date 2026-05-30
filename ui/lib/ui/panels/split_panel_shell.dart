/// Resizable split-panel shell widgets.
part of 'panels.dart';

enum SplitPaneSide {
  /// Left split pane.
  left,

  /// Right split pane.
  right;

  /// Direction used by the shared collapse affordance.
  PanelCollapseDirection get direction {
    return switch (this) {
      SplitPaneSide.left => PanelCollapseDirection.left,
      SplitPaneSide.right => PanelCollapseDirection.right,
    };
  }
}

/// SplitPaneCollapseScope exposes split-pane collapse state to child panels.
class SplitPaneCollapseScope extends InheritedWidget {
  /// Creates inherited collapse state for a split pane.
  const SplitPaneCollapseScope({
    super.key,
    required this.side,
    required this.collapsed,
    required this.onToggle,
    required super.child,
  });

  /// Side of the split shell that owns the child subtree.
  final SplitPaneSide side;

  /// Whether this pane is currently collapsed.
  final bool collapsed;

  /// Toggles collapsed state for this pane.
  final VoidCallback onToggle;

  /// Returns the closest split-pane collapse state, if present.
  static SplitPaneCollapseScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SplitPaneCollapseScope>();
  }

  /// Reports whether descendants should rebuild after collapse state changes.
  @override
  bool updateShouldNotify(covariant SplitPaneCollapseScope oldWidget) {
    return side != oldWidget.side ||
        collapsed != oldWidget.collapsed ||
        onToggle != oldWidget.onToggle;
  }
}

/// SplitPanelShell renders a reusable resizable two-panel workspace.
class SplitPanelShell extends StatefulWidget {
  /// Creates a two-panel workspace shell.
  const SplitPanelShell({
    super.key,
    required this.left,
    required this.right,
    this.split = const PanelSplit(left: 0.5),
    this.gutterWidth = 0,
    this.stackBelowWidth = 940,
  });

  /// Left panel widget.
  final Widget left;

  /// Right panel widget.
  final Widget right;

  /// Split ratio configuration.
  final PanelSplit split;

  /// Horizontal space reserved between panes while preserving the drag handle.
  final double gutterWidth;

  /// Width below which panes stack vertically.
  final double stackBelowWidth;

  @override
  State<SplitPanelShell> createState() => _SplitPanelShellState();
}

class _SplitPanelShellState extends State<SplitPanelShell> {
  static const double _collapsedPaneWidth = 72;
  static const double _handleHitWidth = 12;

  late double _leftPaneFraction = widget.split.left;
  bool _leftPaneCollapsed = false;
  bool _rightPaneCollapsed = false;

  /// Updates the initial split when switching section layouts.
  @override
  void didUpdateWidget(covariant SplitPanelShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sectionChanged =
        oldWidget.left.runtimeType != widget.left.runtimeType ||
        oldWidget.right.runtimeType != widget.right.runtimeType;
    if (oldWidget.split.left != widget.split.left || sectionChanged) {
      _leftPaneFraction = widget.split.left;
      _leftPaneCollapsed = false;
      _rightPaneCollapsed = false;
    }
  }

  /// Builds the split shell and drag handle.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < widget.stackBelowWidth) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(height: constraints.maxHeight, child: widget.left),
                SizedBox(height: constraints.maxHeight, child: widget.right),
              ],
            ),
          );
        }
        final totalWidth = constraints.maxWidth;
        final gutterWidth = widget.gutterWidth
            .clamp(0.0, totalWidth)
            .toDouble();
        final paneWidth = totalWidth - gutterWidth;
        final leftWidth = _leftPaneCollapsed
            ? _collapsedPaneWidth
            : _rightPaneCollapsed
            ? paneWidth - _collapsedPaneWidth
            : paneWidth * _leftPaneFraction;
        final rightWidth = paneWidth - leftWidth;
        final canResize = !_leftPaneCollapsed && !_rightPaneCollapsed;
        return Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: leftWidth,
              child: SplitPaneCollapseScope(
                side: SplitPaneSide.left,
                collapsed: _leftPaneCollapsed,
                onToggle: _toggleLeftPane,
                child: widget.left,
              ),
            ),
            Positioned(
              left: leftWidth + gutterWidth,
              top: 0,
              bottom: 0,
              width: rightWidth,
              child: SplitPaneCollapseScope(
                side: SplitPaneSide.right,
                collapsed: _rightPaneCollapsed,
                onToggle: _toggleRightPane,
                child: widget.right,
              ),
            ),
            Positioned(
              left: leftWidth + ((gutterWidth - _handleHitWidth) / 2),
              top: 0,
              bottom: 0,
              width: _handleHitWidth,
              child: canResize
                  ? _SplitPanelHandle(
                      onDragUpdate: (details) =>
                          _resizePanes(details, paneWidth),
                    )
                  : const _SplitPanelDivider(),
            ),
          ],
        );
      },
    );
  }

  /// Resizes both panes from horizontal drag movement.
  void _resizePanes(DragUpdateDetails details, double paneWidth) {
    if (paneWidth <= 0) {
      return;
    }
    setState(() {
      _leftPaneFraction =
          ((_leftPaneFraction * paneWidth + details.delta.dx) / paneWidth)
              .clamp(widget.split.min, widget.split.max);
    });
  }

  /// Toggles the left pane collapsed state.
  void _toggleLeftPane() {
    setState(() {
      _leftPaneCollapsed = !_leftPaneCollapsed;
      if (_leftPaneCollapsed) {
        _rightPaneCollapsed = false;
      }
    });
  }

  /// Toggles the right pane collapsed state.
  void _toggleRightPane() {
    setState(() {
      _rightPaneCollapsed = !_rightPaneCollapsed;
      if (_rightPaneCollapsed) {
        _leftPaneCollapsed = false;
      }
    });
  }
}

/// _SplitPanelDivider preserves split hit layout when resize is disabled.
class _SplitPanelDivider extends StatelessWidget {
  const _SplitPanelDivider();

  /// Builds the fixed divider shown next to a collapsed pane.
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

/// _SplitPanelHandle renders the hover-only drag affordance.
class _SplitPanelHandle extends StatefulWidget {
  const _SplitPanelHandle({required this.onDragUpdate});

  final GestureDragUpdateCallback onDragUpdate;

  @override
  State<_SplitPanelHandle> createState() => _SplitPanelHandleState();
}

/// _SplitPanelHandleState tracks hover and drag activity for the handle.
class _SplitPanelHandleState extends State<_SplitPanelHandle> {
  bool _active = false;

  /// Builds the draggable divider for split panel panes.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => _setActive(true),
      onExit: (_) => _setActive(false),
      child: GestureDetector(
        key: const ValueKey<String>('command-split-handle'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _setActive(true),
        onHorizontalDragUpdate: widget.onDragUpdate,
        onHorizontalDragEnd: (_) => _setActive(false),
        onHorizontalDragCancel: () => _setActive(false),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: _active ? 4 : 0,
              decoration: BoxDecoration(
                color: colors.green,
                gradient: context.agentAwesomePrimaryGradient,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Stores whether the handle should display the highlighted divider.
  void _setActive(bool value) {
    if (_active == value) {
      return;
    }
    setState(() {
      _active = value;
    });
  }
}
