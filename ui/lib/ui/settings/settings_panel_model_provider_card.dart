/// Settings model provider card widgets.
part of 'settings_panel.dart';

class _SettingsModelProviderCard extends StatelessWidget {
  const _SettingsModelProviderCard({
    required this.controller,
    required this.provider,
    required this.verificationRunning,
    required this.onVerify,
    required this.onChanged,
    this.verificationResult,
    this.verificationError = '',
  });

  final AgentAwesomeAppController controller;
  final ModelProviderConfig provider;
  final ModelProviderVerificationResult? verificationResult;
  final String verificationError;
  final bool verificationRunning;
  final VoidCallback onVerify;
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
        SettingsSecretStorageField(
          controller: controller,
          defaultReference: SettingsNameFactory.credentialNameFromProvider(
            provider.id,
          ),
          reference: provider.apiKey,
          onChanged: (value) => onChanged(provider.copyWith(apiKey: value)),
          label: 'API key',
          secretLabel: 'API key',
          pasteHint: 'Paste API key',
        ),
        _SettingsInlineField(
          label: 'Chat URL',
          value: _endpointValue('chat'),
          onChanged: (value) => _replaceEndpoint('chat', value),
        ),
        _SettingsInlineField(
          label: 'Images URL',
          value: _endpointValue('images'),
          onChanged: (value) => _replaceEndpoint('images', value),
        ),
        _SettingsModelProviderVerification(
          result: verificationResult,
          error: verificationError,
          running: verificationRunning,
          onVerify: _canVerifyProvider ? onVerify : null,
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

  /// Reports whether this provider has enough data for a smoke check.
  bool get _canVerifyProvider {
    return provider.id.trim().isNotEmpty &&
        provider.defaultModel.trim().isNotEmpty &&
        provider.models.any((model) {
          return model.id == provider.defaultModel &&
              model.model.trim().isNotEmpty;
        });
  }

  /// Returns a named endpoint value, falling back to the legacy URL for chat.
  String _endpointValue(String key) {
    final value = provider.endpoint(key);
    if (value.isNotEmpty) {
      return value;
    }
    if (key == 'chat') {
      return provider.url;
    }
    return '';
  }

  /// Replaces one named endpoint while keeping empty endpoints out of config.
  void _replaceEndpoint(String key, String value) {
    final endpoints = <String, String>{...provider.endpoints};
    final normalizedKey = key.trim();
    final normalizedValue = value.trim();
    if (normalizedKey.isEmpty) {
      return;
    }
    if (normalizedValue.isEmpty) {
      endpoints.remove(normalizedKey);
    } else {
      endpoints[normalizedKey] = normalizedValue;
    }
    onChanged(provider.copyWith(endpoints: endpoints, url: ''));
  }

  void _addModel() {
    final nextId = SettingsConfigIds.uniqueModelIdFromProviderModel(
      provider,
      'model',
    );
    onChanged(
      provider.copyWith(
        models: <ModelConfigModel>[
          ...provider.models,
          ModelConfigModel(id: nextId, model: ''),
        ],
      ),
    );
  }

  void _replaceModel(int index, ModelConfigModel model) {
    final previous = provider.models[index];
    final nextModel = _modelWithStableId(previous, model);
    final nextDefault = provider.defaultModel == previous.id
        ? nextModel.id
        : provider.defaultModel;
    onChanged(
      provider.copyWith(
        defaultModel: nextDefault,
        models: <ModelConfigModel>[
          for (var i = 0; i < provider.models.length; i++)
            i == index ? nextModel : provider.models[i],
        ],
      ),
    );
  }

  ModelConfigModel _modelWithStableId(
    ModelConfigModel previous,
    ModelConfigModel next,
  ) {
    if (previous.model.trim().isNotEmpty || next.model.trim().isEmpty) {
      return next.copyWith(id: previous.id);
    }
    final otherModels = provider.copyWith(
      models: <ModelConfigModel>[
        for (final model in provider.models)
          if (model.id != previous.id) model,
      ],
    );
    return next.copyWith(
      id: SettingsConfigIds.uniqueModelIdFromProviderModel(
        otherModels,
        next.model,
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

class _SettingsModelProviderVerification extends StatelessWidget {
  const _SettingsModelProviderVerification({
    required this.result,
    required this.error,
    required this.running,
    required this.onVerify,
  });

  final ModelProviderVerificationResult? result;
  final String error;
  final bool running;
  final VoidCallback? onVerify;

  /// Builds provider verification controls and latest verification evidence.
  @override
  Widget build(BuildContext context) {
    final result = this.result;
    return Padding(
      padding: const EdgeInsets.only(bottom: SettingsFormMetrics.fieldGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: running ? null : onVerify,
                icon: running
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_outlined),
                label: Text(running ? 'Verifying API key' : 'Verify API key'),
              ),
              if (result != null)
                PanelBadge(label: 'Verified ${result.modelName}'),
            ],
          ),
          if (error.trim().isNotEmpty)
            SettingsFormNote(
              icon: Icons.error_outline,
              text: _verificationErrorText(error),
            ),
        ],
      ),
    );
  }

  /// Returns concise verification failure text for the form note.
  String _verificationErrorText(String value) {
    final text = value.trim();
    if (text.startsWith('Bad state: ')) {
      return text.substring('Bad state: '.length);
    }
    return text;
  }
}
