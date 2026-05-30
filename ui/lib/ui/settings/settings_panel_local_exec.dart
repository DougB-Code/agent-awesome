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
  /// Builds local OS command tool settings.
  @override
  Widget build(BuildContext context) {
    final commands = widget.config.commands;
    final editableCommands = commands.isEmpty
        ? <LocalExecCommandConfig>[_emptyLocalExecCommandConfig()]
        : commands;
    return FormPlainSection(
      title: 'Command',
      children: <Widget>[
        for (var index = 0; index < editableCommands.length; index++) ...[
          if (index > 0) const SizedBox(height: SettingsFormMetrics.sectionGap),
          _SettingsLocalExecCommandEditor(
            command: editableCommands[index],
            onChanged: (command) {
              final next = <LocalExecCommandConfig>[
                for (
                  var commandIndex = 0;
                  commandIndex < editableCommands.length;
                  commandIndex++
                )
                  commandIndex == index
                      ? command
                      : editableCommands[commandIndex],
              ];
              widget.onChanged(widget.config.copyWith(commands: next));
            },
          ),
        ],
      ],
    );
  }
}

/// Returns the editable placeholder for a package's single CLI command.
LocalExecCommandConfig _emptyLocalExecCommandConfig() {
  return newLocalExecCommandConfig(name: '', executable: '', description: '');
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
          const SizedBox(height: SettingsFormMetrics.sectionGap),
          _SettingsCommandGlobalFlagsEditor(
            surface: command.surface,
            onChanged: (surface) =>
                onChanged(command.copyWith(surface: surface)),
          ),
          const SizedBox(height: SettingsFormMetrics.compactGap),
          _SettingsCommandSubcommandsEditor(
            surface: command.surface,
            onChanged: (surface) =>
                onChanged(command.copyWith(surface: surface)),
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

class _SettingsCommandSubcommandListField extends StatefulWidget {
  const _SettingsCommandSubcommandListField({
    required this.values,
    required this.onChanged,
  });

  final List<LocalExecSubcommandConfig> values;
  final ValueChanged<List<LocalExecSubcommandConfig>> onChanged;

  /// Creates expansion state for the recursive subcommand table.
  @override
  State<_SettingsCommandSubcommandListField> createState() =>
      _SettingsCommandSubcommandListFieldState();
}

class _SettingsCommandSubcommandListFieldState
    extends State<_SettingsCommandSubcommandListField> {
  final Set<String> _expanded = <String>{};
  String _selectedPath = '';

  /// Adds default command tree expansion after the first config load.
  @override
  void initState() {
    super.initState();
    _expanded.addAll(_defaultExpandedSubcommandPaths(widget.values));
  }

  /// Keeps tree state valid when autosaved config updates return.
  @override
  void didUpdateWidget(
    covariant _SettingsCommandSubcommandListField oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.values != widget.values) {
      _expanded.addAll(_defaultExpandedSubcommandPaths(widget.values));
      if (_selectedPath.isNotEmpty &&
          _subcommandAtPath(
                widget.values,
                _subcommandPathIndexes(_selectedPath),
              ) ==
              null) {
        _selectedPath = '';
      }
    }
  }

  /// Builds editable CLI subcommand metadata as a tree with a command view.
  @override
  Widget build(BuildContext context) {
    final selectedPath = _validatedSelectedPath(widget.values);
    final selected = selectedPath.isEmpty
        ? null
        : _subcommandAtPath(
            widget.values,
            _subcommandPathIndexes(selectedPath),
          );
    return SizedBox(
      height: selected == null ? 560 : 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: widget.values.isEmpty
                ? const PanelEmptyBlock(label: 'No subcommands configured')
                : _SettingsCommandTree(
                    rows: _buildRows(
                      values: widget.values,
                      pathIndexes: const <int>[],
                      pathNames: const <String>[],
                      depth: 0,
                      selectedPath: selectedPath,
                      onChanged: widget.onChanged,
                    ),
                  ),
          ),
          const SizedBox(height: SettingsFormMetrics.compactGap),
          if (selected != null) ...<Widget>[
            SizedBox(
              height: 360,
              child: _SettingsCommandSubcommandDetails(
                value: selected,
                commandPath: _subcommandPathById(widget.values, selectedPath),
                level: _subcommandPathIndexes(selectedPath).length,
                onChanged: (value) {
                  widget.onChanged(
                    _replaceSubcommandAtPath(
                      widget.values,
                      _subcommandPathIndexes(selectedPath),
                      value,
                    ),
                  );
                },
                onDelete: () {
                  widget.onChanged(
                    _removeSubcommandAtPath(
                      widget.values,
                      _subcommandPathIndexes(selectedPath),
                    ),
                  );
                  setState(() => _selectedPath = '');
                },
                onAddNested: () => _addNestedSubcommand(selectedPath, selected),
                onClose: () => setState(() => _selectedPath = ''),
              ),
            ),
            const SizedBox(height: SettingsFormMetrics.compactGap),
          ],
          _SettingsActionRow(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () =>
                    _addSubcommand(widget.values, widget.onChanged),
                icon: const Icon(Icons.add),
                label: const Text('Add subcommand'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds recursive tree rows for one sibling list.
  List<Widget> _buildRows({
    required List<LocalExecSubcommandConfig> values,
    required List<int> pathIndexes,
    required List<String> pathNames,
    required int depth,
    required String selectedPath,
    required ValueChanged<List<LocalExecSubcommandConfig>> onChanged,
  }) {
    return <Widget>[
      for (var index = 0; index < values.length; index++)
        _SettingsCommandTreeNode(
          value: values[index],
          commandPath: _subcommandPath(pathNames, values[index]),
          pathId: _subcommandExpansionId(pathIndexes, index),
          depth: depth,
          expanded: _expanded.contains(
            _subcommandExpansionId(pathIndexes, index),
          ),
          selected: selectedPath == _subcommandExpansionId(pathIndexes, index),
          onToggleExpanded: () =>
              _toggleExpanded(_subcommandExpansionId(pathIndexes, index)),
          onSelected: () =>
              _selectSubcommand(_subcommandExpansionId(pathIndexes, index)),
          childRows:
              _expanded.contains(_subcommandExpansionId(pathIndexes, index))
              ? _buildRows(
                  values: values[index].subcommands,
                  pathIndexes: <int>[...pathIndexes, index],
                  pathNames: <String>[...pathNames, values[index].name.trim()],
                  depth: depth + 1,
                  selectedPath: selectedPath,
                  onChanged: (subcommands) {
                    final next = List<LocalExecSubcommandConfig>.from(values);
                    next[index] = values[index].copyWith(
                      subcommands: subcommands,
                    );
                    onChanged(next);
                  },
                )
              : const <Widget>[],
        ),
    ];
  }

  /// Expands or collapses one subcommand tree node.
  void _toggleExpanded(String id) {
    setState(() {
      if (!_expanded.remove(id)) {
        _expanded.add(id);
      }
    });
  }

  /// Adds one root-level subcommand.
  Future<void> _addSubcommand(
    List<LocalExecSubcommandConfig> values,
    ValueChanged<List<LocalExecSubcommandConfig>> onChanged,
  ) async {
    final subcommand = await showDialog<LocalExecSubcommandConfig>(
      context: context,
      builder: (context) => const _LocalExecSubcommandDialog(),
    );
    if (subcommand == null) {
      return;
    }
    onChanged(<LocalExecSubcommandConfig>[...values, subcommand]);
    _selectSubcommand('${values.length}');
  }

  /// Adds one nested subcommand under the selected command.
  Future<void> _addNestedSubcommand(
    String selectedPath,
    LocalExecSubcommandConfig selected,
  ) async {
    final subcommand = await showDialog<LocalExecSubcommandConfig>(
      context: context,
      builder: (context) => const _LocalExecSubcommandDialog(),
    );
    if (subcommand == null) {
      return;
    }
    final indexes = _subcommandPathIndexes(selectedPath);
    widget.onChanged(
      _replaceSubcommandAtPath(
        widget.values,
        indexes,
        selected.copyWith(
          subcommands: <LocalExecSubcommandConfig>[
            ...selected.subcommands,
            subcommand,
          ],
        ),
      ),
    );
    setState(() {
      _expanded.add(selectedPath);
      _selectedPath = <int>[...indexes, selected.subcommands.length].join('.');
    });
  }

  /// Selects a subcommand and opens the local command inspector.
  void _selectSubcommand(String path) {
    setState(() => _selectedPath = path);
  }

  /// Returns the current selected path only when it still exists.
  String _validatedSelectedPath(List<LocalExecSubcommandConfig> values) {
    if (_selectedPath.isNotEmpty &&
        _subcommandAtPath(values, _subcommandPathIndexes(_selectedPath)) !=
            null) {
      return _selectedPath;
    }
    return '';
  }
}

class _SettingsCommandTree extends StatelessWidget {
  const _SettingsCommandTree({required this.rows});

  final List<Widget> rows;

  /// Builds the selectable command tree surface.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(
          color: colors.border,
          width: AgentAwesomeStrokeTokens.borderWidth,
        ),
        borderRadius: BorderRadius.circular(PanelStyleTokens.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        primary: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[const _SettingsCommandTreeHeader(), ...rows],
        ),
      ),
    );
  }
}

class _SettingsCommandTreeHeader extends StatelessWidget {
  const _SettingsCommandTreeHeader();

  /// Builds column labels for the command tree.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final style = TextStyle(
      color: colors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w800,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.border,
            width: AgentAwesomeStrokeTokens.dividerWidth,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(flex: 4, child: Text('Command Tree', style: style)),
          Expanded(flex: 2, child: Text('Flags', style: style)),
          Expanded(flex: 4, child: Text('Description', style: style)),
        ],
      ),
    );
  }
}

class _SettingsCommandTreeNode extends StatelessWidget {
  const _SettingsCommandTreeNode({
    required this.value,
    required this.commandPath,
    required this.pathId,
    required this.depth,
    required this.expanded,
    required this.selected,
    required this.onToggleExpanded,
    required this.onSelected,
    required this.childRows,
  });

  final LocalExecSubcommandConfig value;
  final String commandPath;
  final String pathId;
  final int depth;
  final bool expanded;
  final bool selected;
  final VoidCallback onToggleExpanded;
  final VoidCallback onSelected;
  final List<Widget> childRows;

  /// Builds one selectable tree node and its visible descendants.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final hasChildren = value.subcommands.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          onTap: onSelected,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
            decoration: BoxDecoration(
              color: selected ? colors.greenSoft : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: colors.border.withValues(alpha: 0.7),
                  width: AgentAwesomeStrokeTokens.dividerWidth,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: 4,
                  child: Row(
                    children: <Widget>[
                      SizedBox(width: _subcommandTreeIndent(depth)),
                      SizedBox(
                        width: 24,
                        child: hasChildren
                            ? PanelInlineIconButton(
                                icon: expanded
                                    ? Icons.keyboard_arrow_down
                                    : Icons.chevron_right,
                                tooltip: expanded
                                    ? 'Collapse command'
                                    : 'Expand command',
                                onPressed: onToggleExpanded,
                              )
                            : Icon(
                                Icons.subdirectory_arrow_right,
                                size: 15,
                                color: colors.muted,
                              ),
                      ),
                      const SizedBox(width: 6),
                      PanelBadge(label: 'L${depth + 1}'),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          value.name.trim().isEmpty
                              ? 'Subcommand'
                              : value.name.trim(),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${value.flags.length}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    value.description.trim().isEmpty
                        ? commandPath
                        : value.description.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...childRows,
      ],
    );
  }
}

class _SettingsCommandSubcommandDetails extends StatelessWidget {
  const _SettingsCommandSubcommandDetails({
    required this.value,
    required this.commandPath,
    required this.level,
    required this.onChanged,
    required this.onDelete,
    required this.onAddNested,
    required this.onClose,
  });

  final LocalExecSubcommandConfig value;
  final String commandPath;
  final int level;
  final ValueChanged<LocalExecSubcommandConfig> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onAddNested;
  final VoidCallback onClose;

  /// Builds the selected command details view below the tree.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(
          color: colors.border,
          width: AgentAwesomeStrokeTokens.borderWidth,
        ),
        borderRadius: BorderRadius.circular(PanelStyleTokens.radius),
      ),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                PanelBadge(label: 'L$level'),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value.name.trim().isEmpty
                        ? 'Subcommand'
                        : value.name.trim(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                PanelInlineIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete subcommand',
                  onPressed: onDelete,
                ),
                const SizedBox(width: 4),
                PanelInlineIconButton(
                  icon: Icons.close,
                  tooltip: 'Close command inspector',
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: SettingsFormMetrics.compactGap),
            _SettingsCommandPathView(commandPath: commandPath),
            const SizedBox(height: SettingsFormMetrics.compactGap),
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
            const SizedBox(height: SettingsFormMetrics.compactGap),
            SettingsFormSubsection(
              title: 'Flags',
              children: <Widget>[
                _SettingsCommandFlagListField(
                  values: value.flags,
                  deleteTooltip: 'Delete subcommand flag',
                  onChanged: (flags) => onChanged(value.copyWith(flags: flags)),
                ),
              ],
            ),
            const SizedBox(height: SettingsFormMetrics.compactGap),
            SettingsFormSubsection(
              title: 'Child commands',
              children: <Widget>[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final child in value.subcommands)
                      PanelBadge(
                        label: child.name.trim().isEmpty
                            ? 'Subcommand'
                            : child.name.trim(),
                      ),
                    OutlinedButton.icon(
                      onPressed: onAddNested,
                      icon: const Icon(Icons.add),
                      label: const Text('Add child command'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCommandPathView extends StatelessWidget {
  const _SettingsCommandPathView({required this.commandPath});

  final String commandPath;

  /// Builds the selected command path preview.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(
          color: colors.border,
          width: AgentAwesomeStrokeTokens.borderWidth,
        ),
        borderRadius: BorderRadius.circular(PanelStyleTokens.compactRadius),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SelectableText(
              commandPath,
              style: TextStyle(
                color: colors.ink,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
          PanelInlineIconButton(
            icon: Icons.copy,
            tooltip: 'Copy command path',
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: commandPath)),
          ),
        ],
      ),
    );
  }
}

/// Returns default expanded paths so command trees open enough to inspect.
Set<String> _defaultExpandedSubcommandPaths(
  List<LocalExecSubcommandConfig> values,
) {
  final paths = <String>{};
  void visit(List<LocalExecSubcommandConfig> items, List<int> parent) {
    for (var index = 0; index < items.length; index++) {
      final path = <int>[...parent, index];
      if (items[index].subcommands.isNotEmpty) {
        paths.add(path.join('.'));
        visit(items[index].subcommands, path);
      }
    }
  }

  visit(values, const <int>[]);
  return paths;
}

/// Returns one subcommand at an index path.
LocalExecSubcommandConfig? _subcommandAtPath(
  List<LocalExecSubcommandConfig> values,
  List<int> path,
) {
  var current = values;
  LocalExecSubcommandConfig? selected;
  for (final index in path) {
    if (index < 0 || index >= current.length) {
      return null;
    }
    selected = current[index];
    current = selected.subcommands;
  }
  return selected;
}

/// Replaces one subcommand at an index path.
List<LocalExecSubcommandConfig> _replaceSubcommandAtPath(
  List<LocalExecSubcommandConfig> values,
  List<int> path,
  LocalExecSubcommandConfig value,
) {
  if (path.isEmpty) {
    return values;
  }
  final index = path.first;
  if (index < 0 || index >= values.length) {
    return values;
  }
  final next = List<LocalExecSubcommandConfig>.from(values);
  if (path.length == 1) {
    next[index] = value;
    return next;
  }
  next[index] = values[index].copyWith(
    subcommands: _replaceSubcommandAtPath(
      values[index].subcommands,
      path.sublist(1),
      value,
    ),
  );
  return next;
}

/// Removes one subcommand at an index path.
List<LocalExecSubcommandConfig> _removeSubcommandAtPath(
  List<LocalExecSubcommandConfig> values,
  List<int> path,
) {
  if (path.isEmpty) {
    return values;
  }
  final index = path.first;
  if (index < 0 || index >= values.length) {
    return values;
  }
  final next = List<LocalExecSubcommandConfig>.from(values);
  if (path.length == 1) {
    next.removeAt(index);
    return next;
  }
  next[index] = values[index].copyWith(
    subcommands: _removeSubcommandAtPath(
      values[index].subcommands,
      path.sublist(1),
    ),
  );
  return next;
}

/// Returns the command path text for a selected tree path id.
String _subcommandPathById(
  List<LocalExecSubcommandConfig> values,
  String pathId,
) {
  final names = <String>[];
  var current = values;
  for (final index in _subcommandPathIndexes(pathId)) {
    if (index < 0 || index >= current.length) {
      break;
    }
    final value = current[index];
    if (value.name.trim().isNotEmpty) {
      names.add(value.name.trim());
    }
    current = value.subcommands;
  }
  return names.join(' ');
}

/// Parses a dot-delimited tree path id into indexes.
List<int> _subcommandPathIndexes(String pathId) {
  return pathId
      .split('.')
      .map((part) => int.tryParse(part.trim()))
      .whereType<int>()
      .toList();
}

/// Returns a stable expansion id from one row index path.
String _subcommandExpansionId(List<int> pathIndexes, int index) {
  return <int>[...pathIndexes, index].join('.');
}

/// Returns the readable command path for a nested subcommand row.
String _subcommandPath(
  List<String> parentNames,
  LocalExecSubcommandConfig value,
) {
  return <String>[
    for (final name in parentNames)
      if (name.trim().isNotEmpty) name.trim(),
    if (value.name.trim().isNotEmpty) value.name.trim(),
  ].join(' ');
}

/// Returns a capped indentation for nested command tree rows.
double _subcommandTreeIndent(int depth) {
  return (depth * 22).clamp(0, 88).toDouble();
}
