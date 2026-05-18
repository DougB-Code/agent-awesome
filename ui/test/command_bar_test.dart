/// Tests the global command bar keyboard submission semantics.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/app_settings.dart';
import 'package:agentawesome_ui/app/config_files.dart';
import 'package:agentawesome_ui/app/theme.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/domain/runtime_profile.dart';
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

  testWidgets('hides setup badge for external gateway model metadata', (
    tester,
  ) async {
    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.appSettings = const AgentAwesomeAppSettings(
      gettingStartedCompleted: true,
    );
    controller.runtimeProfilePath = '/tmp/cloudflare_context.json';
    controller.runtimeProfile = _externalGatewayProfile();
    controller.availableModelConfigs = const <ConfigFileEntry>[];
    controller.availableProfiles = const <RuntimeProfileFileEntry>[
      RuntimeProfileFileEntry(
        path: '/tmp/cloudflare_context.json',
        id: 'cloudflare-doug',
        label: 'Cloudflare Doug',
        active: true,
        runtimeKind: 'Cloud',
        memoryDomainLabels: <String>['Doug Memory'],
      ),
    ];

    await tester.pumpWidget(
      _CommandBarHarness(
        commandController: TextEditingController(),
        appController: controller,
        onScreenCommand: (_) {},
        onNewChatSubmit: () {},
      ),
    );

    expect(controller.hasConfiguredModel, isTrue);
    expect(find.text('Setup incomplete'), findsNothing);
  });

  testWidgets(
    'hides setup badge after completed setup even when model list is stale',
    (tester) async {
      final controller = AgentAwesomeAppController(config: _testConfig());
      controller.appSettings = const AgentAwesomeAppSettings(
        gettingStartedCompleted: true,
      );
      controller.runtimeProfilePath = '/tmp/personal.json';
      controller.runtimeProfile = _personalProfile();
      controller.availableModelConfigs = const <ConfigFileEntry>[];

      await tester.pumpWidget(
        _CommandBarHarness(
          commandController: TextEditingController(),
          appController: controller,
          onScreenCommand: (_) {},
          onNewChatSubmit: () {},
        ),
      );

      expect(controller.gettingStartedCompleted, isTrue);
      expect(controller.hasConfiguredModel, isFalse);
      expect(find.text('Setup incomplete'), findsNothing);
    },
  );

  testWidgets('shows active runtime profile picker in the top bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AgentAwesomeAppController(config: _testConfig());
    final openedSettingsSections = <String>[];
    controller.runtimeProfilePath = '/tmp/personal.json';
    controller.availableProfiles = const <RuntimeProfileFileEntry>[
      RuntimeProfileFileEntry(
        path: '/tmp/personal.json',
        id: 'personal',
        label: 'Personal',
        active: true,
        runtimeKind: 'Local',
        memoryDomainLabels: <String>['memory'],
      ),
      RuntimeProfileFileEntry(
        path: '/tmp/work.json',
        id: 'work',
        label: 'Work',
        active: false,
        runtimeKind: 'Cloud',
        memoryDomainLabels: <String>['work'],
      ),
    ];

    await tester.pumpWidget(
      _CommandBarHarness(
        commandController: TextEditingController(),
        appController: controller,
        onScreenCommand: (_) {},
        onNewChatSubmit: () {},
        onOpenSettingsSection: openedSettingsSections.add,
      ),
    );

    expect(find.byTooltip('Active profile'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);

    await tester.tap(find.byTooltip('Active profile'));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    expect(find.textContaining('Cloud'), findsOneWidget);
    expect(find.textContaining('memory'), findsOneWidget);

    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();

    expect(openedSettingsSections, <String>['Profiles']);
  });

  testWidgets('quick access links profile management and all chats', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final openedSections = <String>[];
    final openedSettingsSections = <String>[];
    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.runtimeProfilePath = '/tmp/personal.json';
    controller.availableProfiles = const <RuntimeProfileFileEntry>[
      RuntimeProfileFileEntry(
        path: '/tmp/personal.json',
        id: 'personal',
        label: 'Agent Awesome',
        active: true,
        runtimeKind: 'Local',
        memoryDomainLabels: <String>['memory'],
      ),
    ];
    controller.chatHistory = <ChatHistoryEntry>[
      ChatHistoryEntry(
        profilePath: '/tmp/personal.json',
        profileId: 'personal',
        profileLabel: 'Agent Awesome',
        sessionId: 'chat-1',
        title: 'Weather information limitation',
        updatedAt: DateTime(2026, 5, 13, 9),
      ),
    ];

    await tester.pumpWidget(
      _CommandBarHarness(
        commandController: TextEditingController(),
        appController: controller,
        onScreenCommand: (_) {},
        onNewChatSubmit: () {},
        onOpenSection: openedSections.add,
        onOpenSettingsSection: openedSettingsSections.add,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('global-command-input')),
    );
    await tester.pumpAndSettle();

    expect(find.text('PROFILES'), findsOneWidget);
    expect(find.text('RECENT CHATS'), findsOneWidget);
    expect(find.text('WORKSPACES'), findsNothing);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('All Chats'), findsOneWidget);
    expect(
      (tester.getTopLeft(find.text('Manage')).dx -
              tester.getTopLeft(find.text('Agent Awesome').last).dx)
          .abs(),
      lessThan(12),
    );
    expect(
      (tester.getTopLeft(find.text('All Chats')).dx -
              tester.getTopLeft(find.text('Weather information limitation')).dx)
          .abs(),
      lessThan(12),
    );
    final profileGap =
        tester.getTopLeft(find.text('RECENT CHATS')).dx -
        tester.getTopRight(find.text('Default profile')).dx;
    final recentGap =
        tester.getTopLeft(find.text('SETTINGS')).dx -
        tester.getTopRight(find.text('Weather information limitation')).dx;
    expect(profileGap, lessThan(140));
    expect((profileGap - recentGap).abs(), lessThan(80));
    expect(
      tester.getTopLeft(find.text('Manage')).dy -
          tester.getBottomLeft(find.text('Agent Awesome').last).dy,
      allOf(greaterThan(0), lessThan(48)),
    );
    expect(
      tester.getTopLeft(find.text('All Chats')).dy -
          tester.getBottomLeft(find.text('Weather information limitation')).dy,
      allOf(greaterThan(0), lessThan(48)),
    );

    await tester.tap(find.text('All Chats'));
    await tester.pumpAndSettle();

    expect(openedSections, <String>[AppSections.chat]);

    await tester.tap(
      find.byKey(const ValueKey<String>('global-command-input')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();

    expect(openedSettingsSections, <String>['Profiles']);
  });

  testWidgets('profile picker closes the command quick-access menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.runtimeProfilePath = '/tmp/personal.json';
    controller.availableProfiles = const <RuntimeProfileFileEntry>[
      RuntimeProfileFileEntry(
        path: '/tmp/personal.json',
        id: 'personal',
        label: 'Agent Awesome',
        active: true,
        runtimeKind: 'Local',
        memoryDomainLabels: <String>['memory'],
      ),
      RuntimeProfileFileEntry(
        path: '/tmp/work.json',
        id: 'work',
        label: 'Work',
        active: false,
        runtimeKind: 'Cloud',
        memoryDomainLabels: <String>['work'],
      ),
    ];

    await tester.pumpWidget(
      _CommandBarHarness(
        commandController: TextEditingController(),
        appController: controller,
        onScreenCommand: (_) {},
        onNewChatSubmit: () {},
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('global-command-input')),
    );
    await tester.pumpAndSettle();

    expect(find.text('RECENT CHATS'), findsOneWidget);

    await tester.tap(find.byTooltip('Active profile'));
    await tester.pumpAndSettle();

    expect(find.text('RECENT CHATS'), findsNothing);
    expect(find.text('Work'), findsOneWidget);
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
    this.appController,
    this.onOpenSetup,
    this.onOpenSection,
    this.onOpenSettingsSection,
  });

  final TextEditingController commandController;
  final ValueChanged<CommandContext> onScreenCommand;
  final VoidCallback onNewChatSubmit;
  final AgentAwesomeAppController? appController;

  /// Optional setup callback used by tests that exercise the status action.
  final VoidCallback? onOpenSetup;

  /// Optional workspace navigation callback used by quick-access tests.
  final ValueChanged<String>? onOpenSection;

  /// Optional settings navigation callback used by quick-access tests.
  final ValueChanged<String>? onOpenSettingsSection;

  /// Builds a minimal shell around the command bar.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CommandBar(
          commandController: commandController,
          appController:
              appController ?? AgentAwesomeAppController(config: _testConfig()),
          commandContext: (text, {String profilePath = ''}) => CommandContext(
            section: AppSections.backlog,
            area: 'Stream',
            text: text,
            profilePath: profilePath,
          ),
          onSubmitScreenCommand: (context) async => onScreenCommand(context),
          onSubmit: ({String profilePath = ''}) async => onNewChatSubmit(),
          onNewChat: () {},
          onToggleAssistantChat: () {},
          onStartChatWithProfile: (_) {},
          onSelectHistoryChat: (_) {},
          onOpenSection: onOpenSection ?? (_) {},
          onOpenSettingsSection: onOpenSettingsSection ?? (_) {},
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
          onToggleAssistantChat: () {},
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

/// Returns a cloud-style profile whose model is selected by the gateway.
RuntimeProfile _externalGatewayProfile() {
  return const RuntimeProfile(
    id: 'cloudflare-doug',
    label: 'Cloudflare Doug',
    harness: HarnessRuntime(
      id: 'cloudflare-harness',
      label: 'Cloudflare Harness',
      apiBaseUrl: 'http://127.0.0.1:18070/api',
      contextApiBaseUrl: 'http://127.0.0.1:18070/api/context',
      appName: 'agent_awesome',
      userId: 'doug',
      workingDirectory: '/tmp/harness',
      packagePath: './cmd/agent-awesome',
      modelConfigPath: '/tmp/external-model.yaml',
      agentConfigPath: '/tmp/agent.yaml',
      toolConfigPath: '/tmp/tool.yaml',
      port: 18070,
      autoStart: false,
    ),
    gateway: GatewayRuntime(
      id: 'cloudflare-gateway',
      label: 'Cloudflare Gateway',
      apiBaseUrl: 'http://127.0.0.1:18070/api',
      healthUrl: 'http://127.0.0.1:18070/healthz',
      workingDirectory: '/tmp/gateway',
      packagePath: './cmd/agent-gateway',
      harnessBaseUrl: 'http://127.0.0.1:18070/api',
      contextBaseUrl: 'http://127.0.0.1:18070/api/context',
      memoryMcpUrl: 'http://127.0.0.1:18070/mcp',
      appName: 'agent_awesome',
      userId: 'doug',
      profileId: 'doug',
      modelProviderId: 'openai',
      modelId: 'gpt-5.4-mini',
      port: 18070,
      autoStart: false,
      enabled: true,
    ),
    memoryDomains: <McpServerRuntime>[
      McpServerRuntime(
        id: 'doug',
        label: 'Doug Memory',
        kind: 'memory',
        endpoint: 'http://127.0.0.1:18070/mcp/doug',
        healthUrl: 'http://127.0.0.1:18070/healthz',
        workingDirectory: '',
        packagePath: '',
        dbPath: '',
        dataDir: '',
        arguments: <String>[],
        autoStart: false,
        enabled: true,
      ),
    ],
    agentMemory: AgentMemoryRuntime(
      actor: 'agent:doug',
      readDomains: <String>['doug'],
      writeDomains: <String>['doug'],
      defaultWriteDomain: 'doug',
      allowedSensitivities: <String>['public', 'internal', 'private'],
    ),
  );
}

/// Returns a local profile that relies on harness model configuration.
RuntimeProfile _personalProfile() {
  return const RuntimeProfile(
    id: 'personal',
    label: 'Personal',
    harness: HarnessRuntime(
      id: 'personal-harness',
      label: 'Personal Harness',
      apiBaseUrl: 'http://127.0.0.1:8080/api',
      contextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
      appName: 'agent_awesome',
      userId: 'doug',
      workingDirectory: '/tmp/harness',
      packagePath: './cmd/agent-awesome',
      modelConfigPath: '/tmp/model.yaml',
      agentConfigPath: '/tmp/agent.yaml',
      toolConfigPath: '/tmp/tool.yaml',
      port: 8080,
      autoStart: true,
    ),
    gateway: GatewayRuntime(
      id: 'personal-gateway',
      label: 'Personal Gateway',
      apiBaseUrl: 'http://127.0.0.1:8070/api',
      healthUrl: 'http://127.0.0.1:8070/healthz',
      workingDirectory: '/tmp/gateway',
      packagePath: './cmd/agent-gateway',
      harnessBaseUrl: 'http://127.0.0.1:8080/api',
      contextBaseUrl: 'http://127.0.0.1:8081/api/context',
      memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
      appName: 'agent_awesome',
      userId: 'doug',
      port: 8070,
      autoStart: true,
      enabled: true,
    ),
    memoryDomains: <McpServerRuntime>[
      McpServerRuntime(
        id: 'memory',
        label: 'Memory',
        kind: 'memory',
        endpoint: 'http://127.0.0.1:8090/mcp',
        healthUrl: 'http://127.0.0.1:8090/healthz',
        workingDirectory: '',
        packagePath: '',
        dbPath: '',
        dataDir: '',
        arguments: <String>[],
        autoStart: false,
        enabled: true,
      ),
    ],
    agentMemory: AgentMemoryRuntime(
      actor: 'agent:personal',
      readDomains: <String>['memory'],
      writeDomains: <String>['memory'],
      defaultWriteDomain: 'memory',
      allowedSensitivities: <String>['public', 'internal', 'private'],
    ),
  );
}
