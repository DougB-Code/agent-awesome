/// Generates compact chat titles from app-owned model configuration files.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'client_logger.dart';
import 'model_invocation_config.dart';

/// ChatTitleException reports title model configuration or request failures.
class ChatTitleException implements Exception {
  /// Creates a title generation exception.
  const ChatTitleException(this.message);

  /// Human-readable failure detail.
  final String message;

  /// Formats the exception for logs and chat title metadata.
  @override
  String toString() => 'ChatTitleException: $message';
}

/// ChatTitleClient calls a small app-owned model to name conversations.
class ChatTitleClient {
  /// Creates a title client using the current process environment by default.
  ChatTitleClient({
    http.Client? httpClient,
    Map<String, String>? environment,
    String localModelChatCompletionsUrl = '',
    this.logger,
  }) : _http = httpClient ?? http.Client(),
       _environment = environment ?? Platform.environment,
       _localModelChatCompletionsUrl = localModelChatCompletionsUrl.trim();

  final http.Client _http;
  final Map<String, String> _environment;
  final String _localModelChatCompletionsUrl;

  /// Optional persistent logger.
  final ClientLogger? logger;

  /// Generates a concise title for a visible chat transcript.
  Future<String> generateTitle({
    required String modelConfigPath,
    String modelRef = '',
    required List<ChatMessage> messages,
  }) async {
    final selection = await _loadSelection(modelConfigPath, modelRef);
    final transcript = _transcript(messages);
    if (transcript.isEmpty) {
      throw const ChatTitleException('Transcript is empty');
    }
    await _log(
      'generate title adapter=${selection.adapter} model=${selection.model} transcriptLength=${transcript.length}',
    );
    final raw = switch (selection.adapter) {
      'anthropic' => await _generateAnthropic(selection, transcript),
      'litert' => await _generateOpenAi(selection, transcript),
      'openai' ||
      'openai_compatible' => await _generateOpenAi(selection, transcript),
      _ => throw ChatTitleException(
        'Unsupported title model adapter "${selection.adapter}"',
      ),
    };
    final title = _sanitizeTitle(raw);
    if (title.isEmpty) {
      throw const ChatTitleException('Title model returned empty text');
    }
    return title;
  }

  /// Closes the underlying HTTP client.
  void close() {
    _http.close();
  }

  /// Loads the selected provider, endpoint, key, and model from config.
  Future<ModelInvocationConfig> _loadSelection(
    String modelConfigPath,
    String modelRef,
  ) async {
    try {
      return await resolveModelInvocationConfig(
        modelConfigPath: modelConfigPath,
        modelRef: modelRef,
        environment: _environment,
        localModelChatCompletionsUrl: _localModelChatCompletionsUrl,
        messages: const ModelInvocationConfigMessages(
          missingSelection: 'Summary model config is not selected',
          missingFilePrefix: 'Summary model config does not exist',
          missingProviders: 'Summary model config has no providers',
          missingDefaultModel: 'Summary model default model is missing',
        ),
      );
    } on ModelInvocationConfigException catch (error) {
      throw ChatTitleException(error.message);
    }
  }

  /// Calls an OpenAI-compatible chat completions endpoint for a title.
  Future<String> _generateOpenAi(
    ModelInvocationConfig selection,
    String transcript,
  ) async {
    final response = await _http.post(
      Uri.parse(selection.url),
      headers: <String, String>{
        'Content-Type': 'application/json',
        if (selection.apiKey.isNotEmpty)
          'Authorization': 'Bearer ${selection.apiKey}',
      },
      body: jsonEncode(_openAiRequestBody(selection.model, transcript)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatTitleException(
        'Title model HTTP ${response.statusCode}: '
        '${clipProviderBody(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body);
    final choices = decoded is Map<String, dynamic> ? decoded['choices'] : null;
    if (choices is! List || choices.isEmpty) {
      throw const ChatTitleException('Title model returned no choices');
    }
    final first = choices.first;
    final message = first is Map<String, dynamic> ? first['message'] : null;
    final content = message is Map<String, dynamic> ? message['content'] : null;
    return modelInvocationString(content);
  }

  /// Calls an Anthropic messages endpoint for a title.
  Future<String> _generateAnthropic(
    ModelInvocationConfig selection,
    String transcript,
  ) async {
    final response = await _http.post(
      Uri.parse(selection.url),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
        if (selection.apiKey.isNotEmpty) 'x-api-key': selection.apiKey,
      },
      body: jsonEncode(<String, dynamic>{
        'model': selection.model,
        'max_tokens': 24,
        'temperature': 0.2,
        'system': _titleSystemPrompt,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': transcript},
        ],
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatTitleException(
        'Title model HTTP ${response.statusCode}: '
        '${clipProviderBody(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body);
    final content = decoded is Map<String, dynamic> ? decoded['content'] : null;
    if (content is! List || content.isEmpty) {
      throw const ChatTitleException('Title model returned no content');
    }
    return content
        .whereType<Map<String, dynamic>>()
        .map((part) => modelInvocationString(part['text']))
        .where((text) => text.isNotEmpty)
        .join(' ');
  }

  /// Writes a title-client diagnostic line when logging is configured.
  Future<void> _log(String message) async {
    await logger?.write('chat-title-client', message);
  }
}

/// Builds the OpenAI-compatible request body for title generation.
Map<String, dynamic> _openAiRequestBody(String model, String transcript) {
  final usesCompletionTokens = usesCompletionTokenLimit(model);
  return <String, dynamic>{
    'model': model,
    'temperature': 0.2,
    if (usesCompletionTokens) 'max_completion_tokens': 24 else 'max_tokens': 24,
    'stream': false,
    'messages': <Map<String, String>>[
      <String, String>{'role': 'system', 'content': _titleSystemPrompt},
      <String, String>{'role': 'user', 'content': transcript},
    ],
  };
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

const String _titleSystemPrompt =
    'Create a concise title for this chat. Return only 2 to 6 words. '
    'Do not use quotation marks, punctuation, emoji, or a prefix.';
