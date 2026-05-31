/// Command-panel area and detail tab widgets.
part of 'panels.dart';

/// _CommandSubShellAreaTabs renders icon buttons for command areas.
class _CommandSubShellAreaTabs extends StatelessWidget {
  const _CommandSubShellAreaTabs({
    required this.areas,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<SwitcherPanelArea> areas;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Builds icon tabs for command areas.
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (var index = 0; index < areas.length; index++)
            if (areas[index].showInQuickAccess || selectedIndex == index)
              _CommandSubShellIconTab(
                icon: areas[index].icon,
                selected: selectedIndex == index,
                tooltip: areas[index].title,
                onTap: () => onSelected(index),
              ),
        ],
      ),
    );
  }
}

/// _CommandSubShellDetailTabs renders icon buttons for detail modes.
class _CommandSubShellDetailTabs extends StatelessWidget {
  const _CommandSubShellDetailTabs({
    required this.modes,
    required this.selectedMode,
    required this.onSelected,
  });

  final List<CommandPanelDetailMode> modes;
  final CommandPanelDetailMode selectedMode;
  final ValueChanged<CommandPanelDetailMode> onSelected;

  /// Builds icon tabs for detail modes.
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final mode in modes)
            _CommandSubShellIconTab(
              icon: mode.icon,
              tooltip: mode.label,
              selected: selectedMode.id == mode.id,
              onTap: () => onSelected(mode),
            ),
        ],
      ),
    );
  }
}

/// _CommandSubShellDetailTextTabs renders labeled tabs for right-pane content.
class _CommandSubShellDetailTextTabs extends StatelessWidget {
  const _CommandSubShellDetailTextTabs({
    required this.tabs,
    required this.selectedTab,
    required this.onSelected,
  });

  final List<ShellTab> tabs;
  final ShellTab selectedTab;
  final ValueChanged<ShellTab> onSelected;

  /// Builds labeled right-pane tabs without replacing quick-access icons.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => onSelected(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
                  decoration: BoxDecoration(
                    color: selectedTab.id == tab.id
                        ? colors.greenSoft
                        : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(
                        color: selectedTab.id == tab.id
                            ? colors.green
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(tab.icon, size: 15, color: colors.muted),
                      const SizedBox(width: 7),
                      Text(
                        tab.label,
                        style: TextStyle(
                          color: selectedTab.id == tab.id
                              ? colors.ink
                              : colors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// _CommandSubShellAreaFilters renders shell-owned left-pane quick filters.
class _CommandSubShellAreaFilters extends StatelessWidget {
  const _CommandSubShellAreaFilters({
    required this.filters,
    required this.selectedId,
    required this.onSelected,
  });

  final List<CommandPanelFilterOption> filters;
  final String selectedId;
  final ValueChanged<CommandPanelFilterOption> onSelected;

  /// Builds labeled quick filters for the current command area.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final filter in filters)
            Padding(
              padding: EdgeInsets.only(right: filter == filters.last ? 0 : 8),
              child: _CommandSubShellAreaFilterButton(
                filter: filter,
                selected: filter.id == selectedId,
                onTap: () => onSelected(filter),
              ),
            ),
        ],
      ),
    );
  }
}

/// _CommandSubShellAreaFilterButton renders one labeled quick filter.
class _CommandSubShellAreaFilterButton extends StatelessWidget {
  const _CommandSubShellAreaFilterButton({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final CommandPanelFilterOption filter;
  final bool selected;
  final VoidCallback onTap;

  /// Builds a shared filter control for command panels.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final label = filter.badge.trim().isEmpty
        ? filter.label
        : '${filter.label} ${filter.badge}';
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        backgroundColor: selected ? colors.greenSoft : colors.surface,
        foregroundColor: selected ? colors.green : colors.ink,
        side: BorderSide(
          color: selected ? colors.borderStrong : colors.border,
          width: AgentAwesomeStrokeTokens.borderWidth,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(filter.icon, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

/// _CommandSubShellIconTab renders one command-area icon tab.
class _CommandSubShellIconTab extends StatelessWidget {
  const _CommandSubShellIconTab({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  /// Builds one icon-only command tab.
  @override
  Widget build(BuildContext context) {
    return PanelIconButton(
      icon: icon,
      tooltip: tooltip,
      selected: selected,
      onPressed: onTap,
    );
  }
}
