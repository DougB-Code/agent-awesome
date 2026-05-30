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

  /// Deletes one editable workflow draft.
  Future<void> deleteDraft(String draftId) async {
    await _delete('/drafts/$draftId');
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

  /// Lists installed automation packages.
  Future<List<AutomationPackage>> listPackages() async {
    final decoded = await _get('/packages');
    return _list(decoded['packages']).map(parseAutomationPackage).toList();
  }

  /// Lists normalized harness capabilities.
  Future<List<AutomationCapability>> listCapabilities({
    String kind = '',
    bool? usableInChat,
    bool? usableInWorkflows,
  }) async {
    final query = <String, String>{
      if (kind.trim().isNotEmpty) 'kind': kind.trim(),
      if (usableInChat != null) 'usable_in_chat': '$usableInChat',
      if (usableInWorkflows != null)
        'usable_in_workflows': '$usableInWorkflows',
    };
    final decoded = await _capabilitiesGet('', query: query);
    return _list(
      decoded['capabilities'],
    ).map(parseAutomationCapability).toList();
  }

  /// Lists Computer or Server targets.
  Future<List<AutomationRuntimeTarget>> listRuntimeTargets() async {
    final decoded = await _runtimeTargetsGet('');
    return parseAutomationRuntimeTargets(decoded);
  }

  /// Loads one Computer or Server target.
  Future<AutomationRuntimeTarget> getRuntimeTarget(String targetId) async {
    final decoded = await _runtimeTargetsGet('/$targetId');
    return parseAutomationRuntimeTarget(decoded['target']);
  }

  /// Updates editable Computer or Server target fields.
  Future<AutomationRuntimeTarget> updateRuntimeTarget(
    AutomationRuntimeTarget target,
  ) async {
    final decoded = await _runtimeTargetsPut('/${target.id}', <String, dynamic>{
      'name': target.name,
      'status': target.status,
      'allowed_codebase_ids': target.allowedCodebaseIds,
      'secret_ref_count': target.secretRefCount,
    });
    return parseAutomationRuntimeTarget(decoded['target']);
  }

  /// Loads target health metadata.
  Future<AutomationTargetHealth> targetHealth(String targetId) async {
    final decoded = await _runtimeTargetsGet('/$targetId/health');
    return parseAutomationTargetHealth(decoded['health']);
  }

  /// Lists display-safe target logs.
  Future<List<AutomationTargetLogEntry>> targetLogs(String targetId) async {
    final decoded = await _runtimeTargetsGet('/$targetId/logs');
    return parseAutomationTargetLogs(decoded);
  }

  /// Loads target secret reference metadata.
  Future<AutomationTargetSecretMetadata> targetSecrets(String targetId) async {
    final decoded = await _runtimeTargetsGet('/$targetId/secrets');
    return parseAutomationTargetSecretMetadata(decoded['secrets']);
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

  /// Lists saved Operations.
  Future<List<AutomationRunSetup>> listRunSetups({
    String definitionId = '',
  }) async {
    final query = <String, String>{
      if (definitionId.trim().isNotEmpty) 'workflow_id': definitionId.trim(),
    };
    final decoded = await _operationsGet('', query: query);
    return _list(decoded['operations']).map(parseAutomationRunSetup).toList();
  }

  /// Creates one saved Operation.
  Future<AutomationRunSetup> createRunSetup({
    required String definitionId,
    required String name,
    String description = '',
    String codebaseId = '',
    String runtimeTargetId = '',
    String agentProfileId = '',
    Map<String, dynamic> input = const <String, dynamic>{},
    Map<String, dynamic> policy = const <String, dynamic>{},
    Map<String, dynamic> schedule = const <String, dynamic>{},
  }) async {
    final decoded = await _operationsPost('', <String, dynamic>{
      'workflow_id': definitionId,
      'name': name,
      'description': description,
      if (codebaseId.trim().isNotEmpty) 'codebase_id': codebaseId.trim(),
      if (runtimeTargetId.trim().isNotEmpty)
        'runtime_target_id': runtimeTargetId.trim(),
      if (agentProfileId.trim().isNotEmpty)
        'agent_profile_id': agentProfileId.trim(),
      'defaults': input,
      if (policy.isNotEmpty) 'policy': policy,
      if (schedule.isNotEmpty) 'schedule': schedule,
    });
    return parseAutomationRunSetup(decoded['operation']);
  }

  /// Updates one saved Operation.
  Future<AutomationRunSetup> updateRunSetup(AutomationRunSetup setup) async {
    final decoded = await _operationsPut('/${setup.id}', <String, dynamic>{
      'workflow_id': setup.definitionId,
      'name': setup.name,
      'description': setup.description,
      if (setup.codebaseId.trim().isNotEmpty)
        'codebase_id': setup.codebaseId.trim(),
      if (setup.runtimeTargetId.trim().isNotEmpty)
        'runtime_target_id': setup.runtimeTargetId.trim(),
      if (setup.agentProfileId.trim().isNotEmpty)
        'agent_profile_id': setup.agentProfileId.trim(),
      'defaults': setup.input,
      if (setup.policy.isNotEmpty) 'policy': setup.policy,
      if (setup.schedule.isNotEmpty) 'schedule': setup.schedule,
    });
    return parseAutomationRunSetup(decoded['operation']);
  }

  /// Deletes one saved Operation.
  Future<void> deleteRunSetup(String setupId) async {
    await _operationsDelete('/$setupId');
  }

  /// Previews one saved Operation without starting a run.
  Future<AutomationOperationPreview> previewRunSetup(
    String setupId, {
    Map<String, dynamic> input = const <String, dynamic>{},
  }) async {
    final decoded = await _operationsPost(
      '/$setupId/preview',
      <String, dynamic>{'input': input},
    );
    return parseAutomationOperationPreview(decoded['preview']);
  }

  /// Starts one saved Operation.
  Future<AutomationRun> startRunSetup(
    String setupId, {
    Map<String, dynamic> input = const <String, dynamic>{},
  }) async {
    final decoded = await _operationsPost('/$setupId/start', <String, dynamic>{
      'input': input,
    });
    final operationRun = _clientMap(decoded['operation_run']);
    return parseAutomationRun(operationRun['run']);
  }

  /// Loads immutable Operation audit data for one workflow run.
  Future<AutomationOperationRunSnapshot> operationRunSnapshot(
    String runId,
  ) async {
    final decoded = await _operationsGet('/runs/$runId/snapshot');
    return parseAutomationOperationRunSnapshot(decoded['snapshot']);
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

  Future<Map<String, dynamic>> _delete(String path) async {
    final uri = _uri(path);
    await _log('DELETE $uri');
    final response = await _http.delete(uri, headers: _headers());
    await _log('DELETE $uri -> ${response.statusCode}');
    return _decode(response, 'DELETE $path');
  }

  Future<Map<String, dynamic>> _operationsGet(
    String path, {
    Map<String, String> query = const <String, String>{},
  }) async {
    final uri = _operationsUri(path, query: query);
    await _log('GET $uri');
    final response = await _http.get(uri, headers: _headers());
    await _log('GET $uri -> ${response.statusCode}');
    return _decode(response, 'GET $path');
  }

  Future<Map<String, dynamic>> _operationsPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _operationsUri(path);
    await _log('POST $uri');
    final response = await _http.post(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(body),
    );
    await _log('POST $uri -> ${response.statusCode}');
    return _decode(response, 'POST $path');
  }

  Future<Map<String, dynamic>> _operationsPut(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _operationsUri(path);
    await _log('PUT $uri');
    final response = await _http.put(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(body),
    );
    await _log('PUT $uri -> ${response.statusCode}');
    return _decode(response, 'PUT $path');
  }

  Future<Map<String, dynamic>> _operationsDelete(String path) async {
    final uri = _operationsUri(path);
    await _log('DELETE $uri');
    final response = await _http.delete(uri, headers: _headers());
    await _log('DELETE $uri -> ${response.statusCode}');
    return _decode(response, 'DELETE $path');
  }

  Future<Map<String, dynamic>> _capabilitiesGet(
    String path, {
    Map<String, String> query = const <String, String>{},
  }) async {
    final uri = _capabilitiesUri(path, query: query);
    await _log('GET $uri');
    final response = await _http.get(uri, headers: _headers());
    await _log('GET $uri -> ${response.statusCode}');
    return _decode(response, 'GET $path');
  }

  Future<Map<String, dynamic>> _runtimeTargetsGet(
    String path, {
    Map<String, String> query = const <String, String>{},
  }) async {
    final uri = _runtimeTargetsUri(path, query: query);
    await _log('GET $uri');
    final response = await _http.get(uri, headers: _headers());
    await _log('GET $uri -> ${response.statusCode}');
    return _decode(response, 'GET $path');
  }

  Future<Map<String, dynamic>> _runtimeTargetsPut(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _runtimeTargetsUri(path);
    await _log('PUT $uri');
    final response = await _http.put(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(body),
    );
    await _log('PUT $uri -> ${response.statusCode}');
    return _decode(response, 'PUT $path');
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

  Uri _operationsUri(
    String path, {
    Map<String, String> query = const <String, String>{},
  }) {
    final workflow = Uri.parse(baseUrl);
    final operationsBase = workflow.replace(path: '/api/operations');
    final trimmed = operationsBase.toString().endsWith('/')
        ? operationsBase.toString().substring(
            0,
            operationsBase.toString().length - 1,
          )
        : operationsBase.toString();
    final uri = Uri.parse('$trimmed$path');
    if (query.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: query);
  }

  Uri _capabilitiesUri(
    String path, {
    Map<String, String> query = const <String, String>{},
  }) {
    final workflow = Uri.parse(baseUrl);
    final capabilitiesBase = workflow.replace(path: '/api/capabilities');
    final trimmed = capabilitiesBase.toString().endsWith('/')
        ? capabilitiesBase.toString().substring(
            0,
            capabilitiesBase.toString().length - 1,
          )
        : capabilitiesBase.toString();
    final uri = Uri.parse('$trimmed$path');
    if (query.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: query);
  }

  Uri _runtimeTargetsUri(
    String path, {
    Map<String, String> query = const <String, String>{},
  }) {
    final workflow = Uri.parse(baseUrl);
    final targetsBase = workflow.replace(path: '/api/runtime-targets');
    final trimmed = targetsBase.toString().endsWith('/')
        ? targetsBase.toString().substring(0, targetsBase.toString().length - 1)
        : targetsBase.toString();
    final uri = Uri.parse('$trimmed$path');
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

Map<String, dynamic> _clientMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry('$key', value));
  }
  return const <String, dynamic>{};
}
