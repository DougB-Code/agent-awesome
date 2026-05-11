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
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            color: selected ? colors.greenSoft : colors.panel,
            gradient: selected
                ? context.agentAwesomeSelectedGradient
                : context.agentAwesomeControlGradient,
            border: Border.all(color: selected ? colors.green : colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: selected ? colors.green : colors.muted,
          ),
        ),
      ),
    );
  }
}
