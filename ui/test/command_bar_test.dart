/// Tests the global command bar keyboard submission semantics.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/ui/command_bar/command_bar.dart';
import 'package:agentawesome_ui/ui/command_bar/command_context.dart';
import 'package:agentawesome_ui/ui/shell/app_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs focused command bar behavior tests.
void main() {
  testWidgets('plain Enter submits a command to the current screen', (
    tester,
  ) async {
    final commandController = TextEditingController();
    final screenCommands = <CommandContext>[];
    var newChatCount = 0;

    await tester.pumpWidget(
      _CommandBarHarness(
        commandController: commandController,
        onScreenCommand: screenCommands.add,
        onNewChatSubmit: () => newChatCount++,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('global-command-input')),
      'show overdue backlog',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(screenCommands, hasLength(1));
    expect(screenCommands.single.section, AppSections.backlog);
    expect(screenCommands.single.area, 'Stream');
    expect(screenCommands.single.text, 'show overdue backlog');
    expect(newChatCount, 0);
    expect(commandController.text, isEmpty);
  });

  testWidgets('Ctrl+Enter launches a new chat instead of a screen command', (
    tester,
  ) async {
    final commandController = TextEditingController();
    final screenCommands = <CommandContext>[];
    var newChatCount = 0;

    await tester.pumpWidget(
      _CommandBarHarness(
        commandController: commandController,
        onScreenCommand: screenCommands.add,
        onNewChatSubmit: () => newChatCount++,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('global-command-input')),
      'research a new vendor',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(screenCommands, isEmpty);
    expect(newChatCount, 1);
  });
}

class _CommandBarHarness extends StatelessWidget {
  const _CommandBarHarness({
    required this.commandController,
    required this.onScreenCommand,
    required this.onNewChatSubmit,
  });

  final TextEditingController commandController;
  final ValueChanged<CommandContext> onScreenCommand;
  final VoidCallback onNewChatSubmit;

  /// Builds a minimal shell around the command bar.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CommandBar(
          commandController: commandController,
          appController: AuroraAppController(config: _testConfig()),
          commandContext: (text, {String profilePath = ''}) => CommandContext(
            section: AppSections.backlog,
            area: 'Stream',
            text: text,
            profilePath: profilePath,
          ),
          onSubmitScreenCommand: (context) async => onScreenCommand(context),
          onSubmit: ({String profilePath = ''}) async => onNewChatSubmit(),
          onNewChat: () {},
          onStartChatWithProfile: (_) {},
          onSelectHistoryChat: (_) {},
          onOpenSection: (_) {},
          onOpenSettingsSection: (_) {},
          onOpenSettings: () {},
        ),
      ),
    );
  }
}

/// Returns a local-only controller configuration for command bar tests.
AppConfig _testConfig() {
  return const AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:1/api',
    memoryMcpUrl: 'http://127.0.0.1:1/mcp',
    agentAppName: 'test',
    agentUserId: 'user',
    workspaceRoot: '/tmp/agentawesome-command-bar-test',
    autoStartLocalServices: false,
    runtimeProfilePath: '',
  );
}
