/// Settings MCP toolset, runtime assignment, and server editor widgets.
part of 'settings_panel.dart';

class _SettingsMcpToolsetsCard extends StatelessWidget {
  const _SettingsMcpToolsetsCard({
    required this.config,
    required this.runtimeServers,
    required this.statusMessage,
    required this.starting,
    required this.startingServerName,
    required this.onStartServer,
  });

  final McpToolConfig config;
  final List<McpServerRuntime> runtimeServers;
  final String statusMessage;
  final bool starting;
  final String startingServerName;
  final ValueChanged<McpServerToolConfig> onStartServer;

  /// Builds loaded MCP server package details.
  @override
  Widget build(BuildContext context) {
    return FormPlainSection(
      title: 'Loaded MCP file',
      children: <Widget>[
        _SettingsReadOnlyField(
          label: 'Enabled',
          value: config.enabled ? 'Yes' : 'No',
        ),
        if (runtimeServers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          _SettingsRuntimeMcpList(servers: runtimeServers),
        ],
        if (statusMessage.trim().isNotEmpty)
          _SettingsReadOnlyField(label: 'Last check', value: statusMessage),
        if (config.servers.isEmpty)
          const PanelEmptyBlock(label: 'No MCP servers loaded')
        else
          for (var index = 0; index < config.servers.length; index++) ...[
            if (index > 0)
              const SizedBox(height: SettingsFormMetrics.compactGap),
            _SettingsMcpServerSummary(
              server: config.servers[index],
              starting:
                  starting &&
                  startingServerName == config.servers[index].name.trim(),
              onStart: () => onStartServer(config.servers[index]),
            ),
          ],
      ],
    );
  }
}

class _SettingsRuntimeMcpList extends StatelessWidget {
  const _SettingsRuntimeMcpList({required this.servers});

  final List<McpServerRuntime> servers;

  /// Builds runtime MCP endpoints that can be bridged into harness tools.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SettingsFormMetrics.fieldGap),
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

class _SettingsMcpServerSummary extends StatelessWidget {
  const _SettingsMcpServerSummary({
    required this.server,
    required this.starting,
    required this.onStart,
  });

  final McpServerToolConfig server;
  final bool starting;
  final VoidCallback onStart;

  /// Builds one loaded MCP server definition.
  @override
  Widget build(BuildContext context) {
    final transport = normalizedMcpTransport(server.transport);
    final actionLabel = transport == 'stdio' ? 'Start' : 'Check';
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
              OutlinedButton.icon(
                onPressed: starting ? null : onStart,
                icon: starting
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        transport == 'stdio'
                            ? Icons.play_arrow
                            : Icons.power_settings_new,
                      ),
                label: Text(actionLabel),
              ),
            ],
          ),
          _SettingsReadOnlyField(label: 'Name', value: server.name),
          _SettingsReadOnlyField(label: 'Transport', value: transport),
          if (transport == 'stdio') ...<Widget>[
            _SettingsReadOnlyField(label: 'Command', value: server.command),
            _SettingsReadOnlyField(
              label: 'Args',
              value: server.args.isEmpty ? 'None' : server.args.join(' '),
            ),
            _SettingsReadOnlyField(
              label: 'Env',
              value: _sortedMcpKeys(server.env),
            ),
          ] else
            _SettingsReadOnlyField(
              label: 'Endpoint',
              value: mcpServerEndpoint(server),
            ),
          _SettingsReadOnlyField(
            label: 'Allowed tools',
            value: server.tools.allow.isEmpty
                ? 'All server tools'
                : server.tools.allow.join(', '),
          ),
          _SettingsReadOnlyField(
            label: 'Confirmation',
            value: _mcpConfirmationSummary(server),
          ),
        ],
      ),
    );
  }
}

/// Formats MCP confirmation policy loaded from the package file.
String _mcpConfirmationSummary(McpServerToolConfig server) {
  if (server.requireConfirmation) {
    return 'All tools';
  }
  if (server.requireConfirmationTools.isEmpty) {
    return 'None';
  }
  return server.requireConfirmationTools.join(', ');
}

/// Formats loaded MCP environment keys without exposing values.
String _sortedMcpKeys(Map<String, String> values) {
  if (values.isEmpty) {
    return 'None';
  }
  final keys = values.keys.toList()..sort();
  return keys.join(', ');
}
