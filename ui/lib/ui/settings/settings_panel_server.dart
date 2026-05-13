/// Runtime server settings widgets.
part of 'settings_panel.dart';

class _SettingsServerContent extends StatefulWidget {
  const _SettingsServerContent({
    required this.profile,
    required this.controller,
    required this.title,
    required this.servers,
  });

  final RuntimeProfile profile;
  final AgentAwesomeAppController controller;
  final String title;
  final List<McpServerRuntime> servers;

  /// Creates state for MCP server settings selection.
  @override
  State<_SettingsServerContent> createState() => _SettingsServerContentState();
}

class _SettingsServerContentState extends State<_SettingsServerContent> {
  String? _selectedServerId;

  /// Initializes the selected server.
  @override
  void initState() {
    super.initState();
    _selectedServerId = _initialSelectedServerId();
  }

  /// Keeps the selected server valid when profile bindings change.
  @override
  void didUpdateWidget(covariant _SettingsServerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedServerId == null ||
        !widget.servers.any((server) => server.id == _selectedServerId)) {
      _selectedServerId = _initialSelectedServerId();
    }
  }

  /// Builds MCP server binding details for one server kind.
  @override
  Widget build(BuildContext context) {
    return CollectionSwitcherPanel<McpServerRuntime>(
      title: widget.title,
      selectedId: _selectedServerId,
      emptyLabel: 'No servers configured',
      items: <CollectionPanelItem<McpServerRuntime>>[
        for (final server in widget.servers)
          CollectionPanelItem<McpServerRuntime>(
            id: server.id,
            label: server.label.isEmpty ? server.id : server.label,
            detail: server.endpoint,
            icon: Icons.hub_outlined,
            badge: server.enabled ? 'Enabled' : 'Disabled',
            value: server,
          ),
      ],
      onSelect: (id) => setState(() => _selectedServerId = id),
      onCreate: () => unawaited(_createDomain()),
      onDelete: (server) => unawaited(_deleteDomain(server)),
      builder: (server, query) {
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
      },
    );
  }

  /// Returns the initially selected MCP server id.
  String? _initialSelectedServerId() {
    if (widget.servers.isEmpty) {
      return null;
    }
    for (final server in widget.servers) {
      if (server.id == widget.profile.agentMemory.defaultWriteDomain) {
        return server.id;
      }
    }
    return widget.servers.first.id;
  }

  Future<void> _createDomain() async {
    try {
      final domain = await widget.controller.createMemoryDomainRuntime();
      if (!mounted) {
        return;
      }
      setState(() => _selectedServerId = domain.id);
    } catch (_) {}
  }

  Future<void> _deleteDomain(McpServerRuntime server) async {
    final label = server.label.trim().isEmpty ? server.id : server.label;
    final confirmed = await _confirmSettingsDelete(
      context,
      label: label,
      message:
          'Delete "$label" from this profile? Existing files at ${server.dbPath} and ${server.dataDir} are not removed automatically.',
    );
    if (!confirmed) {
      return;
    }
    try {
      await widget.controller.deleteMemoryDomainRuntime(server.id);
      if (!mounted) {
        return;
      }
      setState(() => _selectedServerId = _initialSelectedServerId());
    } catch (_) {}
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
  late final TextEditingController _readDomains = TextEditingController(
    text: widget.profile.agentMemory.readDomains.join('\n'),
  );
  late final TextEditingController _writeDomains = TextEditingController(
    text: widget.profile.agentMemory.writeDomains.join('\n'),
  );
  late final TextEditingController _sensitivities = TextEditingController(
    text: widget.profile.agentMemory.allowedSensitivities.join('\n'),
  );
  late final TextEditingController _flows = TextEditingController(
    text: _encodeFlows(widget.profile.agentMemory.allowedFlows),
  );

  /// Cleans up agent memory form controllers.
  @override
  void dispose() {
    _actor.dispose();
    _readDomains.dispose();
    _writeDomains.dispose();
    _sensitivities.dispose();
    _flows.dispose();
    super.dispose();
  }

  /// Keeps controller text aligned when profile access grants change.
  @override
  void didUpdateWidget(covariant _SettingsAgentMemoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final memory = widget.profile.agentMemory;
    if (oldWidget.profile.agentMemory == memory) {
      return;
    }
    _actor.text = memory.actor;
    _readDomains.text = memory.readDomains.join('\n');
    _writeDomains.text = memory.writeDomains.join('\n');
    _sensitivities.text = memory.allowedSensitivities.join('\n');
    _flows.text = _encodeFlows(memory.allowedFlows);
  }

  /// Builds the agent memory access grant editor.
  @override
  Widget build(BuildContext context) {
    final domains = widget.profile.memoryDomains;
    final writable = _availableWriteDomains();
    final defaultWrite =
        writable.contains(widget.profile.agentMemory.defaultWriteDomain)
        ? widget.profile.agentMemory.defaultWriteDomain
        : (writable.isEmpty ? null : writable.first);
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
            _SettingsAutoSaveTextField(
              label: 'Read domains',
              controller: _readDomains,
              initialSavedValue: widget.profile.agentMemory.readDomains.join(
                '\n',
              ),
              onSave: (_) => _save(),
              minLines: 3,
              maxLines: 6,
            ),
            _SettingsAutoSaveTextField(
              label: 'Write domains',
              controller: _writeDomains,
              initialSavedValue: widget.profile.agentMemory.writeDomains.join(
                '\n',
              ),
              onSave: (_) => _save(),
              minLines: 3,
              maxLines: 6,
            ),
            _SettingsAutoSaveTextField(
              label: 'Allowed sensitivities',
              controller: _sensitivities,
              initialSavedValue: widget.profile.agentMemory.allowedSensitivities
                  .join('\n'),
              onSave: (_) => _save(),
              minLines: 3,
              maxLines: 6,
            ),
            _SettingsAutoSaveTextField(
              label: 'Allowed flows',
              controller: _flows,
              initialSavedValue: _encodeFlows(
                widget.profile.agentMemory.allowedFlows,
              ),
              onSave: (_) => _save(),
              minLines: 3,
              maxLines: 6,
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          initialValue: defaultWrite,
          isExpanded: true,
          items: <DropdownMenuItem<String>>[
            for (final domain in domains)
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
            unawaited(_save(defaultWriteDomain: value));
          },
          decoration: SettingsInputDecoration.field(
            context,
            label: 'Default write domain',
          ),
        ),
      ],
    );
  }

  Future<void> _save({String? defaultWriteDomain}) async {
    final writeDomains = _domainLines(_writeDomains.text);
    final nextDefault =
        defaultWriteDomain ??
        (writeDomains.contains(widget.profile.agentMemory.defaultWriteDomain)
            ? widget.profile.agentMemory.defaultWriteDomain
            : (writeDomains.isEmpty
                  ? widget.profile.memoryDomains.first.id
                  : writeDomains.first));
    final memory = AgentMemoryRuntime(
      actor: _actor.text.trim(),
      readDomains: _domainLines(_readDomains.text),
      writeDomains: writeDomains.contains(nextDefault)
          ? writeDomains
          : <String>[...writeDomains, nextDefault],
      defaultWriteDomain: nextDefault,
      allowedSensitivities: SettingsTextCodec.lines(_sensitivities.text),
      allowedFlows: _parseFlows(_flows.text),
    );
    try {
      await widget.controller.saveAgentMemoryRuntime(memory);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }

  List<String> _availableWriteDomains() {
    final ids = widget.profile.memoryDomains.map((domain) => domain.id).toSet();
    return widget.profile.agentMemory.writeDomains.where(ids.contains).toList();
  }

  List<String> _domainLines(String value) {
    final available = widget.profile.memoryDomains
        .map((domain) => domain.id)
        .toSet();
    return SettingsTextCodec.lines(
      value,
    ).where(available.contains).toSet().toList();
  }

  List<MemoryDomainFlow> _parseFlows(String value) {
    final available = widget.profile.memoryDomains
        .map((domain) => domain.id)
        .toSet();
    final flows = <MemoryDomainFlow>[];
    for (final line in SettingsTextCodec.lines(value)) {
      final parts = line.split(RegExp(r'\s*->\s*'));
      if (parts.length != 2) {
        continue;
      }
      final from = parts[0].trim();
      final to = parts[1].trim();
      if (available.contains(from) && available.contains(to)) {
        flows.add(MemoryDomainFlow(fromDomain: from, toDomain: to));
      }
    }
    return flows;
  }

  String _encodeFlows(List<MemoryDomainFlow> flows) {
    return flows
        .map((flow) => '${flow.fromDomain} -> ${flow.toDomain}')
        .join('\n');
  }
}
