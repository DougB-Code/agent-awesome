/// Launch, run, shutdown, and signaling workflows for ProcessSupervisor.
part of 'process_supervisor.dart';

extension ProcessSupervisorLifecycle on ProcessSupervisor {
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
}
