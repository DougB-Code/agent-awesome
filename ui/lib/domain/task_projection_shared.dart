/// Shared projection helper functions.
part of 'task_projection_adapters.dart';

String _dueWindow(DateTime? dueAt, DateTime now) {
  if (dueAt == null) {
    return 'no-due-date';
  }
  final localDue = DateTime(dueAt.year, dueAt.month, dueAt.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = localDue.difference(today).inDays;
  if (days < 0) {
    return 'overdue';
  }
  if (days == 0) {
    return 'today';
  }
  if (days == 1) {
    return 'tomorrow';
  }
  if (days < 7) {
    return 'this-week';
  }
  if (days < 14) {
    return 'next-week';
  }
  return 'later';
}

/// Returns projection facets keyed by stable id.
Map<String, TaskProjectionFacet> _facetsById(TaskProjectionGraph graph) {
  return <String, TaskProjectionFacet>{
    for (final facet in graph.facets) facet.id: facet,
  };
}

/// Returns the first facet label for a task and dimension.
String _facetLabelForTask(
  TaskProjectionTask task,
  Map<String, TaskProjectionFacet> facets,
  String dimension,
) {
  for (final facetId in task.facetIds) {
    final facet = facets[facetId];
    if (facet != null && facet.dimension == dimension) {
      return facet.label;
    }
  }
  return '';
}

/// Returns the first facet id suffix for a task and dimension.
String _facetIDSuffixForTask(
  TaskProjectionTask task,
  Map<String, TaskProjectionFacet> facets,
  String dimension,
  String fallback,
) {
  for (final facetId in task.facetIds) {
    final facet = facets[facetId];
    if (facet == null || facet.dimension != dimension) {
      continue;
    }
    final index = facet.id.indexOf(':');
    return index >= 0 ? facet.id.substring(index + 1) : facet.id;
  }
  return fallback;
}

/// Counts sparse edges touching each task.
Map<String, int> _relationCounts(List<TaskProjectionEdge> edges) {
  final counts = <String, int>{};
  for (final edge in edges) {
    counts[edge.fromTaskId] = (counts[edge.fromTaskId] ?? 0) + 1;
    counts[edge.toTaskId] = (counts[edge.toTaskId] ?? 0) + 1;
  }
  return counts;
}

/// Builds visible stream links from sparse task edges.
List<TaskStreamLink> _streamLinks(
  List<TaskProjectionEdge> edges,
  Map<String, TaskStreamCard> visibleCards,
) {
  final links = <TaskStreamLink>[];
  for (final edge in edges) {
    final link = _streamLink(edge, visibleCards);
    if (link != null) {
      links.add(link);
    }
  }
  links.sort((left, right) {
    final fromCompare = left.fromTaskId.compareTo(right.fromTaskId);
    if (fromCompare != 0) {
      return fromCompare;
    }
    return left.toTaskId.compareTo(right.toTaskId);
  });
  return links;
}

/// Converts one sparse graph edge into a stream transition.
TaskStreamLink? _streamLink(
  TaskProjectionEdge edge,
  Map<String, TaskStreamCard> visibleCards,
) {
  var fromTaskId = edge.fromTaskId;
  var toTaskId = edge.toTaskId;
  final transition = switch (edge.relationType) {
    'depends_on' => 'enables',
    'blocks' => 'blocks',
    'enables' => 'enables',
    'part_of' => 'contributes',
    _ => '',
  };
  if (transition.isEmpty) {
    return null;
  }
  if (edge.relationType == 'depends_on') {
    fromTaskId = edge.toTaskId;
    toTaskId = edge.fromTaskId;
  }
  final fromCard = visibleCards[fromTaskId];
  final toCard = visibleCards[toTaskId];
  if (fromCard == null || toCard == null) {
    return null;
  }
  return TaskStreamLink(
    fromTaskId: fromTaskId,
    toTaskId: toTaskId,
    relationType: edge.relationType,
    transitionType: transition,
    streamId: _streamLinkID(fromCard, toCard, edge),
    confidence: edge.confidence,
    explanation: edge.explanation,
  );
}

/// Chooses a stable route identity for a stream transition.
String _streamLinkID(
  TaskStreamCard from,
  TaskStreamCard to,
  TaskProjectionEdge edge,
) {
  if (from.streamId.isNotEmpty && from.streamId == to.streamId) {
    return from.streamId;
  }
  if (edge.relationType == 'blocks') {
    return 'blockers';
  }
  return _firstNonEmpty(<String>[
    from.streamId,
    to.streamId,
    edge.relationType,
  ]);
}

/// Returns a stable stream id from task domain or topic.
String _streamId(
  TaskProjectionTask task,
  Map<String, TaskProjectionFacet> facets,
) {
  return _normalizeId(
    _firstNonEmpty(<String>[
      task.project,
      _facetLabelForTask(task, facets, 'topic'),
      'general',
    ]),
  );
}

/// Orders stream cards by date, priority, then title.
int _compareStreamCards(TaskStreamCard left, TaskStreamCard right) {
  final leftDue = left.dueAt;
  final rightDue = right.dueAt;
  if (leftDue != null && rightDue != null && leftDue != rightDue) {
    return leftDue.compareTo(rightDue);
  }
  if (leftDue != null && rightDue == null) {
    return -1;
  }
  if (leftDue == null && rightDue != null) {
    return 1;
  }
  final priorityCompare = _priorityRank(
    left.priority,
  ).compareTo(_priorityRank(right.priority));
  if (priorityCompare != 0) {
    return priorityCompare;
  }
  return left.title.compareTo(right.title);
}

/// Maps priority labels to a compact sort rank.
int _priorityRank(String priority) {
  return switch (priority) {
    'urgent' => 0,
    'high' => 1,
    'normal' => 2,
    'low' => 3,
    _ => 4,
  };
}

/// Returns the generic next best action for a canonical task.
String _nextBestAction(TaskProjectionTask task) {
  if (task.status == 'waiting') {
    return 'Check what you are waiting on.';
  }
  if (task.status == 'blocked') {
    return 'Remove the blocker or clarify the dependency.';
  }
  if (task.description.isNotEmpty) {
    return 'Open the task notes and continue.';
  }
  return 'Start with the task title as the next action.';
}

/// Returns the explicit spend label for a projection-only task.
String _spendLabelForProjectionTask(TaskProjectionTask task) {
  return _moneyLabel(
    task.workBreakdown.estimatedCostCents,
    task.workBreakdown.costCurrency,
  );
}

/// Returns the spend bucket score for a projection-only task.
double _spendScoreForProjectionTask(TaskProjectionTask task) {
  return _spendScoreFromCents(task.workBreakdown.estimatedCostCents);
}

/// Returns the explicit spend label for a merged insight task.
String _spendLabelForIndexedTask(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? projectionTask,
) {
  return _moneyLabel(
    _spendCentsForIndexedTask(workspaceTask, projectionTask),
    _currencyForIndexedTask(workspaceTask, projectionTask),
  );
}

/// Returns the spend bucket score for a merged insight task.
double _spendScoreForIndexedTask(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? projectionTask,
) {
  return _spendScoreFromCents(
    _spendCentsForIndexedTask(workspaceTask, projectionTask),
  );
}

/// Returns the first explicit spend amount from task facts.
int _spendCentsForIndexedTask(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? projectionTask,
) {
  final workspaceSpend = workspaceTask?.spendCents ?? 0;
  if (workspaceSpend > 0) {
    return workspaceSpend;
  }
  final workspaceWbsSpend =
      workspaceTask?.workBreakdown.estimatedCostCents ?? 0;
  if (workspaceWbsSpend > 0) {
    return workspaceWbsSpend;
  }
  return projectionTask?.workBreakdown.estimatedCostCents ?? 0;
}

/// Returns the currency attached to the selected spend amount.
String _currencyForIndexedTask(
  WorkspaceTask? workspaceTask,
  TaskProjectionTask? projectionTask,
) {
  if ((workspaceTask?.spendCents ?? 0) > 0) {
    return workspaceTask?.currency ?? '';
  }
  if ((workspaceTask?.workBreakdown.estimatedCostCents ?? 0) > 0) {
    return workspaceTask?.workBreakdown.costCurrency ?? '';
  }
  return projectionTask?.workBreakdown.costCurrency ?? '';
}

/// Converts an explicit spend amount into a normalized display bucket score.
double _spendScoreFromCents(int cents) {
  if (cents <= 0) {
    return 0;
  }
  if (cents <= 2500) {
    return 0.2;
  }
  if (cents <= 10000) {
    return 0.5;
  }
  return 0.85;
}

/// Formats a minor-unit money amount for compact card metadata.
String _moneyLabel(int cents, String currency) {
  if (cents <= 0) {
    return '';
  }
  final amount = (cents / 100).toStringAsFixed(2);
  final code = currency.trim();
  return code.isEmpty ? '$amount spend' : '$amount $code spend';
}

/// Returns a deterministic angle for a text category.
double _categoryAngle(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return (hash % 628) / 100;
}

/// Returns the first non-empty string from a list.
String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

/// Normalizes a display label into a stable id.
String _normalizeId(String value) {
  final trimmed = value.trim().toLowerCase();
  final buffer = StringBuffer();
  var previousDash = false;
  for (final codeUnit in trimmed.codeUnits) {
    final isAlphaNumeric =
        (codeUnit >= 48 && codeUnit <= 57) ||
        (codeUnit >= 97 && codeUnit <= 122);
    if (isAlphaNumeric) {
      buffer.writeCharCode(codeUnit);
      previousDash = false;
    } else if (!previousDash) {
      buffer.write('-');
      previousDash = true;
    }
  }
  final normalized = buffer.toString();
  return normalized.replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Clamps a numeric value into the 0-1 range.
double _clamp01(num value) {
  return value.clamp(0, 1).toDouble();
}
