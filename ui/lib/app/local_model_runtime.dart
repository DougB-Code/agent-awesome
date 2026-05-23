/// Installs and serves local OpenAI-compatible models for Agent Awesome.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../domain/config_yaml.dart';
import '../domain/local_models.dart';
import '../domain/models.dart';
import 'app_config.dart';
import 'local_model_prompt.dart';
import 'local_services.dart';
import 'process_supervisor.dart';
import 'runtime_profile.dart';

const List<String> _localToolArgumentFields = <String>[
  'action',
  'actor',
  'assignee',
  'confidence',
  'description',
  'due_at',
  'estimate_minutes',
  'follow_up_at',
  'idempotency_key',
  'location',
  'note',
  'owner',
  'person',
  'priority',
  'project',
  'scheduled_at',
  'source',
  'status',
  'task',
  'text',
  'title',
  'topics',
  'urgency',
];

const _linuxX64LiteRtCliArtifact = LocalModelRuntimeArtifact(
  id: 'litert-lm-v0.10.1-linux-x64',
  displayName: 'LiteRT-LM CLI',
  fileName: 'lit_linux_x86_64',
  executableName: 'litert-lm',
  downloadUrl:
      'https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.10.1/lit_linux_x86_64',
  expectedBytes: 142096416,
  expectedSha256:
      'd8461038fc1ce523975f8a2ef8cf403cae30b85e469116f9bee186a3a8fe1f54',
);

/// Returns the app-managed LiteRT runtime artifact for this host platform.
LocalModelRuntimeArtifact? _defaultRuntimeArtifactForHost() {
  if (Abi.current() == Abi.linuxX64) {
    return _linuxX64LiteRtCliArtifact;
  }
  return null;
}

/// LocalModelExecutableResolver locates or prepares a runnable model binary.
class LocalModelExecutableResolver {
  /// Creates an executable resolver with injectable environment and commands.
  const LocalModelExecutableResolver({
    Map<String, String>? environment,
    CommandRunner? commandRunner,
    List<String> aliases = const <String>['litert_lm', 'litert-lm'],
    String displayName = 'LiteRT-LM',
  }) : _environment = environment,
       _commandRunner = commandRunner,
       _aliases = aliases,
       _displayName = displayName;

  final Map<String, String>? _environment;
  final CommandRunner? _commandRunner;
  final List<String> _aliases;
  final String _displayName;

  /// Returns a runnable executable path or throws a diagnostic error.
  Future<String> resolve({
    required String configuredExecutable,
    required String dataDirectory,
  }) async {
    final configured = configuredExecutable.trim();
    final names = _candidateNames(configured);
    final checked = <String>[];
    final presentButBlocked = <String>[];
    for (final candidate in _candidatePaths(
      configured: configured,
      names: names,
      dataDirectory: dataDirectory,
    )) {
      if (!checked.contains(candidate)) {
        checked.add(candidate);
      }
      if (await _isRunnable(candidate)) {
        return candidate;
      }
      if (await File(candidate).exists() &&
          !presentButBlocked.contains(candidate)) {
        presentButBlocked.add(candidate);
        final repaired = await _prepareRunnableCopy(
          sourcePath: candidate,
          dataDirectory: dataDirectory,
        );
        if (repaired != null) {
          return repaired;
        }
      }
    }
    throw StateError(_notFoundMessage(configured, checked, presentButBlocked));
  }

  List<String> _candidateNames(String configured) {
    final names = <String>[];
    if (configured.isNotEmpty && !_looksLikePath(configured)) {
      names.add(configured);
    }
    for (final alias in _aliases) {
      if (!names.contains(alias)) {
        names.add(alias);
      }
    }
    return names;
  }

  Iterable<String> _candidatePaths({
    required String configured,
    required List<String> names,
    required String dataDirectory,
  }) sync* {
    if (configured.isNotEmpty && _looksLikePath(configured)) {
      yield configured;
    }
    for (final name in names) {
      yield '$dataDirectory/bin/$name';
    }
    for (final directory in _pathDirectories()) {
      for (final name in names) {
        yield '$directory/$name';
      }
    }
    final home = (_environment ?? Platform.environment)['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      for (final directory in <String>[
        '$home/.local/bin',
        '$home/bin',
        '$home/programs/bin',
      ]) {
        for (final name in names) {
          yield '$directory/$name';
        }
      }
    }
  }

  List<String> _pathDirectories() {
    final path = (_environment ?? Platform.environment)['PATH']?.trim() ?? '';
    if (path.isEmpty) {
      return const <String>[];
    }
    return path
        .split(Platform.isWindows ? ';' : ':')
        .where((entry) => entry.trim().isNotEmpty)
        .toList();
  }

  Future<bool> _isRunnable(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return false;
    }
    if (Platform.isWindows) {
      return true;
    }
    final stat = await file.stat();
    return stat.type == FileSystemEntityType.file && (stat.mode & 0x49) != 0;
  }

  /// Copies a blocked executable into app-managed storage and makes it runnable.
  Future<String?> _prepareRunnableCopy({
    required String sourcePath,
    required String dataDirectory,
  }) async {
    if (Platform.isWindows) {
      return null;
    }
    try {
      final source = File(sourcePath);
      final sourceStat = await source.stat();
      if (sourceStat.type != FileSystemEntityType.file) {
        return null;
      }
      final fileName = source.uri.pathSegments.isEmpty
          ? _aliases.first
          : source.uri.pathSegments.last;
      final target = File('$dataDirectory/bin/$fileName');
      await target.parent.create(recursive: true);
      if (source.path == target.path) {
        return await _makeRunnable(target.path) &&
                await _isRunnable(target.path)
            ? target.path
            : null;
      }
      final partial = File('${target.path}.part');
      if (await partial.exists()) {
        await partial.delete();
      }
      await source.copy(partial.path);
      if (!await _makeRunnable(partial.path)) {
        await partial.delete();
        return null;
      }
      if (await target.exists()) {
        await target.delete();
      }
      await partial.rename(target.path);
      return await _isRunnable(target.path) ? target.path : null;
    } catch (_) {
      return null;
    }
  }

  /// Adds owner/group/other execute bits to a local executable candidate.
  Future<bool> _makeRunnable(String path) async {
    if (Platform.isWindows) {
      return true;
    }
    final commandRunner = _commandRunner;
    if (commandRunner == null) {
      return false;
    }
    final result = await commandRunner.run(
      'chmod',
      <String>['755', path],
      timeout: const Duration(seconds: 5),
      scope: 'local-model',
      kind: ManagedProcessKind.systemProbe,
    );
    return result.exitCode == 0;
  }

  bool _looksLikePath(String value) {
    return value.contains('/') || value.contains(r'\');
  }

  String _notFoundMessage(
    String configured,
    List<String> checked,
    List<String> presentButBlocked,
  ) {
    final requested = configured.isEmpty ? _aliases.first : configured;
    final inspected = checked.take(12).join(', ');
    final blocked = presentButBlocked.isEmpty
        ? ''
        : ' Found but not executable: ${presentButBlocked.join(', ')}.';
    return '$_displayName executable "$requested" was not found or is not executable. '
        'Install ${_aliases.first}, make it executable, or update app configuration. '
        '$blocked Checked: $inspected';
  }
}

/// LocalModelRuntime starts an app-owned OpenAI-compatible local model endpoint.
abstract class LocalModelRuntime {
  /// Ensures the selected model artifact exists and matches its manifest.
  Future<LocalModelInstall> ensureInstalled(
    LocalModelDescriptor model, {
    void Function(LocalModelInstallProgress progress)? onProgress,
  });

  /// Restores a previously downloaded artifact without using the network.
  Future<LocalModelInstall?> recoverInstalled(
    LocalModelDescriptor model, {
    List<String> candidatePaths = const <String>[],
    void Function(LocalModelInstallProgress progress)? onProgress,
  });

  /// Reports whether a model artifact is already installed and verified.
  Future<bool> isInstalled(LocalModelDescriptor model);

  /// Ensures the local runtime executable is installed and launchable.
  Future<String> ensureRuntimeInstalled({
    LocalModelDescriptor? model,
    void Function(LocalModelInstallProgress progress)? onProgress,
  });

  /// Starts the local runtime endpoint for an installed model.
  Future<ServiceProcessStatus> start(LocalModelDescriptor model);

  /// Stops any app-owned local model runtime resources.
  Future<void> close();
}

/// LiteRtLocalModelRuntime installs Hugging Face artifacts and serves them.
class LiteRtLocalModelRuntime implements LocalModelRuntime {
  /// Creates a LiteRT-backed local model runtime.
  LiteRtLocalModelRuntime({
    required this.config,
    required ProcessSupervisor processSupervisor,
    http.Client? httpClient,
    String? dataDirectory,
    LocalModelExecutableResolver? executableResolver,
    LocalModelRuntimeArtifact? runtimeArtifact,
  }) : _processSupervisor = processSupervisor,
       _http = httpClient ?? http.Client(),
       _dataDirectory = dataDirectory ?? agentAwesomeDataDirectoryPath(),
       _runtimeArtifact = runtimeArtifact ?? _defaultRuntimeArtifactForHost(),
       _executableResolver =
           executableResolver ??
           LocalModelExecutableResolver(
             commandRunner: ProcessSupervisorCommandRunner(processSupervisor),
           );

  /// App configuration that supplies paths and local endpoint settings.
  final AppConfig config;

  final ProcessSupervisor _processSupervisor;
  final http.Client _http;
  final String _dataDirectory;
  final LocalModelRuntimeArtifact? _runtimeArtifact;
  final LocalModelExecutableResolver _executableResolver;
  final Set<String> _verifiedInstallPaths = <String>{};
  _LiteRtOpenAiServer? _server;
  _LlamaCppOpenAiServer? _llamaServer;
  bool _closed = false;

  /// Ensures the selected model artifact exists and matches its manifest.
  @override
  Future<LocalModelInstall> ensureInstalled(
    LocalModelDescriptor model, {
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    final install = _installFor(model);
    if (await _isCurrentInstall(install)) {
      onProgress?.call(
        const LocalModelInstallProgress(
          phase: 'ready',
          message: 'Local model already installed',
        ),
      );
      return install;
    }
    if (!model.usesManagedDownload) {
      await Directory(install.directory).create(recursive: true);
      await _writeManifest(install);
      _verifiedInstallPaths.add(install.modelPath);
      onProgress?.call(
        LocalModelInstallProgress(
          phase: 'ready',
          message: '${model.providerName} model ready',
        ),
      );
      return install;
    }
    await Directory(install.directory).create(recursive: true);
    await _downloadModel(model, install, onProgress: onProgress);
    await _writeManifest(install);
    _verifiedInstallPaths.add(install.modelPath);
    onProgress?.call(
      const LocalModelInstallProgress(
        phase: 'ready',
        message: 'Local model installed',
      ),
    );
    return install;
  }

  /// Restores a verified local artifact from the app-managed model store.
  @override
  Future<LocalModelInstall?> recoverInstalled(
    LocalModelDescriptor model, {
    List<String> candidatePaths = const <String>[],
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    final install = _installFor(model);
    if (await _isCurrentInstall(install)) {
      return install;
    }
    final source = await _findRestorableArtifact(
      model,
      install,
      candidatePaths,
    );
    if (source == null) {
      return null;
    }
    onProgress?.call(
      LocalModelInstallProgress(
        phase: 'restoring',
        message: 'Restoring ${model.displayName}',
        totalBytes: model.expectedBytes,
      ),
    );
    await Directory(install.directory).create(recursive: true);
    final target = File(install.modelPath);
    if (source.path != target.path) {
      final partial = File('${install.modelPath}.part');
      if (await partial.exists()) {
        await partial.delete();
      }
      await source.copy(partial.path);
      await _replaceFile(partial, target);
    }
    await _writeManifest(install);
    _verifiedInstallPaths.add(install.modelPath);
    onProgress?.call(
      LocalModelInstallProgress(
        phase: 'ready',
        message: 'Local model restored',
        receivedBytes: model.expectedBytes,
        totalBytes: model.expectedBytes,
      ),
    );
    return install;
  }

  /// Reports whether a model artifact is already installed and verified.
  @override
  Future<bool> isInstalled(LocalModelDescriptor model) async {
    return _isCurrentInstall(_installFor(model));
  }

  /// Ensures the selected local runtime executable is installed.
  @override
  Future<String> ensureRuntimeInstalled({
    LocalModelDescriptor? model,
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    if (_isClosed) {
      throw StateError('Local model runtime is closed');
    }
    if (model?.runtimeKind == LocalModelRuntimeKind.llamaCpp) {
      final executable = await _resolveLlamaExecutable();
      final validationError = await _validateLlamaExecutable(executable);
      if (validationError.isNotEmpty) {
        throw StateError(validationError);
      }
      return executable;
    }
    final existing = await _resolvedLaunchableExecutable();
    if (existing != null) {
      return existing;
    }
    final artifact = _runtimeArtifact;
    if (artifact == null) {
      throw StateError(
        'No managed LiteRT-LM runtime binary is available for ${Abi.current()}.',
      );
    }
    final executable = await _ensureRuntimeArtifact(
      artifact,
      onProgress: onProgress,
    );
    final validationError = await _validateExecutable(executable);
    if (validationError.isNotEmpty) {
      throw StateError(validationError);
    }
    return executable;
  }

  /// Starts the local OpenAI-compatible runtime endpoint.
  @override
  Future<ServiceProcessStatus> start(LocalModelDescriptor model) async {
    if (_isClosed) {
      return _closedStatus(model);
    }
    if (!await isInstalled(model)) {
      return ServiceProcessStatus(
        name: model.providerName,
        url: _healthUrlFor(model),
        state: ConnectionStateKind.disconnected,
        message: '${model.displayName} is not installed',
      );
    }
    if (_isClosed) {
      return _closedStatus(model);
    }
    if (model.runtimeKind == LocalModelRuntimeKind.llamaCpp) {
      return _startLlama(model);
    }
    if (_server != null) {
      return ServiceProcessStatus(
        name: model.providerName,
        url: config.localModelHealthUrl,
        state: ConnectionStateKind.connected,
        message: 'Already running',
      );
    }
    final install = _installFor(model);
    final executable = await _resolveExecutableStatus();
    if (executable.status != null) {
      return executable.status!;
    }
    if (_isClosed) {
      return _closedStatus(model);
    }
    final server = _LiteRtOpenAiServer(
      baseUrl: config.localModelBaseUrl,
      executable: executable.path,
      install: install,
      dataDirectory: _dataDirectory,
      processSupervisor: _processSupervisor,
    );
    await server.start();
    if (_isClosed) {
      await server.close();
      return _closedStatus(model);
    }
    _server = server;
    return ServiceProcessStatus(
      name: model.providerName,
      url: config.localModelHealthUrl,
      state: ConnectionStateKind.connected,
      message: 'Started locally',
    );
  }

  /// Stops the local endpoint and closes HTTP resources.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _server?.close();
    await _llamaServer?.close();
    _server = null;
    _llamaServer = null;
    _http.close();
  }

  /// Returns whether the runtime is closed or the shared supervisor is closing.
  bool get _isClosed {
    return _closed || _processSupervisor.isClosing;
  }

  /// Returns a user-facing status for shutdown races.
  ServiceProcessStatus _closedStatus(LocalModelDescriptor model) {
    return ServiceProcessStatus(
      name: model.providerName,
      url: _healthUrlFor(model),
      state: ConnectionStateKind.disconnected,
      message: 'Local model runtime is closed',
    );
  }

  /// Starts llama.cpp's OpenAI-compatible server for one GGUF model.
  Future<ServiceProcessStatus> _startLlama(LocalModelDescriptor model) async {
    if (_llamaServer != null) {
      return ServiceProcessStatus(
        name: model.providerName,
        url: config.llamaCppHealthUrl,
        state: ConnectionStateKind.connected,
        message: 'Already running',
      );
    }
    final executable = await _resolveLlamaExecutableStatus();
    if (executable.status != null) {
      return executable.status!;
    }
    final install = _installFor(model);
    final server = _LlamaCppOpenAiServer(
      baseUrl: config.llamaCppBaseUrl,
      executable: executable.path,
      install: install,
      dataDirectory: _dataDirectory,
      processSupervisor: _processSupervisor,
      httpClient: _http,
    );
    await server.start();
    if (_isClosed) {
      await server.close();
      return _closedStatus(model);
    }
    _llamaServer = server;
    return ServiceProcessStatus(
      name: model.providerName,
      url: config.llamaCppHealthUrl,
      state: ConnectionStateKind.connected,
      message: 'Started locally',
    );
  }

  /// Returns the configured health endpoint for one local runtime.
  String _healthUrlFor(LocalModelDescriptor model) {
    return model.runtimeKind == LocalModelRuntimeKind.llamaCpp
        ? config.llamaCppHealthUrl
        : config.localModelHealthUrl;
  }

  /// Returns an already configured executable only when it passes validation.
  Future<String?> _resolvedLaunchableExecutable() async {
    try {
      final path = await _executableResolver.resolve(
        configuredExecutable: config.litertLmExecutable,
        dataDirectory: _dataDirectory,
      );
      final validationError = await _validateExecutable(path);
      return validationError.isEmpty ? path : null;
    } catch (_) {
      return null;
    }
  }

  /// Resolves the configured llama.cpp server executable.
  Future<String> _resolveLlamaExecutable() {
    final resolver = LocalModelExecutableResolver(
      commandRunner: ProcessSupervisorCommandRunner(_processSupervisor),
      aliases: const <String>['llama-server'],
      displayName: 'Llama.cpp',
    );
    return resolver.resolve(
      configuredExecutable: config.llamaCppExecutable,
      dataDirectory: _dataDirectory,
    );
  }

  /// Downloads or repairs the managed runtime binary and returns its path.
  Future<String> _ensureRuntimeArtifact(
    LocalModelRuntimeArtifact artifact, {
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    final target = File(_runtimeExecutablePath(artifact));
    if (await _isCurrentRuntimeArtifact(target, artifact)) {
      await _makeRuntimeExecutable(target);
      if (await _isExecutableFile(target)) {
        return target.path;
      }
    }
    await _downloadRuntimeArtifact(artifact, target, onProgress: onProgress);
    await _makeRuntimeExecutable(target);
    if (!await _isCurrentRuntimeArtifact(target, artifact) ||
        !await _isExecutableFile(target)) {
      throw StateError(
        '${artifact.displayName} installation verification failed',
      );
    }
    onProgress?.call(
      LocalModelInstallProgress(
        phase: 'runtime-ready',
        message: '${artifact.displayName} installed',
        receivedBytes: artifact.expectedBytes,
        totalBytes: artifact.expectedBytes,
      ),
    );
    return target.path;
  }

  /// Returns the app-managed executable path for a runtime artifact.
  String _runtimeExecutablePath(LocalModelRuntimeArtifact artifact) {
    return '$_dataDirectory/bin/${artifact.executableName}';
  }

  /// Reports whether a runtime binary matches the pinned artifact metadata.
  Future<bool> _isCurrentRuntimeArtifact(
    File candidate,
    LocalModelRuntimeArtifact artifact,
  ) async {
    if (!await candidate.exists()) {
      return false;
    }
    final stat = await candidate.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size != artifact.expectedBytes) {
      return false;
    }
    return await _sha256ForFile(candidate) == artifact.expectedSha256;
  }

  /// Reports whether a file can be launched on the current platform.
  Future<bool> _isExecutableFile(File file) async {
    if (!await file.exists()) {
      return false;
    }
    if (Platform.isWindows) {
      return true;
    }
    final stat = await file.stat();
    return stat.type == FileSystemEntityType.file && (stat.mode & 0x49) != 0;
  }

  /// Downloads and verifies a runtime artifact into the target executable path.
  Future<void> _downloadRuntimeArtifact(
    LocalModelRuntimeArtifact artifact,
    File target, {
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    final partial = File('${target.path}.part');
    await partial.parent.create(recursive: true);
    if (await partial.exists()) {
      await partial.delete();
    }
    onProgress?.call(
      LocalModelInstallProgress(
        phase: 'downloading-runtime',
        message: 'Downloading ${artifact.displayName}',
        totalBytes: artifact.expectedBytes,
      ),
    );
    final request = http.Request('GET', Uri.parse(artifact.downloadUrl));
    final response = await _http.send(request);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw StateError(
        '${artifact.displayName} download failed with HTTP ${response.statusCode}',
      );
    }
    var received = 0;
    final sink = partial.openWrite();
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(
          LocalModelInstallProgress(
            phase: 'downloading-runtime',
            message: 'Downloading ${artifact.displayName}',
            receivedBytes: received,
            totalBytes: artifact.expectedBytes,
          ),
        );
      }
    } finally {
      await sink.close();
    }
    if (received != artifact.expectedBytes) {
      throw StateError(
        '${artifact.displayName} download size mismatch: got $received bytes, expected ${artifact.expectedBytes}',
      );
    }
    onProgress?.call(
      LocalModelInstallProgress(
        phase: 'verifying-runtime',
        message: 'Verifying ${artifact.displayName}',
        receivedBytes: received,
        totalBytes: artifact.expectedBytes,
      ),
    );
    final digest = await _sha256ForFile(partial);
    if (digest != artifact.expectedSha256) {
      throw StateError('${artifact.displayName} checksum verification failed');
    }
    await _replaceFile(partial, target);
  }

  /// Marks a managed runtime binary executable on POSIX hosts.
  Future<void> _makeRuntimeExecutable(File file) async {
    if (Platform.isWindows) {
      return;
    }
    final result = await _processSupervisor.run(
      ManagedProcessSpec(
        id: 'chmod-litert-${DateTime.now().microsecondsSinceEpoch}',
        name: 'LiteRT-LM permission repair',
        executable: 'chmod',
        arguments: <String>['755', file.path],
        kind: ManagedProcessKind.systemProbe,
        shutdownMode: ManagedProcessShutdownMode.processOnly,
        timeout: const Duration(seconds: 5),
        scope: 'local-model',
      ),
    );
    if (result.exitCode != 0) {
      throw StateError(
        'Could not make ${file.path} executable: ${_processFailureText(result)}',
      );
    }
  }

  LocalModelInstall _installFor(LocalModelDescriptor model) {
    final runtimeDirectory = switch (model.runtimeKind) {
      LocalModelRuntimeKind.litertLm => 'litert-lm',
      LocalModelRuntimeKind.llamaCpp => 'llama-cpp',
    };
    final directory = '$_dataDirectory/models/$runtimeDirectory/${model.id}';
    return LocalModelInstall(
      model: model,
      directory: directory,
      modelPath: '$directory/${model.fileName}',
      manifestPath: '$directory/manifest.json',
    );
  }

  Future<_ExecutableResolution> _resolveExecutableStatus() async {
    try {
      final path = await _executableResolver.resolve(
        configuredExecutable: config.litertLmExecutable,
        dataDirectory: _dataDirectory,
      );
      final validationError = await _validateExecutable(path);
      if (validationError.isNotEmpty) {
        return _ExecutableResolution(
          path: '',
          status: ServiceProcessStatus(
            name: 'LiteRT-LM',
            url: config.localModelHealthUrl,
            state: ConnectionStateKind.disconnected,
            message: validationError,
          ),
        );
      }
      return _ExecutableResolution(path: path);
    } catch (error) {
      return _ExecutableResolution(
        path: '',
        status: ServiceProcessStatus(
          name: 'LiteRT-LM',
          url: config.localModelHealthUrl,
          state: ConnectionStateKind.disconnected,
          message: error.toString(),
        ),
      );
    }
  }

  Future<_ExecutableResolution> _resolveLlamaExecutableStatus() async {
    try {
      final path = await _resolveLlamaExecutable();
      final validationError = await _validateLlamaExecutable(path);
      if (validationError.isNotEmpty) {
        return _ExecutableResolution(
          path: '',
          status: ServiceProcessStatus(
            name: 'Llama.cpp',
            url: config.llamaCppHealthUrl,
            state: ConnectionStateKind.disconnected,
            message: validationError,
          ),
        );
      }
      return _ExecutableResolution(path: path);
    } catch (error) {
      return _ExecutableResolution(
        path: '',
        status: ServiceProcessStatus(
          name: 'Llama.cpp',
          url: config.llamaCppHealthUrl,
          state: ConnectionStateKind.disconnected,
          message: error.toString(),
        ),
      );
    }
  }

  Future<String> _validateExecutable(String path) async {
    try {
      final result = await _processSupervisor.run(
        ManagedProcessSpec(
          id: 'litert-help-${DateTime.now().microsecondsSinceEpoch}',
          name: 'LiteRT-LM validation',
          executable: path,
          arguments: const <String>['--help'],
          environment: _localModelProcessEnvironment(path, _dataDirectory),
          kind: ManagedProcessKind.systemProbe,
          shutdownMode: ManagedProcessShutdownMode.processGroup,
          timeout: const Duration(seconds: 10),
          scope: 'local-model',
        ),
      );
      if (result.exitCode == 0) {
        return '';
      }
      return 'LiteRT-LM could not start: ${_processFailureText(result)}';
    } catch (error) {
      return 'LiteRT-LM could not start: $error';
    }
  }

  Future<String> _validateLlamaExecutable(String path) async {
    try {
      final result = await _processSupervisor.run(
        ManagedProcessSpec(
          id: 'llama-help-${DateTime.now().microsecondsSinceEpoch}',
          name: 'Llama.cpp validation',
          executable: path,
          arguments: const <String>['--help'],
          environment: _localModelProcessEnvironment(path, _dataDirectory),
          kind: ManagedProcessKind.systemProbe,
          shutdownMode: ManagedProcessShutdownMode.processGroup,
          timeout: const Duration(seconds: 10),
          scope: 'local-model',
        ),
      );
      if (result.exitCode == 0) {
        return '';
      }
      return 'Llama.cpp could not start: ${_processFailureText(result)}';
    } catch (error) {
      return 'Llama.cpp could not start: $error';
    }
  }

  Future<bool> _isCurrentInstall(LocalModelInstall install) async {
    final file = File(install.modelPath);
    final manifest = File(install.manifestPath);
    if (!await manifest.exists()) {
      return false;
    }
    if (!install.model.usesManagedDownload) {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return false;
      }
      return decoded['id'] == install.model.id &&
          decoded['runtime'] ==
              _runtimeConfigValue(install.model.runtimeKind) &&
          decoded['hf_repo'] == install.model.hfRepo;
    }
    if (!await file.exists()) {
      return false;
    }
    final stat = await file.stat();
    if (stat.size != install.model.expectedBytes) {
      return false;
    }
    if (_verifiedInstallPaths.contains(install.modelPath)) {
      return true;
    }
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    if (decoded['sha256'] != install.model.expectedSha256 ||
        decoded['revision'] != install.model.revision ||
        decoded['file'] != install.model.fileName) {
      return false;
    }
    _verifiedInstallPaths.add(install.modelPath);
    return true;
  }

  Future<File?> _findRestorableArtifact(
    LocalModelDescriptor model,
    LocalModelInstall install,
    List<String> candidatePaths,
  ) async {
    final checked = <String>{};
    for (final path in await _modelArtifactCandidatePaths(
      model,
      install,
      candidatePaths,
    )) {
      if (path.trim().isEmpty || !checked.add(path)) {
        continue;
      }
      final candidate = File(path);
      if (await _isExpectedArtifact(candidate, model)) {
        return candidate;
      }
    }
    return null;
  }

  Future<List<String>> _modelArtifactCandidatePaths(
    LocalModelDescriptor model,
    LocalModelInstall install,
    List<String> candidatePaths,
  ) async {
    return <String>[...candidatePaths, install.modelPath];
  }

  Future<bool> _isExpectedArtifact(
    File candidate,
    LocalModelDescriptor model,
  ) async {
    if (!model.usesManagedDownload) {
      return false;
    }
    if (!await candidate.exists()) {
      return false;
    }
    final stat = await candidate.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size != model.expectedBytes) {
      return false;
    }
    return await _sha256ForFile(candidate) == model.expectedSha256;
  }

  Future<void> _downloadModel(
    LocalModelDescriptor model,
    LocalModelInstall install, {
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    final target = File(install.modelPath);
    final partial = File('${install.modelPath}.part');
    await partial.parent.create(recursive: true);
    if (await partial.exists()) {
      await partial.delete();
    }
    onProgress?.call(
      LocalModelInstallProgress(
        phase: 'downloading',
        message: 'Downloading ${model.displayName}',
        totalBytes: model.expectedBytes,
      ),
    );
    final request = http.Request('GET', Uri.parse(model.downloadUrl));
    final response = await _http.send(request);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw StateError(
        'Model download failed with HTTP ${response.statusCode}',
      );
    }
    var received = 0;
    final sink = partial.openWrite();
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(
          LocalModelInstallProgress(
            phase: 'downloading',
            message: 'Downloading ${model.displayName}',
            receivedBytes: received,
            totalBytes: model.expectedBytes,
          ),
        );
      }
    } finally {
      await sink.close();
    }
    if (received != model.expectedBytes) {
      throw StateError(
        'Model download size mismatch: got $received bytes, expected ${model.expectedBytes}',
      );
    }
    onProgress?.call(
      LocalModelInstallProgress(
        phase: 'verifying',
        message: 'Verifying ${model.displayName}',
        receivedBytes: received,
        totalBytes: model.expectedBytes,
      ),
    );
    final digest = await _sha256ForFile(partial);
    if (digest != model.expectedSha256) {
      throw StateError('Model checksum verification failed');
    }
    if (await target.exists()) {
      await target.delete();
    }
    await partial.rename(target.path);
  }

  Future<void> _replaceFile(File source, File target) async {
    if (await target.exists()) {
      await target.delete();
    }
    await source.rename(target.path);
  }

  Future<void> _writeManifest(LocalModelInstall install) async {
    final manifest = <String, dynamic>{
      'id': install.model.id,
      'display_name': install.model.displayName,
      'model_name': install.model.modelName,
      'repository': install.model.repository,
      'revision': install.model.revision,
      'file': install.model.fileName,
      'source': install.model.downloadUrl,
      'bytes': install.model.expectedBytes,
      'sha256': install.model.expectedSha256,
      'license': install.model.license,
      'runtime': _runtimeConfigValue(install.model.runtimeKind),
      if (install.model.hfRepo.isNotEmpty) 'hf_repo': install.model.hfRepo,
      'installed_at': DateTime.now().toUtc().toIso8601String(),
    };
    await File(
      install.manifestPath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
  }
}

/// _ExecutableResolution carries a resolved binary path or startup failure.
class _ExecutableResolution {
  /// Creates a local model executable resolution result.
  const _ExecutableResolution({required this.path, this.status});

  /// Runnable local model executable path.
  final String path;

  /// Startup failure status when the executable cannot be resolved.
  final ServiceProcessStatus? status;
}

/// _LiteRtOpenAiServer adapts LiteRT-LM CLI calls to HTTP chat completions.
class _LiteRtOpenAiServer {
  _LiteRtOpenAiServer({
    required this.baseUrl,
    required this.executable,
    required this.install,
    required this.dataDirectory,
    required this.processSupervisor,
  });

  final String baseUrl;
  final String executable;
  final LocalModelInstall install;
  final String dataDirectory;
  final ProcessSupervisor processSupervisor;
  final LocalModelOpenAiPromptBuilder _promptBuilder =
      const LocalModelOpenAiPromptBuilder();
  HttpServer? _server;
  Future<void> _inferenceQueue = Future<void>.value();
  bool _closed = false;

  /// Starts the loopback HTTP endpoint.
  Future<void> start() async {
    final uri = Uri.parse(baseUrl);
    final server = await HttpServer.bind(uri.host, uri.port);
    _server = server;
    unawaited(_serve(server));
  }

  /// Stops the loopback HTTP endpoint.
  Future<void> close() async {
    _closed = true;
    await _server?.close(force: true);
    _server = null;
    await processSupervisor.stopScope('local-model');
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/health') {
        await _writeJson(request, <String, dynamic>{'ok': true});
        return;
      }
      if (request.method == 'POST' &&
          request.uri.path == '/v1/chat/completions') {
        await _handleChatCompletion(request);
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (error) {
      await _writeJson(request, <String, dynamic>{
        'error': <String, dynamic>{'message': error.toString()},
      }, statusCode: HttpStatus.internalServerError);
    }
  }

  Future<void> _handleChatCompletion(HttpRequest request) async {
    final decoded = await _decodeRequest(request);
    final prompt = _promptBuilder.build(decoded);
    final text = await _queuedInference(prompt);
    final toolCall = _toolCallFromLocalModelText(text, decoded);
    final message = toolCall == null
        ? <String, dynamic>{'role': 'assistant', 'content': text}
        : <String, dynamic>{
            'role': 'assistant',
            'content': '',
            'tool_calls': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': toolCall.id,
                'type': 'function',
                'function': <String, dynamic>{
                  'name': toolCall.name,
                  'arguments': jsonEncode(toolCall.arguments),
                },
              },
            ],
          };
    await _writeJson(request, <String, dynamic>{
      'id': 'agentawesome-local-${DateTime.now().millisecondsSinceEpoch}',
      'object': 'chat.completion',
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'model': install.model.modelName,
      'choices': <Map<String, dynamic>>[
        <String, dynamic>{
          'index': 0,
          'message': message,
          'finish_reason': toolCall == null ? 'stop' : 'tool_calls',
        },
      ],
    });
  }

  Future<String> _queuedInference(String prompt) {
    if (_closed || processSupervisor.isClosing) {
      return Future<String>.error(StateError('Local model runtime is closed'));
    }
    final completer = Completer<String>();
    _inferenceQueue = _inferenceQueue.then((_) async {
      try {
        if (_closed || processSupervisor.isClosing) {
          throw StateError('Local model runtime is closed');
        }
        completer.complete(await _runInference(prompt));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<String> _runInference(String prompt) async {
    final promptFile = await _writePromptFile(prompt);
    try {
      final result = await processSupervisor.run(
        ManagedProcessSpec(
          id: 'litert-inference-${DateTime.now().microsecondsSinceEpoch}',
          name: 'LiteRT-LM inference',
          executable: executable,
          arguments: <String>[
            '--min_log_level',
            '4',
            'run',
            install.modelPath,
            '--input_prompt_file',
            promptFile.path,
          ],
          environment: _localModelProcessEnvironment(executable, dataDirectory),
          kind: ManagedProcessKind.requestScopedInference,
          shutdownMode: ManagedProcessShutdownMode.processGroup,
          timeout: const Duration(minutes: 10),
          scope: 'local-model',
        ),
      );
      if (result.exitCode != 0) {
        throw StateError(
          'LiteRT-LM exited with code ${result.exitCode}: ${_processFailureText(result)}',
        );
      }
      final output = _assistantTextFromOutput(result.stdout.toString());
      if (output.isEmpty) {
        throw StateError('LiteRT-LM returned an empty response');
      }
      return output;
    } finally {
      if (await promptFile.exists()) {
        await promptFile.delete();
      }
    }
  }

  Future<File> _writePromptFile(String prompt) async {
    final directory = Directory('$dataDirectory/tmp/local-model-prompts');
    await directory.create(recursive: true);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final file = File('${directory.path}/prompt-$timestamp.txt');
    await file.writeAsString(prompt);
    return file;
  }

  Future<Map<String, dynamic>> _decodeRequest(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Request body must be a JSON object');
    }
    return decoded;
  }

  /// Converts local-model textual tool markup into an OpenAI tool call.
  _LocalModelToolCall? _toolCallFromLocalModelText(
    String text,
    Map<String, dynamic> request,
  ) {
    if (!_promptBuilder.toolCallsAllowed(request)) {
      return null;
    }
    final payload = _toolCallPayload(text);
    if (payload == null) {
      return null;
    }
    final parsed = _parseToolCallPayload(payload);
    if (parsed == null) {
      return null;
    }
    return _normalizeToolCall(parsed, _availableToolNames(request['tools']));
  }

  /// Extracts the first supported local-model tool-call payload.
  String? _toolCallPayload(String text) {
    final start = text.indexOf('<|tool_call>');
    if (start == -1) {
      return null;
    }
    final afterStart = start + '<|tool_call>'.length;
    var end = text.indexOf('<tool_call|>', afterStart);
    if (end == -1) {
      end = text.indexOf('<|/tool_call|>', afterStart);
    }
    if (end == -1) {
      return null;
    }
    final payload = text.substring(afterStart, end).trim();
    return payload.isEmpty ? null : payload;
  }

  /// Parses supported tool payloads emitted by Gemma-family models.
  _LocalModelToolCall? _parseToolCallPayload(String payload) {
    var body = payload.trim();
    if (body.startsWith('call:')) {
      body = body.substring('call:'.length).trim();
    }
    return _parseStandardToolCallPayload(body) ??
        _parseWrappedToolCallPayload(body);
  }

  /// Parses name{arguments} local-model payloads.
  _LocalModelToolCall? _parseStandardToolCallPayload(String body) {
    final argsStart = body.indexOf('{');
    final argsEnd = body.lastIndexOf('}');
    if (argsStart <= 0 || argsEnd <= argsStart) {
      return null;
    }
    final name = body.substring(0, argsStart).trim();
    final arguments = _decodeLooseObject(
      body.substring(argsStart, argsEnd + 1),
    );
    if (name.isEmpty || arguments == null) {
      return null;
    }
    return _LocalModelToolCall(
      id: 'call-local-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      arguments: arguments,
    );
  }

  /// Parses Gemma's nested tool_call{tool_name{arguments}} wrapper.
  _LocalModelToolCall? _parseWrappedToolCallPayload(String body) {
    const wrapperPrefix = 'tool_call{';
    final trimmed = body.trim();
    if (!trimmed.startsWith(wrapperPrefix) || !trimmed.endsWith('}')) {
      return null;
    }
    var inner = trimmed
        .substring(wrapperPrefix.length, trimmed.length - 1)
        .trim();
    if (inner.startsWith('call:')) {
      inner = inner.substring('call:'.length).trim();
    }
    return _parseStandardToolCallPayload(inner);
  }

  /// Decodes JSON-like model output, accepting YAML flow maps as a fallback.
  Map<String, dynamic>? _decodeLooseObject(String text) {
    final normalized = _normalizeGemmaToolObject(text);
    try {
      final decoded = jsonDecode(normalized);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Fall through to YAML for unquoted keys emitted by small local models.
    }
    try {
      final decoded = loadYaml(normalized);
      final plain = plainYamlValue(decoded);
      if (plain is Map<String, dynamic>) {
        return plain;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Normalizes LiteRT quote sentinels into YAML/JSON-compatible text.
  String _normalizeGemmaToolObject(String text) {
    var normalized = text.replaceAll('<|"|>', '"').replaceAll("<|'|>", "'");
    for (final field in _localToolArgumentFields) {
      normalized = normalized
          .replaceAll('$field:"', '$field: "')
          .replaceAll("$field:'", "$field: '");
    }
    return normalized;
  }

  /// Returns function names supplied in the OpenAI-compatible request.
  Set<String> _availableToolNames(Object? tools) {
    if (tools is! List) {
      return const <String>{};
    }
    return tools
        .whereType<Map<String, dynamic>>()
        .map((tool) => tool['function'])
        .whereType<Map<String, dynamic>>()
        .map((function) => function['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  /// Maps known small-model aliases onto real MCP tool names.
  _LocalModelToolCall? _normalizeToolCall(
    _LocalModelToolCall call,
    Set<String> availableNames,
  ) {
    if (availableNames.contains(call.name)) {
      return call;
    }
    if (call.name == 'task_tool' && availableNames.contains('create_task')) {
      final action = call.arguments['action']?.toString().trim();
      if (action == 'create') {
        final args = _createTaskArguments(call.arguments);
        if ((args['title']?.toString().trim() ?? '').isNotEmpty) {
          return _LocalModelToolCall(
            id: call.id,
            name: 'create_task',
            arguments: args,
          );
        }
      }
    }
    return null;
  }

  /// Converts the model's generic task_tool shape into create_task arguments.
  Map<String, dynamic> _createTaskArguments(Map<String, dynamic> arguments) {
    final details = arguments['details'];
    final detailMap = details is Map<String, dynamic>
        ? details
        : const <String, dynamic>{};
    final title = _firstNonEmpty(<Object?>[
      detailMap['title'],
      arguments['title'],
      detailMap['description'],
      arguments['description'],
    ]);
    return <String, dynamic>{
      ...detailMap,
      if (title.isNotEmpty) 'title': title,
      if ((arguments['idempotency_key']?.toString().trim() ?? '').isNotEmpty)
        'idempotency_key': arguments['idempotency_key'].toString().trim(),
    };
  }

  /// Returns the first non-blank string value from candidate values.
  String _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  Future<void> _writeJson(
    HttpRequest request,
    Map<String, dynamic> body, {
    int statusCode = HttpStatus.ok,
  }) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}

/// _LlamaCppOpenAiServer supervises llama.cpp's native HTTP endpoint.
class _LlamaCppOpenAiServer {
  _LlamaCppOpenAiServer({
    required this.baseUrl,
    required this.executable,
    required this.install,
    required this.dataDirectory,
    required this.processSupervisor,
    required this.httpClient,
  });

  final String baseUrl;
  final String executable;
  final LocalModelInstall install;
  final String dataDirectory;
  final ProcessSupervisor processSupervisor;
  final http.Client httpClient;
  ManagedProcessHandle? _handle;

  /// Starts llama.cpp's OpenAI-compatible HTTP server.
  Future<void> start() async {
    final uri = Uri.parse(baseUrl);
    final arguments = <String>[
      '--host',
      uri.host,
      '--port',
      uri.port.toString(),
      ..._modelArguments(),
    ];
    _handle = await processSupervisor.start(
      ManagedProcessSpec(
        id: 'llama-cpp-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Llama.cpp',
        executable: executable,
        arguments: arguments,
        environment: _localModelProcessEnvironment(executable, dataDirectory),
        kind: ManagedProcessKind.longRunningService,
        shutdownMode: ManagedProcessShutdownMode.processGroup,
        persistence: ManagedProcessPersistence.pidRecord,
        outputLogPath: '$dataDirectory/logs/llama-cpp.log',
        scope: 'local-model',
      ),
    );
    try {
      await _waitForReadiness();
    } catch (_) {
      await close();
      rethrow;
    }
  }

  /// Stops the supervised llama.cpp server.
  Future<void> close() async {
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      await processSupervisor.stop(handle);
    }
  }

  /// Returns llama.cpp model arguments for managed HF or local-file models.
  List<String> _modelArguments() {
    if (install.model.hfRepo.trim().isNotEmpty) {
      return <String>['--hf-repo', install.model.hfRepo.trim()];
    }
    return <String>['--model', install.modelPath];
  }

  /// Waits until llama.cpp reports a healthy HTTP endpoint.
  Future<void> _waitForReadiness() async {
    final health = Uri.parse(baseUrl).replace(path: '/health', query: null);
    final deadline = DateTime.now().add(const Duration(minutes: 20));
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final response = await httpClient
            .get(health)
            .timeout(const Duration(seconds: 2));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return;
        }
        lastError = 'HTTP ${response.statusCode}';
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('Llama.cpp did not become ready: $lastError');
  }
}

/// _LocalModelToolCall stores one parsed local-model tool request.
class _LocalModelToolCall {
  /// Creates a local model tool call.
  const _LocalModelToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// OpenAI-compatible tool call id.
  final String id;

  /// Tool function name.
  final String name;

  /// Tool function arguments.
  final Map<String, dynamic> arguments;
}

/// Returns environment variables required by local model subprocesses.
Map<String, String> _localModelProcessEnvironment(
  String executable,
  String dataDirectory,
) {
  final executableDirectory = File(executable).parent.path;
  final environment = <String, String>{'HF_HOME': '$dataDirectory/huggingface'};
  if (!Platform.isWindows) {
    final current = Platform.environment['LD_LIBRARY_PATH']?.trim();
    environment['LD_LIBRARY_PATH'] = current == null || current.isEmpty
        ? executableDirectory
        : '$executableDirectory:$current';
  }
  return environment;
}

/// Returns compact subprocess failure text for user-visible diagnostics.
String _processFailureText(ManagedProcessResult result) {
  final stderr = result.stderr.trim();
  if (stderr.isNotEmpty) {
    return stderr;
  }
  return result.stdout.trim();
}

/// Removes known LiteRT runtime log lines from model output.
String _assistantTextFromOutput(String output) {
  final lines = output
      .split('\n')
      .where((line) => !line.startsWith('INFO: Created TensorFlow Lite '))
      .toList();
  return lines.join('\n').trim();
}

/// Returns the model-config value for one local runtime kind.
String _runtimeConfigValue(LocalModelRuntimeKind kind) {
  return switch (kind) {
    LocalModelRuntimeKind.litertLm => 'litert-lm',
    LocalModelRuntimeKind.llamaCpp => 'llama-cpp',
  };
}

/// Returns the SHA-256 digest for a file.
Future<String> _sha256ForFile(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
