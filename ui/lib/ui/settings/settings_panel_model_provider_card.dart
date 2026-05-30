/// Settings model provider card widgets.
part of 'settings_panel.dart';

class _SettingsModelProviderCard extends StatelessWidget {
  const _SettingsModelProviderCard({
    required this.controller,
    required this.provider,
    required this.onChanged,
  });

  final AgentAwesomeAppController controller;
  final ModelProviderConfig provider;
  final ValueChanged<ModelProviderConfig> onChanged;

  /// Builds one editable provider card and its model rows.
  @override
  Widget build(BuildContext context) {
    return FormPlainSection(
      title: provider.displayName,
      children: <Widget>[
        SettingsFieldGrid(
          children: <Widget>[
            _SettingsInlineField(
              label: 'Name',
              value: provider.name,
              onChanged: (value) => onChanged(provider.copyWith(name: value)),
            ),
            _SettingsAdapterDropdown(
              value: provider.adapter,
              onChanged: (value) =>
                  onChanged(provider.copyWith(adapter: value)),
            ),
          ],
        ),
        _SettingsCredentialField(
          controller: controller,
          providerId: provider.id,
          reference: provider.apiKey,
          onChanged: (value) => onChanged(provider.copyWith(apiKey: value)),
        ),
        _SettingsInlineField(
          label: 'URL',
          value: provider.url,
          onChanged: (value) => onChanged(provider.copyWith(url: value)),
        ),
        const SizedBox(height: SettingsFormMetrics.sectionGap),
        SettingsFormSubsection(
          title: 'Models',
          children: <Widget>[
            for (var index = 0; index < provider.models.length; index++)
              _SettingsModelRow(
                model: provider.models[index],
                onChanged: (model) => _replaceModel(index, model),
                onDelete: provider.models.length <= 1
                    ? null
                    : () => _deleteModel(index),
              ),
            _SettingsProviderDefaultModelDropdown(
              provider: provider,
              onChanged: (value) =>
                  onChanged(provider.copyWith(defaultModel: value)),
            ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _addModel,
                  icon: const Icon(Icons.add),
                  label: const Text('Add model'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  void _addModel() {
    final nextId = SettingsConfigIds.uniqueModelId(provider, 'model');
    onChanged(
      provider.copyWith(
        models: <ModelConfigModel>[
          ...provider.models,
          ModelConfigModel(id: nextId, model: 'provider-model-name'),
        ],
      ),
    );
  }

  void _replaceModel(int index, ModelConfigModel model) {
    final previous = provider.models[index];
    final nextDefault = provider.defaultModel == previous.id
        ? model.id
        : provider.defaultModel;
    onChanged(
      provider.copyWith(
        defaultModel: nextDefault,
        models: <ModelConfigModel>[
          for (var i = 0; i < provider.models.length; i++)
            i == index ? model : provider.models[i],
        ],
      ),
    );
  }

  void _deleteModel(int index) {
    final nextModels = <ModelConfigModel>[
      for (var i = 0; i < provider.models.length; i++)
        if (i != index) provider.models[i],
    ];
    final nextDefault = provider.defaultModel == provider.models[index].id
        ? nextModels.first.id
        : provider.defaultModel;
    onChanged(provider.copyWith(models: nextModels, defaultModel: nextDefault));
  }
}
