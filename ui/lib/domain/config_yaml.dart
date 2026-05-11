/// Provides shared YAML normalization and encoding for config documents.
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Converts YAML package collection values to plain Dart values.
dynamic plainYamlValue(dynamic value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): plainYamlValue(entry.value),
    };
  }
  if (value is YamlList) {
    return value.map(plainYamlValue).toList();
  }
  return value;
}

/// Encodes a map as readable YAML.
String encodeYamlMap(Map<String, dynamic> map) {
  final buffer = StringBuffer();
  _writeYamlMap(buffer, map, 0);
  return buffer.toString();
}

/// Writes a YAML map with stable indentation.
void _writeYamlMap(StringBuffer buffer, Map<String, dynamic> map, int indent) {
  for (final entry in map.entries) {
    _writeYamlMapEntry(buffer, entry.key, entry.value, indent);
  }
}

/// Writes one YAML map entry, optionally prefixed by a list marker.
void _writeYamlMapEntry(
  StringBuffer buffer,
  String key,
  dynamic value,
  int indent, {
  String prefix = '',
}) {
  final padding = ' ' * indent;
  final entryPrefix = '$padding$prefix$key:';
  final childIndent = indent + prefix.length + 2;
  if (value is Map<String, dynamic>) {
    if (value.isEmpty) {
      buffer.writeln('$entryPrefix {}');
      return;
    }
    buffer.writeln(entryPrefix);
    _writeYamlMap(buffer, value, childIndent);
  } else if (value is List) {
    if (value.isEmpty) {
      buffer.writeln('$entryPrefix []');
      return;
    }
    buffer.writeln(entryPrefix);
    _writeYamlList(buffer, value, childIndent);
  } else {
    buffer.writeln('$entryPrefix ${_yamlScalar(value)}');
  }
}

/// Writes a YAML list with stable indentation.
void _writeYamlList(StringBuffer buffer, List<dynamic> list, int indent) {
  for (final value in list) {
    final prefix = ' ' * indent;
    if (value is Map<String, dynamic>) {
      if (value.isEmpty) {
        buffer.writeln('$prefix- {}');
        continue;
      }
      final entries = value.entries.toList(growable: false);
      final first = entries.first;
      _writeYamlMapEntry(buffer, first.key, first.value, indent, prefix: '- ');
      for (final entry in entries.skip(1)) {
        _writeYamlMapEntry(buffer, entry.key, entry.value, indent + 2);
      }
    } else {
      buffer.writeln('$prefix- ${_yamlScalar(value)}');
    }
  }
}

/// Encodes one YAML scalar conservatively.
String _yamlScalar(dynamic value) {
  if (value is num || value is bool) {
    return value.toString();
  }
  if (value == null) {
    return 'null';
  }
  final text = value.toString();
  if (text.isEmpty ||
      text.contains(': ') ||
      text.startsWith('{') ||
      text.startsWith('[') ||
      text.contains('\n')) {
    return jsonEncode(text);
  }
  return text;
}
