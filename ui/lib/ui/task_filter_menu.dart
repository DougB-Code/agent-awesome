/// Provides reusable task filter dropdown controls.
library;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'panels/panels.dart';

/// TaskFilterMenuOption describes one selectable filter value.
class TaskFilterMenuOption {
  /// Creates one filter option.
  const TaskFilterMenuOption({
    required this.value,
    required this.label,
    this.detail = '',
  });

  /// Raw filter value applied by the caller.
  final String value;

  /// Primary option label shown in the dropdown.
  final String label;

  /// Optional secondary metadata for the option.
  final String detail;
}

/// TaskFilterMenuSection describes one group of filter choices.
class TaskFilterMenuSection {
  /// Creates one selectable filter section.
  const TaskFilterMenuSection({
    required this.title,
    required this.icon,
    required this.allLabel,
    required this.selectedValue,
    required this.options,
    required this.onChanged,
  });

  /// Section label.
  final String title;

  /// Section icon.
  final IconData icon;

  /// Label for the unfiltered option.
  final String allLabel;

  /// Currently selected raw value.
  final String selectedValue;

  /// Selectable narrowing options.
  final List<TaskFilterMenuOption> options;

  /// Called when the selection changes.
  final ValueChanged<String> onChanged;
}

/// TaskFilterMenuButton opens a reusable anchored task-filter dropdown.
class TaskFilterMenuButton extends StatelessWidget {
  /// Creates a compact filter button with a large dropdown panel.
  const TaskFilterMenuButton({
    super.key,
    required this.sections,
    this.activeCount = 0,
    this.summary = '',
    this.onClear,
    this.tooltip = 'Filters',
  });

  /// Filter sections shown in the dropdown.
  final List<TaskFilterMenuSection> sections;

  /// Number of active filters.
  final int activeCount;

  /// Optional summary shown at the top of the dropdown.
  final String summary;

  /// Clears all active filters.
  final VoidCallback? onClear;

  /// Tooltip for the button.
  final String tooltip;

  /// Builds the anchored filter button and dropdown contents.
  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    final colors = context.agentAwesomeColors;
    return MenuAnchor(
      style: MenuStyle(
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.zero,
        ),
        backgroundColor: WidgetStatePropertyAll<Color>(colors.surface),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      menuChildren: <Widget>[
        _TaskFilterMenuPanel(
          sections: sections,
          activeCount: activeCount,
          summary: summary,
          onClear: onClear,
        ),
      ],
      builder: (context, controller, child) {
        return PanelIconButton(
          icon: active ? Icons.filter_alt : Icons.filter_alt_outlined,
          tooltip: active ? '$tooltip ($activeCount active)' : tooltip,
          selected: active || controller.isOpen,
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
    );
  }
}

class _TaskFilterMenuPanel extends StatefulWidget {
  const _TaskFilterMenuPanel({
    required this.sections,
    required this.activeCount,
    required this.summary,
    required this.onClear,
  });

  final List<TaskFilterMenuSection> sections;
  final int activeCount;
  final String summary;
  final VoidCallback? onClear;

  /// Creates state for the menu fuzzy search.
  @override
  State<_TaskFilterMenuPanel> createState() => _TaskFilterMenuPanelState();
}

class _TaskFilterMenuPanelState extends State<_TaskFilterMenuPanel> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Cleans up fuzzy search input.
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Builds the large dropdown panel body.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final visibleSections = <_VisibleTaskFilterSection>[
      for (final section in widget.sections) _visibleSection(section, _query),
    ].where((section) => section.hasVisibleRows).toList();
    return SizedBox(
      width: 360,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(child: _TaskFilterPanelTitle()),
                    if (widget.onClear != null && widget.activeCount > 0)
                      TextButton.icon(
                        onPressed: widget.onClear,
                        icon: const Icon(Icons.filter_alt_off_outlined),
                        label: const Text('Clear'),
                      ),
                  ],
                ),
                if (widget.summary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    widget.summary,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _TaskFilterSearchField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 12),
                if (visibleSections.isEmpty)
                  const _TaskFilterNoMatches()
                else
                  for (final section in visibleSections) ...<Widget>[
                    _TaskFilterSectionView(section: section),
                    if (section != visibleSections.last)
                      Divider(height: 18, color: colors.border),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Returns visible rows for one filter section under the fuzzy query.
  _VisibleTaskFilterSection _visibleSection(
    TaskFilterMenuSection section,
    String query,
  ) {
    final trimmed = query.trim();
    final showAll =
        trimmed.isEmpty ||
        _matchesFuzzy(section.allLabel, trimmed) ||
        _matchesFuzzy(section.title, trimmed);
    final options = <TaskFilterMenuOption>[
      for (final option in section.options)
        if (trimmed.isEmpty ||
            _matchesFuzzy(
              '${section.title} ${option.label} ${option.detail}',
              trimmed,
            ))
          option,
    ];
    return _VisibleTaskFilterSection(
      source: section,
      options: options,
      showAll: showAll,
    );
  }
}

class _TaskFilterSearchField extends StatelessWidget {
  const _TaskFilterSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// Builds the fuzzy-search input for the menu.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        autofocus: true,
        onChanged: onChanged,
        style: TextStyle(color: colors.ink),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 18, color: colors.muted),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          hintText: 'Search filters...',
          hintStyle: TextStyle(color: colors.muted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 9,
          ),
          filled: true,
          fillColor: colors.field,
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

class _TaskFilterNoMatches extends StatelessWidget {
  const _TaskFilterNoMatches();

  /// Builds the empty search result state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        'No matching filters',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.agentAwesomeColors.muted),
      ),
    );
  }
}

class _TaskFilterPanelTitle extends StatelessWidget {
  const _TaskFilterPanelTitle();

  /// Builds the dropdown title.
  @override
  Widget build(BuildContext context) {
    return const PanelSectionLabel('Filters');
  }
}

class _TaskFilterSectionView extends StatelessWidget {
  const _TaskFilterSectionView({required this.section});

  final _VisibleTaskFilterSection section;

  /// Builds one section of selectable filter values.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final source = section.source;
    final selected =
        source.options.any((option) => option.value == source.selectedValue)
        ? source.selectedValue
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(source.icon, size: 16, color: colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                source.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (section.showAll)
          _TaskFilterOptionRow(
            label: source.allLabel,
            detail: '',
            selected: selected.isEmpty,
            onTap: () => source.onChanged(''),
          ),
        for (final option in section.options)
          _TaskFilterOptionRow(
            label: option.label,
            detail: option.detail,
            selected: selected == option.value,
            onTap: () => source.onChanged(option.value),
          ),
      ],
    );
  }
}

class _VisibleTaskFilterSection {
  const _VisibleTaskFilterSection({
    required this.source,
    required this.options,
    required this.showAll,
  });

  final TaskFilterMenuSection source;
  final List<TaskFilterMenuOption> options;
  final bool showAll;

  /// Whether this section should be rendered.
  bool get hasVisibleRows => showAll || options.isNotEmpty;
}

class _TaskFilterOptionRow extends StatelessWidget {
  const _TaskFilterOptionRow({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  /// Builds one dropdown option row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 17,
              color: selected ? colors.green : colors.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? colors.green : colors.ink,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
            if (detail.isNotEmpty) ...<Widget>[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 104),
                child: Text(
                  detail,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reports whether a candidate matches a fuzzy query in order.
bool _matchesFuzzy(String candidate, String query) {
  final normalizedCandidate = candidate.toLowerCase();
  final normalizedQuery = query.toLowerCase();
  var position = 0;
  for (final unit in normalizedQuery.codeUnits) {
    position = normalizedCandidate.indexOf(String.fromCharCode(unit), position);
    if (position < 0) {
      return false;
    }
    position++;
  }
  return true;
}
