/// Builds bounded OpenAI-compatible prompts for local model runtimes.
library;

import 'dart:convert';

const int _defaultMaxPromptCharacters = 6000;
const int _defaultMaxMessageCharacters = 1200;
const int _defaultMaxToolSectionCharacters = 1600;
const int _defaultMinConversationCharacters = 1000;
const int _defaultMaxStructuredEntries = 8;
const int _defaultMaxStructuredItems = 4;
const int _defaultMaxStructuredDepth = 4;
const int _defaultMaxScalarCharacters = 240;
const String _openAIUserRole = 'user';
const String _openAIToolRole = 'tool';
const String _openAIDeveloperRole = 'developer';
const String _openAISystemRole = 'system';
const String _functionResponseKey = 'functionResponse';
const String _toolCallIdKey = 'tool_call_id';
const String _toolCallInstructionStart = '<|tool_call>';
const String _toolCallInstructionEnd = '<tool_call|>';
const String _omission = '...';

/// LocalModelOpenAiPromptBuilder converts chat requests to LiteRT prompts.
class LocalModelOpenAiPromptBuilder {
  /// Creates a prompt builder with conservative local-model limits.
  const LocalModelOpenAiPromptBuilder({
    this.maxPromptCharacters = _defaultMaxPromptCharacters,
    this.maxMessageCharacters = _defaultMaxMessageCharacters,
    this.maxToolSectionCharacters = _defaultMaxToolSectionCharacters,
    this.minConversationCharacters = _defaultMinConversationCharacters,
    this.maxStructuredEntries = _defaultMaxStructuredEntries,
    this.maxStructuredItems = _defaultMaxStructuredItems,
    this.maxStructuredDepth = _defaultMaxStructuredDepth,
    this.maxScalarCharacters = _defaultMaxScalarCharacters,
  }) : assert(maxPromptCharacters > 0),
       assert(maxMessageCharacters > 0),
       assert(maxToolSectionCharacters > 0),
       assert(minConversationCharacters > 0),
       assert(maxStructuredEntries > 0),
       assert(maxStructuredItems > 0),
       assert(maxStructuredDepth > 0),
       assert(maxScalarCharacters > 0);

  /// Maximum composed prompt characters passed to the local model CLI.
  final int maxPromptCharacters;

  /// Maximum characters retained for an individual chat message.
  final int maxMessageCharacters;

  /// Maximum characters retained for the generated tool instruction section.
  final int maxToolSectionCharacters;

  /// Prompt budget reserved for recent conversational turns.
  final int minConversationCharacters;

  /// Maximum map entries retained while summarizing structured tool output.
  final int maxStructuredEntries;

  /// Maximum list items retained while summarizing structured tool output.
  final int maxStructuredItems;

  /// Maximum nesting depth retained while summarizing structured tool output.
  final int maxStructuredDepth;

  /// Maximum scalar characters retained inside structured summaries.
  final int maxScalarCharacters;

  /// Builds a bounded LiteRT prompt from an OpenAI-compatible chat request.
  String build(Map<String, dynamic> request) {
    final messages = _messages(request);
    if (messages.isEmpty) {
      throw const FormatException('OpenAI request must include messages');
    }
    final prefixLines = _prefixLines(request, messages);
    final conversationLines = _conversationLines(messages);
    final prefixBudget = _prefixBudget(conversationLines);
    final selectedPrefix = _fitPrefix(prefixLines, prefixBudget);
    final separator = selectedPrefix.isEmpty ? 0 : 1;
    final conversationBudget =
        maxPromptCharacters - _joinedLength(selectedPrefix) - separator;
    var selectedConversation = _fitRecent(
      conversationLines,
      conversationBudget,
    );
    if (selectedConversation.isEmpty && conversationLines.isNotEmpty) {
      selectedPrefix.clear();
      selectedConversation = _fitRecent(conversationLines, maxPromptCharacters);
    }
    final prompt = <String>[
      ...selectedPrefix,
      ...selectedConversation,
    ].join('\n').trim();
    if (prompt.isEmpty) {
      throw const FormatException('OpenAI request has no text content');
    }
    return _truncateEnd(prompt, maxPromptCharacters);
  }

  /// Reports whether the request's latest turn may start local tool calls.
  bool toolCallsAllowed(Map<String, dynamic> request) {
    final messages = _messages(request);
    for (final message in messages.reversed) {
      if (_isToolResultMessage(message)) {
        return false;
      }
      if (_messageContentText(message.content).trim().isNotEmpty) {
        return message.role == _openAIUserRole;
      }
      if (message.toolCalls is List) {
        return message.role == _openAIUserRole;
      }
    }
    return false;
  }

  /// Returns normalized request messages from the decoded request body.
  List<_OpenAiPromptMessage> _messages(Map<String, dynamic> request) {
    final messages = request['messages'];
    if (messages is! List) {
      return const <_OpenAiPromptMessage>[];
    }
    return messages
        .whereType<Map<String, dynamic>>()
        .map(_OpenAiPromptMessage.new)
        .toList();
  }

  /// Builds prompt prefix lines for tools plus durable instructions.
  List<String> _prefixLines(
    Map<String, dynamic> request,
    List<_OpenAiPromptMessage> messages,
  ) {
    final lines = <String>[];
    if (toolCallsAllowed(request)) {
      final toolSection = _toolPromptSection(request['tools']);
      if (toolSection.isNotEmpty) {
        lines.add(_truncateEnd(toolSection, maxToolSectionCharacters));
      }
    }
    for (final message in messages) {
      if (_isInstructionRole(message.role)) {
        final line = _messageLine(message);
        if (line.isNotEmpty) {
          lines.add(line);
        }
      }
    }
    return lines;
  }

  /// Builds ordered conversation lines excluding durable instructions.
  List<String> _conversationLines(List<_OpenAiPromptMessage> messages) {
    final lines = <String>[];
    for (final message in messages) {
      if (_isInstructionRole(message.role)) {
        continue;
      }
      final line = _messageLine(message);
      if (line.isNotEmpty) {
        lines.add(line);
      }
    }
    return lines;
  }

  /// Returns the prompt budget available to prefix lines.
  int _prefixBudget(List<String> conversationLines) {
    if (conversationLines.isEmpty) {
      return maxPromptCharacters;
    }
    final reserve = minConversationCharacters > maxPromptCharacters
        ? maxPromptCharacters
        : minConversationCharacters;
    return maxPromptCharacters - reserve;
  }

  /// Formats one request message as a prompt line.
  String _messageLine(_OpenAiPromptMessage message) {
    final content = _messagePromptContent(message);
    if (content.trim().isEmpty) {
      return '';
    }
    final role = message.role.trim();
    final text = _truncateEnd(_cleanPromptText(content), maxMessageCharacters);
    if (role.isEmpty) {
      return text;
    }
    return '${role.toUpperCase()}: $text';
  }

  /// Returns the prompt content to use for one request message.
  String _messagePromptContent(_OpenAiPromptMessage message) {
    if (_isToolResultMessage(message)) {
      return _toolContentSummary(message.content);
    }
    return _messageContentText(message.content);
  }

  /// Reports whether a message represents tool output instead of user text.
  bool _isToolResultMessage(_OpenAiPromptMessage message) {
    if (message.role == _openAIToolRole) {
      return true;
    }
    if (message.source.containsKey(_toolCallIdKey)) {
      return true;
    }
    return _containsFunctionResponse(
      _decodedStructuredContent(message.content),
    );
  }

  /// Extracts plain text from supported OpenAI message content shapes.
  String _messageContentText(Object? content) {
    if (content is String) {
      return content;
    }
    if (content is List) {
      final parts = <String>[];
      for (final part in content) {
        if (part is String) {
          parts.add(part);
          continue;
        }
        if (part is Map<String, dynamic>) {
          final text = part['text'];
          if (text != null) {
            parts.add(text.toString());
          } else if (_containsFunctionResponse(part)) {
            parts.add(_compactStructuredValue(part));
          }
        }
      }
      return parts.where((part) => part.trim().isNotEmpty).join('\n');
    }
    if (content is Map<String, dynamic>) {
      return _compactStructuredValue(content);
    }
    return '';
  }

  /// Returns a compact summary for structured tool response content.
  String _toolContentSummary(Object? content) {
    final decoded = _decodedStructuredContent(content);
    if (decoded != null) {
      return _compactStructuredValue(decoded);
    }
    return _messageContentText(content);
  }

  /// Decodes structured JSON content when a message stores JSON text.
  Object? _decodedStructuredContent(Object? content) {
    if (content is Map<String, dynamic> || content is List) {
      return content;
    }
    if (content is! String) {
      return null;
    }
    final text = content.trim();
    if (text.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// Reports whether a structured value contains an ADK function response.
  bool _containsFunctionResponse(Object? value, [int depth = 0]) {
    if (depth > maxStructuredDepth) {
      return false;
    }
    if (value is Map) {
      if (value.containsKey(_functionResponseKey)) {
        return true;
      }
      for (final entry in value.entries) {
        if (_containsFunctionResponse(entry.value, depth + 1)) {
          return true;
        }
      }
    }
    if (value is List) {
      for (final item in value) {
        if (_containsFunctionResponse(item, depth + 1)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Returns a bounded textual representation of structured values.
  String _compactStructuredValue(Object? value, [int depth = 0]) {
    if (value == null) {
      return 'null';
    }
    if (depth >= maxStructuredDepth) {
      return _scalarSummary(value);
    }
    if (value is String) {
      return _scalarSummary(value);
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    if (value is List) {
      final items = <String>[];
      for (final item in value.take(maxStructuredItems)) {
        items.add(_compactStructuredValue(item, depth + 1));
      }
      final omitted = value.length - items.length;
      if (omitted > 0) {
        items.add('$_omission $omitted more');
      }
      return '[${items.join(', ')}]';
    }
    if (value is Map) {
      final entries = <String>[];
      for (final entry in value.entries.take(maxStructuredEntries)) {
        final key = entry.key.toString();
        if (key.trim().isEmpty) {
          continue;
        }
        entries.add('$key: ${_compactStructuredValue(entry.value, depth + 1)}');
      }
      final omitted = value.length - entries.length;
      if (omitted > 0) {
        entries.add('$_omission $omitted more');
      }
      return '{${entries.join(', ')}}';
    }
    return _scalarSummary(value);
  }

  /// Returns a bounded textual representation of a scalar value.
  String _scalarSummary(Object value) {
    return _truncateEnd(
      _cleanPromptText(value.toString()),
      maxScalarCharacters,
    );
  }

  /// Builds compact local-model tool instructions from OpenAI tool schemas.
  String _toolPromptSection(Object? tools) {
    if (tools is! List || tools.isEmpty) {
      return '';
    }
    final lines = <String>[
      'AVAILABLE TOOLS:',
      'Use exact tool names only. To call a tool, reply with only '
          '$_toolCallInstructionStart'
          'call:tool_name{json_arguments}'
          '$_toolCallInstructionEnd.',
    ];
    for (final tool in tools.whereType<Map<String, dynamic>>()) {
      final function = tool['function'];
      if (function is! Map<String, dynamic>) {
        continue;
      }
      final name = function['name']?.toString().trim() ?? '';
      if (name.isEmpty) {
        continue;
      }
      final description = function['description']?.toString().trim() ?? '';
      final params = _parameterNames(function['parameters']);
      final signature = params.isEmpty
          ? '$name({})'
          : '$name({${params.join(', ')}})';
      lines.add(
        description.isEmpty ? '- $signature' : '- $signature: $description',
      );
    }
    return lines.length == 2 ? '' : lines.join('\n');
  }

  /// Extracts parameter names from an OpenAI-compatible tool schema.
  List<String> _parameterNames(Object? parameters) {
    if (parameters is! Map<String, dynamic>) {
      return const <String>[];
    }
    final properties = parameters['properties'];
    if (properties is! Map) {
      return const <String>[];
    }
    return properties.keys.map((key) => key.toString()).toList()..sort();
  }
}

/// _OpenAiPromptMessage exposes normalized request message fields.
class _OpenAiPromptMessage {
  /// Creates a prompt message view over one decoded request message.
  const _OpenAiPromptMessage(this.source);

  /// Original decoded OpenAI-compatible message map.
  final Map<String, dynamic> source;

  /// Lower-case OpenAI message role.
  String get role => source['role']?.toString().trim().toLowerCase() ?? '';

  /// OpenAI message content value.
  Object? get content => source['content'];

  /// OpenAI assistant tool call payloads when present.
  Object? get toolCalls => source['tool_calls'];
}

/// Reports whether a role carries durable instructions instead of dialogue.
bool _isInstructionRole(String role) {
  return role == _openAISystemRole || role == _openAIDeveloperRole;
}

/// Selects prefix lines that fit inside the provided character budget.
List<String> _fitPrefix(List<String> lines, int budget) {
  final selected = <String>[];
  var used = 0;
  for (final line in lines) {
    final separator = selected.isEmpty ? 0 : 1;
    final remaining = budget - used - separator;
    if (remaining <= 0) {
      break;
    }
    if (line.length <= remaining) {
      selected.add(line);
      used += separator + line.length;
    } else {
      selected.add(_truncateEnd(line, remaining));
      break;
    }
  }
  return selected;
}

/// Selects the newest dialogue lines that fit inside the prompt budget.
List<String> _fitRecent(List<String> lines, int budget) {
  if (budget <= 0) {
    return const <String>[];
  }
  final selected = <String>[];
  var used = 0;
  for (final line in lines.reversed) {
    final separator = selected.isEmpty ? 0 : 1;
    final remaining = budget - used - separator;
    if (remaining <= 0) {
      break;
    }
    if (line.length <= remaining) {
      selected.add(line);
      used += separator + line.length;
      continue;
    }
    if (selected.isEmpty) {
      selected.add(_truncateEnd(line, remaining));
      break;
    }
  }
  return selected.reversed.toList();
}

/// Returns the character count for lines joined with newline separators.
int _joinedLength(List<String> lines) {
  if (lines.isEmpty) {
    return 0;
  }
  return lines.fold<int>(0, (total, line) => total + line.length) +
      lines.length -
      1;
}

/// Normalizes newline variants and trims prompt text.
String _cleanPromptText(String value) {
  return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
}

/// Truncates text at the end while preserving an omission marker when possible.
String _truncateEnd(String value, int maxCharacters) {
  if (maxCharacters <= 0) {
    return '';
  }
  if (value.length <= maxCharacters) {
    return value;
  }
  if (maxCharacters <= _omission.length) {
    return value.substring(0, maxCharacters);
  }
  return '${value.substring(0, maxCharacters - _omission.length)}$_omission';
}
