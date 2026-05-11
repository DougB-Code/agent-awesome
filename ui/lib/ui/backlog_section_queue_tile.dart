/// Backlog queue tile and quick action widgets.
part of 'backlog_section.dart';

class _TaskQueueTile extends StatelessWidget {
  const _TaskQueueTile({
    required this.task,
    required this.selected,
    required this.focused,
    required this.changes,
    required this.onTap,
    required this.onScheduleToday,
    required this.onSnooze,
    required this.onComplete,
    required this.onDelete,
    required this.insightBadges,
  });

  final WorkspaceTask task;
  final bool selected;
  final bool focused;
  final List<ScreenChange> changes;
  final VoidCallback onTap;
  final VoidCallback onScheduleToday;
  final VoidCallback onSnooze;
  final VoidCallback? onComplete;
  final VoidCallback onDelete;
  final List<String> insightBadges;

  /// Builds one selectable context row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accentColor = _taskQueueAccentColor(context, task);
    final description = _taskQueueDescription(task);
    final suggestedAction = _taskSuggestedAction(task);
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
          gradient: context.agentAwesomeCardGradient,
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(width: 4, color: accentColor),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _TaskActionTypeBadge(task: task),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  task.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
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
                                const SizedBox(height: 8),
                                _TaskSuggestedActionLine(
                                  label: suggestedAction,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: <Widget>[
                                    _TaskBadge(label: _taskLabel(task.status)),
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
                                    for (final badge in insightBadges)
                                      _TaskBadge(label: badge),
                                    for (final topic in task.topics.take(3))
                                      _TaskBadge(label: topic),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _TaskQueueScoreBlock(task: task),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: colors.border),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Row(
                        children: <Widget>[
                          _TaskQuickActionButton(
                            label: 'Schedule',
                            icon: Icons.today_outlined,
                            filled: task.scheduledAt == null,
                            onPressed: onScheduleToday,
                          ),
                          const SizedBox(width: 8),
                          _TaskQuickActionButton(
                            label: 'Mark done',
                            icon: Icons.check,
                            onPressed: onComplete,
                          ),
                          const SizedBox(width: 8),
                          _TaskQuickActionButton(
                            label: 'Snooze',
                            icon: Icons.schedule_outlined,
                            onPressed: onSnooze,
                          ),
                          const Spacer(),
                          Tooltip(
                            message: 'Delete backlog item',
                            child: TextButton.icon(
                              onPressed: onDelete,
                              icon: const Icon(Icons.delete_outline, size: 17),
                              label: const Text('Dismiss'),
                            ),
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

/// _TaskActionTypeBadge renders the queue action category for one task.
class _TaskActionTypeBadge extends StatelessWidget {
  const _TaskActionTypeBadge({required this.task});

  final WorkspaceTask task;

  /// Builds the compact action-type badge.
  @override
  Widget build(BuildContext context) {
    final label = _taskActionTypeLabel(task);
    final icon = _taskActionTypeIcon(task);
    final accent = _taskQueueAccentColor(context, task);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// _TaskSuggestedActionLine renders the recommended next action text.
class _TaskSuggestedActionLine extends StatelessWidget {
  const _TaskSuggestedActionLine({required this.label});

  final String label;

  /// Builds the suggested-action copy.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(
          context,
        ).style.copyWith(color: colors.ink, fontWeight: FontWeight.w800),
        children: <InlineSpan>[
          const TextSpan(text: 'Suggested next action: '),
          TextSpan(
            text: label,
            style: TextStyle(color: colors.green, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

/// _TaskQueueScoreBlock renders a compact attention-style queue score.
class _TaskQueueScoreBlock extends StatelessWidget {
  const _TaskQueueScoreBlock({required this.task});

  final WorkspaceTask task;

  /// Builds a score and urgency label for the queue tile.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final score = _taskQueueScore(task);
    final label = _taskQueueScoreLabel(score);
    final labelColor = _taskQueueScoreColor(context, score);
    return SizedBox(
      width: 86,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            'Queue score',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: colors.ink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            score.toString(),
            style: TextStyle(
              color: colors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// _TaskQuickActionButton renders one queue-row quick action.
class _TaskQuickActionButton extends StatelessWidget {
  const _TaskQuickActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;

  /// Builds a compact action button for queue items.
  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
