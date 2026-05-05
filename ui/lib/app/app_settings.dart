/// Persists app-specific Aurora settings that are not runtime profile concerns.
library;

import 'dart:convert';
import 'dart:io';

import 'runtime_profile.dart';

/// AuroraAppSettings stores UI-owned defaults and app model choices.
class AuroraAppSettings {
  /// Creates app settings for chat defaults and app-owned model work.
  const AuroraAppSettings({
    this.defaultChatProfilePath = '',
    this.summaryModelConfigPath = '',
    this.summaryModelRef = '',
    this.chatTitleSummariesEnabled = true,
  });

  /// Runtime profile used by fast-path new chat creation.
  final String defaultChatProfilePath;

  /// Model config used by app-owned chat title summarization.
  final String summaryModelConfigPath;

  /// Provider:model reference used by app-owned chat title summarization.
  final String summaryModelRef;

  /// Whether the app should generate compact chat titles.
  final bool chatTitleSummariesEnabled;

  /// Returns a copy with selected settings changed.
  AuroraAppSettings copyWith({
    String? defaultChatProfilePath,
    String? summaryModelConfigPath,
    String? summaryModelRef,
    bool? chatTitleSummariesEnabled,
  }) {
    return AuroraAppSettings(
      defaultChatProfilePath:
          defaultChatProfilePath ?? this.defaultChatProfilePath,
      summaryModelConfigPath:
          summaryModelConfigPath ?? this.summaryModelConfigPath,
      summaryModelRef: summaryModelRef ?? this.summaryModelRef,
      chatTitleSummariesEnabled:
          chatTitleSummariesEnabled ?? this.chatTitleSummariesEnabled,
    );
  }

  /// Encodes settings to stable JSON.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'default_chat_profile': defaultChatProfilePath,
      'summary_model_config': summaryModelConfigPath,
      'summary_model_ref': summaryModelRef,
      'chat_title_summaries_enabled': chatTitleSummariesEnabled,
    };
  }

  /// Parses settings from decoded JSON.
  factory AuroraAppSettings.fromJson(Map<String, dynamic> json) {
    return AuroraAppSettings(
      defaultChatProfilePath: _stringValue(json['default_chat_profile']),
      summaryModelConfigPath: _stringValue(json['summary_model_config']),
      summaryModelRef: _stringValue(json['summary_model_ref']),
      chatTitleSummariesEnabled: _boolValue(
        json['chat_title_summaries_enabled'],
        fallback: true,
      ),
    );
  }
}

/// AuroraAppSettingsStore reads and writes app-owned settings.
class AuroraAppSettingsStore {
  /// Creates a settings store in the standard app config directory.
  const AuroraAppSettingsStore();

  /// Loads settings, returning defaults when no file exists yet.
  Future<AuroraAppSettings> load() async {
    final file = File(appSettingsPath());
    if (!await file.exists()) {
      return const AuroraAppSettings();
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('App settings must be a JSON object');
    }
    return AuroraAppSettings.fromJson(decoded);
  }

  /// Saves settings to disk.
  Future<void> save(AuroraAppSettings settings) async {
    final file = File(appSettingsPath());
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(settings.toJson())}\n');
  }
}

/// Returns the app settings JSON path.
String appSettingsPath() {
  return '${auroraAppConfigDirectoryPath()}/app_settings.json';
}

/// Converts a decoded setting value to a string.
String _stringValue(dynamic value) {
  return value == null ? '' : value.toString();
}

/// Converts a decoded setting value to a bool with a required fallback.
bool _boolValue(dynamic value, {required bool fallback}) {
  if (value is bool) {
    return value;
  }
  return fallback;
}
