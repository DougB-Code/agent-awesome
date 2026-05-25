/// Settings local exec command cards and inline editor widgets.
part of 'settings_panel.dart';

class _SettingsLocalExecCard extends StatefulWidget {
  const _SettingsLocalExecCard({required this.config, required this.onChanged});

  final LocalExecToolConfig config;
  final ValueChanged<LocalExecToolConfig> onChanged;

  /// Creates state for the selected configured executable.
  @override
  State<_SettingsLocalExecCard> createState() => _SettingsLocalExecCardState();
}

class _SettingsLocalExecCardState extends State<_SettingsLocalExecCard> {
  String _selectedCommandName = '';

  /// Builds local OS command tool settings.
  @override
  Widget build(BuildContext context) {
    final commands = widget.config.commands;
    final selectedIndex = _selectedCommandIndex(commands);
    final command = commands.isEmpty
        ? _emptyLocalExecCommandConfig()
        : commands[selectedIndex];
    return FormPlainSection(
      title: 'Command',
      children: <Widget>[
        if (commands.length > 1) ...<Widget>[
          _SettingsCommandSelector(
            commands: commands,
            selectedIndex: selectedIndex,
            onSelected: (index) {
              setState(() => _selectedCommandName = commands[index].name);
            },
          ),
          const SizedBox(height: SettingsFormMetrics.sectionGap),
        ],
        _SettingsLocalExecCommandEditor(
          command: command,
          onChanged: (command) {
            if (commands.length > 1 && command.name.trim().isNotEmpty) {
              setState(() => _selectedCommandName = command.name.trim());
            }
            final next = commands.isEmpty
                ? <LocalExecCommandConfig>[command]
                : <LocalExecCommandConfig>[
                    for (var index = 0; index < commands.length; index++)
                      index == selectedIndex ? command : commands[index],
                  ];
            widget.onChanged(widget.config.copyWith(commands: next));
          },
        ),
      ],
    );
  }

  /// Returns the selected command index after config refreshes.
  int _selectedCommandIndex(List<LocalExecCommandConfig> commands) {
    if (commands.isEmpty) {
      return 0;
    }
    if (_selectedCommandName.isNotEmpty) {
      final index = commands.indexWhere(
        (command) => command.name == _selectedCommandName,
      );
      if (index >= 0) {
        return index;
      }
    }
    return 0;
  }
}

/// Returns the editable placeholder for a package's single CLI command.
LocalExecCommandConfig _emptyLocalExecCommandConfig() {
  return newLocalExecCommandConfig(name: '', executable: '', description: '');
}

class _SettingsCommandSelector extends StatelessWidget {
  const _SettingsCommandSelector({
    required this.commands,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<LocalExecCommandConfig> commands;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Builds selector chips for existing executable tools in this package.
  @override
  Widget build(BuildContext context) {
    return SettingsFormSubsection(
      title: 'Tools',
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (var index = 0; index < commands.length; index++)
              PanelFilterChip(
                label: commands[index].name,
                selected: index == selectedIndex,
                onSelected: (_) => onSelected(index),
              ),
          ],
        ),
      ],
    );
  }
}

class _SettingsLocalExecCommandEditor extends StatelessWidget {
  const _SettingsLocalExecCommandEditor({
    required this.command,
    required this.onChanged,
  });

  final LocalExecCommandConfig command;
  final ValueChanged<LocalExecCommandConfig> onChanged;

  /// Builds one editable local CLI surface.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SettingsCommandGlobalFlagsEditor(
            surface: command.surface,
            onChanged: (surface) =>
                onChanged(command.copyWith(surface: surface)),
          ),
          const SizedBox(height: SettingsFormMetrics.sectionGap),
          _SettingsInlineField(
            label: 'Name',
            value: command.name,
            onChanged: (value) => onChanged(command.copyWith(name: value)),
          ),
          _SettingsInlineField(
            label: 'Command',
            value: command.executable,
            onChanged: (value) =>
                onChanged(command.copyWith(executable: value)),
          ),
          _SettingsInlineField(
            label: 'Description',
            value: command.description,
            maxLines: 2,
            onChanged: (value) =>
                onChanged(command.copyWith(description: value)),
          ),
          const SizedBox(height: SettingsFormMetrics.compactGap),
          _SettingsCommandSubcommandsEditor(
            surface: command.surface,
            onChanged: (surface) =>
                onChanged(command.copyWith(surface: surface)),
          ),
          const SizedBox(height: SettingsFormMetrics.compactGap),
          _SettingsCommandOperationsEditor(
            operations: command.operations,
            onChanged: (operations) =>
                onChanged(command.copyWith(operations: operations)),
          ),
        ],
      ),
    );
  }
}

class _SettingsCommandGlobalFlagsEditor extends StatelessWidget {
  const _SettingsCommandGlobalFlagsEditor({
    required this.surface,
    required this.onChanged,
  });

  final LocalExecCommandSurfaceConfig surface;
  final ValueChanged<LocalExecCommandSurfaceConfig> onChanged;

  /// Builds model-facing global flag documentation controls.
  @override
  Widget build(BuildContext context) {
    return SettingsFormSubsection(
      title: 'Global flags',
      children: <Widget>[
        _SettingsCommandFlagListField(
          values: surface.globalFlags,
          deleteTooltip: 'Delete global flag',
          onChanged: (globalFlags) =>
              onChanged(surface.copyWith(globalFlags: globalFlags)),
        ),
      ],
    );
  }
}

class _SettingsCommandSubcommandsEditor extends StatelessWidget {
  const _SettingsCommandSubcommandsEditor({
    required this.surface,
    required this.onChanged,
  });

  final LocalExecCommandSurfaceConfig surface;
  final ValueChanged<LocalExecCommandSurfaceConfig> onChanged;

  /// Builds model-facing subcommand documentation controls.
  @override
  Widget build(BuildContext context) {
    return SettingsFormSubsection(
      title: 'Subcommands',
      children: <Widget>[
        _SettingsCommandSubcommandListField(
          values: surface.subcommands,
          onChanged: (subcommands) =>
              onChanged(surface.copyWith(subcommands: subcommands)),
        ),
      ],
    );
  }
}

class _SettingsCommandOperationsEditor extends StatelessWidget {
  const _SettingsCommandOperationsEditor({
    required this.operations,
    required this.onChanged,
  });

  final List<LocalExecOperationConfig> operations;
  final ValueChanged<List<LocalExecOperationConfig>> onChanged;

  /// Builds deterministic workflow operation controls for the CLI.
  @override
  Widget build(BuildContext context) {
    return SettingsFormSubsection(
      title: 'Operations',
      children: <Widget>[
        _SettingsCommandOperationListField(
          values: operations,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SettingsCommandOperationListField extends StatelessWidget {
  const _SettingsCommandOperationListField({
    required this.values,
    required this.onChanged,
  });

  final List<LocalExecOperationConfig> values;
  final ValueChanged<List<LocalExecOperationConfig>> onChanged;

  /// Builds editable deterministic operation metadata.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < values.length; index++) ...<Widget>[
          _SettingsCommandOperationEditor(
            value: values[index],
            onChanged: (value) {
              final next = List<LocalExecOperationConfig>.from(values);
              next[index] = value;
              onChanged(next);
            },
            onDelete: () {
              final next = List<LocalExecOperationConfig>.from(values)
                ..removeAt(index);
              onChanged(next);
            },
          ),
          const SizedBox(height: SettingsFormMetrics.sectionGap),
        ],
        _SettingsActionRow(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: () async {
                final operation = await showDialog<LocalExecOperationConfig>(
                  context: context,
                  builder: (context) => const _LocalExecOperationDialog(),
                );
                if (operation == null) {
                  return;
                }
                onChanged(<LocalExecOperationConfig>[...values, operation]);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add operation'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsCommandOperationEditor extends StatelessWidget {
  const _SettingsCommandOperationEditor({
    required this.value,
    required this.onChanged,
    required this.onDelete,
  });

  final LocalExecOperationConfig value;
  final ValueChanged<LocalExecOperationConfig> onChanged;
  final VoidCallback onDelete;

  /// Builds one workflow-callable operation block.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                value.name.isEmpty ? 'Operation' : value.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            PanelInlineIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete operation',
              onPressed: onDelete,
            ),
          ],
        ),
        _SettingsInlineField(
          label: 'Name',
          value: value.name,
          onChanged: (name) => onChanged(value.copyWith(name: name)),
        ),
        _SettingsInlineField(
          label: 'Description',
          value: value.description,
          maxLines: 2,
          onChanged: (description) =>
              onChanged(value.copyWith(description: description)),
        ),
        _SettingsInlineField(
          label: 'Argument tokens',
          value: value.args.join('\n'),
          maxLines: 4,
          onChanged: (args) => onChanged(value.copyWith(args: _argLines(args))),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < SettingsFormMetrics.twoColumnMinWidth;
            final formatField = _SettingsInlineField(
              label: 'Output format',
              value: value.output.format,
              onChanged: (format) => onChanged(
                value.copyWith(output: value.output.copyWith(format: format)),
              ),
            );
            final sourceField = _SettingsInlineField(
              label: 'Output source',
              value: value.output.source,
              onChanged: (source) => onChanged(
                value.copyWith(output: value.output.copyWith(source: source)),
              ),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[formatField, sourceField],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: formatField),
                const SizedBox(width: SettingsFormMetrics.fieldGap),
                Expanded(child: sourceField),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Parses line-delimited argv template tokens from an operation field.
List<String> _argLines(String value) {
  return value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

class _SettingsCommandFlagListField extends StatelessWidget {
  const _SettingsCommandFlagListField({
    required this.values,
    required this.deleteTooltip,
    required this.onChanged,
  });

  final List<LocalExecCommandFlagConfig> values;
  final String deleteTooltip;
  final ValueChanged<List<LocalExecCommandFlagConfig>> onChanged;

  /// Builds editable CLI flag metadata rows.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < values.length; index++) ...<Widget>[
          _SettingsCommandFlagField(
            value: values[index],
            deleteTooltip: deleteTooltip,
            onChanged: (value) {
              final next = List<LocalExecCommandFlagConfig>.from(values);
              next[index] = value;
              onChanged(next);
            },
            onDelete: () {
              final next = List<LocalExecCommandFlagConfig>.from(values)
                ..removeAt(index);
              onChanged(next);
            },
          ),
        ],
        _SettingsActionRow(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: () async {
                final flag = await showDialog<LocalExecCommandFlagConfig>(
                  context: context,
                  builder: (context) => const _LocalExecFlagDialog(),
                );
                if (flag == null) {
                  return;
                }
                onChanged(<LocalExecCommandFlagConfig>[...values, flag]);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add flag'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsCommandFlagField extends StatelessWidget {
  const _SettingsCommandFlagField({
    required this.value,
    required this.deleteTooltip,
    required this.onChanged,
    required this.onDelete,
  });

  final LocalExecCommandFlagConfig value;
  final String deleteTooltip;
  final ValueChanged<LocalExecCommandFlagConfig> onChanged;
  final VoidCallback onDelete;

  /// Builds one editable CLI flag row.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 2,
            child: _SettingsInlineField(
              label: 'Flag',
              value: value.name,
              onChanged: (name) => onChanged(value.copyWith(name: name)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: _SettingsInlineField(
              label: 'Description',
              value: value.description,
              maxLines: 2,
              onChanged: (description) =>
                  onChanged(value.copyWith(description: description)),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: PanelInlineIconButton(
              icon: Icons.delete_outline,
              tooltip: deleteTooltip,
              onPressed: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCommandSubcommandListField extends StatelessWidget {
  const _SettingsCommandSubcommandListField({
    required this.values,
    required this.onChanged,
  });

  final List<LocalExecSubcommandConfig> values;
  final ValueChanged<List<LocalExecSubcommandConfig>> onChanged;

  /// Builds editable CLI subcommand metadata.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < values.length; index++) ...<Widget>[
          _SettingsCommandSubcommandEditor(
            value: values[index],
            onChanged: (value) {
              final next = List<LocalExecSubcommandConfig>.from(values);
              next[index] = value;
              onChanged(next);
            },
            onDelete: () {
              final next = List<LocalExecSubcommandConfig>.from(values)
                ..removeAt(index);
              onChanged(next);
            },
          ),
          const SizedBox(height: SettingsFormMetrics.sectionGap),
        ],
        _SettingsActionRow(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: () async {
                final subcommand = await showDialog<LocalExecSubcommandConfig>(
                  context: context,
                  builder: (context) => const _LocalExecSubcommandDialog(),
                );
                if (subcommand == null) {
                  return;
                }
                onChanged(<LocalExecSubcommandConfig>[...values, subcommand]);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add subcommand'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsCommandSubcommandEditor extends StatelessWidget {
  const _SettingsCommandSubcommandEditor({
    required this.value,
    required this.onChanged,
    required this.onDelete,
  });

  final LocalExecSubcommandConfig value;
  final ValueChanged<LocalExecSubcommandConfig> onChanged;
  final VoidCallback onDelete;

  /// Builds one editable CLI subcommand block.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                value.name.isEmpty ? 'Subcommand' : value.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            PanelInlineIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete subcommand',
              onPressed: onDelete,
            ),
          ],
        ),
        _SettingsInlineField(
          label: 'Name',
          value: value.name,
          onChanged: (name) => onChanged(value.copyWith(name: name)),
        ),
        _SettingsInlineField(
          label: 'Description',
          value: value.description,
          maxLines: 2,
          onChanged: (description) =>
              onChanged(value.copyWith(description: description)),
        ),
        _SettingsCommandFlagListField(
          values: value.flags,
          deleteTooltip: 'Delete subcommand flag',
          onChanged: (flags) => onChanged(value.copyWith(flags: flags)),
        ),
      ],
    );
  }
}
