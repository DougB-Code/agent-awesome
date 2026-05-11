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
            badge: server.enabled ? 'Active' : '',
            value: server,
          ),
      ],
      onSelect: (id) => setState(() => _selectedServerId = id),
      builder: (server, query) {
        if (!SettingsQuery.matches(query, <String>[
          server.id,
          server.label,
          server.kind,
          server.endpoint,
          server.healthUrl,
          server.workingDirectory,
          server.packagePath,
          server.arguments.join(' '),
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
    return widget.servers.first.id;
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
    _arguments.dispose();
    super.dispose();
  }

  /// Builds one MCP binding tile from the active profile.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: widget.server.label.isEmpty ? 'MCP binding' : widget.server.label,
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
          label: 'Server ID',
          controller: _id,
          initialSavedValue: widget.server.id,
          onSave: (_) => _save(),
        ),
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
      arguments: _arguments.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(),
      autoStart: _autoStart,
      enabled: _enabled,
    );
    try {
      await widget.controller.saveRequiredServerRuntime(
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
