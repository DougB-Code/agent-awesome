/// Settings MCP toolset, profile assignment, and server editor widgets.
part of 'settings_panel.dart';

class _SettingsMcpToolsetsCard extends StatelessWidget {
  const _SettingsMcpToolsetsCard({
    required this.config,
    required this.profileServers,
    required this.onChanged,
    required this.onAddServer,
    required this.onDeleteServer,
    required this.onServerChanged,
  });

  final McpToolConfig config;
  final List<McpServerRuntime> profileServers;
  final ValueChanged<McpToolConfig> onChanged;
  final VoidCallback onAddServer;
  final ValueChanged<int> onDeleteServer;
  final void Function(int index, McpServerToolConfig server) onServerChanged;

  /// Builds MCP server toolset settings.
  @override
  Widget build(BuildContext context) {
    return FormPlainSection(
      title: 'MCP toolsets',
      children: <Widget>[
        SettingsToggleField(
          title: 'Enabled',
          subtitle: '${config.servers.length} configured servers',
          value: config.enabled,
          onChanged: (enabled) => onChanged(config.copyWith(enabled: enabled)),
        ),
        if (profileServers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          _SettingsProfileMcpList(servers: profileServers),
        ],
        _SettingsActionRow(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: onAddServer,
              icon: const Icon(Icons.add),
              label: const Text('Add MCP server'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (config.servers.isEmpty)
          const PanelEmptyBlock(label: 'No MCP toolsets configured')
        else
          for (var index = 0; index < config.servers.length; index++) ...[
            if (index > 0)
              const SizedBox(height: SettingsFormMetrics.compactGap),
            _SettingsMcpServerEditor(
              server: config.servers[index],
              onDelete: () => onDeleteServer(index),
              onChanged: (server) => onServerChanged(index, server),
            ),
          ],
      ],
    );
  }
}

class _SettingsProfileMcpList extends StatelessWidget {
  const _SettingsProfileMcpList({required this.servers});

  final List<McpServerRuntime> servers;

  /// Builds profile MCP endpoints that can be bridged into harness tools.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final server in servers)
            Tooltip(
              message: server.endpoint,
              child: PanelBadge(
                label: server.kind.isEmpty ? server.label : server.kind,
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsMcpServerEditor extends StatelessWidget {
  const _SettingsMcpServerEditor({
    required this.server,
    required this.onChanged,
    required this.onDelete,
  });

  final McpServerToolConfig server;
  final ValueChanged<McpServerToolConfig> onChanged;
  final VoidCallback onDelete;

  /// Builds one editable MCP server toolset.
  @override
  Widget build(BuildContext context) {
    final transport = normalizedMcpTransport(server.transport);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  server.name.isEmpty ? 'MCP server' : server.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              PanelInlineIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete MCP server',
                onPressed: onDelete,
              ),
            ],
          ),
          _SettingsInlineField(
            label: 'Name',
            value: server.name,
            onChanged: (value) => onChanged(server.copyWith(name: value)),
          ),
          _SettingsMcpTransportDropdown(
            value: transport,
            onChanged: (value) => onChanged(
              server.copyWith(
                transport: value,
                command: value == 'stdio' ? server.command : '',
                args: value == 'stdio' ? server.args : const <String>[],
                endpoint: value == 'stdio' ? '' : mcpServerEndpoint(server),
                url: '',
              ),
            ),
          ),
          if (transport == 'stdio') ...<Widget>[
            _SettingsInlineField(
              label: 'Command',
              value: server.command,
              onChanged: (value) => onChanged(server.copyWith(command: value)),
            ),
            _SettingsLineListField(
              label: 'Args',
              values: server.args,
              onChanged: (values) => onChanged(server.copyWith(args: values)),
            ),
            _SettingsKeyValueField(
              label: 'Env',
              values: server.env,
              onChanged: (values) => onChanged(server.copyWith(env: values)),
            ),
          ] else
            _SettingsInlineField(
              label: 'Endpoint',
              value: mcpServerEndpoint(server),
              onChanged: (value) =>
                  onChanged(server.copyWith(endpoint: value, url: '')),
            ),
          _SettingsLineListField(
            label: 'Allowed tools',
            values: server.tools.allow,
            onChanged: (values) => onChanged(
              server.copyWith(tools: server.tools.copyWith(allow: values)),
            ),
          ),
          SettingsToggleField(
            title: 'Require confirmation',
            subtitle: 'All tools on this server',
            value: server.requireConfirmation,
            onChanged: (value) => onChanged(
              server.copyWith(
                requireConfirmation: value,
                requireConfirmationTools: value
                    ? const <String>[]
                    : server.requireConfirmationTools,
              ),
            ),
          ),
          _SettingsLineListField(
            label: 'Require confirmation tools',
            values: server.requireConfirmationTools,
            onChanged: (values) => onChanged(
              server.copyWith(
                requireConfirmation: false,
                requireConfirmationTools: values,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMcpTransportDropdown extends StatelessWidget {
  const _SettingsMcpTransportDropdown({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// Builds an MCP transport selector.
  @override
  Widget build(BuildContext context) {
    final selected = _mcpTransportOptions.contains(value)
        ? value
        : 'streamable-http';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(
            value: 'streamable-http',
            child: Text('streamable-http'),
          ),
          DropdownMenuItem<String>(value: 'stdio', child: Text('stdio')),
        ],
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
        decoration: SettingsInputDecoration.field(context, label: 'Transport'),
      ),
    );
  }
}

const List<String> _mcpTransportOptions = <String>['streamable-http', 'stdio'];
