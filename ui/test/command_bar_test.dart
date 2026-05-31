/// Tests the global command bar keyboard submission semantics.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/app_settings.dart';
import 'package:agentawesome_ui/app/config_files.dart';
import 'package:agentawesome_ui/ui/theme.dart';
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

  testWidgets('watch changes button toggles static and side-panel modes', (
    tester,
  ) async {
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      appSettingsStore: _MemoryAppSettingsStore(),
    );

    await tester.pumpWidget(
      _CommandBarHarness(
        commandController: TextEditingController(),
        appController: controller,
        onScreenCommand: (_) {},
        onNewChatSubmit: () {},
      ),
    );

    expect(find.byTooltip('Watching AI changes'), findsOneWidget);

    await tester.tap(find.byTooltip('Watching AI changes'));
    await tester.pumpAndSettle();

    expect(controller.watchWorkspaceChangesEnabled, isFalse);
    expect(find.byTooltip('AI changes stay in background'), findsOneWidget);

    await tester.tap(find.byTooltip('AI changes stay in background'));
    await tester.pumpAndSettle();

    expect(controller.watchWorkspaceChangesEnabled, isTrue);
    expect(find.byTooltip('Watching AI changes'), findsOneWidget);
  });

  testWidgets('hides setup badge for external gateway model metadata', (
    tester,
  ) async {
    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.appSettings = const AgentAwesomeAppSettings(
      gettingStartedCompleted: true,
    );
    controller.runtimeProfilePath = '/tmp/external_gateway.json';
    controller.runtimeProfile = _externalGatewayProfile();
    controller.availableModelConfigs = const <ConfigFileEntry>[];
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

  testWidgets('shows active agent picker in the top bar', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AgentAwesomeAppController(config: _testConfig());
    final openedSections = <String>[];
    controller.runtimeProfilePath = '/tmp/personal.json';
    controller.runtimeProfile = _personalProfile();
    controller.availableAgentConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: '/tmp/agent.yaml',
        kind: ConfigFileKind.agent,
        assigned: true,
        displayName: 'Personal',
      ),
      ConfigFileEntry(
        path: '/tmp/work-agent.yaml',
        kind: ConfigFileKind.agent,
        assigned: false,
        displayName: 'Work',
      ),
    ];

    await tester.pumpWidget(
      _CommandBarHarness(
        commandController: TextEditingController(),
        appController: controller,
        onScreenCommand: (_) {},
        onNewChatSubmit: () {},
        onOpenSection: openedSections.add,
      ),
    );

    expect(find.byTooltip('Active agent'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.byTooltip('Active memory'), findsOneWidget);
    expect(find.byTooltip('Views'), findsOneWidget);

    await tester.tap(find.byTooltip('Active agent'));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    expect(find.textContaining('work-agent'), findsOneWidget);

    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();

    expect(openedSections, <String>[AppSections.automationAgents]);
  });

  testWidgets('keeps top bar action spacing equal', (tester) async {
    tester.view.physicalSize = const Size(1800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.appSettings = const AgentAwesomeAppSettings(
      gettingStartedCompleted: true,
    );
    controller.runtimeProfilePath = '/tmp/personal.json';
    controller.runtimeProfile = _personalProfile();
    controller.availableAgentConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: '/tmp/agent.yaml',
        kind: ConfigFileKind.agent,
        assigned: true,
        displayName: 'Agent Awesome',
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

    final agentRect = tester.getRect(
      find.byKey(const ValueKey<String>('command-agent-picker')),
    );
    final memoryRect = tester.getRect(
      find.byKey(const ValueKey<String>('command-memory-picker')),
    );
    final viewRect = tester.getRect(
      find.byKey(const ValueKey<String>('command-workspace-view-picker')),
    );
    final watchRect = tester.getRect(find.byTooltip('Watching AI changes'));
    final themeRect = tester.getRect(
      find.byKey(const ValueKey<String>('command-theme-badge')),
    );
    final helpRect = tester.getRect(find.byTooltip('Help'));
    final chatRect = tester.getRect(find.byTooltip('AI chat'));
    final agentMemoryGap = memoryRect.left - agentRect.right;
    final memoryViewGap = viewRect.left - memoryRect.right;
    final viewWatchGap = watchRect.left - viewRect.right;
    final watchThemeGap = themeRect.left - watchRect.right;
    final themeHelpGap = helpRect.left - themeRect.right;
    final helpChatGap = chatRect.left - helpRect.right;

    expect(agentMemoryGap, closeTo(10, 0.1));
    expect(memoryViewGap, closeTo(agentMemoryGap, 0.1));
    expect(viewWatchGap, closeTo(agentMemoryGap, 0.1));
    expect(watchThemeGap, closeTo(agentMemoryGap, 0.1));
    expect(themeHelpGap, closeTo(agentMemoryGap, 0.1));
    expect(helpChatGap, closeTo(agentMemoryGap, 0.1));
  });

  testWidgets('help opens in-app dialog instead of external handler', (
    tester,
  ) async {
    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.appSettings = const AgentAwesomeAppSettings(
      gettingStartedCompleted: true,
    );

    await tester.pumpWidget(
      _CommandBarHarness(
        commandController: TextEditingController(),
        appController: controller,
        onScreenCommand: (_) {},
        onNewChatSubmit: () {},
      ),
    );

    await tester.tap(find.byTooltip('Help'));
    await tester.pumpAndSettle();

    expect(find.text('Agent Awesome Help'), findsOneWidget);
    expect(find.text('Copy docs link'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('quick access links agent management and all chats', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final openedSections = <String>[];
    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.runtimeProfilePath = '/tmp/personal.json';
    controller.runtimeProfile = _personalProfile();
    controller.availableAgentConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: '/tmp/agent.yaml',
        kind: ConfigFileKind.agent,
        assigned: true,
        displayName: 'Agent Awesome',
      ),
    ];
    controller.chatHistory = <ChatHistoryEntry>[
      ChatHistoryEntry(
        agentPath: '/tmp/agent.yaml',
        agentLabel: 'Agent Awesome',
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
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('global-command-input')),
    );
    await tester.pumpAndSettle();

    expect(find.text('AGENTS'), findsOneWidget);
    expect(find.text('RECENT CHATS'), findsOneWidget);
    expect(find.text('WORKSPACES'), findsNothing);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('Memory'), findsWidgets);
    expect(find.text('Tools'), findsNothing);
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
    final agentGap =
        tester.getTopLeft(find.text('RECENT CHATS')).dx -
        tester.getTopRight(find.text('Active agent')).dx;
    final recentGap =
        tester.getTopLeft(find.text('SETTINGS')).dx -
        tester.getTopRight(find.text('Weather information limitation')).dx;
    expect(agentGap, lessThan(140));
    expect((agentGap - recentGap).abs(), lessThan(80));
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

    expect(openedSections, <String>[
      AppSections.chat,
      AppSections.automationAgents,
    ]);
  });

  testWidgets('agent picker closes the command quick-access menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.runtimeProfilePath = '/tmp/personal.json';
    controller.runtimeProfile = _personalProfile();
    controller.availableAgentConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: '/tmp/agent.yaml',
        kind: ConfigFileKind.agent,
        assigned: true,
        displayName: 'Agent Awesome',
      ),
      ConfigFileEntry(
        path: '/tmp/work-agent.yaml',
        kind: ConfigFileKind.agent,
        assigned: false,
        displayName: 'Work',
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

    await tester.tap(find.byTooltip('Active agent'));
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

    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_outlined), findsNothing);

    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pump();

    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsNothing);
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
  });

  final TextEditingController commandController;
  final ValueChanged<CommandContext> onScreenCommand;
  final VoidCallback onNewChatSubmit;
  final AgentAwesomeAppController? appController;

  /// Optional setup callback used by tests that exercise the status action.
  final VoidCallback? onOpenSetup;

  /// Optional workspace navigation callback used by quick-access tests.
  final ValueChanged<String>? onOpenSection;

  /// Builds a minimal shell around the command bar.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CommandBar(
          commandController: commandController,
          appController:
              appController ?? AgentAwesomeAppController(config: _testConfig()),
          commandContext: (text) => CommandContext(
            section: AppSections.backlog,
            area: 'Stream',
            text: text,
          ),
          onSubmitScreenCommand: (context) async => onScreenCommand(context),
          onSubmit: () async => onNewChatSubmit(),
          onToggleAssistantChat: () {},
          onSelectHistoryChat: (_) {},
          onOpenSection: onOpenSection ?? (_) {},
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
          commandContext: (text) => CommandContext(
            section: AppSections.backlog,
            area: 'Stream',
            text: text,
          ),
          onSubmitScreenCommand: (_) async {},
          onSubmit: () async {},
          onToggleAssistantChat: () {},
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

class _MemoryAppSettingsStore extends AgentAwesomeAppSettingsStore {
  _MemoryAppSettingsStore();

  AgentAwesomeAppSettings saved = const AgentAwesomeAppSettings();

  /// Loads in-memory settings for command-bar tests.
  @override
  Future<AgentAwesomeAppSettings> load() async {
    return saved;
  }

  /// Persists in-memory settings for command-bar tests.
  @override
  Future<void> save(
    AgentAwesomeAppSettings settings, {
    Iterable<String> extraPolicyActors = const <String>[],
  }) async {
    saved = settings;
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

/// Returns an external profile whose model is selected by the gateway.
RuntimeProfile _externalGatewayProfile() {
  return const RuntimeProfile(
    id: 'external-shared',
    label: 'External Shared',
    harness: HarnessRuntime(
      id: 'external-harness',
      label: 'External Harness',
      apiBaseUrl: 'http://127.0.0.1:18070/api',
      contextApiBaseUrl: 'http://127.0.0.1:18070/api/context',
      appName: 'Agent Awesome',
      userId: 'doug',
      workingDirectory: '/tmp/harness',
      executablePath: '/tmp/bin/agent-awesome',
      modelConfigPath: '/tmp/external-model.yaml',
      agentConfigPath: '/tmp/agent.yaml',
      toolConfigPath: '/tmp/tool.yaml',
      port: 18070,
      autoStart: false,
    ),
    gateway: GatewayRuntime(
      id: 'external-gateway',
      label: 'External Gateway',
      apiBaseUrl: 'http://127.0.0.1:18070/api',
      healthUrl: 'http://127.0.0.1:18070/healthz',
      workingDirectory: '/tmp/gateway',
      executablePath: '/tmp/bin/agent-gateway',
      harnessBaseUrl: 'http://127.0.0.1:18070/api',
      contextBaseUrl: 'http://127.0.0.1:18070/api/context',
      memoryMcpUrl: 'http://127.0.0.1:18070/mcp',
      appName: 'Agent Awesome',
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
        executablePath: '',
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
      appName: 'Agent Awesome',
      userId: 'doug',
      workingDirectory: '/tmp/harness',
      executablePath: '/tmp/bin/agent-awesome',
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
      executablePath: '/tmp/bin/agent-gateway',
      harnessBaseUrl: 'http://127.0.0.1:8080/api',
      contextBaseUrl: 'http://127.0.0.1:8081/api/context',
      memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
      appName: 'Agent Awesome',
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
        executablePath: '',
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
