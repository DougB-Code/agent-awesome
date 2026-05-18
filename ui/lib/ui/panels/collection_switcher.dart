/// Collection switcher panel widgets.
part of 'panels.dart';

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
    this.showCollapseButton = true,
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

  /// Whether to show the split-pane collapse button when available.
  final bool showCollapseButton;

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
    final colors = context.agentAwesomeColors;
    final selectedItem = _selectedItem();
    final collapseScope = SplitPaneCollapseScope.maybeOf(context);
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
    return PanelBodySurface(
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
                                style: TextStyle(
                                  color: colors.muted,
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
                                    style: TextStyle(
                                      color: colors.muted,
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
                      if (collapseScope != null &&
                          widget.showCollapseButton) ...<Widget>[
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
                      prefixIcon: Icon(
                        Icons.search,
                        size: 18,
                        color: colors.muted,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      hintText: widget.filterHint,
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
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
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
    return PanelBodySurface(
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
              PanelIconButton(
                icon: Icons.add,
                tooltip: 'Add',
                onPressed: onCreate,
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
    final colors = context.agentAwesomeColors;
    return SizedBox(
      width: width,
      height: 38,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
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
    return PanelIconButton(
      icon: icon,
      tooltip: tooltip,
      selected: selected,
      onPressed: onPressed,
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
      child: PanelIconButton(
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
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
    final colors = context.agentAwesomeColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: TextStyle(color: colors.muted)),
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
