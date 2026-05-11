/// Backlog explicit relation and commitment tile widgets.
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
          Tooltip(
            message: 'Delete relation',
            child: IconButton(
              onPressed: controller.tasksBusy
                  ? null
                  : () => unawaited(_deleteRelation(context, relation)),
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
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

class _TaskCommitmentTile extends StatelessWidget {
  const _TaskCommitmentTile({
    required this.controller,
    required this.task,
    required this.commitment,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;
  final TaskCommitment commitment;

  /// Builds one first-class commitment row.
  @override
  Widget build(BuildContext context) {
    final title = commitment.project.isNotEmpty
        ? commitment.project
        : commitment.domain.isNotEmpty
        ? commitment.domain
        : task.title;
    final subtitleParts = <String>[
      if (commitment.timeWindow.isNotEmpty) commitment.timeWindow,
      if (commitment.responsibility.isNotEmpty) commitment.responsibility,
      if (commitment.promiseSource.isNotEmpty) commitment.promiseSource,
      if (commitment.consequence.isNotEmpty) commitment.consequence,
    ];
    final canUpsertCommitment = controller.primaryMemoryToolAvailable(
      'upsert_commitment',
    );
    final canDeleteCommitment = controller.primaryMemoryToolAvailable(
      'delete_commitment',
    );
    return _TaskGraphRow(
      icon: Icons.handshake_outlined,
      title: title,
      subtitle: subtitleParts.join(' • '),
      badges: <String>[
        for (final person in commitment.people.take(3)) person,
        if (commitment.hardness.isNotEmpty) _taskLabel(commitment.hardness),
      ],
      actions: <Widget>[
        if (canUpsertCommitment)
          Tooltip(
            message: 'Edit commitment',
            child: IconButton(
              onPressed: controller.tasksBusy
                  ? null
                  : () => unawaited(
                      _showTaskCommitmentDialog(
                        context,
                        controller,
                        task,
                        commitment: commitment,
                      ),
                    ),
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          ),
        if (canDeleteCommitment)
          Tooltip(
            message: 'Delete commitment',
            child: IconButton(
              onPressed: controller.tasksBusy
                  ? null
                  : () => unawaited(_deleteCommitment(context, commitment)),
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ),
      ],
    );
  }

  Future<void> _deleteCommitment(
    BuildContext context,
    TaskCommitment commitment,
  ) async {
    if (!await _confirmTaskWrite(context, 'Delete this commitment?')) {
      return;
    }
    await controller.deleteTaskCommitmentFromUi(commitment);
  }
}
