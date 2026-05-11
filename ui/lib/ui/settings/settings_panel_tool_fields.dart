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

class _SettingsToolYamlPreview extends StatelessWidget {
  const _SettingsToolYamlPreview({required this.document});

  final ToolConfigDocument document;

  /// Builds a read-only YAML preview for the structured tool config.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return FormSectionCard(
      title: 'Tool config YAML',
      children: <Widget>[
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              document.toYaml(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}
