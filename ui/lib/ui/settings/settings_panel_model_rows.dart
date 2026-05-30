/// Settings provider default and model row widgets.
part of 'settings_panel.dart';

class _SettingsProviderDefaultModelDropdown extends StatelessWidget {
  const _SettingsProviderDefaultModelDropdown({
    required this.provider,
    required this.onChanged,
  });

  final ModelProviderConfig provider;
  final ValueChanged<String> onChanged;

  /// Builds a provider-local default model selector.
  @override
  Widget build(BuildContext context) {
    final modelIds = provider.models.map((model) => model.id).toList();
    final selected = modelIds.contains(provider.defaultModel)
        ? provider.defaultModel
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: SettingsFormMetrics.fieldGap),
      child: PanelLabeledFormControl(
        label: 'Default model',
        child: DropdownButtonFormField<String>(
          initialValue: selected,
          isDense: true,
          style: SettingsFormTextStyle.field(context),
          isExpanded: true,
          items: <DropdownMenuItem<String>>[
            for (final modelId in modelIds)
              DropdownMenuItem<String>(value: modelId, child: Text(modelId)),
          ],
          onChanged: (value) {
            if (value != null) {
              onChanged(value);
            }
          },
          decoration: SettingsInputDecoration.field(
            context,
            label: 'Default model',
          ),
        ),
      ),
    );
  }
}

class _SettingsModelRow extends StatelessWidget {
  const _SettingsModelRow({
    required this.model,
    required this.onChanged,
    required this.onDelete,
  });

  final ModelConfigModel model;
  final ValueChanged<ModelConfigModel> onChanged;
  final VoidCallback? onDelete;

  /// Builds one editable model row.
  @override
  Widget build(BuildContext context) {
    return SettingsFieldRow(
      trailing: PanelInlineIconButton(
        icon: Icons.delete_outline,
        tooltip: 'Delete model',
        onPressed: onDelete,
      ),
      child: SettingsFieldGrid(
        children: <Widget>[
          _SettingsInlineField(
            label: 'Model id',
            value: model.id,
            onChanged: (value) => onChanged(model.copyWith(id: value)),
          ),
          _SettingsInlineField(
            label: 'Provider model',
            value: model.model,
            onChanged: (value) => onChanged(model.copyWith(model: value)),
          ),
        ],
      ),
    );
  }
}
