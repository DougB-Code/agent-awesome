/// Imports user-selected files as durable source-backed memory records.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

import '../domain/models.dart';

const int _maxImportBytes = 20 * 1024 * 1024;

/// AgentFileImporter selects and serializes files for Agent Awesome.
abstract class AgentFileImporter {
  /// Opens a file picker and returns a serialized import, or null when canceled.
  Future<ImportedAgentFile?> pickFile();
}

/// FileSelectorAgentFileImporter uses the platform file picker.
class FileSelectorAgentFileImporter implements AgentFileImporter {
  /// Creates the default desktop file importer.
  const FileSelectorAgentFileImporter({this.maxBytes = _maxImportBytes});

  /// Maximum accepted file size to avoid oversized memory and chat payloads.
  final int maxBytes;

  /// Opens the native file picker and serializes the selected file.
  @override
  Future<ImportedAgentFile?> pickFile() async {
    final selected = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'Agent files',
          extensions: <String>[
            'pdf',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'csv',
            'ods',
            'png',
            'jpg',
            'jpeg',
            'gif',
            'webp',
            'heic',
            'ppt',
            'pptx',
            'txt',
            'md',
            'json',
            'zip',
          ],
        ),
      ],
    );
    if (selected == null) {
      return null;
    }
    return ImportedAgentFile.fromXFile(selected, maxBytes: maxBytes);
  }
}

/// ImportedAgentFile stores a file payload ready for memory and chat transport.
class ImportedAgentFile {
  /// Creates a serialized file import.
  const ImportedAgentFile({
    required this.name,
    required this.path,
    required this.mediaType,
    required this.sizeBytes,
    required this.sha256Digest,
    required this.encoding,
    required this.serializedContent,
    required this.kind,
    required this.topics,
  });

  /// Builds a serialized import from an XFile.
  static Future<ImportedAgentFile> fromXFile(
    XFile file, {
    int maxBytes = _maxImportBytes,
  }) async {
    final bytes = await file.readAsBytes();
    return fromBytes(
      name: file.name,
      path: file.path,
      bytes: bytes,
      providedMediaType: file.mimeType,
      maxBytes: maxBytes,
    );
  }

  /// Builds a serialized import from file bytes.
  static ImportedAgentFile fromBytes({
    required String name,
    required String path,
    required List<int> bytes,
    String? providedMediaType,
    int maxBytes = _maxImportBytes,
  }) {
    if (bytes.length > maxBytes) {
      throw FileImportException(
        'File is ${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB; '
        'the current limit is ${(maxBytes / (1024 * 1024)).toStringAsFixed(0)} MB.',
      );
    }
    final mediaType = normalizedFileMediaType(
      name: name,
      path: path,
      providedMediaType: providedMediaType,
    );
    final digest = sha256.convert(bytes).toString();
    final text = _decodeTextContent(bytes, mediaType);
    final encoding = text == null ? 'base64' : 'utf-8';
    final payload = text ?? base64Encode(bytes);
    return ImportedAgentFile(
      name: name.trim().isEmpty ? _fileNameFromPath(path) : name.trim(),
      path: path.trim(),
      mediaType: mediaType,
      sizeBytes: bytes.length,
      sha256Digest: digest,
      encoding: encoding,
      serializedContent: _serializedFileContent(
        name: name.trim().isEmpty ? _fileNameFromPath(path) : name.trim(),
        path: path.trim(),
        mediaType: mediaType,
        sizeBytes: bytes.length,
        sha256Digest: digest,
        encoding: encoding,
        payload: payload,
      ),
      kind: memoryKindForMediaType(mediaType),
      topics: fileTopicsForMediaType(mediaType),
    );
  }

  /// Original display filename.
  final String name;

  /// Original local path, when available from the platform picker.
  final String path;

  /// Source media type inferred from the file extension or picker metadata.
  final String mediaType;

  /// Original byte size.
  final int sizeBytes;

  /// SHA-256 checksum of the original bytes.
  final String sha256Digest;

  /// Payload encoding stored inside serializedContent.
  final String encoding;

  /// Text envelope persisted as a memory source record.
  final String serializedContent;

  /// Memory kind to assign to the imported file.
  final String kind;

  /// Search topics to assign to the imported file.
  final List<String> topics;

  /// Returns a reviewed memory draft for this imported file.
  MemoryCaptureDraft toMemoryDraft() {
    return MemoryCaptureDraft(
      content: serializedContent,
      title: name,
      kind: kind,
      firewall: 'user',
      trustLevel: 'source_original',
      sensitivity: 'private',
      sourceSystem: 'local_file',
      sourceId: path.isEmpty ? name : path,
      mediaType: mediaType,
      subjects: <String>[name],
      topics: topics,
      entityNames: const <String>[],
    );
  }

  /// Stable key used to avoid duplicate imports for the same bytes.
  String get idempotencyKey => 'agent_awesome_file:$sha256Digest';
}

/// FileImportException reports rejected imports to the UI controller.
class FileImportException implements Exception {
  /// Creates a file import error.
  const FileImportException(this.message);

  /// Human-readable import failure.
  final String message;

  @override
  String toString() => message;
}

/// Returns a normalized media type for a selected file.
String normalizedFileMediaType({
  required String name,
  required String path,
  String? providedMediaType,
}) {
  final provided = providedMediaType?.trim().toLowerCase() ?? '';
  if (provided.isNotEmpty && provided != 'application/octet-stream') {
    return provided;
  }
  final extension = _extensionFor(name, path);
  return switch (extension) {
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'csv' => 'text/csv; charset=utf-8',
    'ods' => 'application/vnd.oasis.opendocument.spreadsheet',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt' => 'text/plain; charset=utf-8',
    'md' => 'text/markdown; charset=utf-8',
    'json' => 'application/json',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}

/// Returns the memory kind that best matches a media type.
String memoryKindForMediaType(String mediaType) {
  final normalized = mediaType.toLowerCase();
  if (normalized.startsWith('image/')) {
    return 'image';
  }
  if (normalized.contains('spreadsheet') ||
      normalized.contains('excel') ||
      normalized.contains('csv')) {
    return 'spreadsheet';
  }
  if (normalized.contains('presentation') ||
      normalized.contains('powerpoint')) {
    return 'presentation';
  }
  return 'document';
}

/// Returns searchable topics for an imported file.
List<String> fileTopicsForMediaType(String mediaType) {
  final kind = memoryKindForMediaType(mediaType);
  return <String>['file', kind];
}

/// Decodes text-like source files and lets binary files use base64 instead.
String? _decodeTextContent(List<int> bytes, String mediaType) {
  final normalized = mediaType.toLowerCase();
  final isText =
      normalized.startsWith('text/') ||
      normalized.contains('json') ||
      normalized.contains('xml') ||
      normalized.contains('yaml');
  if (!isText) {
    return null;
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// Builds the canonical text envelope stored as file memory content.
String _serializedFileContent({
  required String name,
  required String path,
  required String mediaType,
  required int sizeBytes,
  required String sha256Digest,
  required String encoding,
  required String payload,
}) {
  final sourcePath = path.isEmpty ? name : path;
  return '''
Agent Awesome file
name: $name
media_type: $mediaType
source_path: $sourcePath
size_bytes: $sizeBytes
sha256: $sha256Digest
encoding: $encoding

--- file_content ---
$payload
'''
      .trim();
}

/// Returns a lowercase extension from a display name or path.
String _extensionFor(String name, String path) {
  final source = name.trim().isEmpty ? path : name;
  final match = RegExp(r'\.([A-Za-z0-9]+)$').firstMatch(source.trim());
  return match?.group(1)?.toLowerCase() ?? '';
}

/// Returns the last path segment or a stable untitled fallback.
String _fileNameFromPath(String path) {
  final parts = path.split(RegExp(r'[/\\]')).where((part) => part.isNotEmpty);
  return parts.isEmpty ? 'Untitled file' : parts.last;
}
