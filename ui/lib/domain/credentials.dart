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

/// WebsiteLoginCredentialReferences stores stable refs for one website login.
class WebsiteLoginCredentialReferences {
  /// Creates credential refs for a browser-login profile.
  const WebsiteLoginCredentialReferences({
    required this.profileId,
    required this.username,
    required this.password,
    required this.oneTimeCodeSeed,
  });

  /// Stable profile id used by plugin and tool metadata.
  final String profileId;

  /// Keyring/env ref for the account username.
  final String username;

  /// Keyring/env ref for the account password.
  final String password;

  /// Optional keyring/env ref for a one-time-code seed.
  final String oneTimeCodeSeed;
}

/// WebsiteLoginCredentialLookup stores resolved refs for one website login.
class WebsiteLoginCredentialLookup {
  /// Creates a display-safe lookup summary for one browser-login profile.
  const WebsiteLoginCredentialLookup({
    required this.profileId,
    required this.username,
    required this.password,
    required this.oneTimeCodeSeed,
  });

  /// Stable profile id used by plugin and tool metadata.
  final String profileId;

  /// Username lookup result.
  final CredentialLookup username;

  /// Password lookup result.
  final CredentialLookup password;

  /// Optional one-time-code seed lookup result.
  final CredentialLookup oneTimeCodeSeed;

  /// Whether required username and password credentials are available.
  bool get ready {
    return username.found && password.found;
  }
}

/// AppleCalendarCredentialReferences stores refs for an Apple CalDAV plugin.
class AppleCalendarCredentialReferences {
  /// Creates credential refs for an Apple Calendar integration profile.
  const AppleCalendarCredentialReferences({
    required this.profileId,
    required this.appleId,
    required this.appPassword,
  });

  /// Stable profile id used by plugin and tool metadata.
  final String profileId;

  /// Keyring/env ref for the Apple ID username.
  final String appleId;

  /// Keyring/env ref for the app-specific password.
  final String appPassword;
}

/// Builds stable website-login credential references for one profile id.
WebsiteLoginCredentialReferences websiteLoginCredentialReferences(
  String profileId,
) {
  final token = credentialReferenceToken(profileId);
  return WebsiteLoginCredentialReferences(
    profileId: token,
    username: 'AA_WEB_LOGIN_${token}_USERNAME',
    password: 'AA_WEB_LOGIN_${token}_PASSWORD',
    oneTimeCodeSeed: 'AA_WEB_LOGIN_${token}_OTP_SEED',
  );
}

/// Builds stable Apple Calendar credential references for one profile id.
AppleCalendarCredentialReferences appleCalendarCredentialReferences(
  String profileId,
) {
  final token = credentialReferenceToken(profileId);
  return AppleCalendarCredentialReferences(
    profileId: token,
    appleId: 'AA_APPLE_CALENDAR_${token}_APPLE_ID',
    appPassword: 'AA_APPLE_CALENDAR_${token}_APP_PASSWORD',
  );
}

/// Converts user-facing ids into credential-reference-safe tokens.
String credentialReferenceToken(String value) {
  final upper = value.trim().toUpperCase();
  final buffer = StringBuffer();
  var lastWasUnderscore = false;
  for (final codeUnit in upper.codeUnits) {
    final isAlphaNumeric =
        (codeUnit >= 65 && codeUnit <= 90) ||
        (codeUnit >= 48 && codeUnit <= 57);
    if (isAlphaNumeric) {
      buffer.writeCharCode(codeUnit);
      lastWasUnderscore = false;
      continue;
    }
    if (!lastWasUnderscore) {
      buffer.write('_');
      lastWasUnderscore = true;
    }
  }
  final token = buffer.toString().replaceAll(RegExp(r'^_+|_+$'), '');
  return token.isEmpty ? 'DEFAULT' : token;
}
