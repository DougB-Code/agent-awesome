/// Shared panel surface widgets for command and detail panes.
part of 'panels.dart';

/// PanelSurfaceStyle selects the visual treatment for a panel surface.
enum PanelSurfaceStyle {
  /// Primary command-pane frame used for top-level panel columns.
  primary,

  /// Repeated content card used inside command-pane bodies.
  card,
}

/// PanelSurface renders the single shared bordered panel decoration.
class PanelSurface extends StatelessWidget {
  /// Creates a reusable panel surface.
  const PanelSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.style = PanelSurfaceStyle.primary,
    this.selected = false,
    this.showBorder = true,
    this.fillWidth = false,
    this.clipBehavior = Clip.none,
  });

  /// Surface content.
  final Widget child;

  /// Inner spacing applied before painting the child.
  final EdgeInsetsGeometry padding;

  /// Visual role for the surface.
  final PanelSurfaceStyle style;

  /// Whether the surface represents an active selection.
  final bool selected;

  /// Whether the surface should paint its outer border.
  final bool showBorder;

  /// Whether the surface should expand horizontally.
  final bool fillWidth;

  /// Clip behavior for rounded pane contents.
  final Clip clipBehavior;

  /// Builds a shared bordered panel surface.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      width: fillWidth ? double.infinity : null,
      padding: padding,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: selected ? colors.greenSoft : colors.surface,
        gradient: _gradient(context),
        border: showBorder
            ? Border.all(color: selected ? colors.green : colors.border)
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  /// Returns the theme gradient for this panel style.
  LinearGradient? _gradient(BuildContext context) {
    if (selected) {
      return context.agentAwesomeSelectedGradient;
    }
    return switch (style) {
      PanelSurfaceStyle.primary => context.agentAwesomeSurfaceGradient,
      PanelSurfaceStyle.card => context.agentAwesomeCardGradient,
    };
  }
}

/// PanelBodySurface paints a shared background behind pane body content.
class PanelBodySurface extends StatelessWidget {
  /// Creates a reusable panel body background.
  const PanelBodySurface({super.key, required this.child});

  /// Body content shown above the shared background.
  final Widget child;

  /// Builds a pane body background without adding a nested border.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeSurfaceGradient,
      ),
      child: child,
    );
  }
}
