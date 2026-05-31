/// Settings config, MCP assignment, and summary model dropdowns.
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

  /// Builds an assignment dropdown for managed config files.
  @override
  Widget build(BuildContext context) {
    final selected = entries.any((entry) => entry.path == selectedPath)
        ? selectedPath
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: SettingsFormMetrics.fieldGap),
      child: PanelLabeledFormControl(
        label: label,
        child: DropdownButtonFormField<String>(
          initialValue: selected,
          isDense: true,
          style: SettingsFormTextStyle.field(context),
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
      ),
    );
  }
}

/// _SettingsMemoryDomainDropdown selects the default memory domain.
class _SettingsMemoryDomainDropdown extends StatelessWidget {
  /// Creates a memory domain selector.
  const _SettingsMemoryDomainDropdown({
    required this.label,
    required this.domains,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final List<McpServerRuntime> domains;
  final String selectedId;
  final ValueChanged<McpServerRuntime> onChanged;

  /// Builds a dropdown of configured memory domains.
  @override
  Widget build(BuildContext context) {
    final selected = domains.any((domain) => domain.id == selectedId)
        ? selectedId
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: SettingsFormMetrics.fieldGap),
      child: PanelLabeledFormControl(
        label: label,
        child: DropdownButtonFormField<String>(
          initialValue: selected,
          isDense: true,
          style: SettingsFormTextStyle.field(context),
          isExpanded: true,
          items: <DropdownMenuItem<String>>[
            for (final domain in domains)
              DropdownMenuItem<String>(
                value: domain.id,
                child: Text(domain.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: domains.isEmpty
              ? null
              : (domainId) {
                  if (domainId == null) {
                    return;
                  }
                  for (final domain in domains) {
                    if (domain.id == domainId) {
                      onChanged(domain);
                      return;
                    }
                  }
                },
          decoration: SettingsInputDecoration.field(context, label: label),
        ),
      ),
    );
  }
}

/// _SettingsInterfaceModeDropdown selects Basic or Advanced UI mode.
class _SettingsInterfaceModeDropdown extends StatelessWidget {
  /// Creates an interface mode selector.
  const _SettingsInterfaceModeDropdown({
    required this.label,
    required this.selectedMode,
    required this.onChanged,
  });

  final String label;
  final String selectedMode;
  final ValueChanged<String> onChanged;

  /// Builds a dropdown of supported interface modes.
  @override
  Widget build(BuildContext context) {
    final selected = normalizeInterfaceMode(selectedMode);
    return Padding(
      padding: const EdgeInsets.only(bottom: SettingsFormMetrics.fieldGap),
      child: PanelLabeledFormControl(
        label: label,
        child: DropdownButtonFormField<String>(
          initialValue: selected,
          isDense: true,
          style: SettingsFormTextStyle.field(context),
          isExpanded: true,
          items: <DropdownMenuItem<String>>[
            for (final mode in interfaceModeIds)
              DropdownMenuItem<String>(
                value: mode,
                child: Text(interfaceModeLabel(mode)),
              ),
          ],
          onChanged: (mode) {
            if (mode != null) {
              onChanged(mode);
            }
          },
          decoration: SettingsInputDecoration.field(context, label: label),
        ),
      ),
    );
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
      padding: const EdgeInsets.only(bottom: SettingsFormMetrics.fieldGap),
      child: PanelLabeledFormControl(
        label: label,
        child: DropdownButtonFormField<_SummaryModelOption>(
          initialValue: selected,
          isDense: true,
          style: SettingsFormTextStyle.field(context),
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
