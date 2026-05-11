/// Backlog selected-task graph details widget.
part of 'backlog_section.dart';

class _TaskGraphDetailsBlock extends StatelessWidget {
  const _TaskGraphDetailsBlock({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  /// Builds relationship, suggestion, and commitment controls.
  @override
  Widget build(BuildContext context) {
    final relationSuggestions = controller.selectedTaskRelationSuggestions;
    final metadataSuggestions = controller.selectedTaskMetadataSuggestions;
    final commitmentSuggestions = controller.selectedTaskCommitmentSuggestions;
    final relations = controller.selectedTaskRelations;
    final commitments = controller.selectedTaskCommitments;
    final canUpsertRelation = controller.primaryMemoryToolAvailable(
      'upsert_task_relation',
    );
    final canUpsertCommitment = controller.primaryMemoryToolAvailable(
      'upsert_commitment',
    );
    final suggestionWidgets = <Widget>[
      for (final suggestion in relationSuggestions)
        _TaskRelationSuggestionTile(
          controller: controller,
          task: task,
          suggestion: suggestion,
        ),
      for (final suggestion in metadataSuggestions)
        _TaskMetadataSuggestionTile(
          controller: controller,
          suggestion: suggestion,
        ),
      for (final suggestion in commitmentSuggestions)
        _TaskCommitmentSuggestionTile(
          controller: controller,
          suggestion: suggestion,
        ),
    ];
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: _TaskPanelLabel('Graph')),
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
              if (canUpsertCommitment)
                Tooltip(
                  message: 'Add commitment',
                  child: IconButton(
                    onPressed: controller.tasksBusy
                        ? null
                        : () => unawaited(
                            _showTaskCommitmentDialog(
                              context,
                              controller,
                              task,
                            ),
                          ),
                    icon: const Icon(Icons.handshake_outlined, size: 18),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _TaskGraphSubsection(
            title: 'Suggestions',
            emptyLabel: 'No graph suggestions',
            children: suggestionWidgets,
          ),
          const Divider(height: 22),
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
          const Divider(height: 22),
          _TaskGraphSubsection(
            title: 'Commitments',
            emptyLabel: 'No first-class commitments',
            children: <Widget>[
              for (final commitment in commitments)
                _TaskCommitmentTile(
                  controller: controller,
                  task: task,
                  commitment: commitment,
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
