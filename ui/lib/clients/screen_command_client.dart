/// Plans structured screen commands through the ADK runtime.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/screen_command.dart';
import 'adk_utility_client.dart';
import 'client_logger.dart';
import 'model_ref_selection.dart';

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

/// ScreenCommandClient asks ADK for strict JSON screen-command plans.
class ScreenCommandClient implements ScreenCommandPlanner {
  /// Creates a screen-command client for one ADK app and user.
  ScreenCommandClient({
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

  /// Plans one Backlog command without exposing write tools to the model.
  @override
  Future<ScreenCommandRun> planBacklogCommand({
    required String modelConfigContent,
    String modelRef = '',
    required String command,
    required BacklogScreenSnapshot snapshot,
  }) async {
    final selectedModelRef = _selectedModelRef(modelConfigContent, modelRef);
    final prompt = _backlogPlannerPrompt(command: command, snapshot: snapshot);
    await _log(
      'plan backlog command modelRef=$selectedModelRef promptLength=${prompt.length}',
    );
    final raw = await _runPrompt(selectedModelRef, prompt);
    return parseScreenCommandRun(raw, command: command);
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
        missingSelection: 'Screen planner model is not selected',
        missingProviders: 'Screen planner model config has no providers',
        missingDefaultModel: 'Screen planner default model is missing',
      );
    } on ModelRefSelectionException catch (error) {
      throw ScreenCommandException(error.message);
    }
  }

  Future<String> _runPrompt(String modelRef, String prompt) async {
    try {
      return await _utility.runText(
        modelRef: modelRef,
        logName: 'screen-command-client',
        prompt: '$_plannerSystemPrompt\n\n$prompt',
      );
    } on AdkUtilityException catch (error) {
      throw ScreenCommandException(error.message);
    }
  }

  /// Writes a planner-client diagnostic when logging is configured.
  Future<void> _log(String message) async {
    await logger?.write('screen-command-client', message);
  }
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
