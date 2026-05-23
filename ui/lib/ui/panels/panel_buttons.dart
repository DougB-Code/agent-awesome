/// Shared icon-only panel buttons.
part of 'panels.dart';

/// PanelIconButton renders the shared square command-panel icon button.
class PanelIconButton extends StatelessWidget {
  /// Creates a compact icon-only button.
  const PanelIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  /// Button icon.
  final IconData icon;

  /// Tooltip text.
  final String tooltip;

  /// Activation callback, or null when disabled.
  final VoidCallback? onPressed;

  /// Whether this button represents the active selection.
  final bool selected;

  /// Builds a shared command-panel icon button.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Container(
              height: PanelStyleTokens.iconButtonSize,
              width: PanelStyleTokens.iconButtonSize,
              decoration: BoxDecoration(
                color: selected ? colors.greenSoft : colors.panel,
                border: Border.all(
                  color: selected ? colors.borderStrong : colors.border,
                ),
                borderRadius: BorderRadius.circular(PanelStyleTokens.radius),
              ),
              child: Icon(
                icon,
                size: PanelStyleTokens.iconButtonIconSize,
                color: selected ? colors.green : colors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// PanelCreateButton renders the shared collection-level create button.
class PanelCreateButton extends StatelessWidget {
  /// Creates a right-header create button with the shared add icon.
  const PanelCreateButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  /// Tooltip text that names the creation action.
  final String tooltip;

  /// Activation callback, or null when disabled.
  final VoidCallback? onPressed;

  /// Whether this button represents the active creation mode.
  final bool selected;

  /// Builds the shared create affordance.
  @override
  Widget build(BuildContext context) {
    return PanelIconButton(
      icon: Icons.add,
      tooltip: tooltip,
      selected: selected,
      onPressed: onPressed,
    );
  }
}

/// PanelInlineIconButton renders compact icon actions inside content blocks.
class PanelInlineIconButton extends StatelessWidget {
  /// Creates a compact inline icon action.
  const PanelInlineIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.loading = false,
  });

  /// Button icon.
  final IconData icon;

  /// Tooltip text.
  final String tooltip;

  /// Activation callback, or null when disabled.
  final VoidCallback? onPressed;

  /// Whether this button represents the active action state.
  final bool selected;

  /// Whether the button should show a compact busy indicator.
  final bool loading;

  /// Builds a quiet inline action button with panel styling.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                color: selected ? colors.greenSoft : colors.panel,
                border: Border.all(
                  color: selected ? colors.borderStrong : colors.border,
                ),
                borderRadius: BorderRadius.circular(
                  PanelStyleTokens.compactRadius,
                ),
              ),
              child: loading
                  ? const Center(
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Icon(
                      icon,
                      size: 17,
                      color: selected ? colors.green : colors.muted,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
