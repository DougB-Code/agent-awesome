/// Backlog task search, queue, and insight-preset helpers.
part of 'backlog_section.dart';

/// Confirms a context write operation.
Future<bool> _confirmTaskWrite(BuildContext context, String message) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Confirm Change'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );
  return approved ?? false;
}

/// Returns whether a backlog item matches a panel query.
bool _matchesTask(WorkspaceTask task, String query) {
  return _matchesText(
    '${task.title} ${task.description} ${task.status} ${task.priority} '
    '${task.sourceLabel} ${task.topics.join(' ')}',
    query,
  );
}

/// Returns graph task ids for the active Queue insight preset.
Set<String> _queuePresetTaskIds(AgentAwesomeAppController controller) {
  final presetId = controller.taskInsightPresetId;
  if (presetId == TaskInsightIds.all) {
    return const <String>{};
  }
  return controller.taskInsightIndex
      .tasksForInsight(presetId)
      .map((candidate) => candidate.taskId)
      .toSet();
}

/// Returns compact insight badges for one queue backlog item.
List<String> _insightBadgesForTask(
  AgentAwesomeAppController controller,
  WorkspaceTask task,
) {
  final taskId = task.id;
  final badges = <String>[];
  if (controller.taskInsightIndex.candidateForTask(
        taskId,
        TaskInsightIds.agentHandoff,
      ) !=
      null) {
    final score = controller.taskInsightIndex.scoresFor(taskId);
    badges.add(
      (score?.agentSafety ?? 0) >=
              controller.taskInsightIndex.policy.safeAgentThreshold
          ? 'Agent-ready'
          : 'Needs review',
    );
  }
  final downstream = controller.taskInsightIndex.downstreamTasksFor(taskId);
  if (downstream.isNotEmpty) {
    badges.add('Blocks ${downstream.length}');
  }
  final gaps = controller.taskInsightIndex.metadataGapsFor(taskId);
  if (gaps.isNotEmpty) {
    badges.add('Missing ${gaps.first.field.replaceAll('_', ' ')}');
  }
  return badges.take(3).toList();
}

/// Returns the local date used by queue quick actions.
DateTime _todayDate() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Returns the task card accent color from the displayed score band.
Color _taskQueueAccentColor(BuildContext context, WorkspaceTask task) {
  return _taskQueueScoreColor(context, _taskQueueScore(task));
}

/// Returns a compact task description for queue cards.
String _taskQueueDescription(WorkspaceTask task) {
  if (task.description.trim().isNotEmpty) {
    return task.description.trim();
  }
  if (task.detail.trim().isNotEmpty) {
    return task.detail.trim();
  }
  if (task.dueAt == null && task.scheduledAt == null) {
    return 'No date is attached yet.';
  }
  return '';
}

/// Returns the suggested next action for a queue card.
String _taskSuggestedAction(WorkspaceTask task) {
  if (task.done) {
    return 'Already complete';
  }
  if (task.status == 'blocked') {
    return 'Clarify the blocker';
  }
  if (task.status == 'waiting') {
    return 'Follow up or snooze';
  }
  if (task.scheduledAt == null) {
    return 'Schedule for today';
  }
  return 'Mark done when finished';
}

/// Returns the action category label for a queue card.
String _taskActionTypeLabel(WorkspaceTask task) {
  if (task.status == 'blocked' || task.description.trim().isEmpty) {
    return 'Clarify';
  }
  if (task.scheduledAt == null) {
    return 'Schedule';
  }
  return 'Do';
}

/// Returns the action category icon for a queue card.
IconData _taskActionTypeIcon(WorkspaceTask task) {
  if (task.status == 'blocked' || task.description.trim().isEmpty) {
    return Icons.format_list_bulleted_add;
  }
  if (task.scheduledAt == null) {
    return Icons.calendar_today_outlined;
  }
  return Icons.task_alt_outlined;
}

/// Returns a simple queue priority score for attention-style display.
int _taskQueueScore(WorkspaceTask task) {
  var score = 48;
  if (task.overdue) {
    score += 22;
  }
  if (task.dueAt == null && task.scheduledAt == null) {
    score += 10;
  }
  if (task.priority == 'urgent') {
    score += 22;
  } else if (task.priority == 'high') {
    score += 15;
  } else if (task.priority == 'low') {
    score -= 8;
  }
  if (task.status == 'blocked') {
    score += 12;
  }
  if (task.description.trim().isEmpty) {
    score += 8;
  }
  return score.clamp(0, 99);
}

/// Returns the queue score band label.
String _taskQueueScoreLabel(int score) {
  if (score >= 75) {
    return 'High';
  }
  if (score >= 55) {
    return 'Medium';
  }
  return 'Low';
}

/// Returns the queue score band color.
Color _taskQueueScoreColor(BuildContext context, int score) {
  final colors = context.agentAwesomeColors;
  if (score >= 75) {
    return colors.coral;
  }
  if (score >= 55) {
    return context.agentAwesomeWarningAccent;
  }
  return context.agentAwesomeLowAccent;
}

/// Returns memory links filtered by the panel query.
List<TaskMemoryLink> _filteredLinks(List<TaskMemoryLink> links, String query) {
  return links.where((link) {
    return _matchesText(
      '${link.relationship} ${link.note} ${link.memoryId} '
      '${link.memoryEvidenceId}',
      query,
    );
  }).toList();
}

/// Returns whether text contains every query character in order.
bool _matchesText(String value, String query) {
  final normalizedValue = value.toLowerCase();
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }
  var cursor = 0;
  for (final codeUnit in normalizedQuery.codeUnits) {
    cursor = normalizedValue.indexOf(String.fromCharCode(codeUnit), cursor);
    if (cursor == -1) {
      return false;
    }
    cursor++;
  }
  return true;
}

/// Returns the selected semantic Queue preset, falling back to All.
TaskInsightPreset _selectedTaskInsightPreset(
  AgentAwesomeAppController controller,
) {
  for (final preset in TaskInsightPresetRegistry.queuePresets) {
    if (preset.id == controller.taskInsightPresetId) {
      return preset;
    }
  }
  return TaskInsightPresetRegistry.queuePresets.first;
}
