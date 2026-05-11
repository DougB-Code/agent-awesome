/// Pid-record and supervisor logging helpers.
part of 'process_supervisor.dart';

extension ProcessSupervisorRecords on ProcessSupervisor {
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
