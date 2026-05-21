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

  test('creates tool configs inside package folders', () async {
    final path = await store.create(ConfigFileKind.tool);

    expect(path, '${tempRoot.path}/tools/tool/tool.yaml');

    await store.write(path, 'name: Tool Package\n');
    final entries = await store.list(kind: ConfigFileKind.tool);

    expect(entries.single.path, path);
    expect(entries.single.fileLabel, 'tool');
    expect(entries.single.displayName, 'Tool Package');
  });

  test('creates MCP configs inside package folders', () async {
    final path = await store.create(ConfigFileKind.mcp);

    expect(path, '${tempRoot.path}/mcp/mcp/mcp.yaml');

    await store.write(path, '''
mcp:
  servers:
    - name: memory
''');
    final entries = await store.list(kind: ConfigFileKind.mcp);

    expect(entries.single.path, path);
    expect(entries.single.fileLabel, 'mcp');
    expect(entries.single.displayName, 'memory');
  });

  test('duplicates complete config package directories', () async {
    final sourcePath = await store.create(ConfigFileKind.tool);
    await store.write(sourcePath, 'name: Package\n');
    final helper = File('${File(sourcePath).parent.path}/bin/helper.sh');
    await helper.parent.create(recursive: true);
    await helper.writeAsString('#!/bin/sh\n');

    final duplicatePath = await store.duplicate(
      sourcePath,
      ConfigFileKind.tool,
    );
    final duplicatePackage = File(duplicatePath).parent;

    expect(duplicatePath, '${tempRoot.path}/tools/tool-copy/tool.yaml');
    expect(await File(duplicatePath).readAsString(), 'name: Package\n');
    expect(
      await File('${duplicatePackage.path}/bin/helper.sh').readAsString(),
      '#!/bin/sh\n',
    );
  });

  test('renames config package directories', () async {
    final path = await store.create(ConfigFileKind.mcp);
    final renamed = await store.rename(
      ConfigFileEntry(path: path, kind: ConfigFileKind.mcp, assigned: false),
      'Memory Server',
    );

    expect(renamed, '${tempRoot.path}/mcp/memory-server/mcp.yaml');
    expect(await File(renamed).exists(), isTrue);
    expect(await Directory('${tempRoot.path}/mcp/mcp').exists(), isFalse);
  });

  test('deletes config package directories', () async {
    final path = await store.create(ConfigFileKind.tool);
    final helper = File('${File(path).parent.path}/bin/helper.sh');
    await helper.parent.create(recursive: true);
    await helper.writeAsString('#!/bin/sh\n');

    await store.delete(path, kind: ConfigFileKind.tool);

    expect(await File(path).exists(), isFalse);
    expect(await helper.exists(), isFalse);
    expect(await Directory('${tempRoot.path}/tools/tool').exists(), isFalse);
  });

  test(
    'deletes legacy flat package config files without deleting root',
    () async {
      final root = Directory('${tempRoot.path}/tools');
      await root.create(recursive: true);
      final path = '${root.path}/tool.yaml';
      await File(path).writeAsString('name: Legacy\n');
      await File('${root.path}/other.yaml').writeAsString('name: Other\n');

      await store.delete(path, kind: ConfigFileKind.tool);

      expect(await File(path).exists(), isFalse);
      expect(await File('${root.path}/other.yaml').exists(), isTrue);
      expect(await root.exists(), isTrue);
    },
  );

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
