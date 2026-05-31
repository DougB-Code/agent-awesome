/// Low-level JSON-RPC and gateway transports for MCP-style tool calls.
part of 'mcp_client.dart';

class McpException implements Exception {
  /// Creates an MCP exception with a display message.
  const McpException(this.message);

  /// Error message.
  final String message;

  /// Formats the exception for logs and UI fallback details.
  @override
  String toString() => 'McpException: $message';
}

/// ToolRpcClient defines the common structured tool-call client contract.
abstract class ToolRpcClient {
  /// JSON-style endpoint or API base URL used by this client.
  String get endpoint;

  /// Calls a named tool and returns structured content.
  Future<dynamic> callTool(String name, [Map<String, dynamic>? arguments]);

  /// Lists tool names exposed through this client.
  Future<List<String>> listToolNames();

  /// Closes any owned HTTP resources.
  void close();
}

/// McpJsonRpcClient calls one streamable HTTP MCP JSON-RPC endpoint.
class McpJsonRpcClient implements ToolRpcClient {
  /// Creates a JSON-RPC client for an MCP endpoint.
  McpJsonRpcClient({
    required this.endpoint,
    http.Client? httpClient,
    Map<String, String> headers = const <String, String>{},
    this.logger,
  }) : headers = Map<String, String>.unmodifiable(headers),
       _http = httpClient ?? http.Client();

  /// JSON-RPC endpoint URL.
  @override
  final String endpoint;

  /// Headers applied to every MCP JSON-RPC request.
  final Map<String, String> headers;

  final http.Client _http;
  final ClientLogger? logger;
  int _nextId = 1;

  /// Calls an MCP tool and returns its structured content.
  @override
  Future<dynamic> callTool(
    String name, [
    Map<String, dynamic>? arguments,
  ]) async {
    final id = _nextId++;
    final effectiveArguments = _mcpEndpointArguments(endpoint, arguments);
    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/call',
      'params': <String, dynamic>{
        'name': name,
        'arguments': effectiveArguments,
      },
    };
    await _log('POST $endpoint tools/call id=$id name=$name');
    final response = await _http.post(
      Uri.parse(endpoint),
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(payload),
    );
    await _log('POST $endpoint tools/call id=$id -> ${response.statusCode}');
    if (response.statusCode != 200) {
      throw McpException('HTTP ${response.statusCode} from $endpoint');
    }
    final content = parseToolStructuredContent(jsonDecode(response.body));
    await _log('tools/call id=$id name=$name parsed');
    return content;
  }

  /// Lists tool names exposed by this MCP endpoint.
  @override
  Future<List<String>> listToolNames() async {
    final id = _nextId++;
    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/list',
      'params': <String, dynamic>{},
    };
    await _log('POST $endpoint tools/list id=$id');
    final response = await _http.post(
      Uri.parse(endpoint),
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(payload),
    );
    await _log('POST $endpoint tools/list id=$id -> ${response.statusCode}');
    if (response.statusCode != 200) {
      throw McpException('HTTP ${response.statusCode} from $endpoint');
    }
    return parseToolNames(jsonDecode(response.body));
  }

  /// Closes the underlying HTTP client.
  @override
  void close() {
    _http.close();
  }

  Future<void> _log(String message) async {
    await logger?.write('mcp-client', message);
  }

  Map<String, String> _headers({bool contentTypeJson = false}) {
    return <String, String>{
      ...headers,
      if (contentTypeJson) 'Content-Type': 'application/json',
    };
  }
}

/// GatewayContextClient calls harness-owned context tools through the gateway.
class GatewayContextClient implements ToolRpcClient {
  /// Creates a gateway context API client.
  GatewayContextClient({
    required this.baseUrl,
    http.Client? httpClient,
    Map<String, String> headers = const <String, String>{},
    this.domainId = '',
    this.logger,
  }) : headers = Map<String, String>.unmodifiable(headers),
       _http = httpClient ?? http.Client();

  /// Gateway context API base URL.
  final String baseUrl;

  /// Optional memory domain routed by the harness control plane.
  final String domainId;

  /// Headers applied to every gateway context API request.
  final Map<String, String> headers;

  final http.Client _http;
  final ClientLogger? logger;

  @override
  String get endpoint => baseUrl;

  /// Calls one harness-owned context tool.
  @override
  Future<dynamic> callTool(
    String name, [
    Map<String, dynamic>? arguments,
  ]) async {
    final uri = _uri('/tools/call');
    final effectiveArguments = Map<String, dynamic>.from(
      arguments ?? const <String, dynamic>{},
    );
    final argumentDomain = _removeMemoryDomainSelector(effectiveArguments);
    final selectedDomain = domainId.trim().isNotEmpty
        ? domainId.trim()
        : argumentDomain;
    await _log('POST $uri context tool name=$name');
    final response = await _http.post(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(<String, dynamic>{
        'name': name,
        if (selectedDomain.isNotEmpty) 'domain_id': selectedDomain,
        'arguments': effectiveArguments,
      }),
    );
    await _log('POST $uri context tool name=$name -> ${response.statusCode}');
    if (response.statusCode != 200) {
      throw McpException('HTTP ${response.statusCode} from $uri');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const McpException('Context response was not an object');
    }
    if (decoded['error'] != null) {
      throw McpException('Context error: ${decoded['error']}');
    }
    return decoded['structuredContent'];
  }

  /// Lists context tool names exposed by the harness.
  @override
  Future<List<String>> listToolNames() async {
    final uri = _uri('/tools/list');
    await _log('GET $uri context tools/list');
    final response = await _http.get(uri, headers: _headers());
    await _log('GET $uri context tools/list -> ${response.statusCode}');
    if (response.statusCode != 200) {
      throw McpException('HTTP ${response.statusCode} from $uri');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const McpException('Context tool list was not an object');
    }
    final tools = decoded['tools'];
    if (tools is! List<dynamic>) {
      throw const McpException('Context tools field was not a list');
    }
    return tools.whereType<String>().toList();
  }

  /// Closes the underlying HTTP client.
  @override
  void close() {
    _http.close();
  }

  Uri _uri(String path) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmed$path');
  }

  Future<void> _log(String message) async {
    await logger?.write('context-client', message);
  }

  Map<String, String> _headers({bool contentTypeJson = false}) {
    return <String, String>{
      ...headers,
      if (contentTypeJson) 'Content-Type': 'application/json',
    };
  }
}

/// Returns MCP tool arguments safe for a route-scoped gateway memory endpoint.
Map<String, dynamic> _mcpEndpointArguments(
  String endpoint,
  Map<String, dynamic>? arguments,
) {
  final effective = Map<String, dynamic>.from(
    arguments ?? const <String, dynamic>{},
  );
  if (_gatewayMemoryPathDomain(endpoint).isNotEmpty) {
    _removeMemoryDomainSelector(effective);
  }
  return effective;
}

/// Returns the memory domain selected by a gateway /mcp/{domain} endpoint.
String _gatewayMemoryPathDomain(String endpoint) {
  final uri = Uri.tryParse(endpoint);
  if (uri == null || uri.pathSegments.length != 2) {
    return '';
  }
  return uri.pathSegments[0] == 'mcp' ? uri.pathSegments[1].trim() : '';
}

/// Removes legacy in-argument memory selectors and returns the selected domain.
String _removeMemoryDomainSelector(Map<String, dynamic> arguments) {
  final selected = _stringArgument(arguments['domain_id']).isNotEmpty
      ? _stringArgument(arguments['domain_id'])
      : _stringArgument(arguments['firewall']);
  arguments.remove('domain_id');
  arguments.remove('firewall');
  return selected;
}

/// Returns a trimmed string argument when the value is string-like.
String _stringArgument(Object? value) {
  return value is String ? value.trim() : '';
}

/// Extracts structuredContent from a MCP tools/call response.
dynamic parseToolStructuredContent(dynamic decoded) {
  if (decoded is! Map<String, dynamic>) {
    throw const McpException('MCP response was not an object');
  }
  if (decoded['error'] != null) {
    throw McpException('JSON-RPC error: ${decoded['error']}');
  }
  final result = decoded['result'];
  if (result is! Map<String, dynamic>) {
    throw const McpException('MCP result was not an object');
  }
  if (result['isError'] == true) {
    throw McpException('Tool returned error: ${result['structuredContent']}');
  }
  return result['structuredContent'];
}

/// Extracts tool names from a MCP tools/list response.
List<String> parseToolNames(dynamic decoded) {
  if (decoded is! Map<String, dynamic>) {
    throw const McpException('MCP response was not an object');
  }
  if (decoded['error'] != null) {
    throw McpException('JSON-RPC error: ${decoded['error']}');
  }
  final result = decoded['result'];
  if (result is! Map<String, dynamic>) {
    throw const McpException('MCP tools/list result was not an object');
  }
  final tools = result['tools'];
  if (tools is! List) {
    return const <String>[];
  }
  return tools
      .whereType<Map<String, dynamic>>()
      .map((tool) => stringValue(tool['name']))
      .where((name) => name.isNotEmpty)
      .toList();
}
