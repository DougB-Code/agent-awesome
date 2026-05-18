/// Runtime server settings widgets.
part of 'settings_panel.dart';

class _SettingsServerContent extends StatefulWidget {
  const _SettingsServerContent({
    required this.profile,
    required this.controller,
    required this.title,
    required this.servers,
    this.selectedServerId,
    this.query = '',
  });

  final RuntimeProfile profile;
  final AgentAwesomeAppController controller;
  final String title;
  final List<McpServerRuntime> servers;
  final String? selectedServerId;
  final String query;

  /// Creates state for MCP server settings selection.
  @override
  State<_SettingsServerContent> createState() => _SettingsServerContentState();
}

class _SettingsServerContentState extends State<_SettingsServerContent> {
  /// Builds MCP server binding details for one server kind.
  @override
  Widget build(BuildContext context) {
    final server = _selectedServer();
    if (server == null) {
      return const Center(
        child: PanelEmptyBlock(label: 'No servers configured'),
      );
    }
    final query = widget.query;
    if (!SettingsQuery.matches(query, <String>[
      server.id,
      server.label,
      server.kind,
      server.endpoint,
      server.healthUrl,
      server.dbPath,
      server.dataDir,
      server.workingDirectory,
      server.packagePath,
      server.arguments.join(' '),
      widget.profile.agentMemory.actor,
      widget.profile.agentMemory.readDomains.join(' '),
      widget.profile.agentMemory.writeDomains.join(' '),
    ])) {
      return PanelEmptyState(query: query);
    }
    return FormPanel(
      children: <Widget>[
        _SettingsMemoryAccessReviewTile(profile: widget.profile),
        _SettingsServerTile(
          profile: widget.profile,
          controller: widget.controller,
          server: server,
        ),
        _SettingsAgentMemoryTile(
          profile: widget.profile,
          controller: widget.controller,
        ),
      ],
    );
  }

  /// Returns the selected MCP server for content rendering.
  McpServerRuntime? _selectedServer() {
    if (widget.servers.isEmpty) {
      return null;
    }
    final selectedServerId = widget.selectedServerId;
    if (selectedServerId != null) {
      for (final server in widget.servers) {
        if (server.id == selectedServerId) {
          return server;
        }
      }
    }
    for (final server in widget.servers) {
      if (server.id == widget.profile.agentMemory.defaultWriteDomain) {
        return server;
      }
    }
    return widget.servers.first;
  }
}

class _SettingsServerTile extends StatefulWidget {
  const _SettingsServerTile({
    required this.profile,
    required this.controller,
    required this.server,
  });

  final RuntimeProfile profile;
  final AgentAwesomeAppController controller;
  final McpServerRuntime server;

  @override
  State<_SettingsServerTile> createState() => _SettingsServerTileState();
}

class _SettingsServerTileState extends State<_SettingsServerTile> {
  late final TextEditingController _id = TextEditingController(
    text: widget.server.id,
  );
  late final TextEditingController _label = TextEditingController(
    text: widget.server.label,
  );
  late final TextEditingController _endpoint = TextEditingController(
    text: widget.server.endpoint,
  );
  late final TextEditingController _healthUrl = TextEditingController(
    text: widget.server.healthUrl,
  );
  late final TextEditingController _workingDirectory = TextEditingController(
    text: widget.server.workingDirectory,
  );
  late final TextEditingController _packagePath = TextEditingController(
    text: widget.server.packagePath,
  );
  late final TextEditingController _dbPath = TextEditingController(
    text: widget.server.dbPath,
  );
  late final TextEditingController _dataDir = TextEditingController(
    text: widget.server.dataDir,
  );
  late final TextEditingController _arguments = TextEditingController(
    text: widget.server.arguments.join('\n'),
  );
  late bool _enabled = widget.server.enabled;
  late bool _autoStart = widget.server.autoStart;

  /// Cleans up MCP server form controllers.
  @override
  void dispose() {
    _id.dispose();
    _label.dispose();
    _endpoint.dispose();
    _healthUrl.dispose();
    _workingDirectory.dispose();
    _packagePath.dispose();
    _dbPath.dispose();
    _dataDir.dispose();
    _arguments.dispose();
    super.dispose();
  }

  /// Keeps field controllers aligned when a different domain is selected.
  @override
  void didUpdateWidget(covariant _SettingsServerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.server.id == widget.server.id &&
        oldWidget.server == widget.server) {
      return;
    }
    _id.text = widget.server.id;
    _label.text = widget.server.label;
    _endpoint.text = widget.server.endpoint;
    _healthUrl.text = widget.server.healthUrl;
    _workingDirectory.text = widget.server.workingDirectory;
    _packagePath.text = widget.server.packagePath;
    _dbPath.text = widget.server.dbPath;
    _dataDir.text = widget.server.dataDir;
    _arguments.text = widget.server.arguments.join('\n');
    _enabled = widget.server.enabled;
    _autoStart = widget.server.autoStart;
  }

  /// Builds one memory domain tile from the active profile.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: widget.server.label.isEmpty
          ? 'Memory domain'
          : widget.server.label,
      children: <Widget>[
        SettingsFieldRow(
          leading: Switch(
            value: _enabled,
            onChanged: (value) {
              setState(() => _enabled = value);
              unawaited(_save());
            },
          ),
          trailing: PanelBadge(label: _autoStart ? 'Managed' : 'External'),
          child: _SettingsAutoSaveTextField(
            label: 'Label',
            controller: _label,
            initialSavedValue: widget.server.label,
            onSave: (_) => _save(),
          ),
        ),
        _SettingsAutoSaveTextField(
          label: 'Domain ID',
          controller: _id,
          initialSavedValue: widget.server.id,
          onSave: (_) => _save(),
        ),
        SettingsFieldGrid(
          children: <Widget>[
            _SettingsAutoSaveTextField(
              label: 'Endpoint',
              controller: _endpoint,
              initialSavedValue: widget.server.endpoint,
              onSave: (_) => _save(),
            ),
            _SettingsAutoSaveTextField(
              label: 'Health URL',
              controller: _healthUrl,
              initialSavedValue: widget.server.healthUrl,
              onSave: (_) => _save(),
            ),
            _SettingsAutoSaveTextField(
              label: 'Database path',
              controller: _dbPath,
              initialSavedValue: widget.server.dbPath,
              onSave: (_) => _save(),
            ),
            _SettingsAutoSaveTextField(
              label: 'Data directory',
              controller: _dataDir,
              initialSavedValue: widget.server.dataDir,
              onSave: (_) => _save(),
            ),
            _SettingsAutoSaveTextField(
              label: 'Working directory',
              controller: _workingDirectory,
              initialSavedValue: widget.server.workingDirectory,
              onSave: (_) => _save(),
            ),
            _SettingsAutoSaveTextField(
              label: 'Package path',
              controller: _packagePath,
              initialSavedValue: widget.server.packagePath,
              onSave: (_) => _save(),
            ),
          ],
        ),
        _SettingsAutoSaveTextField(
          label: 'Arguments, one per line',
          controller: _arguments,
          initialSavedValue: widget.server.arguments.join('\n'),
          onSave: (_) => _save(),
          minLines: 3,
          maxLines: 8,
        ),
        SettingsToggleField(
          title: 'Auto-start server',
          value: _autoStart,
          onChanged: (value) {
            setState(() => _autoStart = value);
            unawaited(_save());
          },
        ),
        _SettingsServerOperations(
          controller: widget.controller,
          server: widget.server,
        ),
      ],
    );
  }

  Future<void> _save() async {
    final replacement = widget.server.copyWith(
      id: _id.text.trim(),
      label: _label.text.trim(),
      endpoint: _endpoint.text.trim(),
      healthUrl: _healthUrl.text.trim(),
      workingDirectory: _workingDirectory.text.trim(),
      packagePath: _packagePath.text.trim(),
      dbPath: _dbPath.text.trim(),
      dataDir: _dataDir.text.trim(),
      arguments: _arguments.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(),
      autoStart: _autoStart,
      enabled: _enabled,
    );
    try {
      await widget.controller.saveMemoryDomainRuntime(
        originalId: widget.server.id,
        server: replacement,
      );
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }
}

/// _SettingsMemoryAccessReviewTile summarizes effective memory policy grants.
class _SettingsMemoryAccessReviewTile extends StatelessWidget {
  const _SettingsMemoryAccessReviewTile({required this.profile});

  final RuntimeProfile profile;

  /// Builds an effective access summary and current guardrail warnings.
  @override
  Widget build(BuildContext context) {
    final warnings = _memoryProfileWarnings(profile);
    final memory = profile.agentMemory;
    return FormSectionCard(
      title: 'Effective access',
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            PanelBadge(label: 'Actor ${memory.actor}'),
            PanelBadge(
              label: 'Reads ${_domainLabels(profile, memory.readDomains)}',
            ),
            PanelBadge(
              label: 'Writes ${_domainLabels(profile, memory.writeDomains)}',
            ),
            PanelBadge(
              label:
                  'Default ${_domainLabels(profile, <String>[memory.defaultWriteDomain])}',
            ),
          ],
        ),
        if (memory.allowedFlows.isNotEmpty) ...<Widget>[
          const SizedBox(height: SettingsFormMetrics.compactGap),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final flow in memory.allowedFlows)
                PanelBadge(
                  label:
                      '${_domainLabels(profile, <String>[flow.fromDomain])} -> ${_domainLabels(profile, <String>[flow.toDomain])}',
                ),
            ],
          ),
        ],
        if (warnings.isNotEmpty) ...<Widget>[
          const SizedBox(height: SettingsFormMetrics.compactGap),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                warning,
                style: TextStyle(color: Colors.orange.shade800),
              ),
            ),
        ],
      ],
    );
  }
}

/// _SettingsServerOperations exposes health and restart controls for a domain.
class _SettingsServerOperations extends StatelessWidget {
  const _SettingsServerOperations({
    required this.controller,
    required this.server,
  });

  final AgentAwesomeAppController controller;
  final McpServerRuntime server;

  /// Builds status and local lifecycle actions for one memory domain.
  @override
  Widget build(BuildContext context) {
    final status = _statusForServer(controller.localProcessStatuses, server);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: SettingsFormMetrics.compactGap),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            PanelBadge(label: status?.state.name ?? 'unknown'),
            if (status != null && status.message.trim().isNotEmpty)
              PanelBadge(label: status.message),
            OutlinedButton.icon(
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text('Check'),
              onPressed: () =>
                  unawaited(controller.refreshRuntimeServiceStatuses()),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: const Text('Restart'),
              onPressed: () =>
                  unawaited(controller.restartMemoryRuntimeServices()),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsAgentMemoryTile extends StatefulWidget {
  const _SettingsAgentMemoryTile({
    required this.profile,
    required this.controller,
  });

  final RuntimeProfile profile;
  final AgentAwesomeAppController controller;

  @override
  State<_SettingsAgentMemoryTile> createState() =>
      _SettingsAgentMemoryTileState();
}

class _SettingsAgentMemoryTileState extends State<_SettingsAgentMemoryTile> {
  late final TextEditingController _actor = TextEditingController(
    text: widget.profile.agentMemory.actor,
  );
  late Set<String> _readDomains = _selectedDomainSet(
    widget.profile.agentMemory.readDomains,
  );
  late Set<String> _writeDomains = _selectedDomainSet(
    widget.profile.agentMemory.writeDomains,
  );
  late String _defaultWriteDomain =
      widget.profile.agentMemory.defaultWriteDomain;
  late Set<String> _allowedSensitivities = _selectedSensitivitySet(
    widget.profile.agentMemory.allowedSensitivities,
  );
  late Set<String> _allowedFlowKeys = _selectedFlowKeys(
    widget.profile.agentMemory.allowedFlows,
  );

  /// Cleans up agent memory form controllers.
  @override
  void dispose() {
    _actor.dispose();
    super.dispose();
  }

  /// Keeps structured selections aligned when profile access grants change.
  @override
  void didUpdateWidget(covariant _SettingsAgentMemoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile == widget.profile) {
      return;
    }
    _syncFromProfile();
  }

  /// Builds the agent memory access grant editor.
  @override
  Widget build(BuildContext context) {
    final domains = _enabledMemoryDomains(widget.profile);
    final writeDomains = _orderedDomainSelection(widget.profile, _writeDomains);
    final defaultWrite = writeDomains.contains(_defaultWriteDomain)
        ? _defaultWriteDomain
        : (writeDomains.isEmpty ? null : writeDomains.first);
    return FormSectionCard(
      title: 'Agent access',
      children: <Widget>[
        _SettingsAutoSaveTextField(
          label: 'Actor',
          controller: _actor,
          initialSavedValue: widget.profile.agentMemory.actor,
          onSave: (_) => _save(),
        ),
        SettingsFieldGrid(
          children: <Widget>[
            _SettingsDomainGrantPicker(
              title: 'Readable domains',
              domains: domains,
              selected: _readDomains,
              onChanged: _setReadDomains,
            ),
            _SettingsDomainGrantPicker(
              title: 'Writable domains',
              domains: domains,
              selected: _writeDomains,
              onChanged: _setWriteDomains,
            ),
            _SettingsSensitivityPicker(
              selected: _allowedSensitivities,
              options: _sensitivityOptions(widget.profile),
              onChanged: _setAllowedSensitivities,
            ),
            _SettingsFlowPicker(
              profile: widget.profile,
              readDomains: _readDomains,
              writeDomains: _writeDomains,
              selectedKeys: _allowedFlowKeys,
              onChanged: _setAllowedFlowKeys,
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          key: ValueKey<String?>(defaultWrite),
          initialValue: defaultWrite,
          isExpanded: true,
          items: <DropdownMenuItem<String>>[
            for (final domain in domains.where(
              (domain) => _writeDomains.contains(domain.id),
            ))
              DropdownMenuItem<String>(
                value: domain.id,
                child: Text(
                  domain.label.trim().isEmpty ? domain.id : domain.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() => _defaultWriteDomain = value);
            unawaited(_save());
          },
          decoration: SettingsInputDecoration.field(
            context,
            label: 'Default write domain',
          ),
        ),
      ],
    );
  }

  /// Persists the selected agent memory grants through the controller.
  Future<void> _save() async {
    final readDomains = _orderedDomainSelection(widget.profile, _readDomains);
    final writeDomains = _orderedDomainSelection(widget.profile, _writeDomains);
    if (readDomains.isEmpty || writeDomains.isEmpty) {
      return;
    }
    final nextDefault = writeDomains.contains(_defaultWriteDomain)
        ? _defaultWriteDomain
        : writeDomains.first;
    final sensitivities = _orderedSensitivitySelection(
      _allowedSensitivities,
      _sensitivityOptions(widget.profile),
    );
    final memory = AgentMemoryRuntime(
      actor: _actor.text.trim().isEmpty
          ? widget.profile.agentMemory.actor
          : _actor.text.trim(),
      readDomains: readDomains,
      writeDomains: writeDomains,
      defaultWriteDomain: nextDefault,
      allowedSensitivities: sensitivities.isEmpty
          ? <String>[_sensitivityOptions(widget.profile).first]
          : sensitivities,
      allowedFlows: _flowsFromKeys(_validFlowKeys(_allowedFlowKeys)),
    );
    try {
      await widget.controller.saveAgentMemoryRuntime(memory);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }

  /// Resets local selection state from the current runtime profile.
  void _syncFromProfile() {
    final memory = widget.profile.agentMemory;
    _actor.text = memory.actor;
    _readDomains = _selectedDomainSet(memory.readDomains);
    _writeDomains = _selectedDomainSet(memory.writeDomains);
    _defaultWriteDomain = memory.defaultWriteDomain;
    _allowedSensitivities = _selectedSensitivitySet(
      memory.allowedSensitivities,
    );
    _allowedFlowKeys = _selectedFlowKeys(memory.allowedFlows);
  }

  /// Updates readable domain grants and removes invalid flow selections.
  void _setReadDomains(Set<String> ids) {
    setState(() {
      _readDomains = _atLeastOneDomain(ids);
      _allowedFlowKeys = _validFlowKeys(_allowedFlowKeys);
    });
    unawaited(_save());
  }

  /// Updates writable domain grants and keeps the default write domain valid.
  void _setWriteDomains(Set<String> ids) {
    setState(() {
      _writeDomains = _atLeastOneDomain(ids);
      final writeDomains = _orderedDomainSelection(
        widget.profile,
        _writeDomains,
      );
      if (!writeDomains.contains(_defaultWriteDomain) &&
          writeDomains.isNotEmpty) {
        _defaultWriteDomain = writeDomains.first;
      }
      _allowedFlowKeys = _validFlowKeys(_allowedFlowKeys);
    });
    unawaited(_save());
  }

  /// Updates sensitivity grants while preserving at least one allowed value.
  void _setAllowedSensitivities(Set<String> ids) {
    setState(() {
      final options = _sensitivityOptions(widget.profile).toSet();
      _allowedSensitivities = ids.where(options.contains).toSet();
      if (_allowedSensitivities.isEmpty && options.isNotEmpty) {
        _allowedSensitivities.add(options.first);
      }
    });
    unawaited(_save());
  }

  /// Updates explicit cross-domain flow grants from checkbox keys.
  void _setAllowedFlowKeys(Set<String> keys) {
    setState(() => _allowedFlowKeys = _validFlowKeys(keys));
    unawaited(_save());
  }

  /// Converts configured domain ids into a valid editor selection set.
  Set<String> _selectedDomainSet(Iterable<String> ids) {
    return _atLeastOneDomain(ids.toSet());
  }

  /// Converts configured sensitivity values into a valid editor selection set.
  Set<String> _selectedSensitivitySet(Iterable<String> values) {
    final options = _sensitivityOptions(widget.profile);
    final selected = values.where(options.toSet().contains).toSet();
    if (selected.isEmpty && options.isNotEmpty) {
      selected.add(options.first);
    }
    return selected;
  }

  /// Converts configured flow rules into checkbox selection keys.
  Set<String> _selectedFlowKeys(List<MemoryDomainFlow> flows) {
    return _validFlowKeys(
      flows.map((flow) => _flowKey(flow.fromDomain, flow.toDomain)).toSet(),
    );
  }

  /// Keeps a domain selection within enabled domains and non-empty.
  Set<String> _atLeastOneDomain(Set<String> ids) {
    final domains = _enabledMemoryDomains(widget.profile);
    final available = domains.map((domain) => domain.id).toSet();
    final selected = ids.where(available.contains).toSet();
    if (selected.isEmpty && domains.isNotEmpty) {
      selected.add(domains.first.id);
    }
    return selected;
  }

  /// Filters flow keys to currently readable and writable domain pairs.
  Set<String> _validFlowKeys(Set<String> keys) {
    final valid = <String>{
      for (final from in _readDomains)
        for (final to in _writeDomains)
          if (from != to) _flowKey(from, to),
    };
    return keys.where(valid.contains).toSet();
  }

  /// Converts selected checkbox keys back into ordered flow rules.
  List<MemoryDomainFlow> _flowsFromKeys(Set<String> keys) {
    final orderedRead = _orderedDomainSelection(widget.profile, _readDomains);
    final orderedWrite = _orderedDomainSelection(widget.profile, _writeDomains);
    return <MemoryDomainFlow>[
      for (final from in orderedRead)
        for (final to in orderedWrite)
          if (keys.contains(_flowKey(from, to)))
            MemoryDomainFlow(fromDomain: from, toDomain: to),
    ];
  }
}

/// _SettingsDomainGrantPicker renders domain grant checkboxes.
class _SettingsDomainGrantPicker extends StatelessWidget {
  const _SettingsDomainGrantPicker({
    required this.title,
    required this.domains,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<McpServerRuntime> domains;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  /// Builds a checkbox group for domain read or write grants.
  @override
  Widget build(BuildContext context) {
    return _SettingsSelectionBox(
      title: title,
      children: <Widget>[
        if (domains.isEmpty)
          const Text('No enabled memory domains.')
        else
          for (final domain in domains)
            _SettingsCheckboxRow(
              title: _domainLabel(domain),
              subtitle: domain.id,
              value: selected.contains(domain.id),
              onChanged: (value) {
                final next = <String>{...selected};
                if (value) {
                  next.add(domain.id);
                } else {
                  next.remove(domain.id);
                }
                onChanged(next);
              },
            ),
      ],
    );
  }
}

/// _SettingsSensitivityPicker renders sensitivity grant checkboxes.
class _SettingsSensitivityPicker extends StatelessWidget {
  const _SettingsSensitivityPicker({
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final Set<String> selected;
  final List<String> options;
  final ValueChanged<Set<String>> onChanged;

  /// Builds a checkbox group for memory sensitivity grants.
  @override
  Widget build(BuildContext context) {
    return _SettingsSelectionBox(
      title: 'Allowed sensitivities',
      children: <Widget>[
        for (final option in options)
          _SettingsCheckboxRow(
            title: option,
            value: selected.contains(option),
            onChanged: (value) {
              final next = <String>{...selected};
              if (value) {
                next.add(option);
              } else {
                next.remove(option);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

/// _SettingsFlowPicker renders explicit source-to-target flow grants.
class _SettingsFlowPicker extends StatelessWidget {
  const _SettingsFlowPicker({
    required this.profile,
    required this.readDomains,
    required this.writeDomains,
    required this.selectedKeys,
    required this.onChanged,
  });

  final RuntimeProfile profile;
  final Set<String> readDomains;
  final Set<String> writeDomains;
  final Set<String> selectedKeys;
  final ValueChanged<Set<String>> onChanged;

  /// Builds an explicit cross-domain flow grant picker.
  @override
  Widget build(BuildContext context) {
    final options = <({String key, String label})>[
      for (final from in _orderedDomainSelection(profile, readDomains))
        for (final to in _orderedDomainSelection(profile, writeDomains))
          if (from != to)
            (
              key: _flowKey(from, to),
              label:
                  '${_domainLabels(profile, <String>[from])} -> ${_domainLabels(profile, <String>[to])}',
            ),
    ];
    return _SettingsSelectionBox(
      title: 'Allowed flows',
      children: <Widget>[
        if (options.isEmpty)
          const Text('No cross-domain write flows available.')
        else
          for (final option in options)
            _SettingsCheckboxRow(
              title: option.label,
              value: selectedKeys.contains(option.key),
              onChanged: (value) {
                final next = <String>{...selectedKeys};
                if (value) {
                  next.add(option.key);
                } else {
                  next.remove(option.key);
                }
                onChanged(next);
              },
            ),
      ],
    );
  }
}

/// _SettingsSelectionBox frames one group of settings checkboxes.
class _SettingsSelectionBox extends StatelessWidget {
  const _SettingsSelectionBox({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  /// Builds a compact labeled selection surface for settings controls.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: SettingsFormMetrics.compactGap),
          ...children,
        ],
      ),
    );
  }
}

/// _SettingsCheckboxRow renders a single compact checkbox option.
class _SettingsCheckboxRow extends StatelessWidget {
  const _SettingsCheckboxRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Builds one stable checkbox option without raw policy text editing.
  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(title, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, overflow: TextOverflow.ellipsis),
      onChanged: (next) => onChanged(next ?? false),
    );
  }
}

/// Returns enabled memory domains available for profile grants.
List<McpServerRuntime> _enabledMemoryDomains(RuntimeProfile profile) {
  return profile.memoryDomains.where((domain) => domain.enabled).toList();
}

/// Returns domain ids in profile order after applying a selected-id set.
List<String> _orderedDomainSelection(
  RuntimeProfile profile,
  Set<String> selected,
) {
  return <String>[
    for (final domain in profile.memoryDomains)
      if (domain.enabled && selected.contains(domain.id)) domain.id,
  ];
}

/// Returns sensitivity values in stable display order.
List<String> _orderedSensitivitySelection(
  Set<String> selected,
  List<String> options,
) {
  return <String>[
    for (final option in options)
      if (selected.contains(option)) option,
  ];
}

/// Returns available sensitivity options without dropping custom config values.
List<String> _sensitivityOptions(RuntimeProfile profile) {
  const defaults = <String>['public', 'internal', 'private', 'restricted'];
  return <String>[
    ...defaults,
    for (final value in profile.agentMemory.allowedSensitivities)
      if (!defaults.contains(value)) value,
  ];
}

/// Returns a display label for one configured domain.
String _domainLabel(McpServerRuntime domain) {
  return domain.label.trim().isEmpty ? domain.id : domain.label;
}

/// Returns comma-separated domain labels for effective access summaries.
String _domainLabels(RuntimeProfile profile, Iterable<String> ids) {
  final byId = <String, McpServerRuntime>{
    for (final domain in profile.memoryDomains) domain.id: domain,
  };
  final labels = <String>[
    for (final id in ids)
      if (id.trim().isNotEmpty) byId[id] == null ? id : _domainLabel(byId[id]!),
  ];
  return labels.isEmpty ? 'none' : labels.join(', ');
}

/// Returns guardrail warnings for the active profile memory policy.
List<String> _memoryProfileWarnings(RuntimeProfile profile) {
  final warnings = <String>[];
  final memory = profile.agentMemory;
  final enabledIds = _enabledMemoryDomains(
    profile,
  ).map((domain) => domain.id).toSet();
  for (final domain in <String>[
    ...memory.readDomains,
    ...memory.writeDomains,
    memory.defaultWriteDomain,
  ]) {
    if (!enabledIds.contains(domain)) {
      warnings.add('Grant references disabled domain "$domain".');
    }
  }
  if (!memory.writeDomains.contains(memory.defaultWriteDomain)) {
    warnings.add('Default write domain is not in writable domains.');
  }
  if (memory.readDomains.length > 1 && memory.allowedFlows.isEmpty) {
    warnings.add(
      'Cross-domain writes are blocked unless an allowed flow exists.',
    );
  }
  return warnings;
}

/// Returns the status row that belongs to one server if it has been checked.
ServiceProcessStatus? _statusForServer(
  List<ServiceProcessStatus> statuses,
  McpServerRuntime server,
) {
  for (final status in statuses) {
    if (status.url == server.healthUrl ||
        status.url == server.endpoint ||
        status.name == server.label ||
        status.name == server.id) {
      return status;
    }
  }
  return null;
}

/// Encodes one source-to-target flow key for checkbox state.
String _flowKey(String from, String to) {
  return '$from->$to';
}
