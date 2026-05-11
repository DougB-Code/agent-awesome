/// Settings MCP server editing dialog.
part of 'settings_panel.dart';

class _McpServerDialog extends StatefulWidget {
  const _McpServerDialog({required this.seed});

  final McpServerRuntime? seed;

  /// Creates state for the add-MCP-server dialog.
  @override
  State<_McpServerDialog> createState() => _McpServerDialogState();
}

class _McpServerDialogState extends State<_McpServerDialog> {
  late final TextEditingController _name = TextEditingController(
    text: _seedName(),
  );
  late final TextEditingController _endpoint = TextEditingController(
    text: widget.seed?.endpoint ?? '',
  );
  final TextEditingController _command = TextEditingController();
  String _transport = 'streamable-http';

  /// Cleans up dialog field controllers.
  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _command.dispose();
    super.dispose();
  }

  /// Builds the required-field MCP server dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add MCP server'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: SettingsInputDecoration.field(context, label: 'Name'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _transport,
              decoration: SettingsInputDecoration.field(
                context,
                label: 'Transport',
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'streamable-http',
                  child: Text('streamable-http'),
                ),
                DropdownMenuItem<String>(value: 'stdio', child: Text('stdio')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _transport = value);
                }
              },
            ),
            if (_transport == 'stdio')
              TextField(
                controller: _command,
                decoration: SettingsInputDecoration.field(
                  context,
                  label: 'Command',
                ),
                onSubmitted: (_) => _save(),
              )
            else
              TextField(
                controller: _endpoint,
                decoration: SettingsInputDecoration.field(
                  context,
                  label: 'Endpoint',
                ),
                onSubmitted: (_) => _save(),
              ),
          ],
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

  /// Returns a seed name from the runtime profile server.
  String _seedName() {
    final seed = widget.seed;
    if (seed == null) {
      return '';
    }
    return SettingsNameFactory.toolNameFromLabel(
      seed.kind.isEmpty ? seed.id : seed.kind,
    );
  }

  /// Returns the new MCP server when required fields are present.
  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    if (_transport == 'stdio') {
      final command = _command.text.trim();
      if (command.isEmpty) {
        return;
      }
      Navigator.of(
        context,
      ).pop(newStdioMcpServerToolConfig(name: name, command: command));
      return;
    }
    final endpoint = _endpoint.text.trim();
    if (endpoint.isEmpty) {
      return;
    }
    Navigator.of(
      context,
    ).pop(newHttpMcpServerToolConfig(name: name, endpoint: endpoint));
  }
}
