/// App shell sidebar navigation button widget.
part of 'app_shell_frame.dart';

/// _NavButton renders one selectable sidebar route.
class _NavButton extends StatelessWidget {
  /// Creates a navigation button for one app route.
  const _NavButton({
    required this.label,
    required this.iconGlyph,
    required this.selected,
    required this.onTap,
    required this.compact,
    required this.showsChevron,
  });

  final String label;
  final String iconGlyph;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final bool showsChevron;

  /// Builds one navigation item.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final selectedGradient = selected
        ? context.agentAwesomeSelectedGradient
        : null;
    final foreground = selected ? colors.ink : colors.muted;
    return Tooltip(
      message: compact ? label : '',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 38),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 10,
            vertical: compact ? 8 : 7,
          ),
          decoration: BoxDecoration(
            color: selectedGradient == null
                ? selected
                      ? colors.greenSoft
                      : Colors.transparent
                : null,
            gradient: selectedGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 22,
                child: Text(
                  iconGlyph,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
              if (!compact) ...<Widget>[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0,
                      height: 1.25,
                      color: foreground,
                    ),
                  ),
                ),
                if (showsChevron) const SizedBox(width: 8),
                if (showsChevron) ...<Widget>[
                  Text(
                    '›',
                    style: TextStyle(
                      color: colors.subtle,
                      fontSize: 19,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
