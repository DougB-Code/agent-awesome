/// Contact filter and summary-count helpers.
part of 'people_section.dart';

/// Applies text and type filters to contacts.
List<_ContactItem> _filteredContacts(
  List<_ContactItem> contacts,
  String query,
  _ContactFilter filter,
) {
  return contacts.where((contact) {
    if (!_matchesContactFilter(contact, filter)) {
      return false;
    }
    return _matchesContactQuery(contact, query);
  }).toList();
}

/// Returns whether a contact belongs to a selected filter.
bool _matchesContactFilter(_ContactItem contact, _ContactFilter filter) {
  return switch (filter) {
    _ContactFilter.all => true,
    _ContactFilter.active => contact.openTaskCount > 0,
    _ContactFilter.sources => contact.memoryRecords.isNotEmpty,
    _ContactFilter.multiContext => contact.contexts.length > 1,
    _ContactFilter.taskOwners =>
      contact.tasks.isNotEmpty && contact.memoryRecords.isEmpty,
  };
}

/// Returns whether a contact matches the fuzzy search query.
bool _matchesContactQuery(_ContactItem contact, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }
  final haystack =
      '${contact.name} ${contact.summary} ${contact.statusLabel} '
              '${contact.topics.join(' ')} '
              '${contact.contexts.map((item) => item.displayLabel).join(' ')} '
              '${contact.tasks.map((task) => task.title).join(' ')}'
          .toLowerCase();
  var cursor = 0;
  for (final codeUnit in normalizedQuery.codeUnits) {
    cursor = haystack.indexOf(String.fromCharCode(codeUnit), cursor);
    if (cursor == -1) {
      return false;
    }
    cursor++;
  }
  return true;
}

/// Counts contacts matching a library filter.
int _countContactFilter(List<_ContactItem> contacts, _ContactFilter filter) {
  return contacts
      .where((contact) => _matchesContactFilter(contact, filter))
      .length;
}

/// Counts contacts with active task ownership.
int _activeContactCount(List<_ContactItem> contacts) {
  return contacts.where((contact) => contact.openTaskCount > 0).length;
}

/// Counts context slices across all contacts.
int _contactContextCount(List<_ContactItem> contacts) {
  return contacts.fold<int>(
    0,
    (count, contact) => count + contact.contexts.length,
  );
}

/// Counts source records across all contacts.
int _contactSourceCount(List<_ContactItem> contacts) {
  return contacts.fold<int>(
    0,
    (count, contact) => count + contact.memoryRecords.length,
  );
}

/// Returns whether a task is currently open for contact activity.
bool _contactTaskIsOpen(WorkspaceTask task) {
  final status = task.status.toLowerCase();
  return !task.done &&
      status != 'done' &&
      status != 'completed' &&
      status != 'canceled' &&
      status != 'cancelled' &&
      status != 'archived';
}
