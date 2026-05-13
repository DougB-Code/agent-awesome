/// Chat context lookup and matching helpers.
part of 'agent_awesome_shell.dart';

List<MemoryRecord> _chatMemoryRecords(AgentAwesomeAppController controller) {
  final records = _chatRelevantMemoryRecords(controller).where((record) {
    return !_chatContextRecordIsFile(record);
  }).toList();
  records.sort((left, right) => left.title.compareTo(right.title));
  return records;
}

/// Returns file-like memory records associated with the selected chat.
List<MemoryRecord> _chatFileRecords(AgentAwesomeAppController controller) {
  final records = _chatRelevantMemoryRecords(controller).where((record) {
    return _chatContextRecordIsFile(record);
  }).toList();
  records.sort((left, right) => left.title.compareTo(right.title));
  return records;
}

/// Returns source items associated with the selected chat transcript.
List<SourceItem> _chatSourceItems(AgentAwesomeAppController controller) {
  final transcript = _chatTranscript(controller);
  final sources = controller.workspace.sources.where((source) {
    return _sourceItemBelongsToChat(source, transcript);
  }).toList();
  sources.sort((left, right) => left.title.compareTo(right.title));
  return sources;
}

/// Returns memory records associated with the selected chat, excluding messages.
List<MemoryRecord> _chatRelevantMemoryRecords(
  AgentAwesomeAppController controller,
) {
  final sessionId = controller.selectedSessionId ?? '';
  final transcript = _chatTranscript(controller);
  return controller.workspace.memoryRecords.where((record) {
    return !_chatContextRecordIsChatMessage(record) &&
        _memoryRecordBelongsToChat(record, sessionId, transcript);
  }).toList();
}

/// Builds aggregate people rows from chat memory and task context.
List<_ChatPersonContext> _chatPeopleRows(AgentAwesomeAppController controller) {
  final memoryCounts = <String, int>{};
  final taskCounts = <String, int>{};
  for (final record in _chatRelevantMemoryRecords(controller)) {
    if (_chatContextRecordIsFile(record)) {
      continue;
    }
    for (final name in record.entityNames) {
      final normalized = name.trim();
      if (normalized.isNotEmpty) {
        memoryCounts[normalized] = (memoryCounts[normalized] ?? 0) + 1;
      }
    }
  }
  for (final task in controller.selectedChatTasks) {
    final owner = task.owner.trim();
    if (owner.isNotEmpty) {
      taskCounts[owner] = (taskCounts[owner] ?? 0) + 1;
    }
  }
  final names = <String>{...memoryCounts.keys, ...taskCounts.keys}.toList()
    ..sort();
  return <_ChatPersonContext>[
    for (final name in names)
      _ChatPersonContext(
        name: name,
        memoryCount: memoryCounts[name] ?? 0,
        taskCount: taskCounts[name] ?? 0,
      ),
  ];
}

/// Returns the selected chat transcript as searchable lowercase text.
String _chatTranscript(AgentAwesomeAppController controller) {
  return controller.messages
      .map((message) => '${message.author} ${message.text}')
      .join('\n')
      .toLowerCase();
}

/// Reports whether a memory record belongs to the selected chat.
bool _memoryRecordBelongsToChat(
  MemoryRecord record,
  String sessionId,
  String transcript,
) {
  final sessionNeedle = sessionId.trim().toLowerCase();
  final metadata = <String>[
    record.id,
    record.title,
    record.summary,
    record.sourceLabel,
    record.sourceSystem,
    record.sourceId,
    record.rawPath,
    record.rawMediaType,
    ...record.topics,
    ...record.subjects,
    ...record.entityNames,
  ].join(' ').toLowerCase();
  if (sessionNeedle.isNotEmpty && metadata.contains(sessionNeedle)) {
    return true;
  }
  return _anyMeaningfulTokenAppears(transcript, <String>[
    record.title,
    record.sourceLabel,
    record.sourceId,
    _lastPathSegment(record.rawPath),
    _lastPathSegment(record.sourceId),
    ...record.entityNames,
    ...record.subjects,
  ]);
}

/// Reports whether a source item appears in the selected chat transcript.
bool _sourceItemBelongsToChat(SourceItem source, String transcript) {
  return _anyMeaningfulTokenAppears(transcript, <String>[
    source.id,
    source.title,
    source.detail,
    _lastPathSegment(source.id),
    _lastPathSegment(source.detail),
  ]);
}

/// Reports whether a source row is already represented by a file memory record.
bool _sourceItemRepresentedByFileRecord(
  SourceItem source,
  List<MemoryRecord> fileRecords,
) {
  final sourceTokens =
      <String>[
        source.id,
        source.title,
        source.detail,
        _lastPathSegment(source.id),
        _lastPathSegment(source.title),
        _lastPathSegment(source.detail),
      ].map((value) => value.trim().toLowerCase()).where((value) {
        return value.isNotEmpty;
      }).toSet();
  for (final record in fileRecords) {
    final recordTokens =
        <String>[
          record.id,
          record.evidenceId,
          record.title,
          record.sourceLabel,
          record.sourceId,
          record.rawPath,
          _lastPathSegment(record.title),
          _lastPathSegment(record.sourceId),
          _lastPathSegment(record.rawPath),
        ].map((value) => value.trim().toLowerCase()).where((value) {
          return value.isNotEmpty;
        });
    if (recordTokens.any(sourceTokens.contains)) {
      return true;
    }
  }
  return false;
}

/// Removes storage/provenance jargon from chat overview display text.
String _chatContextDisplayText(String value) {
  return value
      .replaceAll(
        RegExp(r'\bAgent Awesome file evidence\b', caseSensitive: false),
        'Agent Awesome file',
      )
      .replaceAll(RegExp(r'\bfile evidence\b', caseSensitive: false), 'file')
      .replaceAll(
        RegExp(r'\bsource evidence\b', caseSensitive: false),
        'source content',
      )
      .replaceAll(
        RegExp(r'\braw evidence\b', caseSensitive: false),
        'source content',
      )
      .replaceAll(
        RegExp(r'\bevidence\b', caseSensitive: false),
        'source material',
      );
}

/// Reports whether any meaningful candidate appears in normalized text.
bool _anyMeaningfulTokenAppears(
  String normalizedText,
  Iterable<String> tokens,
) {
  for (final token in tokens) {
    final normalized = token.trim().toLowerCase();
    if (normalized.length >= 4 && normalizedText.contains(normalized)) {
      return true;
    }
  }
  return false;
}

/// Reports whether a memory record is a chat transcript row.
bool _chatContextRecordIsChatMessage(MemoryRecord record) {
  final kind = record.kind.toLowerCase();
  final title = record.title.toLowerCase();
  final source = '${record.sourceSystem} ${record.sourceId}'.toLowerCase();
  return kind == 'conversation' ||
      kind == 'chat' ||
      kind == 'chat_message' ||
      title.startsWith('chat message from ') ||
      source.contains('google_adk_session') ||
      source.contains('agent_awesome_chat') ||
      source.contains('chat_session');
}

/// Reports whether a memory record represents a file context item.
bool _chatContextRecordIsFile(MemoryRecord record) {
  final mediaType = record.rawMediaType.toLowerCase();
  final path = record.rawPath.toLowerCase();
  final title = record.title.toLowerCase();
  final source = '${record.sourceSystem} ${record.sourceId}'.toLowerCase();
  final kind = record.kind.toLowerCase();
  return mediaType.startsWith('image/') ||
      mediaType.contains('pdf') ||
      mediaType.contains('spreadsheet') ||
      mediaType.contains('excel') ||
      mediaType.contains('word') ||
      mediaType.contains('presentation') ||
      mediaType.contains('csv') ||
      _chatTextHasKnownFileExtension(path) ||
      _chatTextHasKnownFileExtension(title) ||
      _chatTextHasKnownFileExtension(source) ||
      kind == 'file' ||
      kind == 'document' ||
      kind == 'source_file' ||
      kind == 'pdf' ||
      kind == 'spreadsheet' ||
      kind == 'image' ||
      source.contains('filesystem') ||
      source.contains('file_upload') ||
      source.contains('google_drive');
}

/// Reports whether text contains a known file extension.
bool _chatTextHasKnownFileExtension(String value) {
  return RegExp(
    r'\.(pdf|doc|docx|xls|xlsx|csv|ods|png|jpe?g|gif|webp|heic|ppt|pptx|zip|txt|md)\b',
  ).hasMatch(value);
}

/// Returns the last path segment from a path-like value.
String _lastPathSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final parts = trimmed
      .split(RegExp(r'[/\\]'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  return parts.isEmpty ? trimmed : parts.last.trim();
}
