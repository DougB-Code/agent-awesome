/// Global command bar chrome button and theme toggle widgets.
part of 'command_bar.dart';

/// _CommandChromeButton renders one screenshot-style top-bar action.
class _CommandChromeButton extends StatelessWidget {
  /// Creates a rounded top-bar button.
  const _CommandChromeButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.size,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final double size;
  final VoidCallback? onTap;

  /// Builds a rounded command-bar action button.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final compact = label.isEmpty;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: size,
          width: compact ? size : 118,
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
          decoration: BoxDecoration(
            color: colors.surface,
            gradient: context.agentAwesomeControlGradient,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Icon(
                icon,
                size: 19,
                color: onTap == null
                    ? colors.muted.withValues(alpha: 0.45)
                    : colors.ink,
              ),
              if (!compact) ...<Widget>[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// _ThemeBadge toggles between the light and dark themes.
class _ThemeBadge extends StatelessWidget {
  /// Creates a theme toggle badge.
  const _ThemeBadge();

  /// Builds the active theme indicator.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final themeScope = AgentAwesomeThemeScope.maybeOf(context);
    final dark =
        themeScope?.isDark ?? Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: dark ? 'Switch to light theme' : 'Switch to dark theme',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: themeScope?.onToggleTheme,
        child: Container(
          height: 42,
          width: 118,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            gradient: context.agentAwesomeControlGradient,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                color: colors.ink,
                size: 19,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  dark ? 'Dark' : 'Light',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
