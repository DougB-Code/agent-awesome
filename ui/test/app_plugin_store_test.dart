/// Tests manifest-backed app plugin loading.
library;

import 'dart:io';

import 'package:agentawesome_ui/app/app_plugin_store.dart';
import 'package:agentawesome_ui/app/process_supervisor.dart';
import 'package:agentawesome_ui/domain/app_plugin.dart';
import 'package:agentawesome_ui/domain/app_plugin_manifest_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs app plugin manifest parsing and store tests.
void main() {
  test('parses board-capable Starlark app plugin manifests', () {
    final manifest = parseAppPluginManifest(<String, dynamic>{
      'id': 'Workflow Board',
      'name': 'Workflow Board',
      'description': 'A board-style app supplied by a plugin package.',
      'version': '0.1.0',
      'entrypoint': <String, dynamic>{'starlark': 'main.star'},
      'navigation': <String, dynamic>{'icon': 'board'},
      'panels': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'board',
          'title': 'Board',
          'kind': 'kanban',
          'blocks': <Map<String, dynamic>>[
            <String, dynamic>{
              'title': 'Lanes',
              'text': 'Custom Starlark panel content',
              'badges': <String>['todo', 'doing', 'done'],
            },
          ],
          'actions': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'create-card',
              'title': 'Create card',
              'kind': 'workflow',
            },
          ],
        },
      ],
      'integrations': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'apple-calendar',
          'title': 'Apple Calendar Sync',
          'kind': 'apple-calendar',
          'credentialScope': 'calendar.readwrite',
          'credential': <String, dynamic>{
            'kind': 'apple-calendar',
            'profileId': 'Personal',
            'usernameRef': 'AA_APPLE_CALENDAR_PERSONAL_APPLE_ID',
            'passwordRef': 'AA_APPLE_CALENDAR_PERSONAL_APP_PASSWORD',
          },
          'capabilities': <String>['read events', 'write events'],
        },
        <String, dynamic>{
          'id': 'd2l',
          'title': 'D2L Downloads',
          'kind': 'browser',
          'credential': <String, dynamic>{
            'kind': 'website-login',
            'profileId': 'D2L Downloads',
            'usernameRef': 'AA_WEB_LOGIN_D2L_DOWNLOADS_USERNAME',
            'passwordRef': 'AA_WEB_LOGIN_D2L_DOWNLOADS_PASSWORD',
            'allowedDomains': <String>['d2l.example.test'],
          },
        },
      ],
    }, packagePath: '/tmp/workflow-board');

    expect(manifest.id, 'workflow-board');
    expect(manifest.defaultRoute, 'app-plugin:workflow-board:board');
    expect(manifest.starlarkEntrypoint, 'main.star');
    expect(manifest.supportsBoardTools, isTrue);
    expect(manifest.panels.single.kind, AppPluginPanelKind.board);
    expect(
      manifest.panels.single.blocks.single.text,
      'Custom Starlark panel content',
    );
    expect(manifest.integrations.first.kind, 'apple-calendar');
    expect(manifest.integrations.first.credential.isAppleCalendar, isTrue);
    expect(manifest.integrations.last.credential.isWebsiteLogin, isTrue);
    expect(
      manifest.integrations.last.credential.allowedDomains.single,
      'd2l.example.test',
    );
  });

  test('loads usable app plugin manifests from package directories', () async {
    final root = await Directory.systemTemp.createTemp('aa_app_plugins_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final package = Directory('${root.path}/workflow-board');
    await package.create(recursive: true);
    await File('${package.path}/$aaAppPluginManifestFilename').writeAsString('''
id: workflow-board
name: Workflow Board
entrypoint:
  starlark: main.star
panels:
  - id: board
    title: Board
    kind: board
    actions:
      - id: create-card
        title: Create card
        kind: workflow
''');

    final plugins = await AppPluginStore(rootPath: root.path).list();

    expect(plugins, hasLength(1));
    expect(plugins.single.name, 'Workflow Board');
    expect(plugins.single.defaultRoute, 'app-plugin:workflow-board:board');
  });

  test(
    'renders Starlark app plugins when static manifests are absent',
    () async {
      final root = await Directory.systemTemp.createTemp('aa_app_plugins_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final package = Directory('${root.path}/calendar-sync');
      await package.create(recursive: true);
      await File('${package.path}/app.star').writeAsString('''
def render():
    return {}
''');

      final plugins = await AppPluginStore(
        rootPath: root.path,
        renderer: _FakeAppPluginRenderer(<String, dynamic>{
          'id': 'calendar-sync',
          'name': 'Calendar Sync',
          'entrypoint': <String, dynamic>{'starlark': 'app.star'},
          'panels': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'schedule',
              'title': 'Schedule',
              'kind': 'calendar',
              'blocks': <Map<String, dynamic>>[
                <String, dynamic>{
                  'title': 'Sync',
                  'text': 'Rendered by app.star',
                },
              ],
            },
          ],
        }),
      ).list();

      expect(plugins, hasLength(1));
      expect(plugins.single.renderedFromStarlark, isTrue);
      expect(plugins.single.starlarkEntrypoint, 'app.star');
      expect(plugins.single.panels.single.kind, AppPluginPanelKind.calendar);
      expect(
        plugins.single.panels.single.blocks.single.text,
        'Rendered by app.star',
      );
    },
  );

  test('skips Starlark app plugins when rendering fails', () async {
    final root = await Directory.systemTemp.createTemp('aa_app_plugins_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final package = Directory('${root.path}/broken');
    await package.create(recursive: true);
    await File('${package.path}/app.star').writeAsString('''
def render():
    while True:
        pass
''');

    final plugins = await AppPluginStore(
      rootPath: root.path,
      renderer: const _ThrowingAppPluginRenderer(),
    ).list();

    expect(plugins, isEmpty);
  });

  test('renders Starlark through supervised command runner', () async {
    final runner = _FakeCommandRunner(
      result: const ManagedProcessResult(
        id: 'app-render',
        pid: 1,
        exitCode: 0,
        stdout:
            '{"id":"calendar-sync","name":"Calendar Sync","panels":[{"id":"schedule","title":"Schedule","kind":"calendar"}]}',
        stderr: '',
        timedOut: false,
      ),
    );
    final renderer = CommandRunnerAppPluginRenderer(commandRunner: runner);

    final manifest = await renderer.render(
      packagePath: '/tmp/calendar-sync',
      entrypoint: 'app.star',
    );

    expect(manifest['id'], 'calendar-sync');
    expect(runner.executable, 'agent-awesome');
    expect(runner.arguments, <String>[
      'apps',
      'render',
      '/tmp/calendar-sync',
      '--entrypoint',
      'app.star',
      '--json',
    ]);
    expect(runner.timeout, const Duration(seconds: 5));
    expect(runner.scope, 'app-plugins');
  });
}

/// _FakeAppPluginRenderer returns one configured app plugin manifest.
class _FakeAppPluginRenderer implements AppPluginManifestRenderer {
  /// Creates a fake renderer for store tests.
  const _FakeAppPluginRenderer(this.manifest);

  /// Manifest returned by render calls.
  final Map<String, dynamic> manifest;

  /// Renders without executing external processes.
  @override
  Future<Map<String, dynamic>> render({
    required String packagePath,
    required String entrypoint,
  }) async {
    return manifest;
  }
}

/// _ThrowingAppPluginRenderer simulates a failed app plugin render.
class _ThrowingAppPluginRenderer implements AppPluginManifestRenderer {
  /// Creates a renderer that always fails.
  const _ThrowingAppPluginRenderer();

  /// Throws instead of returning a manifest.
  @override
  Future<Map<String, dynamic>> render({
    required String packagePath,
    required String entrypoint,
  }) async {
    throw FileSystemException('render failed', packagePath);
  }
}

/// _FakeCommandRunner captures supervised render requests.
class _FakeCommandRunner implements CommandRunner {
  /// Creates a fake command runner with one result.
  _FakeCommandRunner({required this.result});

  /// Result returned to callers.
  final ManagedProcessResult result;

  /// Captured executable.
  String executable = '';

  /// Captured arguments.
  List<String> arguments = const <String>[];

  /// Captured timeout.
  Duration? timeout;

  /// Captured process scope.
  String scope = '';

  /// Captures one command run.
  @override
  Future<ManagedProcessResult> run(
    String executable,
    List<String> arguments, {
    String? stdinText,
    Duration? timeout,
    String scope = 'commands',
    ManagedProcessKind kind = ManagedProcessKind.oneShotCommand,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    this.timeout = timeout;
    this.scope = scope;
    return result;
  }
}
