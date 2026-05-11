/// Focus toolbar controls for the task stream canvas.
part of 'task_stream_canvas.dart';

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
