/// Settings config, MCP assignment, summary model, and profile dropdowns.
part of 'settings_panel.dart';

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
