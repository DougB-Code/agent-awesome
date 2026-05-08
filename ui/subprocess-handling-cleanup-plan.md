# Subprocess Handling Cleanup Implementation Plan

## Files to change

- `lib/app/process_supervisor.dart` - new shared subprocess supervisor.
- `lib/app/app_controller.dart` - inject and close the shared supervisor, add shutdown guards.
- `lib/app/aurora_app.dart` - keep the existing signal/window-close path, but ensure it drives one shutdown coordinator.
- `lib/app/local_services.dart` - remove embedded process lifecycle logic and delegate all launches/kills to `ProcessSupervisor`.
- `lib/app/local_model_runtime.dart` - run LiteRT validation and inference through `ProcessSupervisor`; cancel in-flight inference on close.
- `lib/app/credential_store.dart` - run keyring subprocesses through the shared command runner/supervisor instead of direct `Process.run`/`Process.start`.
- `lib/app/system_capabilities.dart` - run `df`/`sysctl` probes through the shared command runner/supervisor.
- `test/process_supervisor_test.dart` - new supervisor contract tests.
- `test/app_controller_shutdown_test.dart` - extend shutdown race coverage.
- `test/local_services_test.dart` - update service tests to use the supervisor abstraction.
- `test/local_model_runtime_test.dart` - add in-flight inference shutdown coverage.
- Optional, only if Windows support is required now: `windows/runner/process_job.*` or a small native plugin/helper for Windows Job Objects.

## Target pattern

Use these patterns deliberately:

- **Supervisor Pattern**: one app-wide object owns all app-started subprocesses.
- **Composite Disposable / Resource Registry**: shutdown closes every registered resource in bounded order.
- **Adapter Pattern**: app code depends on `ProcessSupervisor` or a small `CommandRunner` interface, not directly on `dart:io` process statics.

The important invariant:

> Production code outside `lib/app/process_supervisor.dart` must not call `Process.run`, `Process.runSync`, `Process.start`, or `Process.killPid`.

`ProcessSignal` handling may remain in `lib/app/aurora_app.dart` because app-exit events are not subprocess launches.

## Current subprocess launch sites to clean up

| File | Current behavior | Required replacement |
|---|---|---|
| `lib/app/local_services.dart` | Starts service processes directly with `Process.start`. | Use `ProcessSupervisor.start()` with process-group shutdown and persistent PID records. |
| `lib/app/local_services.dart` | Runs `go build` with `Process.run`. | Use `ProcessSupervisor.run()` with timeout, output capture, and kill-on-shutdown. |
| `lib/app/local_services.dart` | Runs `fuser`, `kill`, and `which` directly. | Move these helpers into `ProcessSupervisor` or a private supervisor-owned platform helper. |
| `lib/app/local_services.dart` | Uses `Process.killPid` directly. | Move PID/group signaling into `ProcessSupervisor`. |
| `lib/app/local_model_runtime.dart` | Runs `litert-lm --help` with `Process.run`. | Use `ProcessSupervisor.run()` with a 10 second timeout. |
| `lib/app/local_model_runtime.dart` | Runs LiteRT inference with `Process.run` and a 10 minute timeout. | Use `ProcessSupervisor.run()` so in-flight inference can be killed when the UI closes. |
| `lib/app/credential_store.dart` | Uses direct `Process.run` and `Process.start` for keyring commands. | Use a `CommandRunner` backed by `ProcessSupervisor.run()`; keep test injection. |
| `lib/app/system_capabilities.dart` | Uses direct `Process.run` for `df` and `sysctl`. | Use a `CommandRunner` backed by `ProcessSupervisor.run()` with short probe timeouts. |

## Step 1: Add `lib/app/process_supervisor.dart`

Create a single subprocess infrastructure file. This is the only production file allowed to touch `dart:io` process launch/kill APIs.

### Public API

Add these types:

```dart
enum ManagedProcessKind {
  longRunningService,
  oneShotCommand,
  requestScopedInference,
  keyringCommand,
  systemProbe,
}

enum ManagedProcessShutdownMode {
  processOnly,
  processGroup,
  windowsJob,
}

enum ManagedProcessPersistence {
  none,
  pidRecord,
}
```

Add a spec object:

```dart
class ManagedProcessSpec {
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

  final String id;
  final String name;
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final ManagedProcessKind kind;
  final ManagedProcessShutdownMode shutdownMode;
  final ManagedProcessPersistence persistence;
  final Duration? timeout;
  final String? stdinText;
  final String? outputLogPath;
  final String? expectedExecutable;
  final String scope;
  final bool killOnSupervisorClose;
}
```

Add result and handle objects:

```dart
class ManagedProcessResult {
  const ManagedProcessResult({
    required this.id,
    required this.pid,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
  });

  final String id;
  final int pid;
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
}

class ManagedProcessHandle {
  ManagedProcessHandle._({
    required this.spec,
    required this.pid,
    required this.exitCode,
    required this.ownsProcessGroup,
  });

  final ManagedProcessSpec spec;
  final int pid;
  final Future<int> exitCode;
  final bool ownsProcessGroup;
}
```

Add the supervisor:

```dart
class ProcessSupervisor {
  ProcessSupervisor({
    required this.logDirectory,
    required this.workspaceRoot,
  });

  final String logDirectory;
  final String workspaceRoot;

  bool get isClosing;

  void beginClosing();

  Future<ManagedProcessHandle> start(ManagedProcessSpec spec);

  Future<ManagedProcessResult> run(ManagedProcessSpec spec);

  Future<void> stop(ManagedProcessHandle handle);

  Future<void> stopScope(String scope, {void Function(String message)? onStatus});

  Future<void> stopPersistedProcesses({
    required String namespace,
    void Function(String message)? onStatus,
  });

  Future<void> close({void Function(String message)? onStatus});
}
```

### Supervisor behavior

Implement these rules:

1. `beginClosing()` sets `_closing = true`. After this, `start()` and `run()` throw `StateError('Process supervisor is closing')` before launching anything.
2. `start()` must register the process handle immediately after `Process.start` returns and before any caller can lose the handle.
3. `start()` must check `_closing` again after launch. If shutdown started during launch, it must terminate the new process before throwing.
4. `run()` must be implemented using `start()`, not `Process.run`, so every one-shot command is killable.
5. `run()` must write `stdinText` when present, close stdin, collect stdout/stderr, enforce `timeout`, and kill the process or group on timeout.
6. `close()` must call `beginClosing()`, then stop active handles in reverse start order.
7. Long-running app-owned services must use PID records. One-shot commands and inference requests should not persist PID records.
8. Process output capture must never block process exit. Capture stdout and stderr concurrently.
9. PID records must include the expected executable path. Stale-record cleanup must refuse to signal a PID unless it still matches that executable.
10. Port-based cleanup is allowed only as a fallback after process-handle/PID-record cleanup.

### PID record format

Replace the service-specific record with a generic record:

```json
{
  "id": "memory",
  "name": "Memory MCP",
  "pid": 12345,
  "executable": ".../harness/build/profiles/default/bin/memory",
  "owns_process_group": true,
  "kind": "longRunningService",
  "scope": "local-services",
  "started_at": "2026-05-08T12:00:00.000Z"
}
```

Store records under:

```text
${logDirectory}/pids/<namespace>/<safe-id>.json
```

For existing compatibility, `local_services.dart` can keep using `${config.serviceLogDirectory}/pids` during the first pass, but the supervisor should own read/write/delete logic.

### Process-group strategy

Move the existing `setsid` launch behavior into `ProcessSupervisor`.

Immediate implementation:

- Linux: use `setsid` when available, then signal `-pid` after verifying the PID is still the process-group leader.
- macOS: do not claim reliable tree kill unless a real process-group/native helper is added. If `setsid` is unavailable, fall back to root-process kill and log that process-tree cleanup is not guaranteed.
- Windows: direct `Process.kill()` only kills the root process. If Windows support matters now, add a Job Object helper and use `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`.

Do not hide platform limitations. The supervisor should log which shutdown mode was actually used for each process.

## Step 2: Change `lib/app/app_controller.dart`

### Add one shared supervisor dependency

The controller must create or receive exactly one `ProcessSupervisor` and pass that same object to every component that launches commands.

Recommended constructor shape:

```dart
factory AuroraAppController({
  required AppConfig config,
  ProcessSupervisor? processSupervisor,
  AssistantClient? assistantClient,
  MemoryClient? memoryClient,
  TasksClient? tasksClient,
  LocalServiceSupervisor? localServices,
  LocalModelRuntime? localModels,
  ConfigFileStore? configFiles,
  AuroraAppSettingsStore? appSettingsStore,
  ChatHistoryStore? chatHistoryStore,
  CredentialStore? credentialStore,
  ChatTitleClient? titleClient,
  ScreenCommandPlanner? screenCommandPlanner,
  AppLogger? logger,
}) {
  final effectiveLogger = logger ?? AppLogger(directory: config.serviceLogDirectory);
  final effectiveProcessSupervisor = processSupervisor ?? ProcessSupervisor(
    logDirectory: config.serviceLogDirectory,
    workspaceRoot: config.workspaceRoot,
  );

  return AuroraAppController._(
    config: config,
    logger: effectiveLogger,
    processSupervisor: effectiveProcessSupervisor,
    assistantClient: assistantClient,
    memoryClient: memoryClient,
    tasksClient: tasksClient,
    localServices: localServices ?? LocalServiceSupervisor(
      config: config,
      processSupervisor: effectiveProcessSupervisor,
    ),
    localModels: localModels ?? LiteRtLocalModelRuntime(
      config: config,
      processSupervisor: effectiveProcessSupervisor,
    ),
    configFiles: configFiles ?? const ConfigFileStore(),
    appSettingsStore: appSettingsStore ?? const AuroraAppSettingsStore(),
    chatHistoryStore: chatHistoryStore ?? const ChatHistoryStore(),
    credentialStore: credentialStore ?? CredentialStore(
      commandRunner: ProcessSupervisorCommandRunner(effectiveProcessSupervisor),
    ),
    titleClient: titleClient,
    screenCommandPlanner: screenCommandPlanner,
  );
}
```

Then move the existing initializer-list logic into `AuroraAppController._(...)`. This avoids accidentally constructing separate supervisors for services, models, credentials, and probes.

### Add shutdown state

Add fields:

```dart
final ProcessSupervisor processSupervisor;
bool _closing = false;
Future<void>? _closeFuture;
```

Add helper:

```dart
void _throwIfClosing() {
  if (_closing || processSupervisor.isClosing) {
    throw StateError('Aurora runtime is shutting down');
  }
}
```

Use this guard before every path that can start local services or commands:

- `initialize()` / `_initialize()` before local services start.
- `_startConfiguredLocalModelRuntime()` before checking/installing/starting local model runtime.
- `_ensureChatRuntimeReady()` before service restart.
- `configureOnboardingLocalModel()` before resolving or validating `litert-lm`.
- Any future method that launches app-owned subprocesses.

### Replace `close()` with an idempotent shutdown coordinator

Use this behavior:

```dart
Future<void> close({void Function(String message)? onStatus}) {
  return _closeFuture ??= () async {
    _closing = true;
    processSupervisor.beginClosing();

    onStatus?.call('Closing service clients');
    closeClients();

    onStatus?.call('Stopping local model runtime');
    await _closeLocalModels();

    onStatus?.call('Stopping managed service processes');
    await _closeLocalServices(onStatus: onStatus);

    onStatus?.call('Stopping remaining subprocesses');
    await processSupervisor.close(onStatus: onStatus);

    onStatus?.call('Managed runtime stopped');
  }();
}
```

Reason: setting `_closing` and `processSupervisor.beginClosing()` at the very start prevents a race where `initialize()` or `_ensureChatRuntimeReady()` starts a process while close is already in progress.

## Step 3: Keep `lib/app/aurora_app.dart` as the app-exit entry point

The existing structure is the right shape: Ctrl-C and window-close both call controller shutdown. Keep that centralization.

Required tweaks:

1. `_requestAppExit()` should continue to return `AppExitResponse.cancel` while shutdown is running, then call `ServicesBinding.instance.exitApplication(AppExitType.required)` from `_closeForExit()`.
2. `_handleProcessSignal()` should not call `exit()` until `controller.close()` completes.
3. `dispose()` may keep `unawaited(_closeForExit(requestPlatformExit: false))` as a fallback, but do not rely on `dispose()` as the primary cleanup path.
4. All app-exit paths must use the same `_closeFuture`, so Ctrl-C plus window close cannot run shutdown twice.

No subprocess-specific APIs should be added to this file beyond `ProcessSignal` subscriptions.

## Step 4: Refactor `lib/app/local_services.dart`

### Keep in this file

Keep service topology and status concerns here:

- `ServiceProcessStatus`
- Runtime-profile interpretation
- Health checks
- Status messages
- Local endpoint fallback cleanup requests
- Service-specific log messages

### Move out of this file

Move or delete these from `local_services.dart`:

- `ManagedServiceProcess`
- `ServiceProcessRecord`
- `ServiceProcessLaunchPlan`
- `buildServiceProcessLaunchPlan()` if it exists in this file
- `_writeProcessRecord()`
- `_readProcessRecord()`
- `_removePidFile()`
- `_terminateProcess()`
- `_signalManagedProcess()`
- `_signalVerifiedPid()`
- `_pidMatchesExecutable()`
- `_waitForPidToReleaseExecutable()`
- `_canStartProcessGroup()`
- `_isProcessGroupLeader()`
- direct `Process.run`, `Process.start`, and `Process.killPid` calls

Those responsibilities belong to `ProcessSupervisor`.

### Constructor change

Change the constructor to require the supervisor:

```dart
LocalServiceSupervisor({
  required this.config,
  required ProcessSupervisor processSupervisor,
  http.Client? httpClient,
}) : _processSupervisor = processSupervisor,
     _http = httpClient ?? http.Client();
```

Add:

```dart
final ProcessSupervisor _processSupervisor;
final Map<String, ManagedProcessHandle> _started = <String, ManagedProcessHandle>{};
```

### `_buildBinary()` replacement behavior

Replace `Process.run('go', ...)` with:

```dart
final result = await _processSupervisor.run(
  ManagedProcessSpec(
    id: 'go-build-${profile.id}-$name',
    name: 'go build $name',
    executable: 'go',
    arguments: buildGoBuildArguments(
      outputPath: executable,
      packagePath: packagePath,
    ),
    workingDirectory: workingDirectory,
    environment: environment,
    kind: ManagedProcessKind.oneShotCommand,
    shutdownMode: ManagedProcessShutdownMode.processGroup,
    persistence: ManagedProcessPersistence.none,
    timeout: const Duration(minutes: 5),
    scope: 'local-services',
  ),
);
```

Then log `result.stdout`, `result.stderr`, and `result.exitCode` exactly as the existing function does.

### `_startProcess()` replacement behavior

Change `_startProcess()` to return `ManagedProcessHandle`.

Build the binary first through `_buildBinary()`, then call:

```dart
final handle = await _processSupervisor.start(
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
```

Then:

- Store it in `_started[id]`.
- Emit the existing startup log using `handle.pid` and `handle.ownsProcessGroup`.
- Call `_waitForProcessHealth(...)` with the handle.

### `_waitForProcessHealth()` change

Change the process parameter type from `ManagedServiceProcess` to `ManagedProcessHandle`.

If the process exits early, remove it from `_started`, but PID-record removal should be performed by the supervisor.

### `close()` change

The local service supervisor should stop its own scope first, then run fallback endpoint cleanup:

```dart
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
```

### Endpoint fallback cleanup

Keep local endpoint fallback cleanup, but move direct process commands into the supervisor.

Current local services code safely tries to identify local listeners before signaling them. Keep that safety idea, but the actual operations should become methods such as:

```dart
await _processSupervisor.signalVerifiedLocalPortListeners(
  name: name,
  port: health.port,
  expectedExecutableBasenamePattern: managedServiceExecutablePattern,
  signal: ManagedProcessSignal.term,
);
```

Primary cleanup must be by tracked process handle and PID record. Port cleanup should be a fallback only.

## Step 5: Refactor `lib/app/local_model_runtime.dart`

### Constructor change

Add the supervisor dependency:

```dart
LiteRtLocalModelRuntime({
  required this.config,
  required ProcessSupervisor processSupervisor,
  http.Client? httpClient,
  String? dataDirectory,
  LocalModelExecutableResolver? executableResolver,
}) : _processSupervisor = processSupervisor,
     _http = httpClient ?? http.Client(),
     _dataDirectory = dataDirectory ?? auroraDataDirectoryPath(),
     _executableResolver = executableResolver ?? const LocalModelExecutableResolver();
```

Add:

```dart
final ProcessSupervisor _processSupervisor;
```

### `start()` shutdown guard

Add closed-state checks before and after every awaited boundary that can race with app shutdown:

```dart
if (_closed || _processSupervisor.isClosing) {
  return ServiceProcessStatus(
    name: 'Local model',
    url: config.localModelHealthUrl,
    state: ConnectionStateKind.disconnected,
    message: 'Local model runtime is closed',
  );
}
```

Apply this check:

- At the top of `start()`.
- After `isInstalled(model)`.
- After `_resolveExecutableStatus()`.
- Immediately after `await server.start()`; if shutdown won the race, call `await server.close()` and return disconnected.

### `_validateExecutable()` replacement behavior

Replace direct `Process.run` with:

```dart
final result = await _processSupervisor.run(
  ManagedProcessSpec(
    id: 'litert-help-${DateTime.now().microsecondsSinceEpoch}',
    name: 'LiteRT-LM validation',
    executable: path,
    arguments: const <String>['--help'],
    environment: _localModelProcessEnvironment(path, _dataDirectory),
    kind: ManagedProcessKind.systemProbe,
    shutdownMode: ManagedProcessShutdownMode.processGroup,
    timeout: const Duration(seconds: 10),
    scope: 'local-model',
  ),
);
```

Then preserve the existing success/failure text behavior.

### `_LiteRtOpenAiServer` constructor change

Pass the supervisor into the local OpenAI-compatible server:

```dart
_LiteRtOpenAiServer(
  baseUrl: config.localModelBaseUrl,
  executable: executable.path,
  install: install,
  dataDirectory: _dataDirectory,
  processSupervisor: _processSupervisor,
);
```

Add fields:

```dart
final ProcessSupervisor processSupervisor;
bool _closed = false;
```

### `_LiteRtOpenAiServer.close()` change

Make close reject queued work and kill active inference processes in this scope:

```dart
Future<void> close() async {
  _closed = true;
  await _server?.close(force: true);
  _server = null;
  await processSupervisor.stopScope('local-model');
}
```

### `_queuedInference()` shutdown behavior

Before queueing and immediately before running inference:

```dart
if (_closed || processSupervisor.isClosing) {
  throw StateError('Local model runtime is closed');
}
```

This prevents queued requests from launching new `litert-lm run` processes after shutdown begins.

### `_runInference()` replacement behavior

Replace direct `Process.run` with:

```dart
final result = await processSupervisor.run(
  ManagedProcessSpec(
    id: 'litert-inference-${DateTime.now().microsecondsSinceEpoch}',
    name: 'LiteRT-LM inference',
    executable: executable,
    arguments: <String>[
      '--min_log_level',
      '4',
      'run',
      install.modelPath,
      '--input_prompt_file',
      promptFile.path,
    ],
    environment: _localModelProcessEnvironment(executable, dataDirectory),
    kind: ManagedProcessKind.requestScopedInference,
    shutdownMode: ManagedProcessShutdownMode.processGroup,
    timeout: const Duration(minutes: 10),
    scope: 'local-model',
  ),
);
```

Then preserve existing behavior:

- Throw if `exitCode != 0`.
- Parse assistant text from stdout.
- Throw on empty output.
- Delete the prompt file in `finally`.

## Step 6: Refactor `lib/app/credential_store.dart`

Keep the existing test-injection idea, but stop using direct process APIs by default.

Add a simple command abstraction:

```dart
abstract class CommandRunner {
  Future<ManagedProcessResult> run(
    String executable,
    List<String> arguments, {
    String? stdinText,
    Duration? timeout,
    String scope,
    ManagedProcessKind kind,
  });
}

class ProcessSupervisorCommandRunner implements CommandRunner {
  ProcessSupervisorCommandRunner(this.supervisor);

  final ProcessSupervisor supervisor;

  @override
  Future<ManagedProcessResult> run(
    String executable,
    List<String> arguments, {
    String? stdinText,
    Duration? timeout,
    String scope = 'commands',
    ManagedProcessKind kind = ManagedProcessKind.oneShotCommand,
  }) {
    return supervisor.run(
      ManagedProcessSpec(
        id: '$scope-${DateTime.now().microsecondsSinceEpoch}',
        name: '$scope command',
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
```

Then update `CredentialStore`:

- Add `CommandRunner? commandRunner` to the constructor.
- Keep existing injected test runners if tests rely on them.
- In production, use `commandRunner`.
- `_runCredentialCommand()` should call `commandRunner.run(..., kind: ManagedProcessKind.keyringCommand, timeout: _lookupTimeout)`.
- `_runSecretCommand()` should call the same runner with `stdinText` when needed.

This allows keyring commands to be killed on app shutdown or timeout.

## Step 7: Refactor `lib/app/system_capabilities.dart`

Add a `CommandRunner?` or `ProcessSupervisor?` dependency to `SystemCapabilityReader`.

Replace:

- `Process.run('df', <String>['-Pk', directory.path])`
- `Process.run('sysctl', <String>['-n', key])`

with supervised one-shot probes:

```dart
final result = await commandRunner.run(
  'df',
  <String>['-Pk', directory.path],
  timeout: const Duration(seconds: 5),
  scope: 'system-capabilities',
  kind: ManagedProcessKind.systemProbe,
);
```

and:

```dart
final result = await commandRunner.run(
  'sysctl',
  <String>['-n', key],
  timeout: const Duration(seconds: 5),
  scope: 'system-capabilities',
  kind: ManagedProcessKind.systemProbe,
);
```

Keep the existing parsing logic unchanged.

## Step 8: Add process-supervisor tests

Create `test/process_supervisor_test.dart`.

Required tests:

1. **Rejects launches after shutdown begins**
   - Call `beginClosing()`.
   - Assert `start()` and `run()` throw `StateError`.

2. **Kills a long-running child on close**
   - Launch a script that sleeps.
   - Call `close()`.
   - Assert the process exits.

3. **Kills a timed-out one-shot command**
   - Run a script that sleeps longer than the timeout.
   - Assert `timedOut == true`.
   - Assert no child process remains.

4. **Captures stdout and stderr**
   - Run a script that writes to both streams.
   - Assert both are present in `ManagedProcessResult`.

5. **Kills process group where supported**
   - Launch a shell script that starts a child sleep process and writes the child PID to a temp file.
   - Close the supervisor.
   - Assert both root and child are gone on Linux when process-group mode is available.
   - Skip or downgrade expectation on platforms where process-group support is unavailable.

6. **Persists and removes PID records**
   - Start a persistent service process.
   - Assert a PID record exists.
   - Stop it.
   - Assert the record is removed.

7. **Does not kill an unverified stale PID**
   - Write a fake record pointing to the test runner PID with the wrong executable path.
   - Call stale-record cleanup.
   - Assert it refuses to signal and deletes or ignores the invalid record according to the chosen policy.

8. **Close is idempotent**
   - Call `close()` twice concurrently.
   - Assert no duplicate kill attempts and no thrown errors.

## Step 9: Extend existing tests

### `test/app_controller_shutdown_test.dart`

Add tests:

- `close begins process supervisor shutdown before closing services`.
- `close during initialize does not start services after closing begins`.
- `close during initialize is idempotent`.
- `ensureChatRuntimeReady returns false or throws when controller is closing`.
- `close reports remaining subprocess supervisor shutdown progress`.

### `test/local_services_test.dart`

Update tests to use a fake `ProcessSupervisor`.

Add tests:

- `_buildBinary()` delegates to `ProcessSupervisor.run()`.
- `_startProcess()` delegates to `ProcessSupervisor.start()` with `ManagedProcessKind.longRunningService`.
- service close stops handles in reverse order.
- stale PID cleanup delegates to `ProcessSupervisor.stopPersistedProcesses()`.
- no direct process API remains in local service orchestration.

### `test/local_model_runtime_test.dart`

Add tests:

- `_validateExecutable()` uses supervised run with 10 second timeout.
- `_runInference()` uses supervised run with 10 minute timeout.
- `close()` while inference is active calls `stopScope('local-model')`.
- queued inference refuses to launch after close.
- `start()` returns disconnected when closed before startup.
- `start()` closes the server if shutdown races after `server.start()`.

### Static guard test or CI command

Add a test or CI script that enforces the invariant:

```bash
grep -RInE 'Process\.(run|runSync|start|killPid)' lib \
  | grep -v 'lib/app/process_supervisor.dart'
```

Expected result: no output.

A separate check may allow `ProcessSignal` only in `aurora_app.dart` and `process_supervisor.dart`.

## Step 10: Acceptance criteria

The cleanup is complete when all of these are true:

- Closing the app window stops all app-started local services.
- Ctrl-C stops all app-started local services.
- Closing during `go build` kills the build command.
- Closing during LiteRT inference kills the active `litert-lm run` process.
- Closing during keyring or system probes does not leave a process behind.
- Startup refuses to launch new subprocesses after shutdown begins.
- A second close request while shutdown is running does not duplicate shutdown work.
- PID records are written only for long-running app-owned services.
- Stale PID records are verified by executable path before any signal is sent.
- Port cleanup is only a fallback, never the primary ownership mechanism.
- On Linux, service process groups are killed, not only root processes.
- On macOS/Windows, unsupported process-tree guarantees are logged honestly or implemented with native helpers.
- `grep` confirms no production direct process launch/kill calls remain outside `process_supervisor.dart`.

## Implementation order

1. Add `process_supervisor.dart` and its unit tests.
2. Migrate `local_services.dart` to the supervisor.
3. Migrate `local_model_runtime.dart` to the supervisor.
4. Add the shared supervisor to `app_controller.dart` and wire it into services, models, credentials, and probes.
5. Migrate `credential_store.dart` and `system_capabilities.dart` through `CommandRunner`.
6. Extend shutdown race tests.
7. Add the static grep guard.
8. Manually test Ctrl-C, window close, close during build, and close during local inference.

## Notes for Codex

- Do not add another subprocess manager inside `local_model_runtime.dart` or `local_services.dart`. That repeats the current problem.
- Do not leave `Process.run` in place because it looks short-lived. Short-lived commands are exactly the commands that leak when shutdown happens mid-command.
- Do not rely on Flutter widget `dispose()` for subprocess cleanup. Use it only as a fallback.
- Do not use port killing as the main cleanup mechanism. It is less precise than process handles and verified PID records.
- Keep the UI-facing status types stable where possible. Most UI code should not need to know that the underlying process implementation changed.
- Prefer small functions in the supervisor: launch, capture output, persist record, signal process, signal group, wait for exit, cleanup stale records.
- Preserve existing log messages where practical so debugging does not regress.
