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
  bool _mcpServerStarting = false;
  String _validationRunningId = '';
  Set<String> _validationRunningIds = const <String>{};
  String _validationRunMode = 'mocked';
  String _validationRunningMode = '';
  String _mcpServerStartingName = '';
  String _mcpServerStatus = '';
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
      _mcpServerStarting = false;
      _mcpServerStartingName = '';
      _mcpServerStatus = '';
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
        error: _validationError,
        onRenamed: widget.onRenamed,
        onDocumentChanged: _save,
      );
    }
    final localExec = _localExecWithDetailsDefaults(document.localExec);
    if (widget.modeId == _toolSurfaceOperationsMode &&
        widget.surface == _ToolSettingsSurface.osTools) {
      return const FormPanel(children: <Widget>[]);
    }
    return FormPanel(
      children: <Widget>[
        if (_validationError.trim().isNotEmpty)
          FormPlainSection(
            title: 'Save issue',
            children: <Widget>[
              _SettingsToolValidationError(message: _validationError),
            ],
          ),
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
            runtimeServers:
                widget.controller.runtimeProfile?.mcpServers ??
                const <McpServerRuntime>[],
            statusMessage: _mcpServerStatus,
            starting: _mcpServerStarting,
            startingServerName: _mcpServerStartingName,
            onStartServer: _startMcpServer,
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
  Future<bool> _save(ToolConfigDocument document) async {
    final validationError = toolConfigValidationError(document);
    if (validationError.isNotEmpty) {
      if (mounted) {
        setState(() => _validationError = validationError);
      }
      return false;
    }
    try {
      await widget.controller.saveConfigurationFile(
        widget.entry.path,
        document.toYaml(),
      );
      await widget.controller.refreshConfigurationCollections();
      widget.onDocumentChanged(document);
      if (!mounted) {
        return true;
      }
      setState(() {
        _document = document;
        _validationError = '';
      });
      return true;
    } catch (_) {}
    if (mounted) {
      setState(() => _validationError = 'Tool config could not be saved.');
    }
    return false;
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

  /// Opens validation authoring and saves direct plus runbook-envelope cases.
  Future<void> _addValidation(ToolConfigDocument document) async {
    final choices = _toolValidationAuthoringChoices(
      document,
      widget.surface,
      tabId: widget.validationTabId,
    );
    if (choices.isEmpty) {
      return;
    }
    final draft = await showDialog<_ToolValidationDraft>(
      context: context,
      builder: (context) => _ToolValidationDraftDialog(choices: choices),
    );
    if (draft == null) {
      return;
    }
    final existingIds = <String>{
      for (final validation in document.validations) validation.id,
    };
    final validations = _toolValidationsForDraft(existingIds, draft);
    await _save(
      document.copyWith(
        validations: <ToolValidationConfig>[
          ...document.validations,
          ...validations,
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

  /// Starts or checks a server from the loaded MCP package file.
  Future<void> _startMcpServer(McpServerToolConfig server) async {
    if (_mcpServerStarting) {
      return;
    }
    final serverName = server.name.trim();
    setState(() {
      _mcpServerStarting = true;
      _mcpServerStartingName = serverName;
      _mcpServerStatus = '';
      _validationError = '';
    });
    try {
      final status = await widget.controller.startMcpServerFromConfig(
        widget.entry.path,
        serverName: serverName,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _mcpServerStatus =
            '${status.name}: ${status.message}'
            '${status.url.trim().isEmpty ? '' : ' (${status.url})'}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _validationError = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _mcpServerStarting = false;
          _mcpServerStartingName = '';
        });
      }
    }
  }
}

class _SettingsToolConfigDetailsEditor extends StatefulWidget {
  const _SettingsToolConfigDetailsEditor({
    required this.controller,
    required this.entry,
    required this.document,
    required this.surface,
    required this.error,
    required this.onRenamed,
    required this.onDocumentChanged,
  });

  final AgentAwesomeAppController controller;
  final ConfigFileEntry entry;
  final ToolConfigDocument document;
  final _ToolSettingsSurface surface;
  final String error;
  final ValueChanged<String> onRenamed;
  final Future<bool> Function(ToolConfigDocument document) onDocumentChanged;

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
            if (widget.error.trim().isNotEmpty) ...<Widget>[
              _SettingsToolValidationError(message: widget.error),
              const SizedBox(height: SettingsFormMetrics.compactGap),
            ],
            if (widget.surface == _ToolSettingsSurface.osTools)
              SettingsToggleField(
                title: 'Enabled',
                value: widget.document.localExec.enabled,
                onChanged: (enabled) => unawaited(
                  widget.onDocumentChanged(
                    widget.document.copyWith(
                      localExec: widget.document.localExec.copyWith(
                        enabled: enabled,
                      ),
                    ),
                  ),
                ),
              ),
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
    'runbook-node' => 'Runbook envelope for $callable.',
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
    'runbook-node' => 'Runbook envelope for $callable.',
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

/// Reports whether selected local executables have been found on this machine.
bool _toolInstallVerified(
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

/// Reports whether live validation is available for the selected target.
bool _toolLiveValidationAvailable(
  ToolConfigDocument document,
  _ToolSettingsSurface surface,
  List<ToolValidationConfig> validations,
) {
  if (surface != _ToolSettingsSurface.osTools) {
    return true;
  }
  if (!document.localExec.enabled) {
    return false;
  }
  return _toolInstallVerified(document, surface, validations);
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
    final installVerified = _toolInstallVerified(
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
                style: installVerified
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
                        installVerified
                            ? Icons.check_circle_outline
                            : Icons.verified_outlined,
                      ),
                label: Text(
                  installVerified ? 'Verified Install' : 'Verify Install',
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
        _SettingsToolEvidenceSection(
          icon: Icons.rule_outlined,
          label: 'Missing coverage',
          child: _SettingsToolEvidenceValueBox(
            value: result.coverage.missing
                .map(_toolCoverageEvidence)
                .join('\n'),
          ),
        ),
      );
    }
    if (result.inputSchemaCoverage.missing.isNotEmpty) {
      lines.add(
        _SettingsToolEvidenceSection(
          icon: Icons.schema_outlined,
          label: 'Missing input schemas',
          child: _SettingsToolEvidenceValueBox(
            value: result.inputSchemaCoverage.missing
                .map(_toolCoverageEvidence)
                .join('\n'),
          ),
        ),
      );
    }
    if (result.missingAssertions.isNotEmpty) {
      lines.add(
        _SettingsToolEvidenceSection(
          icon: Icons.fact_check_outlined,
          label: 'Missing assertions',
          child: _SettingsToolEvidenceValueBox(
            value: result.missingAssertions.join('\n'),
          ),
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

  /// Builds run evidence for command, agent-call, and runbook-node checks.
  @override
  Widget build(BuildContext context) {
    final command = result.command;
    final leftLines = <Widget>[
      _SettingsToolEvidenceSection(
        icon: Icons.my_location_outlined,
        label: 'Target',
        child: _SettingsToolEvidenceValueBox(
          value: targetLabel.trim().isEmpty
              ? _toolTargetEvidence(result.target)
              : targetLabel.trim(),
          monospace: true,
        ),
      ),
    ];
    if (command != null) {
      leftLines.add(
        _SettingsToolEvidenceSection(
          icon: Icons.terminal_outlined,
          label: 'Command',
          child: _SettingsToolEvidenceValueBox(
            value: _toolCommandEvidence(command),
            monospace: true,
          ),
        ),
      );
      if (command.stdoutTail.trim().isNotEmpty) {
        leftLines.add(
          _SettingsToolEvidenceSection(
            icon: Icons.subject_outlined,
            label: 'Stdout',
            child: _SettingsToolEvidenceValueBox(value: command.stdoutTail),
          ),
        );
      }
      if (command.stderrTail.trim().isNotEmpty) {
        leftLines.add(
          _SettingsToolEvidenceSection(
            icon: Icons.error_outline,
            label: 'Stderr',
            child: _SettingsToolEvidenceValueBox(value: command.stderrTail),
          ),
        );
      }
      if (command.artifacts.isNotEmpty) {
        leftLines.add(
          _SettingsToolEvidenceSection(
            icon: Icons.inventory_2_outlined,
            label: 'Artifacts',
            child: _SettingsToolEvidenceValueBox(
              value: command.artifacts.map(_toolArtifactEvidence).join('\n'),
            ),
          ),
        );
      }
    }
    if (result.assertions.isNotEmpty) {
      leftLines.add(
        _SettingsToolEvidenceSection(
          icon: Icons.verified_outlined,
          label: 'Assertions',
          child: _SettingsToolAssertionList(assertions: result.assertions),
        ),
      );
    }
    if (result.diagnostics.isNotEmpty) {
      leftLines.add(
        _SettingsToolEvidenceSection(
          icon: Icons.report_problem_outlined,
          label: 'Diagnostics',
          child: _SettingsToolEvidenceValueBox(
            value: result.diagnostics.map(_toolDiagnosticEvidence).join('\n'),
          ),
        ),
      );
    }
    final output = command?.output;
    final outputLine = output == null
        ? null
        : _SettingsToolEvidenceSection(
            icon: Icons.data_object_outlined,
            label: 'Output',
            trailing: PanelInlineIconButton(
              icon: Icons.content_copy,
              tooltip: 'Copy output',
              onPressed: () => unawaited(
                Clipboard.setData(
                  ClipboardData(text: _toolJsonEvidence(output)),
                ),
              ),
            ),
            child: _SettingsToolEvidenceValueBox(
              value: _toolJsonEvidence(output),
              monospace: true,
              minHeight: 176,
            ),
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

class _SettingsToolEvidenceSection extends StatelessWidget {
  const _SettingsToolEvidenceSection({
    required this.icon,
    required this.label,
    required this.child,
    this.trailing,
  });

  final IconData icon;

  final String label;

  final Widget child;

  final Widget? trailing;

  /// Builds one labeled tool validation evidence block.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 15, color: colors.muted),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _SettingsToolEvidenceValueBox extends StatelessWidget {
  const _SettingsToolEvidenceValueBox({
    required this.value,
    this.monospace = false,
    this.minHeight = 0,
  });

  final String value;

  final bool monospace;

  final double minHeight;

  /// Builds a quiet boxed evidence value.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.74),
        border: Border.all(
          color: colors.border.withValues(alpha: 0.78),
          width: AgentAwesomeStrokeTokens.borderWidth,
        ),
        borderRadius: BorderRadius.circular(PanelStyleTokens.compactRadius),
      ),
      child: SelectableText(
        value,
        style: TextStyle(
          color: colors.ink,
          fontFamily: monospace ? 'monospace' : null,
          height: 1.35,
        ),
      ),
    );
  }
}

class _SettingsToolAssertionList extends StatelessWidget {
  const _SettingsToolAssertionList({required this.assertions});

  final List<ToolValidationAssertionResult> assertions;

  /// Builds assertion evidence with per-assertion pass/fail icons.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.54),
        border: Border.all(
          color: colors.border.withValues(alpha: 0.68),
          width: AgentAwesomeStrokeTokens.borderWidth,
        ),
        borderRadius: BorderRadius.circular(PanelStyleTokens.compactRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < assertions.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: 6),
            _SettingsToolAssertionRow(assertion: assertions[index]),
          ],
        ],
      ),
    );
  }
}

class _SettingsToolAssertionRow extends StatelessWidget {
  const _SettingsToolAssertionRow({required this.assertion});

  final ToolValidationAssertionResult assertion;

  /// Builds one assertion line with semantic color.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final color = assertion.passed ? colors.green : colors.coral;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          assertion.passed ? Icons.check_circle : Icons.cancel,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: SelectableText(
            _toolAssertionEvidence(assertion),
            style: TextStyle(
              color: colors.ink,
              fontFamily: 'monospace',
              height: 1.35,
            ),
          ),
        ),
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

/// _ToolValidationAuthoringChoice describes one selectable validation target.
class _ToolValidationAuthoringChoice {
  /// Creates a validation target option for the Add validation dialog.
  const _ToolValidationAuthoringChoice({
    required this.menuLabel,
    required this.idBase,
    required this.defaultLabel,
    required this.target,
    required this.boundary,
    required this.input,
    this.runbookTarget,
    this.runbookBoundary = '',
    this.runbookIdBase = '',
  });

  /// Short user-facing label shown in the target selector.
  final String menuLabel;

  /// Base id used when creating the validation record.
  final String idBase;

  /// Suggested validation label.
  final String defaultLabel;

  /// Invocation target tested by this validation.
  final ToolValidationTargetConfig target;

  /// Runtime boundary used by this validation.
  final String boundary;

  /// Suggested input map for the selected target.
  final Map<String, dynamic> input;

  /// Optional runbook envelope companion target created from the same fields.
  final ToolValidationTargetConfig? runbookTarget;

  /// Runtime boundary used by the companion runbook envelope validation.
  final String runbookBoundary;

  /// Base id used for the companion runbook envelope validation.
  final String runbookIdBase;
}

/// _ToolValidationExpectedDraft stores user-authored result expectations.
class _ToolValidationExpectedDraft {
  /// Creates expected status and output checks for a validation case.
  const _ToolValidationExpectedDraft({
    required this.status,
    required this.exitCodeCheck,
    required this.outputChecks,
    required this.errorChecks,
  });

  /// Expected boundary status.
  final String status;

  /// Expected process exit-code condition when relevant.
  final _ToolValidationNumberCheckDraft? exitCodeCheck;

  /// Checks expected against stdout.
  final List<_ToolValidationTextCheckDraft> outputChecks;

  /// Checks expected against stderr.
  final List<_ToolValidationTextCheckDraft> errorChecks;
}

/// _ToolValidationNumberCheckDraft stores one numeric result check.
class _ToolValidationNumberCheckDraft {
  /// Creates a numeric check from a condition and operand.
  const _ToolValidationNumberCheckDraft({
    required this.condition,
    required this.value,
  });

  /// Condition id such as equals, not-equals, greater-than, or less-than.
  final String condition;

  /// User-entered numeric operand for the condition.
  final int value;
}

/// _ToolValidationTextCheckDraft stores one stdout or stderr text check.
class _ToolValidationTextCheckDraft {
  /// Creates a text check from a condition and operand.
  const _ToolValidationTextCheckDraft({
    required this.condition,
    required this.value,
  });

  /// Condition id such as none, equals, contains, starts-with, or ends-with.
  final String condition;

  /// User-entered operand for the condition.
  final String value;
}

/// _ToolValidationDraft holds the dialog result before persistence.
class _ToolValidationDraft {
  /// Creates a pending validation from user-authored dialog fields.
  const _ToolValidationDraft({
    required this.idBase,
    required this.scenario,
    required this.target,
    required this.boundary,
    required this.input,
    required this.expected,
    this.runbookTarget,
    this.runbookBoundary = '',
    this.runbookIdBase = '',
  });

  /// Base id used when creating the validation record.
  final String idBase;

  /// User-facing validation scenario name.
  final String scenario;

  /// Invocation target selected by the user.
  final ToolValidationTargetConfig target;

  /// Runtime boundary selected by the user.
  final String boundary;

  /// Input values configured by the user.
  final Map<String, dynamic> input;

  /// Expected result checks configured by the user.
  final _ToolValidationExpectedDraft expected;

  /// Optional runbook envelope target created from the same authored fields.
  final ToolValidationTargetConfig? runbookTarget;

  /// Runtime boundary used by the companion runbook envelope validation.
  final String runbookBoundary;

  /// Base id used for the companion runbook envelope validation.
  final String runbookIdBase;
}

/// _ToolValidationDraftDialog collects one validation case from the user.
class _ToolValidationDraftDialog extends StatefulWidget {
  /// Creates a validation-authoring dialog from available target choices.
  const _ToolValidationDraftDialog({required this.choices});

  /// Target choices available for the active command or MCP tool.
  final List<_ToolValidationAuthoringChoice> choices;

  /// Creates state for the validation-authoring dialog.
  @override
  State<_ToolValidationDraftDialog> createState() =>
      _ToolValidationDraftDialogState();
}

class _ToolValidationDraftDialogState
    extends State<_ToolValidationDraftDialog> {
  final TextEditingController _scenario = TextEditingController();
  final TextEditingController _input = TextEditingController();
  final TextEditingController _exitCode = TextEditingController(text: '0');
  final List<_ToolValidationCheckEditor> _outputChecks =
      <_ToolValidationCheckEditor>[_ToolValidationCheckEditor()];
  final List<_ToolValidationCheckEditor> _errorChecks =
      <_ToolValidationCheckEditor>[_ToolValidationCheckEditor()];
  int _choiceIndex = 0;
  String _expectedStatus = 'succeeded';
  String _exitCodeCondition = 'equals';

  /// Initializes field controllers from the first available target.
  @override
  void initState() {
    super.initState();
    _applyChoice(widget.choices.first);
  }

  /// Cleans up dialog field controllers.
  @override
  void dispose() {
    _scenario.dispose();
    _input.dispose();
    _exitCode.dispose();
    for (final check in _outputChecks) {
      check.dispose();
    }
    for (final check in _errorChecks) {
      check.dispose();
    }
    super.dispose();
  }

  /// Builds the typed validation authoring dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add validation'),
      content: SizedBox(
        width: 1040,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.choices.length > 1) ...<Widget>[
                PanelLabeledFormControl(
                  label: 'Target',
                  child: DropdownButtonFormField<int>(
                    initialValue: _choiceIndex,
                    isDense: true,
                    style: SettingsFormTextStyle.field(context),
                    decoration: SettingsInputDecoration.field(
                      context,
                      label: 'Target',
                    ),
                    items: <DropdownMenuItem<int>>[
                      for (
                        var index = 0;
                        index < widget.choices.length;
                        index++
                      )
                        DropdownMenuItem<int>(
                          value: index,
                          child: Text(widget.choices[index].menuLabel),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null || value == _choiceIndex) {
                        return;
                      }
                      setState(() {
                        _choiceIndex = value;
                        _applyChoice(widget.choices[value]);
                      });
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
              PanelLabeledFormControl(
                label: 'Scenario',
                child: TextField(
                  controller: _scenario,
                  autofocus: true,
                  decoration: SettingsInputDecoration.field(
                    context,
                    label: 'Scenario',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              PanelLabeledFormControl(
                label: 'Input',
                child: TextField(
                  controller: _input,
                  minLines: 2,
                  maxLines: 5,
                  decoration: SettingsInputDecoration.field(
                    context,
                    label: 'Input',
                    hintText: 'name=value',
                    alignLabelWithHint: true,
                    multiline: true,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              PanelLabeledFormControl(
                label: 'Expected status',
                child: DropdownButtonFormField<String>(
                  initialValue: _expectedStatus,
                  isDense: true,
                  style: SettingsFormTextStyle.field(context),
                  decoration: SettingsInputDecoration.field(
                    context,
                    label: 'Expected status',
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: 'succeeded',
                      child: Text('Succeeded'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'failed',
                      child: Text('Failed'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _expectedStatus = value ?? 'succeeded');
                  },
                ),
              ),
              const SizedBox(height: 10),
              _ToolValidationNumberCheckRow(
                label: 'Expected return code',
                condition: _exitCodeCondition,
                controller: _exitCode,
                onConditionChanged: (value) {
                  setState(() => _exitCodeCondition = value);
                },
              ),
              const SizedBox(height: 10),
              _ToolValidationCheckList(
                label: 'Expected output',
                checks: _outputChecks,
                onChanged: () => setState(() {}),
                onAdd: () {
                  setState(() {
                    _outputChecks.add(_ToolValidationCheckEditor());
                  });
                },
                onRemove: (index) {
                  setState(() {
                    _outputChecks.removeAt(index).dispose();
                    if (_outputChecks.isEmpty) {
                      _outputChecks.add(_ToolValidationCheckEditor());
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              _ToolValidationCheckList(
                label: 'Expected error',
                checks: _errorChecks,
                onChanged: () => setState(() {}),
                onAdd: () {
                  setState(() {
                    _errorChecks.add(_ToolValidationCheckEditor());
                  });
                },
                onRemove: (index) {
                  setState(() {
                    _errorChecks.removeAt(index).dispose();
                    if (_errorChecks.isEmpty) {
                      _errorChecks.add(_ToolValidationCheckEditor());
                    }
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Add')),
      ],
    );
  }

  /// Updates controllers with the selected target defaults.
  void _applyChoice(_ToolValidationAuthoringChoice choice) {
    _scenario.text = choice.defaultLabel;
    _input.text = _validationInputText(choice.input);
  }

  /// Returns a single user-authored validation draft.
  void _save() {
    final choice = widget.choices[_choiceIndex];
    final scenario = _scenario.text.trim();
    if (scenario.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      _ToolValidationDraft(
        idBase: '${choice.idBase}_mocked',
        scenario: scenario,
        target: choice.target,
        boundary: choice.boundary,
        input: _validationInputFromText(_input.text, choice.input),
        expected: _ToolValidationExpectedDraft(
          status: _expectedStatus,
          exitCodeCheck: _exitCodeCheckFromEditor(
            _exitCodeCondition,
            _exitCode,
          ),
          outputChecks: _checksFromEditors(_outputChecks),
          errorChecks: _checksFromEditors(_errorChecks),
        ),
        runbookTarget: choice.runbookTarget,
        runbookBoundary: choice.runbookBoundary,
        runbookIdBase: choice.runbookIdBase,
      ),
    );
  }
}

/// _ToolValidationNumberCheckRow renders one numeric condition/value editor.
class _ToolValidationNumberCheckRow extends StatelessWidget {
  /// Creates one numeric check row.
  const _ToolValidationNumberCheckRow({
    required this.label,
    required this.condition,
    required this.controller,
    required this.onConditionChanged,
  });

  /// Field label shown on the value input.
  final String label;

  /// Selected numeric condition.
  final String condition;

  /// Numeric value controller.
  final TextEditingController controller;

  /// Called when the condition changes.
  final ValueChanged<String> onConditionChanged;

  /// Builds one compact condition picker plus numeric value input.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 240,
          child: PanelLabeledFormControl(
            label: 'Condition',
            child: DropdownButtonFormField<String>(
              initialValue: condition,
              isDense: true,
              style: SettingsFormTextStyle.field(context),
              isExpanded: true,
              decoration: SettingsInputDecoration.field(
                context,
                label: 'Condition',
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'equals',
                  child: Text('Equals'),
                ),
                DropdownMenuItem<String>(
                  value: 'not-equals',
                  child: Text('Not equals'),
                ),
                DropdownMenuItem<String>(
                  value: 'greater-than',
                  child: Text('Greater than'),
                ),
                DropdownMenuItem<String>(
                  value: 'less-than',
                  child: Text('Less than'),
                ),
              ],
              onChanged: (value) => onConditionChanged(value ?? 'equals'),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: PanelLabeledFormControl(
            label: label,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: SettingsInputDecoration.field(context, label: label),
            ),
          ),
        ),
      ],
    );
  }
}

/// _ToolValidationCheckEditor owns one editable text-check row.
class _ToolValidationCheckEditor {
  /// Creates a text-check editor with a default no-op condition.
  _ToolValidationCheckEditor();

  /// Selected condition id.
  String condition = 'none';

  /// Operand text for the selected condition.
  final TextEditingController value = TextEditingController();

  /// Disposes the row controller.
  void dispose() {
    value.dispose();
  }
}

/// _ToolValidationCheckList renders addable/removable assertion rows.
class _ToolValidationCheckList extends StatelessWidget {
  /// Creates a text-check list for stdout or stderr expectations.
  const _ToolValidationCheckList({
    required this.label,
    required this.checks,
    required this.onChanged,
    required this.onAdd,
    required this.onRemove,
  });

  /// Field group label.
  final String label;

  /// Mutable check editors owned by the dialog state.
  final List<_ToolValidationCheckEditor> checks;

  /// Called when a check row changes.
  final VoidCallback onChanged;

  /// Called to append a check row.
  final VoidCallback onAdd;

  /// Called to remove a check row by index.
  final ValueChanged<int> onRemove;

  /// Builds the list of conditional text assertions.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
            IconButton(
              tooltip: 'Add $label check',
              onPressed: onAdd,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < checks.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: 8),
          _ToolValidationCheckRow(
            check: checks[index],
            canRemove: checks.length > 1,
            onChanged: onChanged,
            onRemove: () => onRemove(index),
          ),
        ],
      ],
    );
  }
}

/// _ToolValidationCheckRow renders one condition/value assertion editor.
class _ToolValidationCheckRow extends StatelessWidget {
  /// Creates one conditional text-check row.
  const _ToolValidationCheckRow({
    required this.check,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  /// Editable row state.
  final _ToolValidationCheckEditor check;

  /// Whether the delete button should be enabled.
  final bool canRemove;

  /// Called when condition or value changes.
  final VoidCallback onChanged;

  /// Called to delete this row.
  final VoidCallback onRemove;

  /// Builds one compact condition picker plus value input.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 240,
          child: PanelLabeledFormControl(
            label: 'Condition',
            child: DropdownButtonFormField<String>(
              initialValue: check.condition,
              isDense: true,
              style: SettingsFormTextStyle.field(context),
              isExpanded: true,
              decoration: SettingsInputDecoration.field(
                context,
                label: 'Condition',
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'none', child: Text('None')),
                DropdownMenuItem<String>(
                  value: 'equals',
                  child: Text('Equals'),
                ),
                DropdownMenuItem<String>(
                  value: 'contains',
                  child: Text('Contains'),
                ),
                DropdownMenuItem<String>(
                  value: 'starts-with',
                  child: Text('Starts with'),
                ),
                DropdownMenuItem<String>(
                  value: 'ends-with',
                  child: Text('Ends with'),
                ),
              ],
              onChanged: (value) {
                check.condition = value ?? 'none';
                onChanged();
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: PanelLabeledFormControl(
            label: 'Text',
            child: TextField(
              controller: check.value,
              enabled: check.condition != 'none',
              decoration: SettingsInputDecoration.field(context, label: 'Text'),
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Delete check',
          onPressed: canRemove ? onRemove : null,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}

/// Returns a numeric exit-code check from the row editor.
_ToolValidationNumberCheckDraft? _exitCodeCheckFromEditor(
  String condition,
  TextEditingController controller,
) {
  final value = int.tryParse(controller.text.trim());
  if (value == null) {
    return null;
  }
  return _ToolValidationNumberCheckDraft(
    condition: condition.trim().isEmpty ? 'equals' : condition.trim(),
    value: value,
  );
}

/// Returns configured text checks from editable UI rows.
List<_ToolValidationTextCheckDraft> _checksFromEditors(
  List<_ToolValidationCheckEditor> editors,
) {
  final active = <_ToolValidationTextCheckDraft>[
    for (final editor in editors)
      if (editor.condition != 'none' && editor.value.text.trim().isNotEmpty)
        _ToolValidationTextCheckDraft(
          condition: editor.condition,
          value: editor.value.text.trim(),
        ),
  ];
  if (active.isNotEmpty) {
    return active;
  }
  return const <_ToolValidationTextCheckDraft>[
    _ToolValidationTextCheckDraft(condition: 'none', value: ''),
  ];
}

/// Returns validation authoring targets for the active tool surface.
List<_ToolValidationAuthoringChoice> _toolValidationAuthoringChoices(
  ToolConfigDocument document,
  _ToolSettingsSurface surface, {
  String tabId = '',
}) {
  return switch (surface) {
    _ToolSettingsSurface.osTools => _commandValidationAuthoringChoices(
      document,
      tabId,
    ),
    _ToolSettingsSurface.mcpServer => _mcpValidationAuthoringChoices(
      document,
      tabId,
    ),
  };
}

/// Returns command validation target choices for one selected operation.
List<_ToolValidationAuthoringChoice> _commandValidationAuthoringChoices(
  ToolConfigDocument document,
  String tabId,
) {
  final target = _firstCommandValidationTarget(document, tabId);
  if (target == null) {
    return const <_ToolValidationAuthoringChoice>[];
  }
  final id = '${target.command}.${target.operation}';
  final input = _defaultCommandValidationInput(
    document,
    target.command,
    target.operation,
  );
  final runbookTarget = _toolValidationTargetWithType(target, 'runbook-node');
  return <_ToolValidationAuthoringChoice>[
    _ToolValidationAuthoringChoice(
      menuLabel: 'Command operation and runbook envelope',
      idBase: '${target.command}_${target.operation}_command',
      defaultLabel: id,
      target: target,
      boundary: 'command.execute',
      input: input,
      runbookTarget: runbookTarget,
      runbookBoundary: 'command.execute',
      runbookIdBase: '${target.command}_${target.operation}_runbook',
    ),
  ];
}

/// Returns MCP validation target choices for one selected tool.
List<_ToolValidationAuthoringChoice> _mcpValidationAuthoringChoices(
  ToolConfigDocument document,
  String tabId,
) {
  final target = _firstMcpValidationTarget(document, tabId);
  if (target == null) {
    return const <_ToolValidationAuthoringChoice>[];
  }
  final id = '${target.mcpServer}.${target.mcpTool}';
  final runbookTarget = _toolValidationTargetWithType(target, 'runbook-node');
  return <_ToolValidationAuthoringChoice>[
    _ToolValidationAuthoringChoice(
      menuLabel: 'MCP tool call and runbook envelope',
      idBase: '${target.mcpServer}_${target.mcpTool}_mcp',
      defaultLabel: id,
      target: target,
      boundary: 'mcp.call',
      input: const <String, dynamic>{},
      runbookTarget: runbookTarget,
      runbookBoundary: 'mcp.call',
      runbookIdBase: '${target.mcpServer}_${target.mcpTool}_runbook',
    ),
  ];
}

/// Returns a validation target with the same surface and a different type.
ToolValidationTargetConfig _toolValidationTargetWithType(
  ToolValidationTargetConfig target,
  String type,
) {
  return ToolValidationTargetConfig(
    type: type,
    presetId: target.presetId,
    command: target.command,
    operation: target.operation,
    mcpServer: target.mcpServer,
    mcpTool: target.mcpTool,
    extra: target.extra,
  );
}

/// Formats primitive validation input as user-editable key-value rows.
String _validationInputText(Map<String, dynamic> input) {
  return input.entries
      .map((entry) => '${entry.key}=${_validationInputTextValue(entry.value)}')
      .join('\n');
}

/// Formats one validation input value for the key-value editor.
String _validationInputTextValue(Object? value) {
  if (value is List || value is Map<String, dynamic>) {
    return jsonEncode(value);
  }
  return '${value ?? ''}';
}

/// Parses key-value validation input while preserving seeded value types.
Map<String, dynamic> _validationInputFromText(
  String text,
  Map<String, dynamic> seed,
) {
  final pairs = SettingsTextCodec.keyValues(text);
  return <String, dynamic>{
    for (final entry in pairs.entries)
      entry.key: _coercedValidationInputValue(entry.value, seed[entry.key]),
  };
}

/// Coerces a user-entered validation input value to the seeded value type.
Object _coercedValidationInputValue(String value, Object? seed) {
  final trimmed = value.trim();
  if (seed is int) {
    return int.tryParse(trimmed) ?? seed;
  }
  if (seed is double) {
    return double.tryParse(trimmed) ?? seed;
  }
  if (seed is bool) {
    final lower = trimmed.toLowerCase();
    if (lower == 'true' || lower == 'yes' || lower == '1') {
      return true;
    }
    if (lower == 'false' || lower == 'no' || lower == '0') {
      return false;
    }
    return seed;
  }
  if (seed is List || seed is Map<String, dynamic>) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Object) {
        return decoded;
      }
    } on FormatException {
      return seed ?? trimmed;
    }
    return seed ?? trimmed;
  }
  return trimmed;
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

/// Creates validation input from one operation's typed sample values.
Map<String, dynamic> _defaultCommandValidationInput(
  ToolConfigDocument document,
  String commandName,
  String operationName,
) {
  final operation = _localExecOperationByName(
    document,
    commandName,
    operationName,
  );
  if (operation == null) {
    return const <String, dynamic>{};
  }
  final input = <String, dynamic>{
    ..._sampleInputFromSchema(operation.inputSchema),
  };
  for (final key in _templateParameterNames(operation.args)) {
    input.putIfAbsent(key, () => 'sample');
  }
  return input;
}

/// Finds one local command operation by command and operation name.
LocalExecOperationConfig? _localExecOperationByName(
  ToolConfigDocument document,
  String commandName,
  String operationName,
) {
  final command = _localExecCommandByName(document, commandName);
  if (command == null) {
    return null;
  }
  for (final operation in command.operations) {
    if (operation.name.trim() == operationName.trim()) {
      return operation;
    }
  }
  return null;
}

/// Builds sample validation input from supported object-schema properties.
Map<String, dynamic> _sampleInputFromSchema(Map<String, dynamic> schema) {
  final properties = jsonObject(schema['properties']);
  final required = stringList(schema['required'], trim: true).toSet();
  final input = <String, dynamic>{};
  for (final entry in properties.entries) {
    final name = entry.key.trim();
    if (name.isEmpty) {
      continue;
    }
    final property = jsonObject(entry.value);
    final sample = _sampleValueFromProperty(property);
    if (sample != null ||
        required.contains(name) ||
        property.containsKey('default')) {
      input[name] = sample ?? _fallbackSampleValue(property);
    }
  }
  return input;
}

/// Returns the preferred sample value for one JSON Schema property.
Object? _sampleValueFromProperty(Map<String, dynamic> property) {
  if (property.containsKey('default')) {
    return property['default'];
  }
  final examples = property['examples'] is List
      ? property['examples'] as List<dynamic>
      : const <dynamic>[];
  if (examples.isNotEmpty) {
    return examples.first;
  }
  final enumValues = property['enum'] is List
      ? property['enum'] as List<dynamic>
      : const <dynamic>[];
  if (enumValues.isNotEmpty) {
    return enumValues.first;
  }
  return null;
}

/// Returns a type-appropriate placeholder for required generated input.
Object _fallbackSampleValue(Map<String, dynamic> property) {
  switch (stringValue(property['type'], trim: true).toLowerCase()) {
    case 'integer':
      return 1;
    case 'number':
      return 1.0;
    case 'boolean':
      return true;
    case 'array':
      return const <dynamic>[];
    case 'object':
      return const <String, dynamic>{};
    default:
      return 'sample';
  }
}

/// Extracts simple double-brace parameter names from argv template tokens.
Set<String> _templateParameterNames(List<String> args) {
  final names = <String>{};
  final pattern = RegExp(r'\{\{\s*([\w.-]+)\s*\}\}');
  for (final token in args) {
    for (final match in pattern.allMatches(token)) {
      final name = match.group(1)?.trim() ?? '';
      if (name.isNotEmpty) {
        names.add(name);
      }
    }
  }
  return names;
}

/// Creates the direct validation and optional runbook envelope companion.
List<ToolValidationConfig> _toolValidationsForDraft(
  Set<String> existingIds,
  _ToolValidationDraft draft,
) {
  final validations = <ToolValidationConfig>[
    _toolValidation(
      id: _uniqueToolValidationId(existingIds, draft.idBase),
      label: draft.scenario,
      description: '',
      mode: 'mocked',
      target: draft.target,
      boundary: draft.boundary,
      input: draft.input,
      expected: draft.expected,
    ),
  ];
  final runbookTarget = draft.runbookTarget;
  if (runbookTarget != null && draft.runbookBoundary.trim().isNotEmpty) {
    validations.add(
      _toolValidation(
        id: _uniqueToolValidationId(
          existingIds,
          '${draft.runbookIdBase}_mocked',
        ),
        label: '${draft.scenario} runbook envelope',
        description: '',
        mode: 'mocked',
        target: runbookTarget,
        boundary: draft.runbookBoundary,
        input: draft.input,
        expected: draft.expected,
      ),
    );
  }
  return validations;
}

/// Creates one validation with concrete assertions for its invocation lane.
ToolValidationConfig _toolValidation({
  required String id,
  required String label,
  required String description,
  required String mode,
  required ToolValidationTargetConfig target,
  required String boundary,
  required Map<String, dynamic> input,
  required _ToolValidationExpectedDraft expected,
  String prompt = '',
}) {
  return ToolValidationConfig(
    id: id,
    label: label,
    description: description,
    mode: mode,
    target: target,
    prompt: prompt,
    input: input,
    fixtures: const <String, dynamic>{},
    mocks: mode == 'mocked'
        ? <String, dynamic>{
            boundary: _mockedToolValidationResponse(
              target,
              label,
              input,
              expected,
            ),
          }
        : const <String, dynamic>{},
    expected: <String, dynamic>{
      if (expected.status.trim().isNotEmpty) 'status': expected.status.trim(),
      if (expected.exitCodeCheck?.condition == 'equals')
        'exit_code': expected.exitCodeCheck?.value,
    },
    assertions: _toolValidationAssertions(target, mode, input, expected),
  );
}

/// Creates a mocked boundary response that proves the selected target shape.
Map<String, dynamic> _mockedToolValidationResponse(
  ToolValidationTargetConfig target,
  String label,
  Map<String, dynamic> input,
  _ToolValidationExpectedDraft expected,
) {
  final response = <String, dynamic>{
    'status': expected.status.trim().isEmpty ? 'succeeded' : expected.status,
    if (expected.exitCodeCheck != null)
      'exit_code': _mockedExitCodeForCheck(expected.exitCodeCheck!),
    'stdout': _mockedTextForChecks(expected.outputChecks),
    if (_mockedTextForChecks(expected.errorChecks).isNotEmpty)
      'stderr': _mockedTextForChecks(expected.errorChecks),
  };
  if (target.type == 'agent-tool-call' &&
      target.command.isNotEmpty &&
      target.operation.isNotEmpty) {
    response['output'] = <String, dynamic>{
      'tool_name': 'command_execute',
      'arguments': <String, dynamic>{
        'template_id': '${target.command}.${target.operation}',
        if (input.isNotEmpty) 'parameters': input,
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

/// Returns mock text that will satisfy the configured text checks.
String _mockedTextForChecks(List<_ToolValidationTextCheckDraft> checks) {
  final values = <String>[
    for (final check in checks)
      if (check.condition != 'none' && check.value.trim().isNotEmpty)
        check.value.trim(),
  ];
  return values.join('\n');
}

/// Returns a mock exit code that satisfies one numeric condition.
int _mockedExitCodeForCheck(_ToolValidationNumberCheckDraft check) {
  switch (check.condition) {
    case 'not-equals':
    case 'greater-than':
      return check.value + 1;
    case 'less-than':
      return check.value - 1;
    case 'equals':
    default:
      return check.value;
  }
}

/// Creates concrete assertions for one generated starter validation.
List<ToolValidationAssertionConfig> _toolValidationAssertions(
  ToolValidationTargetConfig target,
  String mode,
  Map<String, dynamic> input,
  _ToolValidationExpectedDraft expected,
) {
  final assertions = <ToolValidationAssertionConfig>[
    ToolValidationAssertionConfig(
      type: 'status',
      path: '',
      equals: expected.status.trim().isEmpty ? 'succeeded' : expected.status,
      contains: '',
      matches: '',
      schema: const <String, dynamic>{},
      message: '',
    ),
  ];
  final exitCodeAssertion = _exitCodeAssertion(expected.exitCodeCheck);
  if (exitCodeAssertion != null) {
    assertions.add(exitCodeAssertion);
  }
  assertions.addAll(_textCheckAssertions('stdout', expected.outputChecks));
  assertions.addAll(_textCheckAssertions('stderr', expected.errorChecks));
  if (target.type == 'agent-tool-call' &&
      target.command.isNotEmpty &&
      target.operation.isNotEmpty) {
    assertions.add(
      ToolValidationAssertionConfig(
        type: 'json-path',
        path: mode == 'live'
            ? 'output.tool_calls.0.arguments.template_id'
            : 'output.arguments.template_id',
        equals: '${target.command}.${target.operation}',
        contains: '',
        matches: '',
        schema: const <String, dynamic>{},
        message: '',
      ),
    );
  }
  if (target.type == 'runbook-node' &&
      target.command.isNotEmpty &&
      target.operation.isNotEmpty) {
    assertions.add(
      ToolValidationAssertionConfig(
        type: 'json-path',
        path: 'output.request.template_id',
        equals: '${target.command}.${target.operation}',
        contains: '',
        matches: '',
        schema: const <String, dynamic>{},
        message: '',
      ),
    );
    for (final entry in _orderedValidationInputEntries(input)) {
      assertions.add(
        ToolValidationAssertionConfig(
          type: 'json-path',
          path: 'output.request.parameters.${entry.key}',
          equals: entry.value,
          contains: '',
          matches: '',
          schema: const <String, dynamic>{},
          message: '',
        ),
      );
    }
  }
  if (target.type == 'agent-tool-call' &&
      target.mcpServer.isNotEmpty &&
      target.mcpTool.isNotEmpty) {
    assertions.add(
      ToolValidationAssertionConfig(
        type: 'json-path',
        path: mode == 'live'
            ? 'output.tool_calls.0.name'
            : 'output.arguments.tool',
        equals: mode == 'live' ? null : target.mcpTool,
        contains: mode == 'live' ? target.mcpTool : '',
        matches: '',
        schema: const <String, dynamic>{},
        message: '',
      ),
    );
  }
  if (target.type == 'runbook-node' &&
      target.mcpServer.isNotEmpty &&
      target.mcpTool.isNotEmpty) {
    assertions.addAll(<ToolValidationAssertionConfig>[
      ToolValidationAssertionConfig(
        type: 'json-path',
        path: 'output.request.server_id',
        equals: target.mcpServer,
        contains: '',
        matches: '',
        schema: const <String, dynamic>{},
        message: '',
      ),
      ToolValidationAssertionConfig(
        type: 'json-path',
        path: 'output.request.tool',
        equals: target.mcpTool,
        contains: '',
        matches: '',
        schema: const <String, dynamic>{},
        message: '',
      ),
    ]);
    for (final entry in _orderedValidationInputEntries(input)) {
      assertions.add(
        ToolValidationAssertionConfig(
          type: 'json-path',
          path: 'output.request.arguments.${entry.key}',
          equals: entry.value,
          contains: '',
          matches: '',
          schema: const <String, dynamic>{},
          message: '',
        ),
      );
    }
  }
  return assertions;
}

/// Builds one assertion from a numeric exit-code check.
ToolValidationAssertionConfig? _exitCodeAssertion(
  _ToolValidationNumberCheckDraft? check,
) {
  if (check == null) {
    return null;
  }
  return ToolValidationAssertionConfig(
    type: switch (check.condition) {
      'not-equals' => 'exit-code-not-equals',
      'greater-than' => 'exit-code-greater-than',
      'less-than' => 'exit-code-less-than',
      _ => 'exit-code',
    },
    path: '',
    equals: check.value,
    contains: '',
    matches: '',
    schema: const <String, dynamic>{},
    message: '',
  );
}

/// Builds stdout or stderr assertions from conditional text checks.
List<ToolValidationAssertionConfig> _textCheckAssertions(
  String stream,
  List<_ToolValidationTextCheckDraft> checks,
) {
  return <ToolValidationAssertionConfig>[
    for (final check in checks)
      if (_textCheckAssertion(stream, check) != null)
        _textCheckAssertion(stream, check)!,
  ];
}

/// Builds one assertion from a conditional text check.
ToolValidationAssertionConfig? _textCheckAssertion(
  String stream,
  _ToolValidationTextCheckDraft check,
) {
  final value = check.value.trim();
  final path = stream == 'stderr' ? 'stderr' : 'stdout';
  if (check.condition == 'none') {
    return ToolValidationAssertionConfig(
      type: 'json-path',
      path: path,
      equals: '',
      contains: '',
      matches: '',
      schema: const <String, dynamic>{},
      message: '',
    );
  }
  if (value.isEmpty) {
    return null;
  }
  switch (check.condition) {
    case 'equals':
      return ToolValidationAssertionConfig(
        type: 'json-path',
        path: path,
        equals: value,
        contains: '',
        matches: '',
        schema: const <String, dynamic>{},
        message: '',
      );
    case 'starts-with':
      return ToolValidationAssertionConfig(
        type: 'json-path',
        path: path,
        equals: null,
        contains: '',
        matches: '^${RegExp.escape(value)}',
        schema: const <String, dynamic>{},
        message: '',
      );
    case 'ends-with':
      return ToolValidationAssertionConfig(
        type: 'json-path',
        path: path,
        equals: null,
        contains: '',
        matches: '${RegExp.escape(value)}\$',
        schema: const <String, dynamic>{},
        message: '',
      );
    case 'contains':
    default:
      return ToolValidationAssertionConfig(
        type: stream == 'stderr' ? 'stderr-contains' : 'stdout-contains',
        path: '',
        equals: null,
        contains: value,
        matches: '',
        schema: const <String, dynamic>{},
        message: '',
      );
  }
}

/// Returns validation input entries in stable UI-authored order.
Iterable<MapEntry<String, dynamic>> _orderedValidationInputEntries(
  Map<String, dynamic> input,
) {
  return input.entries.where((entry) => entry.key.trim().isNotEmpty);
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
    'runbook-node' => 'Runbook envelope: $callable',
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
    'runbook-node' => 'Runbook envelope: $callable',
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
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return '$value';
  }
}

/// Merges selected validation reruns into the previous suite result.
ToolValidationSuiteResult _mergedValidationResults(
  ToolValidationSuiteResult? previous,
  ToolValidationSuiteResult next,
) => mergeToolValidationSuiteResults(previous, next);
