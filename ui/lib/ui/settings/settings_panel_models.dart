/// Model provider collection widgets.
part of 'settings_panel.dart';

class _SettingsModelProviderCollection extends StatefulWidget {
  const _SettingsModelProviderCollection({
    required this.controller,
    required this.emptyLabel,
    required this.icon,
    required this.entries,
    required this.assignedPath,
    this.selectedPath,
    this.onSelectedPathChanged,
    required this.modeId,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String emptyLabel;
  final IconData icon;
  final List<ConfigFileEntry> entries;
  final String assignedPath;
  final String? selectedPath;
  final ValueChanged<String>? onSelectedPathChanged;
  final String modeId;
  final String query;

  @override
  State<_SettingsModelProviderCollection> createState() =>
      _SettingsModelProviderCollectionState();
}

class _SettingsModelProviderCollectionState
    extends State<_SettingsModelProviderCollection> {
  String? _selectedPath;
  ModelConfigDocument? _document;
  AgentValidationSuiteResult? _validationResult;
  AgentValidationFileResult? _validationFileResult;
  final Map<String, ModelProviderVerificationResult> _verificationResults =
      <String, ModelProviderVerificationResult>{};
  final Map<String, String> _verificationErrors = <String, String>{};
  String _validationError = '';
  String _validationRunningId = '';
  String _verificationRunningProviderId = '';
  bool _loading = true;
  bool _validationRunning = false;

  /// Initializes the selected model config and provider.
  @override
  void initState() {
    super.initState();
    _selectedPath = widget.selectedPath ?? _initialSelectedPath();
    unawaited(_load());
  }

  /// Keeps the selected model config valid when config files refresh.
  @override
  void didUpdateWidget(covariant _SettingsModelProviderCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedPath != null &&
        widget.selectedPath != oldWidget.selectedPath &&
        widget.selectedPath != _selectedPath) {
      _selectedPath = widget.selectedPath;
      _document = null;
      _clearValidationState();
      _loading = true;
      unawaited(_load());
      return;
    }
    final selectedPath = _selectedPath;
    if (selectedPath == null ||
        !widget.entries.any((entry) => entry.path == selectedPath)) {
      _selectedPath = _initialSelectedPath();
      _document = null;
      _clearValidationState();
      _loading = true;
      unawaited(_load());
    }
  }

  /// Builds the provider-centric model settings panel.
  @override
  Widget build(BuildContext context) {
    final entry = _selectedEntry();
    final document = _document;
    final providers = document?.providers ?? const <ModelProviderConfig>[];
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entry == null || document == null) {
      if (!SettingsQuery.matches(widget.query, <String>[
        'Models',
        widget.emptyLabel,
      ])) {
        return PanelEmptyState(query: widget.query);
      }
      return FormPanel(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => unawaited(_createProvider()),
              icon: const Icon(Icons.add),
              label: const Text('Create provider'),
            ),
          ),
        ],
      );
    }
    final visibleProviders = providers.where((provider) {
      return SettingsQuery.matches(
        widget.query,
        _providerSearchValues(provider),
      );
    }).toList();
    if (widget.modeId == 'model-validations') {
      return _buildValidations(entry, document, visibleProviders);
    }
    return FormPanel(
      children: <Widget>[
        if (providers.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => unawaited(_createProvider()),
              icon: const Icon(Icons.add),
              label: const Text('Create provider'),
            ),
          )
        else if (visibleProviders.isEmpty)
          PanelEmptyBlock(label: 'No matching providers')
        else
          for (final provider in visibleProviders) ...<Widget>[
            _SettingsModelProviderCard(
              controller: widget.controller,
              provider: provider,
              verificationResult: _verificationResults[provider.id],
              verificationError: _verificationErrors[provider.id] ?? '',
              verificationRunning:
                  _verificationRunningProviderId == provider.id,
              onVerify: () => unawaited(_verifyProvider(entry, provider)),
              onChanged: (next) =>
                  _replaceProvider(document, provider.id, next),
            ),
          ],
      ],
    );
  }

  /// Builds model-owned Agent Awesome compatibility validations.
  Widget _buildValidations(
    ConfigFileEntry entry,
    ModelConfigDocument document,
    List<ModelProviderConfig> visibleProviders,
  ) {
    return FormPanel(
      children: <Widget>[
        if (document.providers.isEmpty)
          PanelEmptyBlock(label: 'No provider configured')
        else if (visibleProviders.isEmpty)
          PanelEmptyBlock(label: 'No matching providers')
        else
          _SettingsAgentValidationCard(
            title: 'Model validations',
            emptyLabel: 'No model validations configured',
            validations: document.validations,
            result: _validationResult,
            fileResult: _validationFileResult,
            error: _validationError,
            runningId: _validationRunningId,
            onRunAll: () => unawaited(_runValidations(entry)),
            onAddValidation: () => unawaited(_addValidation()),
            onValidationChanged: (id, validation) =>
                unawaited(_saveValidation(id, validation)),
            onDeleteValidation: (id) => unawaited(_deleteValidation(id)),
            onRunValidation: (validationId) =>
                unawaited(_runValidations(entry, validationId: validationId)),
          ),
      ],
    );
  }

  List<String> _providerSearchValues(ModelProviderConfig provider) {
    return <String>[
      provider.id,
      provider.name,
      provider.adapter,
      provider.apiKey,
      provider.url,
      for (final endpoint in provider.endpoints.entries) ...<String>[
        endpoint.key,
        endpoint.value,
      ],
      for (final model in provider.models) ...<String>[model.id, model.model],
    ];
  }

  String? _initialSelectedPath() {
    if (widget.assignedPath.isNotEmpty &&
        widget.entries.any((entry) => entry.path == widget.assignedPath)) {
      return widget.assignedPath;
    }
    if (widget.entries.isEmpty) {
      return null;
    }
    return widget.entries.first.path;
  }

  ConfigFileEntry? _selectedEntry() {
    final selectedPath = _selectedPath;
    if (selectedPath != null) {
      for (final entry in widget.entries) {
        if (entry.path == selectedPath) {
          return entry;
        }
      }
      return ConfigFileEntry(
        path: selectedPath,
        kind: ConfigFileKind.model,
        assigned: selectedPath == widget.assignedPath,
      );
    }
    if (widget.entries.isEmpty) {
      return null;
    }
    return widget.entries.first;
  }

  Future<void> _load() async {
    final entry = _selectedEntry();
    if (entry == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _document = null;
        _loading = false;
      });
      return;
    }
    try {
      final content = await widget.controller.readConfigurationFile(entry.path);
      final document = ModelConfigDocument.parse(content);
      if (!mounted) {
        return;
      }
      setState(() {
        _document = document;
        _clearValidationState();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _document = null;
        _loading = false;
      });
    }
  }

  Future<void> _createProvider() async {
    var entry = _selectedEntry();
    if (entry == null) {
      try {
        final path = await widget.controller.createConfigFile(
          ConfigFileKind.model,
        );
        await widget.controller.refreshConfigurationCollections();
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedPath = path;
          _loading = true;
        });
        widget.onSelectedPathChanged?.call(path);
        await _load();
        entry = _selectedEntry();
      } catch (_) {
        return;
      }
    }
    if (entry == null) {
      return;
    }
    final document =
        _document ?? const ModelConfigDocument(defaultRef: '', providers: []);
    if (document.providers.isNotEmpty) {
      return;
    }
    final nextId = SettingsConfigIds.uniqueProviderId(document, 'provider');
    final provider = newModelProviderConfig(nextId);
    await _saveDocument(
      entry,
      modelConfigDocumentForProvider(
        provider,
        validations: document.validations,
        extra: document.extra,
      ),
    );
  }

  Future<void> _replaceProvider(
    ModelConfigDocument document,
    String _,
    ModelProviderConfig provider,
  ) async {
    final entry = _selectedEntry();
    if (entry == null) {
      return;
    }
    await _saveDocument(
      entry,
      modelConfigDocumentForProvider(
        provider,
        validations: document.validations,
        extra: document.extra,
      ),
    );
  }

  /// Runs one provider smoke check through the harness model CLI.
  Future<void> _verifyProvider(
    ConfigFileEntry entry,
    ModelProviderConfig provider,
  ) async {
    if (_verificationRunningProviderId.isNotEmpty) {
      return;
    }
    setState(() {
      _verificationRunningProviderId = provider.id;
      _verificationErrors.remove(provider.id);
      _verificationResults.remove(provider.id);
    });
    try {
      final result = await widget.controller.verifyModelProviderConnection(
        modelPath: entry.path,
        provider: provider,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _verificationResults[provider.id] = result;
        _verificationRunningProviderId = '';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _verificationErrors[provider.id] = error.toString();
        _verificationRunningProviderId = '';
      });
    }
  }

  /// Adds one model-owned compatibility validation case.
  Future<void> _addValidation() async {
    final entry = _selectedEntry();
    final document = _document;
    if (entry == null || document == null) {
      return;
    }
    await _saveDocument(
      entry,
      document.copyWith(
        validations: <AgentValidationConfig>[
          ...document.validations,
          _defaultAgentValidation(document.validations).copyWith(mode: 'live'),
        ],
      ),
    );
  }

  /// Saves one model-owned validation case.
  Future<void> _saveValidation(
    String id,
    AgentValidationConfig validation,
  ) async {
    final entry = _selectedEntry();
    final document = _document;
    if (entry == null || document == null) {
      return;
    }
    await _saveDocument(
      entry,
      document.copyWith(
        validations: <AgentValidationConfig>[
          for (final item in document.validations)
            if (item.id == id) validation else item,
        ],
      ),
    );
  }

  /// Removes one model-owned validation case.
  Future<void> _deleteValidation(String id) async {
    final entry = _selectedEntry();
    final document = _document;
    if (entry == null || document == null) {
      return;
    }
    await _saveDocument(
      entry,
      document.copyWith(
        validations: <AgentValidationConfig>[
          for (final item in document.validations)
            if (item.id != id) item,
        ],
      ),
    );
  }

  /// Runs selected model validations through the active agent prompt.
  Future<void> _runValidations(
    ConfigFileEntry entry, {
    String validationId = '',
  }) async {
    if (_validationRunning) {
      return;
    }
    final selectedId = validationId.trim();
    setState(() {
      _validationRunning = true;
      _validationRunningId = selectedId.isEmpty
          ? _allValidationRunId
          : selectedId;
      _validationError = '';
    });
    try {
      final mode = _modelValidationModeForRun(
        _document?.validations ?? const <AgentValidationConfig>[],
        selectedId,
      );
      final result = await widget.controller.runModelPackageValidations(
        entry.path,
        validationId: selectedId,
        mode: mode,
        live: mode == 'live',
        requireValidations: selectedId.isEmpty,
        requireAssertions: true,
        requireToolContracts: true,
      );
      final fileResult = _agentValidationFileForEntry(result, entry);
      final suite = fileResult.result;
      if (!mounted) {
        return;
      }
      setState(() {
        _validationResult = selectedId.isEmpty
            ? suite
            : _mergedAgentValidationResults(_validationResult, suite);
        _validationFileResult = fileResult;
        _validationError = '';
        _validationRunning = false;
        _validationRunningId = '';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _validationError = error.toString();
        _validationFileResult = null;
        _validationRunning = false;
        _validationRunningId = '';
      });
    }
  }

  Future<void> _saveDocument(
    ConfigFileEntry entry,
    ModelConfigDocument document,
  ) async {
    final validationError = modelConfigValidationError(document);
    if (validationError.isNotEmpty) {
      return;
    }
    try {
      await widget.controller.saveConfigurationFile(
        entry.path,
        document.toYaml(),
      );
      await widget.controller.refreshConfigurationCollections();
      if (!mounted) {
        return;
      }
      setState(() {
        _document = document;
      });
    } catch (_) {}
  }

  /// Clears validation runner state for a newly selected model file.
  void _clearValidationState() {
    _validationResult = null;
    _validationFileResult = null;
    _validationError = '';
    _validationRunning = false;
    _validationRunningId = '';
  }
}

/// Chooses the validation lane for model compatibility checks.
String _modelValidationModeForRun(
  List<AgentValidationConfig> validations,
  String validationId,
) {
  final selectedId = validationId.trim();
  if (selectedId.isNotEmpty) {
    return _agentValidationModeForRun(validations, selectedId);
  }
  return validations.any(_agentValidationIsLive) ? 'live' : 'mocked';
}
