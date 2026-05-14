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
    this.onAreaChanged,
    this.areaActionsBuilder,
    this.split = const PanelSplit(left: 0.72, min: 0.46, max: 0.86),
    this.gutterWidth = 12,
    this.padding = const EdgeInsets.fromLTRB(28, 18, 28, 24),
    this.filterHint = 'Filter...',
    this.emptyLabel = 'No command areas configured',
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

  /// Whether the detail pane renders its own title and mode tabs.
  final bool showDetailHeader;

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
          showHeader: widget.showDetailHeader,
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
