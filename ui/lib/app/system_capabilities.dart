/// Reads local system capabilities used by first-run model setup.
library;

import 'dart:io';

import '../domain/system_capabilities.dart';
import 'process_supervisor.dart';
import 'runtime_profile.dart';

/// SystemCapabilityReader loads system capability data for the setup UI.
class SystemCapabilityReader {
  /// Creates a reader for the default app data directory.
  const SystemCapabilityReader({this.dataDirectoryPath, this.commandRunner});

  /// Directory used to calculate available model storage.
  final String? dataDirectoryPath;

  /// Command runner used for bounded system probes.
  final CommandRunner? commandRunner;

  /// Reads CPU, memory, and app-data disk space.
  Future<SystemCapabilitySnapshot> read() async {
    return SystemCapabilitySnapshot(
      cpuThreads: Platform.numberOfProcessors,
      memoryBytes: await _readMemoryBytes(),
      diskBytes: await _readDiskBytes(
        dataDirectoryPath ?? agentAwesomeDataDirectoryPath(),
      ),
    );
  }

  Future<int?> _readMemoryBytes() async {
    if (Platform.isLinux) {
      return _readLinuxMemoryBytes();
    }
    if (Platform.isMacOS) {
      return _readSysctlInt('hw.memsize');
    }
    return null;
  }

  Future<int?> _readLinuxMemoryBytes() async {
    final file = File('/proc/meminfo');
    if (!await file.exists()) {
      return null;
    }
    final content = await file.readAsString();
    for (final line in content.split('\n')) {
      if (!line.startsWith('MemTotal:')) {
        continue;
      }
      final match = RegExp(r'MemTotal:\s+(\d+)\s+kB').firstMatch(line);
      if (match == null) {
        return null;
      }
      return int.parse(match.group(1)!) * 1024;
    }
    return null;
  }

  Future<int?> _readDiskBytes(String path) async {
    if (Platform.isWindows) {
      return null;
    }
    final directory = Directory(path);
    await directory.create(recursive: true);
    final result = await _runProbe('df', <String>['-Pk', directory.path]);
    if (result == null) {
      return null;
    }
    if (result.exitCode != 0) {
      return null;
    }
    final lines = result.stdout.toString().trim().split('\n');
    if (lines.length < 2) {
      return null;
    }
    final columns = lines.last.trim().split(RegExp(r'\s+'));
    if (columns.length < 4) {
      return null;
    }
    final availableKiB = int.tryParse(columns[3]);
    if (availableKiB == null) {
      return null;
    }
    return availableKiB * 1024;
  }

  Future<int?> _readSysctlInt(String key) async {
    final result = await _runProbe('sysctl', <String>['-n', key]);
    if (result == null) {
      return null;
    }
    if (result.exitCode != 0) {
      return null;
    }
    return int.tryParse(result.stdout.toString().trim());
  }

  /// Runs one optional system probe through the command runner.
  Future<ManagedProcessResult?> _runProbe(
    String executable,
    List<String> arguments,
  ) async {
    final runner = commandRunner;
    if (runner == null) {
      return null;
    }
    try {
      return await runner.run(
        executable,
        arguments,
        timeout: const Duration(seconds: 5),
        scope: 'system-capabilities',
        kind: ManagedProcessKind.systemProbe,
      );
    } on Object {
      return null;
    }
  }
}
