/// Command-panel command-area pane widget.
part of 'panels.dart';

/// _CommandSubShellCommandPane renders command area tabs and content.
class _CommandSubShellCommandPane extends StatelessWidget {
  const _CommandSubShellCommandPane({
    required this.area,
    required this.areas,
    required this.selectedIndex,
    required this.filterController,
    required this.filterHint,
    required this.onAreaSelected,
    required this.onTitleTap,
    required this.onFilterChanged,
    required this.actions,
    required this.areaFilters,
    required this.selectedAreaFilterId,
    required this.onAreaFilterSelected,
    required this.showAreaTabs,
    required this.showCollapseButton,
    required this.child,
  });

  final SwitcherPanelArea area;
  final List<SwitcherPanelArea> areas;
  final int selectedIndex;
  final TextEditingController filterController;
  final String filterHint;
  final ValueChanged<int> onAreaSelected;
  final VoidCallback? onTitleTap;
  final ValueChanged<String> onFilterChanged;
  final Widget? actions;
  final List<CommandPanelFilterOption> areaFilters;
  final String selectedAreaFilterId;
  final ValueChanged<CommandPanelFilterOption> onAreaFilterSelected;
  final bool showAreaTabs;
  final bool showCollapseButton;
  final Widget child;

  /// Builds the command area column.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final collapseScope = SplitPaneCollapseScope.maybeOf(context);
    if (collapseScope?.collapsed ?? false) {
      return _CommandSubShellCollapsedPane(
        title: area.title,
        icon: area.icon,
        collapseScope: collapseScope!,
      );
    }
    return DecoratedBox(
      key: const ValueKey<String>('main-content-left-pane'),
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeSurfaceGradient,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: PanelSectionLabel(area.title, onTap: onTitleTap),
                    ),
                    if (collapseScope != null && showCollapseButton)
                      PanelCollapseButton(
                        expanded: true,
                        direction: collapseScope.side.direction,
                        onPressed: collapseScope.onToggle,
                        expandedTooltip: 'Collapse command column',
                        collapsedTooltip: 'Expand command column',
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (showAreaTabs || actions != null) ...<Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (showAreaTabs)
                        Expanded(
                          child: _CommandSubShellAreaTabs(
                            areas: areas,
                            selectedIndex: selectedIndex,
                            onSelected: onAreaSelected,
                          ),
                        )
                      else
                        const Spacer(),
                      if (actions != null) ...<Widget>[
                        const SizedBox(width: 12),
                        actions!,
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                _CommandSubShellFilterField(
                  controller: filterController,
                  hintText: filterHint,
                  onChanged: onFilterChanged,
                ),
                if (areaFilters.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _CommandSubShellAreaFilters(
                    filters: areaFilters,
                    selectedId: selectedAreaFilterId,
                    onSelected: onAreaFilterSelected,
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          Expanded(child: child),
        ],
      ),
    );
  }
}
