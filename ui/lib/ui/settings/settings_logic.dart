/// Provides non-widget helpers for settings panels.
library;

import '../../app/config_files.dart';
import '../../app/model_config.dart';

/// SettingsTextCodec parses user-entered multiline settings fields.
class SettingsTextCodec {
  const SettingsTextCodec._();

  /// Returns trimmed non-empty lines from a settings text area.
  static List<String> lines(String value) {
    return value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  /// Returns trimmed KEY=value pairs from a settings text area.
  static Map<String, String> keyValues(String value) {
    final pairs = <String, String>{};
    for (final line in value.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final equals = trimmed.indexOf('=');
      if (equals <= 0) {
        continue;
      }
      final key = trimmed.substring(0, equals).trim();
      final entryValue = trimmed.substring(equals + 1).trim();
      if (key.isNotEmpty && entryValue.isNotEmpty) {
        pairs[key] = entryValue;
      }
    }
    return pairs;
  }
}

/// SettingsNameFactory creates stable identifiers from visible labels.
class SettingsNameFactory {
  const SettingsNameFactory._();

  /// Returns a harness-safe tool or server identifier from display text.
  static String toolNameFromLabel(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_]+'),
      '_',
    );
    final trimmed = normalized
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (trimmed.isEmpty) {
      return '';
    }
    if (RegExp(r'^[a-z_]').hasMatch(trimmed)) {
      return trimmed;
    }
    return 'tool_$trimmed';
  }

  /// Returns a stable environment-style credential name for a provider id.
  static String credentialNameFromProvider(String providerId) {
    final normalized = providerId.trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]+'),
      '_',
    );
    final trimmed = normalized
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return trimmed.isEmpty ? 'PROVIDER_API_KEY' : '${trimmed}_API_KEY';
  }
}

/// SettingsConfigLabels formats labels for managed settings config data.
class SettingsConfigLabels {
  const SettingsConfigLabels._();

  /// Returns a compact file label for settings collection items.
  static String fileLabel(String path) {
    final filename = path.replaceAll('\\', '/').split('/').last;
    final dot = filename.lastIndexOf('.');
    if (dot <= 0) {
      return filename;
    }
    return filename.substring(0, dot);
  }

  /// Returns the display label for a managed config file kind.
  static String kindLabel(ConfigFileKind kind) {
    return switch (kind) {
      ConfigFileKind.model => 'Model',
      ConfigFileKind.agent => 'Agent',
      ConfigFileKind.tool => 'Tool',
    };
  }

  /// Returns the visible label for an app summary model option.
  static String summaryModelLabel({
    required ConfigFileEntry entry,
    required ModelConfigChoice choice,
    required bool includeConfig,
  }) {
    final providerModel = choice.label;
    return includeConfig ? '${entry.label} / $providerModel' : providerModel;
  }
}

/// SettingsConfigIds creates collision-free ids inside settings documents.
class SettingsConfigIds {
  const SettingsConfigIds._();

  /// Returns a provider id that does not collide with existing providers.
  static String uniqueProviderId(ModelConfigDocument document, String prefix) {
    final existing = document.providers.map((provider) => provider.id).toSet();
    var candidate = prefix;
    var index = 2;
    while (existing.contains(candidate)) {
      candidate = '$prefix-$index';
      index++;
    }
    return candidate;
  }

  /// Returns a model id that does not collide inside one provider.
  static String uniqueModelId(ModelProviderConfig provider, String prefix) {
    final existing = provider.models.map((model) => model.id).toSet();
    var candidate = prefix;
    var index = 2;
    while (existing.contains(candidate)) {
      candidate = '$prefix-$index';
      index++;
    }
    return candidate;
  }
}

/// SettingsQuery matches settings content against filter text.
class SettingsQuery {
  const SettingsQuery._();

  /// Returns whether settings values match a filter query.
  static bool matches(String query, List<String> values) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return values.any((value) => value.toLowerCase().contains(normalized));
  }
}
