/// Config file text editor widgets.
part of 'settings_panel.dart';

class _SettingsConfigFileEditor extends StatefulWidget {
  const _SettingsConfigFileEditor({
    required this.controller,
    required this.entry,
    required this.title,
    required this.query,
    required this.onRenamed,
  });

  final AgentAwesomeAppController controller;
  final ConfigFileEntry entry;
  final String title;
  final String query;
  final ValueChanged<String> onRenamed;

  @override
  State<_SettingsConfigFileEditor> createState() =>
      _SettingsConfigFileEditorState();
}

class _SettingsConfigFileEditorState extends State<_SettingsConfigFileEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.entry.label,
  );
  late String _savedName = widget.entry.label;

  /// Cleans up config editor controllers.
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Keeps the editable name synchronized with the selected file.
  @override
  void didUpdateWidget(covariant _SettingsConfigFileEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path) {
      _name.text = widget.entry.label;
      _savedName = widget.entry.label;
    }
  }

  /// Builds the selected model or agent config editor.
  @override
  Widget build(BuildContext context) {
    if (!SettingsQuery.matches(widget.query, <String>[
      widget.entry.label,
      widget.entry.path,
    ])) {
      return PanelEmptyState(query: widget.query);
    }
    return FormPanel(
      children: <Widget>[
        FormSectionCard(
          title: 'Details',
          children: <Widget>[
            _SettingsAutoSaveTextField(
              label: 'Name',
              controller: _name,
              initialSavedValue: _savedName,
              onSave: _rename,
            ),
          ],
        ),
        _SettingsTextFileEditor(
          controller: widget.controller,
          title: widget.title,
          path: widget.entry.path,
        ),
      ],
    );
  }

  Future<void> _rename(String value) async {
    try {
      final path = await widget.controller.renameConfigFile(
        widget.entry,
        value,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _savedName = value.trim();
      });
      widget.onRenamed(path);
    } catch (_) {}
  }
}

class SettingsAgentConfigCollection extends StatefulWidget {
  const SettingsAgentConfigCollection({
    super.key,
    required this.controller,
    required this.entries,
    required this.assignedPath,
    this.selectedPath,
    this.onSelectedPathChanged,
    required this.modeId,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final List<ConfigFileEntry> entries;
  final String assignedPath;
  final String? selectedPath;
  final ValueChanged<String>? onSelectedPathChanged;
  final String modeId;
  final String query;

  @override
  State<SettingsAgentConfigCollection> createState() =>
      _SettingsAgentConfigCollectionState();
}

class _SettingsAgentConfigCollectionState
    extends State<SettingsAgentConfigCollection> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _instruction = TextEditingController();
  AgentConfigDocument? _document;
  String _savedName = '';
  String _savedDescription = '';
  String _savedInstruction = '';
  bool _loading = true;

  /// Loads the selected agent config file.
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Reloads structured state when the selected file changes.
  @override
  void didUpdateWidget(covariant SettingsAgentConfigCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedEntry()?.path != _selectedEntryFor(oldWidget)?.path) {
      _document = null;
      _loading = true;
      unawaited(_load());
    }
  }

  /// Cleans up field controllers.
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _instruction.dispose();
    super.dispose();
  }

  /// Builds the selected agent config editor.
  @override
  Widget build(BuildContext context) {
    final entry = _selectedEntry();
    final document = _document;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entry == null || document == null) {
      if (!SettingsQuery.matches(widget.query, <String>[
        'Agents',
        'No agent configs configured',
      ])) {
        return PanelEmptyState(query: widget.query);
      }
      return const FormPanel(
        children: <Widget>[
          FormSectionCard(
            title: 'Agent config',
            children: <Widget>[
              PanelEmptyBlock(label: 'No agent configs configured'),
            ],
          ),
        ],
      );
    }
    if (!SettingsQuery.matches(widget.query, _searchValues(entry, document))) {
      return PanelEmptyState(query: widget.query);
    }
    return _buildDetails(entry, document);
  }

  /// Builds high-level agent metadata and instruction fields.
  Widget _buildDetails(ConfigFileEntry entry, AgentConfigDocument document) {
    final profile = widget.controller.runtimeProfile;
    return FormPanel(
      children: <Widget>[
        FormPlainSection(
          title: 'Agent',
          children: <Widget>[
            _SettingsAutoSaveTextField(
              label: 'Name',
              controller: _name,
              initialSavedValue: _savedName,
              onSave: _rename,
            ),
            _SettingsAutoSaveTextField(
              label: 'Description',
              controller: _description,
              initialSavedValue: _savedDescription,
              onSave: _saveDescription,
              minLines: 2,
              maxLines: 4,
            ),
            _SettingsAutoSaveTextField(
              label: 'Instruction',
              controller: _instruction,
              initialSavedValue: _savedInstruction,
              onSave: _saveInstruction,
              minLines: 12,
              maxLines: 24,
            ),
          ],
        ),
        if (profile != null) ...<Widget>[
          _SettingsMemoryAccessReviewTile(profile: profile),
          _SettingsAgentMemoryTile(
            profile: profile,
            controller: widget.controller,
          ),
        ],
      ],
    );
  }

  /// Returns values matched by right-pane filtering.
  List<String> _searchValues(
    ConfigFileEntry entry,
    AgentConfigDocument document,
  ) {
    return <String>[
      entry.label,
      entry.path,
      document.name,
      document.description,
      document.instruction,
      if (widget.controller.runtimeProfile != null) ...<String>[
        widget.controller.runtimeProfile!.agentMemory.actor,
        widget.controller.runtimeProfile!.agentMemory.readDomains.join(' '),
        widget.controller.runtimeProfile!.agentMemory.writeDomains.join(' '),
        widget.controller.runtimeProfile!.agentMemory.defaultWriteDomain,
      ],
    ];
  }

  /// Resolves the selected agent config entry from widget state.
  ConfigFileEntry? _selectedEntry() {
    return _selectedEntryFor(widget);
  }

  /// Resolves the selected agent config entry for one widget snapshot.
  ConfigFileEntry? _selectedEntryFor(SettingsAgentConfigCollection widget) {
    if (widget.entries.isEmpty) {
      return null;
    }
    final selected = widget.selectedPath;
    if (selected != null) {
      for (final entry in widget.entries) {
        if (entry.path == selected) {
          return entry;
        }
      }
    }
    if (widget.assignedPath.isNotEmpty) {
      for (final entry in widget.entries) {
        if (entry.path == widget.assignedPath) {
          return entry;
        }
      }
    }
    return widget.entries.first;
  }

  /// Loads and parses the selected agent config.
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
      final document = AgentConfigDocument.parse(content);
      _hydrateFields(entry, document);
      if (!mounted) {
        return;
      }
      setState(() {
        _document = document;
        _loading = false;
      });
    } catch (_) {
      final document = emptyAgentConfigDocument().copyWith(name: entry.label);
      _hydrateFields(entry, document);
      if (!mounted) {
        return;
      }
      setState(() {
        _document = document;
        _loading = false;
      });
    }
  }

  /// Synchronizes field controllers with parsed document state.
  void _hydrateFields(ConfigFileEntry entry, AgentConfigDocument document) {
    final name = document.name.trim().isEmpty ? entry.label : document.name;
    _name.text = name;
    _description.text = document.description;
    _instruction.text = document.instruction;
    _savedName = name;
    _savedDescription = document.description;
    _savedInstruction = document.instruction;
  }

  /// Saves the selected agent config document.
  Future<void> _save(AgentConfigDocument document) async {
    final entry = _selectedEntry();
    if (entry == null) {
      return;
    }
    await widget.controller.saveConfigurationFile(
      entry.path,
      document.toYaml(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _document = document);
    try {
      await widget.controller.refreshConfigurationCollections();
    } catch (_) {}
  }

  /// Saves the user-facing agent name into typed config metadata.
  Future<void> _rename(String value) async {
    final entry = _selectedEntry();
    final document = _document;
    final trimmed = value.trim();
    if (entry == null || document == null || trimmed.isEmpty) {
      return;
    }
    final next = document.copyWith(name: trimmed);
    try {
      final path = await widget.controller.renameConfigFile(entry, trimmed);
      await widget.controller.saveConfigurationFile(path, next.toYaml());
      await widget.controller.refreshConfigurationCollections();
      widget.onSelectedPathChanged?.call(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _document = next;
        _savedName = trimmed;
      });
    } catch (_) {}
  }

  /// Saves the agent description.
  Future<void> _saveDescription(String value) async {
    final document = _document;
    if (document == null) {
      return;
    }
    final next = document.copyWith(description: value.trim());
    _savedDescription = next.description;
    await _save(next);
  }

  /// Saves the agent instruction.
  Future<void> _saveInstruction(String value) async {
    final document = _document;
    if (document == null) {
      return;
    }
    final next = document.copyWith(instruction: value);
    _savedInstruction = next.instruction;
    await _save(next);
  }
}

class _SettingsAgentValidationCard extends StatelessWidget {
  const _SettingsAgentValidationCard({
    this.title = 'Validations',
    this.emptyLabel = 'No validations configured',
    required this.validations,
    required this.result,
    required this.fileResult,
    required this.error,
    required this.runningId,
    required this.onRunAll,
    required this.onAddValidation,
    required this.onValidationChanged,
    required this.onDeleteValidation,
    required this.onRunValidation,
  });

  final String title;
  final String emptyLabel;
  final List<AgentValidationConfig> validations;
  final AgentValidationSuiteResult? result;
  final AgentValidationFileResult? fileResult;
  final String error;
  final String runningId;
  final VoidCallback? onRunAll;
  final VoidCallback onAddValidation;
  final void Function(String id, AgentValidationConfig validation)
  onValidationChanged;
  final ValueChanged<String> onDeleteValidation;
  final ValueChanged<String> onRunValidation;

  /// Builds installed agent validation metadata for the selected agent config.
  @override
  Widget build(BuildContext context) {
    final running = runningId.isNotEmpty;
    final runningAll = runningId == _allValidationRunId;
    final resultById = <String, AgentValidationRunResult>{
      for (final item in result?.results ?? const <AgentValidationRunResult>[])
        item.id: item,
    };
    return FormPlainSection(
      title: title,
      children: <Widget>[
        _SettingsActionRow(
          children: <Widget>[
            FilledButton.icon(
              key: const ValueKey<String>('agent-validations-run-all'),
              onPressed: running ? null : onRunAll,
              icon: runningAll
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(runningAll ? 'Running' : 'Run all'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const ValueKey<String>('agent-validations-add'),
              onPressed: running ? null : onAddValidation,
              icon: const Icon(Icons.add),
              label: const Text('Add validation'),
            ),
          ],
        ),
        if (result != null) ...<Widget>[
          const SizedBox(height: SettingsFormMetrics.compactGap),
          SettingsAgentValidationSummaryView(result: result!),
        ],
        if (fileResult != null &&
            _agentValidationFileHasIssues(fileResult!)) ...<Widget>[
          const SizedBox(height: SettingsFormMetrics.compactGap),
          SettingsAgentValidationPackageIssuesView(result: fileResult!),
        ],
        if (error.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: SettingsFormMetrics.compactGap),
          _SettingsToolValidationError(message: error),
        ],
        if (validations.isNotEmpty)
          const SizedBox(height: SettingsFormMetrics.sectionGap),
        if (validations.isEmpty)
          PanelEmptyBlock(label: emptyLabel)
        else
          for (var index = 0; index < validations.length; index++) ...<Widget>[
            if (index > 0)
              const SizedBox(height: SettingsFormMetrics.compactGap),
            _SettingsAgentValidationRow(
              validation: validations[index],
              result: resultById[validations[index].id],
              running: runningId == validations[index].id,
              onChanged: (validation) =>
                  onValidationChanged(validations[index].id, validation),
              onDelete: () => onDeleteValidation(validations[index].id),
              onRun: running || validations[index].id.trim().isEmpty
                  ? null
                  : () => onRunValidation(validations[index].id),
            ),
          ],
      ],
    );
  }
}

class SettingsAgentValidationSummaryView extends StatelessWidget {
  /// Creates a compact agent validation run summary.
  const SettingsAgentValidationSummaryView({super.key, required this.result});

  /// Suite result whose aggregate evidence should be displayed.
  final AgentValidationSuiteResult result;

  /// Builds a compact validation run summary.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            PanelBadge(label: 'Total ${result.total}'),
            PanelBadge(label: 'Passed ${result.passed}'),
            PanelBadge(label: 'Failed ${result.failed}'),
            PanelBadge(label: 'Unsupported ${result.unsupported}'),
            if (result.toolCallReferences.isNotEmpty)
              PanelBadge(
                label: 'Tool calls ${result.toolCallReferences.length}',
              ),
          ],
        ),
        if (result.toolCallReferences.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: SettingsFormMetrics.compactGap),
            child: _SettingsAgentEvidenceLine(
              label: 'Tool call references',
              value: result.toolCallReferences.join('\n'),
            ),
          ),
      ],
    );
  }
}

class SettingsAgentValidationPackageIssuesView extends StatelessWidget {
  /// Creates a compact package-level agent validation issue view.
  const SettingsAgentValidationPackageIssuesView({
    super.key,
    required this.result,
  });

  /// File-level validation result whose package gates should be displayed.
  final AgentValidationFileResult result;

  /// Builds package-level gate evidence from CLI/library validation output.
  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    if (result.error.trim().isNotEmpty) {
      lines.add(
        _SettingsAgentEvidenceLine(label: 'Package error', value: result.error),
      );
    }
    if (result.missingAssertions.isNotEmpty) {
      lines.add(
        _SettingsAgentEvidenceLine(
          label: 'Missing assertions',
          value: result.missingAssertions.join('\n'),
        ),
      );
    }
    if (result.missingToolCalls.isNotEmpty) {
      lines.add(
        _SettingsAgentEvidenceLine(
          label: 'Missing tool calls',
          value: result.missingToolCalls.join('\n'),
        ),
      );
    }
    if (result.unknownToolCalls.isNotEmpty) {
      lines.add(
        _SettingsAgentEvidenceLine(
          label: 'Unknown tool calls',
          value: result.unknownToolCalls.join('\n'),
        ),
      );
    }
    if (result.invalidToolArguments.isNotEmpty) {
      lines.add(
        _SettingsAgentEvidenceLine(
          label: 'Invalid tool arguments',
          value: result.invalidToolArguments.join('\n'),
        ),
      );
    }
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
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

class _SettingsAgentValidationRow extends StatelessWidget {
  const _SettingsAgentValidationRow({
    required this.validation,
    required this.running,
    required this.onRun,
    required this.onChanged,
    required this.onDelete,
    this.result,
  });

  final AgentValidationConfig validation;
  final bool running;
  final VoidCallback? onRun;
  final ValueChanged<AgentValidationConfig> onChanged;
  final VoidCallback onDelete;
  final AgentValidationRunResult? result;

  /// Builds one validation summary row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final mode = validation.mode.trim().isEmpty ? 'Mocked' : validation.mode;
    final live = _agentValidationIsLive(validation);
    final failedAssertions =
        result?.assertions.where((assertion) => !assertion.passed).toList() ??
        const <AgentValidationAssertionResult>[];
    final diagnostics =
        result?.diagnostics ?? const <AgentValidationDiagnostic>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _agentValidationLabel(validation),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (result != null) PanelBadge(label: result!.status),
            const SizedBox(width: 6),
            PanelBadge(label: mode),
            const SizedBox(width: 6),
            PanelInlineIconButton(
              icon: Icons.play_arrow,
              tooltip: 'Run validation',
              loading: running,
              onPressed: onRun,
            ),
            const SizedBox(width: 6),
            PanelInlineIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete validation',
              onPressed: onDelete,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _SettingsInlineField(
                label: 'Label',
                value: validation.label,
                onChanged: (value) =>
                    onChanged(validation.copyWith(label: value)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 180,
              child: _SettingsAgentValidationModeField(
                value: live ? 'live' : 'mocked',
                onChanged: (value) =>
                    onChanged(validation.copyWith(mode: value)),
              ),
            ),
          ],
        ),
        _SettingsInlineField(
          label: 'Prompt',
          value: validation.prompt,
          minLines: 2,
          maxLines: 4,
          onChanged: (value) => onChanged(validation.copyWith(prompt: value)),
        ),
        _SettingsInlineField(
          label: 'Expected response contains',
          value: _agentValidationContainsAssertion(validation),
          onChanged: (value) => onChanged(
            validation.copyWith(
              assertions: _agentValidationAssertionsWithContains(
                validation.assertions,
                value,
              ),
            ),
          ),
        ),
        if (!live)
          _SettingsInlineField(
            label: 'Mock response',
            value: _agentValidationMockResponseText(validation),
            minLines: 2,
            maxLines: 4,
            onChanged: (value) => onChanged(
              validation.copyWith(
                mocks: _agentValidationMocksWithResponseText(
                  validation.mocks,
                  value,
                ),
              ),
            ),
          ),
        _SettingsInlineField(
          label: 'Expected tool call',
          value: _agentValidationToolCallAssertion(validation),
          onChanged: (value) => onChanged(
            validation.copyWith(
              mocks: live
                  ? validation.mocks
                  : _agentValidationMocksWithToolCall(validation.mocks, value),
              assertions: _agentValidationAssertionsWithToolCall(
                validation.assertions,
                value,
              ),
            ),
          ),
        ),
        _SettingsAgentToolCallArgumentsEditor(
          arguments: _agentValidationToolCallArguments(validation),
          onAdd: () =>
              onChanged(_agentValidationWithAddedToolCallArgument(validation)),
          onChanged: (oldName, name, value) => onChanged(
            _agentValidationWithToolCallArgument(
              validation,
              oldName: oldName,
              name: name,
              value: value,
            ),
          ),
          onDelete: (name) => onChanged(
            _agentValidationWithoutToolCallArgument(validation, name),
          ),
        ),
        if (validation.description.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(validation.description, style: TextStyle(color: colors.muted)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            PanelBadge(label: 'Prompt'),
            if (validation.assertions.isNotEmpty)
              PanelBadge(label: '${validation.assertions.length} assertions'),
            if (result?.response.toolCalls.isNotEmpty == true)
              PanelBadge(label: '${result!.response.toolCalls.length} calls'),
          ],
        ),
        if (validation.prompt.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(validation.prompt, style: TextStyle(color: colors.muted)),
        ],
        if (result != null) ...<Widget>[
          const SizedBox(height: 8),
          SettingsAgentValidationEvidenceView(result: result!),
        ],
        if (failedAssertions.isNotEmpty || diagnostics.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          for (final assertion in failedAssertions)
            Text(
              _agentAssertionFailureText(assertion),
              style: TextStyle(color: colors.coral),
            ),
          for (final diagnostic in diagnostics)
            Text(diagnostic.message, style: TextStyle(color: colors.muted)),
        ],
      ],
    );
  }
}

class _SettingsAgentValidationModeField extends StatelessWidget {
  const _SettingsAgentValidationModeField({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// Builds the validation execution mode selector.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SettingsFormMetrics.fieldGap),
      child: PanelLabeledFormControl(
        label: 'Mode',
        child: DropdownButtonFormField<String>(
          initialValue: value == 'live' ? 'live' : 'mocked',
          isDense: true,
          style: SettingsFormTextStyle.field(context),
          isExpanded: true,
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(value: 'mocked', child: Text('Mocked')),
            DropdownMenuItem<String>(value: 'live', child: Text('Live')),
          ],
          onChanged: (next) {
            if (next != null) {
              onChanged(next);
            }
          },
          decoration: SettingsInputDecoration.field(context, label: 'Mode'),
        ),
      ),
    );
  }
}

class _SettingsAgentToolCallArgumentsEditor extends StatelessWidget {
  const _SettingsAgentToolCallArgumentsEditor({
    required this.arguments,
    required this.onAdd,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, String> arguments;
  final VoidCallback onAdd;
  final void Function(String oldName, String name, String value) onChanged;
  final ValueChanged<String> onDelete;

  /// Builds typed parameter controls for mocked agent tool calls.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final entry in arguments.entries)
          _SettingsAgentToolCallArgumentRow(
            name: entry.key,
            value: entry.value,
            onChanged: (name, value) => onChanged(entry.key, name, value),
            onDelete: () => onDelete(entry.key),
          ),
        _SettingsActionRow(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add parameter'),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _SettingsAgentToolCallArgumentRow extends StatelessWidget {
  const _SettingsAgentToolCallArgumentRow({
    required this.name,
    required this.value,
    required this.onChanged,
    required this.onDelete,
  });

  final String name;
  final String value;
  final void Function(String name, String value) onChanged;
  final VoidCallback onDelete;

  /// Builds one editable tool-call parameter row.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: _SettingsInlineField(
            label: 'Parameter',
            value: name,
            onChanged: (next) => onChanged(next, value),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _SettingsInlineField(
            label: 'Value',
            value: value,
            onChanged: (next) => onChanged(name, next),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: PanelInlineIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete parameter',
            onPressed: onDelete,
          ),
        ),
      ],
    );
  }
}

class SettingsAgentValidationEvidenceView extends StatelessWidget {
  /// Creates a compact validation evidence view.
  const SettingsAgentValidationEvidenceView({super.key, required this.result});

  /// Result whose captured evidence should be displayed.
  final AgentValidationRunResult result;

  /// Builds the run evidence needed to diagnose one agent validation.
  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    if (result.response.text.trim().isNotEmpty) {
      lines.add(
        _SettingsAgentEvidenceLine(
          label: 'Response',
          value: result.response.text,
        ),
      );
    }
    if (result.response.toolCalls.isNotEmpty) {
      lines.add(
        _SettingsAgentEvidenceLine(
          label: 'Tool calls',
          value: result.response.toolCalls
              .map(_agentToolCallEvidence)
              .join('\n'),
        ),
      );
    }
    if (result.assertions.isNotEmpty) {
      lines.add(
        _SettingsAgentEvidenceLine(
          label: 'Assertions',
          value: result.assertions.map(_agentAssertionEvidence).join('\n'),
        ),
      );
    }
    if (result.diagnostics.isNotEmpty) {
      lines.add(
        _SettingsAgentEvidenceLine(
          label: 'Diagnostics',
          value: result.diagnostics.map(_agentDiagnosticEvidence).join('\n'),
        ),
      );
    }
    if (result.input.isNotEmpty) {
      lines.add(
        _SettingsAgentEvidenceLine(
          label: 'Input',
          value: _agentJsonEvidence(result.input),
        ),
      );
    }
    if (result.fixtures.isNotEmpty) {
      lines.add(
        _SettingsAgentEvidenceLine(
          label: 'Fixtures',
          value: _agentJsonEvidence(result.fixtures),
        ),
      );
    }
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
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

/// Builds a ready-to-edit mocked validation case.
AgentValidationConfig _defaultAgentValidation(
  List<AgentValidationConfig> existing,
) {
  return AgentValidationConfig(
    id: _uniqueAgentValidationId(existing),
    label: 'New validation',
    description: '',
    mode: 'mocked',
    prompt: 'Ask the agent to perform the expected behavior.',
    input: const <String, dynamic>{},
    fixtures: const <String, dynamic>{},
    mocks: const <String, dynamic>{
      'agent.response': <String, dynamic>{'text': 'Expected response.'},
    },
    expected: const <String, dynamic>{},
    assertions: const <AgentValidationAssertionConfig>[
      AgentValidationAssertionConfig(
        type: 'response-contains',
        path: '',
        contains: 'Expected',
        equals: null,
      ),
    ],
  );
}

/// Returns whether a validation should run through the live runtime.
bool _agentValidationIsLive(AgentValidationConfig validation) {
  return validation.mode.trim().toLowerCase() == 'live';
}

/// Chooses the safest validation lane for an agent validation run.
String _agentValidationModeForRun(
  List<AgentValidationConfig> validations,
  String validationId,
) {
  final selectedId = validationId.trim();
  if (selectedId.isEmpty) {
    return 'mocked';
  }
  for (final validation in validations) {
    if (validation.id.trim() != selectedId) {
      continue;
    }
    return _agentValidationIsLive(validation) ? 'live' : 'mocked';
  }
  return '';
}

/// Returns a unique validation id hidden behind the user-facing label.
String _uniqueAgentValidationId(List<AgentValidationConfig> existing) {
  final used = <String>{
    for (final validation in existing) validation.id.trim(),
  };
  const base = 'validation';
  if (!used.contains(base)) {
    return base;
  }
  var index = 2;
  while (used.contains('${base}_$index')) {
    index++;
  }
  return '${base}_$index';
}

/// Returns the first editable response-contains assertion value.
String _agentValidationContainsAssertion(AgentValidationConfig validation) {
  for (final assertion in validation.assertions) {
    if (assertion.type == 'response-contains') {
      return assertion.contains;
    }
  }
  return '';
}

/// Replaces or creates the response-contains assertion edited in the UI.
List<AgentValidationAssertionConfig> _agentValidationAssertionsWithContains(
  List<AgentValidationAssertionConfig> assertions,
  String value,
) {
  var replaced = false;
  final next = <AgentValidationAssertionConfig>[
    for (final assertion in assertions)
      if (assertion.type == 'response-contains')
        (() {
          replaced = true;
          return assertion.copyWith(contains: value);
        })()
      else
        assertion,
  ];
  if (!replaced) {
    next.add(
      AgentValidationAssertionConfig(
        type: 'response-contains',
        path: '',
        contains: value,
        equals: null,
      ),
    );
  }
  return next;
}

/// Returns the mocked agent response text edited in the UI.
String _agentValidationMockResponseText(AgentValidationConfig validation) {
  return _agentMapValue(
        validation.mocks['agent.response'],
      )['text']?.toString() ??
      '';
}

/// Returns the expected tool call assertion edited in the UI.
String _agentValidationToolCallAssertion(AgentValidationConfig validation) {
  for (final assertion in validation.assertions) {
    if (assertion.type == 'tool-call') {
      return assertion.equals?.toString() ?? '';
    }
  }
  return '';
}

/// Returns the first configured tool-call argument map edited in the UI.
Map<String, String> _agentValidationToolCallArguments(
  AgentValidationConfig validation,
) {
  final response = _agentMapValue(validation.mocks['agent.response']);
  final calls = response['tool_calls'];
  if (calls is! List || calls.isEmpty) {
    return _agentValidationToolCallArgumentAssertions(validation.assertions);
  }
  final first = calls.first;
  if (first is! Map) {
    return _agentValidationToolCallArgumentAssertions(validation.assertions);
  }
  final arguments = _agentMapValue(first['arguments']);
  final mockedArguments = <String, String>{
    for (final entry in arguments.entries)
      entry.key: entry.value == null ? '' : entry.value.toString(),
  };
  if (mockedArguments.isNotEmpty) {
    return mockedArguments;
  }
  return _agentValidationToolCallArgumentAssertions(validation.assertions);
}

/// Returns tool-call argument expectations declared as json-path assertions.
Map<String, String> _agentValidationToolCallArgumentAssertions(
  List<AgentValidationAssertionConfig> assertions,
) {
  final arguments = <String, String>{};
  for (final assertion in assertions) {
    final path = assertion.path.trim();
    const prefix = 'response.tool_calls.0.arguments.';
    if (assertion.type != 'json-path' || !path.startsWith(prefix)) {
      continue;
    }
    final name = path.substring(prefix.length).trim();
    if (name.isEmpty) {
      continue;
    }
    arguments[name] = assertion.equals == null
        ? ''
        : assertion.equals.toString();
  }
  return arguments;
}

/// Adds a default parameter to the expected agent tool call.
AgentValidationConfig _agentValidationWithAddedToolCallArgument(
  AgentValidationConfig validation,
) {
  final existing = _agentValidationToolCallArguments(validation);
  final name = _uniqueAgentToolArgumentName(existing.keys.toSet());
  return _agentValidationWithToolCallArgument(
    validation,
    oldName: '',
    name: name,
    value: 'value',
  );
}

/// Replaces or creates one expected tool-call argument and its assertion.
AgentValidationConfig _agentValidationWithToolCallArgument(
  AgentValidationConfig validation, {
  required String oldName,
  required String name,
  required String value,
}) {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) {
    return validation;
  }
  final trimmedOldName = oldName.trim();
  final nextArguments = Map<String, String>.from(
    _agentValidationToolCallArguments(validation),
  );
  if (trimmedOldName.isNotEmpty && trimmedOldName != trimmedName) {
    nextArguments.remove(trimmedOldName);
  }
  nextArguments[trimmedName] = value.trim();
  return validation.copyWith(
    mocks: _agentValidationIsLive(validation)
        ? validation.mocks
        : _agentValidationMocksWithToolCallArguments(
            validation.mocks,
            nextArguments,
          ),
    assertions: _agentValidationAssertionsWithToolCallArgument(
      validation.assertions,
      oldName: trimmedOldName,
      name: trimmedName,
      value: value.trim(),
    ),
  );
}

/// Removes one expected tool-call argument and matching assertion.
AgentValidationConfig _agentValidationWithoutToolCallArgument(
  AgentValidationConfig validation,
  String name,
) {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) {
    return validation;
  }
  final nextArguments = Map<String, String>.from(
    _agentValidationToolCallArguments(validation),
  )..remove(trimmedName);
  return validation.copyWith(
    mocks: _agentValidationIsLive(validation)
        ? validation.mocks
        : _agentValidationMocksWithToolCallArguments(
            validation.mocks,
            nextArguments,
          ),
    assertions: validation.assertions
        .where(
          (assertion) => assertion.path != _agentToolArgumentPath(trimmedName),
        )
        .toList(),
  );
}

/// Replaces the mocked agent response text without exposing raw YAML.
Map<String, dynamic> _agentValidationMocksWithResponseText(
  Map<String, dynamic> mocks,
  String value,
) {
  final next = Map<String, dynamic>.from(mocks);
  final response = _agentMapValue(next['agent.response']);
  response['text'] = value;
  next['agent.response'] = response;
  return next;
}

/// Replaces the first mocked tool-call argument map.
Map<String, dynamic> _agentValidationMocksWithToolCallArguments(
  Map<String, dynamic> mocks,
  Map<String, String> arguments,
) {
  final next = Map<String, dynamic>.from(mocks);
  final response = _agentMapValue(next['agent.response']);
  final calls = _agentToolCallList(response);
  final first = Map<String, dynamic>.from(calls.first);
  first['arguments'] = <String, dynamic>{
    for (final entry in arguments.entries) entry.key: entry.value,
  };
  calls[0] = first;
  response['tool_calls'] = calls;
  next['agent.response'] = response;
  return next;
}

/// Replaces or clears the mocked tool call evidence.
Map<String, dynamic> _agentValidationMocksWithToolCall(
  Map<String, dynamic> mocks,
  String value,
) {
  final next = Map<String, dynamic>.from(mocks);
  final response = _agentMapValue(next['agent.response']);
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    response.remove('tool_calls');
  } else {
    final existing = _agentToolCallList(response).first;
    final arguments = _agentMapValue(existing['arguments']);
    response['tool_calls'] = <Map<String, dynamic>>[
      <String, dynamic>{'id': trimmed, 'name': trimmed, 'arguments': arguments},
    ];
  }
  next['agent.response'] = response;
  return next;
}

/// Returns a mutable mocked tool-call list with one entry.
List<Map<String, dynamic>> _agentToolCallList(Map<String, dynamic> response) {
  final calls = <Map<String, dynamic>>[];
  final value = response['tool_calls'];
  if (value is List) {
    for (final item in value) {
      if (item is Map<String, dynamic>) {
        calls.add(Map<String, dynamic>.from(item));
      } else if (item is Map) {
        calls.add(<String, dynamic>{
          for (final entry in item.entries) entry.key.toString(): entry.value,
        });
      }
    }
  }
  if (calls.isEmpty) {
    calls.add(<String, dynamic>{
      'id': '',
      'name': '',
      'arguments': <String, dynamic>{},
    });
  }
  calls.first['arguments'] = _agentMapValue(calls.first['arguments']);
  return calls;
}

/// Replaces or creates the tool-call assertion edited in the UI.
List<AgentValidationAssertionConfig> _agentValidationAssertionsWithToolCall(
  List<AgentValidationAssertionConfig> assertions,
  String value,
) {
  final trimmed = value.trim();
  var replaced = false;
  final next = <AgentValidationAssertionConfig>[];
  for (final assertion in assertions) {
    if (assertion.type != 'tool-call') {
      next.add(assertion);
      continue;
    }
    replaced = true;
    if (trimmed.isNotEmpty) {
      next.add(assertion.copyWith(equals: trimmed));
    }
  }
  if (!replaced && trimmed.isNotEmpty) {
    next.add(
      AgentValidationAssertionConfig(
        type: 'tool-call',
        path: '',
        contains: '',
        equals: trimmed,
      ),
    );
  }
  return next;
}

/// Replaces or creates the json-path assertion for one tool-call parameter.
List<AgentValidationAssertionConfig>
_agentValidationAssertionsWithToolCallArgument(
  List<AgentValidationAssertionConfig> assertions, {
  required String oldName,
  required String name,
  required String value,
}) {
  final oldPath = oldName.isEmpty ? '' : _agentToolArgumentPath(oldName);
  final nextPath = _agentToolArgumentPath(name);
  final next = <AgentValidationAssertionConfig>[
    for (final assertion in assertions)
      if ((oldPath.isEmpty || assertion.path != oldPath) &&
          assertion.path != nextPath)
        assertion,
  ];
  next.add(
    AgentValidationAssertionConfig(
      type: 'json-path',
      path: nextPath,
      contains: '',
      equals: value,
    ),
  );
  return next;
}

/// Returns the assertion path for one mocked tool-call parameter.
String _agentToolArgumentPath(String name) {
  return 'response.tool_calls.0.arguments.${name.trim()}';
}

/// Returns a unique editable parameter name.
String _uniqueAgentToolArgumentName(Set<String> existing) {
  const base = 'parameter';
  if (!existing.contains(base)) {
    return base;
  }
  var index = 2;
  while (existing.contains('${base}_$index')) {
    index++;
  }
  return '${base}_$index';
}

/// Returns a string-keyed map for generic YAML values.
Map<String, dynamic> _agentMapValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return <String, dynamic>{};
}

class _SettingsAgentEvidenceLine extends StatelessWidget {
  const _SettingsAgentEvidenceLine({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds one selectable evidence row.
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

/// Returns the result entry that corresponds to one selected agent config.
AgentValidationFileResult _agentValidationFileForEntry(
  AgentValidationResult result,
  ConfigFileEntry entry,
) {
  for (final file in result.agents) {
    if (file.path == entry.path) {
      return file;
    }
  }
  if (result.agents.isNotEmpty) {
    return result.agents.first;
  }
  return AgentValidationFileResult(
    path: entry.path,
    name: entry.label,
    passed: false,
    unsupported: false,
    error: 'No agent validation result returned',
    missingAssertions: const <String>[],
    missingToolCalls: const <String>[],
    unknownToolCalls: const <String>[],
    invalidToolArguments: const <String>[],
    result: const AgentValidationSuiteResult(
      total: 0,
      passed: 0,
      failed: 0,
      unsupported: 0,
      toolCallReferences: <String>[],
      results: <AgentValidationRunResult>[],
    ),
  );
}

/// Returns a compact display label for one agent validation.
String _agentValidationLabel(AgentValidationConfig validation) {
  if (validation.label.trim().isNotEmpty) {
    return validation.label;
  }
  return validation.id;
}

/// Returns whether one file-level agent result has gate issues to display.
bool _agentValidationFileHasIssues(AgentValidationFileResult result) {
  return result.error.trim().isNotEmpty ||
      result.missingAssertions.isNotEmpty ||
      result.missingToolCalls.isNotEmpty ||
      result.unknownToolCalls.isNotEmpty ||
      result.invalidToolArguments.isNotEmpty;
}

/// Returns display text for one failed agent validation assertion.
String _agentAssertionFailureText(AgentValidationAssertionResult assertion) {
  if (assertion.message.isNotEmpty) {
    return assertion.message;
  }
  final path = assertion.path.isEmpty ? assertion.type : assertion.path;
  if (assertion.expected != null || assertion.actual != null) {
    return '$path expected ${assertion.expected} but got ${assertion.actual}';
  }
  return '$path failed';
}

/// Formats one tool call for validation evidence review.
String _agentToolCallEvidence(AgentValidationToolCallResult call) {
  final name = call.name.isNotEmpty ? call.name : call.id;
  if (call.arguments.isEmpty) {
    return name;
  }
  return '$name ${_agentJsonEvidence(call.arguments)}';
}

/// Formats one assertion result for validation evidence review.
String _agentAssertionEvidence(AgentValidationAssertionResult assertion) {
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
String _agentDiagnosticEvidence(AgentValidationDiagnostic diagnostic) {
  final severity = diagnostic.severity.isEmpty
      ? 'diagnostic'
      : diagnostic.severity;
  return '$severity ${diagnostic.message}'.trim();
}

/// Encodes structured validation evidence in a stable display form.
String _agentJsonEvidence(Object? value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return '$value';
  }
}

/// Merges selected agent validation reruns into the previous suite result.
AgentValidationSuiteResult _mergedAgentValidationResults(
  AgentValidationSuiteResult? previous,
  AgentValidationSuiteResult next,
) => mergeAgentValidationSuiteResults(previous, next);
