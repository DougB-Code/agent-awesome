/// Route parsing, filtering, display, and action helpers for attention items.
part of 'attention_screen.dart';

/// _attentionScopeForRoute parses a reserved Today attention route.
_AttentionScope _attentionScopeForRoute(String route) {
  final uri = _safeUri(route);
  final metric = uri.queryParameters['metric'] ?? '';
  final lane = uri.queryParameters['lane'] ?? '';
  final itemId = uri.queryParameters['item'] ?? '';
  if (metric == 'actions') {
    return _AttentionScope(
      metric: metric,
      lanes: const <String>{'protect', 'do'},
      itemId: itemId,
    );
  }
  if (metric == 'decisions') {
    return _AttentionScope(
      metric: metric,
      lanes: const <String>{'decide'},
      itemId: itemId,
    );
  }
  if (metric == 'relationships') {
    return _AttentionScope(
      metric: metric,
      lanes: const <String>{'follow_up'},
      itemId: itemId,
    );
  }
  if (lane == 'do') {
    return _AttentionScope(
      metric: 'actions',
      lanes: const <String>{'protect', 'do'},
      itemId: itemId,
    );
  }
  if (lane.isNotEmpty) {
    return _AttentionScope(metric: lane, lanes: <String>{lane}, itemId: itemId);
  }
  return _AttentionScope(
    metric: metric,
    lanes: const <String>{},
    itemId: itemId,
  );
}

/// _safeUri parses route strings without throwing during UI builds.
Uri _safeUri(String route) {
  try {
    return Uri.parse(route.isEmpty ? '/attention' : route);
  } catch (_) {
    return Uri.parse('/attention');
  }
}

/// _itemsForScope filters attention items by route scope.
List<ExecutiveSummaryItem> _itemsForScope(
  List<ExecutiveSummaryItem> items,
  _AttentionScope scope,
) {
  if (scope.lanes.isEmpty) {
    return items;
  }
  return items.where((item) => scope.lanes.contains(item.lane)).toList();
}

/// _itemsForFilter filters attention items by local category.
List<ExecutiveSummaryItem> _itemsForFilter(
  List<ExecutiveSummaryItem> items,
  _AttentionFilter filter,
) {
  switch (filter) {
    case _AttentionFilter.all:
      return items;
    case _AttentionFilter.execute:
      return items.where((item) {
        return item.lane == 'do' || item.lane == 'protect';
      }).toList();
    case _AttentionFilter.clarify:
      return items.where(_itemNeedsClarification).toList();
    case _AttentionFilter.schedule:
      return items.where(_itemNeedsSchedule).toList();
    case _AttentionFilter.review:
      return items.where((item) {
        return item.lane == 'decide' || item.lane == 'monitor';
      }).toList();
  }
}

/// _selectedItem resolves the details selection from filtered items and route.
ExecutiveSummaryItem? _selectedItem(
  List<ExecutiveSummaryItem> filteredItems,
  List<ExecutiveSummaryItem> scopedItems,
  String selectedItemId,
) {
  for (final item in filteredItems) {
    if (_itemMatchesSelection(item, selectedItemId)) {
      return item;
    }
  }
  for (final item in scopedItems) {
    if (_itemMatchesSelection(item, selectedItemId)) {
      return item;
    }
  }
  return filteredItems.isEmpty ? null : filteredItems.first;
}

/// _itemMatchesSelection compares item id, task id, and projection link ids.
bool _itemMatchesSelection(ExecutiveSummaryItem item, String selectedItemId) {
  if (selectedItemId.isEmpty) {
    return false;
  }
  if (item.id == selectedItemId || item.taskId == selectedItemId) {
    return true;
  }
  return item.links.any((link) {
    final routeItem = _safeUri(link.route).queryParameters['item'] ?? '';
    return routeItem == selectedItemId;
  });
}

/// _itemNeedsClarification identifies items with missing action context.
bool _itemNeedsClarification(ExecutiveSummaryItem item) {
  return item.project.isEmpty ||
      item.reason.toLowerCase().contains('missing') ||
      item.subtitle.toLowerCase().contains('missing');
}

/// _itemNeedsSchedule identifies unscheduled items.
bool _itemNeedsSchedule(ExecutiveSummaryItem item) {
  return item.dueAt == null &&
      item.scheduledAt == null &&
      item.followUpAt == null;
}

/// _titleForScope creates the page title for the current route scope.
String _titleForScope(_AttentionScope scope, int count) {
  switch (scope.metric) {
    case 'actions':
      return '$count ${_plural(count, 'item')} ready to execute';
    case 'decisions':
    case 'decide':
      return '$count ${_plural(count, 'decision')} require your input';
    case 'relationships':
    case 'follow_up':
      return '$count ${_plural(count, 'follow-up')} need your care';
    default:
      return '$count attention ${_plural(count, 'item')} need your attention';
  }
}

/// _subtitleForScope returns supporting copy for the current route scope.
String _subtitleForScope(_AttentionScope scope) {
  switch (scope.metric) {
    case 'actions':
      return 'These tasks are ready for concrete execution today or soon.';
    case 'decisions':
    case 'decide':
      return 'These tasks need a choice before work can move cleanly.';
    case 'relationships':
    case 'follow_up':
      return 'These loops involve a person, promise, reply, or check-in.';
    default:
      return 'These items are ranked by what most needs your attention now.';
  }
}

/// _plural returns a singular or plural noun.
String _plural(int count, String noun) {
  return count == 1 ? noun : '${noun}s';
}

/// _filterLabel returns the display label for a local filter.
String _filterLabel(_AttentionFilter filter) {
  switch (filter) {
    case _AttentionFilter.all:
      return 'All';
    case _AttentionFilter.execute:
      return 'Execute now';
    case _AttentionFilter.clarify:
      return 'Clarify';
    case _AttentionFilter.schedule:
      return 'Schedule';
    case _AttentionFilter.review:
      return 'Review';
  }
}

/// _filterSubtitle returns the supporting label for a local filter.
String _filterSubtitle(_AttentionFilter filter) {
  switch (filter) {
    case _AttentionFilter.all:
      return 'Everything';
    case _AttentionFilter.execute:
      return 'Concrete action';
    case _AttentionFilter.clarify:
      return 'Needs more info';
    case _AttentionFilter.schedule:
      return 'Plan it';
    case _AttentionFilter.review:
      return 'Needs review';
  }
}

/// _filterIcon returns the icon for a local filter.
IconData _filterIcon(_AttentionFilter filter) {
  switch (filter) {
    case _AttentionFilter.all:
      return Icons.inbox_outlined;
    case _AttentionFilter.execute:
      return Icons.task_alt;
    case _AttentionFilter.clarify:
      return Icons.edit_note;
    case _AttentionFilter.schedule:
      return Icons.calendar_today_outlined;
    case _AttentionFilter.review:
      return Icons.rate_review_outlined;
  }
}

/// _filterSeverity returns the semantic color for a local filter.
String _filterSeverity(_AttentionFilter filter) {
  switch (filter) {
    case _AttentionFilter.clarify:
    case _AttentionFilter.review:
      return 'attention';
    case _AttentionFilter.schedule:
      return 'warning';
    case _AttentionFilter.execute:
    case _AttentionFilter.all:
      return 'good';
  }
}

/// _updatedLabel formats the projection refresh timestamp.
String _updatedLabel(DateTime? timestamp) {
  if (timestamp == null) {
    return 'Updated just now';
  }
  final local = timestamp.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return 'Updated $hour:$minute';
}

/// _detailSubtitle returns the visible reason summary for an item.
String _detailSubtitle(ExecutiveSummaryItem item) {
  if (item.subtitle.trim().isNotEmpty) {
    return item.subtitle.trim();
  }
  return item.reason.trim();
}

/// _reasonText returns a non-empty item explanation.
String _reasonText(ExecutiveSummaryItem item) {
  final reason = item.reason.trim();
  if (reason.isNotEmpty) {
    return reason;
  }
  final subtitle = item.subtitle.trim();
  return subtitle.isEmpty ? 'Ranked by the Today attention policy.' : subtitle;
}

/// _primaryActionLabel returns the preferred action label for an item.
String _primaryActionLabel(ExecutiveSummaryItem item) {
  final action = item.primaryAction;
  if (action != null && action.label.trim().isNotEmpty) {
    return action.label.trim();
  }
  if (item.actions.isNotEmpty && item.actions.first.label.trim().isNotEmpty) {
    return item.actions.first.label.trim();
  }
  switch (item.lane) {
    case 'decide':
      return 'Make or defer the decision';
    case 'protect':
      return 'Protect time for this';
    case 'follow_up':
      return 'Follow up with the person';
    case 'delegate':
      return 'Delegate the next step';
    default:
      return 'Open the task';
  }
}

/// _requiredAttention summarizes what kind of attention is required.
String _requiredAttention(ExecutiveSummaryItem item) {
  switch (item.lane) {
    case 'decide':
      return 'Decide, defer, or split the work.';
    case 'protect':
      return 'Protect focus time or unblock the schedule.';
    case 'follow_up':
      return 'Reply, follow up, or close the loop.';
    case 'delegate':
      return 'Assign the next step or approve delegation.';
    case 'monitor':
      return 'Review the signal and keep it visible.';
    default:
      return 'Complete, schedule, or dismiss.';
  }
}

/// _itemTags creates compact metadata tags for one item.
List<String> _itemTags(ExecutiveSummaryItem item) {
  final tags = <String>[];
  if (item.status.trim().isNotEmpty) {
    tags.add(_titleCase(item.status));
  }
  if (_itemNeedsSchedule(item)) {
    tags.add('No date');
  }
  if (item.estimateMinutes > 0) {
    tags.add(_formatMinutes(item.estimateMinutes));
  }
  if (item.project.trim().isEmpty) {
    tags.add('No project');
  } else {
    tags.add(item.project.trim());
  }
  if (item.priority.trim().isNotEmpty && item.priority != 'normal') {
    tags.add(_titleCase(item.priority));
  }
  return tags;
}

/// _sourceBullets combines explicit source handles and attention factors.
List<String> _sourceBullets(ExecutiveSummaryItem item) {
  final bullets = <String>[
    for (final source in item.evidence)
      source.label.trim().isEmpty ? source.id.trim() : source.label.trim(),
  ]..removeWhere((value) => value.isEmpty);
  if (item.status.trim().isNotEmpty) {
    bullets.add('${_titleCase(item.status)} task');
  }
  if (item.dueAt == null) {
    bullets.add('No due date');
  }
  if (item.scheduledAt == null) {
    bullets.add('No scheduled date');
  }
  if (item.estimateMinutes > 0) {
    bullets.add(_formatMinutes(item.estimateMinutes));
  }
  if (item.project.trim().isEmpty) {
    bullets.add('No project relation');
  }
  return bullets;
}

/// _canCompleteItem reports whether a row can invoke complete_task safely.
bool _canCompleteItem(ExecutiveSummaryItem item) {
  final taskId = _taskIdForItem(item);
  if (taskId.isEmpty) {
    return false;
  }
  final action = item.primaryAction;
  if (action != null && action.tool == 'complete_task') {
    return true;
  }
  return item.lane == 'do';
}

/// _taskIdForItem returns the linked task id from item fields or action payload.
String _taskIdForItem(ExecutiveSummaryItem item) {
  if (item.taskId.trim().isNotEmpty) {
    return item.taskId.trim();
  }
  final payloadTask = item.primaryAction?.payload['task_id'];
  if (payloadTask is String && payloadTask.trim().isNotEmpty) {
    return payloadTask.trim();
  }
  for (final link in item.links) {
    final routeItem = _safeUri(link.route).queryParameters['item'] ?? '';
    if (routeItem.isNotEmpty) {
      return routeItem;
    }
  }
  return '';
}

/// _scorePercent converts a normalized score to an integer percent.
int _scorePercent(double score) {
  return (score.clamp(0, 1) * 100).round();
}

/// _scoreLabel maps a normalized score to a severity label.
String _scoreLabel(double score) {
  if (score >= 0.75) {
    return 'High';
  }
  if (score >= 0.45) {
    return 'Medium';
  }
  return 'Low';
}

/// _confidencePercent converts confidence to an integer percent.
int _confidencePercent(double confidence) {
  return (confidence.clamp(0, 1) * 100).round();
}

/// _statusText resolves item or task status.
String _statusText(ExecutiveSummaryItem item, WorkspaceTask? task) {
  return _fallbackText(item.status, task?.status ?? '-');
}

/// _priorityText resolves item or task priority.
String _priorityText(ExecutiveSummaryItem item, WorkspaceTask? task) {
  return _fallbackText(item.priority, task?.priority ?? '-');
}

/// _fallbackText returns a trimmed value or fallback.
String _fallbackText(String value, String fallback) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : _titleCase(trimmed);
}

/// _formatMinutes formats an estimate as compact effort text.
String _formatMinutes(int minutes) {
  if (minutes < 60) {
    return '$minutes min';
  }
  final hours = minutes / 60;
  return '${hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1)} hr';
}

/// _titleCase converts identifier-like text to human display text.
String _titleCase(String value) {
  final words = value
      .replaceAll('_', ' ')
      .split(' ')
      .where((word) => word.trim().isNotEmpty)
      .toList();
  return words
      .map((word) {
        final lower = word.toLowerCase();
        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
}
