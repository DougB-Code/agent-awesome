/// Defines editable configuration file collection data.
library;

import 'model_config.dart';

/// ConfigFileKind identifies a managed configuration file collection.
enum ConfigFileKind {
  /// Model runtime configuration files.
  model,

  /// Agent behavior and prompt configuration files.
  agent,

  /// Tool and MCP configuration files.
  tool,
}

/// ConfigFileEntry describes one editable configuration file.
class ConfigFileEntry {
  /// Creates a configuration file entry.
  const ConfigFileEntry({
    required this.path,
    required this.kind,
    required this.assigned,
    this.displayName = '',
    this.modelChoices = const <ModelConfigChoice>[],
  });

  /// Absolute or configured file path.
  final String path;

  /// Configuration collection kind.
  final ConfigFileKind kind;

  /// Whether the active profile currently references this file.
  final bool assigned;

  /// Human-readable name derived from the config content when available.
  final String displayName;

  /// Selectable model choices parsed from model config files.
  final List<ModelConfigChoice> modelChoices;

  /// Stable item identifier.
  String get id {
    return path;
  }

  /// Human-readable item label.
  String get label {
    final trimmed = displayName.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return fileLabel;
  }

  /// Human-readable filename without extension.
  String get fileLabel {
    final normalized = path.replaceAll('\\', '/');
    final filename = normalized.split('/').last;
    final dot = filename.lastIndexOf('.');
    if (dot <= 0) {
      return filename;
    }
    return filename.substring(0, dot);
  }
}
