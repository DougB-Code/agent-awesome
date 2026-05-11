/// Tests managed configuration file store boundaries.
library;

import 'dart:io';

import 'package:agentawesome_ui/app/config_files.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs managed config file store tests.
void main() {
  late Directory tempRoot;
  late ConfigFileStore store;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('aa-config-files-');
    store = ConfigFileStore(configDirectoryPath: '${tempRoot.path}/config');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('reads and writes managed config files', () async {
    final path = await store.create(ConfigFileKind.model);

    await store.write(path, 'default: local:model\n');

    expect(await store.read(path), 'default: local:model\n');
  });

  test('rejects config reads outside managed directories', () async {
    final outside = File('${tempRoot.path}/outside.yaml');
    await outside.writeAsString('name: outside\n');

    expect(() => store.read(outside.path), throwsA(isA<FileSystemException>()));
  });

  test('rejects unsupported managed file extensions', () async {
    final path = '${tempRoot.path}/config/models/model.txt';

    expect(
      () => store.write(path, 'not config'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('rejects traversal out of a managed directory', () async {
    final path = '${tempRoot.path}/config/models/../outside.yaml';

    expect(
      () => store.write(path, 'name: outside\n'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('does not read metadata from assigned external config paths', () async {
    final outside = File('${tempRoot.path}/outside.yaml');
    await outside.writeAsString('name: Should Not Leak\n');

    final entries = await store.list(
      kind: ConfigFileKind.agent,
      assignedPath: outside.path,
    );

    expect(entries, hasLength(1));
    expect(entries.single.path, outside.path);
    expect(entries.single.displayName, isEmpty);
  });

  test(
    'rejects symlinked config file paths',
    () async {
      await store.create(ConfigFileKind.model);
      final target = File('${tempRoot.path}/outside.yaml');
      await target.writeAsString('name: outside\n');
      final link = Link('${tempRoot.path}/config/models/link.yaml');
      await link.create(target.path);

      expect(
        () => store.write(link.path, 'name: overwritten\n'),
        throwsA(isA<FileSystemException>()),
      );
    },
    skip: Platform.isWindows ? 'Windows symlink permissions vary.' : false,
  );

  test(
    'rejects symlinked config collection directories',
    () async {
      final configRoot = Directory('${tempRoot.path}/config');
      await configRoot.create(recursive: true);
      final target = Directory('${tempRoot.path}/outside-models');
      await target.create();
      final link = Link('${configRoot.path}/models');
      await link.create(target.path);

      expect(
        () => store.create(ConfigFileKind.model),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.list(kind: ConfigFileKind.model), isEmpty);
    },
    skip: Platform.isWindows ? 'Windows symlink permissions vary.' : false,
  );
}
