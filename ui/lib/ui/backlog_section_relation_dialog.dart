/// Backlog task relation creation dialog.
part of 'backlog_section.dart';

/// Shows the backlog relation creation dialog.
Future<void> _showTaskRelationDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  WorkspaceTask task,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskRelationDialog(controller: controller, task: task);
    },
  );
}

class _TaskRelationDialog extends StatefulWidget {
  const _TaskRelationDialog({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  @override
  State<_TaskRelationDialog> createState() => _TaskRelationDialogState();
}

class _TaskRelationDialogState extends State<_TaskRelationDialog> {
  final TextEditingController _explanation = TextEditingController();
  String _targetTaskId = '';
  String _relationType = 'related_to';

  /// Initializes the first available target backlog item.
  @override
  void initState() {
    super.initState();
    final targets = _relationTargets;
    if (targets.isNotEmpty) {
      _targetTaskId = targets.first.id;
    }
  }

  /// Cleans up dialog controllers.
  @override
  void dispose() {
    _explanation.dispose();
    super.dispose();
  }

  List<WorkspaceTask> get _relationTargets {
    return widget.controller.workspace.tasks.where((task) {
      return task.id != widget.task.id;
    }).toList();
  }

  /// Builds the backlog relation creation dialog.
  @override
  Widget build(BuildContext context) {
    final targets = _relationTargets;
    return AlertDialog(
      title: const Text('Add Relation'),
      content: SizedBox(
        width: 460,
        child: targets.isEmpty
            ? const Text(
                'Create another backlog item before adding a relation.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: _targetTaskId.isEmpty ? null : _targetTaskId,
                    decoration: _taskDialogDecoration(
                      context,
                      'Related backlog item',
                    ),
                    isExpanded: true,
                    items: <DropdownMenuItem<String>>[
                      for (final target in targets)
                        DropdownMenuItem<String>(
                          value: target.id,
                          child: Text(
                            target.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _targetTaskId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _TaskDropdown(
                    value: _relationType,
                    values: _taskRelationTypes,
                    tooltip: 'Relation type',
                    onChanged: (value) => setState(() => _relationType = value),
                  ),
                  const SizedBox(height: 10),
                  _TaskTextField(
                    controller: _explanation,
                    label: 'Explanation',
                    maxLines: 3,
                  ),
                ],
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: targets.isEmpty ? null : _save,
          child: const Text('Add'),
        ),
      ],
    );
  }

  /// Saves the explicit relation through graph-backed context tools.
  Future<void> _save() async {
    if (_targetTaskId.isEmpty) {
      return;
    }
    await widget.controller.upsertTaskRelationFromUi(
      fromTaskId: widget.task.id,
      toTaskId: _targetTaskId,
      relationType: _relationType,
      explanation: _explanation.text.trim(),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
