/// Tests the global command bar keyboard submission semantics.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/theme.dart';
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

  testWidgets('Shift+Enter launches a new chat instead of a screen command', (
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
      'plan this weekend',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(screenCommands, isEmpty);
    expect(newChatCount, 1);
  });

  testWidgets('setup status opens first-run setup', (tester) async {
    final commandController = TextEditingController();
    var setupOpenCount = 0;

    await tester.pumpWidget(
      _CommandBarHarness(
        commandController: commandController,
        onScreenCommand: (_) {},
        onNewChatSubmit: () {},
        onOpenSetup: () => setupOpenCount++,
      ),
    );

    expect(find.text('Setup incomplete'), findsOneWidget);

    await tester.tap(find.text('Setup incomplete'));
    await tester.pump();

    expect(setupOpenCount, 1);
  });

  testWidgets('theme badge toggles between light and dark themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _ThemeCommandBarHarness(commandController: TextEditingController()),
    );

    expect(find.text('Light'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pump();

    expect(find.text('Dark'), findsOneWidget);
  });
}

class _CommandBarHarness extends StatelessWidget {
  const _CommandBarHarness({
    required this.commandController,
    required this.onScreenCommand,
    required this.onNewChatSubmit,
    this.onOpenSetup,
  });

  final TextEditingController commandController;
  final ValueChanged<CommandContext> onScreenCommand;
  final VoidCallback onNewChatSubmit;

  /// Optional setup callback used by tests that exercise the status action.
  final VoidCallback? onOpenSetup;

  /// Builds a minimal shell around the command bar.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CommandBar(
          commandController: commandController,
          appController: AgentAwesomeAppController(config: _testConfig()),
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
          onOpenSetup: onOpenSetup ?? () {},
        ),
      ),
    );
  }
}

class _ThemeCommandBarHarness extends StatefulWidget {
  const _ThemeCommandBarHarness({required this.commandController});

  final TextEditingController commandController;

  @override
  State<_ThemeCommandBarHarness> createState() =>
      _ThemeCommandBarHarnessState();
}

class _ThemeCommandBarHarnessState extends State<_ThemeCommandBarHarness> {
  ThemeMode _themeMode = ThemeMode.light;

  /// Builds a themed command-bar harness with a real toggle scope.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildAgentAwesomeTheme(),
      darkTheme: buildAgentAwesomeTheme(brightness: Brightness.dark),
      themeMode: _themeMode,
      builder: (context, child) {
        return AgentAwesomeThemeScope(
          themeMode: _themeMode,
          onToggleTheme: _toggleTheme,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: Scaffold(
        body: CommandBar(
          commandController: widget.commandController,
          appController: AgentAwesomeAppController(config: _testConfig()),
          commandContext: (text, {String profilePath = ''}) => CommandContext(
            section: AppSections.backlog,
            area: 'Stream',
            text: text,
            profilePath: profilePath,
          ),
          onSubmitScreenCommand: (_) async {},
          onSubmit: ({String profilePath = ''}) async {},
          onNewChat: () {},
          onStartChatWithProfile: (_) {},
          onSelectHistoryChat: (_) {},
          onOpenSection: (_) {},
          onOpenSettingsSection: (_) {},
          onOpenSettings: () {},
          onOpenSetup: () {},
        ),
      ),
    );
  }

  /// Flips between the explicit light and dark test themes.
  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }
}

/// Returns a local-only controller configuration for command bar tests.
AppConfig _testConfig() {
  return const AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:1/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:2/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:1/mcp',
    agentAppName: 'test',
    agentUserId: 'user',
    workspaceRoot: '/tmp/agentawesome-command-bar-test',
    autoStartLocalServices: false,
    runtimeProfilePath: '',
  );
}
