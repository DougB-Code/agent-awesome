/// Settings local exec command cards and inline editor widgets.
part of 'settings_panel.dart';

class _SettingsLocalExecCard extends StatelessWidget {
  const _SettingsLocalExecCard({
    required this.config,
    required this.onChanged,
    required this.onAddCommand,
    required this.onDeleteCommand,
    required this.onCommandChanged,
  });

  final LocalExecToolConfig config;
  final ValueChanged<LocalExecToolConfig> onChanged;
  final VoidCallback onAddCommand;
  final ValueChanged<int> onDeleteCommand;
  final void Function(int index, LocalExecCommandConfig command)
  onCommandChanged;

  /// Builds local OS command tool settings.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: 'Local OS tools',
      children: <Widget>[
        SettingsToggleField(
          title: 'Enabled',
          subtitle: 'local_exec + request_command',
          value: config.enabled,
          onChanged: (enabled) => onChanged(config.copyWith(enabled: enabled)),
        ),
        SettingsToggleField(
          title: 'Persistent approvals',
          subtitle: 'Allow saved request_command approvals',
          value: config.allowPersistentApprovals,
          onChanged: (value) =>
              onChanged(config.copyWith(allowPersistentApprovals: value)),
        ),
        _SettingsInlineField(
          label: 'Default timeout',
          value: config.defaultTimeout,
          onChanged: (value) =>
              onChanged(config.copyWith(defaultTimeout: value)),
        ),
        _SettingsInlineField(
          label: 'Default max output bytes',
          value: config.defaultMaxOutputBytes == 0
              ? ''
              : config.defaultMaxOutputBytes.toString(),
          onChanged: (value) => onChanged(
            config.copyWith(defaultMaxOutputBytes: int.tryParse(value) ?? 0),
          ),
        ),
        _SettingsLineListField(
          label: 'Allowed workdirs',
          values: config.allowedWorkdirs,
          onChanged: (values) =>
              onChanged(config.copyWith(allowedWorkdirs: values)),
        ),
        const SizedBox(height: 4),
        _SettingsActionRow(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: onAddCommand,
              icon: const Icon(Icons.add),
              label: const Text('Add command'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (config.commands.isEmpty)
          const PanelEmptyBlock(label: 'No local commands configured')
        else
          for (var index = 0; index < config.commands.length; index++) ...[
            if (index > 0)
              const SizedBox(height: SettingsFormMetrics.compactGap),
            _SettingsLocalExecCommandEditor(
              command: config.commands[index],
              onDelete: () => onDeleteCommand(index),
              onChanged: (command) => onCommandChanged(index, command),
            ),
          ],
      ],
    );
  }
}

class _SettingsLocalExecCommandEditor extends StatelessWidget {
  const _SettingsLocalExecCommandEditor({
    required this.command,
    required this.onChanged,
    required this.onDelete,
  });

  final LocalExecCommandConfig command;
  final ValueChanged<LocalExecCommandConfig> onChanged;
  final VoidCallback onDelete;

  /// Builds one editable local command alias.
  @override
  Widget build(BuildContext context) {
    final approval = command.approval;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  command.name.isEmpty ? 'Local command' : command.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              PanelInlineIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete command',
                onPressed: onDelete,
              ),
            ],
          ),
          _SettingsInlineField(
            label: 'Name',
            value: command.name,
            onChanged: (value) => onChanged(command.copyWith(name: value)),
          ),
          _SettingsInlineField(
            label: 'Executable',
            value: command.executable,
            onChanged: (value) =>
                onChanged(command.copyWith(executable: value)),
          ),
          _SettingsInlineField(
            label: 'Description',
            value: command.description,
            onChanged: (value) =>
                onChanged(command.copyWith(description: value)),
          ),
          _SettingsLineListField(
            label: 'Args',
            values: command.args,
            onChanged: (values) => onChanged(command.copyWith(args: values)),
          ),
          _SettingsInlineField(
            label: 'Timeout',
            value: command.timeout,
            onChanged: (value) => onChanged(command.copyWith(timeout: value)),
          ),
          _SettingsInlineField(
            label: 'Max output bytes',
            value: command.maxOutputBytes == 0
                ? ''
                : command.maxOutputBytes.toString(),
            onChanged: (value) => onChanged(
              command.copyWith(maxOutputBytes: int.tryParse(value) ?? 0),
            ),
          ),
          SettingsToggleField(
            title: 'Always allow',
            subtitle: 'Skip review for this alias',
            value: approval.alwaysAllow,
            onChanged: (value) => onChanged(
              command.copyWith(approval: approval.copyWith(alwaysAllow: value)),
            ),
          ),
          SettingsToggleField(
            title: 'Always allow within workspace',
            subtitle: 'Skip review when cwd stays in workspace',
            value: approval.alwaysAllowWithinWorkspace,
            onChanged: (value) => onChanged(
              command.copyWith(
                approval: approval.copyWith(alwaysAllowWithinWorkspace: value),
              ),
            ),
          ),
          _SettingsLineListField(
            label: 'Always allow starts with',
            values: approval.alwaysAllowCommandPrefixes,
            onChanged: (values) => onChanged(
              command.copyWith(
                approval: approval.copyWith(alwaysAllowCommandPrefixes: values),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
