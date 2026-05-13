/// Tests shared subprocess supervision behavior.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentawesome_ui/app/process_supervisor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs process supervisor contract tests.
void main() {
  test('rejects launches after shutdown begins', () async {
    final root = await _tempRoot('reject');
    final supervisor = _supervisor(root);
    supervisor.beginClosing();

    await expectLater(
      supervisor.start(
        const ManagedProcessSpec(
          id: 'sleep',
          name: 'sleep',
          executable: 'sleep',
          arguments: <String>['1'],
          kind: ManagedProcessKind.oneShotCommand,
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      supervisor.run(
        const ManagedProcessSpec(
          id: 'echo',
          name: 'echo',
          executable: 'echo',
          arguments: <String>['hello'],
          kind: ManagedProcessKind.oneShotCommand,
        ),
      ),
      throwsStateError,
    );
  });

  test('captures stdout and stderr', () async {
    if (Platform.isWindows) {
      return;
    }
    final root = await _tempRoot('capture');
    final supervisor = _supervisor(root);
    final script = await _script(root, 'capture.sh', '''
#!/bin/sh
echo hello-out
echo hello-err >&2
''');

    final result = await supervisor.run(
      ManagedProcessSpec(
        id: 'capture',
        name: 'capture',
        executable: script.path,
        kind: ManagedProcessKind.oneShotCommand,
        shutdownMode: ManagedProcessShutdownMode.processOnly,
      ),
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('hello-out'));
    expect(result.stderr, contains('hello-err'));
  });

  test('kills a timed-out one-shot command', () async {
    if (Platform.isWindows) {
      return;
    }
    final root = await _tempRoot('timeout');
    final supervisor = _supervisor(root);
    final script = await _script(root, 'slow.sh', '''
#!/bin/sh
sleep 30
''');

    final result = await supervisor.run(
      ManagedProcessSpec(
        id: 'slow',
        name: 'slow',
        executable: script.path,
        kind: ManagedProcessKind.oneShotCommand,
        shutdownMode: ManagedProcessShutdownMode.processGroup,
        timeout: const Duration(milliseconds: 100),
      ),
    );

    expect(result.timedOut, isTrue);
    expect(await _pidAlive(result.pid), isFalse, reason: await _logText(root));
  });

  test('kills a long-running child on close', () async {
    if (!Platform.isLinux) {
      return;
    }
    final root = await _tempRoot('close-child');
    final supervisor = _supervisor(root);
    final childPidFile = File('${root.path}/child.pid');
    final script = await _script(root, 'child.sh', '''
#!/bin/sh
sleep 30 &
echo \$! > "\$1"
wait
''');
    final handle = await supervisor.start(
      ManagedProcessSpec(
        id: 'child',
        name: 'child',
        executable: '/bin/sh',
        arguments: <String>[script.path, childPidFile.path],
        kind: ManagedProcessKind.longRunningService,
        shutdownMode: ManagedProcessShutdownMode.processGroup,
        scope: 'test',
      ),
    );
    final childPid = await _readPid(childPidFile);

    await supervisor.close();

    expect(
      await _waitUntilDead(handle.pid),
      isTrue,
      reason: await _logText(root),
    );
    expect(
      await _waitUntilDead(childPid),
      isTrue,
      reason: await _logText(root),
    );
  });

  test('persists and removes pid records', () async {
    if (Platform.isWindows) {
      return;
    }
    final root = await _tempRoot('pid-record');
    final supervisor = _supervisor(root);
    final script = await _script(root, 'persist.sh', '''
#!/bin/sh
sleep 30
''');

    final handle = await supervisor.start(
      ManagedProcessSpec(
        id: 'service',
        name: 'Service',
        executable: script.path,
        kind: ManagedProcessKind.longRunningService,
        shutdownMode: ManagedProcessShutdownMode.processOnly,
        persistence: ManagedProcessPersistence.pidRecord,
        expectedExecutable: script.path,
        scope: 'test-scope',
      ),
    );
    final record = File('${root.path}/logs/pids/test-scope/service.json');

    expect(await record.exists(), isTrue);
    await supervisor.stop(handle);
    expect(await record.exists(), isFalse);
  });

  test('does not kill an unverified stale pid', () async {
    final root = await _tempRoot('stale');
    final supervisor = _supervisor(root);
    final record = File('${root.path}/logs/pids/test-scope/current.json');
    await record.parent.create(recursive: true);
    await record.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{'id': 'current', 'name': 'Current Test Process', 'pid': pid, 'executable': '${root.path}/not-this-process', 'owns_process_group': false, 'kind': 'longRunningService', 'scope': 'test-scope', 'started_at': DateTime.now().toUtc().toIso8601String()})}\n',
    );

    await supervisor.stopPersistedProcesses(namespace: 'test-scope');

    expect(await _pidAlive(pid), isTrue);
    expect(await record.exists(), isFalse);
  });

  test('close is idempotent', () async {
    if (Platform.isWindows) {
      return;
    }
    final root = await _tempRoot('idempotent');
    final supervisor = _supervisor(root);
    final script = await _script(root, 'idle.sh', '''
#!/bin/sh
sleep 30
''');
    await supervisor.start(
      ManagedProcessSpec(
        id: 'idle',
        name: 'idle',
        executable: script.path,
        kind: ManagedProcessKind.longRunningService,
        shutdownMode: ManagedProcessShutdownMode.processOnly,
      ),
    );

    await Future.wait(<Future<void>>[supervisor.close(), supervisor.close()]);
  });

  test('production code only launches processes through supervisor', () async {
    final matches = <String>[];
    final lib = Directory('lib');
    final pattern = RegExp(r'Process\.(run|runSync|start|killPid)');
    await for (final entity in lib.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final normalizedPath = entity.path.replaceAll('\\', '/');
      if (normalizedPath == 'lib/app/process_supervisor.dart' ||
          normalizedPath.startsWith('lib/app/process_supervisor_')) {
        continue;
      }
      final lines = await entity.readAsLines();
      for (var index = 0; index < lines.length; index++) {
        if (pattern.hasMatch(lines[index])) {
          matches.add('${entity.path}:${index + 1}: ${lines[index].trim()}');
        }
      }
    }

    expect(matches, isEmpty);
  });

  test('app controller routes domain tools through control plane', () async {
    final matches = <String>[];
    final lib = Directory('lib/app');
    final pattern = RegExp(r'McpJsonRpcClient\s*\(');
    await for (final entity in lib.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final lines = await entity.readAsLines();
      for (var index = 0; index < lines.length; index++) {
        if (pattern.hasMatch(lines[index])) {
          matches.add('${entity.path}:${index + 1}: ${lines[index].trim()}');
        }
      }
    }

    expect(matches, isEmpty, reason: matches.join('\n'));
  });

  test('app channel clients target gateway routes', () async {
    final matches = <String>[];
    final files = <String>[
      'lib/app/app_controller.dart',
      'lib/app/app_controller_runtime_profile.dart',
    ];
    final forbidden = <RegExp>[
      RegExp(r'baseUrl:\s*config\.agentApiBaseUrl'),
      RegExp(r'baseUrl:\s*profile\.harness\.apiBaseUrl'),
      RegExp(r'return\s+profile\.harness\.contextApiBaseUrl'),
      RegExp(r'gateway\s*!=\s*null\s*&&\s*gateway\.enabled'),
    ];
    for (final path in files) {
      final lines = await File(path).readAsLines();
      for (var index = 0; index < lines.length; index++) {
        if (forbidden.any((pattern) => pattern.hasMatch(lines[index]))) {
          matches.add('$path:${index + 1}: ${lines[index].trim()}');
        }
      }
    }

    expect(matches, isEmpty, reason: matches.join('\n'));
  });
}

/// Creates a temp root and registers cleanup for one test.
Future<Directory> _tempRoot(String name) async {
  final root = await Directory.systemTemp.createTemp(
    'agentawesome-process-supervisor-$name-',
  );
  addTearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });
  return root;
}

/// Creates a supervisor bound to one temp root.
ProcessSupervisor _supervisor(Directory root) {
  final supervisor = ProcessSupervisor(
    logDirectory: '${root.path}/logs',
    workspaceRoot: root.path,
  );
  addTearDown(supervisor.close);
  return supervisor;
}

/// Writes an executable shell script for a test.
Future<File> _script(Directory root, String name, String content) async {
  final file = File('${root.path}/$name');
  await file.writeAsString(content);
  await _makeExecutable(file.path);
  return file;
}

/// Marks a file executable on POSIX hosts.
Future<void> _makeExecutable(String path) async {
  if (Platform.isWindows) {
    return;
  }
  final result = await Process.run('chmod', <String>['755', path]);
  if (result.exitCode != 0) {
    throw StateError('chmod failed: ${result.stderr}');
  }
}

/// Reads a pid file written by a child script.
Future<int> _readPid(File file) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (await file.exists()) {
      final parsed = int.tryParse((await file.readAsString()).trim());
      if (parsed != null) {
        return parsed;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('pid file was not written: ${file.path}');
}

/// Reports whether a pid is currently signalable.
Future<bool> _pidAlive(int processId) async {
  if (Platform.isWindows || processId <= 1) {
    return false;
  }
  final stat = File('/proc/$processId/stat');
  if (await stat.exists()) {
    final content = await stat.readAsString();
    final commandEnd = content.lastIndexOf(')');
    if (commandEnd != -1 && commandEnd + 2 < content.length) {
      final state = content.substring(commandEnd + 2).trim().split(' ').first;
      if (state == 'Z') {
        return false;
      }
    }
  }
  final result = await Process.run('kill', <String>['-0', '$processId']);
  return result.exitCode == 0;
}

/// Waits briefly for a process id to disappear.
Future<bool> _waitUntilDead(int processId) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (!await _pidAlive(processId)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return false;
}

/// Reads the supervisor log for assertion failure context.
Future<String> _logText(Directory root) async {
  final log = File('${root.path}/logs/ui.log');
  if (!await log.exists()) {
    return 'no supervisor log at ${log.path}';
  }
  return log.readAsString();
}
