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
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: selected ? colors.greenSoft : colors.panel,
              gradient: selected
                  ? context.agentAwesomeSelectedGradient
                  : context.agentAwesomeControlGradient,
              border: Border.all(
                color: selected ? colors.green : colors.border,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: selected ? colors.green : colors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
