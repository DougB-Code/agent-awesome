/// Starts and monitors local Agent Awesome service processes for the UI.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'app_config.dart';
import 'runtime_profile.dart';

/// ServiceProcessStatus reports local process orchestration state.
class ServiceProcessStatus {
  /// Creates an immutable local service process status.
  const ServiceProcessStatus({
    required this.name,
    required this.url,
    required this.state,
    required this.message,
  });

  /// Display name for the service.
  final String name;

  /// Health or API URL used to prove readiness.
  final String url;

  /// Current service availability state.
  final ConnectionStateKind state;

  /// Concise process or readiness detail.
  final String message;
}

/// ManagedServiceProcess stores an owned process and its cleanup strategy.
class ManagedServiceProcess {
  /// Creates an owned process handle.
  const ManagedServiceProcess({
    required this.process,
    required this.ownsProcessGroup,
  });

  /// Root process started by the supervisor.
  final Process process;

  /// Whether the process was started as a process-group leader.
  final bool ownsProcessGroup;

  /// Operating system process id.
  int get pid => process.pid;

  /// Completes when the root process exits.
  Future<int> get exitCode => process.exitCode;
}

/// ServiceProcessLaunchPlan stores the exact command used to start a service.
class ServiceProcessLaunchPlan {
  /// Creates an immutable process launch plan.
  const ServiceProcessLaunchPlan({
    required this.executable,
    required this.arguments,
    required this.ownsProcessGroup,
  });

  /// Executable passed to Process.start.
  final String executable;

  /// Arguments passed to Process.start.
  final List<String> arguments;

  /// Whether the launched process owns a separate process group.
  final bool ownsProcessGroup;
}

/// LocalServiceSupervisor starts and restarts local services for the UI.
class LocalServiceSupervisor {
  /// Creates a supervisor for services described by the app configuration.
  LocalServiceSupervisor({required this.config, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// Runtime configuration for local service commands and endpoints.
  final AppConfig config;

  final http.Client _http;
  final Map<String, ManagedServiceProcess> _started =
      <String, ManagedServiceProcess>{};
  final Map<String, StringBuffer> _logs = <String, StringBuffer>{};
  Future<void> _logWrite = Future<void>.value();

  /// Starts required services when auto-start is enabled.
  Future<List<ServiceProcessStatus>> startRequiredServices(
    RuntimeProfile profile, {
    bool restartAutoStarted = false,
  }) async {
    await _prepareLogDirectory();
    await _writeLogLine(
      'supervisor',
      'checking services for profile ${profile.id}; restart=$restartAutoStarted',
    );
    if (!config.autoStartLocalServices) {
      final status = _status(
        'Local Services',
        config.workspaceRoot,
        ConnectionStateKind.unknown,
        'Auto-start disabled',
      );
      await _writeStatusLog(status);
      return <ServiceProcessStatus>[status];
    }

    final statuses = <ServiceProcessStatus>[];
    for (final server in profile.mcpServers.where((server) => server.enabled)) {
      final status = await _ensureMcpServerStatus(
        profile,
        server,
        restartAutoStarted: restartAutoStarted,
      );
      await _writeStatusLog(status);
      statuses.add(status);
    }
    final harnessStatus = await _ensureHarnessStatus(
      profile,
      restartAutoStarted: restartAutoStarted,
    );
    await _writeStatusLog(harnessStatus);
    statuses.add(harnessStatus);
    final gateway = profile.gateway;
    if (gateway != null && gateway.enabled) {
      final gatewayStatus = await _ensureGatewayStatus(
        profile,
        gateway,
        restartAutoStarted: restartAutoStarted,
      );
      await _writeStatusLog(gatewayStatus);
      statuses.add(gatewayStatus);
    }
    return statuses;
  }

  /// Stops only processes started by this supervisor.
  Future<void> close() async {
    await Future.wait(_started.values.map(_terminateProcess));
    _started.clear();
    await _logWrite;
    _http.close();
  }

  /// Stops an auto-started service endpoint so it can reload fresh config.
  Future<void> _restartAutoStartedEndpoint({
    required String id,
    required String name,
    required Uri health,
  }) async {
    await _stopOwnedProcess(id: id, name: name);
    if (!await _isHealthy(health)) {
      return;
    }
    if (!_isLocalEndpoint(health)) {
      throw StateError(
        'Cannot restart $name because ${health.host} is not a local endpoint.',
      );
    }
    await _writeLogLine(name, 'stopping existing listener on ${health.port}');
    await _signalEndpointPort(name: name, port: health.port, signal: 'TERM');
    if (await _waitUntilUnhealthy(health)) {
      return;
    }
    await _signalEndpointPort(name: name, port: health.port, signal: 'KILL');
    if (!await _waitUntilUnhealthy(health)) {
      throw StateError(
        'Could not stop existing $name listener on port ${health.port}.',
      );
    }
  }

  /// Stops one process started by this supervisor if it is still tracked.
  Future<void> _stopOwnedProcess({
    required String id,
    required String name,
  }) async {
    final process = _started.remove(id);
    if (process == null) {
      return;
    }
    await _writeLogLine(name, 'stopping owned process ${process.pid}');
    await _terminateProcess(process);
  }

  /// Sends one signal to every process listening on a local TCP port.
  Future<void> _signalEndpointPort({
    required String name,
    required int port,
    required String signal,
  }) async {
    if (port <= 0) {
      throw StateError(
        'Cannot restart $name because the health port is empty.',
      );
    }
    if (Platform.isWindows) {
      throw StateError('Cannot restart an unowned $name listener on Windows.');
    }
    final result = await Process.run('fuser', <String>[
      '-k',
      '-$signal',
      '$port/tcp',
    ]);
    await _writeLogLine(
      name,
      'fuser -$signal port $port exit ${result.exitCode}: ${result.stderr}',
    );
  }

  /// Waits until a previously healthy endpoint stops answering.
  Future<bool> _waitUntilUnhealthy(Uri health) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!await _isHealthy(health)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  /// Ensures one MCP server and converts launch failures into a status.
  Future<ServiceProcessStatus> _ensureMcpServerStatus(
    RuntimeProfile profile,
    McpServerRuntime server, {
    required bool restartAutoStarted,
  }) async {
    try {
      return await _ensureMcpServer(
        profile,
        server,
        restartAutoStarted: restartAutoStarted,
      );
    } catch (error) {
      return _status(
        server.label,
        server.healthUrl,
        ConnectionStateKind.disconnected,
        await _startupFailureMessage(server.label, error),
      );
    }
  }

  /// Ensures the harness and converts launch failures into a status.
  Future<ServiceProcessStatus> _ensureHarnessStatus(
    RuntimeProfile profile, {
    required bool restartAutoStarted,
  }) async {
    try {
      return await _ensureHarness(
        profile,
        restartAutoStarted: restartAutoStarted,
      );
    } catch (error) {
      final harness = profile.harness;
      return _status(
        harness.label,
        harness.sessionsUrl,
        ConnectionStateKind.disconnected,
        await _startupFailureMessage(harness.label, error),
      );
    }
  }

  /// Ensures the gateway and converts launch failures into a status.
  Future<ServiceProcessStatus> _ensureGatewayStatus(
    RuntimeProfile profile,
    GatewayRuntime gateway, {
    required bool restartAutoStarted,
  }) async {
    try {
      return await _ensureGateway(
        profile,
        gateway,
        restartAutoStarted: restartAutoStarted,
      );
    } catch (error) {
      return _status(
        gateway.label,
        gateway.healthUrl,
        ConnectionStateKind.disconnected,
        await _startupFailureMessage(gateway.label, error),
      );
    }
  }

  /// Ensures one MCP server is reachable, starting it when the profile manages it.
  Future<ServiceProcessStatus> _ensureMcpServer(
    RuntimeProfile profile,
    McpServerRuntime server, {
    required bool restartAutoStarted,
  }) async {
    final health = Uri.parse(server.healthUrl);
    if (restartAutoStarted && server.autoStart) {
      await _restartAutoStartedEndpoint(
        id: server.id,
        name: server.label,
        health: health,
      );
    }
    if (server.healthUrl.isNotEmpty && await _isHealthy(health)) {
      return _status(
        server.label,
        server.healthUrl,
        ConnectionStateKind.connected,
        'Already running',
      );
    }
    if (!server.autoStart) {
      return _status(
        server.label,
        server.healthUrl,
        ConnectionStateKind.disconnected,
        'External service is not reachable',
      );
    }
    if (server.workingDirectory.isEmpty || server.packagePath.isEmpty) {
      return _status(
        server.label,
        server.healthUrl,
        ConnectionStateKind.disconnected,
        'Managed server has no package path',
      );
    }
    await _createArgumentDirectories(server.arguments);
    final process = await _startProcess(
      profile: profile,
      name: server.label,
      workingDirectory: server.workingDirectory,
      packagePath: server.packagePath,
      arguments: _withLogFile(server.arguments, _serviceLogPath(server.kind)),
    );
    _started[server.id] = process;
    return _waitForProcessHealth(
      server.label,
      health,
      process,
      logPath: _serviceLogPath(server.kind),
    );
  }

  /// Ensures the harness web API is reachable, starting it when needed.
  Future<ServiceProcessStatus> _ensureHarness(
    RuntimeProfile profile, {
    required bool restartAutoStarted,
  }) async {
    final harness = profile.harness;
    final health = Uri.parse(harness.sessionsUrl);
    if (restartAutoStarted && harness.autoStart) {
      await _restartAutoStartedEndpoint(
        id: harness.id,
        name: harness.label,
        health: health,
      );
    }
    if (await _isHealthy(health)) {
      return _status(
        harness.label,
        health.toString(),
        ConnectionStateKind.connected,
        'Already running',
      );
    }
    if (!harness.autoStart) {
      return _status(
        harness.label,
        health.toString(),
        ConnectionStateKind.disconnected,
        'External harness is not reachable',
      );
    }
    final process = await _startProcess(
      profile: profile,
      name: harness.label,
      workingDirectory: harness.workingDirectory,
      packagePath: harness.packagePath,
      arguments: _withHarnessLogFile(harness.arguments),
    );
    _started[harness.id] = process;
    return _waitForProcessHealth(
      harness.label,
      health,
      process,
      logPath: '${config.serviceLogDirectory}/harness.log',
    );
  }

  /// Ensures the gateway API is reachable, starting it when configured.
  Future<ServiceProcessStatus> _ensureGateway(
    RuntimeProfile profile,
    GatewayRuntime gateway, {
    required bool restartAutoStarted,
  }) async {
    final health = Uri.parse(gateway.healthUrl);
    if (restartAutoStarted && gateway.autoStart) {
      await _restartAutoStartedEndpoint(
        id: gateway.id,
        name: gateway.label,
        health: health,
      );
    }
    if (await _isHealthy(health)) {
      return _status(
        gateway.label,
        health.toString(),
        ConnectionStateKind.connected,
        'Already running',
      );
    }
    if (!gateway.autoStart) {
      return _status(
        gateway.label,
        health.toString(),
        ConnectionStateKind.disconnected,
        'External gateway is not reachable',
      );
    }
    final process = await _startProcess(
      profile: profile,
      name: gateway.label,
      workingDirectory: gateway.workingDirectory,
      packagePath: gateway.packagePath,
      arguments: gateway.arguments,
    );
    _started[gateway.id] = process;
    return _waitForProcessHealth(
      gateway.label,
      health,
      process,
      logPath: '${config.serviceLogDirectory}/gateway.log',
    );
  }

  /// Builds and starts one service binary with captured output.
  Future<ManagedServiceProcess> _startProcess({
    required RuntimeProfile profile,
    required String name,
    required String workingDirectory,
    required String packagePath,
    required List<String> arguments,
  }) async {
    final env = Map<String, String>.of(Platform.environment);
    env['GOCACHE'] =
        env['GOCACHE'] ?? '${config.workspaceRoot}/harness/build/gocache';
    await Directory(env['GOCACHE']!).create(recursive: true);
    final outputLogPath = _processOutputLogPath(arguments);
    await _writeLogLine(name, 'building $packagePath in $workingDirectory');
    final executable = await _buildBinary(
      profile: profile,
      name: name,
      workingDirectory: workingDirectory,
      packagePath: packagePath,
      environment: env,
    );

    await _writeLogLine(name, 'starting $executable ${arguments.join(' ')}');
    final processGroup = await _canStartProcessGroup();
    final launch = buildServiceProcessLaunchPlan(
      executable: executable,
      arguments: arguments,
      outputLogPath: outputLogPath,
      canStartProcessGroup: processGroup,
      isWindows: Platform.isWindows,
    );
    final process = await Process.start(
      launch.executable,
      launch.arguments,
      workingDirectory: workingDirectory,
      environment: env,
    );
    await _writeLogLine(
      name,
      'pid ${process.pid}; process_group=${launch.ownsProcessGroup}; log $outputLogPath',
    );
    _captureOutput(name, process.stdout, 'stdout');
    _captureOutput(name, process.stderr, 'stderr');
    return ManagedServiceProcess(
      process: process,
      ownsProcessGroup: launch.ownsProcessGroup,
    );
  }

  /// Builds a Go command binary into the pilot build directory.
  Future<String> _buildBinary({
    required RuntimeProfile profile,
    required String name,
    required String workingDirectory,
    required String packagePath,
    required Map<String, String> environment,
  }) async {
    final binRoot = Directory(
      '${config.workspaceRoot}/harness/build/profiles/${_binaryName(profile.id)}/bin',
    );
    await binRoot.create(recursive: true);
    final executable = '${binRoot.path}/${_binaryName(name)}';
    final result = await Process.run(
      'go',
      buildGoBuildArguments(outputPath: executable, packagePath: packagePath),
      workingDirectory: workingDirectory,
      environment: environment,
    );
    await _writeLogLine(name, 'go build exit ${result.exitCode}');
    await _writeLogBlock(name, 'go build stdout', result.stdout.toString());
    await _writeLogBlock(name, 'go build stderr', result.stderr.toString());
    if (result.exitCode != 0) {
      throw StateError('Could not build $name. See service logs for details.');
    }
    return executable;
  }

  /// Terminates one owned process gracefully before forcing it closed.
  Future<void> _terminateProcess(ManagedServiceProcess process) async {
    await _signalManagedProcess(process, ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      await _signalManagedProcess(process, ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 2));
    }
  }

  /// Sends a signal to the owned process group with a process-level fallback.
  Future<void> _signalManagedProcess(
    ManagedServiceProcess process,
    ProcessSignal signal,
  ) async {
    if (process.ownsProcessGroup && !Platform.isWindows) {
      final signalName = signal == ProcessSignal.sigkill ? 'KILL' : 'TERM';
      final result = await Process.run('kill', <String>[
        '-$signalName',
        '-${process.pid}',
      ]);
      if (result.exitCode == 0) {
        return;
      }
      await _writeLogLine(
        'supervisor',
        'process-group signal $signalName failed for ${process.pid}: ${result.stderr}',
      );
    }
    process.process.kill(signal);
  }

  /// Captures process output for service logs and readiness diagnostics.
  void _captureOutput(String name, Stream<List<int>> stream, String source) {
    final buffer = _logs.putIfAbsent(name, StringBuffer.new);
    stream.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      buffer.writeln(line);
      unawaited(_writeLogLine(name, '[$source] $line'));
    });
  }

  /// Waits for a process health endpoint or an early process exit.
  Future<ServiceProcessStatus> _waitForProcessHealth(
    String name,
    Uri health,
    ManagedServiceProcess process, {
    required String logPath,
  }) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (await _isHealthy(health)) {
        return _status(
          name,
          health.toString(),
          ConnectionStateKind.connected,
          'Started locally',
        );
      }
      final exited = await _hasExited(process);
      if (exited != null) {
        await _writeLogLine(
          name,
          'process exited before readiness with code $exited; recent output: ${_recentLog(name)}; log $logPath',
        );
        return _status(
          name,
          health.toString(),
          ConnectionStateKind.disconnected,
          'Exited before it was ready. See service logs for details.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _writeLogLine(
      name,
      'process did not become ready; recent output: ${_recentLog(name)}; log $logPath',
    );
    return _status(
      name,
      health.toString(),
      ConnectionStateKind.disconnected,
      'Started but did not become ready. See service logs for details.',
    );
  }

  /// Returns the exit code when the process has already stopped.
  Future<int?> _hasExited(ManagedServiceProcess process) async {
    try {
      return await process.exitCode.timeout(Duration.zero);
    } on TimeoutException {
      return null;
    }
  }

  /// Reports whether local services can be launched as killable process groups.
  Future<bool> _canStartProcessGroup() async {
    if (Platform.isWindows) {
      return false;
    }
    try {
      final result = await Process.run('which', <String>['setsid']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Reports whether an HTTP endpoint returns a successful status code.
  Future<bool> _isHealthy(Uri uri) async {
    try {
      final response = await _http.get(uri).timeout(const Duration(seconds: 1));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Reports whether an endpoint is safe for local process supervision.
  bool _isLocalEndpoint(Uri uri) {
    return uri.host == '127.0.0.1' ||
        uri.host == 'localhost' ||
        uri.host == '::1';
  }

  /// Returns the last process output lines for internal readiness logs.
  String _recentLog(String name) {
    final lines =
        _logs[name]?.toString().trim().split('\n') ?? const <String>[];
    if (lines.isEmpty) {
      return 'no process output';
    }
    return lines.length <= 3
        ? lines.join(' ')
        : lines.sublist(lines.length - 3).join(' ');
  }

  /// Logs raw startup failures and returns a UI-safe status message.
  Future<String> _startupFailureMessage(String name, Object error) async {
    await _writeLogLine(name, 'startup failed: $error');
    return 'Startup failed. See service logs for details.';
  }

  /// Converts a display name into a stable local binary filename.
  String _binaryName(String name) {
    final safe = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return safe.isEmpty ? 'service' : safe;
  }

  /// Creates parent directories for known file path arguments.
  Future<void> _createArgumentDirectories(List<String> arguments) async {
    for (var index = 0; index < arguments.length - 1; index++) {
      final flag = arguments[index];
      final value = arguments[index + 1];
      if (flag == '--db') {
        final parent = File(value).parent;
        await parent.create(recursive: true);
      }
      if (flag == '--data') {
        await Directory(value).create(recursive: true);
      }
    }
  }

  /// Creates a status value for the settings surface.
  ServiceProcessStatus _status(
    String name,
    String url,
    ConnectionStateKind state,
    String message,
  ) {
    return ServiceProcessStatus(
      name: name,
      url: url,
      state: state,
      message: message,
    );
  }

  /// Ensures the managed service log directory exists.
  Future<void> _prepareLogDirectory() async {
    await Directory(config.serviceLogDirectory).create(recursive: true);
  }

  /// Returns the persistent UI log path.
  String _uiLogPath() {
    return '${config.serviceLogDirectory}/ui.log';
  }

  /// Returns the persistent log path for a managed service kind.
  String _serviceLogPath(String kind) {
    return switch (kind) {
      'memory' => '${config.serviceLogDirectory}/memory.log',
      _ => '${config.serviceLogDirectory}/ui.log',
    };
  }

  /// Returns the service log path that should receive process stdio.
  String _processOutputLogPath(List<String> arguments) {
    for (var index = 0; index < arguments.length - 1; index++) {
      if (arguments[index] == '--log-file') {
        return arguments[index + 1];
      }
    }
    return _uiLogPath();
  }

  /// Adds or replaces a standard service log-file argument.
  List<String> _withLogFile(List<String> arguments, String path) {
    final next = <String>[];
    for (var index = 0; index < arguments.length; index++) {
      if (arguments[index] == '--log-file') {
        index++;
        continue;
      }
      next.add(arguments[index]);
    }
    return <String>[...next, '--log-file', path];
  }

  /// Adds the harness log-file argument before delegated runtime args.
  List<String> _withHarnessLogFile(List<String> arguments) {
    final boundary = arguments.indexOf('--');
    final path = '${config.serviceLogDirectory}/harness.log';
    if (boundary == -1) {
      return _withLogFile(arguments, path);
    }
    final runArgs = _withLogFile(arguments.sublist(0, boundary), path);
    return <String>[...runArgs, ...arguments.sublist(boundary)];
  }

  /// Writes one timestamped line to the UI log.
  Future<void> _writeLogLine(String name, String line) {
    final timestamp = DateTime.now().toIso8601String();
    final record = '[$timestamp] [$name] $line\n';
    final path = _uiLogPath();
    _logWrite = _logWrite
        .then((_) async {
          await Directory(config.serviceLogDirectory).create(recursive: true);
          await File(
            path,
          ).writeAsString(record, mode: FileMode.append, flush: true);
        })
        .catchError((Object _) {});
    return _logWrite;
  }

  /// Writes a titled multi-line block to the persistent logs.
  Future<void> _writeLogBlock(String name, String title, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _writeLogLine(name, '$title:');
    for (final line in trimmed.split('\n')) {
      await _writeLogLine(name, line);
    }
  }

  /// Writes a status transition to the combined service log.
  Future<void> _writeStatusLog(ServiceProcessStatus status) async {
    await _writeLogLine(
      'supervisor',
      '${status.name} ${status.state.name}: ${status.message}',
    );
  }
}

/// Builds a durable process command for managed local services.
ServiceProcessLaunchPlan buildServiceProcessLaunchPlan({
  required String executable,
  required List<String> arguments,
  required String outputLogPath,
  required bool canStartProcessGroup,
  required bool isWindows,
}) {
  if (isWindows) {
    return ServiceProcessLaunchPlan(
      executable: executable,
      arguments: arguments,
      ownsProcessGroup: false,
    );
  }
  final redirectedArguments = _stdioRedirectShellArguments(
    executable: executable,
    arguments: arguments,
    outputLogPath: outputLogPath,
  );
  if (!canStartProcessGroup) {
    return ServiceProcessLaunchPlan(
      executable: 'sh',
      arguments: redirectedArguments,
      ownsProcessGroup: false,
    );
  }
  return ServiceProcessLaunchPlan(
    executable: 'setsid',
    arguments: <String>['sh', ...redirectedArguments],
    ownsProcessGroup: true,
  );
}

/// Builds Go compiler arguments for managed service binaries.
List<String> buildGoBuildArguments({
  required String outputPath,
  required String packagePath,
}) {
  return <String>['build', '-buildvcs=false', '-o', outputPath, packagePath];
}

/// Builds shell arguments that redirect child stdio without shell-escaping args.
List<String> _stdioRedirectShellArguments({
  required String executable,
  required List<String> arguments,
  required String outputLogPath,
}) {
  return <String>[
    '-c',
    r'exec "$@" >> "$0" 2>&1',
    outputLogPath,
    executable,
    ...arguments,
  ];
}
