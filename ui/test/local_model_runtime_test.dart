/// Tests local model installation and runtime behavior.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/local_model_runtime.dart';
import 'package:agentawesome_ui/app/process_supervisor.dart';
import 'package:agentawesome_ui/domain/local_models.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Runs local model installer tests without downloading real model artifacts.
void main() {
  test('downloads, verifies, and records a local model manifest', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-local-model-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final bytes = utf8.encode('hello local model');
    final descriptor = _testDescriptor(bytes);
    final phases = <String>[];
    final runtime = LiteRtLocalModelRuntime(
      config: _testConfig(),
      processSupervisor: _testProcessSupervisor(root),
      dataDirectory: root.path,
      httpClient: MockClient((request) async {
        expect(request.url.toString(), descriptor.downloadUrl);
        return http.Response.bytes(bytes, 200);
      }),
    );
    addTearDown(runtime.close);

    final install = await runtime.ensureInstalled(
      descriptor,
      onProgress: (progress) => phases.add(progress.phase),
    );

    expect(await File(install.modelPath).readAsBytes(), bytes);
    expect(await runtime.isInstalled(descriptor), isTrue);
    expect(phases, containsAll(<String>['downloading', 'verifying', 'ready']));
    final manifest = jsonDecode(
      await File(install.manifestPath).readAsString(),
    );
    expect(manifest['sha256'], descriptor.expectedSha256);
    expect(manifest['license'], descriptor.license);
  });

  test('records a llama.cpp Hugging Face model without app download', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-llama-model-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final descriptor = _llamaDescriptor();
    final runtime = LiteRtLocalModelRuntime(
      config: _testConfig(),
      processSupervisor: _testProcessSupervisor(root),
      dataDirectory: root.path,
      httpClient: MockClient((request) async {
        fail('llama.cpp HF models should not use the app downloader');
      }),
    );
    addTearDown(runtime.close);

    final install = await runtime.ensureInstalled(descriptor);

    expect(await File(install.modelPath).exists(), isFalse);
    expect(await runtime.isInstalled(descriptor), isTrue);
    final manifest = jsonDecode(
      await File(install.manifestPath).readAsString(),
    );
    expect(manifest['runtime'], 'llama-cpp');
    expect(manifest['hf_repo'], descriptor.hfRepo);
  });

  test('rejects a downloaded model when the checksum does not match', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-local-model-bad-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final descriptor = _testDescriptor(
      utf8.encode('expected'),
      expectedSha256: '0' * 64,
    );
    final runtime = LiteRtLocalModelRuntime(
      config: _testConfig(),
      processSupervisor: _testProcessSupervisor(root),
      dataDirectory: root.path,
      httpClient: MockClient((request) async {
        return http.Response.bytes(utf8.encode('expected'), 200);
      }),
    );
    addTearDown(runtime.close);

    await expectLater(
      runtime.ensureInstalled(descriptor),
      throwsA(isA<StateError>()),
    );
    expect(await runtime.isInstalled(descriptor), isFalse);
  });

  test(
    'restores a verified local model artifact without downloading',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agentawesome-local-model-restore-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final cache = Directory('${root.path}/cache');
      await cache.create(recursive: true);
      final bytes = utf8.encode('cached local model');
      final descriptor = _testDescriptor(bytes);
      final cached = File('${cache.path}/${descriptor.fileName}');
      await cached.writeAsBytes(bytes);
      var downloadAttempted = false;
      final runtime = LiteRtLocalModelRuntime(
        config: _testConfig(),
        processSupervisor: _testProcessSupervisor(root),
        dataDirectory: '${root.path}/data',
        httpClient: MockClient((request) async {
          downloadAttempted = true;
          return http.Response.bytes(const <int>[], 500);
        }),
      );
      addTearDown(runtime.close);

      final install = await runtime.recoverInstalled(
        descriptor,
        candidatePaths: <String>[cached.path],
      );

      expect(install, isNotNull);
      expect(downloadAttempted, isFalse);
      expect(await File(install!.modelPath).readAsBytes(), bytes);
      expect(await runtime.isInstalled(descriptor), isTrue);
      final manifest = jsonDecode(
        await File(install.manifestPath).readAsString(),
      );
      expect(manifest['source'], descriptor.downloadUrl);
    },
  );

  test('resolves the underscore LiteRT-LM binary name from PATH', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-litert-path-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final bin = Directory('${root.path}/bin');
    await bin.create(recursive: true);
    final executable = File('${bin.path}/litert_lm');
    await executable.writeAsString('#!/bin/sh\nexit 0\n');
    await _makeExecutable(executable.path);
    final resolver = LocalModelExecutableResolver(
      environment: <String, String>{'PATH': bin.path},
    );

    final resolved = await resolver.resolve(
      configuredExecutable: 'litert-lm',
      dataDirectory: '${root.path}/data',
    );

    expect(resolved, executable.path);
  });

  test('copies a blocked LiteRT-LM binary into app-managed storage', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-litert-repair-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final bin = Directory('${root.path}/programs/bin');
    await bin.create(recursive: true);
    final executable = File('${bin.path}/litert_lm');
    await executable.writeAsString('#!/bin/sh\nexit 0\n');
    final supervisor = _testProcessSupervisor(root);
    final resolver = LocalModelExecutableResolver(
      environment: <String, String>{'PATH': bin.path},
      commandRunner: ProcessSupervisorCommandRunner(supervisor),
    );

    final resolved = await resolver.resolve(
      configuredExecutable: 'litert-lm',
      dataDirectory: '${root.path}/data',
    );

    final repaired = File('${root.path}/data/bin/litert_lm');
    expect(resolved, repaired.path);
    expect(await repaired.exists(), isTrue);
    if (!Platform.isWindows) {
      expect((await repaired.stat()).mode & 0x49, isNot(0));
    }
  });

  test('downloads a managed LiteRT-LM runtime binary', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-litert-runtime-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final bytes = utf8.encode(r'''
#!/bin/sh
if [ "$1" = "--help" ]; then
  exit 0
fi
exit 0
''');
    final artifact = LocalModelRuntimeArtifact(
      id: 'test-runtime',
      displayName: 'Test LiteRT-LM runtime',
      fileName: 'lit_test',
      executableName: 'litert-lm',
      downloadUrl: 'https://example.test/litert-lm',
      expectedBytes: bytes.length,
      expectedSha256: sha256.convert(bytes).toString(),
    );
    var downloads = 0;
    final supervisor = _testProcessSupervisor(root);
    final runtime = LiteRtLocalModelRuntime(
      config: _testConfig(litertLmExecutable: 'missing-litert-lm'),
      processSupervisor: supervisor,
      dataDirectory: root.path,
      runtimeArtifact: artifact,
      executableResolver: LocalModelExecutableResolver(
        environment: const <String, String>{'PATH': ''},
        commandRunner: ProcessSupervisorCommandRunner(supervisor),
      ),
      httpClient: MockClient((request) async {
        downloads++;
        expect(request.url.toString(), artifact.downloadUrl);
        return http.Response.bytes(bytes, 200);
      }),
    );
    addTearDown(runtime.close);

    final executable = await runtime.ensureRuntimeInstalled();

    final installed = File('${root.path}/bin/litert-lm');
    expect(executable, installed.path);
    expect(await installed.readAsBytes(), bytes);
    expect(downloads, 1);
    if (!Platform.isWindows) {
      expect((await installed.stat()).mode & 0x49, isNot(0));
    }
  });

  test(
    'reports a missing executable before starting the local endpoint',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agentawesome-litert-missing-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final bytes = utf8.encode('installed local model');
      final descriptor = _testDescriptor(bytes);
      final runtime = LiteRtLocalModelRuntime(
        config: _testConfig(litertLmExecutable: 'missing-litert-lm'),
        processSupervisor: _testProcessSupervisor(root),
        dataDirectory: root.path,
        httpClient: MockClient((request) async {
          return http.Response.bytes(bytes, 200);
        }),
        executableResolver: const LocalModelExecutableResolver(
          environment: <String, String>{'PATH': ''},
        ),
      );
      addTearDown(runtime.close);
      await runtime.ensureInstalled(descriptor);

      final status = await runtime.start(descriptor);

      expect(status.state, ConnectionStateKind.disconnected);
      expect(status.message, contains('LiteRT-LM executable'));
      expect(status.message, contains('missing-litert-lm'));
    },
  );

  test('reports executable dependency failures before serving chat', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-litert-invalid-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final executable = File('${root.path}/litert_lm');
    await executable.writeAsString(
      '#!/bin/sh\necho missing shared lib >&2\nexit 127\n',
    );
    await _makeExecutable(executable.path);
    final bytes = utf8.encode('installed local model');
    final descriptor = _testDescriptor(bytes);
    final runtime = LiteRtLocalModelRuntime(
      config: _testConfig(litertLmExecutable: executable.path),
      processSupervisor: _testProcessSupervisor(root),
      dataDirectory: root.path,
      httpClient: MockClient((request) async {
        return http.Response.bytes(bytes, 200);
      }),
    );
    addTearDown(runtime.close);
    await runtime.ensureInstalled(descriptor);

    final status = await runtime.start(descriptor);

    expect(status.state, ConnectionStateKind.disconnected);
    expect(status.message, contains('LiteRT-LM could not start'));
    expect(status.message, contains('missing shared lib'));
  });

  test('translates Gemma textual task calls into OpenAI tool calls', () async {
    final root = await Directory.systemTemp.createTemp(
      'agentawesome-litert-tool-call-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final port = await _freePort();
    final executable = File('${root.path}/litert_lm');
    await executable.writeAsString('''
#!/bin/sh
if [ "\$1" = "--help" ]; then
  exit 0
fi
echo '<|tool_call>call:task_tool{action: "create", details: { "description": "Buy milk" }, idempotency_key: "agent_awesome:session:"}<tool_call|>'
''');
    await _makeExecutable(executable.path);
    final bytes = utf8.encode('installed local model');
    final descriptor = _testDescriptor(bytes);
    final runtime = LiteRtLocalModelRuntime(
      config: _testConfig(
        litertLmExecutable: executable.path,
        localModelBaseUrl: 'http://127.0.0.1:$port',
      ),
      processSupervisor: _testProcessSupervisor(root),
      dataDirectory: root.path,
      httpClient: MockClient((request) async {
        return http.Response.bytes(bytes, 200);
      }),
    );
    addTearDown(runtime.close);
    await runtime.ensureInstalled(descriptor);
    final status = await runtime.start(descriptor);
    expect(status.state, ConnectionStateKind.connected);

    final response = await http.post(
      Uri.parse('http://127.0.0.1:$port/v1/chat/completions'),
      headers: const <String, String>{'content-type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'model': descriptor.modelName,
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'user',
            'content': 'Remember that I need to buy milk',
          },
        ],
        'tools': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'function',
            'function': <String, dynamic>{
              'name': 'create_task',
              'description': 'Create a graph-backed task.',
              'parameters': <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'title': <String, dynamic>{'type': 'string'},
                  'description': <String, dynamic>{'type': 'string'},
                  'idempotency_key': <String, dynamic>{'type': 'string'},
                },
              },
            },
          },
        ],
      }),
    );

    expect(response.statusCode, HttpStatus.ok);
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choice = (decoded['choices'] as List).single as Map<String, dynamic>;
    expect(choice['finish_reason'], 'tool_calls');
    final message = choice['message'] as Map<String, dynamic>;
    final calls = message['tool_calls'] as List;
    final call = calls.single as Map<String, dynamic>;
    final function = call['function'] as Map<String, dynamic>;
    expect(function['name'], 'create_task');
    final arguments = jsonDecode(function['arguments'].toString());
    expect(arguments['title'], 'Buy milk');
    expect(arguments['idempotency_key'], 'agent_awesome:session:');

    await executable.writeAsString('''
#!/bin/sh
if [ "\$1" = "--help" ]; then
  exit 0
fi
echo '<|tool_call>call:tool_call{create_task{description:<|"|>Buy milk<|"|>,title:<|"|>Buy Milk<|"|>}}<tool_call|>'
''');
    await _makeExecutable(executable.path);

    final nestedResponse = await http.post(
      Uri.parse('http://127.0.0.1:$port/v1/chat/completions'),
      headers: const <String, String>{'content-type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'model': descriptor.modelName,
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'user',
            'content': 'Make a reminder to buy milk',
          },
        ],
        'tools': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'function',
            'function': <String, dynamic>{
              'name': 'create_task',
              'description': 'Create a graph-backed task.',
              'parameters': <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'title': <String, dynamic>{'type': 'string'},
                  'description': <String, dynamic>{'type': 'string'},
                },
              },
            },
          },
        ],
      }),
    );

    expect(nestedResponse.statusCode, HttpStatus.ok);
    final nestedDecoded =
        jsonDecode(nestedResponse.body) as Map<String, dynamic>;
    final nestedChoice =
        (nestedDecoded['choices'] as List).single as Map<String, dynamic>;
    expect(nestedChoice['finish_reason'], 'tool_calls');
    final nestedMessage = nestedChoice['message'] as Map<String, dynamic>;
    final nestedCalls = nestedMessage['tool_calls'] as List;
    final nestedCall = nestedCalls.single as Map<String, dynamic>;
    final nestedFunction = nestedCall['function'] as Map<String, dynamic>;
    expect(nestedFunction['name'], 'create_task');
    final nestedArguments = jsonDecode(nestedFunction['arguments'].toString());
    expect(nestedArguments['title'], 'Buy Milk');
    expect(nestedArguments['description'], 'Buy milk');
  });
}

LocalModelDescriptor _testDescriptor(
  List<int> bytes, {
  String? expectedSha256,
}) {
  return LocalModelDescriptor(
    id: 'test-model',
    displayName: 'Test Model',
    modelName: 'test-model',
    repository: 'example/test-model',
    revision: 'revision',
    fileName: 'test.litertlm',
    downloadUrl: 'https://example.test/test.litertlm',
    expectedBytes: bytes.length,
    expectedSha256: expectedSha256 ?? sha256.convert(bytes).toString(),
    license: 'Apache-2.0',
  );
}

LocalModelDescriptor _llamaDescriptor() {
  return const LocalModelDescriptor(
    id: 'test-llama',
    displayName: 'Test Llama',
    modelName: 'test-llama-q4',
    repository: 'example/test-llama-gguf',
    revision: '',
    fileName: 'hf-repo.txt',
    downloadUrl: '',
    expectedBytes: 0,
    expectedSha256: '',
    license: 'Test',
    runtimeKind: LocalModelRuntimeKind.llamaCpp,
    providerId: 'llama-cpp',
    providerName: 'Llama.cpp',
    hfRepo: 'example/test-llama-gguf:Q4_K_M',
  );
}

Future<void> _makeExecutable(String path) async {
  if (Platform.isWindows) {
    return;
  }
  final result = await Process.run('chmod', <String>['755', path]);
  if (result.exitCode != 0) {
    throw StateError('chmod failed: ${result.stderr}');
  }
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

ProcessSupervisor _testProcessSupervisor(Directory root) {
  final supervisor = ProcessSupervisor(
    logDirectory: '${root.path}/logs',
    workspaceRoot: root.path,
  );
  addTearDown(supervisor.close);
  return supervisor;
}

AppConfig _testConfig({
  String litertLmExecutable = 'litert_lm',
  String localModelBaseUrl = 'http://127.0.0.1:0',
}) {
  return AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:1/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:2/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:1/mcp',
    agentAppName: 'test',
    agentUserId: 'user',
    workspaceRoot: '/tmp/agentawesome-local-model-test',
    autoStartLocalServices: false,
    runtimeProfilePath: '',
    litertLmExecutable: litertLmExecutable,
    localModelBaseUrl: localModelBaseUrl,
  );
}
