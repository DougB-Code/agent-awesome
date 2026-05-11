/// Searchable picker dropdown widgets.
part of 'panels.dart';

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
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: width,
        height: 38,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            backgroundColor: colors.surface,
            foregroundColor: colors.ink,
            side: BorderSide(color: colors.border),
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
    final colors = context.agentAwesomeColors;
    final options = _options.where(_matchesQuery).toList();
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 90, left: 24, right: 24),
      backgroundColor: colors.surface,
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
                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: colors.muted),
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
            Divider(height: 1, color: colors.border),
            Flexible(
              child: options.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          widget.emptyLabel,
                          style: TextStyle(color: colors.muted),
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
    final colors = context.agentAwesomeColors;
    return ListTile(
      leading: Icon(
        selected ? Icons.check_circle : option.icon,
        color: selected ? colors.green : colors.muted,
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
              style: TextStyle(color: colors.muted),
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
