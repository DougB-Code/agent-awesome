/// Provides file-backed collections for editable Agent Awesome configuration files.
library;

import 'dart:convert';
import 'dart:io';

import '../domain/config_files.dart';
import '../domain/model_config.dart';
import 'runtime_profile.dart';

export '../domain/config_files.dart';

/// ConfigFileStore manages real configuration files in the app config folder.
class ConfigFileStore {
  /// Creates a configuration file store.
  const ConfigFileStore({this.configDirectoryPath = ''});

  /// Root config directory used for editable collections.
  final String configDirectoryPath;

  /// Reads one managed text configuration file.
  Future<String> read(String path) async {
    final file = await _validatedConfigFile(path, requireExists: true);
    return file.readAsString();
  }

  /// Writes one managed text configuration file.
  Future<void> write(String path, String content) async {
    final file = await _validatedConfigFile(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  /// Lists config files for a collection, including assigned external paths.
  Future<List<ConfigFileEntry>> list({
    required ConfigFileKind kind,
    String assignedPath = '',
  }) async {
    final directory = Directory(_directoryPath(kind));
    final entries = <ConfigFileEntry>[];
    if (!await _hasSymlinkPathComponent(directory.path) &&
        await directory.exists()) {
      final files = await _configFilesInDirectory(directory, kind);
      files.sort((left, right) => left.path.compareTo(right.path));
      for (final file in files) {
        entries.add(
          ConfigFileEntry(
            path: file.path,
            kind: kind,
            assigned: file.path == assignedPath,
            displayName: await _displayName(file.path, kind),
            modelChoices: await _modelChoices(file.path, kind),
          ),
        );
      }
    }
    if (assignedPath.trim().isNotEmpty &&
        !entries.any((entry) => entry.path == assignedPath)) {
      final readMetadata = await _canReadManagedMetadata(assignedPath);
      entries.insert(
        0,
        ConfigFileEntry(
          path: assignedPath,
          kind: kind,
          assigned: true,
          displayName: readMetadata
              ? await _displayName(assignedPath, kind)
              : '',
          modelChoices: readMetadata
              ? await _modelChoices(assignedPath, kind)
              : const <ModelConfigChoice>[],
        ),
      );
    }
    return entries;
  }

  /// Creates a new empty config file in the appropriate collection directory.
  Future<String> create(ConfigFileKind kind) async {
    final directory = Directory(_directoryPath(kind));
    await directory.create(recursive: true);
    final path = _isPackageConfigKind(kind)
        ? await _uniquePackageConfigPath(
            directory.path,
            _defaultPrefix(kind),
            kind,
          )
        : await _uniquePath(directory.path, '${_defaultPrefix(kind)}.yaml');
    final file = await _validatedConfigFile(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('');
    return path;
  }

  /// Duplicates a config file into the app config collection directory.
  Future<String> duplicate(String sourcePath, ConfigFileKind kind) async {
    final source = await _validatedConfigFile(sourcePath, requireExists: true);
    final directory = Directory(_directoryPath(kind));
    await directory.create(recursive: true);
    final path = _isCanonicalPackageConfigFile(source.path, kind)
        ? await _duplicatePackageConfigPath(source.path, directory.path, kind)
        : await _uniquePath(
            directory.path,
            _copyName(sourcePath.replaceAll('\\', '/').split('/').last),
          );
    final target = await _validatedConfigFile(path);
    if (_isCanonicalPackageConfigFile(target.path, kind)) {
      await _copyPackageDirectory(source.parent, target.parent);
      return target.path;
    }
    await target.parent.create(recursive: true);
    await target.writeAsString(await source.readAsString());
    return path;
  }

  /// Deletes an existing config file.
  Future<void> delete(String path, {ConfigFileKind? kind}) async {
    final file = await _validatedConfigFile(path);
    if (!await file.exists()) {
      return;
    }
    if (kind != null && _isCanonicalPackageConfigFile(file.path, kind)) {
      final packageDir = file.parent;
      await packageDir.delete(recursive: true);
      return;
    }
    await file.delete();
  }

  /// Renames a config file inside its collection directory.
  Future<String> rename(ConfigFileEntry entry, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw FileSystemException('Configuration name is required', entry.path);
    }
    final file = await _validatedConfigFile(entry.path, requireExists: true);
    final directory = Directory(_directoryPath(entry.kind));
    await directory.create(recursive: true);
    final sanitized = _sanitizeFileName(trimmed);
    final sourceIsPackage = _isCanonicalPackageConfigFile(
      file.path,
      entry.kind,
    );
    final target = sourceIsPackage
        ? '${directory.path}/$sanitized/${_packageConfigFilename(entry.kind)}'
        : '${directory.path}/$sanitized${_extension(entry.path)}';
    if (target == entry.path) {
      return target;
    }
    if (await File(target).exists()) {
      throw FileSystemException('Configuration name already exists', target);
    }
    final targetFile = await _validatedConfigFile(target);
    if (sourceIsPackage) {
      if (await targetFile.parent.exists()) {
        throw FileSystemException(
          'Configuration package already exists',
          targetFile.parent.path,
        );
      }
      await file.parent.rename(targetFile.parent.path);
      return targetFile.path;
    }
    await file.rename(targetFile.path);
    return target;
  }

  /// Reports whether a managed path is the canonical file inside one package.
  bool _isCanonicalPackageConfigFile(String path, ConfigFileKind kind) {
    if (!_isPackageConfigKind(kind)) {
      return false;
    }
    final normalized = path.replaceAll('\\', '/');
    final filename = normalized.split('/').last;
    if (filename != _packageConfigFilename(kind)) {
      return false;
    }
    final packageRoot = _normalizedAbsolutePath(File(path).parent.parent.path);
    return packageRoot == _normalizedAbsolutePath(_directoryPath(kind));
  }

  String _directoryPath(ConfigFileKind kind) {
    final root = _configRootPath();
    return switch (kind) {
      ConfigFileKind.model => '$root/models',
      ConfigFileKind.agent => '$root/agents',
      ConfigFileKind.tool => _toolConfigRootPath(),
      ConfigFileKind.mcp => _mcpConfigRootPath(),
    };
  }

  String _defaultPrefix(ConfigFileKind kind) {
    return switch (kind) {
      ConfigFileKind.model => 'model',
      ConfigFileKind.agent => 'agent',
      ConfigFileKind.tool => 'tool',
      ConfigFileKind.mcp => 'mcp',
    };
  }

  /// Returns the configured root for editable app config files.
  String _configRootPath() {
    final trimmed = configDirectoryPath.trim();
    return trimmed.isEmpty ? agentAwesomeConfigDirectoryPath() : trimmed;
  }

  /// Returns the app OS config root that owns package config folders.
  String _appConfigRootPath() {
    final trimmed = configDirectoryPath.trim();
    if (trimmed.isEmpty) {
      return agentAwesomeAppConfigDirectoryPath();
    }
    return Directory(trimmed).parent.path;
  }

  /// Returns the tool package config directory for this store.
  String _toolConfigRootPath() {
    return '${_appConfigRootPath()}/$aaToolPackageDirectoryName';
  }

  /// Returns the MCP package config directory for this store.
  String _mcpConfigRootPath() {
    return '${_appConfigRootPath()}/$aaMcpPackageDirectoryName';
  }

  /// Returns a managed config file after validating its path and extension.
  Future<File> _validatedConfigFile(
    String path, {
    bool requireExists = false,
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw const FileSystemException('Configuration path is empty');
    }
    if (!_isConfigFile(trimmed)) {
      throw FileSystemException('Unsupported configuration file type', trimmed);
    }
    final file = File(trimmed);
    if (!_isManagedConfigPath(file.path)) {
      throw FileSystemException(
        'Configuration path is outside managed config directories',
        trimmed,
      );
    }
    if (await _hasSymlinkPathComponent(file.path)) {
      throw FileSystemException(
        'Configuration path cannot include symbolic links',
        trimmed,
      );
    }
    if (requireExists && !await file.exists()) {
      throw FileSystemException('Configuration file does not exist', trimmed);
    }
    return file;
  }

  /// Reports whether a path belongs to one editable config collection.
  bool _isManagedConfigPath(String path) {
    final candidate = _normalizedAbsolutePath(path);
    return ConfigFileKind.values.any((kind) {
      final directory = _normalizedAbsolutePath(_directoryPath(kind));
      return candidate == directory || candidate.startsWith('$directory/');
    });
  }

  /// Reports whether metadata can be read without crossing store boundaries.
  Future<bool> _canReadManagedMetadata(String path) async {
    final trimmed = path.trim();
    if (!_isConfigFile(trimmed)) {
      return false;
    }
    final file = File(trimmed);
    return _isManagedConfigPath(file.path) &&
        !await _hasSymlinkPathComponent(file.path);
  }

  /// Reports whether any existing managed-path segment is a symbolic link.
  Future<bool> _hasSymlinkPathComponent(String path) async {
    final candidate = _normalizedAbsolutePath(path);
    final root = _managedRootForPath(candidate);
    if (root == null) {
      return true;
    }
    if (candidate == root) {
      return false;
    }
    final relative = candidate.substring(root.length + 1);
    var current = root;
    for (final part in relative.split('/')) {
      if (part.isEmpty) {
        continue;
      }
      current = '$current/$part';
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        return true;
      }
      if (type == FileSystemEntityType.notFound) {
        return false;
      }
    }
    return false;
  }

  /// Returns the managed root that contains an absolute normalized path.
  String? _managedRootForPath(String normalizedPath) {
    final roots = <String>{
      _normalizedAbsolutePath(_configRootPath()),
      _normalizedAbsolutePath(_toolConfigRootPath()),
      _normalizedAbsolutePath(_mcpConfigRootPath()),
    }.toList()..sort((left, right) => right.length.compareTo(left.length));
    for (final root in roots) {
      if (normalizedPath == root || normalizedPath.startsWith('$root/')) {
        return root;
      }
    }
    return null;
  }
}

/// Returns selectable model choices for model config files.
Future<List<ModelConfigChoice>> _modelChoices(
  String path,
  ConfigFileKind kind,
) async {
  if (kind != ConfigFileKind.model) {
    return const <ModelConfigChoice>[];
  }
  final file = File(path);
  if (!await file.exists()) {
    return const <ModelConfigChoice>[];
  }
  try {
    return modelConfigChoices(await file.readAsString());
  } on FileSystemException {
    return const <ModelConfigChoice>[];
  }
}

/// Returns a config-content display name without changing harness schemas.
Future<String> _displayName(String path, ConfigFileKind kind) async {
  final file = File(path);
  if (!await file.exists()) {
    return '';
  }
  String content;
  try {
    content = await file.readAsString();
  } on FileSystemException {
    return '';
  }
  return switch (kind) {
    ConfigFileKind.model => modelConfigDisplayName(content),
    ConfigFileKind.agent => _configScalar(content, 'name') ?? '',
    ConfigFileKind.tool => _configScalar(content, 'name') ?? '',
    ConfigFileKind.mcp => _mcpConfigDisplayName(content),
  };
}

/// Returns a display label for a package-scoped MCP config.
String _mcpConfigDisplayName(String content) {
  final direct = _configScalar(content, 'name') ?? '';
  if (direct.isNotEmpty) {
    return direct;
  }
  final match = RegExp(
    r'^\s*-\s*name\s*:\s*(.*?)\s*$',
    multiLine: true,
  ).firstMatch(content);
  if (match == null) {
    return '';
  }
  return _unquoteYamlScalar((match.group(1) ?? '').trim());
}

/// Returns a top-level JSON or YAML scalar value for display labels.
String? _configScalar(String content, String key) {
  final jsonValue = _jsonScalar(content, key);
  if (jsonValue != null) {
    return jsonValue;
  }
  return _yamlScalar(content, key);
}

/// Returns a simple top-level JSON scalar value for display labels.
String? _jsonScalar(String content, String key) {
  if (!content.trimLeft().startsWith('{')) {
    return null;
  }
  try {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final value = decoded[key];
    if (value == null) {
      return null;
    }
    final label = value.toString().trim();
    return label.isEmpty ? null : label;
  } on FormatException {
    return null;
  }
}

/// Returns a simple top-level YAML scalar value for display labels.
String? _yamlScalar(String content, String key) {
  final pattern = RegExp('^$key\\s*:\\s*(.*?)\\s*\$', multiLine: true);
  final match = pattern.firstMatch(content);
  if (match == null) {
    return null;
  }
  final value = (match.group(1) ?? '').trim();
  if (value.isEmpty || value.startsWith('#')) {
    return null;
  }
  return _unquoteYamlScalar(value.split(' #').first.trim());
}

/// Removes matching YAML scalar quote wrappers for display purposes.
String _unquoteYamlScalar(String value) {
  if (value.length < 2) {
    return value;
  }
  final first = value[0];
  final last = value[value.length - 1];
  if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

/// Returns whether a path is a managed text configuration file.
bool _isConfigFile(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.yaml') ||
      lower.endsWith('.yml') ||
      lower.endsWith('.json');
}

/// Returns the files managed directly by a config collection.
Future<List<File>> _configFilesInDirectory(
  Directory directory,
  ConfigFileKind kind,
) async {
  final files = <File>[];
  await for (final entity in directory.list()) {
    if (entity is File && _isConfigFile(entity.path)) {
      files.add(entity);
      continue;
    }
    if (!_isPackageConfigKind(kind) || entity is! Directory) {
      continue;
    }
    final packageFile = File('${entity.path}/${_packageConfigFilename(kind)}');
    if (await packageFile.exists()) {
      files.add(packageFile);
    }
  }
  return files;
}

/// Reports whether config files for a kind live inside package folders.
bool _isPackageConfigKind(ConfigFileKind kind) {
  return kind == ConfigFileKind.tool || kind == ConfigFileKind.mcp;
}

/// Returns the canonical config filename for one package kind.
String _packageConfigFilename(ConfigFileKind kind) {
  return switch (kind) {
    ConfigFileKind.tool => aaToolPackageConfigFilename,
    ConfigFileKind.mcp => aaMcpPackageConfigFilename,
    ConfigFileKind.model => 'model.yaml',
    ConfigFileKind.agent => 'agent.yaml',
  };
}

/// Returns a unique package config path using a package folder.
Future<String> _uniquePackageConfigPath(
  String directory,
  String baseName,
  ConfigFileKind kind,
) async {
  var packageId = _sanitizeFileName(baseName);
  var candidate = '$directory/$packageId/${_packageConfigFilename(kind)}';
  var index = 2;
  while (await Directory('$directory/$packageId').exists()) {
    packageId = '${_sanitizeFileName(baseName)}-$index';
    candidate = '$directory/$packageId/${_packageConfigFilename(kind)}';
    index++;
  }
  return candidate;
}

/// Returns the target package config path for duplicating a package.
Future<String> _duplicatePackageConfigPath(
  String sourcePath,
  String directory,
  ConfigFileKind kind,
) async {
  final packageId = File(
    sourcePath,
  ).parent.path.replaceAll('\\', '/').split('/').last;
  return _uniquePackageConfigPath(directory, _copyName(packageId), kind);
}

/// Copies all package-owned files while rejecting symlink package contents.
Future<void> _copyPackageDirectory(Directory source, Directory target) async {
  if (await target.exists()) {
    throw FileSystemException(
      'Configuration package already exists',
      target.path,
    );
  }
  await target.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final targetPath = '${target.path}/$relative';
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw FileSystemException(
        'Configuration package cannot include symbolic links',
        entity.path,
      );
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(targetPath).create(recursive: true);
      continue;
    }
    if (type == FileSystemEntityType.file) {
      await File(targetPath).parent.create(recursive: true);
      await File(entity.path).copy(targetPath);
    }
  }
}

String _copyName(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot <= 0) {
    return '$filename-copy';
  }
  return '${filename.substring(0, dot)}-copy${filename.substring(dot)}';
}

Future<String> _uniquePath(String directory, String filename) async {
  final dot = filename.lastIndexOf('.');
  final base = dot <= 0 ? filename : filename.substring(0, dot);
  final extension = dot <= 0 ? '' : filename.substring(dot);
  var candidate = '$directory/$filename';
  var index = 2;
  while (await File(candidate).exists()) {
    candidate = '$directory/$base-$index$extension';
    index++;
  }
  return candidate;
}

String _extension(String path) {
  final filename = path.replaceAll('\\', '/').split('/').last;
  final dot = filename.lastIndexOf('.');
  if (dot <= 0) {
    return '.yaml';
  }
  return filename.substring(dot);
}

String _sanitizeFileName(String name) {
  final safe = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  if (safe.isEmpty) {
    throw FileSystemException('Configuration name has no valid characters');
  }
  return safe;
}

/// Returns a slash-normalized absolute path for boundary checks.
String _normalizedAbsolutePath(String path) {
  final raw = File(path).absolute.path.replaceAll('\\', '/');
  final prefix = raw.startsWith('/') ? '/' : '';
  final parts = <String>[];
  for (final part in raw.split('/')) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (parts.isNotEmpty && parts.last != '..') {
        parts.removeLast();
      } else {
        parts.add(part);
      }
      continue;
    }
    parts.add(part);
  }
  return '$prefix${parts.join('/')}';
}
