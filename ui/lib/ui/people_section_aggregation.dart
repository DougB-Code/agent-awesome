/// Aggregates contacts from memory records, tasks, commitments, and pages.
part of 'people_section.dart';

Future<void> _showContactCaptureDialog(
  BuildContext context,
  AgentAwesomeAppController controller, {
  _ContactItem? contact,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _ContactCaptureDialog(
        controller: controller,
        initialName: contact?.name ?? '',
        initialContext: contact?.primaryContext?.label ?? '',
        initialTopics: contact?.topics ?? const <String>[],
      );
    },
  );
}

/// Builds contact records from memory, task owners, and commitments.
List<_ContactItem> _contactItemsFromController(
  AgentAwesomeAppController controller,
) {
  final aggregates = <String, _ContactAggregate>{};
  for (final record in controller.workspace.memoryRecords) {
    for (var index = 0; index < record.entityNames.length; index++) {
      final name = record.entityNames[index].trim();
      if (!_isUsableContactName(name)) {
        continue;
      }
      final aggregate = _contactAggregateFor(aggregates, name);
      aggregate.memoryRecords.add(record);
      aggregate.topics.addAll(record.topics.where(_isUsableTopic));
      if (index < record.entityIds.length &&
          record.entityIds[index].isNotEmpty) {
        aggregate.entityIds.add(record.entityIds[index]);
      } else {
        aggregate.entityIds.addAll(record.entityIds.where(_isUsableTopic));
      }
    }
  }
  for (final task in controller.workspace.tasks) {
    final owner = task.owner.trim();
    if (!_isUsableContactName(owner)) {
      continue;
    }
    final aggregate = _contactAggregateFor(aggregates, owner);
    aggregate.tasks.add(task);
    aggregate.topics.addAll(task.topics.where(_isUsableTopic));
    for (final label in <String>[task.domain, task.project, task.context]) {
      if (_isUsableTopic(label)) {
        aggregate.topics.add(label.trim());
      }
    }
  }
  for (final commitment in controller.taskCommitments) {
    for (final person in commitment.people) {
      if (!_isUsableContactName(person)) {
        continue;
      }
      final aggregate = _contactAggregateFor(aggregates, person);
      aggregate.commitments.add(commitment);
      for (final label in <String>[
        commitment.domain,
        commitment.project,
        commitment.responsibility,
        commitment.hardness,
      ]) {
        if (_isUsableTopic(label)) {
          aggregate.topics.add(label.trim());
        }
      }
    }
  }
  final contacts = aggregates.values.map(_contactItemFromAggregate).toList()
    ..sort(_compareContacts);
  return contacts;
}

/// Returns the aggregate for a contact name, creating it when needed.
_ContactAggregate _contactAggregateFor(
  Map<String, _ContactAggregate> aggregates,
  String name,
) {
  final displayName = name.trim();
  final id = _normalizedContactId(displayName);
  return aggregates.putIfAbsent(
    id,
    () => _ContactAggregate(id: id, name: displayName),
  );
}

/// Converts one aggregate into a display contact.
_ContactItem _contactItemFromAggregate(_ContactAggregate aggregate) {
  final records = _sortedContactRecords(aggregate.memoryRecords);
  final tasks = _sortedContactTasks(aggregate.tasks);
  final commitments = _sortedContactCommitments(aggregate.commitments);
  final primary = _primaryContactMemory(records);
  final contexts = _contactContextsFromAggregate(
    records: records,
    tasks: tasks,
    commitments: commitments,
  );
  final firewallLabels = _firewallLabelsForContexts(contexts);
  final openTaskCount = tasks.where(_contactTaskIsOpen).length;
  return _ContactItem(
    id: aggregate.id,
    name: aggregate.name,
    entityId: aggregate.entityIds.isEmpty ? '' : aggregate.entityIds.first,
    summary: _contactSummary(
      name: aggregate.name,
      primary: primary,
      openTaskCount: openTaskCount,
      sourceCount: records.length,
      commitmentCount: commitments.length,
    ),
    statusLabel: _contactStatusLabel(
      openTaskCount: openTaskCount,
      commitmentCount: commitments.length,
      sourceCount: records.length,
    ),
    openTaskCount: openTaskCount,
    memoryRecords: records,
    tasks: tasks,
    commitments: commitments,
    contexts: contexts,
    firewallLabels: firewallLabels,
    topics: aggregate.topics.toList()..sort(),
    primaryMemory: primary,
    primaryContext: contexts.isEmpty ? null : contexts.first,
    lastUpdatedAt: _latestContactTimestamp(records, tasks, commitments),
  );
}

/// Builds firewall context slices from a contact aggregate.
List<_ContactContext> _contactContextsFromAggregate({
  required List<MemoryRecord> records,
  required List<WorkspaceTask> tasks,
  required List<TaskCommitment> commitments,
}) {
  final aggregates = <String, _ContactContextAggregate>{};
  for (final record in records) {
    final label = _memoryContextLabel(record);
    final aggregate = _contextAggregateFor(
      aggregates,
      firewall: _normalizedFirewall(record.firewall),
      label: label,
    );
    aggregate.memoryRecords.add(record);
    aggregate.topics.addAll(record.topics.where(_isUsableTopic));
    if (record.sensitivity.isNotEmpty) {
      aggregate.sensitivities.add(record.sensitivity);
    }
  }
  for (final task in tasks) {
    final aggregate = _contextAggregateFor(
      aggregates,
      firewall: _taskContextFirewall(task),
      label: _taskContextLabel(task),
    );
    aggregate.tasks.add(task);
    aggregate.topics.addAll(task.topics.where(_isUsableTopic));
    for (final label in <String>[task.domain, task.project, task.context]) {
      if (_isUsableTopic(label)) {
        aggregate.topics.add(label.trim());
      }
    }
  }
  for (final commitment in commitments) {
    final aggregate = _contextAggregateFor(
      aggregates,
      firewall: _commitmentContextFirewall(commitment),
      label: _commitmentContextLabel(commitment),
    );
    aggregate.commitments.add(commitment);
    for (final label in <String>[
      commitment.domain,
      commitment.project,
      commitment.responsibility,
      commitment.hardness,
    ]) {
      if (_isUsableTopic(label)) {
        aggregate.topics.add(label.trim());
      }
    }
  }
  final contexts = aggregates.values.map(_contactContextFromAggregate).toList()
    ..sort(_compareContactContexts);
  return contexts;
}

/// Returns the aggregate for a firewall/context pair.
_ContactContextAggregate _contextAggregateFor(
  Map<String, _ContactContextAggregate> aggregates, {
  required String firewall,
  required String label,
}) {
  final normalizedFirewall = _normalizedFirewall(firewall);
  final displayLabel = label.trim().isEmpty ? 'General' : label.trim();
  final id = '$normalizedFirewall:${_normalizedContactId(displayLabel)}';
  return aggregates.putIfAbsent(
    id,
    () => _ContactContextAggregate(
      id: id,
      firewall: normalizedFirewall,
      label: displayLabel,
    ),
  );
}

/// Converts one context aggregate into a display item.
_ContactContext _contactContextFromAggregate(
  _ContactContextAggregate aggregate,
) {
  final records = _sortedContactRecords(aggregate.memoryRecords);
  final tasks = _sortedContactTasks(aggregate.tasks);
  final commitments = _sortedContactCommitments(aggregate.commitments);
  final openTaskCount = tasks.where(_contactTaskIsOpen).length;
  return _ContactContext(
    id: aggregate.id,
    firewall: aggregate.firewall,
    label: aggregate.label,
    summary: _contactContextSummary(
      label: aggregate.label,
      records: records,
      tasks: tasks,
      commitments: commitments,
    ),
    sensitivityLabel: _contextSensitivityLabel(aggregate.sensitivities),
    sourceCount: records.length,
    openTaskCount: openTaskCount,
    commitmentCount: commitments.length,
    memoryRecords: records,
    tasks: tasks,
    commitments: commitments,
    topics: aggregate.topics.toList()..sort(),
    lastUpdatedAt: _latestContactTimestamp(records, tasks, commitments),
  );
}

/// Summarizes one firewall context slice.
String _contactContextSummary({
  required String label,
  required List<MemoryRecord> records,
  required List<WorkspaceTask> tasks,
  required List<TaskCommitment> commitments,
}) {
  final primary = _primaryContactMemory(records);
  if (primary != null && primary.summary.trim().isNotEmpty) {
    return primary.summary.trim();
  }
  final openTaskCount = tasks.where(_contactTaskIsOpen).length;
  final parts = <String>[
    if (openTaskCount > 0) '$openTaskCount active tasks',
    if (commitments.isNotEmpty) '${commitments.length} commitments',
    if (records.isNotEmpty) '${records.length} source records',
  ];
  if (parts.isEmpty) {
    return label;
  }
  return parts.join(' | ');
}

/// Returns a sensitivity label for one context.
String _contextSensitivityLabel(Set<String> sensitivities) {
  final values = sensitivities.where((value) => value.trim().isNotEmpty);
  if (values.isEmpty) {
    return '-';
  }
  if (values.length == 1) {
    return values.first;
  }
  return 'mixed';
}

/// Returns distinct readable firewall labels for a contact.
List<String> _firewallLabelsForContexts(List<_ContactContext> contexts) {
  final labels = <String>{};
  for (final context in contexts) {
    labels.add(_contactLabel(context.firewall));
  }
  return labels.toList()..sort();
}

/// Compares context slices for contact display.
int _compareContactContexts(_ContactContext left, _ContactContext right) {
  final activeCompare = right.openTaskCount.compareTo(left.openTaskCount);
  if (activeCompare != 0) {
    return activeCompare;
  }
  final commitmentCompare = right.commitmentCount.compareTo(
    left.commitmentCount,
  );
  if (commitmentCompare != 0) {
    return commitmentCompare;
  }
  final sourceCompare = right.sourceCount.compareTo(left.sourceCount);
  if (sourceCompare != 0) {
    return sourceCompare;
  }
  final firewallCompare = left.firewall.compareTo(right.firewall);
  if (firewallCompare != 0) {
    return firewallCompare;
  }
  return left.label.compareTo(right.label);
}

/// Returns a concise summary for one contact.
String _contactSummary({
  required String name,
  required MemoryRecord? primary,
  required int openTaskCount,
  required int sourceCount,
  required int commitmentCount,
}) {
  final summary = primary?.summary.trim() ?? '';
  if (summary.isNotEmpty) {
    return summary;
  }
  final parts = <String>[
    if (openTaskCount > 0) '$openTaskCount active tasks',
    if (commitmentCount > 0) '$commitmentCount commitments',
    if (sourceCount > 0) '$sourceCount source records',
  ];
  if (parts.isEmpty) {
    return '$name is referenced by workspace work.';
  }
  return parts.join(' | ');
}

/// Returns the status label for one contact.
String _contactStatusLabel({
  required int openTaskCount,
  required int commitmentCount,
  required int sourceCount,
}) {
  if (openTaskCount > 0) {
    return 'Active';
  }
  if (commitmentCount > 0) {
    return 'Committed';
  }
  if (sourceCount > 0) {
    return 'Known';
  }
  return 'Referenced';
}

/// Returns the preferred memory record for contact actions.
MemoryRecord? _primaryContactMemory(List<MemoryRecord> records) {
  if (records.isEmpty) {
    return null;
  }
  for (final record in records) {
    if (record.kind == 'profile_fact' && record.status == 'active') {
      return record;
    }
  }
  for (final record in records) {
    if (record.status == 'active') {
      return record;
    }
  }
  return records.first;
}

/// Sorts contact memory records by usefulness and recency.
List<MemoryRecord> _sortedContactRecords(List<MemoryRecord> records) {
  final sorted = List<MemoryRecord>.from(records);
  sorted.sort((left, right) {
    final leftProfile = left.kind == 'profile_fact' ? 0 : 1;
    final rightProfile = right.kind == 'profile_fact' ? 0 : 1;
    final profileCompare = leftProfile.compareTo(rightProfile);
    if (profileCompare != 0) {
      return profileCompare;
    }
    final timeCompare = _compareDateDesc(left.updatedAt, right.updatedAt);
    if (timeCompare != 0) {
      return timeCompare;
    }
    return left.title.compareTo(right.title);
  });
  return sorted;
}

/// Sorts contact tasks by open state and title.
List<WorkspaceTask> _sortedContactTasks(List<WorkspaceTask> tasks) {
  final sorted = List<WorkspaceTask>.from(tasks);
  sorted.sort((left, right) {
    final leftOpen = _contactTaskIsOpen(left) ? 0 : 1;
    final rightOpen = _contactTaskIsOpen(right) ? 0 : 1;
    final openCompare = leftOpen.compareTo(rightOpen);
    if (openCompare != 0) {
      return openCompare;
    }
    final timeCompare = _compareDateDesc(left.updatedAt, right.updatedAt);
    if (timeCompare != 0) {
      return timeCompare;
    }
    return left.title.compareTo(right.title);
  });
  return sorted;
}

/// Sorts commitments by recency and project label.
List<TaskCommitment> _sortedContactCommitments(
  List<TaskCommitment> commitments,
) {
  final sorted = List<TaskCommitment>.from(commitments);
  sorted.sort((left, right) {
    final timeCompare = _compareDateDesc(left.updatedAt, right.updatedAt);
    if (timeCompare != 0) {
      return timeCompare;
    }
    return _firstNonEmpty(<String>[
      left.project,
      left.domain,
    ]).compareTo(_firstNonEmpty(<String>[right.project, right.domain]));
  });
  return sorted;
}

/// Compares contacts for library display.
int _compareContacts(_ContactItem left, _ContactItem right) {
  final activeCompare = right.openTaskCount.compareTo(left.openTaskCount);
  if (activeCompare != 0) {
    return activeCompare;
  }
  final commitmentCompare = right.commitments.length.compareTo(
    left.commitments.length,
  );
  if (commitmentCompare != 0) {
    return commitmentCompare;
  }
  final sourceCompare = right.memoryRecords.length.compareTo(
    left.memoryRecords.length,
  );
  if (sourceCompare != 0) {
    return sourceCompare;
  }
  return left.name.compareTo(right.name);
}
