/// Settings tool configuration editor widget.
part of 'settings_panel.dart';

const String _defaultLocalExecTimeout = '30s';
const int _defaultLocalExecMaxOutputBytes = 1048576;
const String _allValidationRunId = '__all__';

class _SettingsToolConfigEditor extends StatefulWidget {
  const _SettingsToolConfigEditor({
    super.key,
    required this.controller,
    required this.entry,
    required this.surface,
    required this.modeId,
    required this.validationTabId,
    required this.query,
    required this.onRenamed,
    required this.onDocumentChanged,
  });

  final AgentAwesomeAppController controller;
  final ConfigFileEntry entry;
  final _ToolSettingsSurface surface;
  final String modeId;
  final String validationTabId;
  final String query;
  final ValueChanged<String> onRenamed;
  final ValueChanged<ToolConfigDocument> onDocumentChanged;

  /// Creates state for editing structured tool config content.
  @override
  State<_SettingsToolConfigEditor> createState() =>
      _SettingsToolConfigEditorState();
}

class _SettingsToolConfigEditorState extends State<_SettingsToolConfigEditor> {
  ToolConfigDocument? _document;
  ToolValidationSuiteResult? _validationResult;
  String _validationError = '';
  bool _loading = true;
  bool _validationRunning = false;
  bool _installVerifying = false;
  String _validationRunningId = '';
  Set<String> _validationRunningIds = const <String>{};
  String _validationRunMode = 'mocked';
  String _validationRunningMode = '';
  int _validationResultRevision = 0;

  /// Loads the selected tool config file.
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Reloads structured state when the selected file changes.
  @override
  void didUpdateWidget(covariant _SettingsToolConfigEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path) {
      _document = null;
      _validationResult = null;
      _validationError = '';
      _validationRunning = false;
      _installVerifying = false;
      _validationRunningId = '';
      _validationRunningIds = const <String>{};
      _validationRunningMode = '';
      _validationResultRevision++;
      _loading = true;
      unawaited(_load());
    }
  }

  /// Builds the selected tool config editor.
  @override
  Widget build(BuildContext context) {
    final document = _document;
    if (document != null &&
        !SettingsQuery.matches(
          widget.query,
          _searchValues(document, widget.surface),
        )) {
      return PanelEmptyState(query: widget.query);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (document == null) {
      return FormPanel(
        children: <Widget>[
          FormPlainSection(
            title: 'Tool config',
            children: <Widget>[
              _SettingsReadOnlyField(label: 'Path', value: widget.entry.path),
            ],
          ),
        ],
      );
    }
    if (widget.modeId == _toolSurfaceValidationsMode) {
      final validations = _selectedValidations(document);
      return FormPanel(
        children: <Widget>[
          _SettingsToolValidationCard(
            title: widget.surface == _ToolSettingsSurface.osTools
                ? 'Command validations'
                : 'MCP validations',
            document: document,
            surface: widget.surface,
            validations: validations,
            validationTabId: widget.validationTabId,
            result: _validationResult,
            error: _validationError,
            selectedRunMode: _validationRunMode,
            runningMode: _validationRunningMode,
            runningIds: _validationRunningIds,
            runningAll: _validationRunningId == _allValidationRunId,
            installVerifying: _installVerifying,
            onRunAll: (request) => unawaited(_runValidations(request)),
            onVerifyInstall: widget.surface == _ToolSettingsSurface.osTools
                ? () => unawaited(_verifyToolInstall(document, validations))
                : null,
            onAddValidation:
                _canAddToolValidation(
                  document,
                  widget.surface,
                  widget.validationTabId,
                )
                ? () => unawaited(_addValidation(document))
                : null,
            onRunValidation: (request) => unawaited(_runValidations(request)),
            onDeleteValidation: (scenario) =>
                unawaited(_deleteValidationScenario(scenario)),
          ),
        ],
      );
    }
    if (widget.modeId == _toolSurfaceDetailsMode) {
      return _SettingsToolConfigDetailsEditor(
        controller: widget.controller,
        entry: widget.entry,
        document: document,
        surface: widget.surface,
        onRenamed: widget.onRenamed,
        onDocumentChanged: _save,
      );
    }
    final localExec = _localExecWithDetailsDefaults(document.localExec);
    return FormPanel(
      children: <Widget>[
        if (widget.surface == _ToolSettingsSurface.osTools)
          _SettingsLocalExecCard(
            config: localExec,
            onChanged: (localExec) {
              unawaited(_save(document.copyWith(localExec: localExec)));
            },
          )
        else
          _SettingsMcpToolsetsCard(
            config: document.mcp,
            profileServers:
                widget.controller.runtimeProfile?.mcpServers ??
                const <McpServerRuntime>[],
            onChanged: (mcp) {
              unawaited(_save(document.copyWith(mcp: mcp)));
            },
            onAddServer: () => unawaited(_addMcpServer(document)),
            onDeleteServer: (index) =>
                unawaited(_deleteMcpServer(document, index)),
            onServerChanged: (index, server) {
              final servers = <McpServerToolConfig>[
                for (var i = 0; i < document.mcp.servers.length; i++)
                  i == index ? server : document.mcp.servers[i],
              ];
              unawaited(
                _save(
                  document.copyWith(
                    mcp: document.mcp.copyWith(servers: servers),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  /// Returns values used by the selected-surface search filter.
  List<String> _searchValues(
    ToolConfigDocument document,
    _ToolSettingsSurface surface,
  ) {
    final base = <String>[widget.entry.label, widget.entry.path];
    return switch (surface) {
      _ToolSettingsSurface.osTools => <String>[
        ...base,
        'OS Tools',
        'command_execute',
        'command_template',
        for (final command in document.localExec.commands) ...<String>[
          command.name,
          command.executable,
          command.description,
          command.args.join(' '),
          for (final operation in command.operations) ...<String>[
            operation.name,
            operation.description,
            operation.args.join(' '),
          ],
        ],
        for (final preset in document.nodePresets) ...<String>[
          preset.id,
          preset.label,
          preset.description,
          preset.action,
        ],
        for (final validation in document.validations) ...<String>[
          validation.id,
          validation.label,
          validation.target.presetId,
          validation.target.command,
          validation.target.operation,
          validation.target.mcpServer,
          validation.target.mcpTool,
          validation.description,
        ],
      ],
      _ToolSettingsSurface.mcpServer => <String>[
        ...base,
        'MCP Server',
        for (final server in document.mcp.servers) ...<String>[
          server.name,
          server.transport,
          server.command,
          mcpServerEndpoint(server),
          server.tools.allow.join(' '),
        ],
        for (final preset in document.nodePresets) ...<String>[
          preset.id,
          preset.label,
          preset.description,
          preset.action,
        ],
        for (final validation in document.validations) ...<String>[
          validation.id,
          validation.label,
          validation.target.presetId,
          validation.target.command,
          validation.target.operation,
          validation.target.mcpServer,
          validation.target.mcpTool,
          validation.description,
        ],
      ],
    };
  }

  /// Returns node preset ids that belong to the active settings surface.
  Set<String> _surfacePresetIds(ToolConfigDocument document) {
    final action = widget.surface == _ToolSettingsSurface.osTools
        ? 'command.execute'
        : 'mcp.call';
    return document.nodePresets
        .where((preset) => preset.action == action)
        .map((preset) => preset.id)
        .toSet();
  }

  /// Returns validations whose targets belong to the active surface.
  List<ToolValidationConfig> _surfaceValidations(ToolConfigDocument document) {
    final presetIds = _surfacePresetIds(document);
    return document.validations
        .where((validation) => _validationMatchesSurface(validation, presetIds))
        .toList();
  }

  /// Returns validations for the active validation tab.
  List<ToolValidationConfig> _selectedValidations(ToolConfigDocument document) {
    return _surfaceValidations(document)
        .where(
          (validation) =>
              _validationConfigMatchesTab(validation, widget.validationTabId),
        )
        .toList();
  }

  /// Returns whether one validation target belongs to the active surface.
  bool _validationMatchesSurface(
    ToolValidationConfig validation,
    Set<String> presetIds,
  ) {
    final target = validation.target;
    return switch (widget.surface) {
      _ToolSettingsSurface.osTools =>
        target.type == 'command-operation' ||
            target.command.isNotEmpty ||
            presetIds.contains(target.presetId),
      _ToolSettingsSurface.mcpServer =>
        target.type == 'mcp-tool' ||
            target.mcpTool.isNotEmpty ||
            presetIds.contains(target.presetId),
    };
  }

  /// Loads and parses the selected tool config.
  Future<void> _load() async {
    try {
      final entryPath = widget.entry.path;
      final content = await widget.controller.readConfigurationFile(entryPath);
      final document = ToolConfigDocument.parse(content);
      widget.onDocumentChanged(document);
      if (!mounted) {
        return;
      }
      setState(() {
        _document = document;
        _loading = false;
      });
      final validationRevision = _validationResultRevision;
      final validationResult = await _loadValidationResultCache(entryPath);
      if (!mounted ||
          widget.entry.path != entryPath ||
          validationRevision != _validationResultRevision) {
        return;
      }
      setState(() {
        _validationResult = validationResult;
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

  /// Saves a typed tool config document after local validation.
  Future<void> _save(ToolConfigDocument document) async {
    final validationError = toolConfigValidationError(document);
    if (validationError.isNotEmpty) {
      return;
    }
    try {
      await widget.controller.saveConfigurationFile(
        widget.entry.path,
        document.toYaml(),
      );
      await widget.controller.refreshConfigurationCollections();
      widget.onDocumentChanged(document);
      if (!mounted) {
        return;
      }
      setState(() {
        _document = document;
      });
    } catch (_) {}
  }

  /// Runs configured validations for the selected tool package.
  Future<void> _runValidations(SettingsValidationRunRequest request) async {
    if (_validationRunning) {
      return;
    }
    final document = _document;
    if (document == null) {
      return;
    }
    final selectedIds = <String>[
      for (final id in request.validationIds)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    if (selectedIds.isEmpty && !request.allowEmpty) {
      setState(() {
        _validationError =
            'No ${_settingsValidationModeLabel(request.mode).toLowerCase()} validations configured for this selection.';
      });
      return;
    }
    final runMode = _settingsValidationModeValue(request.mode);
    setState(() {
      _validationResultRevision++;
      _validationRunning = true;
      _validationRunningId =
          selectedIds.isEmpty ||
              selectedIds.length == _selectedValidations(document).length
          ? _allValidationRunId
          : selectedIds.join(',');
      _validationRunningIds = selectedIds.toSet();
      _validationRunMode = runMode;
      _validationRunningMode = runMode;
      _validationError = '';
    });
    try {
      final result = await widget.controller.runToolPackageValidations(
        widget.entry.path,
        validationIds: selectedIds,
        mode: runMode == 'all' ? '' : runMode,
        requireAssertions: true,
        requireCoverage: selectedIds.isEmpty,
        requireInputSchemas: selectedIds.isEmpty,
      );
      if (!mounted) {
        return;
      }
      final merged = selectedIds.isEmpty
          ? result
          : _mergedValidationResults(_validationResult, result);
      setState(() {
        _validationResult = merged;
        _validationRunning = false;
        _validationRunningId = '';
        _validationRunningIds = const <String>{};
        _validationRunningMode = '';
      });
      try {
        await _saveValidationResultCache(merged);
      } catch (_) {}
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _validationError = error.toString();
        _validationRunning = false;
        _validationRunningId = '';
        _validationRunningIds = const <String>{};
        _validationRunningMode = '';
      });
    }
  }

  /// Verifies selected local executables and records the result in config.
  Future<void> _verifyToolInstall(
    ToolConfigDocument document,
    List<ToolValidationConfig> validations,
  ) async {
    if (_installVerifying) {
      return;
    }
    final commandNames = _toolValidationCommandNames(validations);
    setState(() {
      _installVerifying = true;
      _validationError = '';
    });
    try {
      final commands = <LocalExecCommandConfig>[];
      for (final command in document.localExec.commands) {
        if (commandNames.isNotEmpty && !commandNames.contains(command.name)) {
          commands.add(command);
          continue;
        }
        commands.add(
          command.copyWith(
            installation: await _verifyLocalExecCommandInstall(command),
          ),
        );
      }
      await _save(
        document.copyWith(
          localExec: document.localExec.copyWith(commands: commands),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _validationError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _installVerifying = false);
      }
    }
  }

  /// Adds starter validations for the next uncovered tool target.
  Future<void> _addValidation(ToolConfigDocument document) async {
    final additions = _defaultToolValidationSet(
      document,
      widget.surface,
      tabId: widget.validationTabId,
    );
    if (additions.isEmpty) {
      return;
    }
    await _save(
      document.copyWith(
        validations: <ToolValidationConfig>[
          ...document.validations,
          ...additions,
        ],
      ),
    );
  }

  /// Loads the last persisted validation result for this tool config.
  Future<ToolValidationSuiteResult?> _loadValidationResultCache(
    String entryPath,
  ) async {
    try {
      final file = File(
        _toolValidationResultCachePath(widget.controller, entryPath),
      );
      if (!file.existsSync()) {
        return null;
      }
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        return ToolValidationSuiteResult.fromJson(decoded);
      }
      if (decoded is Map) {
        return ToolValidationSuiteResult.fromJson(<String, dynamic>{
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value,
        });
      }
    } catch (_) {}
    return null;
  }

  /// Persists the latest validation result outside source-controlled config.
  Future<void> _saveValidationResultCache(
    ToolValidationSuiteResult result,
  ) async {
    final file = File(
      _toolValidationResultCachePath(widget.controller, widget.entry.path),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result.toJson()),
    );
  }

  /// Deletes every configured lane for one validation scenario.
  Future<void> _deleteValidationScenario(
    SettingsValidationScenario scenario,
  ) async {
    final document = _document;
    if (document == null) {
      return;
    }
    final ids = scenario.allValidationIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    final confirmed = await _confirmSettingsDelete(
      context,
      label: scenario.label,
    );
    if (!confirmed) {
      return;
    }
    await _save(
      document.copyWith(
        validations: <ToolValidationConfig>[
          for (final validation in document.validations)
            if (!ids.contains(validation.id)) validation,
        ],
      ),
    );
  }

  /// Adds an MCP server through a required-field dialog.
  Future<void> _addMcpServer(ToolConfigDocument document) async {
    final server = await showDialog<McpServerToolConfig>(
      context: context,
      builder: (context) {
        return _McpServerDialog(seed: _suggestedProfileServer(document));
      },
    );
    if (server == null) {
      return;
    }
    await _save(
      document.copyWith(
        mcp: document.mcp.copyWith(
          enabled: true,
          servers: <McpServerToolConfig>[...document.mcp.servers, server],
        ),
      ),
    );
  }

  /// Deletes an MCP server and disables MCP if no servers remain.
  Future<void> _deleteMcpServer(ToolConfigDocument document, int index) async {
    final server = document.mcp.servers[index];
    final confirmed = await _confirmSettingsDelete(context, label: server.name);
    if (!confirmed) {
      return;
    }
    final servers = <McpServerToolConfig>[
      for (var i = 0; i < document.mcp.servers.length; i++)
        if (i != index) document.mcp.servers[i],
    ];
    await _save(
      document.copyWith(
        mcp: document.mcp.copyWith(
          enabled: servers.isNotEmpty && document.mcp.enabled,
          servers: servers,
        ),
      ),
    );
  }

  /// Returns a profile MCP server not already present in the tool config.
  McpServerRuntime? _suggestedProfileServer(ToolConfigDocument document) {
    final existingNames = document.mcp.servers.map((server) => server.name);
    for (final server
        in widget.controller.runtimeProfile?.mcpServers ??
            const <McpServerRuntime>[]) {
      final name = SettingsNameFactory.toolNameFromLabel(
        server.kind.isEmpty ? server.id : server.kind,
      );
      if (!existingNames.contains(name)) {
        return server;
      }
    }
    return null;
  }
}

class _SettingsToolConfigDetailsEditor extends StatefulWidget {
  const _SettingsToolConfigDetailsEditor({
    required this.controller,
    required this.entry,
    required this.document,
    required this.surface,
    required this.onRenamed,
    required this.onDocumentChanged,
  });

  final AgentAwesomeAppController controller;
  final ConfigFileEntry entry;
  final ToolConfigDocument document;
  final _ToolSettingsSurface surface;
  final ValueChanged<String> onRenamed;
  final Future<void> Function(ToolConfigDocument document) onDocumentChanged;

  /// Creates state for high-level tool package details editing.
  @override
  State<_SettingsToolConfigDetailsEditor> createState() =>
      _SettingsToolConfigDetailsEditorState();
}

class _SettingsToolConfigDetailsEditorState
    extends State<_SettingsToolConfigDetailsEditor> {
  late final TextEditingController _name = TextEditingController(
    text: _displayName(),
  );
  late String _savedName = _displayName();

  /// Cleans up details field controllers.
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Rehydrates high-level fields when the selected package changes.
  @override
  void didUpdateWidget(covariant _SettingsToolConfigDetailsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextName = _displayName();
    if (oldWidget.entry.path != widget.entry.path ||
        oldWidget.document.extra['name'] != widget.document.extra['name']) {
      _name.text = nextName;
      _savedName = nextName;
    }
  }

  /// Builds the selected package details.
  @override
  Widget build(BuildContext context) {
    return FormPanel(
      children: <Widget>[
        FormPlainSection(
          title: widget.surface == _ToolSettingsSurface.osTools
              ? 'Tool'
              : 'MCP Server',
          children: <Widget>[
            _SettingsAutoSaveTextField(
              label: 'Name',
              controller: _name,
              initialSavedValue: _savedName,
              onSave: _rename,
            ),
            _SettingsReadOnlyField(label: 'Path', value: widget.entry.path),
            if (widget.surface == _ToolSettingsSurface.osTools)
              _SettingsLocalExecDetailsFields(
                config: _localExecWithDetailsDefaults(
                  widget.document.localExec,
                ),
                onChanged: (localExec) => unawaited(
                  widget.onDocumentChanged(
                    widget.document.copyWith(localExec: localExec),
                  ),
                ),
              ),
            if (widget.surface == _ToolSettingsSurface.osTools)
              _SettingsActionRow(
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: widget.entry.assigned
                        ? null
                        : () => unawaited(_assign()),
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      widget.entry.assigned ? 'Assigned' : 'Use for profile',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  /// Returns the visible package display name.
  String _displayName() {
    final name = '${widget.document.extra['name'] ?? ''}'.trim();
    if (name.isNotEmpty) {
      return name;
    }
    return widget.entry.label;
  }

  /// Assigns the selected tool package to the active runtime profile.
  Future<void> _assign() async {
    try {
      await widget.controller.assignConfigFile(widget.entry);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }

  /// Saves the user-facing package name into typed config metadata.
  Future<void> _rename(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final extra = Map<String, dynamic>.from(widget.document.extra);
    extra['name'] = trimmed;
    final document = widget.document.copyWith(extra: extra);
    final validationError = toolConfigValidationError(document);
    if (validationError.isNotEmpty) {
      return;
    }
    try {
      final path = await widget.controller.renameConfigFile(
        widget.entry,
        trimmed,
      );
      widget.onRenamed(path);
      await widget.controller.saveConfigurationFile(path, document.toYaml());
      await widget.controller.refreshConfigurationCollections();
      if (!mounted) {
        return;
      }
      setState(() => _savedName = trimmed);
    } catch (_) {}
  }
}

class _SettingsLocalExecDetailsFields extends StatelessWidget {
  const _SettingsLocalExecDetailsFields({
    required this.config,
    required this.onChanged,
  });

  final LocalExecToolConfig config;
  final ValueChanged<LocalExecToolConfig> onChanged;

  /// Builds global local command execution details.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsToggleField(
          title: 'Enabled',
          value: config.enabled,
          onChanged: (enabled) => onChanged(config.copyWith(enabled: enabled)),
        ),
        _SettingsInlineField(
          label: 'Default timeout',
          value: config.defaultTimeout,
          onChanged: (value) =>
              onChanged(config.copyWith(defaultTimeout: value)),
        ),
        _SettingsInlineField(
          label: 'Default max output bytes',
          value: config.defaultMaxOutputBytes.toString(),
          onChanged: (value) => onChanged(
            config.copyWith(
              defaultMaxOutputBytes:
                  int.tryParse(value) ?? _defaultLocalExecMaxOutputBytes,
            ),
          ),
        ),
      ],
    );
  }
}

/// Returns local exec settings with product defaults applied for editing.
LocalExecToolConfig _localExecWithDetailsDefaults(LocalExecToolConfig config) {
  return config.copyWith(
    defaultTimeout: config.defaultTimeout.trim().isEmpty
        ? _defaultLocalExecTimeout
        : config.defaultTimeout,
    defaultMaxOutputBytes: config.defaultMaxOutputBytes == 0
        ? _defaultLocalExecMaxOutputBytes
        : config.defaultMaxOutputBytes,
  );
}

/// Indexes tool validation runner results by id and callable target.
class _ToolValidationResultIndex {
  _ToolValidationResultIndex(Iterable<ToolValidationRunResult> source)
    : results = List<ToolValidationRunResult>.unmodifiable(source) {
    for (final result in results) {
      final id = result.id.trim();
      if (id.isNotEmpty) {
        byId[id] = result;
      }
      final targetKey = _toolValidationResultTargetKey(result.target);
      final mode = _toolValidationConfigMode(result.mode);
      if (targetKey.isNotEmpty) {
        byTargetAndMode
            .putIfAbsent('$targetKey|$mode', () => <ToolValidationRunResult>[])
            .add(result);
      }
    }
  }

  /// Runner results in the order emitted by the validation service.
  final List<ToolValidationRunResult> results;

  /// Runner results keyed by configured validation id.
  final Map<String, ToolValidationRunResult> byId =
      <String, ToolValidationRunResult>{};

  /// Runner results keyed by target and mode for id-renamed scenarios.
  final Map<String, List<ToolValidationRunResult>> byTargetAndMode =
      <String, List<ToolValidationRunResult>>{};

  /// Returns the best result for one configured validation case.
  ToolValidationRunResult? resultFor(ToolValidationConfig validation) {
    final exact = byId[validation.id.trim()];
    if (exact != null) {
      return exact;
    }
    final targetKey = _toolValidationConfigTargetKey(validation.target);
    if (targetKey.isEmpty) {
      return null;
    }
    final mode = _toolValidationConfigMode(validation.mode);
    final candidates = byTargetAndMode['$targetKey|$mode'];
    if (candidates == null || candidates.length != 1) {
      return null;
    }
    return candidates.single;
  }
}

/// Builds reusable scenario rows from configured tool validations.
List<SettingsValidationScenario> _toolValidationScenarios(
  ToolConfigDocument document,
  List<ToolValidationConfig> validations,
  _ToolValidationResultIndex resultIndex,
  String validationTabId,
) {
  final groups = <String, List<ToolValidationConfig>>{};
  for (final validation in validations) {
    final key = _toolValidationScenarioKey(validation);
    groups.putIfAbsent(key, () => <ToolValidationConfig>[]).add(validation);
  }
  final matchedResults = <ToolValidationRunResult>{};
  return <SettingsValidationScenario>[
    for (final entry in groups.entries)
      _toolValidationScenarioFromGroup(
        document,
        entry.key,
        entry.value,
        resultIndex,
        matchedResults,
      ),
    ..._unmatchedToolValidationScenarios(
      document,
      resultIndex.results,
      matchedResults,
      validationTabId,
    ),
  ];
}

/// Converts one grouped scenario into table row metadata.
SettingsValidationScenario _toolValidationScenarioFromGroup(
  ToolConfigDocument document,
  String id,
  List<ToolValidationConfig> validations,
  _ToolValidationResultIndex resultIndex,
  Set<ToolValidationRunResult> matchedResults,
) {
  final seed = validations.first;
  final resultPairs =
      <({ToolValidationConfig validation, ToolValidationRunResult result})>[];
  for (final validation in validations) {
    final result = resultIndex.resultFor(validation);
    if (result != null) {
      resultPairs.add((validation: validation, result: result));
    }
  }
  for (final pair in resultPairs) {
    matchedResults.add(pair.result);
  }
  final details = resultPairs.isEmpty
      ? null
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (
              var index = 0;
              index < resultPairs.length;
              index++
            ) ...<Widget>[
              if (index > 0)
                const SizedBox(height: SettingsFormMetrics.compactGap),
              Text(
                resultPairs[index].result.label.isEmpty
                    ? resultPairs[index].result.id
                    : resultPairs[index].result.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              SettingsToolValidationEvidenceView(
                result: resultPairs[index].result,
                targetLabel: _toolValidationTargetPreview(
                  resultPairs[index].validation,
                  document,
                ),
              ),
            ],
          ],
        );
  return SettingsValidationScenario(
    id: id,
    label: seed.label.isEmpty ? seed.id : seed.label,
    description: _toolValidationScenarioDescription(seed),
    modeStates: <String, SettingsValidationModeState>{
      for (final mode in const <String>['mocked', 'live'])
        mode: _toolValidationModeState(mode, validations, resultIndex),
    },
    status: _toolValidationScenarioStatus(validations, resultIndex),
    details: details,
  );
}

/// Returns mode status metadata for one scenario group.
SettingsValidationModeState _toolValidationModeState(
  String mode,
  List<ToolValidationConfig> validations,
  _ToolValidationResultIndex resultIndex,
) {
  final lane = validations.where((validation) {
    return _toolValidationConfigMode(validation.mode) == mode;
  }).toList();
  final result = _firstToolValidationResult(lane, resultIndex);
  return SettingsValidationModeState(
    mode: mode,
    validationIds: <String>[for (final validation in lane) validation.id],
    status: result == null ? '' : _toolValidationRunStatus(result),
    configured: lane.isNotEmpty,
  );
}

/// Returns the first available result for configured validations.
ToolValidationRunResult? _firstToolValidationResult(
  List<ToolValidationConfig> validations,
  _ToolValidationResultIndex resultIndex,
) {
  for (final validation in validations) {
    final result = resultIndex.resultFor(validation);
    if (result != null) {
      return result;
    }
  }
  return null;
}

/// Returns cached runner results that were not matched to configured rows.
List<SettingsValidationScenario> _unmatchedToolValidationScenarios(
  ToolConfigDocument document,
  List<ToolValidationRunResult> results,
  Set<ToolValidationRunResult> matchedResults,
  String validationTabId,
) {
  final scenarios = <SettingsValidationScenario>[];
  for (var index = 0; index < results.length; index++) {
    final result = results[index];
    if (matchedResults.contains(result) ||
        !_toolValidationResultMatchesTab(result, validationTabId)) {
      continue;
    }
    scenarios.add(_toolValidationScenarioFromResult(document, result, index));
  }
  return scenarios;
}

/// Returns a stable scenario grouping key that ignores the validation lane.
String _toolValidationScenarioKey(ToolValidationConfig validation) {
  final label = validation.label
      .replaceAll(RegExp(r'\s+(mocked|live)$', caseSensitive: false), '')
      .trim();
  final target = validation.target;
  final id = validation.id.replaceAll(RegExp(r'_(mocked|live)$'), '');
  return <String>[
    target.type,
    target.command,
    target.operation,
    target.mcpServer,
    target.mcpTool,
    label.isEmpty ? id : label,
  ].join('|');
}

/// Returns the configured validation lane, defaulting to mocked.
String _toolValidationConfigMode(String mode) {
  return mode.trim().toLowerCase() == 'live' ? 'live' : 'mocked';
}

/// Returns a target key for configured validation matching.
String _toolValidationConfigTargetKey(ToolValidationTargetConfig target) {
  final hasCallable =
      target.command.trim().isNotEmpty ||
      target.operation.trim().isNotEmpty ||
      target.mcpServer.trim().isNotEmpty ||
      target.mcpTool.trim().isNotEmpty ||
      target.presetId.trim().isNotEmpty;
  if (!hasCallable) {
    return '';
  }
  return <String>[
    target.type.trim().toLowerCase(),
    target.command.trim(),
    target.operation.trim(),
    target.mcpServer.trim(),
    target.mcpTool.trim(),
    target.presetId.trim(),
  ].join('|');
}

/// Returns a target key for runner result matching.
String _toolValidationResultTargetKey(ToolValidationTargetResult target) {
  final hasCallable =
      target.command.trim().isNotEmpty ||
      target.operation.trim().isNotEmpty ||
      target.mcpServer.trim().isNotEmpty ||
      target.mcpTool.trim().isNotEmpty ||
      target.presetId.trim().isNotEmpty;
  if (!hasCallable) {
    return '';
  }
  return <String>[
    target.type.trim().toLowerCase(),
    target.command.trim(),
    target.operation.trim(),
    target.mcpServer.trim(),
    target.mcpTool.trim(),
    target.presetId.trim(),
  ].join('|');
}

/// Returns whether one runner result belongs under the active validation tab.
bool _toolValidationResultMatchesTab(
  ToolValidationRunResult result,
  String validationTabId,
) {
  final selected = validationTabId.trim();
  if (selected.isEmpty) {
    return true;
  }
  final targetTab = _validationTabIdForResultTarget(result.target);
  return targetTab.isEmpty || targetTab == selected;
}

/// Returns the validation tab id for a runner result target.
String _validationTabIdForResultTarget(ToolValidationTargetResult target) {
  if (target.command.isNotEmpty && target.operation.isNotEmpty) {
    return _commandValidationTabId(target.command, target.operation);
  }
  if (target.mcpServer.isNotEmpty && target.mcpTool.isNotEmpty) {
    return _mcpValidationTabId(target.mcpServer, target.mcpTool);
  }
  return '';
}

/// Builds a visible table row for a runner result without a configured row.
SettingsValidationScenario _toolValidationScenarioFromResult(
  ToolConfigDocument document,
  ToolValidationRunResult result,
  int index,
) {
  final mode = _toolValidationConfigMode(result.mode);
  final status = _toolValidationRunStatus(result);
  final modeStates = <String, SettingsValidationModeState>{
    for (final candidate in const <String>['mocked', 'live'])
      candidate: SettingsValidationModeState(
        mode: candidate,
        validationIds: const <String>[],
        status: candidate == mode ? status : '',
        configured: candidate == mode,
      ),
  };
  return SettingsValidationScenario(
    id: _toolValidationResultScenarioId(result, index),
    label: _toolValidationResultLabel(result),
    description: _toolValidationResultDescription(result),
    modeStates: modeStates,
    status: _toolValidationStatusFromModeStates(modeStates),
    details: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _toolValidationResultLabel(result),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        SettingsToolValidationEvidenceView(
          result: result,
          targetLabel: _toolValidationResultTargetPreview(result, document),
        ),
      ],
    ),
  );
}

/// Returns a stable UI id for an unmatched runner result.
String _toolValidationResultScenarioId(
  ToolValidationRunResult result,
  int index,
) {
  final id = result.id.trim();
  if (id.isNotEmpty) {
    return 'result:$id';
  }
  return 'result:${_toolValidationResultTargetKey(result.target)}:$index';
}

/// Returns a user-facing label for one runner result.
String _toolValidationResultLabel(ToolValidationRunResult result) {
  final label = result.label.trim();
  if (label.isNotEmpty) {
    return label;
  }
  final callable = _toolTargetCallableLabel(result.target);
  if (callable.trim().isNotEmpty) {
    return callable;
  }
  return 'Validation result';
}

/// Returns a user-facing validation purpose for one runner result.
String _toolValidationResultDescription(ToolValidationRunResult result) {
  final description = result.description.trim();
  if (description.isNotEmpty) {
    return description;
  }
  final callable = _toolTargetCallableLabel(result.target);
  return switch (result.target.type) {
    'agent-tool-call' => 'Agent selects $callable.',
    'workflow-node' => 'Workflow invokes $callable.',
    'mcp-tool' => 'MCP call for $callable.',
    'command-operation' => 'Command operation for $callable.',
    _ => callable,
  };
}

/// Returns a command preview for an unmatched runner result when possible.
String _toolValidationResultTargetPreview(
  ToolValidationRunResult result,
  ToolConfigDocument document,
) {
  for (final validation in document.validations) {
    if (_toolValidationConfigTargetKey(validation.target) ==
        _toolValidationResultTargetKey(result.target)) {
      return _toolValidationTargetPreview(validation, document);
    }
  }
  final target = result.target;
  if (target.command.isNotEmpty && target.operation.isNotEmpty) {
    final command = _localExecCommandByName(document, target.command);
    if (command != null) {
      LocalExecOperationConfig? operation;
      for (final candidate in command.operations) {
        if (candidate.name.trim() == target.operation.trim()) {
          operation = candidate;
          break;
        }
      }
      final args = operation?.args ?? command.args;
      final tokens = <String>[
        command.executable.trim().isEmpty
            ? command.name.trim()
            : command.executable.trim(),
        ...args,
      ];
      return tokens.map(_displayCommandToken).join(' ');
    }
  }
  return _toolTargetEvidence(result.target);
}

/// Returns the best user-facing description for a validation scenario.
String _toolValidationScenarioDescription(ToolValidationConfig validation) {
  final target = validation.target;
  final callable = _validationTargetLabel(target);
  return switch (target.type) {
    'agent-tool-call' => 'Agent selects $callable.',
    'workflow-node' => 'Workflow invokes $callable.',
    'mcp-tool' => 'MCP call for $callable.',
    'command-operation' => 'Command operation for $callable.',
    _ => callable,
  };
}

/// Reports whether the active target can receive another validation case.
bool _canAddToolValidation(
  ToolConfigDocument document,
  _ToolSettingsSurface surface,
  String tabId,
) {
  return switch (surface) {
    _ToolSettingsSurface.osTools =>
      _firstCommandValidationTarget(document, tabId) != null,
    _ToolSettingsSurface.mcpServer =>
      _firstMcpValidationTarget(document, tabId) != null,
  };
}

/// Returns command names referenced by the visible validation set.
Set<String> _toolValidationCommandNames(
  List<ToolValidationConfig> validations,
) {
  return <String>{
    for (final validation in validations)
      if (validation.target.command.trim().isNotEmpty)
        validation.target.command.trim(),
  };
}

/// Reports whether live validation is available for the selected target.
bool _toolLiveValidationAvailable(
  ToolConfigDocument document,
  _ToolSettingsSurface surface,
  List<ToolValidationConfig> validations,
) {
  if (surface != _ToolSettingsSurface.osTools) {
    return true;
  }
  final commandNames = _toolValidationCommandNames(validations);
  if (commandNames.isEmpty) {
    return false;
  }
  for (final commandName in commandNames) {
    final command = _localExecCommandByName(document, commandName);
    if (command == null || !command.installation.verified) {
      return false;
    }
  }
  return true;
}

/// Finds one configured local command by name.
LocalExecCommandConfig? _localExecCommandByName(
  ToolConfigDocument document,
  String name,
) {
  for (final command in document.localExec.commands) {
    if (command.name.trim() == name.trim()) {
      return command;
    }
  }
  return null;
}

/// Records whether one local executable is installed for live validation.
Future<LocalExecInstallationConfig> _verifyLocalExecCommandInstall(
  LocalExecCommandConfig command,
) async {
  final executable = command.executable.trim();
  final checkedAt = DateTime.now().toUtc().toIso8601String();
  if (executable.isEmpty) {
    return LocalExecInstallationConfig(
      verified: false,
      checkedAt: checkedAt,
      executable: executable,
      path: '',
      version: '',
      error: 'Command is empty',
    );
  }
  try {
    final which = await Process.run('/usr/bin/env', <String>[
      'sh',
      '-c',
      'command -v "\$1"',
      'aa-tool-check',
      executable,
    ]).timeout(const Duration(seconds: 3));
    final path = '${which.stdout}'.trim().split('\n').first.trim();
    if (which.exitCode != 0 || path.isEmpty) {
      return LocalExecInstallationConfig(
        verified: false,
        checkedAt: checkedAt,
        executable: executable,
        path: '',
        version: '',
        error: '${which.stderr}'.trim().isEmpty
            ? '$executable was not found'
            : '${which.stderr}'.trim(),
      );
    }
    final version = await _localExecVersionLine(path);
    return LocalExecInstallationConfig(
      verified: true,
      checkedAt: checkedAt,
      executable: executable,
      path: path,
      version: version,
      error: '',
    );
  } catch (error) {
    return LocalExecInstallationConfig(
      verified: false,
      checkedAt: checkedAt,
      executable: executable,
      path: '',
      version: '',
      error: error.toString(),
    );
  }
}

/// Returns the first version line for a verified executable.
Future<String> _localExecVersionLine(String executablePath) async {
  try {
    final result = await Process.run(executablePath, const <String>[
      '--version',
    ]).timeout(const Duration(seconds: 2));
    final output = '${result.stdout}\n${result.stderr}'.trim();
    if (output.isEmpty) {
      return '';
    }
    return output.split('\n').first.trim();
  } catch (_) {
    return '';
  }
}

/// Returns a user-facing command preview for validation evidence.
String _toolValidationTargetPreview(
  ToolValidationConfig validation,
  ToolConfigDocument document,
) {
  final target = validation.target;
  if (target.command.isNotEmpty && target.operation.isNotEmpty) {
    final command = _localExecCommandByName(document, target.command);
    if (command != null) {
      LocalExecOperationConfig? operation;
      for (final candidate in command.operations) {
        if (candidate.name.trim() == target.operation.trim()) {
          operation = candidate;
          break;
        }
      }
      final args = operation?.args ?? command.args;
      final tokens = <String>[
        command.executable.trim().isEmpty
            ? command.name.trim()
            : command.executable.trim(),
        for (final arg in args)
          _renderToolValidationToken(arg, validation.input),
      ];
      return tokens.map(_displayCommandToken).join(' ');
    }
  }
  return _toolTargetEvidenceFromConfig(validation.target);
}

/// Renders simple double-brace argument templates from validation input.
String _renderToolValidationToken(String token, Map<String, dynamic> input) {
  return token.replaceAllMapped(RegExp(r'\{\{\s*([\w.-]+)\s*\}\}'), (match) {
    final key = match.group(1) ?? '';
    final value = input[key];
    if (value == null) {
      return match.group(0) ?? token;
    }
    if (value is Map || value is List) {
      return jsonEncode(value);
    }
    return value.toString();
  });
}

/// Quotes display tokens only when needed for readability.
String _displayCommandToken(String token) {
  if (token.trim().isEmpty) {
    return "''";
  }
  if (!RegExp(r'\s').hasMatch(token)) {
    return token;
  }
  return "'${token.replaceAll("'", "'\"'\"'")}'";
}

/// Returns the build-cache path for one tool validation result file.
String _toolValidationResultCachePath(
  AgentAwesomeAppController controller,
  String toolPath,
) {
  final encoded = base64Url.encode(utf8.encode(toolPath)).replaceAll('=', '');
  return '${controller.config.workspaceRoot}/build/tool-validations/$encoded.json';
}

/// Returns the latest scenario status displayed in the status column.
String _toolValidationScenarioStatus(
  List<ToolValidationConfig> validations,
  _ToolValidationResultIndex resultIndex,
) {
  if (validations.isEmpty) {
    return '';
  }
  final mocked = _toolValidationModeState('mocked', validations, resultIndex);
  final live = _toolValidationModeState('live', validations, resultIndex);
  return _toolValidationStatusFromModeStates(
    <String, SettingsValidationModeState>{'mocked': mocked, 'live': live},
  );
}

/// Returns the aggregate status for mocked/live lane states.
String _toolValidationStatusFromModeStates(
  Map<String, SettingsValidationModeState> modeStates,
) {
  final mocked = modeStates['mocked'];
  final live = modeStates['live'];
  if (mocked == null && live == null) {
    return '';
  }
  final mockedStatus = mocked?.status ?? '';
  final liveStatus = live?.status ?? '';
  final mockedSuccess = _validationStatusIsSuccess(mockedStatus);
  final liveSuccess = _validationStatusIsSuccess(liveStatus);
  if (mockedSuccess && liveSuccess) {
    return 'success';
  }
  if (mockedSuccess || liveSuccess) {
    return 'partial_success';
  }
  final statuses = <String>[
    mockedStatus,
    liveStatus,
  ].where((status) => status.trim().isNotEmpty).toList();
  if (statuses.any(_validationStatusIsFailure)) {
    return 'failed';
  }
  return '';
}

/// Returns a user-facing status from validation or command evidence.
String _toolValidationRunStatus(ToolValidationRunResult result) {
  final commandStatus = result.command?.status.trim() ?? '';
  if (commandStatus.isNotEmpty) {
    return commandStatus;
  }
  return result.status.trim();
}

class _SettingsToolValidationCard extends StatelessWidget {
  const _SettingsToolValidationCard({
    required this.title,
    required this.document,
    required this.surface,
    required this.validations,
    required this.validationTabId,
    required this.result,
    required this.error,
    required this.selectedRunMode,
    required this.runningMode,
    required this.runningIds,
    required this.runningAll,
    required this.installVerifying,
    required this.onRunAll,
    required this.onVerifyInstall,
    required this.onAddValidation,
    required this.onRunValidation,
    required this.onDeleteValidation,
  });

  final String title;
  final ToolConfigDocument document;
  final _ToolSettingsSurface surface;
  final List<ToolValidationConfig> validations;
  final String validationTabId;
  final ToolValidationSuiteResult? result;
  final String error;
  final String selectedRunMode;
  final String runningMode;
  final Set<String> runningIds;
  final bool runningAll;
  final bool installVerifying;
  final ValueChanged<SettingsValidationRunRequest> onRunAll;
  final VoidCallback? onVerifyInstall;
  final VoidCallback? onAddValidation;
  final ValueChanged<SettingsValidationRunRequest> onRunValidation;
  final ValueChanged<SettingsValidationScenario> onDeleteValidation;

  /// Builds installed validation metadata for the selected tool config.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final resultIndex = _ToolValidationResultIndex(
      result?.results ?? const <ToolValidationRunResult>[],
    );
    final scenarios = _toolValidationScenarios(
      document,
      validations,
      resultIndex,
      validationTabId,
    );
    final liveAvailable = _toolLiveValidationAvailable(
      document,
      surface,
      validations,
    );
    return FormPlainSection(
      title: title,
      children: <Widget>[
        if (result != null) ...<Widget>[
          _SettingsToolValidationSummary(result: result!),
          _SettingsToolValidationCoverageDetails(result: result!),
          const SizedBox(height: SettingsFormMetrics.sectionGap),
        ],
        if (error.trim().isNotEmpty) ...<Widget>[
          _SettingsToolValidationError(message: error),
          const SizedBox(height: SettingsFormMetrics.sectionGap),
        ],
        SettingsValidationScenarioTable(
          scenarios: scenarios,
          selectedRunMode: selectedRunMode,
          runningMode: runningMode,
          runningValidationIds: runningIds,
          runningAll: runningAll,
          liveAvailable: liveAvailable,
          onRunAll: onRunAll,
          onRunScenario: onRunValidation,
          onDeleteScenario: onDeleteValidation,
          onAddValidation: onAddValidation,
          extraActions: <Widget>[
            if (surface == _ToolSettingsSurface.osTools)
              OutlinedButton.icon(
                style: liveAvailable
                    ? OutlinedButton.styleFrom(
                        backgroundColor: colors.greenSoft,
                        foregroundColor: colors.green,
                        side: BorderSide(
                          color: colors.green.withValues(alpha: 0.5),
                        ),
                      )
                    : null,
                onPressed: installVerifying ? null : onVerifyInstall,
                icon: installVerifying
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        liveAvailable
                            ? Icons.check_circle_outline
                            : Icons.verified_outlined,
                      ),
                label: Text(
                  liveAvailable ? 'Verified Install' : 'Verify Install',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SettingsToolValidationSummary extends StatelessWidget {
  const _SettingsToolValidationSummary({required this.result});

  final ToolValidationSuiteResult result;

  /// Builds the latest validation run summary.
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        PanelBadge(label: 'Total ${result.total}'),
        PanelBadge(label: 'Passed ${result.passed}'),
        PanelBadge(label: 'Failed ${result.failed}'),
        PanelBadge(label: 'Unsupported ${result.unsupported}'),
        PanelBadge(
          label:
              'Coverage ${result.coverage.covered}/${result.coverage.required}',
        ),
        PanelBadge(
          label:
              'Input schemas ${result.inputSchemaCoverage.covered}/${result.inputSchemaCoverage.required}',
        ),
        if (result.coverage.missing.isNotEmpty)
          PanelBadge(label: 'Missing ${result.coverage.missing.length}'),
        if (result.inputSchemaCoverage.missing.isNotEmpty)
          PanelBadge(
            label:
                'Missing schemas ${result.inputSchemaCoverage.missing.length}',
          ),
      ],
    );
  }
}

class _SettingsToolValidationError extends StatelessWidget {
  const _SettingsToolValidationError({required this.message});

  final String message;

  /// Builds a compact validation runner error.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Text(
      message,
      style: TextStyle(color: colors.coral, fontWeight: FontWeight.w700),
    );
  }
}

class _SettingsToolValidationCoverageDetails extends StatelessWidget {
  const _SettingsToolValidationCoverageDetails({required this.result});

  final ToolValidationSuiteResult result;

  /// Builds missing target and schema evidence for strict tool validation runs.
  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    if (result.coverage.missing.isNotEmpty) {
      lines.add(
        _SettingsToolEvidenceLine(
          label: 'Missing coverage',
          value: result.coverage.missing.map(_toolCoverageEvidence).join('\n'),
        ),
      );
    }
    if (result.inputSchemaCoverage.missing.isNotEmpty) {
      lines.add(
        _SettingsToolEvidenceLine(
          label: 'Missing input schemas',
          value: result.inputSchemaCoverage.missing
              .map(_toolCoverageEvidence)
              .join('\n'),
        ),
      );
    }
    if (result.missingAssertions.isNotEmpty) {
      lines.add(
        _SettingsToolEvidenceLine(
          label: 'Missing assertions',
          value: result.missingAssertions.join('\n'),
        ),
      );
    }
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: SettingsFormMetrics.compactGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < lines.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: 6),
            lines[index],
          ],
        ],
      ),
    );
  }
}

class SettingsToolValidationEvidenceView extends StatelessWidget {
  /// Creates a compact tool validation evidence view.
  const SettingsToolValidationEvidenceView({
    super.key,
    required this.result,
    this.targetLabel = '',
  });

  /// Result whose captured boundary evidence should be displayed.
  final ToolValidationRunResult result;

  /// User-facing command or tool preview for the selected target.
  final String targetLabel;

  /// Builds run evidence for command, agent-call, and workflow-node checks.
  @override
  Widget build(BuildContext context) {
    final command = result.command;
    final leftLines = <Widget>[
      _SettingsToolEvidenceLine(
        label: 'Target',
        value: targetLabel.trim().isEmpty
            ? _toolTargetEvidence(result.target)
            : targetLabel.trim(),
      ),
    ];
    if (command != null) {
      leftLines.add(
        _SettingsToolEvidenceLine(
          label: 'Command',
          value: _toolCommandEvidence(command),
        ),
      );
      if (command.stdoutTail.trim().isNotEmpty) {
        leftLines.add(
          _SettingsToolEvidenceLine(label: 'Stdout', value: command.stdoutTail),
        );
      }
      if (command.stderrTail.trim().isNotEmpty) {
        leftLines.add(
          _SettingsToolEvidenceLine(label: 'Stderr', value: command.stderrTail),
        );
      }
      if (command.artifacts.isNotEmpty) {
        leftLines.add(
          _SettingsToolEvidenceLine(
            label: 'Artifacts',
            value: command.artifacts.map(_toolArtifactEvidence).join('\n'),
          ),
        );
      }
    }
    if (result.assertions.isNotEmpty) {
      leftLines.add(
        _SettingsToolEvidenceLine(
          label: 'Assertions',
          value: result.assertions.map(_toolAssertionEvidence).join('\n'),
        ),
      );
    }
    if (result.diagnostics.isNotEmpty) {
      leftLines.add(
        _SettingsToolEvidenceLine(
          label: 'Diagnostics',
          value: result.diagnostics.map(_toolDiagnosticEvidence).join('\n'),
        ),
      );
    }
    final output = command?.output;
    final outputLine = output == null
        ? null
        : _SettingsToolEvidenceLine(
            label: 'Output',
            value: _toolJsonEvidence(output),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final left = _SettingsToolEvidenceColumn(lines: leftLines);
        if (constraints.maxWidth < 760 || outputLine == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              left,
              if (outputLine != null) ...<Widget>[
                const SizedBox(height: SettingsFormMetrics.compactGap),
                outputLine,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: left),
            const SizedBox(width: SettingsFormMetrics.sectionGap),
            Expanded(child: outputLine),
          ],
        );
      },
    );
  }
}

class _SettingsToolEvidenceColumn extends StatelessWidget {
  const _SettingsToolEvidenceColumn({required this.lines});

  final List<Widget> lines;

  /// Builds stacked validation evidence rows.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < lines.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: 6),
          lines[index],
        ],
      ],
    );
  }
}

class _SettingsToolEvidenceLine extends StatelessWidget {
  const _SettingsToolEvidenceLine({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds one selectable tool validation evidence row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: colors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(value, style: TextStyle(color: colors.ink)),
      ],
    );
  }
}

/// Returns a compact display label for one validation target.
String _validationTargetLabel(ToolValidationTargetConfig target) {
  if (target.command.isNotEmpty && target.operation.isNotEmpty) {
    return '${target.command}.${target.operation}';
  }
  if (target.mcpServer.isNotEmpty && target.mcpTool.isNotEmpty) {
    return '${target.mcpServer}.${target.mcpTool}';
  }
  if (target.presetId.isNotEmpty) {
    return target.presetId;
  }
  return target.type;
}

/// Creates starter validations for the next uncovered target on a tool surface.
List<ToolValidationConfig> _defaultToolValidationSet(
  ToolConfigDocument document,
  _ToolSettingsSurface surface, {
  String tabId = '',
}) {
  final existingIds = <String>{
    for (final validation in document.validations) validation.id,
  };
  final covered = _toolValidationCoverageKeys(document.validations);
  final starter = switch (surface) {
    _ToolSettingsSurface.osTools => _defaultCommandValidationSet(
      document,
      existingIds,
      covered,
      tabId,
    ),
    _ToolSettingsSurface.mcpServer => _defaultMcpValidationSet(
      document,
      existingIds,
      covered,
      tabId,
    ),
  };
  if (starter.isNotEmpty) {
    return starter;
  }
  return switch (surface) {
    _ToolSettingsSurface.osTools => _additionalCommandValidationSet(
      document,
      existingIds,
      tabId,
    ),
    _ToolSettingsSurface.mcpServer => _additionalMcpValidationSet(
      document,
      existingIds,
      tabId,
    ),
  };
}

/// Creates one additional direct command validation for the active operation.
List<ToolValidationConfig> _additionalCommandValidationSet(
  ToolConfigDocument document,
  Set<String> existingIds,
  String tabId,
) {
  final target = _firstCommandValidationTarget(document, tabId);
  if (target == null) {
    return const <ToolValidationConfig>[];
  }
  final id = '${target.command}.${target.operation}';
  return <ToolValidationConfig>[
    _mockedToolValidation(
      id: _uniqueToolValidationId(
        existingIds,
        '${target.command}_${target.operation}_validation',
      ),
      label: 'Command $id',
      description: 'Command operation for $id.',
      target: target,
      boundary: 'command.execute',
    ),
  ];
}

/// Creates one additional direct MCP validation for the active tool.
List<ToolValidationConfig> _additionalMcpValidationSet(
  ToolConfigDocument document,
  Set<String> existingIds,
  String tabId,
) {
  final target = _firstMcpValidationTarget(document, tabId);
  if (target == null) {
    return const <ToolValidationConfig>[];
  }
  final id = '${target.mcpServer}.${target.mcpTool}';
  return <ToolValidationConfig>[
    _mockedToolValidation(
      id: _uniqueToolValidationId(
        existingIds,
        '${target.mcpServer}_${target.mcpTool}_validation',
      ),
      label: 'MCP $id',
      description: 'MCP call for $id.',
      target: target,
      boundary: 'mcp.call',
    ),
  ];
}

/// Returns the first command validation target for the selected tab.
ToolValidationTargetConfig? _firstCommandValidationTarget(
  ToolConfigDocument document,
  String tabId,
) {
  for (final command in document.localExec.commands) {
    final commandName = command.name.trim();
    if (commandName.isEmpty) {
      continue;
    }
    for (final operation in command.operations) {
      final operationName = operation.name.trim();
      if (operationName.isEmpty) {
        continue;
      }
      if (tabId.isNotEmpty &&
          _commandValidationTabId(commandName, operationName) != tabId) {
        continue;
      }
      return ToolValidationTargetConfig(
        type: 'command-operation',
        presetId: '',
        command: commandName,
        operation: operationName,
        mcpServer: '',
        mcpTool: '',
      );
    }
  }
  return null;
}

/// Returns the first MCP validation target for the selected tab.
ToolValidationTargetConfig? _firstMcpValidationTarget(
  ToolConfigDocument document,
  String tabId,
) {
  for (final server in document.mcp.servers) {
    final serverName = server.name.trim();
    if (serverName.isEmpty) {
      continue;
    }
    for (final tool in server.tools.allow) {
      final toolName = tool.trim();
      if (toolName.isEmpty) {
        continue;
      }
      if (tabId.isNotEmpty &&
          _mcpValidationTabId(serverName, toolName) != tabId) {
        continue;
      }
      return ToolValidationTargetConfig(
        type: 'mcp-tool',
        presetId: '',
        command: '',
        operation: '',
        mcpServer: serverName,
        mcpTool: toolName,
      );
    }
  }
  return null;
}

/// Creates direct, agent-call, and workflow validations for one command op.
List<ToolValidationConfig> _defaultCommandValidationSet(
  ToolConfigDocument document,
  Set<String> existingIds,
  Set<String> covered,
  String tabId,
) {
  for (final command in document.localExec.commands) {
    final commandName = command.name.trim();
    if (commandName.isEmpty) {
      continue;
    }
    for (final operation in command.operations) {
      final operationName = operation.name.trim();
      if (operationName.isEmpty) {
        continue;
      }
      if (tabId.isNotEmpty &&
          _commandValidationTabId(commandName, operationName) != tabId) {
        continue;
      }
      final id = '$commandName.$operationName';
      final additions = <ToolValidationConfig>[];
      if (!covered.contains(_toolCoverageKey('command-operation', id))) {
        additions.add(
          _mockedToolValidation(
            id: _uniqueToolValidationId(
              existingIds,
              '${commandName}_${operationName}_command',
            ),
            label: 'Command $id',
            description: 'Validates the command boundary for $id.',
            target: ToolValidationTargetConfig(
              type: 'command-operation',
              presetId: '',
              command: commandName,
              operation: operationName,
              mcpServer: '',
              mcpTool: '',
            ),
            boundary: 'command.execute',
          ),
        );
      }
      if (!covered.contains(
        _toolCoverageKey('agent-tool-call', 'command:$id'),
      )) {
        additions.add(
          _mockedToolValidation(
            id: _uniqueToolValidationId(
              existingIds,
              '${commandName}_${operationName}_agent',
            ),
            label: 'Agent can call $id',
            description: 'Validates the direct agent-call contract for $id.',
            target: ToolValidationTargetConfig(
              type: 'agent-tool-call',
              presetId: '',
              command: commandName,
              operation: operationName,
              mcpServer: '',
              mcpTool: '',
            ),
            boundary: 'agent.tool_call',
            prompt: 'Use $id for this request.',
          ),
        );
      }
      if (!covered.contains(_toolCoverageKey('workflow-node', 'command:$id'))) {
        additions.add(
          _mockedToolValidation(
            id: _uniqueToolValidationId(
              existingIds,
              '${commandName}_${operationName}_workflow',
            ),
            label: 'Workflow can call $id',
            description: 'Validates the workflow-node contract for $id.',
            target: ToolValidationTargetConfig(
              type: 'workflow-node',
              presetId: '',
              command: commandName,
              operation: operationName,
              mcpServer: '',
              mcpTool: '',
            ),
            boundary: 'command.execute',
          ),
        );
      }
      if (additions.isNotEmpty) {
        return additions;
      }
    }
  }
  return const <ToolValidationConfig>[];
}

/// Creates direct, agent-call, and workflow validations for one MCP tool.
List<ToolValidationConfig> _defaultMcpValidationSet(
  ToolConfigDocument document,
  Set<String> existingIds,
  Set<String> covered,
  String tabId,
) {
  for (final server in document.mcp.servers) {
    final serverName = server.name.trim();
    if (serverName.isEmpty) {
      continue;
    }
    for (final tool in server.tools.allow) {
      final toolName = tool.trim();
      if (toolName.isEmpty) {
        continue;
      }
      if (tabId.isNotEmpty &&
          _mcpValidationTabId(serverName, toolName) != tabId) {
        continue;
      }
      final id = '$serverName.$toolName';
      final additions = <ToolValidationConfig>[];
      if (!covered.contains(_toolCoverageKey('mcp-tool', id))) {
        additions.add(
          _mockedToolValidation(
            id: _uniqueToolValidationId(
              existingIds,
              '${serverName}_${toolName}_mcp',
            ),
            label: 'MCP $id',
            description: 'Validates the MCP boundary for $id.',
            target: ToolValidationTargetConfig(
              type: 'mcp-tool',
              presetId: '',
              command: '',
              operation: '',
              mcpServer: serverName,
              mcpTool: toolName,
            ),
            boundary: 'mcp.call',
          ),
        );
      }
      if (!covered.contains(_toolCoverageKey('agent-tool-call', 'mcp:$id'))) {
        additions.add(
          _mockedToolValidation(
            id: _uniqueToolValidationId(
              existingIds,
              '${serverName}_${toolName}_agent',
            ),
            label: 'Agent can call $id',
            description: 'Validates the direct agent-call contract for $id.',
            target: ToolValidationTargetConfig(
              type: 'agent-tool-call',
              presetId: '',
              command: '',
              operation: '',
              mcpServer: serverName,
              mcpTool: toolName,
            ),
            boundary: 'agent.tool_call',
            prompt: 'Use $id for this request.',
          ),
        );
      }
      if (!covered.contains(_toolCoverageKey('workflow-node', 'mcp:$id'))) {
        additions.add(
          _mockedToolValidation(
            id: _uniqueToolValidationId(
              existingIds,
              '${serverName}_${toolName}_workflow',
            ),
            label: 'Workflow can call $id',
            description: 'Validates the workflow-node contract for $id.',
            target: ToolValidationTargetConfig(
              type: 'workflow-node',
              presetId: '',
              command: '',
              operation: '',
              mcpServer: serverName,
              mcpTool: toolName,
            ),
            boundary: 'mcp.call',
          ),
        );
      }
      if (additions.isNotEmpty) {
        return additions;
      }
    }
  }
  return const <ToolValidationConfig>[];
}

/// Creates one mocked validation with a concrete passing status assertion.
ToolValidationConfig _mockedToolValidation({
  required String id,
  required String label,
  required String description,
  required ToolValidationTargetConfig target,
  required String boundary,
  String prompt = '',
}) {
  return ToolValidationConfig(
    id: id,
    label: label,
    description: description,
    mode: 'mocked',
    target: target,
    prompt: prompt,
    input: const <String, dynamic>{},
    fixtures: const <String, dynamic>{},
    mocks: <String, dynamic>{
      boundary: _mockedToolValidationResponse(target, label),
    },
    expected: const <String, dynamic>{},
    assertions: _mockedToolValidationAssertions(target),
  );
}

/// Creates a mocked boundary response that proves the selected target shape.
Map<String, dynamic> _mockedToolValidationResponse(
  ToolValidationTargetConfig target,
  String label,
) {
  final response = <String, dynamic>{
    'status': 'succeeded',
    'exit_code': 0,
    'stdout': label,
  };
  if (target.type == 'agent-tool-call' &&
      target.command.isNotEmpty &&
      target.operation.isNotEmpty) {
    response['output'] = <String, dynamic>{
      'tool_name': 'command_execute',
      'arguments': <String, dynamic>{
        'template_id': '${target.command}.${target.operation}',
      },
    };
  }
  if (target.type == 'agent-tool-call' &&
      target.mcpServer.isNotEmpty &&
      target.mcpTool.isNotEmpty) {
    response['output'] = <String, dynamic>{
      'tool_name': '${target.mcpServer}.${target.mcpTool}',
      'arguments': <String, dynamic>{
        'server_id': target.mcpServer,
        'tool': target.mcpTool,
      },
    };
  }
  return response;
}

/// Creates concrete assertions for one generated starter validation.
List<ToolValidationAssertionConfig> _mockedToolValidationAssertions(
  ToolValidationTargetConfig target,
) {
  final assertions = <ToolValidationAssertionConfig>[
    const ToolValidationAssertionConfig(
      type: 'status',
      path: '',
      equals: 'succeeded',
      contains: '',
      matches: '',
      schema: <String, dynamic>{},
      message: '',
    ),
  ];
  if (target.type == 'agent-tool-call' &&
      target.command.isNotEmpty &&
      target.operation.isNotEmpty) {
    assertions.add(
      ToolValidationAssertionConfig(
        type: 'json-path',
        path: 'output.arguments.template_id',
        equals: '${target.command}.${target.operation}',
        contains: '',
        matches: '',
        schema: const <String, dynamic>{},
        message: '',
      ),
    );
  }
  if (target.type == 'agent-tool-call' &&
      target.mcpServer.isNotEmpty &&
      target.mcpTool.isNotEmpty) {
    assertions.add(
      ToolValidationAssertionConfig(
        type: 'json-path',
        path: 'output.arguments.tool',
        equals: target.mcpTool,
        contains: '',
        matches: '',
        schema: const <String, dynamic>{},
        message: '',
      ),
    );
  }
  return assertions;
}

/// Returns coverage keys proved by validations with concrete expectations.
Set<String> _toolValidationCoverageKeys(
  List<ToolValidationConfig> validations,
) {
  final covered = <String>{};
  for (final validation in validations) {
    if (!_toolValidationHasConfiguredExpectation(validation)) {
      continue;
    }
    final target = validation.target;
    switch (target.type.trim()) {
      case 'command-operation':
        if (target.command.isNotEmpty && target.operation.isNotEmpty) {
          covered.add(
            _toolCoverageKey(
              'command-operation',
              '${target.command}.${target.operation}',
            ),
          );
        }
        break;
      case 'agent-tool-call':
        if (target.command.isNotEmpty && target.operation.isNotEmpty) {
          covered.add(
            _toolCoverageKey(
              'agent-tool-call',
              'command:${target.command}.${target.operation}',
            ),
          );
        } else if (target.mcpServer.isNotEmpty && target.mcpTool.isNotEmpty) {
          covered.add(
            _toolCoverageKey(
              'agent-tool-call',
              'mcp:${target.mcpServer}.${target.mcpTool}',
            ),
          );
        }
        break;
      case 'workflow-node':
        if (target.command.isNotEmpty && target.operation.isNotEmpty) {
          covered.add(
            _toolCoverageKey(
              'workflow-node',
              'command:${target.command}.${target.operation}',
            ),
          );
        } else if (target.mcpServer.isNotEmpty && target.mcpTool.isNotEmpty) {
          covered.add(
            _toolCoverageKey(
              'workflow-node',
              'mcp:${target.mcpServer}.${target.mcpTool}',
            ),
          );
        } else if (target.presetId.isNotEmpty) {
          covered.add(_toolCoverageKey('workflow-node', target.presetId));
        }
        break;
      case 'mcp-tool':
        if (target.mcpServer.isNotEmpty && target.mcpTool.isNotEmpty) {
          covered.add(
            _toolCoverageKey(
              'mcp-tool',
              '${target.mcpServer}.${target.mcpTool}',
            ),
          );
        }
        break;
    }
  }
  return covered;
}

/// Returns whether one validation contains a concrete expected behavior.
bool _toolValidationHasConfiguredExpectation(ToolValidationConfig validation) {
  for (final entry in validation.expected.entries) {
    switch (entry.key.trim()) {
      case 'status':
        if ('${entry.value}'.trim().isNotEmpty) {
          return true;
        }
        break;
      case 'exit_code':
        if (entry.value != null) {
          return true;
        }
        break;
    }
  }
  for (final assertion in validation.assertions) {
    switch (assertion.type.trim()) {
      case 'status':
        if (assertion.equals != null &&
            '${assertion.equals}'.trim().isNotEmpty) {
          return true;
        }
        break;
      case 'exit-code':
        if (assertion.equals != null) {
          return true;
        }
        break;
      case 'stdout-contains':
      case 'stderr-contains':
        if (assertion.contains.trim().isNotEmpty) {
          return true;
        }
        break;
      case 'json-path':
        if (assertion.path.trim().isNotEmpty &&
            (assertion.contains.trim().isNotEmpty ||
                assertion.matches.trim().isNotEmpty ||
                assertion.equals != null)) {
          return true;
        }
        break;
      case 'schema':
        if (assertion.schema.isNotEmpty) {
          return true;
        }
        break;
    }
  }
  return false;
}

/// Returns a stable coverage lookup key.
String _toolCoverageKey(String type, String id) {
  return '${type.trim()}:${id.trim()}';
}

/// Returns a unique validation id derived from a user-facing target label.
String _uniqueToolValidationId(Set<String> existing, String base) {
  final safeBase = _safeToolValidationId(base);
  var candidate = safeBase;
  var index = 2;
  while (existing.contains(candidate)) {
    candidate = '${safeBase}_$index';
    index++;
  }
  existing.add(candidate);
  return candidate;
}

/// Converts a target label into a schema-compatible validation id.
String _safeToolValidationId(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final allowed = RegExp(r'[A-Za-z0-9_-]').hasMatch(char) && char.length == 1;
    buffer.write(allowed ? char : '_');
  }
  var id = buffer.toString().replaceAll(RegExp(r'_+'), '_').trim();
  if (id.isEmpty) {
    id = 'validation';
  }
  if (!RegExp(r'^[A-Za-z_]').hasMatch(id)) {
    id = 'validation_$id';
  }
  return id;
}

/// Formats one missing coverage item for validation evidence review.
String _toolCoverageEvidence(ToolValidationCoverageItem item) {
  final label = item.label.isEmpty ? item.id : item.label;
  return '${item.type} ${item.id} $label'.trim();
}

/// Formats one configured validation target for fallback evidence.
String _toolTargetEvidenceFromConfig(ToolValidationTargetConfig target) {
  final callable = _validationTargetLabel(target);
  return switch (target.type) {
    'agent-tool-call' => 'Agent selection: $callable',
    'workflow-node' => 'Workflow node: $callable',
    'mcp-tool' => 'MCP tool: $callable',
    'command-operation' => 'Command operation: $callable',
    _ => callable,
  };
}

/// Formats the validation target boundary and selected callable surface.
String _toolTargetEvidence(ToolValidationTargetResult target) {
  final callable = _toolTargetCallableLabel(target);
  return switch (target.type) {
    'agent-tool-call' => 'Agent selection: $callable',
    'workflow-node' => 'Workflow node: $callable',
    'mcp-tool' => 'MCP tool: $callable',
    'command-operation' => 'Command operation: $callable',
    _ => callable,
  };
}

/// Returns the user-facing callable label for one target result.
String _toolTargetCallableLabel(ToolValidationTargetResult target) {
  if (target.command.isNotEmpty && target.operation.isNotEmpty) {
    return '${target.command}.${target.operation}';
  }
  if (target.mcpServer.isNotEmpty && target.mcpTool.isNotEmpty) {
    return '${target.mcpServer}.${target.mcpTool}';
  }
  if (target.templateId.isNotEmpty) {
    return target.templateId;
  }
  if (target.presetId.isNotEmpty) {
    return target.presetId;
  }
  return target.type;
}

/// Formats one command result for validation evidence review.
String _toolCommandEvidence(ToolValidationCommandResult command) {
  final details = <String>[
    if (command.status.isNotEmpty) 'status ${command.status}',
    'exit ${command.exitCode}',
    if (command.timedOut) 'timed out',
    if (command.truncated) 'truncated',
    if (command.error.isNotEmpty) command.error,
  ];
  return details.join(', ');
}

/// Formats one command artifact for validation evidence review.
String _toolArtifactEvidence(ToolValidationCommandArtifact artifact) {
  return '${artifact.path} (${artifact.size} bytes)';
}

/// Formats one assertion result for validation evidence review.
String _toolAssertionEvidence(ToolValidationAssertionResult assertion) {
  final status = assertion.passed ? 'passed' : 'failed';
  final path = assertion.path.isEmpty ? assertion.type : assertion.path;
  final expectation = assertion.expected == null
      ? ''
      : ' expected ${assertion.expected}';
  final actual = assertion.actual == null ? '' : ' actual ${assertion.actual}';
  final message = assertion.message.isEmpty ? '' : ' ${assertion.message}';
  return '$status $path$expectation$actual$message'.trim();
}

/// Formats one diagnostic for validation evidence review.
String _toolDiagnosticEvidence(ToolValidationDiagnostic diagnostic) {
  final severity = diagnostic.severity.isEmpty
      ? 'diagnostic'
      : diagnostic.severity;
  return '$severity ${diagnostic.message}'.trim();
}

/// Encodes structured tool validation evidence in a stable display form.
String _toolJsonEvidence(Object? value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return '$value';
  }
}

/// Merges selected validation reruns into the previous suite result.
ToolValidationSuiteResult _mergedValidationResults(
  ToolValidationSuiteResult? previous,
  ToolValidationSuiteResult next,
) => mergeToolValidationSuiteResults(previous, next);
