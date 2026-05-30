/// App shell sidebar navigation button widget.
part of 'app_shell_frame.dart';

/// _NavButton renders one selectable sidebar route.
class _NavButton extends StatelessWidget {
  /// Creates a navigation button for one app route.
  const _NavButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  /// Builds one navigation item.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final selectedGradient = selected
        ? context.agentAwesomeSidebarSelectedGradient
        : null;
    final foreground = selected ? colors.ink : colors.muted;
    final radius = BorderRadius.circular(8);
    return Tooltip(
      message: compact ? label : '',
      child: InkWell(
        borderRadius: radius,
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
            borderRadius: radius,
          ),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 22,
                child: Icon(icon, color: foreground, size: 19),
              ),
              if (!compact) ...<Widget>[
                const SizedBox(width: 8),
                Expanded(
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
                if (selected) ...<Widget>[
                  const SizedBox(width: 8),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: colors.green,
                      shape: BoxShape.circle,
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
