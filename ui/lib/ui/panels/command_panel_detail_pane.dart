/// Command-panel detail pane widget.
part of 'panels.dart';

/// _CommandSubShellDetailPane renders detail mode tabs and content.
class _CommandSubShellDetailPane extends StatelessWidget {
  const _CommandSubShellDetailPane({
    required this.title,
    required this.modes,
    required this.tabs,
    required this.selectedMode,
    required this.selectedTab,
    required this.onModeSelected,
    required this.onTabSelected,
    required this.actions,
    required this.items,
    required this.selectedItem,
    required this.onItemSelected,
    required this.itemActions,
    required this.detailFilterController,
    required this.detailFilterHint,
    required this.showDetailFilter,
    required this.onDetailFilterChanged,
    required this.showCollapseButton,
    required this.showHeader,
    required this.highlightFilterField,
    required this.onTitleTap,
    required this.child,
  });

  final String title;
  final List<CommandPanelDetailMode> modes;
  final List<ShellTab> tabs;
  final CommandPanelDetailMode selectedMode;
  final ShellTab selectedTab;
  final ValueChanged<CommandPanelDetailMode> onModeSelected;
  final ValueChanged<ShellTab> onTabSelected;
  final Widget? actions;
  final List<CommandPanelContentItem> items;
  final CommandPanelContentItem? selectedItem;
  final ValueChanged<CommandPanelContentItem> onItemSelected;
  final Widget? itemActions;
  final TextEditingController detailFilterController;
  final String detailFilterHint;
  final bool showDetailFilter;
  final ValueChanged<String> onDetailFilterChanged;
  final bool showCollapseButton;
  final bool showHeader;
  final bool highlightFilterField;
  final VoidCallback? onTitleTap;
  final Widget child;

  /// Builds the detail column.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final collapseScope = SplitPaneCollapseScope.maybeOf(context);
    final showModeSwitcher = modes.length > 1;
    final hasItemChrome =
        items.isNotEmpty && (items.length > 1 || itemActions != null);
    if (collapseScope?.collapsed ?? false) {
      return _CommandSubShellCollapsedPane(
        title: title,
        icon: selectedMode.icon,
        collapseScope: collapseScope!,
      );
    }
    return DecoratedBox(
      key: const ValueKey<String>('main-content-right-pane'),
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeSurfaceGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showHeader) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: PanelSectionLabel(title, onTap: onTitleTap),
                      ),
                      if (hasItemChrome) ...<Widget>[
                        const SizedBox(width: 10),
                        _CommandSubShellDetailItemSelect(
                          items: items,
                          selectedId: selectedItem?.id,
                          width: 210,
                          onChanged: _selectItemById,
                        ),
                      ],
                      if (collapseScope != null && showCollapseButton)
                        const SizedBox(width: 8),
                      if (collapseScope != null && showCollapseButton)
                        PanelCollapseButton(
                          expanded: true,
                          direction: collapseScope.side.direction,
                          onPressed: collapseScope.onToggle,
                          expandedTooltip: 'Collapse details column',
                          collapsedTooltip: 'Expand details column',
                        ),
                    ],
                  ),
                  if (showModeSwitcher || actions != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        if (showModeSwitcher)
                          Expanded(
                            child: _CommandSubShellDetailTabs(
                              modes: modes,
                              selectedMode: selectedMode,
                              onSelected: onModeSelected,
                            ),
                          )
                        else
                          const Spacer(),
                        if (actions != null) ...<Widget>[
                          if (showModeSwitcher) const SizedBox(width: 8),
                          actions!,
                        ],
                      ],
                    ),
                  ],
                  if (hasItemChrome) ...<Widget>[
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: <Widget>[
                                for (final item in items)
                                  PanelIconButton(
                                    icon: item.icon,
                                    tooltip: item.label,
                                    selected: item.id == selectedItem?.id,
                                    onPressed: () => onItemSelected(item),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        ?itemActions,
                      ],
                    ),
                  ],
                  if (tabs.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    _CommandSubShellDetailTextTabs(
                      tabs: tabs,
                      selectedTab: selectedTab,
                      onSelected: onTabSelected,
                    ),
                  ],
                  if (showDetailFilter) ...<Widget>[
                    const SizedBox(height: 12),
                    _CommandSubShellFilterField(
                      controller: detailFilterController,
                      hintText: detailFilterHint,
                      onChanged: onDetailFilterChanged,
                      highlighted: highlightFilterField,
                    ),
                  ],
                ],
              ),
            ),
            Divider(
              height: AgentAwesomeStrokeTokens.dividerWidth,
              thickness: AgentAwesomeStrokeTokens.dividerWidth,
              color: colors.border,
            ),
          ],
          Expanded(child: PanelBodySurface(child: child)),
        ],
      ),
    );
  }

  /// Selects a detail item by id from the dropdown.
  void _selectItemById(String id) {
    for (final item in items) {
      if (item.id == id) {
        onItemSelected(item);
        return;
      }
    }
  }
}

class _CommandSubShellDetailItemSelect extends StatelessWidget {
  const _CommandSubShellDetailItemSelect({
    required this.items,
    required this.selectedId,
    required this.width,
    required this.onChanged,
  });

  final List<CommandPanelContentItem> items;
  final String? selectedId;
  final double width;
  final ValueChanged<String> onChanged;

  /// Builds the compact right-pane item dropdown.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SizedBox(
      width: width,
      height: 38,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(
            color: colors.border,
            width: AgentAwesomeStrokeTokens.borderWidth,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedId,
            isDense: true,
            isExpanded: true,
            menuWidth: 360,
            icon: const Icon(Icons.expand_more, size: 18),
            selectedItemBuilder: (context) {
              return <Widget>[
                for (final item in items)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(item.label, overflow: TextOverflow.ellipsis),
                  ),
              ];
            },
            items: <DropdownMenuItem<String>>[
              for (final item in items)
                DropdownMenuItem<String>(
                  value: item.id,
                  child: _CommandSubShellDetailDropdownLabel(item: item),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged(value);
              }
            },
          ),
        ),
      ),
    );
  }
}

class _CommandSubShellDetailDropdownLabel extends StatelessWidget {
  const _CommandSubShellDetailDropdownLabel({required this.item});

  final CommandPanelContentItem item;

  /// Builds one right-pane dropdown item label.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Row(
      children: <Widget>[
        Icon(item.icon, size: 16, color: colors.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(item.label, softWrap: false)),
        if (item.badge.isNotEmpty) ...<Widget>[
          const SizedBox(width: 8),
          Text(item.badge, style: TextStyle(color: colors.green, fontSize: 11)),
        ],
      ],
    );
  }
}
