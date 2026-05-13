/// Provides an assistant API client for sessions and streaming runs.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'client_logger.dart';

/// AssistantException reports an assistant API or stream parsing failure.
class AssistantException implements Exception {
  /// Creates an assistant exception with a display message.
  const AssistantException(this.message);

  /// Error message.
  final String message;

  /// Formats the exception for logs and UI fallback details.
  @override
  String toString() => 'AssistantException: $message';
}

/// AssistantEvent is a normalized assistant runtime event.
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

  /// Runtime event author.
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

/// AssistantClient calls the assistant API used by the Flutter workspace.
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

  /// Base URL of the assistant API.
  final String baseUrl;

  /// Assistant app name.
  final String appName;

  /// Assistant user id.
  final String userId;

  /// Headers applied to every assistant API request.
  final Map<String, String> headers;

  final http.Client _http;
  final ClientLogger? logger;

  /// Lists existing assistant sessions for the configured user.
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

  /// Creates a new assistant session.
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

  /// Deletes an assistant session.
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

  /// Loads normalized events for one assistant session.
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

  /// Sends a user message or confirmation reply and streams assistant events.
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
            'text': messageTextForAgent(text, sessionId: sessionId),
          }
        : <String, dynamic>{
            'functionResponse': <String, dynamic>{
              'id': confirmation.callId,
              'name': _runtimeConfirmationFunctionName,
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

/// Parses a session returned by the assistant sessions API.
ChatSession parseChatSession(dynamic value) {
  final map = value is Map<String, dynamic> ? value : <String, dynamic>{};
  final id = stringFrom(map['id'], fallback: 'session');
  final updatedSeconds = map['lastUpdateTime'];
  final updatedAt = updatedSeconds is num
      ? DateTime.fromMillisecondsSinceEpoch(updatedSeconds.toInt() * 1000)
      : DateTime.now();
  return ChatSession(id: id, title: titleFromSession(id), updatedAt: updatedAt);
}

/// Parses one assistant runtime event into a UI event.
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
  var errorMessage = stringFrom(event['errorMessage']);
  if (parts is List) {
    for (final rawPart in parts.whereType<Map<String, dynamic>>()) {
      if (rawPart['text'] != null) {
        text += displayTextFromRuntimePolicy(stringFrom(rawPart['text']));
      }
      final functionCall = rawPart['functionCall'];
      if (functionCall is Map<String, dynamic>) {
        final name = stringFrom(functionCall['name'], fallback: 'tool');
        if (name == _runtimeConfirmationFunctionName) {
          confirmation = parseConfirmation(functionCall);
        } else {
          final displayName = _displayToolName(name);
          toolActivity = ToolActivity(
            name: name,
            status: 'requested',
            summary: 'Agent Awesome requested $displayName',
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
        if (name == _runtimeConfirmationFunctionName) {
          continue;
        }
        final displayName = _displayToolName(name);
        final error = stringFrom(responseMap['error']);
        if (error.isNotEmpty && errorMessage.isEmpty) {
          errorMessage = 'Tool $displayName failed: $error';
        }
        toolActivity = ToolActivity(
          name: name,
          status: error.isEmpty ? 'completed' : 'failed',
          summary: error.isEmpty
              ? 'Tool response received'
              : 'Tool $displayName failed: $error',
        );
      }
    }
  }
  return AssistantEvent(
    id: stringFrom(
      event['id'],
      fallback: DateTime.now().microsecondsSinceEpoch.toString(),
    ),
    author: stringFrom(event['author'], fallback: 'Agent Awesome'),
    text: text,
    partial: event['partial'] == true,
    toolActivity: toolActivity,
    confirmation: confirmation,
    errorMessage: errorMessage,
  );
}

/// Parses an assistant confirmation function call.
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
      fallback: 'Agent Awesome wants to use a tool.',
    ),
    options: options,
    toolName: stringFrom(originalCallMap['name']),
  );
}

/// Internal confirmation function name used by the assistant runtime protocol.
const String _runtimeConfirmationFunctionName = 'adk_request_confirmation';

/// Returns a user-facing tool name for activity summaries.
String _displayToolName(String name) {
  return switch (name.trim()) {
    _runtimeConfirmationFunctionName => 'confirmation request',
    _ => name,
  };
}

/// Prefix used to strip persisted runtime policy text from older transcripts.
const String runtimePolicyPrefix =
    '[[AGENT_AWESOME_RUNTIME_POLICY: legacy persisted policy]]\n\n';

/// Prefix used to strip persisted session metadata from older transcripts.
const String runtimeSessionContextPrefix = '[[AGENT_AWESOME_SESSION_CONTEXT:';

/// Prefix that marks UI-generated policy repair turns as non-display content.
const String hiddenRuntimeMessagePrefix =
    '[[AGENT_AWESOME_HIDDEN_RUNTIME_MESSAGE]]\n';

/// Prefixes for runtime policy blocks that should never render in chat.
///
/// The AURORA entries are intentional old-transcript migration filters.
const List<String> _runtimePolicyPrefixes = <String>[
  '[[AGENT_AWESOME_RUNTIME_POLICY:',
  '[[AURORA_RUNTIME_POLICY:',
];

/// Prefixes for runtime session blocks that should never render in chat.
///
/// The AURORA entries are intentional old-transcript migration filters.
const List<String> _runtimeSessionContextPrefixes = <String>[
  runtimeSessionContextPrefix,
  '[[AURORA_SESSION_CONTEXT:',
];

/// Prefixes for hidden repair turns that should never render in chat.
///
/// The AURORA entry is an intentional old-transcript migration filter.
const List<String> _hiddenRuntimeMessagePrefixes = <String>[
  hiddenRuntimeMessagePrefix,
  '[[AURORA_HIDDEN_RUNTIME_MESSAGE]]\n',
];

/// Local model control-token fragments that should never render in chat.
const List<String> _localToolMarkupFragments = <String>[
  '<|tool_call>',
  '<|/tool_call|>',
  '<tool_call|>',
];

/// Returns user text without adding UI-owned runtime policy instructions.
String messageTextForAgent(String text, {String sessionId = ''}) {
  return text;
}

/// Removes local runtime policy wrappers before messages are displayed.
String displayTextFromRuntimePolicy(String text) {
  var visible = text;
  while (visible.isNotEmpty) {
    if (_startsWithAny(visible, _hiddenRuntimeMessagePrefixes)) {
      return '';
    }
    final stripped = _stripLeadingControlBlock(visible, <String>[
      ..._runtimePolicyPrefixes,
      ..._runtimeSessionContextPrefixes,
    ]);
    if (stripped == visible) {
      break;
    }
    visible = stripped;
  }
  if (_looksLikeLocalToolMarkup(visible)) {
    return '';
  }
  return visible;
}

/// Reports whether text starts with one of the supplied prefixes.
bool _startsWithAny(String text, List<String> prefixes) {
  return prefixes.any(text.startsWith);
}

/// Removes one leading double-bracket runtime control block.
String _stripLeadingControlBlock(String text, List<String> prefixes) {
  if (!_startsWithAny(text, prefixes)) {
    return text;
  }
  final end = text.indexOf(']]');
  if (end == -1) {
    return '';
  }
  return text.substring(end + 2).trimLeft();
}

/// Reports whether text appears to contain local model tool-call control markup.
bool _looksLikeLocalToolMarkup(String text) {
  final trimmed = text.trimLeft();
  return _localToolMarkupFragments.any(trimmed.contains);
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
