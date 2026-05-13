/// File workspace aggregation, filtering, and display helpers.
part of 'files_section.dart';

/// Builds file-only records from workspace memory records.
List<_AgentFileItem> _agentFilesFromWorkspace(ProjectWorkspace workspace) {
  final files = <_AgentFileItem>[];
  for (final record in workspace.memoryRecords) {
    if (!_isFileMemoryRecord(record)) {
      continue;
    }
    files.add(_fileItemFromRecord(record));
  }
  files.sort((left, right) => left.title.compareTo(right.title));
  return files;
}

/// Converts one file-like memory record into a display item.
_AgentFileItem _fileItemFromRecord(MemoryRecord record) {
  final path = record.rawPath.trim();
  final sourceId = record.sourceId.trim();
  final mediaType = record.rawMediaType.trim();
  final kind = _fileKindFor(record);
  return _AgentFileItem(
    id: record.evidenceId.isEmpty ? record.id : record.evidenceId,
    memoryId: record.id,
    evidenceId: record.evidenceId,
    title: _fileTitle(record),
    summary: _fileSummary(record),
    kind: kind,
    mediaLabel: mediaType.isEmpty ? _extensionLabel(path, sourceId) : mediaType,
    pathLabel: _filePathLabel(path: path, sourceId: sourceId),
    checksumLabel: record.rawChecksum,
    sourceLabel: _fileSourceLabel(record.sourceLabel),
    sourceSystem: _fileSourceLabel(record.sourceSystem),
    sourceId: sourceId,
    firewall: record.firewall,
    sensitivity: record.sensitivity,
    trustLevel: record.trustLevel,
    status: record.status,
    topics: record.topics,
    record: record,
  );
}

/// Returns a product-facing source label for file displays.
String _fileSourceLabel(String value) {
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

/// Returns a file-oriented title from record metadata.
String _fileTitle(MemoryRecord record) {
  final path = record.rawPath.trim();
  final sourceId = record.sourceId.trim();
  final candidates = <String>[
    if (_looksLikeFilePath(sourceId)) sourceId,
    record.title.trim(),
    if (!_isStoredSourcePath(path)) path,
    sourceId,
    path,
  ];
  for (final candidate in candidates) {
    final label = _fileNameFromPath(candidate);
    if (label.isNotEmpty) {
      return label;
    }
  }
  return 'Untitled file';
}

/// Returns a concise file summary without leaking storage terminology.
String _fileSummary(MemoryRecord record) {
  final summary = record.summary.trim();
  if (summary.isEmpty) {
    return 'Indexed file';
  }
  return _fileLanguage(summary);
}

/// Returns the user-facing path, preferring the original file location.
String _filePathLabel({required String path, required String sourceId}) {
  if (sourceId.trim().isNotEmpty &&
      (path.trim().isEmpty ||
          _isStoredSourcePath(path) ||
          _looksLikeFilePath(sourceId))) {
    return sourceId.trim();
  }
  if (_isStoredSourcePath(path)) {
    return _fileNameFromPath(path);
  }
  return path.trim().isEmpty ? sourceId.trim() : path.trim();
}

/// Removes old "evidence" wording from file-only display strings.
String _fileLanguage(String value) {
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

/// Returns whether a path points at Agent Awesome's backing source store.
bool _isStoredSourcePath(String path) {
  final normalized = path.trim().replaceAll('\\', '/').toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return normalized == 'evidence' ||
      normalized == 'sources' ||
      normalized.startsWith('evidence/') ||
      normalized.startsWith('sources/') ||
      normalized.contains('/evidence/') ||
      normalized.contains('/sources/');
}

/// Returns whether a value looks like a local file path.
bool _looksLikeFilePath(String value) {
  final trimmed = value.trim();
  return trimmed.contains('/') || trimmed.contains('\\');
}

/// Returns the last path segment from a path-like string.
String _fileNameFromPath(String value) {
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

/// Returns whether a memory record represents a file rather than chat.
bool _isFileMemoryRecord(MemoryRecord record) {
  if (_isChatLikeMemory(record)) {
    return false;
  }
  final mediaType = record.rawMediaType.toLowerCase();
  final path = record.rawPath.toLowerCase();
  final title = record.title.toLowerCase();
  final source = '${record.sourceSystem} ${record.sourceId}'.toLowerCase();
  final kind = record.kind.toLowerCase();
  return _isFileMediaType(mediaType) ||
      _hasKnownFileExtension(path) ||
      _hasKnownFileExtension(title) ||
      _hasKnownFileExtension(source) ||
      _isFileKind(kind) ||
      source.contains('filesystem') ||
      source.contains('file_upload') ||
      source.contains('google_drive');
}

/// Returns whether a record is conversational memory, not a file.
bool _isChatLikeMemory(MemoryRecord record) {
  final kind = record.kind.toLowerCase();
  final title = record.title.toLowerCase();
  final source = '${record.sourceSystem} ${record.sourceId}'.toLowerCase();
  return kind == 'conversation' ||
      kind == 'chat' ||
      kind == 'chat_message' ||
      title.startsWith('chat message from ') ||
      source.contains('google_adk_session') ||
      source.contains('agent_awesome_chat') ||
      source.contains('chat_session') ||
      source.contains('chat:');
}

/// Returns whether a media type is file-like for the Files screen.
bool _isFileMediaType(String mediaType) {
  if (mediaType.isEmpty) {
    return false;
  }
  if (mediaType.startsWith('image/')) {
    return true;
  }
  return mediaType.contains('pdf') ||
      mediaType.contains('spreadsheet') ||
      mediaType.contains('excel') ||
      mediaType.contains('word') ||
      mediaType.contains('presentation') ||
      mediaType.contains('powerpoint') ||
      mediaType.contains('csv') ||
      mediaType.contains('zip');
}

/// Returns whether a kind string names a file-like memory category.
bool _isFileKind(String kind) {
  return kind == 'file' ||
      kind == 'document' ||
      kind == 'source_file' ||
      kind == 'pdf' ||
      kind == 'spreadsheet' ||
      kind == 'image' ||
      kind == 'photo' ||
      kind == 'presentation';
}

/// Returns whether text contains a known file extension.
bool _hasKnownFileExtension(String value) {
  return RegExp(
    r'\.(pdf|doc|docx|xls|xlsx|csv|ods|png|jpe?g|gif|webp|heic|ppt|pptx|zip|txt|md)\b',
  ).hasMatch(value);
}

/// Returns a category for a file-like memory record.
_AgentFileKind _fileKindFor(MemoryRecord record) {
  final combined =
      '${record.rawMediaType} ${record.rawPath} ${record.title} ${record.kind}'
          .toLowerCase();
  if (combined.contains('xls') ||
      combined.contains('spreadsheet') ||
      combined.contains('excel') ||
      combined.contains('.csv') ||
      combined.contains('.ods')) {
    return _AgentFileKind.spreadsheet;
  }
  if (combined.contains('image/') ||
      combined.contains('.png') ||
      combined.contains('.jpg') ||
      combined.contains('.jpeg') ||
      combined.contains('.gif') ||
      combined.contains('.webp') ||
      combined.contains('.heic') ||
      combined.contains('photo')) {
    return _AgentFileKind.image;
  }
  if (combined.contains('presentation') ||
      combined.contains('powerpoint') ||
      combined.contains('.ppt')) {
    return _AgentFileKind.presentation;
  }
  if (combined.contains('zip') || combined.contains('.zip')) {
    return _AgentFileKind.archive;
  }
  if (combined.contains('pdf') ||
      combined.contains('.doc') ||
      combined.contains('.txt') ||
      combined.contains('.md') ||
      combined.contains('document')) {
    return _AgentFileKind.document;
  }
  return _AgentFileKind.other;
}

/// Returns a readable extension label when no media type exists.
String _extensionLabel(String path, String sourceId) {
  final value = path.isEmpty ? sourceId : path;
  final match = RegExp(
    r'\.([a-z0-9]+)\b',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) {
    return 'File';
  }
  return '.${match.group(1)!.toLowerCase()}';
}

/// Applies text and type filters to files.
List<_AgentFileItem> _filteredFiles(
  List<_AgentFileItem> files,
  String query,
  _FileKindFilter kindFilter,
) {
  return files.where((file) {
    if (!_matchesFileKindFilter(file, kindFilter)) {
      return false;
    }
    return _matchesFileQuery(file, query);
  }).toList();
}

/// Returns whether a file belongs to a selected type filter.
bool _matchesFileKindFilter(_AgentFileItem file, _FileKindFilter filter) {
  return switch (filter) {
    _FileKindFilter.all => true,
    _FileKindFilter.documents => file.kind == _AgentFileKind.document,
    _FileKindFilter.spreadsheets => file.kind == _AgentFileKind.spreadsheet,
    _FileKindFilter.images => file.kind == _AgentFileKind.image,
    _FileKindFilter.other =>
      file.kind == _AgentFileKind.other ||
          file.kind == _AgentFileKind.presentation ||
          file.kind == _AgentFileKind.archive,
  };
}

/// Returns whether a file matches the fuzzy search query.
bool _matchesFileQuery(_AgentFileItem file, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }
  final haystack =
      '${file.title} ${file.summary} ${file.mediaLabel} ${file.pathLabel} '
              '${file.sourceLabel} ${file.topics.join(' ')}'
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

/// Counts files matching one concrete file kind.
int _countKind(List<_AgentFileItem> files, _AgentFileKind kind) {
  return files.where((file) => file.kind == kind).length;
}

/// Counts files matching a library filter.
int _countFilter(List<_AgentFileItem> files, _FileKindFilter filter) {
  return files.where((file) => _matchesFileKindFilter(file, filter)).length;
}

/// Returns the accent color for a file category.
Color _fileKindAccent(BuildContext context, _AgentFileKind kind) {
  final colors = context.agentAwesomeColors;
  return switch (kind) {
    _AgentFileKind.document => colors.green,
    _AgentFileKind.spreadsheet => context.agentAwesomeWarningAccent,
    _AgentFileKind.image => colors.coral,
    _AgentFileKind.presentation => colors.coral,
    _AgentFileKind.archive => colors.warningText,
    _AgentFileKind.other => colors.muted,
  };
}
