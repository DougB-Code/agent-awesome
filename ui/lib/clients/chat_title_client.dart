/// Generates compact chat titles through the ADK runtime.
library;

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'adk_utility_client.dart';
import 'client_logger.dart';
import 'model_ref_selection.dart';

/// ChatTitleException reports title model selection or request failures.
class ChatTitleException implements Exception {
  /// Creates a title generation exception.
  const ChatTitleException(this.message);

  /// Human-readable failure detail.
  final String message;

  /// Formats the exception for logs and chat title metadata.
  @override
  String toString() => 'ChatTitleException: $message';
}

/// ChatTitleClient asks ADK to name conversations with the selected model.
class ChatTitleClient {
  /// Creates a title client for one ADK app and user.
  ChatTitleClient({
    required String baseUrl,
    required String appName,
    required String userId,
    http.Client? httpClient,
    AdkUtilityClient? utilityClient,
    Map<String, String> headers = const <String, String>{},
    this.logger,
  }) : _utility =
           utilityClient ??
           AdkUtilityClient(
             baseUrl: baseUrl,
             appName: appName,
             userId: userId,
             httpClient: httpClient,
             headers: headers,
             logger: logger,
           );

  final AdkUtilityClient _utility;

  /// Optional persistent logger.
  final ClientLogger? logger;

  /// Generates a concise title for a visible chat transcript.
  Future<String> generateTitle({
    required String modelConfigContent,
    String modelRef = '',
    required List<ChatMessage> messages,
  }) async {
    final selectedModelRef = _selectedModelRef(modelConfigContent, modelRef);
    final transcript = _transcript(messages);
    if (transcript.isEmpty) {
      throw const ChatTitleException('Transcript is empty');
    }
    await _log(
      'generate title modelRef=$selectedModelRef transcriptLength=${transcript.length}',
    );
    final raw = await _runPrompt(selectedModelRef, transcript);
    final title = _sanitizeTitle(raw);
    if (title.isEmpty) {
      throw const ChatTitleException('Title model returned empty text');
    }
    return title;
  }

  /// Closes the underlying utility client.
  void close() {
    _utility.close();
  }

  String _selectedModelRef(String modelConfigContent, String modelRef) {
    try {
      return selectedModelRefFromConfig(
        modelConfigContent: modelConfigContent,
        modelRef: modelRef,
        missingSelection: 'Summary model config is not selected',
        missingProviders: 'Summary model config has no providers',
        missingDefaultModel: 'Summary model default model is missing',
      );
    } on ModelRefSelectionException catch (error) {
      throw ChatTitleException(error.message);
    }
  }

  Future<String> _runPrompt(String modelRef, String transcript) async {
    try {
      return await _utility.runText(
        modelRef: modelRef,
        logName: 'chat-title-client',
        prompt:
            'Create a concise title for this chat. Return only 2 to 6 words. '
            'Do not use quotation marks, punctuation, emoji, or a prefix. '
            'Never call tools.\n\n$transcript',
      );
    } on AdkUtilityException catch (error) {
      throw ChatTitleException(error.message);
    }
  }

  /// Writes a title-client diagnostic line when logging is configured.
  Future<void> _log(String message) async {
    await logger?.write('chat-title-client', message);
  }
}

/// Builds a compact transcript for title generation.
String _transcript(List<ChatMessage> messages) {
  final visible = messages
      .where((message) {
        return message.role == ChatRole.user ||
            message.role == ChatRole.assistant;
      })
      .take(8)
      .map((message) => '${message.author}: ${message.text.trim()}')
      .where((line) => line.trim().length > 4)
      .join('\n');
  if (visible.length <= 2400) {
    return visible;
  }
  return visible.substring(0, 2400);
}

/// Cleans model output into a short UI title.
String _sanitizeTitle(String raw) {
  var title = raw.trim();
  title = title.replaceFirst(
    RegExp(r'^title\s*:\s*', caseSensitive: false),
    '',
  );
  title = title.replaceAll(RegExp(r'[\r\n]+'), ' ');
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  title = title.replaceAll(RegExp(r'''^["']+|["'.]+$'''), '').trim();
  if (title.length > 64) {
    title = title.substring(0, 64).trimRight();
  }
  return title;
}
