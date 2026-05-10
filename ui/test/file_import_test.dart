/// Tests file import serialization helpers.
library;

import 'dart:convert';

import 'package:agentawesome_ui/app/file_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs focused file import tests.
void main() {
  test('serializes text files as utf-8 file content', () {
    final imported = ImportedAgentFile.fromBytes(
      name: 'notes.md',
      path: '/tmp/notes.md',
      bytes: utf8.encode('# Notes'),
    );

    expect(imported.mediaType, 'text/markdown; charset=utf-8');
    expect(imported.encoding, 'utf-8');
    expect(imported.kind, 'document');
    expect(imported.topics, <String>['file', 'document']);
    expect(imported.serializedContent, contains('Agent Awesome file'));
    expect(imported.serializedContent, isNot(contains('file evidence')));
    expect(imported.serializedContent, contains('# Notes'));
    expect(imported.toMemoryDraft().sourceSystem, 'local_file');
  });

  test('serializes binary files as base64 file content', () {
    final imported = ImportedAgentFile.fromBytes(
      name: 'receipt.pdf',
      path: '/tmp/receipt.pdf',
      bytes: <int>[0, 1, 2, 3],
    );

    expect(imported.mediaType, 'application/pdf');
    expect(imported.encoding, 'base64');
    expect(imported.kind, 'document');
    expect(
      imported.serializedContent,
      contains(base64Encode(<int>[0, 1, 2, 3])),
    );
  });

  test('rejects oversized files before memory capture', () {
    expect(
      () => ImportedAgentFile.fromBytes(
        name: 'large.bin',
        path: '/tmp/large.bin',
        bytes: <int>[1, 2, 3],
        maxBytes: 2,
      ),
      throwsA(isA<FileImportException>()),
    );
  });
}
