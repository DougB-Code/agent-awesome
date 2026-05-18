/// Shared form fields for command-panel detail editors.
part of 'panels.dart';

/// PanelFormDecoration centralizes command-panel form field chrome.
abstract final class PanelFormDecoration {
  /// Creates the standard command-panel input decoration.
  static InputDecoration field(
    BuildContext context, {
    required String label,
    Widget? suffixIcon,
    FloatingLabelBehavior floatingLabelBehavior = FloatingLabelBehavior.auto,
  }) {
    final colors = context.agentAwesomeColors;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: colors.muted),
      floatingLabelBehavior: floatingLabelBehavior,
      filled: true,
      fillColor: colors.surface,
      suffixIcon: suffixIcon,
      border: _border(colors.border),
      enabledBorder: _border(colors.border),
      focusedBorder: _border(colors.searchBorder),
    );
  }

  /// Builds one shared outlined border.
  static OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color),
    );
  }
}

/// PanelFormFieldBase is the parent class for command-panel form fields.
abstract class PanelFormFieldBase extends StatelessWidget {
  /// Creates a shared command-panel form field base.
  const PanelFormFieldBase({super.key, required this.label});

  /// Field label.
  final String label;

  /// Creates standard field decoration for subclasses.
  @protected
  InputDecoration decoration(
    BuildContext context, {
    Widget? suffixIcon,
    FloatingLabelBehavior floatingLabelBehavior = FloatingLabelBehavior.auto,
  }) {
    return PanelFormDecoration.field(
      context,
      label: label,
      suffixIcon: suffixIcon,
      floatingLabelBehavior: floatingLabelBehavior,
    );
  }
}

/// PanelTextFormField renders autosaved command-panel text inputs.
class PanelTextFormField extends PanelFormFieldBase {
  /// Creates a shared text form field.
  const PanelTextFormField({
    super.key,
    required super.label,
    this.minLines,
    required this.controller,
    this.maxLines = 1,
    this.keyboardType,
    this.monospace = false,
  });

  /// Text controller owned by the parent editor.
  final TextEditingController controller;

  /// Minimum field lines.
  final int? minLines;

  /// Maximum field lines.
  final int maxLines;

  /// Optional keyboard override.
  final TextInputType? keyboardType;

  /// Whether to render text in a monospace font.
  final bool monospace;

  /// Builds the shared command-panel text field.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return TextField(
      controller: controller,
      keyboardType:
          keyboardType ??
          (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      minLines: minLines ?? (maxLines == 1 ? 1 : (maxLines < 3 ? maxLines : 3)),
      maxLines: maxLines,
      style: TextStyle(
        color: colors.ink,
        fontFamily: monospace ? 'monospace' : null,
      ),
      decoration: decoration(context),
    );
  }
}

/// PanelDropdownFormField renders shared command-panel dropdown inputs.
class PanelDropdownFormField<T> extends PanelFormFieldBase {
  /// Creates a shared dropdown form field.
  const PanelDropdownFormField({
    super.key,
    required super.label,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
    this.tooltip,
    this.showLabel = true,
  });

  /// Selected value.
  final T value;

  /// Available values.
  final List<T> values;

  /// Converts values to visible labels.
  final String Function(T value) labelFor;

  /// Handles a selected value.
  final ValueChanged<T> onChanged;

  /// Optional tooltip.
  final String? tooltip;

  /// Whether the field label should be visible.
  final bool showLabel;

  /// Builds the shared command-panel dropdown.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final options = values.isEmpty ? <T>[value] : values;
    final selected = options.contains(value) ? value : options.first;
    final field = DropdownButtonFormField<T>(
      initialValue: selected,
      isDense: true,
      isExpanded: true,
      dropdownColor: colors.surface,
      icon: Icon(Icons.expand_more, size: 18, color: colors.muted),
      style: TextStyle(color: colors.ink),
      decoration: decoration(
        context,
        floatingLabelBehavior: showLabel
            ? FloatingLabelBehavior.auto
            : FloatingLabelBehavior.never,
      ),
      items: <DropdownMenuItem<T>>[
        for (final option in options)
          DropdownMenuItem<T>(
            value: option,
            child: Text(labelFor(option), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (next) {
        if (next != null) {
          onChanged(next);
        }
      },
    );
    if (tooltip == null || tooltip!.trim().isEmpty) {
      return field;
    }
    return Tooltip(message: tooltip!, child: field);
  }
}
