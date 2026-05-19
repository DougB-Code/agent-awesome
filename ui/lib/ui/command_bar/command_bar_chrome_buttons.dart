/// Global command bar chrome button and theme toggle widgets.
part of 'command_bar.dart';

/// _CommandProfilePicker switches the active runtime profile.
class _CommandProfilePicker extends StatelessWidget {
  /// Creates a top-bar runtime profile picker.
  const _CommandProfilePicker({
    required this.profiles,
    required this.activePath,
    required this.defaultPath,
    required this.compact,
    required this.switching,
    required this.size,
    required this.onChanged,
    required this.onManageProfiles,
    required this.onOpen,
  });

  static const String _manageProfilesValue = '__manage_profiles__';

  /// Profiles available in app-owned profile storage.
  final List<RuntimeProfileFileEntry> profiles;

  /// Currently loaded profile path.
  final String activePath;

  /// Profile path used when starting default chats.
  final String defaultPath;

  /// Whether the control should render as an icon-only button.
  final bool compact;

  /// Whether a profile switch is currently in progress.
  final bool switching;

  /// Control height.
  final double size;

  /// Callback invoked with the selected profile path.
  final ValueChanged<String>? onChanged;

  /// Callback invoked when the user opens profile management.
  final VoidCallback onManageProfiles;

  /// Callback invoked before the picker menu is shown.
  final VoidCallback onOpen;

  /// Builds the profile picker.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final active = _activeProfile();
    final label = active?.label ?? 'Profile';
    final enabled = profiles.isNotEmpty && onChanged != null;
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'Active profile',
      offset: Offset(0, size + 8),
      onOpened: onOpen,
      onSelected: (value) {
        if (value == _manageProfilesValue) {
          onManageProfiles();
          return;
        }
        onChanged?.call(value);
      },
      itemBuilder: (context) {
        if (profiles.isEmpty) {
          return <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                'No profiles configured',
                style: TextStyle(color: colors.muted),
              ),
            ),
          ];
        }
        return <PopupMenuEntry<String>>[
          for (final profile in profiles)
            PopupMenuItem<String>(
              value: profile.path,
              enabled: profile.path != activePath,
              child: _CommandProfileMenuItem(
                profile: profile,
                activePath: activePath,
                defaultPath: defaultPath,
              ),
            ),
          const PopupMenuDivider(height: 1),
          const PopupMenuItem<String>(
            value: _manageProfilesValue,
            height: 24,
            child: _CommandProfileManageItem(),
          ),
        ];
      },
      child: Container(
        height: size,
        width: compact ? size : 178,
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
              switching ? Icons.sync_outlined : Icons.manage_accounts_outlined,
              size: 19,
              color: enabled ? colors.ink : colors.muted,
            ),
            if (!compact) ...<Widget>[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  switching ? 'Switching...' : label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 18, color: colors.muted),
            ],
          ],
        ),
      ),
    );
  }

  RuntimeProfileFileEntry? _activeProfile() {
    for (final profile in profiles) {
      if (profile.path == activePath || profile.active) {
        return profile;
      }
    }
    return profiles.isEmpty ? null : profiles.first;
  }
}

/// _CommandProfileManageItem renders the compact profile management shortcut.
class _CommandProfileManageItem extends StatelessWidget {
  /// Creates the compact profile-management menu row.
  const _CommandProfileManageItem();

  /// Builds a half-height manage row for profile settings.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SizedBox(
      width: 280,
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.settings_outlined, size: 14, color: colors.green),
            const SizedBox(width: 6),
            Text(
              'Manage',
              style: TextStyle(
                color: colors.green,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// _CommandProfileMenuItem renders one profile choice with policy context.
class _CommandProfileMenuItem extends StatelessWidget {
  /// Creates one profile picker row.
  const _CommandProfileMenuItem({
    required this.profile,
    required this.activePath,
    required this.defaultPath,
  });

  /// Profile represented by this row.
  final RuntimeProfileFileEntry profile;

  /// Active profile path.
  final String activePath;

  /// Default chat profile path.
  final String defaultPath;

  /// Builds the menu row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final active = profile.path == activePath || profile.active;
    final defaultProfile = profile.path == defaultPath;
    final details = <String>[
      if (profile.runtimeKind.isNotEmpty) profile.runtimeKind,
      if (profile.memoryDomainLabels.isNotEmpty)
        profile.memoryDomainLabels.take(3).join(', '),
      if (defaultProfile) 'Default',
    ];
    return SizedBox(
      width: 280,
      child: Row(
        children: <Widget>[
          Icon(
            active ? Icons.check_circle_outline : Icons.person_outline,
            color: active ? colors.green : colors.muted,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  profile.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  details.isEmpty ? profile.id : details.join(' • '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
    final enabled = onTap != null;
    final foreground = enabled
        ? colors.ink
        : colors.muted.withValues(alpha: 0.45);
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
            color: enabled
                ? colors.surface
                : colors.surface.withValues(alpha: 0.42),
            gradient: enabled ? context.agentAwesomeControlGradient : null,
            border: Border.all(
              color: enabled
                  ? colors.border
                  : colors.border.withValues(alpha: 0.45),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Icon(icon, size: 19, color: foreground),
              if (!compact) ...<Widget>[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
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
