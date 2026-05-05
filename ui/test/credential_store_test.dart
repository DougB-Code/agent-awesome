/// Tests display-safe credential lookup behavior.
library;

import 'dart:io';

import 'package:agentawesome_ui/app/credential_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs credential store tests.
void main() {
  test(
    'masks keyring credentials while retaining explicit reveal value',
    () async {
      final store = CredentialStore(
        operatingSystem: 'linux',
        processRunner: (executable, arguments) async {
          expect(executable, 'secret-tool');
          expect(arguments, <String>[
            'lookup',
            'service',
            'agent-awesome',
            'username',
            'OPENAI_API_KEY',
          ]);
          return ProcessResult(1, 0, 'sk-test-secret-1234', '');
        },
      );

      final lookup = await store.lookup('OPENAI_API_KEY');

      expect(lookup.found, isTrue);
      expect(lookup.source, 'keyring');
      expect(lookup.displayValue, '••••••••1234');
      expect(lookup.displayValue, isNot(contains('sk-test-secret')));
      expect(lookup.secretValue, 'sk-test-secret-1234');
    },
  );

  test('falls back to environment credentials', () async {
    final store = CredentialStore(
      operatingSystem: 'linux',
      environment: const <String, String>{'OPENAI_API_KEY': 'env-secret-9999'},
      processRunner: (_, _) async => ProcessResult(1, 1, '', 'not found'),
    );

    final lookup = await store.lookup('OPENAI_API_KEY');

    expect(lookup.found, isTrue);
    expect(lookup.source, 'env');
    expect(lookup.displayValue, '••••••••9999');
    expect(lookup.secretValue, 'env-secret-9999');
  });

  test('does not echo missing credential references', () async {
    const literalSecret = 'xai-secret-value-that-must-not-render';
    final store = CredentialStore(
      operatingSystem: 'linux',
      environment: const <String, String>{},
      processRunner: (_, _) async => ProcessResult(1, 1, '', 'not found'),
    );

    final lookup = await store.lookup(literalSecret);

    expect(lookup.found, isFalse);
    expect(lookup.message, 'No keyring or environment value found');
    expect(lookup.message, isNot(contains(literalSecret)));
  });

  test('does not echo keyring process errors', () async {
    const literalSecret = 'xai-secret-value-that-must-not-render';
    final store = CredentialStore(
      operatingSystem: 'linux',
      secretProcessRunner: (_, _, _) async =>
          ProcessResult(1, 1, '', 'failed for $literalSecret'),
    );

    final result = await store.delete(literalSecret);

    expect(result.success, isFalse);
    expect(result.message, 'Could not delete API key (exit code 1)');
    expect(result.message, isNot(contains(literalSecret)));
  });

  test('stores linux keyring credentials from stdin', () async {
    final calls =
        <({String executable, List<String> arguments, String? stdin})>[];
    final store = CredentialStore(
      operatingSystem: 'linux',
      secretProcessRunner: (executable, arguments, stdin) async {
        calls.add((executable: executable, arguments: arguments, stdin: stdin));
        return ProcessResult(1, 0, '', '');
      },
    );

    final result = await store.store(
      reference: 'OPENAI_API_KEY',
      secret: 'sk-live-secret',
    );

    expect(result.success, isTrue);
    expect(calls.single.executable, 'secret-tool');
    expect(calls.single.arguments, <String>[
      'store',
      '--label',
      'Agent Awesome OPENAI_API_KEY',
      'service',
      'agent-awesome',
      'username',
      'OPENAI_API_KEY',
    ]);
    expect(calls.single.stdin, 'sk-live-secret');
  });

  test('deletes linux keyring credentials', () async {
    final calls =
        <({String executable, List<String> arguments, String? stdin})>[];
    final store = CredentialStore(
      operatingSystem: 'linux',
      secretProcessRunner: (executable, arguments, stdin) async {
        calls.add((executable: executable, arguments: arguments, stdin: stdin));
        return ProcessResult(1, 0, '', '');
      },
    );

    final result = await store.delete('OPENAI_API_KEY');

    expect(result.success, isTrue);
    expect(calls.single.executable, 'secret-tool');
    expect(calls.single.arguments, <String>[
      'clear',
      'service',
      'agent-awesome',
      'username',
      'OPENAI_API_KEY',
    ]);
    expect(calls.single.stdin, isNull);
  });
}
