/// Backlog explicit relation tile widgets.
part of 'backlog_section.dart';

class _TaskRelationTile extends StatelessWidget {
  const _TaskRelationTile({
    required this.controller,
    required this.task,
    required this.relation,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;
  final TaskRelationRecord relation;

  /// Builds one explicit relation row.
  @override
  Widget build(BuildContext context) {
    final outgoing = relation.fromTaskId == task.id;
    final otherId = outgoing ? relation.toTaskId : relation.fromTaskId;
    final direction = outgoing ? 'To' : 'From';
    final canDeleteRelation = controller.primaryMemoryToolAvailable(
      'delete_task_relation',
    );
    return _TaskGraphRow(
      icon: outgoing ? Icons.arrow_forward : Icons.arrow_back,
      title: '$direction ${_taskTitleFor(controller, otherId)}',
      subtitle: relation.explanation,
      badges: <String>[
        _taskLabel(relation.relationType),
        relation.source.isEmpty ? 'Explicit' : _taskLabel(relation.source),
        _formatTaskScore(relation.confidence),
      ],
      actions: <Widget>[
        if (canDeleteRelation)
          PanelInlineIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete relation',
            onPressed: controller.tasksBusy
                ? null
                : () => unawaited(_deleteRelation(context, relation)),
          ),
      ],
    );
  }

  Future<void> _deleteRelation(
    BuildContext context,
    TaskRelationRecord relation,
  ) async {
    if (!await _confirmTaskWrite(context, 'Delete this backlog relation?')) {
      return;
    }
    await controller.deleteTaskRelationFromUi(relation);
  }
}
