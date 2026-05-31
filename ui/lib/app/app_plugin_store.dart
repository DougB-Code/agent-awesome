/// Loads installed Agent Awesome app plugin packages from disk.
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../domain/app_plugin.dart';
import '../domain/app_plugin_manifest_parser.dart';
import '../domain/config_yaml.dart';
import 'process_supervisor.dart';
import 'runtime_profile.dart';

/// AppPluginManifestRenderer renders Starlark-backed plugin manifests.
abstract interface class AppPluginManifestRenderer {
  /// Renders one package-local Starlark entrypoint as a manifest map.
  Future<Map<String, dynamic>> render({
    required String packagePath,
    required String entrypoint,
  });
}

/// DisabledAppPluginRenderer skips script-backed plugins when no boundary exists.
class DisabledAppPluginRenderer implements AppPluginManifestRenderer {
  /// Creates a renderer that intentionally cannot execute plugin scripts.
  const DisabledAppPluginRenderer();

  /// Rejects rendering because no supervised runtime boundary was injected.
  @override
  Future<Map<String, dynamic>> render({
    required String packagePath,
    required String entrypoint,
  }) async {
    throw const FileSystemException('App plugin renderer is not configured');
  }
}

/// CommandRunnerAppPluginRenderer delegates Starlark execution to the harness.
class CommandRunnerAppPluginRenderer implements AppPluginManifestRenderer {
  /// Creates a renderer that invokes the agent-awesome CLI through supervision.
  const CommandRunnerAppPluginRenderer({
    required this.commandRunner,
    this.executable = 'agent-awesome',
    this.timeout = const Duration(seconds: 5),
  });

  /// Supervised command boundary used for plugin rendering.
  final CommandRunner commandRunner;

  /// Executable used for app plugin rendering.
  final String executable;

  /// Maximum time allowed for one plugin render.
  final Duration timeout;

  /// Renders a Starlark app plugin through the product CLI boundary.
  @override
  Future<Map<String, dynamic>> render({
    required String packagePath,
    required String entrypoint,
  }) async {
    final result = await commandRunner.run(
      executable,
      <String>[
        'apps',
        'render',
        packagePath,
        '--entrypoint',
        entrypoint,
        '--json',
      ],
      timeout: timeout,
      scope: 'app-plugins',
      kind: ManagedProcessKind.oneShotCommand,
    );
    if (result.timedOut) {
      throw FileSystemException(
        'App plugin Starlark render timed out',
        packagePath,
      );
    }
    if (result.exitCode != 0) {
      throw FileSystemException(
        'App plugin Starlark render failed',
        packagePath,
      );
    }
    final decoded = jsonDecode(result.stdout);
    if (decoded is! Map) {
      throw FileSystemException(
        'App plugin Starlark render did not return a manifest',
        packagePath,
      );
    }
    return <String, dynamic>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    };
  }
}

/// AppPluginStore reads manifest-backed app plugins from a managed directory.
class AppPluginStore {
  /// Creates a store rooted at the app plugin package directory.
  const AppPluginStore({
    this.rootPath = '',
    this.renderer = const DisabledAppPluginRenderer(),
  });

  /// Optional root path override used by tests and controlled bootstraps.
  final String rootPath;

  /// Renderer used when a package exposes a Starlark entrypoint.
  final AppPluginManifestRenderer renderer;

  /// Lists usable plugin manifests sorted by display name.
  Future<List<AppPluginManifest>> list() async {
    final root = Directory(_pluginRootPath());
    if (await _hasSymlinkPathComponent(root.path) || !await root.exists()) {
      return const <AppPluginManifest>[];
    }
    final manifests = <AppPluginManifest>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory || await _hasSymlinkPathComponent(entity.path)) {
        continue;
      }
      final manifest = await _readPackageManifestSafely(entity);
      if (manifest != null && manifest.isUsable) {
        manifests.add(manifest);
      }
    }
    manifests.sort((left, right) => left.name.compareTo(right.name));
    return manifests;
  }

  /// Reads one package manifest without letting a bad package break startup.
  Future<AppPluginManifest?> _readPackageManifestSafely(
    Directory package,
  ) async {
    try {
      return await _readPackageManifest(package);
    } on Object {
      return null;
    }
  }

  /// Reads the first supported manifest file inside one package.
  Future<AppPluginManifest?> _readPackageManifest(Directory package) async {
    for (final filename in const <String>[
      aaAppPluginManifestFilename,
      'app.yml',
      'manifest.yaml',
      'manifest.yml',
    ]) {
      final file = File('${package.path}/$filename');
      if (!await file.exists() || await _hasSymlinkPathComponent(file.path)) {
        continue;
      }
      final parsed = loadYaml(await file.readAsString());
      final value = plainYamlValue(parsed);
      if (value is! Map<String, dynamic>) {
        continue;
      }
      return parseAppPluginManifest(value, packagePath: package.path);
    }
    return _readStarlarkManifest(package);
  }

  /// Renders an app.star package when no static manifest is present.
  Future<AppPluginManifest?> _readStarlarkManifest(Directory package) async {
    final entrypoint = File('${package.path}/app.star');
    if (!await entrypoint.exists() ||
        await _hasSymlinkPathComponent(entrypoint.path)) {
      return null;
    }
    final rendered = await renderer.render(
      packagePath: package.path,
      entrypoint: 'app.star',
    );
    final manifest = <String, dynamic>{
      ...rendered,
      'renderedFromStarlark': true,
    };
    return parseAppPluginManifest(manifest, packagePath: package.path);
  }

  /// Returns the managed root path for app plugin packages.
  String _pluginRootPath() {
    final trimmed = rootPath.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return appPluginConfigsDirectoryPath();
  }
}

/// Returns the directory where installed app plugin packages live.
String appPluginConfigsDirectoryPath() {
  return '${agentAwesomeAppConfigDirectoryPath()}/$aaAppPluginPackageDirectoryName';
}

/// Reports whether any path component is a symbolic link.
Future<bool> _hasSymlinkPathComponent(String path) async {
  final absolute = File(path).absolute.path;
  final parts = absolute.split(Platform.pathSeparator);
  var current = absolute.startsWith(Platform.pathSeparator)
      ? Platform.pathSeparator
      : '';
  for (final part in parts) {
    if (part.isEmpty) {
      continue;
    }
    current = current == Platform.pathSeparator || current.isEmpty
        ? '$current$part'
        : '$current${Platform.pathSeparator}$part';
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type == FileSystemEntityType.link) {
      return true;
    }
  }
  return false;
}
