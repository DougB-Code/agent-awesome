/// Shared backlog badges, form fields, and empty-state widgets.
part of 'backlog_section.dart';

class _TaskPanelLabel extends StatelessWidget {
  const _TaskPanelLabel(this.label);

  final String label;

  /// Builds an uppercase context panel label.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Text(
      label.toUpperCase(),
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.4,
      ),
    );
  }
}

class _TaskTileScreenChanges extends StatelessWidget {
  const _TaskTileScreenChanges({required this.changes});

  final List<ScreenChange> changes;

  /// Builds inline AI annotations for a queue tile.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.warningSoft,
        border: Border.all(color: colors.warningBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final change in changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    _screenChangeIcon(change),
                    size: 16,
                    color: _screenChangeColor(context, change),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          change.summary,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: colors.green,
                          ),
                        ),
                        if (change.afterValues.isNotEmpty)
                          Text(
                            _inlineScreenChangeDiff(change),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TaskBadge(label: _screenChangeStatusLabel(change)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskBadge extends StatelessWidget {
  const _TaskBadge({required this.label});

  final String label;

  /// Builds a dense context metadata badge.
  @override
  Widget build(BuildContext context) {
    return PanelBadge(label: _taskLabel(label));
  }
}

class _TaskDropdown extends StatelessWidget {
  const _TaskDropdown({
    required this.value,
    required this.values,
    required this.tooltip,
    required this.onChanged,
  });

  final String value;
  final List<String> values;
  final String tooltip;
  final ValueChanged<String> onChanged;

  /// Builds a compact dropdown for context controlled vocabulary.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final dropdownValue = values.contains(value) ? value : values.first;
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          gradient: context.agentAwesomeControlGradient,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: dropdownValue,
            isDense: true,
            isExpanded: true,
            dropdownColor: colors.surface,
            icon: Icon(Icons.expand_more, size: 18, color: colors.muted),
            style: TextStyle(color: colors.ink),
            items: <DropdownMenuItem<String>>[
              for (final item in values)
                DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    _taskLabel(item),
                    overflow: TextOverflow.ellipsis,
                  ),
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

class _TaskTextField extends StatelessWidget {
  const _TaskTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;

  /// Builds a compact context form field.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: maxLines == 1 ? 1 : 3,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
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
    );
  }
}

/// _TaskDatePickerField renders a task date value with a popup date picker.
class _TaskDatePickerField extends StatefulWidget {
  const _TaskDatePickerField({required this.controller, required this.label});

  /// Text controller that stores the formatted date.
  final TextEditingController controller;

  /// Field label shown in the editor.
  final String label;

  /// Creates state that can refresh suffix icons after date changes.
  @override
  State<_TaskDatePickerField> createState() => _TaskDatePickerFieldState();
}

/// _TaskDatePickerFieldState owns picker and clear interactions.
class _TaskDatePickerFieldState extends State<_TaskDatePickerField> {
  /// Builds a button-like date field backed by a date picker dialog.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final colors = context.agentAwesomeColors;
        final value = widget.controller.text.trim();
        final hasValue = value.isNotEmpty;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _pickDate,
            child: InputDecorator(
              isEmpty: !hasValue,
              decoration: InputDecoration(
                labelText: widget.label,
                floatingLabelBehavior: FloatingLabelBehavior.always,
                filled: true,
                fillColor: colors.surface,
                suffixIcon: IconButton(
                  tooltip: hasValue
                      ? 'Clear ${widget.label}'
                      : 'Pick ${widget.label}',
                  onPressed: hasValue ? _clearDate : _pickDate,
                  icon: Icon(
                    hasValue ? Icons.close : Icons.calendar_today_outlined,
                    size: 18,
                  ),
                ),
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
              child: Text(
                hasValue ? _datePickerFieldLabel(value) : 'Select date',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: hasValue ? colors.ink : colors.muted),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Opens a date picker and writes the selected date into the text controller.
  Future<void> _pickDate() async {
    final selectedDate = _parseTaskDateInput(widget.controller.text);
    final now = DateTime.now();
    final firstDate = DateTime(2000);
    final lastDate = DateTime(2100);
    final picked = await showDatePicker(
      context: context,
      initialDate: _clampDate(selectedDate ?? now, firstDate, lastDate),
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      widget.controller.text = formatOptionalLocalDate(picked);
    });
  }

  /// Clears the selected date.
  void _clearDate() {
    setState(() {
      widget.controller.clear();
    });
  }
}

/// Returns a normalized visible label for a date picker field value.
String _datePickerFieldLabel(String value) {
  final parsed = _parseTaskDateInput(value);
  if (parsed == null) {
    return value;
  }
  return formatOptionalLocalDate(parsed);
}

/// Returns a date constrained to a picker-supported range.
DateTime _clampDate(DateTime value, DateTime firstDate, DateTime lastDate) {
  if (value.isBefore(firstDate)) {
    return firstDate;
  }
  if (value.isAfter(lastDate)) {
    return lastDate;
  }
  return value;
}

class _TaskMetadataRow extends StatelessWidget {
  const _TaskMetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds one key/value metadata row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: colors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskSelectionEmpty extends StatelessWidget {
  const _TaskSelectionEmpty();

  /// Builds the context inspector no-selection state.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Center(
      child: Text(
        'Select a backlog item or list',
        style: TextStyle(color: colors.muted),
      ),
    );
  }
}

/// Shows the graph metadata editing dialog.
