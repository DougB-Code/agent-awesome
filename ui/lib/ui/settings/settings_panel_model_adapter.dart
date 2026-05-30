/// Settings model adapter dropdown widget.
part of 'settings_panel.dart';

class _SettingsAdapterDropdown extends StatelessWidget {
  const _SettingsAdapterDropdown({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// Builds a constrained selector for supported harness adapters.
  @override
  Widget build(BuildContext context) {
    final selected = supportedModelAdapters.contains(value) ? value : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: SettingsFormMetrics.fieldGap),
      child: PanelLabeledFormControl(
        label: 'Adapter',
        child: DropdownButtonFormField<String>(
          initialValue: selected,
          isDense: true,
          style: SettingsFormTextStyle.field(context),
          isExpanded: true,
          items: <DropdownMenuItem<String>>[
            for (final adapter in supportedModelAdapters)
              DropdownMenuItem<String>(value: adapter, child: Text(adapter)),
          ],
          onChanged: (value) {
            if (value != null) {
              onChanged(value);
            }
          },
          decoration: SettingsInputDecoration.field(context, label: 'Adapter'),
        ),
      ),
    );
  }
}
