/// Generates compact chat titles from app-owned model configuration files.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../app/app_logger.dart';
import '../domain/models.dart';

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
  final AppLogger? logger;

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
  Future<_TitleModelSelection> _loadSelection(
    String modelConfigPath,
    String modelRef,
  ) async {
    final path = modelConfigPath.trim();
    if (path.isEmpty) {
      throw const ChatTitleException('Summary model config is not selected');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw ChatTitleException('Summary model config does not exist: $path');
    }
    final decoded = _plainYaml(loadYaml(await file.readAsString()));
    if (decoded is! Map<String, dynamic>) {
      throw const ChatTitleException('Summary model config must be a map');
    }
    final providers = decoded['providers'];
    if (providers is! Map<String, dynamic> || providers.isEmpty) {
      throw const ChatTitleException('Summary model config has no providers');
    }
    final configuredRef = modelRef.trim();
    final defaultRef = _string(decoded['default']);
    final parsedDefault = _parseDefault(
      configuredRef.isEmpty ? defaultRef : configuredRef,
    );
    final providerName = parsedDefault.provider;
    if (providerName.isEmpty) {
      throw const ChatTitleException('Summary model is not selected');
    }
    final provider = providers[providerName];
    if (provider is! Map<String, dynamic>) {
      throw ChatTitleException('Provider "$providerName" is not configured');
    }
    final modelId = parsedDefault.model.isEmpty
        ? _string(provider['default'])
        : parsedDefault.model;
    final model = _resolveModel(provider, modelId);
    return _TitleModelSelection(
      adapter: _string(provider['adapter'], fallback: 'openai'),
      url: _providerUrl(provider, _localModelChatCompletionsUrl),
      apiKey: _apiKey(_string(provider['api-key'] ?? provider['api_key'])),
      model: model,
    );
  }

  /// Calls an OpenAI-compatible chat completions endpoint for a title.
  Future<String> _generateOpenAi(
    _TitleModelSelection selection,
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
        'Title model HTTP ${response.statusCode}: ${_clip(response.body)}',
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
    return _string(content);
  }

  /// Calls an Anthropic messages endpoint for a title.
  Future<String> _generateAnthropic(
    _TitleModelSelection selection,
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
        'Title model HTTP ${response.statusCode}: ${_clip(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body);
    final content = decoded is Map<String, dynamic> ? decoded['content'] : null;
    if (content is! List || content.isEmpty) {
      throw const ChatTitleException('Title model returned no content');
    }
    return content
        .whereType<Map<String, dynamic>>()
        .map((part) => _string(part['text']))
        .where((text) => text.isNotEmpty)
        .join(' ');
  }

  /// Writes a title-client diagnostic line when logging is configured.
  Future<void> _log(String message) async {
    await logger?.write('chat-title-client', message);
  }

  /// Resolves an API key reference from the configured environment.
  String _apiKey(String reference) {
    if (reference.isEmpty) {
      return '';
    }
    final fromEnvironment = _environment[reference];
    if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
      return fromEnvironment;
    }
    if (RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(reference)) {
      throw ChatTitleException('Environment variable $reference is not set');
    }
    return reference;
  }
}

/// Builds the OpenAI-compatible request body for title generation.
Map<String, dynamic> _openAiRequestBody(String model, String transcript) {
  final usesCompletionTokens = _usesCompletionTokenLimit(model);
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

/// Returns whether a chat-completions model requires max_completion_tokens.
bool _usesCompletionTokenLimit(String model) {
  final normalized = model.trim().toLowerCase();
  return normalized.startsWith('gpt-5') ||
      normalized.startsWith('o1') ||
      normalized.startsWith('o3') ||
      normalized.startsWith('o4');
}

/// _TitleModelSelection is the resolved model invocation target.
class _TitleModelSelection {
  /// Creates a resolved title model selection.
  const _TitleModelSelection({
    required this.adapter,
    required this.url,
    required this.apiKey,
    required this.model,
  });

  /// Provider adapter name.
  final String adapter;

  /// HTTP endpoint used for generation.
  final String url;

  /// Resolved provider API key.
  final String apiKey;

  /// Provider-specific model identifier sent on the wire.
  final String model;
}

/// Converts a YAML object graph to plain Dart collection types.
dynamic _plainYaml(dynamic value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _plainYaml(entry.value),
    };
  }
  if (value is YamlList) {
    return value.map(_plainYaml).toList();
  }
  return value;
}

/// Parses a provider:model default reference.
({String provider, String model}) _parseDefault(String value) {
  final parts = value.split(':');
  if (parts.length == 1) {
    return (provider: parts.first.trim(), model: '');
  }
  return (
    provider: parts.first.trim(),
    model: parts.sublist(1).join(':').trim(),
  );
}

/// Resolves the wire model name from a provider model list.
String _resolveModel(Map<String, dynamic> provider, String modelId) {
  final id = modelId.trim();
  final models = provider['models'];
  if (models is List) {
    for (final rawModel in models) {
      if (rawModel is! Map<String, dynamic>) {
        continue;
      }
      if (_string(rawModel['id']) == id) {
        return _string(rawModel['model'], fallback: id);
      }
    }
  }
  if (id.isNotEmpty) {
    return id;
  }
  throw const ChatTitleException('Summary model default model is missing');
}

/// Returns the request URL for the configured provider.
String _providerUrl(
  Map<String, dynamic> provider,
  String localModelChatCompletionsUrl,
) {
  final explicit = _string(provider['url']);
  if (explicit.isNotEmpty) {
    return explicit;
  }
  final adapter = _string(provider['adapter'], fallback: 'openai');
  if (adapter == 'litert' && localModelChatCompletionsUrl.isNotEmpty) {
    return localModelChatCompletionsUrl;
  }
  final base = _string(provider['base_url'] ?? provider['base-url']);
  if (base.isEmpty) {
    if (adapter == 'openai') {
      return 'https://api.openai.com/v1/chat/completions';
    }
    if (adapter == 'anthropic') {
      return 'https://api.anthropic.com/v1/messages';
    }
    throw const ChatTitleException('Provider url or base_url is required');
  }
  final trimmed = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  return adapter == 'anthropic'
      ? '$trimmed/messages'
      : '$trimmed/chat/completions';
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

/// Converts a dynamic scalar to a string.
String _string(dynamic value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
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

/// Clips long provider error bodies for chat title storage.
String _clip(String value) {
  const limit = 500;
  if (value.length <= limit) {
    return value;
  }
  return '${value.substring(0, limit)}...';
}

const String _titleSystemPrompt =
    'Create a concise title for this chat. Return only 2 to 6 words. '
    'Do not use quotation marks, punctuation, emoji, or a prefix.';
