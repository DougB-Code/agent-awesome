/// Provides an ADK REST client for assistant sessions and streaming runs.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/app_logger.dart';
import '../domain/models.dart';

/// AssistantException reports an ADK REST or stream parsing failure.
class AssistantException implements Exception {
  /// Creates an assistant exception with a display message.
  const AssistantException(this.message);

  /// Error message.
  final String message;

  /// Formats the exception for logs and UI fallback details.
  @override
  String toString() => 'AssistantException: $message';
}

/// AssistantEvent is a normalized ADK runtime event.
class AssistantEvent {
  /// Creates a normalized assistant event.
  const AssistantEvent({
    required this.id,
    required this.author,
    required this.text,
    required this.partial,
    this.toolActivity,
    this.confirmation,
    this.errorMessage = '',
  });

  /// Event id.
  final String id;

  /// ADK event author.
  final String author;

  /// Text content, if present.
  final String text;

  /// Whether this is a partial streaming event.
  final bool partial;

  /// Tool activity, if present.
  final ToolActivity? toolActivity;

  /// Confirmation request, if present.
  final ConfirmationRequest? confirmation;

  /// Error message, if present.
  final String errorMessage;
}

/// AssistantClient calls the ADK REST API used by the Flutter workspace.
class AssistantClient {
  /// Creates an assistant client.
  AssistantClient({
    required this.baseUrl,
    required this.appName,
    required this.userId,
    http.Client? httpClient,
    Map<String, String> headers = const <String, String>{},
    this.logger,
  }) : headers = Map<String, String>.unmodifiable(headers),
       _http = httpClient ?? http.Client();

  /// Base URL of the ADK REST API.
  final String baseUrl;

  /// ADK app name.
  final String appName;

  /// ADK user id.
  final String userId;

  /// Headers applied to every assistant API request.
  final Map<String, String> headers;

  final http.Client _http;
  final AppLogger? logger;

  /// Lists existing ADK sessions for the configured user.
  Future<List<ChatSession>> listSessions() async {
    final uri = _uri('/apps/$appName/users/$userId/sessions');
    await _log('GET $uri');
    final response = await _http.get(uri, headers: _headers());
    await _log('GET $uri -> ${response.statusCode}');
    if (response.statusCode != 200) {
      throw AssistantException('HTTP ${response.statusCode} listing sessions');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return const <ChatSession>[];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(parseChatSession)
        .toList();
  }

  /// Creates a new ADK session.
  Future<ChatSession> createSession() async {
    final uri = _uri('/apps/$appName/users/$userId/sessions');
    await _log('POST $uri create session');
    final response = await _http.post(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(<String, dynamic>{'state': <String, dynamic>{}}),
    );
    await _log('POST $uri -> ${response.statusCode}');
    if (response.statusCode != 200) {
      throw AssistantException('HTTP ${response.statusCode} creating session');
    }
    return parseChatSession(jsonDecode(response.body));
  }

  /// Deletes an ADK session.
  Future<void> deleteSession(String sessionId) async {
    final uri = _uri('/apps/$appName/users/$userId/sessions/$sessionId');
    await _log('DELETE $uri');
    final response = await _http.delete(uri, headers: _headers());
    await _log('DELETE $uri -> ${response.statusCode}');
    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 404) {
      throw AssistantException('HTTP ${response.statusCode} deleting session');
    }
  }

  /// Loads normalized events for one ADK session.
  Future<List<AssistantEvent>> loadSessionEvents(String sessionId) async {
    final uri = _uri('/apps/$appName/users/$userId/sessions/$sessionId');
    await _log('GET $uri load session events');
    final response = await _http.get(uri, headers: _headers());
    await _log('GET $uri -> ${response.statusCode}');
    if (response.statusCode != 200) {
      throw AssistantException('HTTP ${response.statusCode} loading session');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const <AssistantEvent>[];
    }
    final events = decoded['events'];
    if (events is! List) {
      return const <AssistantEvent>[];
    }
    return events
        .whereType<Map<String, dynamic>>()
        .map(parseAssistantEvent)
        .toList();
  }

  /// Sends a user message or confirmation reply and streams ADK events.
  Stream<AssistantEvent> sendMessage({
    required String sessionId,
    String text = '',
    ConfirmationReply? confirmation,
  }) async* {
    final uri = _uri('/run_sse');
    await _log(
      'POST $uri run_sse session=$sessionId textLength=${text.length} confirmation=${confirmation != null}',
    );
    final request = http.Request('POST', uri);
    request.headers.addAll(_headers(contentTypeJson: true));
    request.body = jsonEncode(_runBody(sessionId, text, confirmation));
    final response = await _http.send(request);
    await _log('POST $uri -> ${response.statusCode}');
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      await _log('POST $uri error body: ${_clip(body)}');
      throw AssistantException(
        'HTTP ${response.statusCode} running agent: $body',
      );
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final buffer = StringBuffer();
    var eventType = 'message';
    var eventCount = 0;
    await for (final line in lines) {
      if (line.startsWith('data:')) {
        buffer.writeln(line.substring(5).trimLeft());
      } else if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.isEmpty && buffer.isNotEmpty) {
        final event = parseSseAssistantEvent(eventType, buffer.toString());
        eventCount++;
        await _log(
          'run_sse event #$eventCount author=${event.author} textLength=${event.text.length} partial=${event.partial} tool=${event.toolActivity?.name ?? ''} error=${event.errorMessage.isNotEmpty}',
        );
        yield event;
        buffer.clear();
        eventType = 'message';
      }
    }
    if (buffer.isNotEmpty) {
      final event = parseSseAssistantEvent(eventType, buffer.toString());
      eventCount++;
      await _log(
        'run_sse event #$eventCount author=${event.author} textLength=${event.text.length} partial=${event.partial} tool=${event.toolActivity?.name ?? ''} error=${event.errorMessage.isNotEmpty}',
      );
      yield event;
    }
    await _log('run_sse completed session=$sessionId events=$eventCount');
  }

  /// Closes the underlying HTTP client.
  void close() {
    _http.close();
  }

  Uri _uri(String path) {
    final trimmedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmedBase$path');
  }

  Map<String, String> _headers({bool contentTypeJson = false}) {
    return <String, String>{
      ...headers,
      if (contentTypeJson) 'Content-Type': 'application/json',
    };
  }

  Future<void> _log(String message) async {
    await logger?.write('assistant-client', message);
  }

  String _clip(String value) {
    const limit = 600;
    if (value.length <= limit) {
      return value;
    }
    return '${value.substring(0, limit)}...';
  }

  Map<String, dynamic> _runBody(
    String sessionId,
    String text,
    ConfirmationReply? confirmation,
  ) {
    final part = confirmation == null
        ? <String, dynamic>{
            'text': messageTextWithRuntimePolicy(text, sessionId: sessionId),
          }
        : <String, dynamic>{
            'functionResponse': <String, dynamic>{
              'id': confirmation.callId,
              'name': 'adk_request_confirmation',
              'response': <String, dynamic>{
                'confirmed': confirmation.confirmed,
                if (confirmation.confirmed && confirmation.action != null)
                  'payload': <String, dynamic>{'action': confirmation.action},
              },
            },
          };
    return <String, dynamic>{
      'appName': appName,
      'userId': userId,
      'sessionId': sessionId,
      'streaming': false,
      'newMessage': <String, dynamic>{
        'role': 'user',
        'parts': <Map<String, dynamic>>[part],
      },
    };
  }
}

/// Parses one SSE data payload into a normalized assistant event.
AssistantEvent parseSseAssistantEvent(String eventType, String data) {
  final decoded = jsonDecode(data);
  final event = decoded is Map<String, dynamic>
      ? decoded
      : <String, dynamic>{'error': decoded.toString()};
  if (eventType == 'error' || event['error'] != null) {
    return AssistantEvent(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      author: 'Runtime',
      text: '',
      partial: false,
      errorMessage: stringFrom(event['error'], fallback: data),
    );
  }
  return parseAssistantEvent(event);
}

/// Parses a session returned by the ADK sessions API.
ChatSession parseChatSession(dynamic value) {
  final map = value is Map<String, dynamic> ? value : <String, dynamic>{};
  final id = stringFrom(map['id'], fallback: 'session');
  final updatedSeconds = map['lastUpdateTime'];
  final updatedAt = updatedSeconds is num
      ? DateTime.fromMillisecondsSinceEpoch(updatedSeconds.toInt() * 1000)
      : DateTime.now();
  return ChatSession(id: id, title: titleFromSession(id), updatedAt: updatedAt);
}

/// Parses one ADK runtime event into a UI event.
AssistantEvent parseAssistantEvent(Map<String, dynamic> event) {
  if (event['error'] != null) {
    return AssistantEvent(
      id: stringFrom(
        event['id'],
        fallback: DateTime.now().microsecondsSinceEpoch.toString(),
      ),
      author: 'Runtime',
      text: '',
      partial: false,
      errorMessage: stringFrom(event['error']),
    );
  }
  final content = event['content'];
  final parts = content is Map<String, dynamic> ? content['parts'] : null;
  var text = '';
  ToolActivity? toolActivity;
  ConfirmationRequest? confirmation;
  if (parts is List) {
    for (final rawPart in parts.whereType<Map<String, dynamic>>()) {
      if (rawPart['text'] != null) {
        text += displayTextFromRuntimePolicy(stringFrom(rawPart['text']));
      }
      final functionCall = rawPart['functionCall'];
      if (functionCall is Map<String, dynamic>) {
        final name = stringFrom(functionCall['name'], fallback: 'tool');
        if (name == 'adk_request_confirmation') {
          confirmation = parseConfirmation(functionCall);
        } else {
          toolActivity = ToolActivity(
            name: name,
            status: 'requested',
            summary: 'Aurora requested $name',
          );
        }
      }
      final functionResponse = rawPart['functionResponse'];
      if (functionResponse is Map<String, dynamic>) {
        final name = stringFrom(functionResponse['name'], fallback: 'tool');
        final response = functionResponse['response'];
        final responseMap = response is Map<String, dynamic>
            ? response
            : <String, dynamic>{};
        final error = stringFrom(responseMap['error']);
        toolActivity = ToolActivity(
          name: name,
          status: error.isEmpty ? 'completed' : 'failed',
          summary: error.isEmpty
              ? 'Tool response received'
              : 'Tool $name failed: $error',
        );
      }
    }
  }
  return AssistantEvent(
    id: stringFrom(
      event['id'],
      fallback: DateTime.now().microsecondsSinceEpoch.toString(),
    ),
    author: stringFrom(event['author'], fallback: 'Aurora'),
    text: text,
    partial: event['partial'] == true,
    toolActivity: toolActivity,
    confirmation: confirmation,
    errorMessage: stringFrom(event['errorMessage']),
  );
}

/// Parses an ADK confirmation function call.
ConfirmationRequest parseConfirmation(Map<String, dynamic> functionCall) {
  final args = functionCall['args'];
  final argsMap = args is Map<String, dynamic> ? args : <String, dynamic>{};
  final body = argsMap['toolConfirmation'];
  final confirmation = body is Map<String, dynamic>
      ? body
      : <String, dynamic>{};
  final originalCall = argsMap['originalFunctionCall'];
  final originalCallMap = originalCall is Map<String, dynamic>
      ? originalCall
      : <String, dynamic>{};
  final payload = confirmation['payload'];
  final optionsSource = payload is Map<String, dynamic>
      ? payload['options']
      : null;
  final options = optionsSource is List
      ? optionsSource.whereType<Map<String, dynamic>>().map((option) {
          return ConfirmationOption(
            action: stringFrom(option['action'], fallback: 'approve_once'),
            label: stringFrom(option['label'], fallback: 'Approve once'),
          );
        }).toList()
      : const <ConfirmationOption>[
          ConfirmationOption(action: 'deny', label: 'Deny'),
          ConfirmationOption(action: 'approve_once', label: 'Approve once'),
        ];
  return ConfirmationRequest(
    callId: stringFrom(functionCall['id']),
    hint: stringFrom(
      confirmation['hint'],
      fallback: 'Aurora wants to use a tool.',
    ),
    options: options,
    toolName: stringFrom(originalCallMap['name']),
  );
}

/// Prefix that carries local UI policy to stale or long-running agents.
const String runtimePolicyPrefix =
    '[[AURORA_RUNTIME_POLICY: Graph-backed task management is auto-approved. '
    'When Doug asks to create, update, complete, cancel, delete, or link a '
    'task, call the task tool immediately. Do not ask for '
    'approval. Treat "remember that I need to..." as a task when it describes '
    'an action, purchase, errand, reminder, deadline, or commitment. Ask only '
    'for missing task details that block execution.]]\n\n';

/// Prefix for per-run session metadata hidden from the transcript.
const String runtimeSessionContextPrefix = '[[AURORA_SESSION_CONTEXT:';

/// Prefix that marks UI-generated policy repair turns as non-display content.
const String hiddenRuntimeMessagePrefix = '[[AURORA_HIDDEN_RUNTIME_MESSAGE]]\n';

/// Adds the runtime policy prefix to user messages sent to the agent.
String messageTextWithRuntimePolicy(String text, {String sessionId = ''}) {
  if (text.trim().isEmpty || text.startsWith(runtimePolicyPrefix)) {
    return text;
  }
  final trimmedSessionId = sessionId.trim();
  final sessionContext = trimmedSessionId.isEmpty
      ? ''
      : '$runtimeSessionContextPrefix Current chat session id is '
            '"$trimmedSessionId". For create_task calls made '
            'from this chat, include an idempotency_key beginning with '
            '"personal_pilot:$trimmedSessionId:".]]\n\n';
  return '$runtimePolicyPrefix$sessionContext$text';
}

/// Removes local runtime policy wrappers before messages are displayed.
String displayTextFromRuntimePolicy(String text) {
  var withoutPolicy = text.startsWith(runtimePolicyPrefix)
      ? text.substring(runtimePolicyPrefix.length)
      : text;
  if (withoutPolicy.startsWith(runtimeSessionContextPrefix)) {
    final end = withoutPolicy.indexOf(']]\n\n');
    withoutPolicy = end == -1 ? '' : withoutPolicy.substring(end + 4);
  }
  if (withoutPolicy.startsWith(hiddenRuntimeMessagePrefix)) {
    return '';
  }
  return withoutPolicy;
}

/// Converts a dynamic value to a string.
String stringFrom(dynamic value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

/// Builds a compact display title from a session id.
String titleFromSession(String id) {
  if (id.length <= 8) {
    return 'Chat $id';
  }
  return 'Chat ${id.substring(0, 8)}';
}
