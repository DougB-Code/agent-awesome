/// Persists app-specific Agent Awesome settings that are not runtime profile concerns.
library;

import 'dart:convert';
import 'dart:io';

import '../domain/json_value.dart';
import 'runtime_profile.dart';

/// AgentAwesomeAppSettings stores UI-owned defaults and app model choices.
class AgentAwesomeAppSettings {
  /// Creates app settings for chat defaults and app-owned model work.
  const AgentAwesomeAppSettings({
    this.defaultChatProfilePath = '',
    this.summaryModelConfigPath = '',
    this.summaryModelRef = '',
    this.chatTitleSummariesEnabled = true,
    this.gettingStartedCompleted = false,
  });

  /// Runtime profile used by fast-path new chat creation.
  final String defaultChatProfilePath;

  /// Model config used by app-owned chat title summarization.
  final String summaryModelConfigPath;

  /// Provider:model reference used by app-owned chat title summarization.
  final String summaryModelRef;

  /// Whether the app should generate compact chat titles.
  final bool chatTitleSummariesEnabled;

  /// Whether the first-launch setup guide has been completed or hidden.
  final bool gettingStartedCompleted;

  /// Returns a copy with selected settings changed.
  AgentAwesomeAppSettings copyWith({
    String? defaultChatProfilePath,
    String? summaryModelConfigPath,
    String? summaryModelRef,
    bool? chatTitleSummariesEnabled,
    bool? gettingStartedCompleted,
  }) {
    return AgentAwesomeAppSettings(
      defaultChatProfilePath:
          defaultChatProfilePath ?? this.defaultChatProfilePath,
      summaryModelConfigPath:
          summaryModelConfigPath ?? this.summaryModelConfigPath,
      summaryModelRef: summaryModelRef ?? this.summaryModelRef,
      chatTitleSummariesEnabled:
          chatTitleSummariesEnabled ?? this.chatTitleSummariesEnabled,
      gettingStartedCompleted:
          gettingStartedCompleted ?? this.gettingStartedCompleted,
    );
  }

  /// Encodes settings to stable JSON.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'default_chat_profile': defaultChatProfilePath,
      'summary_model_config': summaryModelConfigPath,
      'summary_model_ref': summaryModelRef,
      'chat_title_summaries_enabled': chatTitleSummariesEnabled,
      'getting_started_completed': gettingStartedCompleted,
    };
  }

  /// Parses settings from decoded JSON.
  factory AgentAwesomeAppSettings.fromJson(Map<String, dynamic> json) {
    return AgentAwesomeAppSettings(
      defaultChatProfilePath: stringValue(json['default_chat_profile']),
      summaryModelConfigPath: stringValue(json['summary_model_config']),
      summaryModelRef: stringValue(json['summary_model_ref']),
      chatTitleSummariesEnabled: boolValue(
        json['chat_title_summaries_enabled'],
        fallback: true,
      ),
      gettingStartedCompleted: boolValue(
        json['getting_started_completed'],
        fallback: false,
      ),
    );
  }
}

/// AgentAwesomeAppSettingsStore reads and writes app-owned settings.
class AgentAwesomeAppSettingsStore {
  /// Creates a settings store in the standard app config directory.
  const AgentAwesomeAppSettingsStore();

  /// Loads settings, returning defaults when no file exists yet.
  Future<AgentAwesomeAppSettings> load() async {
    final file = File(appSettingsPath());
    if (!await file.exists()) {
      return const AgentAwesomeAppSettings();
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('App settings must be a JSON object');
    }
    return AgentAwesomeAppSettings.fromJson(decoded);
  }

  /// Saves settings to disk.
  Future<void> save(AgentAwesomeAppSettings settings) async {
    final file = File(appSettingsPath());
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(settings.toJson())}\n');
  }
}

/// Returns the app settings JSON path.
String appSettingsPath() {
  return '${agentAwesomeAppConfigDirectoryPath()}/app_settings.json';
}
