/// Calls an app-owned model for structured screen-command plans.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../app/app_logger.dart';
import '../domain/screen_command.dart';

/// ScreenCommandPlanner describes a structured AI planner dependency.
abstract class ScreenCommandPlanner {
  /// Plans one Backlog command from a compact screen snapshot.
  Future<ScreenCommandRun> planBacklogCommand({
    required String modelConfigPath,
    String modelRef = '',
    required String command,
    required BacklogScreenSnapshot snapshot,
  });
}

/// ScreenCommandException reports screen-planner request failures.
class ScreenCommandException implements Exception {
  /// Creates a screen-command exception.
  const ScreenCommandException(this.message);

  /// Human-readable failure detail.
  final String message;

  @override
  String toString() => 'ScreenCommandException: $message';
}

/// ScreenCommandClient asks the configured model for strict JSON plans.
class ScreenCommandClient implements ScreenCommandPlanner {
  /// Creates a screen-command client using process environment credentials.
  ScreenCommandClient({
    http.Client? httpClient,
    Map<String, String>? environment,
    this.logger,
  }) : _http = httpClient ?? http.Client(),
       _environment = environment ?? Platform.environment;

  final http.Client _http;
  final Map<String, String> _environment;

  /// Optional persistent logger.
  final AppLogger? logger;

  /// Plans one Backlog command without exposing write tools to the model.
  @override
  Future<ScreenCommandRun> planBacklogCommand({
    required String modelConfigPath,
    String modelRef = '',
    required String command,
    required BacklogScreenSnapshot snapshot,
  }) async {
    final selection = await _loadSelection(modelConfigPath, modelRef);
    final prompt = _backlogPlannerPrompt(command: command, snapshot: snapshot);
    await _log(
      'plan backlog command adapter=${selection.adapter} model=${selection.model} promptLength=${prompt.length}',
    );
    final raw = switch (selection.adapter) {
      'anthropic' => await _callAnthropic(selection, prompt),
      'openai' || 'openai_compatible' => await _callOpenAi(selection, prompt),
      _ => throw ScreenCommandException(
        'Unsupported screen planner adapter "${selection.adapter}"',
      ),
    };
    return parseScreenCommandRun(raw, command: command);
  }

  /// Closes the underlying HTTP client.
  void close() {
    _http.close();
  }

  /// Resolves the configured provider, model, endpoint, and credential.
  Future<_ScreenModelSelection> _loadSelection(
    String modelConfigPath,
    String modelRef,
  ) async {
    final path = modelConfigPath.trim();
    if (path.isEmpty) {
      throw const ScreenCommandException(
        'Screen planner model is not selected',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      throw ScreenCommandException(
        'Screen planner model config is missing: $path',
      );
    }
    final decoded = _plainYaml(loadYaml(await file.readAsString()));
    if (decoded is! Map<String, dynamic>) {
      throw const ScreenCommandException(
        'Screen planner model config must be a map',
      );
    }
    final providers = decoded['providers'];
    if (providers is! Map<String, dynamic> || providers.isEmpty) {
      throw const ScreenCommandException(
        'Screen planner model config has no providers',
      );
    }
    final configuredRef = modelRef.trim();
    final defaultRef = _string(decoded['default']);
    final parsedDefault = _parseDefault(
      configuredRef.isEmpty ? defaultRef : configuredRef,
    );
    final providerName = parsedDefault.provider;
    if (providerName.isEmpty) {
      throw const ScreenCommandException(
        'Screen planner model is not selected',
      );
    }
    final provider = providers[providerName];
    if (provider is! Map<String, dynamic>) {
      throw ScreenCommandException(
        'Provider "$providerName" is not configured',
      );
    }
    final modelId = parsedDefault.model.isEmpty
        ? _string(provider['default'])
        : parsedDefault.model;
    return _ScreenModelSelection(
      adapter: _string(provider['adapter'], fallback: 'openai'),
      url: _providerUrl(provider),
      apiKey: _apiKey(_string(provider['api-key'] ?? provider['api_key'])),
      model: _resolveModel(provider, modelId),
    );
  }

  /// Calls an OpenAI-compatible chat-completions endpoint for a JSON plan.
  Future<String> _callOpenAi(
    _ScreenModelSelection selection,
    String prompt,
  ) async {
    final response = await _http.post(
      Uri.parse(selection.url),
      headers: <String, String>{
        'Content-Type': 'application/json',
        if (selection.apiKey.isNotEmpty)
          'Authorization': 'Bearer ${selection.apiKey}',
      },
      body: jsonEncode(_openAiRequestBody(selection.model, prompt)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ScreenCommandException(
        'Screen planner HTTP ${response.statusCode}: ${_clip(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body);
    final choices = decoded is Map<String, dynamic> ? decoded['choices'] : null;
    if (choices is! List || choices.isEmpty) {
      throw const ScreenCommandException('Screen planner returned no choices');
    }
    final first = choices.first;
    final message = first is Map<String, dynamic> ? first['message'] : null;
    final content = message is Map<String, dynamic> ? message['content'] : null;
    final text = _string(content);
    if (text.isEmpty) {
      throw const ScreenCommandException(
        'Screen planner returned empty content',
      );
    }
    return text;
  }

  /// Calls an Anthropic messages endpoint for a JSON plan.
  Future<String> _callAnthropic(
    _ScreenModelSelection selection,
    String prompt,
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
        'max_tokens': 1600,
        'temperature': 0.1,
        'system': _plannerSystemPrompt,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': prompt},
        ],
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ScreenCommandException(
        'Screen planner HTTP ${response.statusCode}: ${_clip(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body);
    final content = decoded is Map<String, dynamic> ? decoded['content'] : null;
    if (content is! List || content.isEmpty) {
      throw const ScreenCommandException('Screen planner returned no content');
    }
    final text = content
        .whereType<Map<String, dynamic>>()
        .map((part) => _string(part['text']))
        .where((part) => part.isNotEmpty)
        .join(' ')
        .trim();
    if (text.isEmpty) {
      throw const ScreenCommandException('Screen planner returned empty text');
    }
    return text;
  }

  /// Writes a planner-client diagnostic when logging is configured.
  Future<void> _log(String message) async {
    await logger?.write('screen-command-client', message);
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
      throw ScreenCommandException(
        'Environment variable $reference is not set',
      );
    }
    return reference;
  }
}

/// _ScreenModelSelection stores a resolved model endpoint.
class _ScreenModelSelection {
  /// Creates a resolved model endpoint.
  const _ScreenModelSelection({
    required this.adapter,
    required this.url,
    required this.apiKey,
    required this.model,
  });

  /// Provider adapter.
  final String adapter;

  /// HTTP endpoint URL.
  final String url;

  /// Resolved API key.
  final String apiKey;

  /// Provider-native model name.
  final String model;
}

/// Builds an OpenAI-compatible request body for one planner call.
Map<String, dynamic> _openAiRequestBody(String model, String prompt) {
  final usesCompletionTokens = _usesCompletionTokenLimit(model);
  return <String, dynamic>{
    'model': model,
    'temperature': 0.1,
    if (usesCompletionTokens)
      'max_completion_tokens': 1600
    else
      'max_tokens': 1600,
    'stream': false,
    'messages': <Map<String, String>>[
      <String, String>{'role': 'system', 'content': _plannerSystemPrompt},
      <String, String>{'role': 'user', 'content': prompt},
    ],
  };
}

/// Returns whether a model requires max_completion_tokens.
bool _usesCompletionTokenLimit(String model) {
  final normalized = model.trim().toLowerCase();
  return normalized.startsWith('gpt-5') ||
      normalized.startsWith('o1') ||
      normalized.startsWith('o3') ||
      normalized.startsWith('o4');
}

/// Builds the user prompt carrying command text and a Backlog snapshot.
String _backlogPlannerPrompt({
  required String command,
  required BacklogScreenSnapshot snapshot,
}) {
  return jsonEncode(<String, dynamic>{
    'user_command': command,
    'screen_snapshot': snapshot.toJson(),
    'allowed_response_schema': <String, dynamic>{
      'intent': 'change | question | clarification',
      'message': 'short answer or clarification when intent is not change',
      'confidence': 'number from 0 to 1',
      'changes': <Map<String, dynamic>>[
        <String, dynamic>{
          'operation':
              'create_task | update_task | complete_task | cancel_task | delete_task | upsert_task_relation | delete_task_relation | link_task_memory',
          'target': <String, dynamic>{
            'task_id': 'existing task id when applicable',
            'task_title': 'existing task title when task id is unknown',
          },
          'summary': 'short user-facing change summary',
          'reason': 'why this follows the command',
          'confidence': 'number from 0 to 1',
          'fields': <String, dynamic>{
            'field_name': 'new value for update_task or operation arguments',
          },
        },
      ],
    },
  });
}

const String _plannerSystemPrompt = '''
You plan UI-local Backlog screen commands for Aurora.
Return strict JSON only. Do not include Markdown, comments, or prose outside JSON.
Never call tools. Never claim a change was applied.
Classify informational requests as {"intent":"question"} and ambiguous mutation requests as {"intent":"clarification"}.
For mutations, use only task ids from the provided visible_tasks unless creating a task.
Use operation names exactly as specified in the schema.
Use field names from the graph task API: title, description, status, priority, due_at, scheduled_at, clear_due_at, clear_scheduled_at, topics, estimate_minutes, energy_required, effort, value, urgency, risk, context, view, project, location, person, source, confidence.
''';

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

/// Resolves the provider-native model name from the config model id.
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
  throw const ScreenCommandException('Screen planner default model is missing');
}

/// Returns the request URL for the configured provider.
String _providerUrl(Map<String, dynamic> provider) {
  final explicit = _string(provider['url']);
  if (explicit.isNotEmpty) {
    return explicit;
  }
  final adapter = _string(provider['adapter'], fallback: 'openai');
  final base = _string(provider['base_url'] ?? provider['base-url']);
  if (base.isEmpty) {
    if (adapter == 'openai') {
      return 'https://api.openai.com/v1/chat/completions';
    }
    if (adapter == 'anthropic') {
      return 'https://api.anthropic.com/v1/messages';
    }
    throw const ScreenCommandException('Provider url or base_url is required');
  }
  final trimmed = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  return adapter == 'anthropic'
      ? '$trimmed/messages'
      : '$trimmed/chat/completions';
}

/// Clips long provider error bodies for display and logs.
String _clip(String value) {
  const limit = 500;
  if (value.length <= limit) {
    return value;
  }
  return '${value.substring(0, limit)}...';
}

/// Converts a dynamic scalar to a trimmed string.
String _string(dynamic value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}
