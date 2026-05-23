/// Shared panel surface widgets for command and detail panes.
part of 'panels.dart';

/// PanelSurfaceStyle selects the visual treatment for a panel surface.
enum PanelSurfaceStyle {
  /// Primary command-pane frame used for top-level panel columns.
  primary,

  /// Repeated content card used inside command-pane bodies.
  card,
}

/// PanelStyleTokens stores shared dimensions for quiet panel chrome.
class PanelStyleTokens {
  /// Prevents construction because this type only exposes constants.
  const PanelStyleTokens._();

  /// Square radius used by command-panel frames.
  static const double panelRadius = 0;

  /// Standard radius used by cards, controls, and sections.
  static const double radius = 8;

  /// Compact radius for low-emphasis badges and toolbar pills.
  static const double compactRadius = 6;

  /// Standard square icon button size for shell and panel actions.
  static const double iconButtonSize = 36;

  /// Standard icon size for shell and panel action buttons.
  static const double iconButtonIconSize = 18;
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
    this.borderRadius,
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

  /// Optional border radius override for specialized shared surfaces.
  final BorderRadiusGeometry? borderRadius;

  /// Builds a shared bordered panel surface.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      width: fillWidth ? double.infinity : null,
      padding: padding,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: selected ? colors.greenSoft : _fillColor(colors),
        gradient: _gradient(context),
        border: showBorder
            ? Border.all(color: selected ? colors.borderStrong : colors.border)
            : null,
        borderRadius: borderRadius ?? _defaultBorderRadius(),
      ),
      child: child,
    );
  }

  /// Returns the default radius for the surface role.
  BorderRadiusGeometry _defaultBorderRadius() {
    return switch (style) {
      PanelSurfaceStyle.primary => BorderRadius.circular(
        PanelStyleTokens.panelRadius,
      ),
      PanelSurfaceStyle.card => BorderRadius.circular(PanelStyleTokens.radius),
    };
  }

  /// Returns the flat fill color for the panel role.
  Color _fillColor(AgentAwesomePalette colors) {
    return switch (style) {
      PanelSurfaceStyle.primary => colors.surface,
      PanelSurfaceStyle.card => colors.surface,
    };
  }

  /// Returns the selected gradient only when it clarifies active state.
  LinearGradient? _gradient(BuildContext context) {
    if (selected) {
      return context.agentAwesomeSelectedGradient;
    }
    return null;
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
      decoration: BoxDecoration(color: colors.surface),
      child: child,
    );
  }
}
