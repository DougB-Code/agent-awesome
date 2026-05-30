/// Starts and monitors local Agent Awesome service processes for the UI.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'app_config.dart';
import 'local_service_environment.dart';
import 'process_supervisor.dart';
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

/// _ManagedServiceEndpoint stores a local endpoint the UI is allowed to stop.
class _ManagedServiceEndpoint {
  /// Creates an endpoint stop target from agent runtime topology data.
  const _ManagedServiceEndpoint({
    required this.id,
    required this.name,
    required this.health,
    required this.arguments,
  });

  /// Stable agent runtime topology service id.
  final String id;

  /// Display name used in service logs.
  final String name;

  /// Health URL used to verify whether the process is still running.
  final Uri health;

  /// Launch arguments used to describe ports in shutdown messages.
  final List<String> arguments;
}

/// LocalServiceSupervisor starts and restarts local services for the UI.
class LocalServiceSupervisor {
  /// Creates a supervisor for services described by the app configuration.
  LocalServiceSupervisor({
    required this.config,
    required ProcessSupervisor processSupervisor,
    http.Client? httpClient,
  }) : _processSupervisor = processSupervisor,
       _http = httpClient ?? http.Client();

  /// Runtime configuration for local service commands and endpoints.
  final AppConfig config;

  final ProcessSupervisor _processSupervisor;
  final http.Client _http;
  final Map<String, ManagedProcessHandle> _started =
      <String, ManagedProcessHandle>{};
  final Map<String, _ManagedServiceEndpoint> _endpoints =
      <String, _ManagedServiceEndpoint>{};
  final Map<String, StringBuffer> _logs = <String, StringBuffer>{};
  final Set<String> _printedStartupKeys = <String>{};
  Future<void> _logWrite = Future<void>.value();
  bool _closed = false;

  /// Starts required services when auto-start is enabled.
  Future<List<ServiceProcessStatus>> startRequiredServices(
    RuntimeProfile profile, {
    bool restartAutoStarted = false,
    bool includeHarness = true,
    bool includeMcpServers = true,
  }) async {
    await _prepareLogDirectory();
    await _writeLogLine(
      'supervisor',
      'checking services for profile ${profile.id}; restart=$restartAutoStarted',
    );
    if (_closed || _processSupervisor.isClosing) {
      final status = _status(
        'Local Services',
        config.workspaceRoot,
        ConnectionStateKind.disconnected,
        'Supervisor is closed',
      );
      await _writeStatusLog(status);
      return <ServiceProcessStatus>[status];
    }
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
    if (includeMcpServers) {
      for (final server in profile.mcpServers.where(
        (server) => server.enabled,
      )) {
        final status = await _ensureMcpServerStatus(
          profile,
          server,
          restartAutoStarted: restartAutoStarted,
        );
        await _writeStatusLog(status);
        statuses.add(status);
      }
    }
    if (profile.workflow.enabled && !profile.workflow.hostedByHarness) {
      final workflowStatus = await _ensureWorkflowStatus(
        profile,
        restartAutoStarted: restartAutoStarted,
      );
      await _writeStatusLog(workflowStatus);
      statuses.add(workflowStatus);
    }
    if (includeHarness) {
      final harnessStatus = await _ensureHarnessStatus(
        profile,
        restartAutoStarted: restartAutoStarted,
      );
      await _writeStatusLog(harnessStatus);
      statuses.add(harnessStatus);
    }
    if (includeHarness &&
        profile.workflow.enabled &&
        profile.workflow.hostedByHarness) {
      final workflowStatus = await _ensureWorkflowStatus(
        profile,
        restartAutoStarted: restartAutoStarted,
      );
      await _writeStatusLog(workflowStatus);
      statuses.add(workflowStatus);
    }
    final gatewayStatus = await _ensureGatewayStatus(
      profile,
      profile.gateway,
      restartAutoStarted: restartAutoStarted,
    );
    await _writeStatusLog(gatewayStatus);
    statuses.add(gatewayStatus);
    return statuses;
  }

  /// Restarts managed memory MCP services so configuration files are reloaded.
  Future<List<ServiceProcessStatus>> restartMemoryServices(
    RuntimeProfile profile,
  ) async {
    await _prepareLogDirectory();
    await _writeLogLine(
      'supervisor',
      'restarting memory services for profile ${profile.id}',
    );
    if (_closed || _processSupervisor.isClosing) {
      final status = _status(
        'Memory Services',
        config.workspaceRoot,
        ConnectionStateKind.disconnected,
        'Supervisor is closed',
      );
      await _writeStatusLog(status);
      return <ServiceProcessStatus>[status];
    }
    if (!config.autoStartLocalServices) {
      final status = _status(
        'Memory Services',
        config.workspaceRoot,
        ConnectionStateKind.unknown,
        'Auto-start disabled',
      );
      await _writeStatusLog(status);
      return <ServiceProcessStatus>[status];
    }
    final statuses = <ServiceProcessStatus>[];
    for (final server in profile.memoryServers) {
      final status = await _ensureMcpServerStatus(
        profile,
        server,
        restartAutoStarted: true,
      );
      await _writeStatusLog(status);
      statuses.add(status);
    }
    return statuses;
  }

  /// Stops processes started or previously recorded by this supervisor.
  Future<void> close({void Function(String message)? onStatus}) async {
    _closed = true;
    for (final entry in _started.entries.toList().reversed) {
      final handle = entry.value;
      onStatus?.call('Stopping ${handle.spec.name} (pid ${handle.pid})');
      await _processSupervisor.stop(handle);
    }
    _started.clear();
    onStatus?.call('Checking stale managed service records');
    await _processSupervisor.stopPersistedProcesses(
      namespace: 'local-services',
      onStatus: onStatus,
    );
    await _stopKnownEndpointListeners(onStatus: onStatus);
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
    await _writeLogLine(name, 'stopping registered listener on ${health.port}');
    await _processSupervisor.stopPersistedProcess(
      namespace: 'local-services',
      id: id,
      name: name,
      onLog: (message) => _writeLogLine(name, message),
    );
    if (!await _isHealthy(health)) {
      return;
    }
    await _writeLogLine(
      name,
      'looking for managed Agent Awesome listener on ${health.port}',
    );
    final stopped = await _signalManagedPortListeners(
      name: name,
      port: health.port,
      signal: ManagedProcessSignal.term,
    );
    if (!stopped) {
      throw StateError(
        'Could not safely identify the existing $name listener on port '
        '${health.port}. Stop it manually before restarting.',
      );
    }
    if (await _waitUntilUnhealthy(health)) {
      return;
    }
    await _signalManagedPortListeners(
      name: name,
      port: health.port,
      signal: ManagedProcessSignal.kill,
    );
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
    await _processSupervisor.stop(process);
  }

  /// Remembers a managed endpoint for final shutdown verification.
  void _rememberServiceEndpoint({
    required String id,
    required String name,
    required Uri health,
    required List<String> arguments,
  }) {
    _endpoints[id] = _ManagedServiceEndpoint(
      id: id,
      name: name,
      health: health,
      arguments: arguments,
    );
  }

  /// Stops any verified managed binaries still listening on known endpoints.
  Future<void> _stopKnownEndpointListeners({
    void Function(String message)? onStatus,
  }) async {
    for (final endpoint in _endpoints.values.toList().reversed) {
      if (!_isLocalEndpoint(endpoint.health)) {
        continue;
      }
      final ports = serviceLocalPorts(
        health: endpoint.health,
        arguments: endpoint.arguments,
      );
      if (ports.isEmpty) {
        continue;
      }
      onStatus?.call('Verifying ${endpoint.name} has stopped');
      await _writeLogLine(
        endpoint.name,
        'final shutdown sweep for ${endpoint.id} on ports ${ports.join(', ')}',
      );
      var sentTerm = false;
      for (final port in ports) {
        sentTerm =
            await _signalManagedPortListeners(
              name: endpoint.name,
              port: port,
              signal: ManagedProcessSignal.term,
            ) ||
            sentTerm;
      }
      if (sentTerm) {
        await _waitUntilUnhealthy(endpoint.health);
      }
      for (final port in ports) {
        await _signalManagedPortListeners(
          name: endpoint.name,
          port: port,
          signal: ManagedProcessSignal.kill,
        );
      }
      if (!await _waitUntilUnhealthy(endpoint.health)) {
        await _writeLogLine(
          endpoint.name,
          'listener on ${ports.join(', ')} survived final shutdown sweep',
        );
      }
    }
  }

  /// Sends one signal to verified Agent Awesome listeners on a local TCP port.
  Future<bool> _signalManagedPortListeners({
    required String name,
    required int port,
    required ManagedProcessSignal signal,
  }) async {
    return _processSupervisor.signalVerifiedLocalPortListeners(
      name: name,
      port: port,
      signal: signal,
      onLog: (message) => _writeLogLine(name, message),
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

  /// Ensures workflow and converts launch failures into a status.
  Future<ServiceProcessStatus> _ensureWorkflowStatus(
    RuntimeProfile profile, {
    required bool restartAutoStarted,
  }) async {
    try {
      return await _ensureWorkflow(
        profile,
        restartAutoStarted: restartAutoStarted,
      );
    } catch (error) {
      final workflow = profile.workflow;
      return _status(
        workflow.label,
        workflow.healthUrl,
        ConnectionStateKind.disconnected,
        await _startupFailureMessage(workflow.label, error),
      );
    }
  }

  /// Ensures one MCP server is reachable, starting it when the profile manages it.
  Future<ServiceProcessStatus> _ensureMcpServer(
    RuntimeProfile profile,
    McpServerRuntime server, {
    required bool restartAutoStarted,
  }) async {
    final serviceId = agentRuntimeServiceId(profile, server.id);
    final health = Uri.parse(server.healthUrl);
    final logPath = _serviceLogPath(profile, server.kind);
    _rememberServiceEndpoint(
      id: serviceId,
      name: server.label,
      health: health,
      arguments: server.arguments,
    );
    if (restartAutoStarted && server.autoStart) {
      await _restartAutoStartedEndpoint(
        id: serviceId,
        name: server.label,
        health: health,
      );
    }
    if (server.healthUrl.isNotEmpty && await _isHealthy(health)) {
      await _emitObservedServiceLog(
        id: server.id,
        name: server.label,
        health: health,
        arguments: server.arguments,
      );
      return _status(
        server.label,
        server.healthUrl,
        ConnectionStateKind.connected,
        'Already running',
      );
    }
    if (!server.autoStart) {
      if (server.healthUrl.isEmpty) {
        return _status(
          server.label,
          server.endpoint,
          ConnectionStateKind.unknown,
          'External service is not supervised locally',
        );
      }
      return _status(
        server.label,
        server.healthUrl,
        ConnectionStateKind.disconnected,
        'External service is not reachable',
      );
    }
    if (server.workingDirectory.isEmpty || server.executablePath.isEmpty) {
      return _status(
        server.label,
        server.healthUrl,
        ConnectionStateKind.disconnected,
        'Managed server has no executable path',
      );
    }
    await _createArgumentDirectories(server.arguments);
    final process = await _startProcess(
      id: serviceId,
      name: server.label,
      health: health,
      workingDirectory: server.workingDirectory,
      executablePath: server.executablePath,
      arguments: _withLogFile(server.arguments, logPath),
    );
    _started[serviceId] = process;
    final status = await _waitForProcessHealth(
      server.label,
      health,
      process,
      logPath: logPath,
    );
    if (status.state != ConnectionStateKind.connected) {
      _started.remove(serviceId);
    }
    return status;
  }

  /// Ensures workflow is reachable, starting it when the profile manages it.
  Future<ServiceProcessStatus> _ensureWorkflow(
    RuntimeProfile profile, {
    required bool restartAutoStarted,
  }) async {
    final workflow = profile.workflow;
    final serviceId = agentRuntimeServiceId(profile, workflow.id);
    final health = Uri.parse(workflow.healthUrl);
    final arguments = workflowArgumentsForProfile(profile);
    if (workflow.hostedByHarness) {
      if (await _isHealthy(health)) {
        return _status(
          workflow.label,
          workflow.healthUrl,
          ConnectionStateKind.connected,
          'Hosted by harness',
        );
      }
      return _status(
        workflow.label,
        workflow.healthUrl,
        ConnectionStateKind.disconnected,
        'Harness-owned workflow service is not reachable',
      );
    }
    _rememberServiceEndpoint(
      id: serviceId,
      name: workflow.label,
      health: health,
      arguments: arguments,
    );
    if (restartAutoStarted && workflow.autoStart) {
      await _restartAutoStartedEndpoint(
        id: serviceId,
        name: workflow.label,
        health: health,
      );
    }
    if (await _isHealthy(health)) {
      await _emitObservedServiceLog(
        id: workflow.id,
        name: workflow.label,
        health: health,
        arguments: arguments,
      );
      return _status(
        workflow.label,
        workflow.healthUrl,
        ConnectionStateKind.connected,
        'Already running',
      );
    }
    if (!workflow.autoStart) {
      return _status(
        workflow.label,
        workflow.healthUrl,
        ConnectionStateKind.disconnected,
        'External workflow service is not reachable',
      );
    }
    await _createArgumentDirectories(arguments);
    final logPath = _agentServiceLogPath(profile, 'workflow.log');
    final process = await _startProcess(
      id: serviceId,
      name: workflow.label,
      health: health,
      workingDirectory: workflow.workingDirectory,
      executablePath: workflow.executablePath,
      arguments: arguments,
      outputLogPath: logPath,
    );
    _started[serviceId] = process;
    final status = await _waitForProcessHealth(
      workflow.label,
      health,
      process,
      logPath: logPath,
    );
    if (status.state != ConnectionStateKind.connected) {
      _started.remove(serviceId);
    }
    return status;
  }

  /// Ensures the harness web API is reachable, starting it when needed.
  Future<ServiceProcessStatus> _ensureHarness(
    RuntimeProfile profile, {
    required bool restartAutoStarted,
  }) async {
    final harness = profile.harness;
    final serviceId = agentRuntimeServiceId(profile, harness.id);
    final health = Uri.parse(harness.sessionsUrl);
    final arguments = harnessArgumentsForProfile(profile);
    _rememberServiceEndpoint(
      id: serviceId,
      name: harness.label,
      health: health,
      arguments: arguments,
    );
    if (restartAutoStarted && harness.autoStart) {
      await _restartAutoStartedEndpoint(
        id: serviceId,
        name: harness.label,
        health: health,
      );
    }
    if (await _isHealthy(health)) {
      await _emitObservedServiceLog(
        id: harness.id,
        name: harness.label,
        health: health,
        arguments: arguments,
      );
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
    await _createArgumentDirectories(arguments);
    final logPath = _agentServiceLogPath(profile, 'harness.log');
    final process = await _startProcess(
      id: serviceId,
      name: harness.label,
      health: health,
      workingDirectory: harness.workingDirectory,
      executablePath: harness.executablePath,
      arguments: _withHarnessLogFile(arguments, logPath),
    );
    _started[serviceId] = process;
    final status = await _waitForProcessHealth(
      harness.label,
      health,
      process,
      logPath: logPath,
    );
    if (status.state != ConnectionStateKind.connected) {
      _started.remove(serviceId);
    }
    return status;
  }

  /// Ensures the gateway API is reachable, starting it when configured.
  Future<ServiceProcessStatus> _ensureGateway(
    RuntimeProfile profile,
    GatewayRuntime gateway, {
    required bool restartAutoStarted,
  }) async {
    final serviceId = agentRuntimeServiceId(profile, gateway.id);
    final health = Uri.parse(gateway.healthUrl);
    final arguments = gatewayArgumentsForProfile(profile);
    _rememberServiceEndpoint(
      id: serviceId,
      name: gateway.label,
      health: health,
      arguments: arguments,
    );
    if (restartAutoStarted && gateway.autoStart) {
      await _restartAutoStartedEndpoint(
        id: serviceId,
        name: gateway.label,
        health: health,
      );
    }
    if (await _isHealthy(health)) {
      await _emitObservedServiceLog(
        id: gateway.id,
        name: gateway.label,
        health: health,
        arguments: arguments,
      );
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
    final logPath = _agentServiceLogPath(profile, 'gateway.log');
    final process = await _startProcess(
      id: serviceId,
      name: gateway.label,
      health: health,
      workingDirectory: gateway.workingDirectory,
      executablePath: gateway.executablePath,
      arguments: arguments,
      outputLogPath: logPath,
      disableSlackIngress: true,
    );
    _started[serviceId] = process;
    final status = await _waitForProcessHealth(
      gateway.label,
      health,
      process,
      logPath: logPath,
    );
    if (status.state != ConnectionStateKind.connected) {
      _started.remove(serviceId);
    }
    return status;
  }

  /// Starts one configured service executable through the shared supervisor.
  Future<ManagedProcessHandle> _startProcess({
    required String id,
    required String name,
    required Uri health,
    required String workingDirectory,
    required String executablePath,
    required List<String> arguments,
    String? outputLogPath,
    bool disableSlackIngress = false,
  }) async {
    final env = disableSlackIngress
        ? buildManagedGatewayEnvironment(config: config)
        : buildLocalServiceEnvironment(config: config);
    final resolvedOutputLogPath =
        outputLogPath ?? _processOutputLogPath(arguments);
    final executable = executablePath.trim();
    if (executable.isEmpty) {
      throw StateError('No executable configured for $name.');
    }
    if (_closed) {
      throw StateError(
        'Local service supervisor closed before starting $name.',
      );
    }

    await _writeLogLine(name, 'starting $executable ${arguments.join(' ')}');
    final process = await _processSupervisor.start(
      ManagedProcessSpec(
        id: id,
        name: name,
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: env,
        kind: ManagedProcessKind.longRunningService,
        shutdownMode: ManagedProcessShutdownMode.processGroup,
        persistence: ManagedProcessPersistence.pidRecord,
        outputLogPath: resolvedOutputLogPath,
        expectedExecutable: executable,
        scope: 'local-services',
      ),
    );
    await _writeLogLine(
      name,
      'pid ${process.pid}; process_group=${process.ownsProcessGroup}; log $resolvedOutputLogPath',
    );
    await _emitStartedServiceLog(
      id: id,
      name: name,
      pid: process.pid,
      executable: executable,
      ownsProcessGroup: process.ownsProcessGroup,
      health: health,
      arguments: arguments,
      outputLogPath: resolvedOutputLogPath,
    );
    if (_closed) {
      await _processSupervisor.stop(process);
      throw StateError('Local service supervisor closed after starting $name.');
    }
    return process;
  }

  /// Prints a one-time log line for a service the UI started.
  Future<void> _emitStartedServiceLog({
    required String id,
    required String name,
    required int pid,
    required String executable,
    required bool ownsProcessGroup,
    required Uri health,
    required List<String> arguments,
    required String outputLogPath,
  }) async {
    await _emitStartupLog(
      key: 'started:$id:$pid',
      line: serviceStartupLogLine(
        state: 'started',
        name: name,
        pid: pid,
        executable: executable,
        ownsProcessGroup: ownsProcessGroup,
        health: health,
        arguments: arguments,
        outputLogPath: outputLogPath,
      ),
    );
  }

  /// Prints a one-time log line for a reachable managed endpoint.
  Future<void> _emitObservedServiceLog({
    required String id,
    required String name,
    required Uri health,
    required List<String> arguments,
  }) async {
    await _emitStartupLog(
      key: 'observed:$id:${health.port}',
      line: serviceStartupLogLine(
        state: 'already-running',
        name: name,
        health: health,
        arguments: arguments,
      ),
    );
  }

  /// Writes one visible startup line to stdout and the UI log once.
  Future<void> _emitStartupLog({
    required String key,
    required String line,
  }) async {
    if (!_printedStartupKeys.add(key)) {
      return;
    }
    stdout.writeln('[agentawesome-ui] $line');
    await _writeLogLine('startup', line);
  }

  /// Waits for a process health endpoint or an early process exit.
  Future<ServiceProcessStatus> _waitForProcessHealth(
    String name,
    Uri health,
    ManagedProcessHandle process, {
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
      final exited = await _hasExited(process.exitCode);
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
    await _writeLogLine(name, 'stopping process ${process.pid} after timeout');
    await _processSupervisor.stop(process);
    return _status(
      name,
      health.toString(),
      ConnectionStateKind.disconnected,
      'Started but did not become ready. See service logs for details.',
    );
  }

  /// Returns the exit code when the process has already stopped.
  Future<int?> _hasExited(Future<int> exitCode) async {
    try {
      return await exitCode.timeout(Duration.zero);
    } on TimeoutException {
      return null;
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
      if (flag == '--definitions') {
        await Directory(value).create(recursive: true);
      }
      if (flag == '--workflow-db') {
        final parent = File(value).parent;
        await parent.create(recursive: true);
      }
      if (flag == '--workflow-definitions' ||
          flag == '--command-data-dir' ||
          flag == '--command-parser-dir' ||
          flag == '--command-allow-workdir') {
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
  String _serviceLogPath(RuntimeProfile profile, String kind) {
    return switch (kind) {
      'memory' => _agentServiceLogPath(profile, 'memory.log'),
      _ => '${config.serviceLogDirectory}/ui.log',
    };
  }

  /// Returns a profile-scoped service log path for one local agent runtime.
  String _agentServiceLogPath(RuntimeProfile profile, String filename) {
    return '${config.serviceLogDirectory}/agents/${serviceBinaryName(profile.id)}/$filename';
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
  List<String> _withHarnessLogFile(List<String> arguments, String path) {
    final boundary = arguments.indexOf('--');
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

  /// Writes a status transition to the combined service log.
  Future<void> _writeStatusLog(ServiceProcessStatus status) async {
    await _writeLogLine(
      'supervisor',
      '${status.name} ${status.state.name}: ${status.message}',
    );
  }
}

/// Returns the profile-scoped local service id for one agent runtime.
String agentRuntimeServiceId(RuntimeProfile profile, String serviceId) {
  final profilePart = serviceBinaryName(profile.id);
  final servicePart = serviceBinaryName(serviceId);
  return '$profilePart-$servicePart';
}

/// Converts a display name into a stable local binary filename.
String serviceBinaryName(String name) {
  final safe = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return safe.isEmpty ? 'service' : safe;
}

/// Builds the UI-visible startup line for one managed service process.
String serviceStartupLogLine({
  required String state,
  required String name,
  required Uri health,
  required List<String> arguments,
  int? pid,
  String executable = '',
  bool ownsProcessGroup = false,
  String outputLogPath = '',
}) {
  final parts = <String>[
    'subprocess $state',
    'name="$name"',
    if (pid != null) 'pid=$pid',
    'ports="${servicePortsDescription(health: health, arguments: arguments)}"',
    'health=$health',
    if (executable.isNotEmpty) 'binary=$executable',
    if (pid != null) 'process_group=$ownsProcessGroup',
    if (outputLogPath.isNotEmpty) 'log=$outputLogPath',
  ];
  return parts.join(' ');
}

/// Returns a concise description of the local ports a service should expose.
String servicePortsDescription({
  required Uri health,
  required List<String> arguments,
}) {
  final ports = <String>{};
  if (health.hasPort) {
    ports.add('health=${_hostPort(health.host, health.port)}');
  }
  for (var index = 0; index < arguments.length - 1; index++) {
    final flag = arguments[index];
    final value = arguments[index + 1];
    if (flag == '--addr') {
      ports.add('listen=${_listenDescription(value)}');
    } else if (flag == '--port') {
      ports.add('api=${_listenDescription(value)}');
    } else if (flag == '--context-api-addr') {
      ports.add('context=${_listenDescription(value)}');
    } else if (flag == '--workflow-api-addr') {
      ports.add('workflow=${_listenDescription(value)}');
    }
  }
  return ports.isEmpty ? 'unknown' : ports.join(', ');
}

/// Returns the local TCP ports advertised by one managed service endpoint.
Set<int> serviceLocalPorts({
  required Uri health,
  required List<String> arguments,
}) {
  final ports = <int>{};
  if (health.hasPort) {
    ports.add(health.port);
  }
  for (var index = 0; index < arguments.length - 1; index++) {
    final flag = arguments[index];
    final value = arguments[index + 1];
    if (flag == '--addr' ||
        flag == '--port' ||
        flag == '--context-api-addr' ||
        flag == '--workflow-api-addr') {
      final port = _listenPort(value);
      if (port != null) {
        ports.add(port);
      }
    }
  }
  return ports;
}

/// Formats a host and port pair for log display.
String _hostPort(String host, int port) {
  final safeHost = host.trim().isEmpty ? '127.0.0.1' : host.trim();
  return '$safeHost:$port';
}

/// Formats a listen flag value for log display.
String _listenDescription(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'unknown';
  }
  return RegExp(r'^\d+$').hasMatch(trimmed) ? ':$trimmed' : trimmed;
}

/// Extracts a TCP port from a listen flag value.
int? _listenPort(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final numeric = int.tryParse(trimmed);
  if (numeric != null) {
    return numeric > 0 ? numeric : null;
  }
  final separator = trimmed.lastIndexOf(':');
  if (separator == -1 || separator + 1 >= trimmed.length) {
    return null;
  }
  final port = int.tryParse(trimmed.substring(separator + 1));
  return port != null && port > 0 ? port : null;
}
