/// Runs short utility prompts through the local ADK REST runtime.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'assistant_client.dart';
import 'client_logger.dart';

/// AdkUtilityException reports one-shot ADK request failures.
class AdkUtilityException implements Exception {
  /// Creates a utility runtime exception.
  const AdkUtilityException(this.message);

  /// Human-readable failure detail.
  final String message;

  @override
  String toString() => 'AdkUtilityException: $message';
}

/// AdkUtilityClient executes hidden one-shot prompts with ephemeral sessions.
class AdkUtilityClient {
  /// Creates a utility client for the configured ADK app and user.
  AdkUtilityClient({
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

  /// Headers applied to every request.
  final Map<String, String> headers;

  final http.Client _http;
  final ClientLogger? logger;

  /// Runs one prompt and returns the final assistant text.
  Future<String> runText({
    required String prompt,
    String modelRef = '',
    String logName = 'adk-utility-client',
  }) async {
    final sessionId = await _createSession(logName);
    try {
      return await _runSessionText(
        sessionId: sessionId,
        prompt: prompt,
        modelRef: modelRef,
        logName: logName,
      );
    } finally {
      await _deleteSession(sessionId, logName);
    }
  }

  /// Closes the underlying HTTP client.
  void close() {
    _http.close();
  }

  Future<String> _createSession(String logName) async {
    final uri = _sessionCollectionUri();
    await _log(logName, 'POST $uri create utility session');
    final response = await _http.post(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(<String, dynamic>{'state': <String, dynamic>{}}),
    );
    await _log(logName, 'POST $uri -> ${response.statusCode}');
    if (response.statusCode != 200) {
      throw AdkUtilityException(
        'HTTP ${response.statusCode} creating utility session',
      );
    }
    final decoded = jsonDecode(response.body);
    final sessionId = _stringFrom(
      decoded is Map<String, dynamic> ? decoded['id'] : null,
    );
    if (sessionId.isEmpty) {
      throw const AdkUtilityException('Utility session response had no id');
    }
    return sessionId;
  }

  Future<String> _runSessionText({
    required String sessionId,
    required String prompt,
    required String modelRef,
    required String logName,
  }) async {
    final uri = _uri('/run_sse');
    await _log(
      logName,
      'POST $uri run_sse utility session=$sessionId promptLength=${prompt.length} modelRef=$modelRef',
    );
    final request = http.Request('POST', uri);
    request.headers.addAll(_headers(contentTypeJson: true));
    request.body = jsonEncode(_runBody(sessionId, prompt, modelRef));
    final response = await _http.send(request);
    await _log(logName, 'POST $uri -> ${response.statusCode}');
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw AdkUtilityException(
        'HTTP ${response.statusCode} running utility prompt: $body',
      );
    }
    final text = await _readAssistantText(response.stream, logName);
    if (text.trim().isEmpty) {
      throw const AdkUtilityException('Utility prompt returned empty text');
    }
    return text.trim();
  }

  Future<String> _readAssistantText(
    Stream<List<int>> stream,
    String logName,
  ) async {
    final lines = stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final buffer = StringBuffer();
    final output = StringBuffer();
    var eventType = 'message';
    await for (final line in lines) {
      if (line.startsWith('data:')) {
        buffer.writeln(line.substring(5).trimLeft());
        continue;
      }
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
        continue;
      }
      if (line.isEmpty && buffer.isNotEmpty) {
        _appendUtilityEvent(output, eventType, buffer.toString());
        buffer.clear();
        eventType = 'message';
      }
    }
    if (buffer.isNotEmpty) {
      _appendUtilityEvent(output, eventType, buffer.toString());
    }
    await _log(logName, 'utility prompt textLength=${output.length}');
    return output.toString();
  }

  void _appendUtilityEvent(StringBuffer output, String eventType, String data) {
    final event = parseSseAssistantEvent(eventType, data);
    if (event.errorMessage.trim().isNotEmpty) {
      throw AdkUtilityException(event.errorMessage.trim());
    }
    if (event.toolActivity != null || event.confirmation != null) {
      throw const AdkUtilityException('Utility prompt attempted to use a tool');
    }
    if (event.text.isNotEmpty && !event.partial) {
      output.write(event.text);
    }
  }

  Future<void> _deleteSession(String sessionId, String logName) async {
    final uri = _sessionUri(sessionId);
    await _log(logName, 'DELETE $uri utility session');
    try {
      final response = await _http.delete(uri, headers: _headers());
      await _log(logName, 'DELETE $uri -> ${response.statusCode}');
    } catch (error) {
      await _log(logName, 'DELETE $uri failed: $error');
    }
  }

  Map<String, dynamic> _runBody(
    String sessionId,
    String prompt,
    String modelRef,
  ) {
    final normalizedModelRef = modelRef.trim();
    return <String, dynamic>{
      'appName': appName,
      'userId': userId,
      'sessionId': sessionId,
      'streaming': false,
      if (normalizedModelRef.isNotEmpty)
        'stateDelta': <String, dynamic>{
          runtimeModelRefStateKey: normalizedModelRef,
        },
      'newMessage': <String, dynamic>{
        'role': 'user',
        'parts': <Map<String, dynamic>>[
          <String, dynamic>{'text': prompt},
        ],
      },
    };
  }

  Uri _uri(String path) {
    final trimmedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmedBase$path');
  }

  Uri _sessionCollectionUri() {
    return _uri(
      '/apps/${Uri.encodeComponent(appName.trim())}'
      '/users/${Uri.encodeComponent(userId)}/sessions',
    );
  }

  Uri _sessionUri(String sessionId) {
    return _uri(
      '/apps/${Uri.encodeComponent(appName.trim())}'
      '/users/${Uri.encodeComponent(userId)}/sessions'
      '/${Uri.encodeComponent(sessionId)}',
    );
  }

  Map<String, String> _headers({bool contentTypeJson = false}) {
    return <String, String>{
      ...headers,
      if (contentTypeJson) 'Content-Type': 'application/json',
    };
  }

  Future<void> _log(String logName, String message) async {
    await logger?.write(logName, message);
  }
}

/// Returns a trimmed string representation for runtime JSON values.
String _stringFrom(dynamic value) {
  if (value == null) {
    return '';
  }
  return value.toString().trim();
}
