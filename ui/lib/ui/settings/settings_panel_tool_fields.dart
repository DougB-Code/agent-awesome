/// Settings tool field-list and YAML preview widgets.
part of 'settings_panel.dart';

class _SettingsLineListField extends StatelessWidget {
  const _SettingsLineListField({
    required this.label,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  /// Builds a newline-delimited string-list field.
  @override
  Widget build(BuildContext context) {
    return _SettingsInlineField(
      label: label,
      value: values.join('\n'),
      minLines: 2,
      maxLines: 5,
      onChanged: (value) => onChanged(SettingsTextCodec.lines(value)),
    );
  }
}

class _SettingsKeyValueField extends StatelessWidget {
  const _SettingsKeyValueField({
    required this.label,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final Map<String, String> values;
  final ValueChanged<Map<String, String>> onChanged;

  /// Builds a newline-delimited KEY=value map field.
  @override
  Widget build(BuildContext context) {
    return _SettingsInlineField(
      label: label,
      value: values.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('\n'),
      minLines: 2,
      maxLines: 5,
      onChanged: (value) => onChanged(SettingsTextCodec.keyValues(value)),
    );
  }
}
