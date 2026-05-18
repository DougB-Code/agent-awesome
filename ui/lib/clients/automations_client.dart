/// Provides the gateway-backed Automations workflow client.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models_automation.dart';
import 'client_logger.dart';

/// AutomationsClientException reports workflow API failures.
class AutomationsClientException implements Exception {
  /// Creates an automation client exception.
  const AutomationsClientException(this.message);

  /// Display-safe error message.
  final String message;

  @override
  String toString() => 'AutomationsClientException: $message';
}

/// AutomationsClient calls gateway-routed workflow APIs.
class AutomationsClient {
  /// Creates a workflow client that only talks to gateway routes.
  AutomationsClient({
    required this.baseUrl,
    http.Client? httpClient,
    Map<String, String> headers = const <String, String>{},
    this.logger,
  }) : headers = Map<String, String>.unmodifiable(headers),
       _http = httpClient ?? http.Client();

  /// Gateway `/api/workflows` base URL.
  final String baseUrl;

  /// Headers applied to protected gateway requests.
  final Map<String, String> headers;

  final http.Client _http;
  final ClientLogger? logger;

  /// Lists authoring action types.
  Future<List<AutomationActionType>> listActionTypes() async {
    final decoded = await _get('/action-types');
    return _list(
      decoded['action_types'],
    ).map(parseAutomationActionType).toList();
  }

  /// Lists installed workflow definitions.
  Future<List<AutomationDefinition>> listDefinitions() async {
    final decoded = await _get('/definitions');
    return _list(
      decoded['definitions'],
    ).map(parseAutomationDefinition).toList();
  }

  /// Lists editable workflow drafts.
  Future<List<AutomationDraft>> listDrafts() async {
    final decoded = await _get('/drafts');
    return _list(decoded['drafts']).map(parseAutomationDraft).toList();
  }

  /// Creates one editable workflow draft.
  Future<AutomationDraft> createDraft({
    required String kind,
    required String name,
    String description = '',
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    final decoded = await _post('/drafts', <String, dynamic>{
      'kind': kind,
      'name': name,
      'description': description,
      'body': body,
    });
    return parseAutomationDraft(decoded['draft']);
  }

  /// Updates one editable workflow draft.
  Future<AutomationDraft> updateDraft(AutomationDraft draft) async {
    final decoded = await _put('/drafts/${draft.id}', <String, dynamic>{
      'kind': draft.kind,
      'name': draft.name,
      'description': draft.description,
      'body': draft.body,
    });
    return parseAutomationDraft(decoded['draft']);
  }

  /// Validates one workflow draft.
  Future<AutomationValidationResult> validateDraft(String draftId) async {
    final decoded = await _post(
      '/drafts/$draftId/validate',
      <String, dynamic>{},
    );
    return parseAutomationValidationResult(decoded['validation']);
  }

  /// Publishes one workflow draft.
  Future<AutomationDefinition> publishDraft(String draftId) async {
    final decoded = await _post(
      '/drafts/$draftId/publish',
      <String, dynamic>{},
    );
    return parseAutomationDefinition(decoded['definition']);
  }

  /// Lists workflow templates.
  Future<List<AutomationTemplate>> listTemplates() async {
    final decoded = await _get('/templates');
    return _list(decoded['templates']).map(parseAutomationTemplate).toList();
  }

  /// Lists reusable workflow agent specs.
  Future<List<AutomationAgentSpec>> listAgentSpecs() async {
    final decoded = await _get('/agent-specs');
    return _list(decoded['agent_specs']).map(parseAutomationAgentSpec).toList();
  }

  /// Creates one reusable workflow agent spec.
  Future<AutomationAgentSpec> createAgentSpec({
    String id = '',
    required String name,
    String description = '',
    String instructions = '',
    AutomationAgentPermissions permissions = const AutomationAgentPermissions(),
  }) async {
    final decoded = await _post('/agent-specs', <String, dynamic>{
      if (id.trim().isNotEmpty) 'id': id.trim(),
      'name': name,
      'description': description,
      'instructions': instructions,
      'permissions': permissions.toJson(),
    });
    return parseAutomationAgentSpec(decoded['agent_spec']);
  }

  /// Updates one reusable workflow agent spec.
  Future<AutomationAgentSpec> updateAgentSpec(AutomationAgentSpec spec) async {
    final decoded = await _put('/agent-specs/${spec.id}', <String, dynamic>{
      'name': spec.name,
      'description': spec.description,
      'instructions': spec.instructions,
      'permissions': spec.permissions.toJson(),
    });
    return parseAutomationAgentSpec(decoded['agent_spec']);
  }

  /// Deletes one reusable workflow agent spec.
  Future<void> deleteAgentSpec(String specId) async {
    await _delete('/agent-specs/$specId');
  }

  /// Instantiates one template as an editable draft.
  Future<AutomationDraft> instantiateTemplate(
    String templateId, {
    String name = '',
    Map<String, dynamic> parameters = const <String, dynamic>{},
  }) async {
    final decoded = await _post(
      '/templates/$templateId/instantiate',
      <String, dynamic>{'name': name, 'parameters': parameters},
    );
    return parseAutomationDraft(decoded['draft']);
  }

  /// Lists installed automation packages.
  Future<List<AutomationPackage>> listPackages() async {
    final decoded = await _get('/packages');
    return _list(decoded['packages']).map(parseAutomationPackage).toList();
  }

  /// Lists workflow runs for operations.
  Future<List<AutomationRun>> listRuns({
    String status = '',
    String definitionId = '',
    int limit = 100,
  }) async {
    final query = <String, String>{
      if (status.trim().isNotEmpty) 'status': status.trim(),
      if (definitionId.trim().isNotEmpty) 'definition_id': definitionId.trim(),
      'limit': '$limit',
    };
    final decoded = await _get('/runs', query: query);
    return _list(decoded['runs']).map(parseAutomationRun).toList();
  }

  /// Starts one workflow definition.
  Future<AutomationRun> startRun(
    String definitionId, {
    Map<String, dynamic> input = const <String, dynamic>{},
  }) async {
    final decoded = await _post('/runs', <String, dynamic>{
      'definition_id': definitionId,
      'input': input,
    });
    return parseAutomationRun(decoded['run']);
  }

  /// Lists one run event history.
  Future<List<AutomationEvent>> history(String runId) async {
    final decoded = await _get('/runs/$runId/history');
    return _list(decoded['events']).map(parseAutomationEvent).toList();
  }

  /// Lists pending user-facing workflow inbox items.
  Future<List<AutomationPendingItem>> inbox() async {
    final decoded = await _get('/inbox');
    return _list(decoded['items']).map(parseAutomationPendingItem).toList();
  }

  /// Sends one signal to a workflow run.
  Future<AutomationRun> signal(
    String runId,
    String signal, {
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    final decoded = await _post('/runs/$runId/signal', <String, dynamic>{
      'signal': signal,
      'payload': payload,
    });
    return parseAutomationRun(decoded['run']);
  }

  /// Cancels one workflow run.
  Future<AutomationRun> cancel(String runId) async {
    final decoded = await _post('/runs/$runId/cancel', <String, dynamic>{});
    return parseAutomationRun(decoded['run']);
  }

  /// Releases the underlying HTTP client.
  void close() {
    _http.close();
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String> query = const <String, String>{},
  }) async {
    final uri = _uri(path, query: query);
    await _log('GET $uri');
    final response = await _http.get(uri, headers: _headers());
    await _log('GET $uri -> ${response.statusCode}');
    return _decode(response, 'GET $path');
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _uri(path);
    await _log('POST $uri');
    final response = await _http.post(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(body),
    );
    await _log('POST $uri -> ${response.statusCode}');
    return _decode(response, 'POST $path');
  }

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _uri(path);
    await _log('PUT $uri');
    final response = await _http.put(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(body),
    );
    await _log('PUT $uri -> ${response.statusCode}');
    return _decode(response, 'PUT $path');
  }

  /// Sends a DELETE request to the workflow API.
  Future<Map<String, dynamic>> _delete(String path) async {
    final uri = _uri(path);
    await _log('DELETE $uri');
    final response = await _http.delete(uri, headers: _headers());
    await _log('DELETE $uri -> ${response.statusCode}');
    return _decode(response, 'DELETE $path');
  }

  Map<String, dynamic> _decode(http.Response response, String operation) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AutomationsClientException(
        '$operation failed with HTTP ${response.statusCode}: ${response.body}',
      );
    }
    if (response.body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
    return const <String, dynamic>{};
  }

  Uri _uri(
    String path, {
    Map<String, String> query = const <String, String>{},
  }) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse('$base$path');
    if (query.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: query);
  }

  Map<String, String> _headers({bool contentTypeJson = false}) {
    return <String, String>{
      ...headers,
      if (contentTypeJson) 'Content-Type': 'application/json',
    };
  }

  Future<void> _log(String message) async {
    await logger?.write('automations-client', message);
  }
}

List<dynamic> _list(dynamic value) {
  if (value is List) {
    return value;
  }
  return const <dynamic>[];
}
