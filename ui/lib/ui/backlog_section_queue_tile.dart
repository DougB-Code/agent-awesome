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
    final accentColor = _taskQueueAccentColor(context, task);
    final description = _taskQueueDescription(task);
    final borderColor = selected
        ? colors.borderStrong
        : focused
        ? colors.borderStrong
        : changes.isNotEmpty
        ? colors.warningText
        : colors.border;
    final borderWidth = focused || changes.isNotEmpty ? 1.25 : 1.0;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(width: 3, color: accentColor),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  task.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                if (description.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 8),
                                  Text(
                                    description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: colors.muted),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: <Widget>[
                                    _TaskBadge(label: _taskLabel(task.status)),
                                    _TaskBadge(
                                      label: _taskLabel(task.priority),
                                    ),
                                    if (task.overdue)
                                      const _TaskBadge(label: 'Overdue'),
                                    if (task.dueAt == null)
                                      const _TaskBadge(label: 'No due date')
                                    else
                                      _TaskBadge(
                                        label:
                                            'Due ${formatOptionalLocalDate(task.dueAt)}',
                                      ),
                                    if (task.scheduledAt != null)
                                      _TaskBadge(
                                        label:
                                            'Scheduled ${formatOptionalLocalDate(task.scheduledAt)}',
                                      ),
                                    if (task.estimateMinutes > 0)
                                      _TaskBadge(
                                        label: '${task.estimateMinutes} min',
                                      ),
                                    if (task.project.isEmpty)
                                      const _TaskBadge(label: 'No project'),
                                    if (task.memoryLinks.isNotEmpty)
                                      _TaskBadge(
                                        label:
                                            '${task.memoryLinks.length} memories',
                                      ),
                                    if (task.sourceLabel.isNotEmpty)
                                      _TaskBadge(label: task.sourceLabel),
                                    for (final topic in task.topics.take(3))
                                      _TaskBadge(label: topic),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _TaskQueueTileActions(
                            controller: controller,
                            task: task,
                          ),
                        ],
                      ),
                    ),
                    if (changes.isNotEmpty) ...<Widget>[
                      Divider(height: 1, color: colors.border),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: _TaskTileScreenChanges(changes: changes),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
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
