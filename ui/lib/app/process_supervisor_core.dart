/// Core ProcessSupervisor state and shutdown gate.
part of 'process_supervisor.dart';

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
}
