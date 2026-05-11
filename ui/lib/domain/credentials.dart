/// Defines display-safe credential result data shared across UI layers.
library;

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
