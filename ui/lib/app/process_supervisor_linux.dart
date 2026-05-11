/// Linux procfs helpers for supervised process verification.
part of 'process_supervisor.dart';

extension ProcessSupervisorLinux on ProcessSupervisor {
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
}
