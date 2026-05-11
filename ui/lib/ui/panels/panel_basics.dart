/// Basic panel layout data and collapse controls.
part of 'panels.dart';

class PanelSplit {
  /// Creates split ratio constraints for a two-panel workspace.
  const PanelSplit({required this.left, this.min = 0.2, this.max = 0.8});

  /// Initial fraction assigned to the left panel.
  final double left;

  /// Minimum allowed left panel fraction while dragging.
  final double min;

  /// Maximum allowed left panel fraction while dragging.
  final double max;
}

/// SectionLayout describes one two-panel app section composition.
class SectionLayout {
  /// Creates a section layout with reusable panels.
  const SectionLayout({
    required this.split,
    required this.left,
    required this.right,
    this.third,
    this.outerSplit = const PanelSplit(left: 0.72, min: 0.5, max: 0.86),
  });

  /// Split ratio configuration.
  final PanelSplit split;

  /// Left panel widget.
  final Widget left;

  /// Right panel widget.
  final Widget right;

  /// Optional third panel shown to the right of the two-panel workspace.
  final Widget? third;

  /// Split ratio between the two-panel workspace and optional third panel.
  final PanelSplit outerSplit;
}

/// PanelCollapseDirection identifies which edge a panel collapses toward.
enum PanelCollapseDirection {
  /// Collapse toward the left edge.
  left,

  /// Collapse toward the right edge.
  right,
}

/// PanelCollapseButton renders the shared sidebar and command-panel toggle.
class PanelCollapseButton extends StatelessWidget {
  /// Creates a compact collapse or expand button.
  const PanelCollapseButton({
    super.key,
    required this.expanded,
    required this.onPressed,
    this.direction = PanelCollapseDirection.left,
    this.expandedTooltip = 'Collapse panel',
    this.collapsedTooltip = 'Expand panel',
  });

  /// Whether the controlled surface is currently expanded.
  final bool expanded;

  /// Collapse or expand callback.
  final VoidCallback onPressed;

  /// Edge the surface collapses toward.
  final PanelCollapseDirection direction;

  /// Tooltip shown while the surface is expanded.
  final String expandedTooltip;

  /// Tooltip shown while the surface is collapsed.
  final String collapsedTooltip;

  /// Builds the shared icon-only collapse affordance.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: expanded ? expandedTooltip : collapsedTooltip,
      child: IconButton(
        alignment: Alignment.topCenter,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        onPressed: onPressed,
        icon: Icon(_icon, color: colors.muted, size: 20),
      ),
    );
  }

  IconData get _icon {
    if (!expanded) {
      return Icons.menu;
    }
    return switch (direction) {
      PanelCollapseDirection.left => Icons.keyboard_double_arrow_left,
      PanelCollapseDirection.right => Icons.keyboard_double_arrow_right,
    };
  }
}
