/// Global command bar chrome button and theme toggle widgets.
part of 'command_bar.dart';

/// _CommandAgentPicker switches the active agent prompt config.
class _CommandAgentPicker extends StatelessWidget {
  /// Creates a top-bar agent picker.
  const _CommandAgentPicker({
    required this.agents,
    required this.activePath,
    required this.compact,
    required this.switching,
    required this.size,
    required this.onChanged,
    required this.onManageAgents,
    required this.onOpen,
  });

  static const String _manageAgentsValue = '__manage_agents__';

  /// Agent configs available in app-owned storage.
  final List<ConfigFileEntry> agents;

  /// Currently selected agent config path.
  final String activePath;

  /// Whether the control should render as an icon-only button.
  final bool compact;

  /// Whether an agent switch is currently in progress.
  final bool switching;

  /// Control height.
  final double size;

  /// Callback invoked with the selected agent config path.
  final ValueChanged<String>? onChanged;

  /// Callback invoked when the user opens agent management.
  final VoidCallback onManageAgents;

  /// Callback invoked before the picker menu is shown.
  final VoidCallback onOpen;

  /// Builds the agent picker.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final active = _activeAgent();
    final label = active?.label ?? 'Agent';
    final enabled = agents.isNotEmpty && onChanged != null;
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'Active agent',
      offset: Offset(0, size + 8),
      onOpened: onOpen,
      onSelected: (value) {
        if (value == _manageAgentsValue) {
          onManageAgents();
          return;
        }
        onChanged?.call(value);
      },
      itemBuilder: (context) {
        if (agents.isEmpty) {
          return <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                'No agents configured',
                style: TextStyle(color: colors.muted),
              ),
            ),
          ];
        }
        return <PopupMenuEntry<String>>[
          for (final agent in agents)
            PopupMenuItem<String>(
              value: agent.path,
              enabled: agent.path != activePath,
              child: _CommandAgentMenuItem(
                agent: agent,
                activePath: activePath,
              ),
            ),
          const PopupMenuDivider(height: 1),
          const PopupMenuItem<String>(
            value: _manageAgentsValue,
            height: 24,
            child: _CommandManageItem(),
          ),
        ];
      },
      child: _CommandPickerFrame(
        key: const ValueKey<String>('command-agent-picker'),
        size: size,
        width: 164,
        compact: compact,
        enabled: enabled,
        switching: switching,
        icon: Icons.psychology_outlined,
        label: label,
      ),
    );
  }

  /// Returns the currently active agent entry.
  ConfigFileEntry? _activeAgent() {
    for (final agent in agents) {
      if (agent.path == activePath || agent.assigned) {
        return agent;
      }
    }
    return agents.isEmpty ? null : agents.first;
  }
}

/// _CommandMemoryPicker switches the active memory domain.
class _CommandMemoryPicker extends StatelessWidget {
  /// Creates a top-bar memory picker.
  const _CommandMemoryPicker({
    required this.domains,
    required this.activeId,
    required this.compact,
    required this.switching,
    required this.size,
    required this.onChanged,
    required this.onManageMemory,
    required this.onOpen,
  });

  static const String _manageMemoryValue = '__manage_memory__';

  /// Memory domains available for reads and writes.
  final List<McpServerRuntime> domains;

  /// Currently selected memory domain id.
  final String activeId;

  /// Whether the control should render as an icon-only button.
  final bool compact;

  /// Whether a memory switch is currently in progress.
  final bool switching;

  /// Control height.
  final double size;

  /// Callback invoked with the selected memory domain id.
  final ValueChanged<String>? onChanged;

  /// Callback invoked when the user opens memory settings.
  final VoidCallback onManageMemory;

  /// Callback invoked before the picker menu is shown.
  final VoidCallback onOpen;

  /// Builds the memory picker.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final active = _activeDomain();
    final label = _domainLabel(active) ?? 'Memory';
    final enabled = domains.isNotEmpty && onChanged != null;
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'Active memory',
      offset: Offset(0, size + 8),
      onOpened: onOpen,
      onSelected: (value) {
        if (value == _manageMemoryValue) {
          onManageMemory();
          return;
        }
        onChanged?.call(value);
      },
      itemBuilder: (context) {
        if (domains.isEmpty) {
          return <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                'No memory domains configured',
                style: TextStyle(color: colors.muted),
              ),
            ),
          ];
        }
        return <PopupMenuEntry<String>>[
          for (final domain in domains)
            PopupMenuItem<String>(
              value: domain.id,
              enabled: domain.id != activeId,
              child: _CommandMemoryMenuItem(domain: domain, activeId: activeId),
            ),
          const PopupMenuDivider(height: 1),
          const PopupMenuItem<String>(
            value: _manageMemoryValue,
            height: 24,
            child: _CommandManageItem(),
          ),
        ];
      },
      child: _CommandPickerFrame(
        key: const ValueKey<String>('command-memory-picker'),
        size: size,
        width: 150,
        compact: compact,
        enabled: enabled,
        switching: switching,
        icon: Icons.account_tree_outlined,
        label: label,
      ),
    );
  }

  /// Returns the currently active memory domain.
  McpServerRuntime? _activeDomain() {
    for (final domain in domains) {
      if (domain.id == activeId) {
        return domain;
      }
    }
    return domains.isEmpty ? null : domains.first;
  }

  /// Returns a user-facing memory domain label.
  String? _domainLabel(McpServerRuntime? domain) {
    if (domain == null) {
      return null;
    }
    return domain.label.trim().isEmpty ? domain.id : domain.label;
  }
}

/// _CommandPickerFrame renders a compact top-bar selector body.
class _CommandPickerFrame extends StatelessWidget {
  /// Creates a shared top-bar picker frame.
  const _CommandPickerFrame({
    super.key,
    required this.size,
    required this.width,
    required this.compact,
    required this.enabled,
    required this.switching,
    required this.icon,
    required this.label,
  });

  /// Control height.
  final double size;

  /// Expanded control width.
  final double width;

  /// Whether only the icon should be visible.
  final bool compact;

  /// Whether the picker can be used.
  final bool enabled;

  /// Whether an async switch is in progress.
  final bool switching;

  /// Icon shown for the selected resource.
  final IconData icon;

  /// Label shown for the selected resource.
  final String label;

  /// Builds a top-bar selector frame.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      height: size,
      width: compact ? size : width,
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeControlGradient,
        border: Border.all(
          color: colors.border,
          width: AgentAwesomeStrokeTokens.borderWidth,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: compact
            ? MainAxisAlignment.center
            : MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Icon(
            switching ? Icons.sync_outlined : icon,
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
    );
  }
}

/// _CommandManageItem renders the compact management shortcut.
class _CommandManageItem extends StatelessWidget {
  /// Creates the compact management menu row.
  const _CommandManageItem();

  /// Builds a half-height manage row for settings.
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

/// _CommandAgentMenuItem renders one agent choice.
class _CommandAgentMenuItem extends StatelessWidget {
  /// Creates one agent picker row.
  const _CommandAgentMenuItem({required this.agent, required this.activePath});

  /// Agent represented by this row.
  final ConfigFileEntry agent;

  /// Active agent path.
  final String activePath;

  /// Builds the menu row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final active = agent.path == activePath || agent.assigned;
    return SizedBox(
      width: 280,
      child: Row(
        children: <Widget>[
          Icon(
            active ? Icons.check_circle_outline : Icons.psychology_outlined,
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
                  agent.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  active ? 'Active agent' : agent.fileLabel,
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

/// _CommandMemoryMenuItem renders one memory-domain choice.
class _CommandMemoryMenuItem extends StatelessWidget {
  /// Creates one memory picker row.
  const _CommandMemoryMenuItem({required this.domain, required this.activeId});

  /// Memory domain represented by this row.
  final McpServerRuntime domain;

  /// Active memory domain id.
  final String activeId;

  /// Builds the menu row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final active = domain.id == activeId;
    final label = domain.label.trim().isEmpty ? domain.id : domain.label;
    return SizedBox(
      width: 280,
      child: Row(
        children: <Widget>[
          Icon(
            active ? Icons.check_circle_outline : Icons.account_tree_outlined,
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
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  active ? 'Active memory' : domain.id,
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
              width: AgentAwesomeStrokeTokens.borderWidth,
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
          key: const ValueKey<String>('command-theme-badge'),
          height: 42,
          width: 118,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            gradient: context.agentAwesomeControlGradient,
            border: Border.all(
              color: colors.border,
              width: AgentAwesomeStrokeTokens.borderWidth,
            ),
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
