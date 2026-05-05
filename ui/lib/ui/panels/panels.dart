/// Provides reusable panel primitives for Aurora section workspaces.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';

/// PanelSplit describes the default and allowed split ratios for two panels.
class PanelSplit {
  /// Creates split ratio constraints for a two-panel workspace.
  const PanelSplit({required this.left, this.min = 0.2, this.max = 0.8});

  /// Initial fraction assigned to the left panel.
  final double left;

  /// Minimum allowed left panel fraction while dragging.
  final double min;

  /// Maximum allowed left panel fraction while dragging.
  final double max;
}

/// SectionLayout describes one two-panel app section composition.
class SectionLayout {
  /// Creates a section layout with reusable panels.
  const SectionLayout({
    required this.split,
    required this.left,
    required this.right,
  });

  /// Split ratio configuration.
  final PanelSplit split;

  /// Left panel widget.
  final Widget left;

  /// Right panel widget.
  final Widget right;
}

/// PanelCollapseDirection identifies which edge a panel collapses toward.
enum PanelCollapseDirection {
  /// Collapse toward the left edge.
  left,

  /// Collapse toward the right edge.
  right,
}

/// PanelCollapseButton renders the shared sidebar and command-panel toggle.
class PanelCollapseButton extends StatelessWidget {
  /// Creates a compact collapse or expand button.
  const PanelCollapseButton({
    super.key,
    required this.expanded,
    required this.onPressed,
    this.direction = PanelCollapseDirection.left,
    this.expandedTooltip = 'Collapse panel',
    this.collapsedTooltip = 'Expand panel',
  });

  /// Whether the controlled surface is currently expanded.
  final bool expanded;

  /// Collapse or expand callback.
  final VoidCallback onPressed;

  /// Edge the surface collapses toward.
  final PanelCollapseDirection direction;

  /// Tooltip shown while the surface is expanded.
  final String expandedTooltip;

  /// Tooltip shown while the surface is collapsed.
  final String collapsedTooltip;

  /// Builds the shared icon-only collapse affordance.
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: expanded ? expandedTooltip : collapsedTooltip,
      child: IconButton(
        alignment: Alignment.topCenter,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        onPressed: onPressed,
        icon: Icon(_icon, color: AuroraColors.muted, size: 20),
      ),
    );
  }

  IconData get _icon {
    if (!expanded) {
      return Icons.menu;
    }
    return switch (direction) {
      PanelCollapseDirection.left => Icons.keyboard_double_arrow_left,
      PanelCollapseDirection.right => Icons.keyboard_double_arrow_right,
    };
  }
}

enum _SplitPaneSide {
  left,
  right;

  PanelCollapseDirection get direction {
    return switch (this) {
      _SplitPaneSide.left => PanelCollapseDirection.left,
      _SplitPaneSide.right => PanelCollapseDirection.right,
    };
  }
}

class _SplitPaneCollapseScope extends InheritedWidget {
  const _SplitPaneCollapseScope({
    required this.side,
    required this.collapsed,
    required this.onToggle,
    required super.child,
  });

  final _SplitPaneSide side;
  final bool collapsed;
  final VoidCallback onToggle;

  /// Returns the closest split-pane collapse state, if present.
  static _SplitPaneCollapseScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_SplitPaneCollapseScope>();
  }

  @override
  bool updateShouldNotify(covariant _SplitPaneCollapseScope oldWidget) {
    return side != oldWidget.side ||
        collapsed != oldWidget.collapsed ||
        onToggle != oldWidget.onToggle;
  }
}

/// SplitPanelShell renders a reusable resizable two-panel workspace.
class SplitPanelShell extends StatefulWidget {
  /// Creates a two-panel workspace shell.
  const SplitPanelShell({
    super.key,
    required this.left,
    required this.right,
    this.split = const PanelSplit(left: 0.5),
  });

  /// Left panel widget.
  final Widget left;

  /// Right panel widget.
  final Widget right;

  /// Split ratio configuration.
  final PanelSplit split;

  @override
  State<SplitPanelShell> createState() => _SplitPanelShellState();
}

class _SplitPanelShellState extends State<SplitPanelShell> {
  static const double _collapsedPaneWidth = 72;
  static const double _handleHitWidth = 12;

  late double _leftPaneFraction = widget.split.left;
  bool _leftPaneCollapsed = false;
  bool _rightPaneCollapsed = false;

  /// Updates the initial split when switching section layouts.
  @override
  void didUpdateWidget(covariant SplitPanelShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sectionChanged =
        oldWidget.left.runtimeType != widget.left.runtimeType ||
        oldWidget.right.runtimeType != widget.right.runtimeType;
    if (oldWidget.split.left != widget.split.left || sectionChanged) {
      _leftPaneFraction = widget.split.left;
      _leftPaneCollapsed = false;
      _rightPaneCollapsed = false;
    }
  }

  /// Builds the split shell and drag handle.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 940) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(height: constraints.maxHeight, child: widget.left),
                SizedBox(height: constraints.maxHeight, child: widget.right),
              ],
            ),
          );
        }
        final totalWidth = constraints.maxWidth;
        final leftWidth = _leftPaneCollapsed
            ? _collapsedPaneWidth
            : _rightPaneCollapsed
            ? totalWidth - _collapsedPaneWidth
            : totalWidth * _leftPaneFraction;
        final rightWidth = totalWidth - leftWidth;
        final canResize = !_leftPaneCollapsed && !_rightPaneCollapsed;
        return Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: leftWidth,
              child: _SplitPaneCollapseScope(
                side: _SplitPaneSide.left,
                collapsed: _leftPaneCollapsed,
                onToggle: _toggleLeftPane,
                child: widget.left,
              ),
            ),
            Positioned(
              left: leftWidth,
              top: 0,
              bottom: 0,
              width: rightWidth,
              child: _SplitPaneCollapseScope(
                side: _SplitPaneSide.right,
                collapsed: _rightPaneCollapsed,
                onToggle: _toggleRightPane,
                child: widget.right,
              ),
            ),
            Positioned(
              left: leftWidth - (_handleHitWidth / 2),
              top: 0,
              bottom: 0,
              width: _handleHitWidth,
              child: canResize
                  ? _SplitPanelHandle(
                      onDragUpdate: (details) =>
                          _resizePanes(details, totalWidth),
                    )
                  : const _SplitPanelDivider(),
            ),
          ],
        );
      },
    );
  }

  void _resizePanes(DragUpdateDetails details, double paneWidth) {
    if (paneWidth <= 0) {
      return;
    }
    setState(() {
      _leftPaneFraction =
          ((_leftPaneFraction * paneWidth + details.delta.dx) / paneWidth)
              .clamp(widget.split.min, widget.split.max);
    });
  }

  void _toggleLeftPane() {
    setState(() {
      _leftPaneCollapsed = !_leftPaneCollapsed;
      if (_leftPaneCollapsed) {
        _rightPaneCollapsed = false;
      }
    });
  }

  void _toggleRightPane() {
    setState(() {
      _rightPaneCollapsed = !_rightPaneCollapsed;
      if (_rightPaneCollapsed) {
        _leftPaneCollapsed = false;
      }
    });
  }
}

class _SplitPanelDivider extends StatelessWidget {
  const _SplitPanelDivider();

  /// Builds the fixed divider shown next to a collapsed pane.
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: AuroraColors.border,
      ),
    );
  }
}

class _SplitPanelHandle extends StatefulWidget {
  const _SplitPanelHandle({required this.onDragUpdate});

  final GestureDragUpdateCallback onDragUpdate;

  @override
  State<_SplitPanelHandle> createState() => _SplitPanelHandleState();
}

class _SplitPanelHandleState extends State<_SplitPanelHandle> {
  bool _active = false;

  /// Builds the draggable divider for split panel panes.
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => _setActive(true),
      onExit: (_) => _setActive(false),
      child: GestureDetector(
        key: const ValueKey<String>('command-split-handle'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _setActive(true),
        onHorizontalDragUpdate: widget.onDragUpdate,
        onHorizontalDragEnd: (_) => _setActive(false),
        onHorizontalDragCancel: () => _setActive(false),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: AuroraColors.border,
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: _active ? 4 : 0,
              color: AuroraColors.green,
            ),
          ],
        ),
      ),
    );
  }

  void _setActive(bool value) {
    if (_active == value) {
      return;
    }
    setState(() {
      _active = value;
    });
  }
}

/// SwitcherPanelArea describes one selectable content area.
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

/// SwitcherPanel is a high-density command panel with area and filter controls.
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

/// SearchPickerOption describes one searchable dropdown item.
class SearchPickerOption<T> {
  /// Creates a typed option for searchable picker dropdowns.
  const SearchPickerOption({
    required this.value,
    required this.title,
    this.subtitle = '',
    this.searchText = '',
    this.icon = Icons.circle_outlined,
  });

  /// Typed value returned when the option is selected.
  final T value;

  /// Primary visible label.
  final String title;

  /// Secondary visible label.
  final String subtitle;

  /// Extra text used by the fuzzy search matcher.
  final String searchText;

  /// Leading icon for the option.
  final IconData icon;
}

/// SearchPickerDropdown opens a reusable fuzzy-search dropdown menu.
class SearchPickerDropdown<T> extends StatelessWidget {
  /// Creates a searchable picker button.
  const SearchPickerDropdown({
    super.key,
    required this.label,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.tooltip = 'Select',
    this.emptyLabel = 'No items found',
    this.width = 220,
    this.onDelete,
    this.deleteTooltip = 'Delete',
  });

  /// Button label for the current selection.
  final String label;

  /// Options shown inside the popup.
  final List<SearchPickerOption<T>> options;

  /// Current selected value.
  final T? selectedValue;

  /// Called when the user selects an option.
  final ValueChanged<T> onSelected;

  /// Tooltip for the button.
  final String tooltip;

  /// Empty-state text for filtered results.
  final String emptyLabel;

  /// Button width.
  final double width;

  /// Optional trailing delete action for each option.
  final FutureOr<void> Function(T value)? onDelete;

  /// Tooltip shown for the optional trailing delete action.
  final String deleteTooltip;

  /// Builds a compact button that launches the search menu.
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: width,
        height: 38,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            backgroundColor: AuroraColors.surface,
            foregroundColor: AuroraColors.ink,
            side: const BorderSide(color: AuroraColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: () => _showPicker(context),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the searchable picker overlay and emits a selected value.
  Future<void> _showPicker(BuildContext context) async {
    final selected = await showDialog<T>(
      context: context,
      builder: (dialogContext) {
        return _SearchPickerDialog<T>(
          options: options,
          selectedValue: selectedValue,
          emptyLabel: emptyLabel,
          onDelete: onDelete,
          deleteTooltip: deleteTooltip,
        );
      },
    );
    if (selected != null) {
      onSelected(selected);
    }
  }
}

class _SearchPickerDialog<T> extends StatefulWidget {
  const _SearchPickerDialog({
    required this.options,
    required this.selectedValue,
    required this.emptyLabel,
    required this.onDelete,
    required this.deleteTooltip,
  });

  final List<SearchPickerOption<T>> options;
  final T? selectedValue;
  final String emptyLabel;
  final FutureOr<void> Function(T value)? onDelete;
  final String deleteTooltip;

  /// Creates dialog state for filtering picker options.
  @override
  State<_SearchPickerDialog<T>> createState() => _SearchPickerDialogState<T>();
}

class _SearchPickerDialogState<T> extends State<_SearchPickerDialog<T>> {
  final TextEditingController _controller = TextEditingController();
  late List<SearchPickerOption<T>> _options = widget.options.toList();
  final List<T> _deleting = <T>[];
  String _query = '';

  /// Keeps dialog options synchronized when the picker is rebuilt.
  @override
  void didUpdateWidget(covariant _SearchPickerDialog<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options != widget.options) {
      _options = widget.options.toList();
    }
  }

  /// Cleans up the search field.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Builds the fuzzy-search picker popup.
  @override
  Widget build(BuildContext context) {
    final options = _options.where(_matchesQuery).toList();
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 90, left: 24, right: 24),
      backgroundColor: AuroraColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: TextField(
                key: const ValueKey<String>('search-picker-filter'),
                controller: _controller,
                autofocus: true,
                onChanged: (value) => setState(() {
                  _query = value;
                }),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 18,
                    color: AuroraColors.muted,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  hintText: 'Search...',
                  hintStyle: const TextStyle(color: AuroraColors.muted),
                  filled: true,
                  fillColor: const Color(0xfffffcf8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AuroraColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AuroraColors.border),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AuroraColors.border),
            Flexible(
              child: options.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          widget.emptyLabel,
                          style: const TextStyle(color: AuroraColors.muted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options[index];
                        return _SearchPickerOptionTile<T>(
                          option: option,
                          selected: option.value == widget.selectedValue,
                          deleting: _deleting.contains(option.value),
                          onDelete: widget.onDelete == null
                              ? null
                              : () => _deleteOption(option),
                          deleteTooltip: widget.deleteTooltip,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Reports whether an option matches the current fuzzy query.
  bool _matchesQuery(SearchPickerOption<T> option) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final target = '${option.title} ${option.subtitle} ${option.searchText}'
        .toLowerCase();
    var position = 0;
    for (final unit in query.codeUnits) {
      position = target.indexOf(String.fromCharCode(unit), position);
      if (position == -1) {
        return false;
      }
      position++;
    }
    return true;
  }

  /// Deletes an option through the picker callback and removes it locally.
  Future<void> _deleteOption(SearchPickerOption<T> option) async {
    final onDelete = widget.onDelete;
    if (onDelete == null || _deleting.contains(option.value)) {
      return;
    }
    setState(() {
      _deleting.add(option.value);
    });
    var deleted = false;
    try {
      await onDelete(option.value);
      deleted = true;
    } catch (_) {
      deleted = false;
    } finally {
      if (mounted) {
        setState(() {
          _deleting.remove(option.value);
        });
      }
    }
    if (!mounted || !deleted) {
      return;
    }
    setState(() {
      _options = _options
          .where((candidate) => candidate.value != option.value)
          .toList();
    });
  }
}

class _SearchPickerOptionTile<T> extends StatelessWidget {
  const _SearchPickerOptionTile({
    required this.option,
    required this.selected,
    required this.deleting,
    required this.onDelete,
    required this.deleteTooltip,
  });

  final SearchPickerOption<T> option;
  final bool selected;
  final bool deleting;
  final VoidCallback? onDelete;
  final String deleteTooltip;

  /// Builds one selectable row in the search picker.
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        selected ? Icons.check_circle : option.icon,
        color: selected ? AuroraColors.green : AuroraColors.muted,
      ),
      title: Text(
        option.title,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: option.subtitle.isEmpty
          ? null
          : Text(
              option.subtitle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AuroraColors.muted),
            ),
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: deleteTooltip,
              onPressed: deleting ? null : onDelete,
              icon: deleting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
            ),
      onTap: () => Navigator.of(context).pop(option.value),
    );
  }
}

/// CollectionPanelItem describes one dynamic content item.
class CollectionPanelItem<T> {
  /// Creates a dynamic collection panel item.
  const CollectionPanelItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.value,
    this.detail = '',
    this.badge = '',
  });

  /// Stable item identifier.
  final String id;

  /// Display label.
  final String label;

  /// Display icon.
  final IconData icon;

  /// Backing value for the selected item editor.
  final T value;

  /// Optional supporting detail.
  final String detail;

  /// Optional status badge.
  final String badge;
}

/// CollectionSwitcherPanel renders dynamic same-type content panels.
class CollectionSwitcherPanel<T> extends StatefulWidget {
  /// Creates a managed collection switcher panel.
  const CollectionSwitcherPanel({
    super.key,
    required this.title,
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.builder,
    this.titleControl,
    this.onTitleTap,
    this.onCreate,
    this.onDuplicate,
    this.onDelete,
    this.emptyLabel = 'No items configured',
    this.showQuickSelect = true,
    this.selectionWidth = 210,
    this.filterHint = 'Filter selected...',
    this.filterKeyBuilder,
  });

  /// Panel title.
  final String title;

  /// Dynamic collection items.
  final List<CollectionPanelItem<T>> items;

  /// Currently selected item id.
  final String? selectedId;

  /// Selection callback.
  final ValueChanged<String> onSelect;

  /// Selected item content builder.
  final Widget Function(T value, String query) builder;

  /// Optional control shown instead of the item dropdown.
  final Widget? titleControl;

  /// Optional callback when the title label is clicked.
  final VoidCallback? onTitleTap;

  /// Optional create callback.
  final VoidCallback? onCreate;

  /// Optional duplicate callback for the selected item.
  final ValueChanged<T>? onDuplicate;

  /// Optional delete callback for the selected item.
  final ValueChanged<T>? onDelete;

  /// Empty collection label.
  final String emptyLabel;

  /// Whether to show quick icon selectors for items.
  final bool showQuickSelect;

  /// Width for the compact dropdown selector.
  final double selectionWidth;

  /// Placeholder text for the filter field.
  final String filterHint;

  /// Optional stable key builder for the filter field.
  final String Function(CollectionPanelItem<T>? selectedItem)? filterKeyBuilder;

  @override
  State<CollectionSwitcherPanel<T>> createState() =>
      _CollectionSwitcherPanelState<T>();
}

class _CollectionSwitcherPanelState<T>
    extends State<CollectionSwitcherPanel<T>> {
  final TextEditingController _filterController = TextEditingController();
  String _query = '';

  /// Clears filter text when the selected item changes externally.
  @override
  void didUpdateWidget(covariant CollectionSwitcherPanel<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) {
      _query = '';
      _filterController.clear();
    }
  }

  /// Cleans up filter input state.
  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  /// Builds a high-density panel for a dynamic collection.
  @override
  Widget build(BuildContext context) {
    final selectedItem = _selectedItem();
    final collapseScope = _SplitPaneCollapseScope.maybeOf(context);
    final hasMultipleItems = widget.items.length > 1;
    final hasCollectionActions =
        widget.onCreate != null ||
        widget.onDuplicate != null ||
        widget.onDelete != null;
    final canSelectItems =
        widget.items.isNotEmpty && (hasMultipleItems || hasCollectionActions);
    final showQuickSelect = widget.showQuickSelect && canSelectItems;
    final titleTap =
        widget.onTitleTap ?? (hasMultipleItems ? _selectNextItem : null);
    final titleText = widget.title.toUpperCase();
    if (collapseScope?.collapsed ?? false) {
      return _CollectionCollapsedRail<T>(
        items: widget.items,
        selectedId: selectedItem?.id,
        onSelect: _selectItem,
        onExpand: collapseScope!.onToggle,
        onCreate: widget.onCreate,
      );
    }
    return ColoredBox(
      color: const Color(0xfffffcf8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Column(
              children: <Widget>[
                SizedBox(
                  height: 38,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: titleTap == null
                            ? Text(
                                titleText,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AuroraColors.muted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                ),
                              )
                            : InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: titleTap,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    titleText,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AuroraColors.muted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      if (widget.titleControl != null)
                        widget.titleControl!
                      else if (canSelectItems)
                        _CollectionPanelSelect<T>(
                          items: widget.items,
                          selectedId: selectedItem?.id,
                          width: widget.selectionWidth,
                          onChanged: _selectItem,
                        ),
                      if (collapseScope != null) ...<Widget>[
                        const SizedBox(width: 8),
                        PanelCollapseButton(
                          expanded: true,
                          direction: collapseScope.side.direction,
                          onPressed: collapseScope.onToggle,
                        ),
                      ],
                    ],
                  ),
                ),
                if (showQuickSelect) ...<Widget>[
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
                              for (final item in widget.items)
                                _CollectionQuickSelect(
                                  icon: item.icon,
                                  selected: item.id == selectedItem?.id,
                                  tooltip: item.label,
                                  onPressed: () => _selectItem(item.id),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.onCreate != null)
                        _CollectionActionButton(
                          icon: Icons.add,
                          tooltip: 'Add',
                          onPressed: widget.onCreate,
                        ),
                      if (widget.onDuplicate != null)
                        _CollectionActionButton(
                          icon: Icons.content_copy,
                          tooltip: 'Duplicate',
                          onPressed: selectedItem == null
                              ? null
                              : () => widget.onDuplicate!(selectedItem.value),
                        ),
                      if (widget.onDelete != null)
                        _CollectionActionButton(
                          icon: Icons.delete_outline,
                          tooltip: 'Remove',
                          onPressed: selectedItem == null
                              ? null
                              : () => widget.onDelete!(selectedItem.value),
                        ),
                    ],
                  ),
                ] else if (hasCollectionActions) ...<Widget>[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: <Widget>[
                        if (widget.onCreate != null)
                          _CollectionActionButton(
                            icon: Icons.add,
                            tooltip: 'Add',
                            onPressed: widget.onCreate,
                          ),
                        if (widget.onDuplicate != null)
                          _CollectionActionButton(
                            icon: Icons.content_copy,
                            tooltip: 'Duplicate',
                            onPressed: selectedItem == null
                                ? null
                                : () => widget.onDuplicate!(selectedItem.value),
                          ),
                        if (widget.onDelete != null)
                          _CollectionActionButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Remove',
                            onPressed: selectedItem == null
                                ? null
                                : () => widget.onDelete!(selectedItem.value),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: 38,
                  child: TextField(
                    key: ValueKey<String>(
                      widget.filterKeyBuilder?.call(selectedItem) ??
                          'collection-panel-filter-${widget.title}',
                    ),
                    controller: _filterController,
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 18,
                        color: AuroraColors.muted,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      hintText: widget.filterHint,
                      hintStyle: const TextStyle(color: AuroraColors.muted),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      filled: true,
                      fillColor: AuroraColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AuroraColors.border,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AuroraColors.border,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AuroraColors.border),
          Expanded(
            child: selectedItem == null
                ? _CollectionEmptyState(
                    label: widget.emptyLabel,
                    onCreate: widget.onCreate,
                  )
                : widget.builder(selectedItem.value, _query),
          ),
        ],
      ),
    );
  }

  CollectionPanelItem<T>? _selectedItem() {
    if (widget.items.isEmpty) {
      return null;
    }
    final selectedId = widget.selectedId;
    if (selectedId != null) {
      for (final item in widget.items) {
        if (item.id == selectedId) {
          return item;
        }
      }
    }
    return widget.items.first;
  }

  void _selectItem(String id) {
    setState(() {
      _query = '';
      _filterController.clear();
    });
    widget.onSelect(id);
  }

  /// Selects the next item when the command title is clicked.
  void _selectNextItem() {
    final items = widget.items;
    if (items.length < 2) {
      return;
    }
    final selectedItem = _selectedItem();
    final selectedIndex = selectedItem == null
        ? -1
        : items.indexWhere((item) => item.id == selectedItem.id);
    final nextIndex = (selectedIndex + 1) % items.length;
    _selectItem(items[nextIndex].id);
  }
}

class _CollectionCollapsedRail<T> extends StatelessWidget {
  const _CollectionCollapsedRail({
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.onExpand,
    this.onCreate,
  });

  final List<CollectionPanelItem<T>> items;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onExpand;
  final VoidCallback? onCreate;

  /// Builds the collapsed command-panel rail with vertical quick selectors.
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xfffffcf8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            PanelCollapseButton(expanded: false, onPressed: onExpand),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CollectionQuickSelect(
                        icon: item.icon,
                        selected: item.id == selectedId,
                        tooltip: item.label,
                        onPressed: () => onSelect(item.id),
                      ),
                    ),
                ],
              ),
            ),
            if (onCreate != null) ...<Widget>[
              const SizedBox(height: 10),
              Tooltip(
                message: 'Add',
                child: IconButton.outlined(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 18),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CollectionPanelSelect<T> extends StatelessWidget {
  const _CollectionPanelSelect({
    required this.items,
    required this.selectedId,
    required this.width,
    required this.onChanged,
  });

  final List<CollectionPanelItem<T>> items;
  final String? selectedId;
  final double width;
  final ValueChanged<String> onChanged;

  /// Builds the compact item dropdown beside a collection title.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 38,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AuroraColors.surface,
          border: Border.all(color: AuroraColors.border),
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
                  child: _CollectionDropdownLabel(item: item),
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

class _CollectionDropdownLabel<T> extends StatelessWidget {
  const _CollectionDropdownLabel({required this.item});

  final CollectionPanelItem<T> item;

  /// Builds one collection dropdown label.
  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(item.icon, size: 16, color: AuroraColors.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(item.label, softWrap: false)),
        if (item.badge.isNotEmpty) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            item.badge,
            style: const TextStyle(color: AuroraColors.green, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _CollectionQuickSelect extends StatelessWidget {
  const _CollectionQuickSelect({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onPressed;

  /// Builds one compact selector for a collection item.
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            color: selected ? AuroraColors.greenSoft : AuroraColors.panel,
            border: Border.all(
              color: selected ? AuroraColors.green : AuroraColors.border,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: selected ? AuroraColors.green : AuroraColors.muted,
          ),
        ),
      ),
    );
  }
}

class _CollectionActionButton extends StatelessWidget {
  const _CollectionActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Builds one icon-only collection action button.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: tooltip,
        child: IconButton.outlined(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _CollectionEmptyState extends StatelessWidget {
  const _CollectionEmptyState({required this.label, required this.onCreate});

  final String label;
  final VoidCallback? onCreate;

  /// Builds an empty collection state with an optional create action.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: const TextStyle(color: AuroraColors.muted)),
          if (onCreate != null) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ],
      ),
    );
  }
}

/// PanelEmptyState renders a standard empty state for filtered panel content.
class PanelEmptyState extends StatelessWidget {
  /// Creates a panel empty state for a search query.
  const PanelEmptyState({super.key, required this.query});

  /// Filter query that produced no results.
  final String query;

  /// Builds a compact empty state for filtered command panel content.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No results for "$query"',
        style: const TextStyle(color: AuroraColors.muted),
      ),
    );
  }
}

/// MenuPanelItem describes one item in a reusable menu panel.
class MenuPanelItem {
  /// Creates a menu item for panel navigation.
  const MenuPanelItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.detail,
  });

  /// Stable selection key.
  final String key;

  /// Display label.
  final String label;

  /// Display icon.
  final IconData icon;

  /// Short supporting description.
  final String detail;
}

/// MenuPanel renders a vertical sub-navigation panel.
class MenuPanel extends StatelessWidget {
  /// Creates a reusable menu panel.
  const MenuPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.selectedKey,
    required this.onSelected,
  });

  /// Panel title.
  final String title;

  /// Supporting subtitle.
  final String subtitle;

  /// Menu items.
  final List<MenuPanelItem> items;

  /// Currently selected item key.
  final String selectedKey;

  /// Selection callback.
  final ValueChanged<String> onSelected;

  /// Builds the menu panel.
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xfffffcf8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.displayMedium),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(color: AuroraColors.muted),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AuroraColors.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                for (final item in items)
                  _MenuPanelTile(
                    item: item,
                    selected: selectedKey == item.key,
                    onTap: () => onSelected(item.key),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuPanelTile extends StatelessWidget {
  const _MenuPanelTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final MenuPanelItem item;
  final bool selected;
  final VoidCallback onTap;

  /// Builds one menu panel tile.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AuroraColors.greenSoft : AuroraColors.surface,
            border: Border.all(
              color: selected ? AuroraColors.green : AuroraColors.border,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                item.icon,
                color: selected ? AuroraColors.green : AuroraColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.label,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AuroraColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AuroraColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// PanelSectionBlock renders a reusable bordered workspace surface.
class PanelSectionBlock extends StatelessWidget {
  /// Creates a compact reusable section block.
  const PanelSectionBlock({super.key, required this.child});

  /// Content shown inside the block.
  final Widget child;

  /// Builds the shared bordered panel surface.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfffffcf8),
        border: Border.all(color: AuroraColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

/// PanelSectionLabel renders a compact uppercase section label.
class PanelSectionLabel extends StatelessWidget {
  /// Creates a reusable uppercase section label.
  const PanelSectionLabel(this.label, {super.key});

  final String label;

  /// Builds the uppercase label shared by panel section cards.
  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AuroraColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 3,
      ),
    );
  }
}

/// PanelBadge renders a compact metadata/status badge.
class PanelBadge extends StatelessWidget {
  /// Creates a reusable status badge.
  const PanelBadge({super.key, required this.label});

  /// Badge text.
  final String label;

  /// Builds a dense bordered badge.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AuroraColors.panel,
        border: Border.all(color: AuroraColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AuroraColors.green,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// PanelEmptyBlock renders a bordered empty state block.
class PanelEmptyBlock extends StatelessWidget {
  /// Creates a reusable empty state block.
  const PanelEmptyBlock({super.key, required this.label});

  /// Empty-state text.
  final String label;

  /// Builds a compact bordered empty block.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfffffcf8),
        border: Border.all(color: AuroraColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: SelectableText(
            label,
            style: const TextStyle(color: AuroraColors.muted),
          ),
        ),
      ),
    );
  }
}

/// StatusRow renders one service/process status line.
class StatusRow extends StatelessWidget {
  /// Creates a reusable status row.
  const StatusRow({
    super.key,
    required this.name,
    required this.url,
    required this.state,
    required this.message,
  });

  /// Status subject name.
  final String name;

  /// Endpoint or path detail.
  final String url;

  /// Current connection state.
  final ConnectionStateKind state;

  /// Supporting status message.
  final String message;

  /// Builds one reusable connection status row.
  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      ConnectionStateKind.connected => AuroraColors.green,
      ConnectionStateKind.disconnected => AuroraColors.coral,
      ConnectionStateKind.unknown => AuroraColors.muted,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xfffffcf8),
        border: Border.all(color: AuroraColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 14),
          SizedBox(
            width: 160,
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(child: Text(url, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              message,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AuroraColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// ChatPanel renders chat timeline content in a section panel.
class ChatPanel extends StatelessWidget {
  /// Creates a chat panel body.
  const ChatPanel({super.key, required this.children, required this.empty});

  /// Timeline children.
  final List<Widget> children;

  /// Empty state widget.
  final Widget empty;

  /// Builds the chat panel.
  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return empty;
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      children: children,
    );
  }
}
