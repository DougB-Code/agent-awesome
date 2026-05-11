/// Shared settings cards, fields, dropdowns, and action widgets.
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
    return FormSectionCard(
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

class _SettingsModelProviderYamlPreview extends StatelessWidget {
  const _SettingsModelProviderYamlPreview({required this.provider});

  final ModelProviderConfig provider;

  /// Builds a selected-provider YAML preview without exposing sibling providers.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return FormSectionCard(
      title: 'Provider YAML',
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
              modelProviderConfigYaml(provider),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

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
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
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
    );
  }
}

class _SettingsCredentialField extends StatefulWidget {
  const _SettingsCredentialField({
    required this.controller,
    required this.providerId,
    required this.reference,
    required this.onChanged,
  });

  final AgentAwesomeAppController controller;
  final String providerId;
  final String reference;
  final ValueChanged<String> onChanged;

  /// Creates state for an async masked credential lookup field.
  @override
  State<_SettingsCredentialField> createState() =>
      _SettingsCredentialFieldState();
}

class _SettingsCredentialFieldState extends State<_SettingsCredentialField> {
  final TextEditingController _controller = TextEditingController();
  bool _obscureText = true;
  CredentialLookup? _lookup;
  bool _loading = true;
  bool _saving = false;

  /// Loads the initial credential display state.
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Cleans up secret input state.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Reloads when the configured credential reference changes.
  @override
  void didUpdateWidget(covariant _SettingsCredentialField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) {
      _lookup = null;
      _loading = true;
      unawaited(_load());
    }
  }

  /// Builds a password-style API key field backed by the OS keyring.
  @override
  Widget build(BuildContext context) {
    final lookup = _lookup;
    final hasTypedSecret = _controller.text.isNotEmpty;
    final canReveal = hasTypedSecret || (lookup?.found ?? false);
    final copyableSecret = _copyableSecret(lookup, hasTypedSecret);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _controller,
        obscureText: hasTypedSecret && _obscureText,
        enabled: !_saving,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => unawaited(_saveSecret()),
        decoration: SettingsInputDecoration.field(
          context,
          label: 'API key',
          floatingLabelBehavior: lookup?.found ?? false
              ? FloatingLabelBehavior.always
              : FloatingLabelBehavior.auto,
          hintText: _hintText(lookup),
          suffixIcon: Wrap(
            spacing: 2,
            children: <Widget>[
              IconButton(
                onPressed: canReveal
                    ? () => setState(() => _obscureText = !_obscureText)
                    : null,
                tooltip: _obscureText ? 'Show API key' : 'Hide API key',
                icon: Icon(
                  _obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              if (copyableSecret.isNotEmpty)
                IconButton(
                  onPressed: () => unawaited(_copySecret(copyableSecret)),
                  tooltip: 'Copy API key',
                  icon: const Icon(Icons.copy_outlined),
                ),
              IconButton(
                onPressed: hasTypedSecret && !_saving
                    ? () => unawaited(_saveSecret())
                    : null,
                tooltip: 'Save API key to OS keyring',
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
              ),
              IconButton(
                onPressed: widget.reference.trim().isNotEmpty && !_saving
                    ? () => unawaited(_deleteSecret())
                    : null,
                tooltip: 'Delete API key from OS keyring',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          suffixIconConstraints: BoxConstraints(
            minWidth: copyableSecret.isEmpty ? 144 : 192,
          ),
        ),
      ),
    );
  }

  /// Copies the revealed API key.
  Future<void> _copySecret(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
  }

  /// Saves the typed API key into the OS keyring.
  Future<void> _saveSecret() async {
    final secret = _controller.text.trim();
    if (secret.isEmpty) {
      return;
    }
    final reference = _credentialReference();
    setState(() {
      _saving = true;
    });
    final result = await widget.controller.storeCredential(
      reference: reference,
      secret: secret,
    );
    if (!mounted) {
      return;
    }
    if (!result.success) {
      setState(() {
        _saving = false;
      });
      return;
    }
    _controller.clear();
    widget.onChanged(reference);
    final lookup = await widget.controller.lookupCredential(reference);
    if (!mounted) {
      return;
    }
    setState(() {
      _lookup = lookup;
      _loading = false;
      _saving = false;
      _obscureText = true;
    });
  }

  /// Deletes the configured API key from the OS keyring.
  Future<void> _deleteSecret() async {
    final reference = widget.reference.trim();
    if (reference.isEmpty) {
      return;
    }
    final confirmed = await _confirmSettingsDelete(
      context,
      label: 'API key credential',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _saving = true;
    });
    await widget.controller.deleteCredential(reference);
    final lookup = await widget.controller.lookupCredential(reference);
    if (!mounted) {
      return;
    }
    setState(() {
      _lookup = lookup;
      _loading = false;
      _saving = false;
    });
  }

  /// Returns the existing credential reference or generates a provider default.
  String _credentialReference() {
    final current = widget.reference.trim();
    if (current.isNotEmpty) {
      return current;
    }
    return SettingsNameFactory.credentialNameFromProvider(widget.providerId);
  }

  /// Returns the field display text for missing, masked, or revealed secrets.
  String _hintText(CredentialLookup? lookup) {
    if (_loading) {
      return '';
    }
    if (lookup != null && lookup.found) {
      final value = _obscureText ? lookup.displayValue : lookup.secretValue;
      return '${lookup.source}: $value';
    }
    return 'Paste API key';
  }

  /// Returns the current secret when an API key is present.
  String _copyableSecret(CredentialLookup? lookup, bool hasTypedSecret) {
    if (hasTypedSecret) {
      return _controller.text;
    }
    if (lookup != null && lookup.found) {
      return lookup.secretValue;
    }
    return '';
  }

  Future<void> _load() async {
    final lookup = await widget.controller.lookupCredential(widget.reference);
    if (!mounted) {
      return;
    }
    setState(() {
      _lookup = lookup;
      _loading = false;
    });
  }
}

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
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
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
      trailing: IconButton(
        onPressed: onDelete,
        tooltip: 'Delete model',
        icon: const Icon(Icons.delete_outline),
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

class _SettingsInlineField extends StatefulWidget {
  const _SettingsInlineField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int minLines;
  final int maxLines;

  /// Creates state for blur-based inline settings edits.
  @override
  State<_SettingsInlineField> createState() => _SettingsInlineFieldState();
}

class _SettingsInlineFieldState extends State<_SettingsInlineField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focusNode = FocusNode();
  late String _savedValue = widget.value;

  /// Initializes focus tracking for blur saves.
  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  /// Keeps field text synchronized when the backing model changes.
  @override
  void didUpdateWidget(covariant _SettingsInlineField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = widget.value;
      _savedValue = widget.value;
    }
  }

  /// Cleans up field controllers.
  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Builds a compact settings text field that saves on change.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        focusNode: _focusNode,
        controller: _controller,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        onFieldSubmitted: (_) => _save(),
        decoration: SettingsInputDecoration.field(context, label: widget.label),
      ),
    );
  }

  /// Saves changed field content after focus leaves the field.
  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _save();
    }
  }

  /// Emits the new value when it differs from the saved value.
  void _save() {
    final next = _controller.text.trim();
    if (next == _savedValue.trim()) {
      return;
    }
    _savedValue = next;
    widget.onChanged(next);
  }
}

class _SettingsReadOnlyField extends StatelessWidget {
  const _SettingsReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds a read-only settings field.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: value,
        readOnly: true,
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }
}

class _SettingsAutoSaveTextField extends StatefulWidget {
  const _SettingsAutoSaveTextField({
    required this.label,
    required this.controller,
    required this.initialSavedValue,
    required this.onSave,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String initialSavedValue;
  final Future<void> Function(String value) onSave;
  final int minLines;
  final int maxLines;

  @override
  State<_SettingsAutoSaveTextField> createState() =>
      _SettingsAutoSaveTextFieldState();
}

class _SettingsAutoSaveTextFieldState
    extends State<_SettingsAutoSaveTextField> {
  late final FocusNode _focusNode = FocusNode();
  late String _savedValue = widget.initialSavedValue;

  /// Initializes focus tracking for blur autosave.
  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  /// Synchronizes saved value when the selected backing item changes.
  @override
  void didUpdateWidget(covariant _SettingsAutoSaveTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSavedValue != widget.initialSavedValue) {
      _savedValue = widget.initialSavedValue;
    }
  }

  /// Cleans up field focus state.
  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  /// Builds an editable field that saves when focus leaves it.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        focusNode: _focusNode,
        controller: widget.controller,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        decoration: SettingsInputDecoration.field(context, label: widget.label),
      ),
    );
  }

  /// Saves changed field content after focus leaves the field.
  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      return;
    }
    final next = widget.controller.text.trim();
    if (next == _savedValue.trim()) {
      return;
    }
    _savedValue = next;
    unawaited(widget.onSave(next));
  }
}

class _SettingsConfigDropdown extends StatelessWidget {
  const _SettingsConfigDropdown({
    required this.label,
    required this.entries,
    required this.selectedPath,
    required this.onChanged,
  });

  final String label;
  final List<ConfigFileEntry> entries;
  final String selectedPath;
  final ValueChanged<ConfigFileEntry> onChanged;

  /// Builds a profile assignment dropdown for config files.
  @override
  Widget build(BuildContext context) {
    final selected = entries.any((entry) => entry.path == selectedPath)
        ? selectedPath
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final entry in entries)
            DropdownMenuItem<String>(
              value: entry.path,
              child: Text(entry.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (path) {
          if (path == null) {
            return;
          }
          for (final entry in entries) {
            if (entry.path == path) {
              onChanged(entry);
              return;
            }
          }
        },
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }
}

class _SettingsMcpServerAssignmentDropdown extends StatelessWidget {
  const _SettingsMcpServerAssignmentDropdown({
    required this.label,
    required this.kind,
    required this.servers,
    required this.onChanged,
  });

  final String label;
  final String kind;
  final List<McpServerRuntime> servers;
  final ValueChanged<McpServerRuntime> onChanged;

  /// Builds a role-specific MCP server assignment dropdown.
  @override
  Widget build(BuildContext context) {
    final choices = servers.where((server) => server.kind == kind).toList();
    final selected = _selectedServerId(choices);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final server in choices)
            DropdownMenuItem<String>(
              value: server.id,
              child: Text(_labelFor(server), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: choices.isEmpty
            ? null
            : (id) {
                if (id == null) {
                  return;
                }
                for (final server in choices) {
                  if (server.id == id) {
                    onChanged(server);
                    return;
                  }
                }
              },
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }

  /// Returns the active server id for this MCP role.
  String? _selectedServerId(List<McpServerRuntime> choices) {
    for (final server in choices) {
      if (server.enabled) {
        return server.id;
      }
    }
    return choices.isEmpty ? null : choices.first.id;
  }

  /// Returns a readable server label for assignment choices.
  String _labelFor(McpServerRuntime server) {
    if (server.label.trim().isNotEmpty) {
      return server.label;
    }
    return server.id;
  }
}

/// _SummaryModelOption describes one exact model available for app summaries.
class _SummaryModelOption {
  /// Creates an app summary model dropdown option.
  const _SummaryModelOption({
    required this.configPath,
    required this.modelRef,
    required this.label,
    required this.isConfigDefault,
  });

  /// Model config file containing this option.
  final String configPath;

  /// Provider:model reference inside the model config file.
  final String modelRef;

  /// Human-readable dropdown label.
  final String label;

  /// Whether this option matches the config file's top-level default.
  final bool isConfigDefault;
}

/// _SettingsSummaryModelDropdown selects a provider:model for title summaries.
class _SettingsSummaryModelDropdown extends StatelessWidget {
  /// Creates an exact summary model selector.
  const _SettingsSummaryModelDropdown({
    required this.label,
    required this.entries,
    required this.selectedPath,
    required this.selectedModelRef,
    required this.onChanged,
  });

  final String label;
  final List<ConfigFileEntry> entries;
  final String selectedPath;
  final String selectedModelRef;
  final ValueChanged<_SummaryModelOption> onChanged;

  /// Builds a dropdown of exact app-owned model choices.
  @override
  Widget build(BuildContext context) {
    final options = _options();
    final selected = _selectedOption(options);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<_SummaryModelOption>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<_SummaryModelOption>>[
          for (final option in options)
            DropdownMenuItem<_SummaryModelOption>(
              value: option,
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: options.isEmpty
            ? null
            : (option) {
                if (option != null) {
                  onChanged(option);
                }
              },
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }

  /// Returns flattened provider:model choices from config file metadata.
  List<_SummaryModelOption> _options() {
    final options = <_SummaryModelOption>[];
    final multipleConfigs = entries.length > 1;
    for (final entry in entries) {
      for (final choice in entry.modelChoices) {
        options.add(
          _SummaryModelOption(
            configPath: entry.path,
            modelRef: choice.ref,
            label: SettingsConfigLabels.summaryModelLabel(
              entry: entry,
              choice: choice,
              includeConfig: multipleConfigs,
            ),
            isConfigDefault: choice.isDefault,
          ),
        );
      }
    }
    return options;
  }

  /// Returns the currently selected option, falling back to config defaults.
  _SummaryModelOption? _selectedOption(List<_SummaryModelOption> options) {
    if (options.isEmpty) {
      return null;
    }
    final selectedPath = this.selectedPath.trim();
    final selectedRef = selectedModelRef.trim();
    if (selectedPath.isNotEmpty && selectedRef.isNotEmpty) {
      for (final option in options) {
        if (option.configPath == selectedPath &&
            option.modelRef == selectedRef) {
          return option;
        }
      }
    }
    if (selectedPath.isNotEmpty) {
      for (final option in options) {
        if (option.configPath == selectedPath && option.isConfigDefault) {
          return option;
        }
      }
      for (final option in options) {
        if (option.configPath == selectedPath) {
          return option;
        }
      }
    }
    return options.first;
  }
}

/// _SettingsProfileDropdown selects one configured runtime profile file.
class _SettingsProfileDropdown extends StatelessWidget {
  /// Creates a runtime profile dropdown for app settings.
  const _SettingsProfileDropdown({
    required this.label,
    required this.entries,
    required this.selectedPath,
    required this.onChanged,
  });

  /// Field label shown above the dropdown.
  final String label;

  /// Runtime profiles available for selection.
  final List<RuntimeProfileFileEntry> entries;

  /// Currently selected profile path.
  final String selectedPath;

  /// Callback fired with the selected profile entry.
  final ValueChanged<RuntimeProfileFileEntry> onChanged;

  /// Builds an app setting dropdown for runtime profile files.
  @override
  Widget build(BuildContext context) {
    final selected = entries.any((entry) => entry.path == selectedPath)
        ? selectedPath
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final entry in entries)
            DropdownMenuItem<String>(
              value: entry.path,
              child: Text(entry.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (path) {
          if (path == null) {
            return;
          }
          for (final entry in entries) {
            if (entry.path == path) {
              onChanged(entry);
              return;
            }
          }
        },
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({required this.children});

  final List<Widget> children;

  /// Builds settings action buttons with standard spacing.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: children),
    );
  }
}

/// Confirms a destructive settings deletion.
Future<bool> _confirmSettingsDelete(
  BuildContext context, {
  required String label,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Delete configuration'),
        content: Text('Delete "$label"? This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

class _SettingsTextFileEditor extends StatefulWidget {
  const _SettingsTextFileEditor({
    required this.controller,
    required this.title,
    required this.path,
  });

  final AgentAwesomeAppController controller;
  final String title;
  final String path;

  @override
  State<_SettingsTextFileEditor> createState() =>
      _SettingsTextFileEditorState();
}

class _SettingsTextFileEditorState extends State<_SettingsTextFileEditor> {
  final TextEditingController _content = TextEditingController();
  final FocusNode _contentFocus = FocusNode();
  String _savedContent = '';
  bool _loading = true;

  /// Loads the file editor content.
  @override
  void initState() {
    super.initState();
    _contentFocus.addListener(_handleContentFocusChange);
    unawaited(_load());
  }

  /// Reloads editor content when the target file path changes.
  @override
  void didUpdateWidget(covariant _SettingsTextFileEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      unawaited(_load());
    }
  }

  /// Cleans up the text editor controller.
  @override
  void dispose() {
    _contentFocus.removeListener(_handleContentFocusChange);
    _contentFocus.dispose();
    _content.dispose();
    super.dispose();
  }

  /// Builds a raw editor for the referenced configuration file.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: widget.title,
      children: <Widget>[
        _SettingsReadOnlyField(label: 'Path', value: widget.path),
        if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          TextFormField(
            focusNode: _contentFocus,
            controller: _content,
            minLines: 14,
            maxLines: 28,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: SettingsInputDecoration.field(
              context,
              alignLabelWithHint: true,
              label: 'File content',
            ),
          ),
        const SizedBox(height: 12),
        _SettingsActionRow(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      _content.text = await widget.controller.readConfigurationFile(
        widget.path,
      );
      _savedContent = _content.text;
      if (!mounted) {
        return;
      }
    } catch (error) {
      _content.text = '';
      _savedContent = '';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_content.text == _savedContent) {
      return;
    }
    try {
      await widget.controller.saveConfigurationFile(widget.path, _content.text);
      _savedContent = _content.text;
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }

  /// Saves changed file content after focus leaves the editor.
  void _handleContentFocusChange() {
    if (_contentFocus.hasFocus || _loading) {
      return;
    }
    unawaited(_save());
  }
}
