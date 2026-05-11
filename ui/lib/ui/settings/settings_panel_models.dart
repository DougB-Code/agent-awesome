/// Model provider collection widgets.
part of 'settings_panel.dart';

class _SettingsModelProviderCollection extends StatefulWidget {
  const _SettingsModelProviderCollection({
    required this.controller,
    required this.emptyLabel,
    required this.icon,
    required this.entries,
    required this.assignedPath,
  });

  final AgentAwesomeAppController controller;
  final String emptyLabel;
  final IconData icon;
  final List<ConfigFileEntry> entries;
  final String assignedPath;

  @override
  State<_SettingsModelProviderCollection> createState() =>
      _SettingsModelProviderCollectionState();
}

class _SettingsModelProviderCollectionState
    extends State<_SettingsModelProviderCollection> {
  String? _selectedPath;
  String? _selectedProviderId;
  ModelConfigDocument? _document;
  bool _loading = true;

  /// Initializes the selected model config and provider.
  @override
  void initState() {
    super.initState();
    _selectedPath = _initialSelectedPath();
    unawaited(_load());
  }

  /// Keeps the selected model config valid when config files refresh.
  @override
  void didUpdateWidget(covariant _SettingsModelProviderCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedPath = _selectedPath;
    if (selectedPath == null ||
        !widget.entries.any((entry) => entry.path == selectedPath)) {
      _selectedPath = _initialSelectedPath();
      _document = null;
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
    return CollectionSwitcherPanel<ModelProviderConfig>(
      title: 'Models',
      selectedId: _selectedProviderIdFor(providers),
      emptyLabel: entry == null ? widget.emptyLabel : 'No providers configured',
      items: <CollectionPanelItem<ModelProviderConfig>>[
        for (final provider in providers)
          CollectionPanelItem<ModelProviderConfig>(
            id: provider.id,
            label: provider.displayName,
            detail: provider.id,
            icon: widget.icon,
            badge: _isDefaultProvider(document, provider.id) ? 'Active' : '',
            value: provider,
          ),
      ],
      onSelect: (id) => setState(() => _selectedProviderId = id),
      onCreate: () => unawaited(_addProvider()),
      onDuplicate: (provider) => unawaited(_duplicateProvider(provider)),
      onDelete: (provider) => unawaited(_deleteProvider(provider)),
      builder: (provider, query) {
        if (entry == null || document == null) {
          return PanelEmptyState(query: query);
        }
        return _buildProviderEditor(entry, document, provider, query);
      },
    );
  }

  Widget _buildProviderEditor(
    ConfigFileEntry entry,
    ModelConfigDocument document,
    ModelProviderConfig provider,
    String query,
  ) {
    if (!SettingsQuery.matches(query, <String>[
      provider.id,
      provider.name,
      provider.adapter,
      provider.apiKey,
      provider.url,
      for (final model in provider.models) ...<String>[model.id, model.model],
    ])) {
      return PanelEmptyState(query: query);
    }
    return FormPanel(
      children: <Widget>[
        _SettingsActionRow(
          children: <Widget>[
            FilledButton.icon(
              onPressed: entry.assigned
                  ? null
                  : () => unawaited(_assign(entry)),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(entry.assigned ? 'Assigned' : 'Use for profile'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _isDefaultProvider(document, provider.id)
                  ? null
                  : () => unawaited(
                      _setDefaultProvider(entry, document, provider),
                    ),
              icon: const Icon(Icons.radio_button_checked),
              label: Text(
                _isDefaultProvider(document, provider.id)
                    ? 'Default provider'
                    : 'Set default provider',
              ),
            ),
          ],
        ),
        _SettingsModelProviderCard(
          controller: widget.controller,
          provider: provider,
          onChanged: (next) => _replaceProvider(document, provider.id, next),
        ),
        _SettingsModelProviderYamlPreview(provider: provider),
      ],
    );
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

  String? _selectedProviderIdFor(List<ModelProviderConfig> providers) {
    if (providers.isEmpty) {
      return null;
    }
    final selected = _selectedProviderId;
    if (selected != null &&
        providers.any((provider) => provider.id == selected)) {
      return selected;
    }
    final defaultProviderId = _defaultProviderId(_document);
    if (defaultProviderId.isNotEmpty &&
        providers.any((provider) => provider.id == defaultProviderId)) {
      return defaultProviderId;
    }
    return providers.first.id;
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
        _selectedProviderId = _selectedProviderIdFor(document.providers);
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

  Future<void> _addProvider() async {
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
    final nextId = SettingsConfigIds.uniqueProviderId(document, 'provider');
    final provider = newModelProviderConfig(nextId);
    final defaultRef = document.defaultRef.trim().isEmpty
        ? '${provider.id}:${provider.defaultModel}'
        : document.defaultRef;
    await _saveDocument(
      entry,
      document.copyWith(
        defaultRef: defaultRef,
        providers: <ModelProviderConfig>[...document.providers, provider],
      ),
      selectedProviderId: provider.id,
    );
  }

  Future<void> _duplicateProvider(ModelProviderConfig provider) async {
    final entry = _selectedEntry();
    final document = _document;
    if (entry == null || document == null) {
      return;
    }
    final nextId = SettingsConfigIds.uniqueProviderId(
      document,
      '${provider.id}-copy',
    );
    final nextProvider = provider.copyWith(
      id: nextId,
      name: '${provider.displayName} Copy',
    );
    await _saveDocument(
      entry,
      document.copyWith(
        providers: <ModelProviderConfig>[...document.providers, nextProvider],
      ),
      selectedProviderId: nextProvider.id,
    );
  }

  Future<void> _deleteProvider(ModelProviderConfig provider) async {
    final entry = _selectedEntry();
    final document = _document;
    if (entry == null || document == null) {
      return;
    }
    if (document.providers.length <= 1) {
      return;
    }
    final confirmed = await _confirmSettingsDelete(
      context,
      label: provider.displayName,
    );
    if (!confirmed) {
      return;
    }
    if (provider.apiKey.trim().isNotEmpty) {
      await widget.controller.deleteCredential(provider.apiKey);
    }
    final providers = document.providers
        .where((candidate) => candidate.id != provider.id)
        .toList();
    final deletingDefault = _isDefaultProvider(document, provider.id);
    final defaultRef = deletingDefault
        ? '${providers.first.id}:${providers.first.defaultModel}'
        : document.defaultRef;
    await _saveDocument(
      entry,
      document.copyWith(defaultRef: defaultRef, providers: providers),
      selectedProviderId: deletingDefault
          ? providers.first.id
          : _selectedProviderIdFor(providers) ?? providers.first.id,
    );
  }

  Future<void> _replaceProvider(
    ModelConfigDocument document,
    String previousId,
    ModelProviderConfig provider,
  ) async {
    final entry = _selectedEntry();
    if (entry == null) {
      return;
    }
    final duplicate = document.providers.any((candidate) {
      return candidate.id == provider.id && candidate.id != previousId;
    });
    if (duplicate) {
      return;
    }
    final providers = <ModelProviderConfig>[
      for (final candidate in document.providers)
        candidate.id == previousId ? provider : candidate,
    ];
    final defaultRef = document.defaultRef.startsWith('$previousId:')
        ? '${provider.id}:${provider.defaultModel}'
        : document.defaultRef;
    await _saveDocument(
      entry,
      document.copyWith(defaultRef: defaultRef, providers: providers),
      selectedProviderId: provider.id,
    );
  }

  Future<void> _assign(ConfigFileEntry entry) async {
    try {
      await widget.controller.assignConfigFile(entry);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }

  /// Marks the selected provider as the config-level default provider.
  Future<void> _setDefaultProvider(
    ConfigFileEntry entry,
    ModelConfigDocument document,
    ModelProviderConfig provider,
  ) async {
    await _saveDocument(
      entry,
      document.copyWith(defaultRef: modelProviderDefaultRef(provider)),
      selectedProviderId: provider.id,
    );
  }

  Future<void> _saveDocument(
    ConfigFileEntry entry,
    ModelConfigDocument document, {
    required String selectedProviderId,
  }) async {
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
        _selectedProviderId = selectedProviderId;
      });
    } catch (_) {}
  }

  bool _isDefaultProvider(ModelConfigDocument? document, String providerId) {
    return _defaultProviderId(document) == providerId;
  }

  String _defaultProviderId(ModelConfigDocument? document) {
    return document?.defaultRef.split(':').first.trim() ?? '';
  }
}
