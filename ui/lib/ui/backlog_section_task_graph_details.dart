/// Backlog selected-task graph details widget.
part of 'backlog_section.dart';

class _TaskGraphDetailsBlock extends StatelessWidget {
  const _TaskGraphDetailsBlock({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  /// Builds relationship controls.
  @override
  Widget build(BuildContext context) {
    final relations = controller.selectedTaskRelations;
    final canUpsertRelation = controller.primaryMemoryToolAvailable(
      'upsert_task_relation',
    );
    return PanelSectionBlock.gradient(
      title: 'Graph',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (canUpsertRelation)
            Tooltip(
              message: 'Add relation',
              child: IconButton(
                onPressed: controller.tasksBusy
                    ? null
                    : () => unawaited(
                        _showTaskRelationDialog(context, controller, task),
                      ),
                icon: const Icon(Icons.account_tree_outlined, size: 18),
              ),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TaskGraphSubsection(
            title: 'Relations',
            emptyLabel: 'No explicit relations',
            children: <Widget>[
              for (final relation in relations)
                _TaskRelationTile(
                  controller: controller,
                  task: task,
                  relation: relation,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskGraphSubsection extends StatelessWidget {
  const _TaskGraphSubsection({
    required this.title,
    required this.emptyLabel,
    required this.children,
  });

  final String title;
  final String emptyLabel;
  final List<Widget> children;

  /// Builds one compact graph data subsection.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (children.isEmpty)
          Text(
            emptyLabel,
            style: TextStyle(color: context.agentAwesomeColors.muted),
          )
        else
          ...children,
      ],
    );
  }
}
