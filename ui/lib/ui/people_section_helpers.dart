/// Contact display, prompt, normalization, and formatting helpers.
part of 'people_section.dart';

/// Returns the contact context label for a memory record.
String _memoryContextLabel(MemoryRecord record) {
  for (final value in <String>[
    ...record.subjects,
    ...record.topics,
    record.kind == 'profile_fact' ? 'Profile' : '',
  ]) {
    if (_isContactContextLabel(value)) {
      return value.trim();
    }
  }
  return 'General';
}

/// Returns a product-facing source label for contact activity rows.
String _contactSourceLabel(String value) {
  final trimmed = value.trim();
  final normalized = trimmed.toLowerCase();
  if (normalized == 'google_adk_session' ||
      normalized == 'agent_awesome_chat' ||
      normalized == 'chat_session') {
    return 'Chat';
  }
  for (final prefix in <String>[
    'google_adk_session:',
    'agent_awesome_chat:',
    'chat_session:',
  ]) {
    if (normalized.startsWith(prefix)) {
      final suffix = trimmed.substring(prefix.length).trim();
      return suffix.isEmpty ? 'Chat' : 'Chat: $suffix';
    }
  }
  return trimmed;
}

/// Returns the inferred contact context firewall for a task.
String _taskContextFirewall(WorkspaceTask task) {
  if (task.project.trim().isNotEmpty) {
    return 'project';
  }
  return 'user';
}

/// Returns the contact context label for a task.
String _taskContextLabel(WorkspaceTask task) {
  return _firstNonEmpty(<String>[task.project, 'Task ownership']);
}

/// Reports whether a label can identify a contact context.
bool _isContactContextLabel(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return normalized != 'people' &&
      normalized != 'person' &&
      normalized != 'contacts' &&
      normalized != 'contact';
}

/// Normalizes an empty firewall into the default contact memory firewall.
String _normalizedFirewall(String firewall) {
  final trimmed = firewall.trim();
  return trimmed.isEmpty ? 'user' : trimmed;
}

/// Returns configured firewall labels represented by one contact.
List<String> _contactFirewallLabels(
  AgentAwesomeAppController controller,
  _ContactItem contact,
) {
  final labels = <String>[];
  final seen = <String>{};
  for (final context in contact.contexts) {
    final label = controller.memoryFirewallLabel(context.firewall).trim();
    if (label.isEmpty || seen.contains(label)) {
      continue;
    }
    seen.add(label);
    labels.add(label);
  }
  return labels.isEmpty ? contact.firewallLabels : labels;
}

/// Returns a contact context label prefixed by the configured firewall.
String _contactContextDisplayLabel(
  AgentAwesomeAppController controller,
  _ContactContext context,
) {
  final firewall = controller.memoryFirewallLabel(context.firewall);
  return context.label.trim().isEmpty
      ? firewall
      : '$firewall / ${context.label}';
}

/// Returns the newest timestamp across contact data.
DateTime? _latestContactTimestamp(
  List<MemoryRecord> records,
  List<WorkspaceTask> tasks,
) {
  DateTime? latest;
  for (final value in <DateTime?>[
    for (final record in records) record.updatedAt ?? record.createdAt,
    for (final task in tasks) task.updatedAt ?? task.createdAt,
  ]) {
    if (value == null) {
      continue;
    }
    if (latest == null || value.isAfter(latest)) {
      latest = value;
    }
  }
  return latest;
}

/// Compares nullable dates in descending order.
int _compareDateDesc(DateTime? left, DateTime? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return right.compareTo(left);
}

/// Returns whether a compiled page belongs to a contact.
bool _pageBelongsToContact(CompiledMemoryPage page, _ContactItem contact) {
  if (page.title.trim().toLowerCase() == contact.name.trim().toLowerCase()) {
    return true;
  }
  final sourceIds = page.sourceIds.toSet();
  return contact.memoryRecords.any((record) {
    return sourceIds.contains(record.id) ||
        sourceIds.contains(record.evidenceId);
  });
}

/// Builds the chat prompt for reviewing one contact.
String _contactChatPrompt(
  _ContactItem contact,
  AgentAwesomeAppController controller,
) {
  return '''
Please review this contact context and use it as source material for the conversation.

Contact: ${contact.name}
Status: ${contact.statusLabel}
Summary: ${contact.summary}
Topics: ${contact.topics.join(', ')}
Contexts: ${contact.contexts.map((item) => _contactContextDisplayLabel(controller, item)).join(', ')}
Open tasks: ${contact.openTaskCount}
Sources: ${contact.memoryRecords.length}
'''
      .trim();
}

/// Returns the accent color for a contact.
Color _contactAccent(BuildContext context, _ContactItem contact) {
  final colors = context.agentAwesomeColors;
  if (contact.openTaskCount > 0) {
    return colors.green;
  }
  if (contact.memoryRecords.isNotEmpty) {
    return context.agentAwesomeLowAccent;
  }
  return colors.muted;
}

/// Returns whether a value is a usable contact name.
bool _isUsableContactName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (trimmed.length < 2) {
    return false;
  }
  if (trimmed.contains('/') || trimmed.contains('\\')) {
    return false;
  }
  return true;
}

/// Returns whether a topic-like value can be shown.
bool _isUsableTopic(String value) {
  return value.trim().isNotEmpty;
}

/// Normalizes a contact id from a display name.
String _normalizedContactId(String name) {
  return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Returns a filesystem-safe contact slug for source ids.
String _contactSlug(String name) {
  final slug = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'contact' : slug;
}

/// Splits comma-delimited contact labels.
List<String> _splitContactList(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

/// Merges typed topics with the selected context label.
List<String> _mergedContactTopics(List<String> topics, String contextLabel) {
  final merged = <String>{...topics};
  if (contextLabel.trim().isNotEmpty) {
    merged.add(contextLabel.trim());
  }
  return merged.toList();
}

/// Builds the stored content for a contact note.
String _contactNoteContent({
  required String name,
  required String contextLabel,
  required String note,
}) {
  if (note.trim().isNotEmpty) {
    return note.trim();
  }
  if (contextLabel.trim().isNotEmpty) {
    return 'Contact: $name\nContext: ${contextLabel.trim()}';
  }
  return 'Contact: $name';
}

/// Builds the title for a contact note.
String _contactNoteTitle({
  required String name,
  required String contextLabel,
  required String note,
}) {
  final contextSuffix = contextLabel.trim().isEmpty
      ? ''
      : ' (${contextLabel.trim()})';
  return note.trim().isEmpty
      ? '$name profile$contextSuffix'
      : 'Contact note: $name$contextSuffix';
}

/// Returns the first non-empty value from a list.
String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    if (value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return '';
}

/// Converts controlled vocabulary to readable labels.
String _contactLabel(String value) {
  if (value.isEmpty) {
    return '';
  }
  return value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}
