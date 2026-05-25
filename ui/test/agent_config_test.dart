/// Tests harness agent configuration parsing.
library;

import 'package:agentawesome_ui/domain/agent_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs agent config parser tests.
void main() {
  test('parses agent validations from YAML', () {
    final document = AgentConfigDocument.parse('''
name: test_agent
description: Useful test agent.
instruction: |
  Ask for missing context.
validations:
  - id: asks_for_context
    label: Asks for context
    mode: mocked
    prompt: Help me with the thing.
    mocks:
      agent.response:
        text: I need more context.
    assertions:
      - type: response-contains
        contains: context
''');

    expect(document.name, 'test_agent');
    expect(document.description, 'Useful test agent.');
    expect(document.instruction, contains('Ask for missing context.'));
    expect(document.validations.single.id, 'asks_for_context');
    expect(document.validations.single.label, 'Asks for context');
    expect(document.validations.single.mocks['agent.response'], isA<Map>());
    expect(
      document.validations.single.assertions.single.type,
      'response-contains',
    );
    expect(document.validations.single.assertions.single.contains, 'context');
  });
}
