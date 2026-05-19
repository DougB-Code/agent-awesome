/// Verifies the rendered desktop UI against the release gateway container.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentawesome_ui/ui/agent_awesome_app.dart';
import 'package:agentawesome_ui/app/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

const _prompt = 'release e2e prompt from rendered Flutter UI';
const _followUpPrompt = 'second release e2e prompt from chat composer';
const _taskPrompt = 'create release e2e task from rendered Flutter UI';
const _responsePhrase = 'mock llm e2e response';
const _taskResponsePhrase = 'mock llm e2e task created';
const _taskTitle = 'Release E2E Verified Task';
const _toolCallId = 'call-create-release-e2e-task';
const _wireModel = 'e2e-wire-model';

/// Runs the release-gateway E2E UI scenario.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('drives chat and task creation through the rendered UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      AgentAwesomeApp(config: AppConfig.fromEnvironment()),
    );

    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey<String>('global-command-input'))
          .evaluate()
          .isNotEmpty,
      description: 'global command input to render',
    );
    expect(find.text('Today'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('global-command-input')),
      findsOneWidget,
    );

    await _openNewChat(tester);
    await _sendChatMessageAndWaitForProvider(tester, _prompt);
    await _waitForText(tester, '$_responsePhrase: $_prompt');
    expect(find.textContaining(_responsePhrase), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('chat-thread-composer')),
      findsOneWidget,
    );

    await _sendChatMessageAndWaitForProvider(tester, _followUpPrompt);
    await _waitForText(tester, '$_responsePhrase: $_followUpPrompt');

    await _sendChatMessageAndWaitForProvider(tester, _taskPrompt);
    await _waitForText(
      tester,
      _taskResponsePhrase,
      timeout: const Duration(seconds: 120),
    );

    await tester.tap(find.text('Backlog').first);
    await tester.pump();
    await _waitForText(
      tester,
      _taskTitle,
      timeout: const Duration(seconds: 90),
      description: 'created task to render in Backlog',
    );
    expect(find.text('Active tasks'), findsWidgets);
    expect(find.text(_taskTitle), findsWidgets);

    final requests = await _loadMockRequests();
    final chatRequests = _chatRequests(requests);
    expect(chatRequests.length, greaterThanOrEqualTo(4));
    for (final request in chatRequests) {
      _expectOpenAiRequest(request);
    }
    _expectChatTranscriptProgression(chatRequests);
    _expectTaskToolRoundTrip(chatRequests.last);
    expect(_requestsContain(chatRequests, _prompt), isTrue);
    expect(_requestsContain(chatRequests, _followUpPrompt), isTrue);
    expect(_requestsContain(chatRequests, _taskPrompt), isTrue);
    expect(_requestsContain(chatRequests, '"name":"create_task"'), isTrue);
    expect(_requestsContain(chatRequests, _toolCallId), isTrue);
    expect(_requestsContain(chatRequests, '"role":"tool"'), isTrue);
  });
}

/// Opens an empty chat through the visible command-bar control.
Future<void> _openNewChat(WidgetTester tester) async {
  await tester.tap(find.byTooltip('New chat').first);
  await tester.pump();
  await _pumpUntil(
    tester,
    () {
      final composerReady = find
          .byKey(const ValueKey<String>('chat-thread-composer'))
          .evaluate()
          .isNotEmpty;
      final sessionReady =
          find.text('Select chat').evaluate().isEmpty &&
          find.textContaining('Chat ').evaluate().isNotEmpty;
      return composerReady && sessionReady;
    },
    timeout: const Duration(seconds: 45),
    description: 'new chat session and composer to render',
  );
}

/// Sends a chat prompt and waits until the mock provider records it.
Future<void> _sendChatMessageAndWaitForProvider(
  WidgetTester tester,
  String text,
) async {
  final before = await _loadMockRequests();
  await _submitChatMessage(tester, text);
  if (await _waitForMockRequestContaining(text, previousCount: before.length)) {
    return;
  }

  final after = await _loadMockRequests();
  fail(
    'Timed out waiting for mock provider to receive "$text"; '
    'requests before=${before.length} after=${after.length}',
  );
}

/// Sends a prompt through the active chat thread composer.
Future<void> _submitChatMessage(WidgetTester tester, String text) async {
  final composer = find.byKey(const ValueKey<String>('chat-thread-composer'));
  final sendButton = find.byKey(
    const ValueKey<String>('chat-thread-send-button'),
  );
  final editableText = find.descendant(
    of: composer,
    matching: find.byType(EditableText),
  );
  await _pumpUntil(
    tester,
    () =>
        composer.evaluate().length == 1 &&
        editableText.evaluate().length == 1 &&
        sendButton.evaluate().length == 1,
    description: 'one chat composer, editable field, and send button',
  );
  await tester.ensureVisible(composer);
  await tester.tap(editableText);
  await tester.showKeyboard(editableText);
  tester.testTextInput.enterText(text);
  await tester.pump();
  final field = tester.widget<TextField>(composer);
  if (field.controller?.text != text) {
    final controller = field.controller;
    if (controller == null) {
      fail('Chat composer does not expose a controller for E2E input');
    }
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    await tester.pump();
  }
  if (field.controller?.text != text) {
    fail('Chat composer did not receive text');
  }
  final button = tester.widget<IconButton>(sendButton);
  if (button.onPressed == null) {
    fail('Chat send button is disabled after entering text');
  }
  await tester.tapAt(tester.getCenter(sendButton));
  await tester.pump();
}

/// Waits until the mock provider records a request containing [text].
Future<bool> _waitForMockRequestContaining(
  String text, {
  required int previousCount,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final requests = await _loadMockRequests();
    if (requests.length > previousCount && _requestsContain(requests, text)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

/// Waits for visible text containing [text].
Future<void> _waitForText(
  WidgetTester tester,
  String text, {
  Duration timeout = const Duration(seconds: 90),
  String? description,
}) async {
  await _pumpUntil(
    tester,
    () => find.textContaining(text).evaluate().isNotEmpty,
    timeout: timeout,
    description: description ?? '"$text" to appear',
  );
}

/// Pumps frames until a condition is true or the timeout expires.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 60),
  String description = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $description');
}

/// Loads recorded provider calls from the mock LLM admin endpoint.
Future<List<Map<String, dynamic>>> _loadMockRequests() async {
  final adminURL =
      Platform.environment['AGENTAWESOME_E2E_MOCK_ADMIN_URL']?.trim() ?? '';
  if (adminURL.isEmpty) {
    fail('AGENTAWESOME_E2E_MOCK_ADMIN_URL is required');
  }
  final response = await http.get(Uri.parse('$adminURL/requests'));
  if (response.statusCode != 200) {
    fail(
      'Mock LLM request log returned HTTP ${response.statusCode}: ${response.body}',
    );
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic> || decoded['requests'] is! List) {
    fail('Mock LLM request log has unexpected shape: ${response.body}');
  }
  final requests = decoded['requests'] as List<dynamic>;
  return requests.cast<Map<String, dynamic>>();
}

/// Returns chat-completion requests from the mock provider log.
List<Map<String, dynamic>> _chatRequests(List<Map<String, dynamic>> requests) {
  return requests
      .where((request) => request['path'] == '/v1/chat/completions')
      .toList(growable: false);
}

/// Verifies one provider call was sent with the expected release wiring.
void _expectOpenAiRequest(Map<String, dynamic> request) {
  expect(request['method'], 'POST');
  expect(request['authorization'], 'Bearer e2e-test-key');
  final body = request['body'];
  expect(body, isA<Map<String, dynamic>>());
  final typedBody = body as Map<String, dynamic>;
  expect(typedBody['model'], _wireModel);
  expect(typedBody['stream'], isFalse);
  expect(typedBody['messages'], isA<List<dynamic>>());
  _expectToolDeclaration(typedBody, 'create_task');
  _expectToolDeclaration(typedBody, 'load_memory');
  _expectToolDeclaration(typedBody, 'remember');
}

/// Verifies each UI prompt was sent with the expected accumulated context.
void _expectChatTranscriptProgression(List<Map<String, dynamic>> requests) {
  final first = _messagesForRequest(requests[0]);
  final second = _messagesForRequest(requests[1]);
  final third = _messagesForRequest(requests[2]);
  final fourth = _messagesForRequest(requests[3]);

  _expectLatestUser(first, _prompt);
  _expectLatestUser(second, _followUpPrompt);
  _expectLatestUser(third, _taskPrompt);
  expect(_messageContents(second), contains('$_responsePhrase: $_prompt'));
  expect(
    _messageContents(third),
    contains('$_responsePhrase: $_followUpPrompt'),
  );
  expect(_messageContents(fourth), contains(contains(_taskTitle)));
  expect(_roleCount(fourth, 'tool'), 1);
}

/// Verifies the mock task tool call was executed and returned to the model.
void _expectTaskToolRoundTrip(Map<String, dynamic> request) {
  final messages = _messagesForRequest(request);
  final toolCall = _toolCallById(messages, _toolCallId);
  final function = toolCall['function'];
  expect(function, isA<Map<String, dynamic>>());
  final typedFunction = function as Map<String, dynamic>;
  expect(typedFunction['name'], 'create_task');
  final arguments = jsonDecode(typedFunction['arguments'] as String);
  expect(arguments, isA<Map<String, dynamic>>());
  final typedArguments = arguments as Map<String, dynamic>;
  expect(typedArguments['title'], _taskTitle);
  expect(
    typedArguments['description'],
    'Created by the release E2E mock provider.',
  );
  expect(typedArguments['idempotency_key'], 'release-e2e-verified-task');

  final toolMessage = _toolMessageByCallId(messages, _toolCallId);
  final output = jsonDecode(toolMessage['content'] as String);
  expect(output, isA<Map<String, dynamic>>());
  final typedOutput = output as Map<String, dynamic>;
  expect(typedOutput['output'], isA<Map<String, dynamic>>());
  final task = typedOutput['output'] as Map<String, dynamic>;
  expect(task['title'], _taskTitle);
  expect(task['status'], 'open');
  expect(task['idempotency_key'], 'release-e2e-verified-task');
}

/// Verifies the gateway exposed one named tool to the model request.
void _expectToolDeclaration(Map<String, dynamic> body, String name) {
  final tools = body['tools'];
  expect(tools, isA<List<dynamic>>());
  final encodedTools = jsonEncode(tools);
  expect(encodedTools, contains('"name":"$name"'));
}

/// Returns typed OpenAI messages from one recorded provider request.
List<Map<String, dynamic>> _messagesForRequest(Map<String, dynamic> request) {
  final body = request['body'];
  expect(body, isA<Map<String, dynamic>>());
  final messages = (body as Map<String, dynamic>)['messages'];
  expect(messages, isA<List<dynamic>>());
  return (messages as List<dynamic>).cast<Map<String, dynamic>>();
}

/// Verifies the latest user turn matches the expected prompt text.
void _expectLatestUser(List<Map<String, dynamic>> messages, String text) {
  final latestUser = messages.lastWhere(
    (message) => message['role'] == 'user',
    orElse: () => <String, dynamic>{},
  );
  expect(latestUser['content'], text);
}

/// Returns all message content values as strings for transcript assertions.
List<String> _messageContents(List<Map<String, dynamic>> messages) {
  return messages
      .map((message) => message['content'])
      .whereType<String>()
      .toList(growable: false);
}

/// Counts messages with one OpenAI role.
int _roleCount(List<Map<String, dynamic>> messages, String role) {
  return messages.where((message) => message['role'] == role).length;
}

/// Returns the assistant tool call with a matching id.
Map<String, dynamic> _toolCallById(
  List<Map<String, dynamic>> messages,
  String id,
) {
  for (final message in messages) {
    final toolCalls = message['tool_calls'];
    if (toolCalls is! List<dynamic>) {
      continue;
    }
    for (final toolCall in toolCalls.cast<Map<String, dynamic>>()) {
      if (toolCall['id'] == id) {
        return toolCall;
      }
    }
  }
  fail('Expected tool call $id in transcript');
}

/// Returns the tool result message for one assistant tool-call id.
Map<String, dynamic> _toolMessageByCallId(
  List<Map<String, dynamic>> messages,
  String id,
) {
  for (final message in messages) {
    if (message['role'] == 'tool' && message['tool_call_id'] == id) {
      return message;
    }
  }
  fail('Expected tool response for $id in transcript');
}

/// Reports whether any recorded request contains the encoded marker.
bool _requestsContain(List<Map<String, dynamic>> requests, String marker) {
  return requests.any((request) => jsonEncode(request).contains(marker));
}
