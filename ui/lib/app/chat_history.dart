/// Persists app-owned chat metadata across runtime profiles.
library;

import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';
import 'runtime_profile.dart';

/// ChatHistoryStore reads and writes local chat metadata.
class ChatHistoryStore {
  /// Creates a chat history store in the standard app data directory.
  const ChatHistoryStore();

  /// Loads known chats from disk.
  Future<List<ChatHistoryEntry>> load() async {
    final file = File(chatHistoryPath());
    if (!await file.exists()) {
      return const <ChatHistoryEntry>[];
    }
    final decoded = jsonDecode(await file.readAsString());
    final chats = decoded is Map<String, dynamic> ? decoded['chats'] : decoded;
    if (chats is! List) {
      return const <ChatHistoryEntry>[];
    }
    final entries = chats
        .whereType<Map<String, dynamic>>()
        .map(ChatHistoryEntry.fromJson)
        .toList();
    entries.sort(_compareHistoryEntries);
    return entries;
  }

  /// Saves known chats to disk.
  Future<void> save(List<ChatHistoryEntry> entries) async {
    final file = File(chatHistoryPath());
    await file.parent.create(recursive: true);
    final sorted = entries.toList()..sort(_compareHistoryEntries);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert(<String, dynamic>{'chats': sorted.map((entry) => entry.toJson()).toList()})}\n',
    );
  }
}

/// Returns the chat history JSON path.
String chatHistoryPath() {
  return '${agentAwesomeDataDirectoryPath()}/chats.json';
}

/// Sorts chat entries by latest activity first.
int _compareHistoryEntries(ChatHistoryEntry left, ChatHistoryEntry right) {
  return right.updatedAt.compareTo(left.updatedAt);
}
