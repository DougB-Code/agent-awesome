/// Command-panel subshell widgets and navigation affordances.
part of 'panels.dart';

class SwitcherPanelArea {
  /// Creates a selectable panel area.
  const SwitcherPanelArea({
    required this.title,
    required this.icon,
    required this.builder,
    this.id = '',
  });

  /// Stable area id used by global command routing.
  final String id;

  /// Area title.
  final String title;

  /// Area icon.
  final IconData icon;

  /// Builds filtered area content.
  final Widget Function(String query) builder;
}

/// CommandPanelDetailMode describes one selectable detail panel mode.
class CommandPanelDetailMode {
  /// Creates a command-panel detail mode.
  const CommandPanelDetailMode({
    required this.id,
    required this.label,
    required this.icon,
  });

  /// Stable mode id.
  final String id;

  /// Visible detail mode label.
  final String label;

  /// Visible detail mode icon.
  final IconData icon;
}

/// CommandPanelAreaActionsBuilder builds trailing controls for a command area.
typedef CommandPanelAreaActionsBuilder =
    Widget? Function(BuildContext context, SwitcherPanelArea area);

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
    this.onAreaChanged,
    this.areaActionsBuilder,
    this.split = const PanelSplit(left: 0.72, min: 0.46, max: 0.86),
    this.gutterWidth = 12,
    this.padding = const EdgeInsets.fromLTRB(28, 18, 28, 24),
    this.filterHint = 'Filter...',
    this.emptyLabel = 'No command areas configured',
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

  /// Reports the active command area to the owning shell.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds trailing command controls for the selected area.
  final CommandPanelAreaActionsBuilder? areaActionsBuilder;

  /// Split ratio configuration.
  final PanelSplit split;

  /// Horizontal space between command and detail columns.
  final double gutterWidth;

  /// Outer page padding for the subshell.
  final EdgeInsetsGeometry padding;

  /// Placeholder text for the command-area filter.
  final String filterHint;

  /// Empty-state label when there are no command areas.
  final String emptyLabel;

  @override
  State<CommandPanelSubShell> createState() => _CommandPanelSubShellState();
}

class _CommandPanelSubShellState extends State<CommandPanelSubShell> {
  final TextEditingController _filterController = TextEditingController();
  int _selectedAreaIndex = 0;
  String _reportedAreaKey = '';
  String _query = '';

  /// Reports the initial active command area.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
  }

  /// Cleans up filter state.
  @override
  void dispose() {
    _filterController.dispose();
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
    final detailMode = _selectedDetailMode();
    return Padding(
      padding: widget.padding,
      child: SplitPanelShell(
        split: widget.split,
        gutterWidth: widget.gutterWidth,
        left: _CommandSubShellCommandPane(
          area: area,
          areas: widget.areas,
          selectedIndex: boundedIndex,
          filterController: _filterController,
          filterHint: widget.filterHint,
          onAreaSelected: _selectArea,
          onTitleTap: widget.areas.length > 1 ? _selectNextArea : null,
          onFilterChanged: (value) => setState(() => _query = value),
          actions: widget.areaActionsBuilder?.call(context, area),
          child: area.builder(_query),
        ),
        right: _CommandSubShellDetailPane(
          title: detailMode.id.isEmpty ? widget.detailTitle : detailMode.label,
          modes: widget.detailModes,
          selectedMode: detailMode,
          onModeSelected: (mode) => widget.onDetailModeSelected(mode.id),
          onTitleTap: widget.detailModes.length > 1
              ? () => _selectNextDetailMode(detailMode)
              : null,
          child: widget.detailBuilder(detailMode.id),
        ),
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
      _filterController.clear();
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
  void _selectNextDetailMode(CommandPanelDetailMode selectedMode) {
    final modes = widget.detailModes;
    if (modes.isEmpty) {
      return;
    }
    final currentIndex = modes.indexWhere((mode) => mode.id == selectedMode.id);
    final nextIndex = currentIndex < 0 ? 0 : (currentIndex + 1) % modes.length;
    widget.onDetailModeSelected(modes[nextIndex].id);
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

  /// Returns the currently selected detail mode, falling back to the first mode.
  CommandPanelDetailMode _selectedDetailMode() {
    if (widget.detailModes.isEmpty) {
      return const CommandPanelDetailMode(
        id: '',
        label: 'Details',
        icon: Icons.info_outline,
      );
    }
    for (final mode in widget.detailModes) {
      if (mode.id == widget.selectedDetailModeId) {
        return mode;
      }
    }
    return widget.detailModes.first;
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
}

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
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeSurfaceGradient,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
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
                    if (collapseScope != null)
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _CommandSubShellAreaTabs(
                        areas: areas,
                        selectedIndex: selectedIndex,
                        onSelected: onAreaSelected,
                      ),
                    ),
                    if (actions != null) ...<Widget>[
                      const SizedBox(width: 12),
                      actions!,
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _CommandSubShellFilterField(
                  controller: filterController,
                  hintText: filterHint,
                  onChanged: onFilterChanged,
                ),
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

/// _CommandSubShellDetailPane renders detail mode tabs and content.
class _CommandSubShellDetailPane extends StatelessWidget {
  const _CommandSubShellDetailPane({
    required this.title,
    required this.modes,
    required this.selectedMode,
    required this.onModeSelected,
    required this.onTitleTap,
    required this.child,
  });

  final String title;
  final List<CommandPanelDetailMode> modes;
  final CommandPanelDetailMode selectedMode;
  final ValueChanged<CommandPanelDetailMode> onModeSelected;
  final VoidCallback? onTitleTap;
  final Widget child;

  /// Builds the detail column.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final collapseScope = SplitPaneCollapseScope.maybeOf(context);
    if (collapseScope?.collapsed ?? false) {
      return _CommandSubShellCollapsedPane(
        title: title,
        icon: selectedMode.icon,
        collapseScope: collapseScope!,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeSurfaceGradient,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
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
                      child: PanelSectionLabel(title, onTap: onTitleTap),
                    ),
                    if (collapseScope != null)
                      PanelCollapseButton(
                        expanded: true,
                        direction: collapseScope.side.direction,
                        onPressed: collapseScope.onToggle,
                        expandedTooltip: 'Collapse details column',
                        collapsedTooltip: 'Expand details column',
                      ),
                  ],
                ),
                if (modes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _CommandSubShellDetailTabs(
                    modes: modes,
                    selectedMode: selectedMode,
                    onSelected: onModeSelected,
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

/// _CommandSubShellFilterField renders the local fuzzy-search input.
class _CommandSubShellFilterField extends StatelessWidget {
  const _CommandSubShellFilterField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  /// Builds the local command-area filter.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SizedBox(
      height: 38,
      child: TextField(
        key: const ValueKey<String>('command-subshell-filter'),
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 18, color: colors.muted),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          hintText: hintText,
          hintStyle: TextStyle(color: colors.muted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          filled: true,
          fillColor: colors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.searchBorder),
          ),
        ),
      ),
    );
  }
}

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

/// _CommandSubShellCollapsedPane renders a collapsed split-pane rail.
class _CommandSubShellCollapsedPane extends StatelessWidget {
  const _CommandSubShellCollapsedPane({
    required this.title,
    required this.icon,
    required this.collapseScope,
  });

  final String title;
  final IconData icon;
  final SplitPaneCollapseScope collapseScope;

  /// Builds the compact collapsed column.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeSurfaceGradient,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          children: <Widget>[
            PanelCollapseButton(
              expanded: false,
              direction: collapseScope.side.direction,
              onPressed: collapseScope.onToggle,
              expandedTooltip: 'Collapse column',
              collapsedTooltip: 'Expand column',
            ),
            const SizedBox(height: 14),
            Icon(icon, size: 20, color: colors.green),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
