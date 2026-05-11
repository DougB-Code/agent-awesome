/// Data models and enums for supervised subprocesses.
part of 'process_supervisor.dart';

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
