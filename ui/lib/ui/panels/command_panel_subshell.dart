/// Command-panel subshell state and layout coordination widget.
part of 'panels.dart';

/// CommandPanelSubShell renders the official command-panel two-column shell.
class CommandPanelSubShell extends StatefulWidget {
  /// Creates a reusable command-panel subshell.
  const CommandPanelSubShell({
    super.key,
    required this.areas,
    required this.detailTitle,
    required this.detailModes,
    required this.selectedDetailModeId,
    required this.onDetailModeSelected,
    required this.detailBuilder,
    this.detailTabs = const <ShellTab>[],
    this.detailTabsBuilder,
    this.onAreaChanged,
    this.areaActionsBuilder,
    this.areaFiltersBuilder,
    this.selectedAreaFilterIdBuilder,
    this.onAreaFilterSelected,
    this.detailActionsBuilder,
    this.detailModesBuilder,
    this.selectedDetailModeIdBuilder,
    this.onAreaDetailModeSelected,
    this.areaDetailBuilder,
    this.searchableDetailBuilder,
    this.areaTabbedDetailBuilder,
    this.detailItemsBuilder,
    this.selectedDetailItemIdBuilder,
    this.onDetailItemSelected,
    this.detailItemActionsBuilder,
    this.itemDetailBuilder,
    this.companionAreaIdBuilder,
    this.split = const PanelSplit(left: 0.72, min: 0.46, max: 0.86),
    this.gutterWidth = 0,
    this.padding = EdgeInsets.zero,
    this.filterHint = 'Filter...',
    this.detailFilterHint = 'Filter selected...',
    this.emptyLabel = 'No command areas configured',
    this.showDetailPane = true,
    this.showAreaTabs = true,
    this.showPaneCollapseButtons = true,
    this.showDetailHeader = true,
  });

  /// Selectable command areas shown in the left panel.
  final List<SwitcherPanelArea> areas;

  /// Title shown above the right detail panel.
  final String detailTitle;

  /// Selectable detail modes shown in the right panel.
  final List<CommandPanelDetailMode> detailModes;

  /// Currently selected detail mode id.
  final String selectedDetailModeId;

  /// Detail mode selection callback.
  final ValueChanged<String> onDetailModeSelected;

  /// Builds the right panel body for one detail mode id.
  final Widget Function(String modeId) detailBuilder;

  /// Optional labeled tabs shown below the right-pane quick-access row.
  final List<ShellTab> detailTabs;

  /// Optional builder for tabs inside the selected right-pane mode.
  final CommandPanelDetailTabsBuilder? detailTabsBuilder;

  /// Reports the active command area to the owning shell.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds trailing command controls for the selected area.
  final CommandPanelAreaActionsBuilder? areaActionsBuilder;

  /// Builds shell-owned quick filters for the selected command area.
  final CommandPanelAreaFiltersBuilder? areaFiltersBuilder;

  /// Resolves the active shell-owned quick filter for the selected area.
  final CommandPanelSelectedAreaFilterBuilder? selectedAreaFilterIdBuilder;

  /// Handles shell-owned quick filter selection.
  final CommandPanelAreaFilterChanged? onAreaFilterSelected;

  /// Builds trailing controls for the active detail mode.
  final CommandPanelDetailActionsBuilder? detailActionsBuilder;

  /// Optional area-aware detail mode builder.
  final CommandPanelDetailModesBuilder? detailModesBuilder;

  /// Optional area-aware selected detail mode resolver.
  final CommandPanelSelectedDetailModeBuilder? selectedDetailModeIdBuilder;

  /// Optional area-aware detail mode selection callback.
  final CommandPanelAreaDetailModeChanged? onAreaDetailModeSelected;

  /// Optional area-aware detail body builder.
  final CommandPanelAreaDetailBuilder? areaDetailBuilder;

  /// Optional area-aware detail body builder that receives right-pane search.
  final CommandPanelSearchableDetailBuilder? searchableDetailBuilder;

  /// Optional area-aware mode/tab body builder.
  final CommandPanelAreaTabbedDetailBuilder? areaTabbedDetailBuilder;

  /// Optional selectable items shown inside the right-pane header.
  final CommandPanelDetailItemsBuilder? detailItemsBuilder;

  /// Optional selected right-pane item resolver.
  final CommandPanelSelectedDetailItemBuilder? selectedDetailItemIdBuilder;

  /// Optional right-pane item selection callback.
  final CommandPanelDetailItemChanged? onDetailItemSelected;

  /// Optional item-level right-pane action builder.
  final CommandPanelDetailItemActionsBuilder? detailItemActionsBuilder;

  /// Optional selected item content builder with right-pane filtering.
  final CommandPanelItemDetailBuilder? itemDetailBuilder;

  /// Optional right-mode to left-area companion selector.
  final CommandPanelCompanionAreaBuilder? companionAreaIdBuilder;

  /// Split ratio configuration.
  final PanelSplit split;

  /// Horizontal space between command and detail columns.
  final double gutterWidth;

  /// Outer page padding for the subshell.
  final EdgeInsetsGeometry padding;

  /// Placeholder text for the command-area filter.
  final String filterHint;

  /// Placeholder text for the detail-area filter.
  final String detailFilterHint;

  /// Empty-state label when there are no command areas.
  final String emptyLabel;

  /// Whether the shell renders a right-side detail pane.
  final bool showDetailPane;

  /// Whether the left pane renders area quick-access tabs.
  final bool showAreaTabs;

  /// Whether split-pane collapse buttons are visible in pane headers.
  final bool showPaneCollapseButtons;

  /// Whether the detail pane renders its own title and mode tabs.
  final bool showDetailHeader;

  @override
  State<CommandPanelSubShell> createState() => _CommandPanelSubShellState();
}

class _CommandPanelSubShellState extends State<CommandPanelSubShell> {
  final TextEditingController _filterController = TextEditingController();
  final TextEditingController _detailFilterController = TextEditingController();
  final Map<String, String> _selectedTabIds = <String, String>{};
  int _selectedAreaIndex = 0;
  String _reportedAreaKey = '';
  String _query = '';
  String _detailQuery = '';

  /// Reports the initial active command area.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _selectCompanionArea(_activeDetailModeId());
      _notifyAreaChanged();
    });
  }

  /// Keeps local selection bounded when the command area list changes.
  @override
  void didUpdateWidget(covariant CommandPanelSubShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedAreaIndex >= widget.areas.length) {
      _selectedAreaIndex = 0;
    }
    if (_activeAreaKey(oldWidget.areas) != _activeAreaKey(widget.areas)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notifyAreaChanged();
      });
    }
    if (oldWidget.selectedDetailModeId != widget.selectedDetailModeId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selectCompanionArea(_activeDetailModeId());
        }
      });
    }
  }

  /// Cleans up filter state.
  @override
  void dispose() {
    _filterController.dispose();
    _detailFilterController.dispose();
    super.dispose();
  }

  /// Builds the reusable command subshell.
  @override
  Widget build(BuildContext context) {
    if (widget.areas.isEmpty) {
      return Padding(
        padding: widget.padding,
        child: PanelEmptyBlock(label: widget.emptyLabel),
      );
    }
    final boundedIndex = _selectedAreaIndex.clamp(0, widget.areas.length - 1);
    final area = widget.areas[boundedIndex];
    final detailModes = _detailModesForArea(area);
    final detailMode = _selectedDetailMode(area, detailModes);
    final detailTabs = _detailTabsForMode(area, detailMode);
    final detailTab = _selectedDetailTab(area, detailMode, detailTabs);
    final detailItems = _detailItemsForMode(area, detailMode);
    final detailItem = _selectedDetailItem(area, detailMode, detailItems);
    final areaFilters =
        widget.areaFiltersBuilder?.call(context, area) ??
        const <CommandPanelFilterOption>[];
    final commandPane = _CommandSubShellCommandPane(
      area: area,
      areas: widget.areas,
      selectedIndex: boundedIndex,
      filterController: _filterController,
      filterHint: widget.filterHint,
      onAreaSelected: _selectArea,
      onTitleTap: widget.areas.length > 1 ? _selectNextArea : null,
      onFilterChanged: (value) => setState(() => _query = value),
      actions: widget.areaActionsBuilder?.call(context, area),
      areaFilters: areaFilters,
      selectedAreaFilterId:
          widget.selectedAreaFilterIdBuilder?.call(area) ?? '',
      onAreaFilterSelected: (option) =>
          widget.onAreaFilterSelected?.call(area, option.id),
      showAreaTabs: widget.showAreaTabs,
      showCollapseButton: widget.showPaneCollapseButtons,
      child: area.builder(_query),
    );
    return Padding(
      padding: widget.padding,
      child: DecoratedBox(
        key: const ValueKey<String>('main-content-sub-shell'),
        decoration: BoxDecoration(
          border: Border.all(color: context.agentAwesomeColors.border),
        ),
        child: widget.showDetailPane
            ? SplitPanelShell(
                split: widget.split,
                gutterWidth: widget.gutterWidth,
                left: commandPane,
                right: _CommandSubShellDetailPane(
                  title: detailTabs.isEmpty && detailMode.id.isNotEmpty
                      ? detailMode.label
                      : widget.detailTitle,
                  modes: detailModes,
                  tabs: detailTabs,
                  selectedMode: detailMode,
                  selectedTab: detailTab,
                  onModeSelected: (mode) => _selectDetailMode(area, mode.id),
                  onTabSelected: (tab) =>
                      _selectDetailTab(area, detailMode, tab.id),
                  actions: widget.detailActionsBuilder?.call(
                    context,
                    area,
                    detailMode,
                  ),
                  items: detailItems,
                  selectedItem: detailItem,
                  onItemSelected: (item) =>
                      _selectDetailItem(area, detailMode, item.id),
                  itemActions: widget.detailItemActionsBuilder?.call(
                    context,
                    area,
                    detailMode,
                    detailItem,
                  ),
                  detailFilterController: _detailFilterController,
                  detailFilterHint: widget.detailFilterHint,
                  showDetailFilter:
                      widget.searchableDetailBuilder != null ||
                      widget.itemDetailBuilder != null ||
                      widget.detailItemsBuilder != null,
                  onDetailFilterChanged: (value) =>
                      setState(() => _detailQuery = value),
                  showCollapseButton: widget.showPaneCollapseButtons,
                  showHeader: widget.showDetailHeader,
                  onTitleTap: detailModes.length > 1
                      ? () =>
                            _selectNextDetailMode(area, detailModes, detailMode)
                      : null,
                  child: _buildDetail(
                    area,
                    detailMode.id,
                    detailTab.id,
                    detailItem,
                  ),
                ),
              )
            : commandPane,
      ),
    );
  }

  /// Selects one command area and clears its local filter.
  void _selectArea(int index) {
    if (_selectedAreaIndex == index) {
      return;
    }
    setState(() {
      _selectedAreaIndex = index;
      _query = '';
      _detailQuery = '';
      _filterController.clear();
      _detailFilterController.clear();
    });
    _notifyAreaChanged();
  }

  /// Selects the next command area from the title interaction.
  void _selectNextArea() {
    if (widget.areas.isEmpty) {
      return;
    }
    _selectArea((_selectedAreaIndex + 1) % widget.areas.length);
  }

  /// Selects the next detail mode from the title interaction.
  void _selectNextDetailMode(
    SwitcherPanelArea area,
    List<CommandPanelDetailMode> modes,
    CommandPanelDetailMode selectedMode,
  ) {
    if (modes.isEmpty) {
      return;
    }
    final currentIndex = modes.indexWhere((mode) => mode.id == selectedMode.id);
    final nextIndex = currentIndex < 0 ? 0 : (currentIndex + 1) % modes.length;
    _selectDetailMode(area, modes[nextIndex].id);
  }

  /// Selects a detail mode for either the whole shell or active area.
  void _selectDetailMode(SwitcherPanelArea area, String modeId) {
    final areaHandler = widget.onAreaDetailModeSelected;
    if (areaHandler != null) {
      _clearDetailFilter();
      areaHandler(area, modeId);
      _selectCompanionArea(modeId);
      return;
    }
    _clearDetailFilter();
    widget.onDetailModeSelected(modeId);
    _selectCompanionArea(modeId);
  }

  /// Selects one tab inside the current right-side mode.
  void _selectDetailTab(
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
    String tabId,
  ) {
    setState(() {
      _selectedTabIds[_tabKey(area, mode)] = tabId;
    });
  }

  /// Selects one right-pane item and clears the item-local search.
  void _selectDetailItem(
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
    String itemId,
  ) {
    _clearDetailFilter();
    widget.onDetailItemSelected?.call(area, mode, itemId);
  }

  /// Builds detail content for either the whole shell or active area.
  Widget _buildDetail(
    SwitcherPanelArea area,
    String modeId,
    String tabId,
    CommandPanelContentItem? item,
  ) {
    final itemBuilder = widget.itemDetailBuilder;
    if (itemBuilder != null) {
      return itemBuilder(area, modeId, item, _detailQuery);
    }
    final searchableBuilder = widget.searchableDetailBuilder;
    if (searchableBuilder != null) {
      return searchableBuilder(area, modeId, _detailQuery);
    }
    final tabbedBuilder = widget.areaTabbedDetailBuilder;
    if (tabbedBuilder != null && tabId.isNotEmpty) {
      return tabbedBuilder(area, modeId, tabId);
    }
    final areaBuilder = widget.areaDetailBuilder;
    if (areaBuilder != null) {
      return areaBuilder(area, modeId);
    }
    return widget.detailBuilder(modeId);
  }

  /// Reports the active command area to the owning shell.
  void _notifyAreaChanged() {
    if (!mounted || widget.areas.isEmpty) {
      return;
    }
    final area =
        widget.areas[_selectedAreaIndex.clamp(0, widget.areas.length - 1)];
    final areaKey = area.id.isEmpty ? area.title : area.id;
    if (_reportedAreaKey == areaKey) {
      return;
    }
    _reportedAreaKey = areaKey;
    widget.onAreaChanged?.call(area);
  }

  /// Returns detail modes for the active command area.
  List<CommandPanelDetailMode> _detailModesForArea(SwitcherPanelArea area) {
    return widget.detailModesBuilder?.call(area) ?? widget.detailModes;
  }

  /// Returns labeled tabs available inside a selected right-side mode.
  List<ShellTab> _detailTabsForMode(
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    return widget.detailTabsBuilder?.call(area, mode) ?? widget.detailTabs;
  }

  /// Returns selectable detail items for the active right-pane mode.
  List<CommandPanelContentItem> _detailItemsForMode(
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    return widget.detailItemsBuilder?.call(area, mode) ??
        const <CommandPanelContentItem>[];
  }

  /// Returns the selected detail item, falling back to the first item.
  CommandPanelContentItem? _selectedDetailItem(
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
    List<CommandPanelContentItem> items,
  ) {
    if (items.isEmpty) {
      return null;
    }
    final selectedId = widget.selectedDetailItemIdBuilder?.call(area, mode);
    if (selectedId != null) {
      for (final item in items) {
        if (item.id == selectedId) {
          return item;
        }
      }
    }
    return items.first;
  }

  /// Returns the selected tab for the selected right-side mode.
  ShellTab _selectedDetailTab(
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
    List<ShellTab> tabs,
  ) {
    if (tabs.isEmpty) {
      return const ShellTab(id: '', label: '', icon: Icons.info_outline);
    }
    final selectedId = _selectedTabIds[_tabKey(area, mode)];
    for (final tab in tabs) {
      if (tab.id == selectedId) {
        return tab;
      }
    }
    return tabs.first;
  }

  /// Returns the selected detail mode, falling back to the first mode.
  CommandPanelDetailMode _selectedDetailMode(
    SwitcherPanelArea area,
    List<CommandPanelDetailMode> modes,
  ) {
    if (modes.isEmpty) {
      return const CommandPanelDetailMode(
        id: '',
        label: 'Details',
        icon: Icons.info_outline,
      );
    }
    final selectedModeId =
        widget.selectedDetailModeIdBuilder?.call(area) ??
        widget.selectedDetailModeId;
    for (final mode in modes) {
      if (mode.id == selectedModeId) {
        return mode;
      }
    }
    return modes.first;
  }

  /// Returns a stable key for the selected area in one area collection.
  String _activeAreaKey(List<SwitcherPanelArea> areas) {
    if (areas.isEmpty) {
      return '';
    }
    final boundedIndex = _selectedAreaIndex.clamp(0, areas.length - 1);
    final area = areas[boundedIndex];
    return area.id.isEmpty ? area.title : area.id;
  }

  /// Returns the active detail mode id for the currently selected area.
  String _activeDetailModeId() {
    if (widget.areas.isEmpty) {
      return '';
    }
    final boundedIndex = _selectedAreaIndex.clamp(0, widget.areas.length - 1);
    final area = widget.areas[boundedIndex];
    final modes = _detailModesForArea(area);
    return _selectedDetailMode(area, modes).id;
  }

  /// Selects a right-mode companion left area when one is declared.
  void _selectCompanionArea(String modeId) {
    final companionAreaId = widget.companionAreaIdBuilder?.call(modeId) ?? '';
    if (companionAreaId.trim().isEmpty) {
      return;
    }
    final companionIndex = widget.areas.indexWhere(
      (area) => area.id == companionAreaId,
    );
    if (companionIndex < 0 || companionIndex == _selectedAreaIndex) {
      return;
    }
    setState(() {
      _selectedAreaIndex = companionIndex;
      _query = '';
      _detailQuery = '';
      _filterController.clear();
      _detailFilterController.clear();
    });
    _notifyAreaChanged();
  }

  /// Clears detail-pane search when the selected item or mode changes.
  void _clearDetailFilter() {
    setState(() {
      _detailQuery = '';
      _detailFilterController.clear();
    });
  }

  /// Returns the local tab-selection key for one area and mode.
  String _tabKey(SwitcherPanelArea area, CommandPanelDetailMode mode) {
    final areaKey = area.id.isEmpty ? area.title : area.id;
    return '$areaKey:${mode.id}';
  }
}
