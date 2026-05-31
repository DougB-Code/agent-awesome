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
            for (final model in provider.models)
              DropdownMenuItem<String>(
                value: model.id,
                child: Text(_modelOptionLabel(model)),
              ),
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

  /// Returns the user-facing model label for default selection.
  String _modelOptionLabel(ModelConfigModel model) {
    final providerModel = model.model.trim();
    if (providerModel.isNotEmpty) {
      return providerModel;
    }
    return 'Unconfigured model';
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
      child: _SettingsInlineField(
        label: 'Provider model',
        value: model.model,
        hintText: 'Provider model name',
        onChanged: (value) => onChanged(model.copyWith(model: value)),
      ),
    );
  }
}
