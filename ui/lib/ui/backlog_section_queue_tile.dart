/// Backlog queue tile widgets.
part of 'backlog_section.dart';

class _TaskQueueTile extends StatelessWidget {
  const _TaskQueueTile({
    required this.controller,
    required this.task,
    required this.selected,
    required this.focused,
    required this.changes,
    required this.onTap,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;
  final bool selected;
  final bool focused;
  final List<ScreenChange> changes;
  final VoidCallback onTap;

  /// Builds one selectable context row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final description = _taskQueueDescription(task);
    return PanelSelectorTile(
      label: task.title,
      icon: Icons.task_alt_outlined,
      detail: description,
      selected: selected || focused,
      onTap: onTap,
      trailing: _TaskQueueTileActions(controller: controller, task: task),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _TaskBadge(label: _taskLabel(task.status)),
              _TaskBadge(label: _taskLabel(task.priority)),
              if (task.overdue) const _TaskBadge(label: 'Overdue'),
              if (task.dueAt == null)
                const _TaskBadge(label: 'No due date')
              else
                _TaskBadge(label: 'Due ${formatOptionalLocalDate(task.dueAt)}'),
              if (task.scheduledAt != null)
                _TaskBadge(
                  label:
                      'Scheduled ${formatOptionalLocalDate(task.scheduledAt)}',
                ),
              if (task.estimateMinutes > 0)
                _TaskBadge(label: '${task.estimateMinutes} min'),
              if (task.project.isEmpty) const _TaskBadge(label: 'No project'),
              if (task.memoryLinks.isNotEmpty)
                _TaskBadge(label: '${task.memoryLinks.length} memories'),
              if (task.sourceLabel.isNotEmpty)
                _TaskBadge(label: task.sourceLabel),
              for (final topic in task.topics.take(3)) _TaskBadge(label: topic),
            ],
          ),
          if (changes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: 10),
            _TaskTileScreenChanges(changes: changes),
          ],
        ],
      ),
    );
  }
}

class _TaskQueueTileActions extends StatelessWidget {
  const _TaskQueueTileActions({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  /// Builds compact row-level actions for one backlog item.
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PanelInlineIconButton(
          icon: Icons.content_copy,
          tooltip: 'Copy backlog item title',
          onPressed: () {
            unawaited(Clipboard.setData(ClipboardData(text: task.title)));
          },
        ),
        const SizedBox(width: 6),
        PanelInlineIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete backlog item',
          onPressed: controller.tasksBusy
              ? null
              : () => unawaited(_delete(context)),
        ),
      ],
    );
  }

  /// Deletes this backlog item after confirmation.
  Future<void> _delete(BuildContext context) async {
    if (!await _confirmTaskWrite(
      context,
      'Delete backlog item "${task.title}"?',
    )) {
      return;
    }
    await controller.deleteTaskFromUi(task.id);
  }
}
