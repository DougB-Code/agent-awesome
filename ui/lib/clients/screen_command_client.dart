/// Calls an app-owned model for structured screen-command plans.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/screen_command.dart';
import 'client_logger.dart';
import 'model_invocation_config.dart';

/// ScreenCommandPlanner describes a structured AI planner dependency.
abstract class ScreenCommandPlanner {
  /// Plans one Backlog command from a compact screen snapshot.
  Future<ScreenCommandRun> planBacklogCommand({
    required String modelConfigContent,
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
  /// Creates a screen-command client with explicitly supplied credentials.
  ScreenCommandClient({
    http.Client? httpClient,
    Map<String, String> environment = const <String, String>{},
    this.logger,
  }) : _http = httpClient ?? http.Client(),
       _environment = environment;

  final http.Client _http;
  final Map<String, String> _environment;

  /// Optional persistent logger.
  final ClientLogger? logger;

  /// Plans one Backlog command without exposing write tools to the model.
  @override
  Future<ScreenCommandRun> planBacklogCommand({
    required String modelConfigContent,
    String modelRef = '',
    required String command,
    required BacklogScreenSnapshot snapshot,
  }) async {
    final selection = _loadSelection(modelConfigContent, modelRef);
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
  ModelInvocationConfig _loadSelection(
    String modelConfigContent,
    String modelRef,
  ) {
    try {
      return resolveModelInvocationConfig(
        modelConfigContent: modelConfigContent,
        modelRef: modelRef,
        environment: _environment,
        messages: const ModelInvocationConfigMessages(
          missingSelection: 'Screen planner model is not selected',
          missingProviders: 'Screen planner model config has no providers',
          missingDefaultModel: 'Screen planner default model is missing',
        ),
      );
    } on ModelInvocationConfigException catch (error) {
      throw ScreenCommandException(error.message);
    }
  }

  /// Calls an OpenAI-compatible chat-completions endpoint for a JSON plan.
  Future<String> _callOpenAi(
    ModelInvocationConfig selection,
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
        'Screen planner HTTP ${response.statusCode}: '
        '${clipProviderBody(response.body)}',
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
    final text = modelInvocationString(content);
    if (text.isEmpty) {
      throw const ScreenCommandException(
        'Screen planner returned empty content',
      );
    }
    return text;
  }

  /// Calls an Anthropic messages endpoint for a JSON plan.
  Future<String> _callAnthropic(
    ModelInvocationConfig selection,
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
        'Screen planner HTTP ${response.statusCode}: '
        '${clipProviderBody(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body);
    final content = decoded is Map<String, dynamic> ? decoded['content'] : null;
    if (content is! List || content.isEmpty) {
      throw const ScreenCommandException('Screen planner returned no content');
    }
    final text = content
        .whereType<Map<String, dynamic>>()
        .map((part) => modelInvocationString(part['text']))
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
}

/// Builds an OpenAI-compatible request body for one planner call.
Map<String, dynamic> _openAiRequestBody(String model, String prompt) {
  final usesCompletionTokens = usesCompletionTokenLimit(model);
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
You plan UI-local Backlog screen commands for Agent Awesome.
Return strict JSON only. Do not include Markdown, comments, or prose outside JSON.
Never call tools. Never claim a change was applied.
Classify informational requests as {"intent":"question"} and ambiguous mutation requests as {"intent":"clarification"}.
For mutations, use only task ids from the provided visible_tasks unless creating a task.
Use operation names exactly as specified in the schema.
Use field names from the graph task API: title, description, status, priority, due_at, scheduled_at, follow_up_at, clear_due_at, clear_scheduled_at, clear_follow_up_at, topics, estimate_minutes, urgency, project, location, person.
''';
