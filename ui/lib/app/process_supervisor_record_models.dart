/// Private persisted-process record models.
part of 'process_supervisor.dart';

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
