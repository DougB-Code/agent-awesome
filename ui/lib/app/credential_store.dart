/// Resolves and masks provider credentials from the local credential sources.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Runs one external process for platform credential lookup.
typedef CredentialProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Runs one external process that may need secret stdin.
typedef CredentialSecretProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
      String? stdin,
    );

/// CredentialLookup describes the display-safe result of resolving a key.
class CredentialLookup {
  /// Creates a credential lookup result.
  const CredentialLookup({
    required this.reference,
    required this.found,
    required this.displayValue,
    required this.secretValue,
    required this.source,
    required this.message,
  });

  /// Configured credential name, such as OPENAI_API_KEY.
  final String reference;

  /// Whether a secret value was found.
  final bool found;

  /// Masked value safe to render in the UI.
  final String displayValue;

  /// Full resolved secret value for explicit user reveal actions.
  final String secretValue;

  /// Source label for the resolved secret.
  final String source;

  /// Short diagnostic message when a secret is missing.
  final String message;
}

/// CredentialMutationResult describes storing or deleting a credential.
class CredentialMutationResult {
  /// Creates a credential mutation result.
  const CredentialMutationResult({
    required this.reference,
    required this.success,
    required this.message,
  });

  /// Credential name that was mutated.
  final String reference;

  /// Whether the operation completed successfully.
  final bool success;

  /// User-safe mutation status.
  final String message;
}

/// CredentialStore resolves Agent Awesome credentials from keyring or env.
class CredentialStore {
  /// Creates a credential resolver with injectable process and env sources.
  const CredentialStore({
    Map<String, String>? environment,
    CredentialProcessRunner? processRunner,
    CredentialSecretProcessRunner? secretProcessRunner,
    String? operatingSystem,
  }) : _environment = environment,
       _processRunner = processRunner,
       _secretProcessRunner = secretProcessRunner,
       _operatingSystem = operatingSystem;

  static const String _serviceName = 'agent-awesome';
  static const Duration _lookupTimeout = Duration(seconds: 2);

  final Map<String, String>? _environment;
  final CredentialProcessRunner? _processRunner;
  final CredentialSecretProcessRunner? _secretProcessRunner;
  final String? _operatingSystem;

  /// Resolves a credential reference for masked display and explicit reveal.
  Future<CredentialLookup> lookup(String reference) async {
    final trimmed = reference.trim();
    if (trimmed.isEmpty) {
      return const CredentialLookup(
        reference: '',
        found: false,
        displayValue: 'No credential configured',
        secretValue: '',
        source: '',
        message: 'No credential configured',
      );
    }

    final keyringValue = await _lookupKeyring(trimmed);
    if (keyringValue != null && keyringValue.trim().isNotEmpty) {
      return CredentialLookup(
        reference: trimmed,
        found: true,
        displayValue: _maskSecret(keyringValue.trim()),
        secretValue: keyringValue.trim(),
        source: 'keyring',
        message: '',
      );
    }

    final envValue = (_environment ?? Platform.environment)[trimmed]?.trim();
    if (envValue != null && envValue.isNotEmpty) {
      return CredentialLookup(
        reference: trimmed,
        found: true,
        displayValue: _maskSecret(envValue),
        secretValue: envValue,
        source: 'env',
        message: '',
      );
    }

    return CredentialLookup(
      reference: trimmed,
      found: false,
      displayValue: 'Missing credential',
      secretValue: '',
      source: '',
      message: 'No keyring or environment value found',
    );
  }

  /// Stores a provider secret in the platform keyring.
  Future<CredentialMutationResult> store({
    required String reference,
    required String secret,
  }) async {
    final trimmedReference = reference.trim();
    final trimmedSecret = secret.trim();
    if (trimmedReference.isEmpty) {
      return const CredentialMutationResult(
        reference: '',
        success: false,
        message: 'Credential name is required',
      );
    }
    if (trimmedSecret.isEmpty) {
      return CredentialMutationResult(
        reference: trimmedReference,
        success: false,
        message: 'API key is required',
      );
    }
    final os = _operatingSystem ?? Platform.operatingSystem;
    final result = switch (os) {
      'linux' => await _runSecretCommand('secret-tool', <String>[
        'store',
        '--label',
        'Agent Awesome $trimmedReference',
        'service',
        _serviceName,
        'username',
        trimmedReference,
      ], trimmedSecret),
      'macos' => await _runSecretCommand('security', <String>[
        'add-generic-password',
        '-U',
        '-s',
        _serviceName,
        '-a',
        trimmedReference,
        '-w',
        trimmedSecret,
      ], null),
      _ => null,
    };
    if (result == null) {
      return CredentialMutationResult(
        reference: trimmedReference,
        success: false,
        message: 'OS keyring is not supported on $os',
      );
    }
    if (result.exitCode != 0) {
      return CredentialMutationResult(
        reference: trimmedReference,
        success: false,
        message: _mutationError(result, 'Could not save API key'),
      );
    }
    return CredentialMutationResult(
      reference: trimmedReference,
      success: true,
      message: 'Saved API key to OS keyring',
    );
  }

  /// Deletes a provider secret from the platform keyring.
  Future<CredentialMutationResult> delete(String reference) async {
    final trimmed = reference.trim();
    if (trimmed.isEmpty) {
      return const CredentialMutationResult(
        reference: '',
        success: true,
        message: 'No credential configured',
      );
    }
    final os = _operatingSystem ?? Platform.operatingSystem;
    final result = switch (os) {
      'linux' => await _runSecretCommand('secret-tool', <String>[
        'clear',
        'service',
        _serviceName,
        'username',
        trimmed,
      ], null),
      'macos' => await _runSecretCommand('security', <String>[
        'delete-generic-password',
        '-s',
        _serviceName,
        '-a',
        trimmed,
      ], null),
      _ => null,
    };
    if (result == null) {
      return CredentialMutationResult(
        reference: trimmed,
        success: false,
        message: 'OS keyring is not supported on $os',
      );
    }
    if (result.exitCode != 0) {
      return CredentialMutationResult(
        reference: trimmed,
        success: false,
        message: _mutationError(result, 'Could not delete API key'),
      );
    }
    return CredentialMutationResult(
      reference: trimmed,
      success: true,
      message: 'Deleted API key from OS keyring',
    );
  }

  /// Looks up a credential in the platform keyring when supported.
  Future<String?> _lookupKeyring(String reference) async {
    final os = _operatingSystem ?? Platform.operatingSystem;
    if (os == 'linux') {
      return _runCredentialCommand('secret-tool', <String>[
        'lookup',
        'service',
        _serviceName,
        'username',
        reference,
      ]);
    }
    if (os == 'macos') {
      return _runCredentialCommand('security', <String>[
        'find-generic-password',
        '-s',
        _serviceName,
        '-wa',
        reference,
      ]);
    }
    return null;
  }

  /// Runs a bounded keyring command and returns stdout on success.
  Future<String?> _runCredentialCommand(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await (_processRunner ?? Process.run)(
        executable,
        arguments,
      ).timeout(_lookupTimeout);
      if (result.exitCode != 0) {
        return null;
      }
      return result.stdout.toString().trim();
    } on Object {
      return null;
    }
  }

  /// Runs a bounded keyring mutation command.
  Future<ProcessResult?> _runSecretCommand(
    String executable,
    List<String> arguments,
    String? stdin,
  ) async {
    final runner = _secretProcessRunner;
    if (runner != null) {
      try {
        return await runner(
          executable,
          arguments,
          stdin,
        ).timeout(_lookupTimeout);
      } on Object {
        return null;
      }
    }
    try {
      if (stdin == null) {
        return await Process.run(executable, arguments).timeout(_lookupTimeout);
      }
      final process = await Process.start(executable, arguments);
      process.stdin.write(stdin);
      await process.stdin.close();
      final stdout = await process.stdout.transform(utf8.decoder).join();
      final stderr = await process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(_lookupTimeout);
      return ProcessResult(0, exitCode, stdout, stderr);
    } on Object {
      return null;
    }
  }
}

/// Returns a compact user-safe keyring mutation error.
String _mutationError(ProcessResult result, String fallback) {
  return '$fallback (exit code ${result.exitCode})';
}

/// Masks a secret while preserving a short suffix for recognition.
String _maskSecret(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.length <= 8) {
    return '••••••••';
  }
  return '••••••••${trimmed.substring(trimmed.length - 4)}';
}
