/// Backlog task search and queue helpers.
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

/// Returns the local date used by selected-task scheduling actions.
DateTime _todayDate() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Returns a compact task description for queue cards.
String _taskQueueDescription(WorkspaceTask task) {
  if (task.description.trim().isNotEmpty) {
    return task.description.trim();
  }
  final detail = _taskQueueDetailWithoutStatus(task);
  if (detail.isNotEmpty) {
    return detail;
  }
  if (task.dueAt == null && task.scheduledAt == null) {
    return 'No date is attached yet.';
  }
  return '';
}

/// Returns secondary queue text without duplicating the status badge.
String _taskQueueDetailWithoutStatus(WorkspaceTask task) {
  final detail = task.detail.trim();
  if (detail.isEmpty) {
    return '';
  }
  final statusLabels = <String>{
    task.status.trim().toLowerCase(),
    _taskLabel(task.status).trim().toLowerCase(),
  };
  final parts = detail
      .split('•')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .where((part) => !statusLabels.contains(part.toLowerCase()))
      .toList();
  return parts.join(' • ');
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
