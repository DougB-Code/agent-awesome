/// Tests command-bar contextual help routing.
library;

import 'dart:io';

import 'package:agentawesome_ui/ui/command_bar/command_bar.dart';
import 'package:agentawesome_ui/ui/command_bar/command_context.dart';
import 'package:agentawesome_ui/ui/shell/app_sections.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs command-bar help routing tests.
void main() {
  test('maps chat context to web help when docs are unbuilt', () {
    final uri = commandHelpUri(
      const CommandContext(section: AppSections.chat, area: '', text: ''),
      '/tmp/agentawesome-missing-docs',
    );

    expect(uri.scheme, 'https');
    expect(uri.host, 'github.com');
    expect(uri.path, endsWith('/docs/modules/user/pages/local-chat.adoc'));
  });

  test('prefers built html documentation when present', () {
    final root = Directory.systemTemp.createTempSync('aa-help-docs-');
    addTearDown(() => root.deleteSync(recursive: true));
    File(
      '${root.path}/build/site/agent-awesome/0.1/user/local-chat.html',
    ).createSync(recursive: true);

    final uri = commandHelpUri(
      const CommandContext(section: AppSections.chat, area: '', text: ''),
      root.path,
    );

    expect(
      uri.path,
      endsWith('/build/site/agent-awesome/0.1/user/local-chat.html'),
    );
  });

  test('maps runbook contexts to launchpad local-run documentation', () {
    final uri = commandHelpUri(
      const CommandContext(
        section: AppSections.automationRunbooks,
        area: '',
        text: '',
      ),
      '/tmp/agentawesome-missing-docs',
    );

    expect(uri.scheme, 'https');
    expect(uri.host, 'github.com');
    expect(uri.path, endsWith('/docs/modules/launchpad/pages/local-run.adoc'));
  });
}
