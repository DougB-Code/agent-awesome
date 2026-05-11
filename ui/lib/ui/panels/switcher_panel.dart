/// Single-surface switcher panel widget.
part of 'panels.dart';

class SwitcherPanel extends StatefulWidget {
  /// Creates a switchable high-density panel.
  const SwitcherPanel({
    super.key,
    required this.areas,
    this.titleControl,
    this.showAreaQuickSelect = true,
    this.onAreaChanged,
  });

  /// Selectable content areas.
  final List<SwitcherPanelArea> areas;

  /// Optional control shown beside the active panel title.
  final Widget? titleControl;

  /// Whether to show compact icon buttons for the selectable areas.
  final bool showAreaQuickSelect;

  /// Reports the active area to the owning shell.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  @override
  State<SwitcherPanel> createState() => _SwitcherPanelState();
}

class _SwitcherPanelState extends State<SwitcherPanel> {
  int _selectedIndex = 0;
  String _reportedAreaKey = '';

  /// Reports the initially selected area after the first layout pass.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyAreaChanged();
    });
  }

  /// Reports the active area when the area collection changes.
  @override
  void didUpdateWidget(covariant SwitcherPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= widget.areas.length) {
      _selectedIndex = 0;
    }
    if (_activeAreaKey(oldWidget.areas) != _activeAreaKey(widget.areas)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notifyAreaChanged();
      });
    }
  }

  /// Builds a dense command content panel with area selection and filtering.
  @override
  Widget build(BuildContext context) {
    final areas = widget.areas;
    final boundedIndex = _selectedIndex.clamp(0, areas.length - 1);
    return CollectionSwitcherPanel<SwitcherPanelArea>(
      title: areas[boundedIndex].title,
      selectedId: boundedIndex.toString(),
      items: <CollectionPanelItem<SwitcherPanelArea>>[
        for (var index = 0; index < areas.length; index++)
          CollectionPanelItem<SwitcherPanelArea>(
            id: index.toString(),
            label: areas[index].title,
            icon: areas[index].icon,
            value: areas[index],
          ),
      ],
      onSelect: (id) => _selectArea(int.parse(id)),
      builder: (area, query) => area.builder(query),
      titleControl: widget.titleControl,
      onTitleTap: areas.length > 1 ? _selectNextArea : null,
      showQuickSelect: widget.showAreaQuickSelect,
      selectionWidth: 150,
      filterHint: 'Filter...',
      filterKeyBuilder: (item) => 'command-panel-filter-${item?.label}',
    );
  }

  void _selectNextArea() {
    _selectArea((_selectedIndex + 1) % widget.areas.length);
  }

  void _selectArea(int index) {
    if (_selectedIndex == index) {
      return;
    }
    setState(() => _selectedIndex = index);
    _notifyAreaChanged();
  }

  void _notifyAreaChanged() {
    if (!mounted || widget.areas.isEmpty) {
      return;
    }
    final boundedIndex = _selectedIndex.clamp(0, widget.areas.length - 1);
    final area = widget.areas[boundedIndex];
    final areaKey = area.id.isNotEmpty ? area.id : area.title;
    if (_reportedAreaKey == areaKey) {
      return;
    }
    _reportedAreaKey = areaKey;
    widget.onAreaChanged?.call(area);
  }

  String _activeAreaKey(List<SwitcherPanelArea> areas) {
    if (areas.isEmpty) {
      return '';
    }
    final boundedIndex = _selectedIndex.clamp(0, areas.length - 1);
    final area = areas[boundedIndex];
    return area.id.isNotEmpty ? area.id : area.title;
  }
}
