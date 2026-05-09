/// Supervises subprocesses started by the Agent Awesome UI.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// ManagedProcessKind describes why the UI started a subprocess.
enum ManagedProcessKind {
  /// A service that should stay alive until app shutdown.
  longRunningService,

  /// A short-lived command owned by one app operation.
  oneShotCommand,

  /// A LiteRT inference request scoped to one local-model HTTP request.
  requestScopedInference,

  /// A platform keyring command.
  keyringCommand,

  /// A bounded system capability probe.
  systemProbe,
}

/// ManagedProcessShutdownMode describes how shutdown should signal a process.
enum ManagedProcessShutdownMode {
  /// Signal only the root process.
  processOnly,

  /// Signal the root process group when the platform supports it.
  processGroup,

  /// Placeholder for Windows Job Object based process-tree shutdown.
  windowsJob,
}

/// ManagedProcessPersistence describes whether process ownership is persisted.
enum ManagedProcessPersistence {
  /// Do not write a pid record.
  none,

  /// Persist a verified pid record for stale cleanup after UI restart.
  pidRecord,
}

/// ManagedProcessSignal names the termination signals used by cleanup code.
enum ManagedProcessSignal {
  /// Request graceful process termination.
  term,

  /// Force process termination.
  kill,
}

/// ManagedProcessSpec stores one subprocess launch request.
class ManagedProcessSpec {
  /// Creates an immutable subprocess launch specification.
  const ManagedProcessSpec({
    required this.id,
    required this.name,
    required this.executable,
    this.arguments = const <String>[],
    this.workingDirectory,
    this.environment = const <String, String>{},
    required this.kind,
    this.shutdownMode = ManagedProcessShutdownMode.processGroup,
    this.persistence = ManagedProcessPersistence.none,
    this.timeout,
    this.stdinText,
    this.outputLogPath,
    this.expectedExecutable,
    this.scope = '',
    this.killOnSupervisorClose = true,
  });

  /// Stable process id within its scope.
  final String id;

  /// Human-readable process name for logs.
  final String name;

  /// Executable requested by app code.
  final String executable;

  /// Arguments requested by app code.
  final List<String> arguments;

  /// Optional working directory for the process.
  final String? workingDirectory;

  /// Environment overrides for the process.
  final Map<String, String> environment;

  /// The reason this process exists.
  final ManagedProcessKind kind;

  /// Requested shutdown strategy.
  final ManagedProcessShutdownMode shutdownMode;

  /// Whether a pid record should be persisted.
  final ManagedProcessPersistence persistence;

  /// Optional timeout for one-shot commands.
  final Duration? timeout;

  /// Optional stdin text for one-shot commands.
  final String? stdinText;

  /// Optional log file receiving stdout and stderr for long-running services.
  final String? outputLogPath;

  /// Executable path that must still own persisted pids before signaling.
  final String? expectedExecutable;

  /// Logical process scope used for grouped shutdown.
  final String scope;

  /// Whether supervisor shutdown should kill this process.
  final bool killOnSupervisorClose;
}

/// ManagedProcessResult stores a completed one-shot command result.
class ManagedProcessResult {
  /// Creates an immutable command result.
  const ManagedProcessResult({
    required this.id,
    required this.pid,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
  });

  /// Stable process id from the launch spec.
  final String id;

  /// Operating-system root process id.
  final int pid;

  /// Process exit code, or -1 when forced shutdown did not report one.
  final int exitCode;

  /// Captured stdout text.
  final String stdout;

  /// Captured stderr text.
  final String stderr;

  /// Whether the command exceeded its timeout.
  final bool timedOut;
}

/// ManagedProcessHandle exposes a supervised process without leaking Process.
class ManagedProcessHandle {
  ManagedProcessHandle._({
    required this.spec,
    required this.pid,
    required this.exitCode,
    required this.ownsProcessGroup,
  });

  /// Launch specification used to create this process.
  final ManagedProcessSpec spec;

  /// Operating-system root process id.
  final int pid;

  /// Future completing with the root process exit code.
  final Future<int> exitCode;

  /// Whether this pid is expected to be a process-group leader.
  final bool ownsProcessGroup;
}

/// CommandRunner runs bounded commands without exposing process primitives.
abstract class CommandRunner {
  /// Runs one command through an app-owned subprocess supervisor.
  Future<ManagedProcessResult> run(
    String executable,
    List<String> arguments, {
    String? stdinText,
    Duration? timeout,
    String scope,
    ManagedProcessKind kind,
  });
}

/// ProcessSupervisorCommandRunner adapts ProcessSupervisor to CommandRunner.
class ProcessSupervisorCommandRunner implements CommandRunner {
  /// Creates a command runner backed by the shared supervisor.
  const ProcessSupervisorCommandRunner(this.supervisor);

  /// Shared app-wide process supervisor.
  final ProcessSupervisor supervisor;

  /// Runs a bounded command through the shared supervisor.
  @override
  Future<ManagedProcessResult> run(
    String executable,
    List<String> arguments, {
    String? stdinText,
    Duration? timeout,
    String scope = 'commands',
    ManagedProcessKind kind = ManagedProcessKind.oneShotCommand,
  }) {
    final commandName = _safeId(_basename(executable));
    return supervisor.run(
      ManagedProcessSpec(
        id: '$scope-$commandName-${DateTime.now().microsecondsSinceEpoch}',
        name: '$scope $commandName',
        executable: executable,
        arguments: arguments,
        stdinText: stdinText,
        timeout: timeout,
        kind: kind,
        shutdownMode: ManagedProcessShutdownMode.processOnly,
        scope: scope,
      ),
    );
  }
}

/// ManagedProcessLaunchPlan stores the concrete command passed to dart:io.
class ManagedProcessLaunchPlan {
  /// Creates an immutable process launch plan.
  const ManagedProcessLaunchPlan({
    required this.executable,
    required this.arguments,
    required this.ownsProcessGroup,
  });

  /// Executable passed to Process.start.
  final String executable;

  /// Arguments passed to Process.start.
  final List<String> arguments;

  /// Whether the launched process should own a separate process group.
  final bool ownsProcessGroup;
}

/// ProcessSupervisor owns all app-started subprocesses.
class ProcessSupervisor {
  /// Creates an app-wide process supervisor.
  ProcessSupervisor({required this.logDirectory, required this.workspaceRoot});

  /// Directory where supervisor logs and pid records are written.
  final String logDirectory;

  /// Repository root used to verify app-built service binaries.
  final String workspaceRoot;

  final Map<ManagedProcessHandle, _ManagedProcessEntry> _active =
      <ManagedProcessHandle, _ManagedProcessEntry>{};
  final List<ManagedProcessHandle> _startOrder = <ManagedProcessHandle>[];
  Future<void> _logWrite = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closing = false;
  bool? _setsidAvailable;

  /// Whether this supervisor has begun shutting down.
  bool get isClosing => _closing;

  /// Marks the supervisor as closing so new launches are rejected.
  void beginClosing() {
    _closing = true;
  }

  /// Starts one supervised subprocess and registers it immediately.
  Future<ManagedProcessHandle> start(ManagedProcessSpec spec) async {
    _throwIfClosing();
    await _prepareLaunchFilesystem(spec);
    final launch = await _launchPlanFor(spec);
    _throwIfClosing();
    final process = await Process.start(
      launch.executable,
      launch.arguments,
      workingDirectory: spec.workingDirectory,
      environment: spec.environment.isEmpty ? null : spec.environment,
    );
    final ownsProcessGroup =
        launch.ownsProcessGroup && await _isProcessGroupLeader(process.pid);
    final handle = ManagedProcessHandle._(
      spec: spec,
      pid: process.pid,
      exitCode: process.exitCode,
      ownsProcessGroup: ownsProcessGroup,
    );
    final entry = _ManagedProcessEntry(
      handle: handle,
      process: process,
      expectedExecutable: spec.expectedExecutable ?? spec.executable,
      pidFilePath: _pidRecordPathForSpec(spec),
      startedAt: DateTime.now().toUtc(),
    );
    _active[handle] = entry;
    _startOrder.add(handle);
    if (spec.kind == ManagedProcessKind.longRunningService) {
      _drainServiceOutput(process);
      unawaited(
        process.exitCode.then((_) => _forget(handle)).catchError((Object _) {}),
      );
    }
    try {
      await _writePidRecordIfNeeded(entry);
    } catch (_) {
      await stop(handle);
      throw StateError(
        'Could not record ${spec.name} process ownership. See service logs for details.',
      );
    }
    await _writeLogLine(
      spec.name,
      'started pid ${process.pid}; kind=${spec.kind.name}; '
      'scope=${_namespace(spec.scope)}; process_group=$ownsProcessGroup; '
      'shutdown=${_actualShutdownMode(spec, ownsProcessGroup)}',
    );
    if (_closing) {
      await stop(handle);
      throw StateError('Process supervisor is closing');
    }
    return handle;
  }

  /// Runs one supervised command with captured output and optional timeout.
  Future<ManagedProcessResult> run(ManagedProcessSpec spec) async {
    final handle = await start(spec);
    final entry = _active[handle];
    if (entry == null) {
      throw StateError('Managed process exited before output capture started');
    }
    final stdoutFuture = entry.process.stdout.transform(utf8.decoder).join();
    final stderrFuture = entry.process.stderr.transform(utf8.decoder).join();
    try {
      final stdinText = spec.stdinText;
      if (stdinText != null) {
        entry.process.stdin.write(stdinText);
      }
      await entry.process.stdin.close();
    } catch (_) {
      // The child may close stdin before the parent writes; exit handling below
      // still reports the process outcome.
    }

    var timedOut = false;
    var exitCode = -1;
    try {
      final timeout = spec.timeout;
      if (timeout == null) {
        exitCode = await handle.exitCode;
      } else {
        exitCode = await handle.exitCode.timeout(timeout);
      }
    } on TimeoutException {
      timedOut = true;
      await _writeLogLine(spec.name, 'timed out after ${spec.timeout}');
      await stop(handle);
      exitCode = await _exitCodeOrFallback(handle.exitCode);
    } finally {
      await _forget(handle);
    }
    final stdout = await _textOrFallback(stdoutFuture);
    final stderr = await _textOrFallback(stderrFuture);
    return ManagedProcessResult(
      id: spec.id,
      pid: handle.pid,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      timedOut: timedOut,
    );
  }

  /// Stops one active process handle if it is still running.
  Future<void> stop(ManagedProcessHandle handle) async {
    final entry = _active[handle];
    if (entry == null) {
      return;
    }
    if (await _hasExited(handle.exitCode) != null) {
      await _forget(handle);
      return;
    }
    try {
      await _signalActiveProcess(entry, ManagedProcessSignal.term);
      if (!await _waitForProcessToStop(handle, const Duration(seconds: 3))) {
        await _signalActiveProcess(entry, ManagedProcessSignal.kill);
        if (!await _waitForProcessToStop(handle, const Duration(seconds: 2))) {
          await _writeLogLine(
            handle.spec.name,
            'process ${handle.pid} did not exit after SIGKILL',
          );
        }
      }
    } finally {
      await _forget(handle);
    }
  }

  /// Stops all active processes in one logical scope.
  Future<void> stopScope(
    String scope, {
    void Function(String message)? onStatus,
  }) async {
    final namespace = _namespace(scope);
    final handles = _startOrder
        .where((handle) => _namespace(handle.spec.scope) == namespace)
        .toList()
        .reversed;
    for (final handle in handles) {
      onStatus?.call('Stopping ${handle.spec.name} (pid ${handle.pid})');
      await stop(handle);
    }
  }

  /// Stops one persisted process record by id when it is safe to verify.
  Future<void> stopPersistedProcess({
    required String namespace,
    required String id,
    required String name,
    FutureOr<void> Function(String message)? onLog,
  }) async {
    for (final path in _pidRecordCandidatePaths(namespace, id)) {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      final record = await _readProcessRecord(path);
      if (record == null) {
        await _removePidFile(path);
        continue;
      }
      await _stopPersistedRecord(record, path, name, onLog: onLog);
    }
  }

  /// Stops every persisted process record in one namespace.
  Future<void> stopPersistedProcesses({
    required String namespace,
    void Function(String message)? onStatus,
  }) async {
    final paths = await _pidRecordPathsForNamespace(namespace);
    for (final path in paths) {
      final record = await _readProcessRecord(path);
      if (record == null) {
        await _removePidFile(path);
        continue;
      }
      onStatus?.call('Stopping ${record.name} (pid ${record.pid})');
      await _stopPersistedRecord(record, path, record.name);
    }
  }

  /// Signals verified Agent Awesome listeners on a local TCP port.
  Future<bool> signalVerifiedLocalPortListeners({
    required String name,
    required int port,
    required ManagedProcessSignal signal,
    FutureOr<void> Function(String message)? onLog,
  }) async {
    if (port <= 0) {
      throw StateError('Cannot inspect an empty local port for $name.');
    }
    if (Platform.isWindows) {
      throw StateError('Cannot restart an unowned $name listener on Windows.');
    }
    final pids = await _localPortListenerPids(
      name: name,
      port: port,
      onLog: onLog,
    );
    var signaled = false;
    for (final pid in pids) {
      final commandLine = await _processCommandLine(pid);
      final executable = commandLine.isEmpty ? '' : commandLine.first;
      if (!isWorkspaceManagedExecutablePath(
        executable: executable,
        workspaceRoot: workspaceRoot,
      )) {
        await _emitLog(
          onLog,
          'leaving unowned listener pid $pid on port $port untouched',
        );
        continue;
      }
      final sent = await _signalVerifiedPid(
        name: name,
        pid: pid,
        executable: executable,
        ownsProcessGroup: await _isProcessGroupLeader(pid),
        signal: signal,
        onLog: onLog,
      );
      signaled = signaled || sent;
    }
    return signaled;
  }

  /// Stops all active processes in reverse start order exactly once.
  Future<void> close({void Function(String message)? onStatus}) {
    return _closeFuture ??= () async {
      beginClosing();
      final handles = _startOrder
          .where((handle) => handle.spec.killOnSupervisorClose)
          .toList()
          .reversed;
      for (final handle in handles) {
        onStatus?.call('Stopping ${handle.spec.name} (pid ${handle.pid})');
        await stop(handle);
      }
      await _logWrite;
    }();
  }

  /// Throws when callers try to launch after shutdown begins.
  void _throwIfClosing() {
    if (_closing) {
      throw StateError('Process supervisor is closing');
    }
  }

  /// Creates directories needed before launching a process.
  Future<void> _prepareLaunchFilesystem(ManagedProcessSpec spec) async {
    await Directory(logDirectory).create(recursive: true);
    final outputLogPath = spec.outputLogPath?.trim() ?? '';
    if (outputLogPath.isNotEmpty) {
      await File(outputLogPath).parent.create(recursive: true);
    }
  }

  /// Builds the concrete dart:io launch command for a spec.
  Future<ManagedProcessLaunchPlan> _launchPlanFor(
    ManagedProcessSpec spec,
  ) async {
    final processGroup =
        spec.shutdownMode == ManagedProcessShutdownMode.processGroup &&
        await _canStartProcessGroup();
    return buildManagedProcessLaunchPlan(
      executable: spec.executable,
      arguments: spec.arguments,
      outputLogPath: spec.outputLogPath ?? '',
      canStartProcessGroup: processGroup,
      isWindows: Platform.isWindows,
    );
  }

  /// Writes a pid record for long-running managed services.
  Future<void> _writePidRecordIfNeeded(_ManagedProcessEntry entry) async {
    final path = entry.pidFilePath;
    if (path == null) {
      return;
    }
    final record = _ManagedProcessRecord(
      id: entry.handle.spec.id,
      name: entry.handle.spec.name,
      pid: entry.handle.pid,
      executable: entry.expectedExecutable,
      ownsProcessGroup: entry.handle.ownsProcessGroup,
      kind: entry.handle.spec.kind.name,
      scope: _namespace(entry.handle.spec.scope),
      startedAt: entry.startedAt,
    );
    const encoder = JsonEncoder.withIndent('  ');
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('${encoder.convert(record.toJson())}\n');
  }

  /// Removes active bookkeeping and pid records for an exited process.
  Future<void> _forget(ManagedProcessHandle handle) async {
    final entry = _active.remove(handle);
    _startOrder.remove(handle);
    final pidFilePath = entry?.pidFilePath;
    if (pidFilePath != null) {
      await _removePidFile(pidFilePath);
    }
  }

  /// Stops a persisted pid record after verifying executable ownership.
  Future<void> _stopPersistedRecord(
    _ManagedProcessRecord record,
    String path,
    String logName, {
    FutureOr<void> Function(String message)? onLog,
  }) async {
    await _emitLog(onLog, 'stopping registered process ${record.pid}');
    final termSent = await _signalVerifiedPid(
      name: logName,
      pid: record.pid,
      executable: record.executable,
      ownsProcessGroup: record.ownsProcessGroup,
      signal: ManagedProcessSignal.term,
      onLog: onLog,
    );
    if (termSent) {
      await _waitForPidToReleaseExecutable(
        pid: record.pid,
        executable: record.executable,
        timeout: const Duration(seconds: 3),
      );
    }
    if (await _pidMatchesExecutable(record.pid, record.executable)) {
      await _signalVerifiedPid(
        name: logName,
        pid: record.pid,
        executable: record.executable,
        ownsProcessGroup: record.ownsProcessGroup,
        signal: ManagedProcessSignal.kill,
        onLog: onLog,
      );
      await _waitForPidToReleaseExecutable(
        pid: record.pid,
        executable: record.executable,
        timeout: const Duration(seconds: 2),
      );
    }
    await _removePidFile(path);
  }

  /// Sends a signal to an active process or process group.
  Future<void> _signalActiveProcess(
    _ManagedProcessEntry entry,
    ManagedProcessSignal signal,
  ) async {
    final handle = entry.handle;
    if (Platform.isWindows) {
      final sent = entry.process.kill(_processSignal(signal));
      await _writeLogLine(
        handle.spec.name,
        'sent ${signal.name} to pid ${handle.pid}: $sent',
      );
      return;
    }
    if (handle.ownsProcessGroup &&
        await _canSignalProcessGroup(
          name: handle.spec.name,
          groupLeaderPid: handle.pid,
          executable: entry.expectedExecutable,
          onLog: (message) => _writeLogLine(handle.spec.name, message),
        )) {
      await _sendProcessGroupSignal(
        name: handle.spec.name,
        pid: handle.pid,
        signal: signal,
        onLog: (message) => _writeLogLine(handle.spec.name, message),
      );
      return;
    }
    final sent = entry.process.kill(_processSignal(signal));
    await _writeLogLine(
      handle.spec.name,
      'sent ${signal.name} to pid ${handle.pid}: $sent',
    );
  }

  /// Sends a signal only when a pid still matches the expected executable.
  Future<bool> _signalVerifiedPid({
    required String name,
    required int pid,
    required String executable,
    required bool ownsProcessGroup,
    required ManagedProcessSignal signal,
    FutureOr<void> Function(String message)? onLog,
  }) async {
    if (pid <= 1) {
      await _emitLog(onLog, 'refusing to signal unsafe pid $pid');
      return false;
    }
    if (Platform.isWindows) {
      await _emitLog(
        onLog,
        'cannot verify stale registered pid $pid on Windows',
      );
      return false;
    }
    if (ownsProcessGroup &&
        await _canSignalProcessGroup(
          name: name,
          groupLeaderPid: pid,
          executable: executable,
          onLog: onLog,
        )) {
      return _sendProcessGroupSignal(
        name: name,
        pid: pid,
        signal: signal,
        onLog: onLog,
      );
    }
    if (!await _pidMatchesExecutable(pid, executable)) {
      await _emitLog(
        onLog,
        'pid $pid no longer matches managed executable $executable',
      );
      return false;
    }
    final signalName = _processSignalName(signal);
    final sent = Process.killPid(pid, _processSignal(signal));
    await _emitLog(onLog, 'sent SIG$signalName to pid $pid: $sent');
    return sent;
  }

  /// Reports whether a negative process-group signal is safe to send.
  Future<bool> _canSignalProcessGroup({
    required String name,
    required int groupLeaderPid,
    required String executable,
    FutureOr<void> Function(String message)? onLog,
  }) async {
    if (!Platform.isLinux || groupLeaderPid <= 1) {
      return false;
    }
    final target = await _linuxProcessIds(groupLeaderPid);
    if (target == null || target.processGroupId != groupLeaderPid) {
      await _emitLog(
        onLog,
        'refusing process-group signal for $name because pid '
        '$groupLeaderPid is not a process-group leader',
      );
      return false;
    }
    final current = await _linuxProcessIds(_currentProcessId());
    if (current != null &&
        (target.processGroupId == current.processGroupId ||
            target.sessionId == current.sessionId)) {
      await _emitLog(
        onLog,
        'refusing process-group signal for $name because group '
        '${target.processGroupId} is not isolated from current session',
      );
      return false;
    }
    if (!await _pidMatchesExecutable(groupLeaderPid, executable)) {
      await _emitLog(
        onLog,
        'pid $groupLeaderPid no longer matches managed executable $executable',
      );
      return false;
    }
    return true;
  }

  /// Sends a POSIX signal to a previously verified process group.
  Future<bool> _sendProcessGroupSignal({
    required String name,
    required int pid,
    required ManagedProcessSignal signal,
    FutureOr<void> Function(String message)? onLog,
  }) async {
    final signalName = _processSignalName(signal);
    final result = await Process.run('kill', <String>[
      '-$signalName',
      '--',
      '-$pid',
    ]);
    await _emitLog(
      onLog,
      'sent SIG$signalName to process group $pid exit ${result.exitCode}',
    );
    return result.exitCode == 0;
  }

  /// Drains long-running process pipes so exitCode can complete on shutdown.
  void _drainServiceOutput(Process process) {
    unawaited(process.stdout.drain<void>().catchError((Object _) {}));
    unawaited(process.stderr.drain<void>().catchError((Object _) {}));
  }

  /// Reports whether this host can launch a reliable process group.
  Future<bool> _canStartProcessGroup() async {
    if (!Platform.isLinux) {
      return false;
    }
    final cached = _setsidAvailable;
    if (cached != null) {
      return cached;
    }
    try {
      final result = await Process.run('which', const <String>[
        'setsid',
      ]).timeout(const Duration(seconds: 1));
      _setsidAvailable = result.exitCode == 0;
    } catch (_) {
      _setsidAvailable = false;
    }
    return _setsidAvailable!;
  }

  /// Reports whether the pid is currently a process-group leader.
  Future<bool> _isProcessGroupLeader(int pid) async {
    if (!Platform.isLinux) {
      return false;
    }
    final ids = await _linuxProcessIds(pid);
    return ids?.processGroupId == pid;
  }

  /// Reads Linux process ids from procfs.
  Future<_LinuxProcessIds?> _linuxProcessIds(int pid) async {
    try {
      return _parseLinuxProcessIds(
        await File('/proc/$pid/stat').readAsString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns true while a pid still belongs to the expected executable path.
  Future<bool> _pidMatchesExecutable(int pid, String executable) async {
    if (Platform.isWindows || executable.isEmpty) {
      return false;
    }
    final commandLine = await _processCommandLine(pid);
    if (commandLine.isEmpty) {
      return false;
    }
    if (_samePath(commandLine.first, executable)) {
      return true;
    }
    return _isExpectedLaunchWrapper(commandLine, executable);
  }

  /// Waits until a pid exits or no longer belongs to the expected executable.
  Future<bool> _waitForPidToReleaseExecutable({
    required int pid,
    required String executable,
    required Duration timeout,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (!await _pidMatchesExecutable(pid, executable)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return !await _pidMatchesExecutable(pid, executable);
  }

  /// Reads a Linux command line from procfs for ownership verification.
  Future<List<String>> _processCommandLine(int pid) async {
    if (Platform.isWindows) {
      return const <String>[];
    }
    try {
      return splitProcessCommandLineBytes(
        await File('/proc/$pid/cmdline').readAsBytes(),
      );
    } catch (_) {
      return const <String>[];
    }
  }

  /// Finds process ids currently listening on a local TCP port.
  Future<List<int>> _localPortListenerPids({
    required String name,
    required int port,
    FutureOr<void> Function(String message)? onLog,
  }) async {
    try {
      final result = await Process.run('fuser', <String>['$port/tcp']);
      await _emitLog(
        onLog,
        'fuser port $port exit ${result.exitCode}: ${result.stderr}',
      );
      if (result.exitCode != 0) {
        return _procNetLocalPortListenerPids(
          name: name,
          port: port,
          onLog: onLog,
        );
      }
      final pids = RegExp(r'\d+')
          .allMatches(result.stdout.toString())
          .map((match) => int.parse(match.group(0)!))
          .where((pid) => pid > 1)
          .toSet()
          .toList();
      if (pids.isNotEmpty) {
        return pids;
      }
      return _procNetLocalPortListenerPids(
        name: name,
        port: port,
        onLog: onLog,
      );
    } catch (error) {
      await _emitLog(onLog, 'could not inspect port $port: $error');
      return _procNetLocalPortListenerPids(
        name: name,
        port: port,
        onLog: onLog,
      );
    }
  }

  /// Finds listener pids by matching procfs TCP socket inodes.
  Future<List<int>> _procNetLocalPortListenerPids({
    required String name,
    required int port,
    FutureOr<void> Function(String message)? onLog,
  }) async {
    if (!Platform.isLinux) {
      return const <int>[];
    }
    final inodes = <String>{};
    inodes.addAll(await _listeningSocketInodes('/proc/net/tcp', port));
    inodes.addAll(await _listeningSocketInodes('/proc/net/tcp6', port));
    if (inodes.isEmpty) {
      return const <int>[];
    }
    final pids = <int>{};
    try {
      await for (final entity in Directory('/proc').list(followLinks: false)) {
        final pid = int.tryParse(entity.uri.pathSegments.last);
        if (pid == null || pid <= 1) {
          continue;
        }
        if (await _pidOwnsSocketInode(pid, inodes)) {
          pids.add(pid);
        }
      }
    } catch (error) {
      await _emitLog(onLog, 'procfs port scan failed for $port: $error');
    }
    await _emitLog(
      onLog,
      'procfs port $port listener pids: ${pids.join(', ')}',
    );
    return pids.toList();
  }

  /// Reads listening socket inodes for one TCP port from a procfs table.
  Future<Set<String>> _listeningSocketInodes(String path, int port) async {
    try {
      final lines = await File(path).readAsLines();
      return lines
          .skip(1)
          .map((line) => listeningSocketInodeFromProcNetLine(line, port))
          .whereType<String>()
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  /// Reports whether one pid owns at least one expected socket inode.
  Future<bool> _pidOwnsSocketInode(int pid, Set<String> inodes) async {
    try {
      final fdDirectory = Directory('/proc/$pid/fd');
      await for (final entity in fdDirectory.list(followLinks: false)) {
        if (entity is! Link) {
          continue;
        }
        final target = await entity.target();
        final match = RegExp(r'^socket:\[(\d+)\]$').firstMatch(target);
        if (match != null && inodes.contains(match.group(1))) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  /// Reads a persisted process ownership record when structurally valid.
  Future<_ManagedProcessRecord?> _readProcessRecord(String path) async {
    try {
      final decoded = jsonDecode(await File(path).readAsString());
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final record = _ManagedProcessRecord.fromJson(decoded);
      if (record.id.isEmpty || record.pid <= 1 || record.executable.isEmpty) {
        return null;
      }
      return record;
    } catch (_) {
      return null;
    }
  }

  /// Returns the pid record path for a persisted process spec.
  String? _pidRecordPathForSpec(ManagedProcessSpec spec) {
    if (spec.persistence != ManagedProcessPersistence.pidRecord) {
      return null;
    }
    return _pidRecordPath(_namespace(spec.scope), spec.id);
  }

  /// Returns candidate paths for a pid record including legacy records.
  List<String> _pidRecordCandidatePaths(String namespace, String id) {
    final safe = _safeId(id);
    final effectiveNamespace = _namespace(namespace);
    return <String>[
      '$logDirectory/pids/$effectiveNamespace/$safe.json',
      if (effectiveNamespace == 'local-services')
        '$logDirectory/pids/$safe.json',
    ];
  }

  /// Returns every pid record path for a namespace.
  Future<List<String>> _pidRecordPathsForNamespace(String namespace) async {
    final effectiveNamespace = _namespace(namespace);
    final paths = <String>[];
    final directories = <Directory>[
      Directory('$logDirectory/pids/$effectiveNamespace'),
      if (effectiveNamespace == 'local-services')
        Directory('$logDirectory/pids'),
    ];
    for (final directory in directories) {
      if (!await directory.exists()) {
        continue;
      }
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.json')) {
          paths.add(entity.path);
        }
      }
    }
    paths.sort();
    return paths.toSet().toList();
  }

  /// Returns one generic pid record path.
  String _pidRecordPath(String namespace, String id) {
    return '$logDirectory/pids/${_namespace(namespace)}/${_safeId(id)}.json';
  }

  /// Removes one pid record if it still exists.
  Future<void> _removePidFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Returns the exit code when the process has already stopped.
  Future<int?> _hasExited(Future<int> exitCode) async {
    try {
      return await exitCode.timeout(Duration.zero);
    } on TimeoutException {
      return null;
    }
  }

  /// Waits until Dart exitCode or Linux procfs shows the process is gone.
  Future<bool> _waitForProcessToStop(
    ManagedProcessHandle handle,
    Duration timeout,
  ) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (await _hasExited(handle.exitCode) != null) {
        return true;
      }
      if (!await _pidAppearsAlive(handle.pid)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return await _hasExited(handle.exitCode) != null ||
        !await _pidAppearsAlive(handle.pid);
  }

  /// Reports whether a Linux pid still appears alive to procfs.
  Future<bool> _pidAppearsAlive(int pid) async {
    if (!Platform.isLinux || pid <= 1) {
      return true;
    }
    try {
      final stat = await File('/proc/$pid/stat').readAsString();
      final commandEnd = stat.lastIndexOf(')');
      if (commandEnd != -1 && commandEnd + 2 < stat.length) {
        final state = stat.substring(commandEnd + 2).trim().split(' ').first;
        return state != 'Z';
      }
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Returns an exit code after forced shutdown without hanging forever.
  Future<int> _exitCodeOrFallback(Future<int> exitCode) async {
    try {
      return await exitCode.timeout(const Duration(milliseconds: 100));
    } on TimeoutException {
      return -1;
    }
  }

  /// Returns captured text or an empty fallback when stream collection fails.
  Future<String> _textOrFallback(Future<String> text) async {
    try {
      return await text.timeout(const Duration(seconds: 1));
    } catch (_) {
      return '';
    }
  }

  /// Writes one timestamped supervisor line to the UI log.
  Future<void> _writeLogLine(String name, String line) {
    final timestamp = DateTime.now().toIso8601String();
    final record = '[$timestamp] [process-supervisor:$name] $line\n';
    final path = '$logDirectory/ui.log';
    _logWrite = _logWrite
        .then((_) async {
          await Directory(logDirectory).create(recursive: true);
          await File(
            path,
          ).writeAsString(record, mode: FileMode.append, flush: true);
        })
        .catchError((Object _) {});
    return _logWrite;
  }

  /// Emits a cleanup log through the caller callback and supervisor log.
  Future<void> _emitLog(
    FutureOr<void> Function(String message)? onLog,
    String message,
  ) async {
    await _writeLogLine('cleanup', message);
    if (onLog != null) {
      await Future.sync(() => onLog(message));
    }
  }

  /// Returns a concise shutdown mode for logs.
  String _actualShutdownMode(ManagedProcessSpec spec, bool ownsProcessGroup) {
    if (ownsProcessGroup) {
      return ManagedProcessShutdownMode.processGroup.name;
    }
    if (spec.shutdownMode == ManagedProcessShutdownMode.windowsJob) {
      return ManagedProcessShutdownMode.processOnly.name;
    }
    return ManagedProcessShutdownMode.processOnly.name;
  }
}

/// _ManagedProcessEntry stores private process state for one handle.
class _ManagedProcessEntry {
  /// Creates private state for one active process.
  const _ManagedProcessEntry({
    required this.handle,
    required this.process,
    required this.expectedExecutable,
    required this.pidFilePath,
    required this.startedAt,
  });

  /// Public handle returned to app code.
  final ManagedProcessHandle handle;

  /// dart:io process object kept inside the supervisor boundary.
  final Process process;

  /// Executable path used for stale pid verification.
  final String expectedExecutable;

  /// Optional persisted pid record path.
  final String? pidFilePath;

  /// UTC launch time.
  final DateTime startedAt;
}

/// _ManagedProcessRecord stores persisted ownership of one service process.
class _ManagedProcessRecord {
  /// Creates a persisted process ownership record.
  const _ManagedProcessRecord({
    required this.id,
    required this.name,
    required this.pid,
    required this.executable,
    required this.ownsProcessGroup,
    required this.kind,
    required this.scope,
    required this.startedAt,
  });

  /// Stable process id.
  final String id;

  /// Human-readable process name.
  final String name;

  /// Operating-system process id.
  final int pid;

  /// Expected executable path.
  final String executable;

  /// Whether the pid owns a process group.
  final bool ownsProcessGroup;

  /// Process kind name.
  final String kind;

  /// Logical process namespace.
  final String scope;

  /// UTC launch time.
  final DateTime startedAt;

  /// Decodes a persisted process ownership record.
  factory _ManagedProcessRecord.fromJson(Map<String, dynamic> json) {
    return _ManagedProcessRecord(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      pid: json['pid'] is int
          ? json['pid'] as int
          : int.tryParse(json['pid']?.toString() ?? '') ?? -1,
      executable: json['executable']?.toString() ?? '',
      ownsProcessGroup: json['owns_process_group'] == true,
      kind:
          json['kind']?.toString() ??
          ManagedProcessKind.longRunningService.name,
      scope: json['scope']?.toString() ?? '',
      startedAt:
          DateTime.tryParse(json['started_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  /// Encodes this process ownership record for disk.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'pid': pid,
      'executable': executable,
      'owns_process_group': ownsProcessGroup,
      'kind': kind,
      'scope': scope,
      'started_at': startedAt.toUtc().toIso8601String(),
    };
  }
}

/// _LinuxProcessIds stores process-group and session ids parsed from procfs.
class _LinuxProcessIds {
  /// Creates parsed Linux process identity values.
  const _LinuxProcessIds({
    required this.processGroupId,
    required this.sessionId,
  });

  /// POSIX process group id.
  final int processGroupId;

  /// POSIX session id.
  final int sessionId;
}

/// Builds a durable process command for managed subprocesses.
ManagedProcessLaunchPlan buildManagedProcessLaunchPlan({
  required String executable,
  required List<String> arguments,
  required String outputLogPath,
  required bool canStartProcessGroup,
  required bool isWindows,
}) {
  if (isWindows) {
    return ManagedProcessLaunchPlan(
      executable: executable,
      arguments: arguments,
      ownsProcessGroup: false,
    );
  }
  final logPath = outputLogPath.trim();
  if (logPath.isNotEmpty) {
    final redirectedArguments = _stdioRedirectShellArguments(
      executable: executable,
      arguments: arguments,
      outputLogPath: logPath,
    );
    if (canStartProcessGroup) {
      return ManagedProcessLaunchPlan(
        executable: 'setsid',
        arguments: <String>['sh', ...redirectedArguments],
        ownsProcessGroup: true,
      );
    }
    return ManagedProcessLaunchPlan(
      executable: 'sh',
      arguments: redirectedArguments,
      ownsProcessGroup: false,
    );
  }
  if (canStartProcessGroup) {
    return ManagedProcessLaunchPlan(
      executable: 'setsid',
      arguments: <String>[executable, ...arguments],
      ownsProcessGroup: true,
    );
  }
  return ManagedProcessLaunchPlan(
    executable: executable,
    arguments: arguments,
    ownsProcessGroup: false,
  );
}

/// Reports whether an executable path belongs to UI-built service binaries.
bool isWorkspaceManagedExecutablePath({
  required String executable,
  required String workspaceRoot,
}) {
  if (executable.isEmpty || workspaceRoot.isEmpty) {
    return false;
  }
  final candidate = File(executable).absolute.path;
  final managedRoot = Directory(
    '$workspaceRoot/harness/build/profiles',
  ).absolute.path;
  return candidate.startsWith('$managedRoot${Platform.pathSeparator}');
}

/// Parses the Linux process group id from a procfs stat record.
int? parseLinuxProcessGroupId(String stat) {
  return _parseLinuxProcessIds(stat)?.processGroupId;
}

/// Parses Linux process group and session ids from a procfs stat record.
_LinuxProcessIds? _parseLinuxProcessIds(String stat) {
  final commandEnd = stat.lastIndexOf(')');
  if (commandEnd == -1 || commandEnd + 2 >= stat.length) {
    return null;
  }
  final fields = stat.substring(commandEnd + 2).trim().split(RegExp(r'\s+'));
  if (fields.length < 4) {
    return null;
  }
  final processGroupId = int.tryParse(fields[2]);
  final sessionId = int.tryParse(fields[3]);
  if (processGroupId == null || sessionId == null) {
    return null;
  }
  return _LinuxProcessIds(processGroupId: processGroupId, sessionId: sessionId);
}

/// Parses a listening socket inode from one procfs TCP table line.
String? listeningSocketInodeFromProcNetLine(String line, int port) {
  final fields = line.trim().split(RegExp(r'\s+'));
  if (fields.length < 10 || fields[3] != '0A') {
    return null;
  }
  final local = fields[1];
  final separator = local.lastIndexOf(':');
  if (separator == -1 || separator + 1 >= local.length) {
    return null;
  }
  final localPort = int.tryParse(local.substring(separator + 1), radix: 16);
  if (localPort != port) {
    return null;
  }
  final inode = fields[9];
  return inode == '0' ? null : inode;
}

/// Splits procfs cmdline bytes into command-line arguments.
List<String> splitProcessCommandLineBytes(List<int> bytes) {
  if (bytes.isEmpty) {
    return const <String>[];
  }
  return utf8
      .decode(bytes, allowMalformed: true)
      .split('\x00')
      .where((part) => part.isNotEmpty)
      .toList();
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

/// Converts supervisor signal names into dart:io signals.
ProcessSignal _processSignal(ManagedProcessSignal signal) {
  return signal == ManagedProcessSignal.kill
      ? ProcessSignal.sigkill
      : ProcessSignal.sigterm;
}

/// Converts supervisor signal names into POSIX signal names.
String _processSignalName(ManagedProcessSignal signal) {
  return signal == ManagedProcessSignal.kill ? 'KILL' : 'TERM';
}

/// Returns the current Dart process id.
int _currentProcessId() {
  return pid;
}

/// Compares two executable paths after normalizing them to absolute paths.
bool _samePath(String left, String right) {
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  return File(left).absolute.path == File(right).absolute.path;
}

/// Reports whether a command line is the short-lived launch wrapper.
bool _isExpectedLaunchWrapper(List<String> commandLine, String executable) {
  if (commandLine.isEmpty) {
    return false;
  }
  final launcher = _basename(commandLine.first);
  if (launcher != 'setsid' && launcher != 'sh') {
    return false;
  }
  return commandLine.any((argument) => _samePath(argument, executable));
}

/// Returns a stable namespace string for pid records and scope matching.
String _namespace(String scope) {
  final safe = _safeId(scope);
  return safe.isEmpty ? 'default' : safe;
}

/// Returns a filesystem-safe id segment.
String _safeId(String value) {
  final safe = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return safe.isEmpty ? 'process' : safe;
}

/// Returns the basename for a platform path.
String _basename(String path) {
  if (path.isEmpty) {
    return '';
  }
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash == -1 ? normalized : normalized.substring(slash + 1);
}
