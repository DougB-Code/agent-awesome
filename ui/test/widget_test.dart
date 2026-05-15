/// Tests the primary Agent Awesome workspace widgets.
library;

import 'dart:ui' show PointerDeviceKind;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/file_import.dart';
import 'package:agentawesome_ui/app/app_settings.dart';
import 'package:agentawesome_ui/app/config_files.dart';
import 'package:agentawesome_ui/app/local_services.dart';
import 'package:agentawesome_ui/app/theme.dart';
import 'package:agentawesome_ui/domain/model_config.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:agentawesome_ui/domain/executive_summary.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/domain/screen_command.dart';
import 'package:agentawesome_ui/domain/today_state.dart';
import 'package:agentawesome_ui/features/today/widgets/today_schedule_card.dart';
import 'package:agentawesome_ui/ui/agent_awesome_shell.dart';
import 'package:agentawesome_ui/ui/onboarding/setup_wizard_shell.dart';
import 'package:agentawesome_ui/ui/panels/panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs widget tests for the shell.
void main() {
  testWidgets('renders Today screen without local demo data', (tester) async {
    final controller = _readyController();

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );

    expect(find.text('Here is what matters now.'), findsNothing);
    expect(find.byTooltip('Refresh Today'), findsNothing);
    expect(find.text('Decide'), findsOneWidget);
    expect(find.text('OPEN LOOP RADAR'), findsOneWidget);
    expect(find.text("TODAY'S ATTENTION"), findsOneWidget);
    expect(find.text('RISKS & COVERAGE'), findsOneWidget);
    expect(find.text('Prepare investor meeting brief'), findsNothing);
  });

  testWidgets('makes Today errors selectable and copyable', (tester) async {
    const error =
        'ClientException with SocketException: Connection refused, uri=http://127.0.0.1:8070/api/context/tools/call';
    var copied = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final data = call.arguments as Map<dynamic, dynamic>;
            copied = data['text'] as String? ?? '';
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final controller = _readyController()
      ..todayState = const TodayState(error: error);

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Copy error'));

    expect(find.widgetWithText(SelectableText, error), findsOneWidget);
    expect(copied, error);
  });

  testWidgets('renders populated Today lower sections without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1460, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..todayState = TodayState(projection: _populatedTodayProjection());
    controller.workspace = ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live connected workspace',
      tasks: <WorkspaceTask>[
        WorkspaceTask(
          id: 'scheduled-brief',
          title: 'Review weekly plan',
          detail: 'Scheduled today',
          done: false,
          scheduledAt: DateTime.now(),
          project: 'Planning',
        ),
      ],
      sources: const <SourceItem>[],
      memoryRecords: const <MemoryRecord>[],
    );

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('RISKS & COVERAGE'), findsOneWidget);
    expect(find.text('SCHEDULE'), findsOneWidget);
    expect(find.text('Review weekly plan'), findsWidgets);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.textContaining('Banking / Bills'), findsOneWidget);
    expect(find.text('Manage connections'), findsNothing);
    expect(
      tester.getTopLeft(find.text('RISKS & COVERAGE')).dy,
      lessThan(tester.getTopLeft(find.text("TODAY'S ATTENTION")).dy),
    );
    expect(
      tester.getTopLeft(find.text('SCHEDULE')).dy,
      greaterThan(tester.getTopLeft(find.text("TODAY'S ATTENTION")).dy),
    );
    expect(find.text('Data quality'), findsNothing);
    expect(find.textContaining('I only use information'), findsNothing);
    expect(find.textContaining('I will not infer'), findsNothing);
  });

  testWidgets('schedule opens nearest dated range when today is empty', (
    tester,
  ) async {
    final now = DateTime(2026, 5, 11, 9);
    final workspace = ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live connected workspace',
      tasks: <WorkspaceTask>[
        WorkspaceTask(
          id: 'calendar-rollup',
          title: 'Fix calendar rollup',
          detail: 'Due this week',
          done: false,
          dueAt: DateTime(2026, 5, 13, 17),
        ),
      ],
      sources: const <SourceItem>[],
      memoryRecords: const <MemoryRecord>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: TodayScheduleCard(
              workspace: workspace,
              projection: const ExecutiveSummaryProjection(),
              now: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fix calendar rollup'), findsWidgets);
    expect(find.text('Due'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('No scheduled items today'), findsNothing);

    await tester.tap(find.text('Today').first);
    await tester.pumpAndSettle();

    expect(find.text('Fix calendar rollup'), findsNothing);
    expect(find.text('No scheduled items today'), findsOneWidget);
  });

  testWidgets('opens Today attention view from execute metric', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..todayState = TodayState(projection: _attentionTodayProjection())
      ..workspace = _attentionWorkspace();

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Execute').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('3 items ready to execute'), findsOneWidget);
    expect(find.text('Buy Socks'), findsWidgets);
    expect(
      find.text('Small isolated errand with no date. Easy to forget.'),
      findsWidgets,
    );
    expect(find.text('ATTENTION DETAILS'), findsOneWidget);
    expect(find.text('Why this surfaced'), findsOneWidget);
    expect(find.text('QUEUE'), findsNothing);
  });

  testWidgets('opens Backlog with the command panel subshell', (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController(
      fileImporter: const _NoopFileImporter(),
    );
    controller.workspace = const ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live connected workspace',
      tasks: <WorkspaceTask>[
        WorkspaceTask(
          id: 'task-brief',
          title: 'Draft task brief',
          detail: 'Open',
          done: false,
          status: 'open',
          priority: 'normal',
        ),
      ],
      sources: <SourceItem>[],
      memoryRecords: <MemoryRecord>[],
    );
    controller.priorityTerrainProjection = const PriorityTerrainProjection(
      points: <PriorityTerrainPoint>[
        PriorityTerrainPoint(
          taskId: 'task-brief',
          title: 'Draft task brief',
          status: 'open',
          priority: 'normal',
          valueScore: 0.5,
          riskScore: 0.2,
          x: 0.5,
          y: 0.5,
        ),
      ],
    );
    controller.selectedTaskId = 'task-brief';

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Backlog').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Queue command panel'), findsNothing);
    expect(find.textContaining('visible of'), findsNothing);
    expect(find.text('Ready'), findsNothing);
    expect(find.text('New task'), findsNothing);
    expect(find.text('Inspector'), findsNothing);
    expect(find.text('Agent handoff 0'), findsNothing);
    expect(find.byTooltip('Refresh context'), findsNothing);
    expect(find.byTooltip('New backlog item'), findsOneWidget);
    expect(find.text('All insights'), findsNothing);
    expect(find.text('Open, Waiting, Blocked'), findsOneWidget);
    expect(find.text('Active tasks'), findsNothing);
    expect(find.text('Queue score'), findsNothing);
    expect(find.text('Schedule'), findsWidgets);
    expect(find.text('Mark done'), findsWidgets);
    expect(find.textContaining('Data quality'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('command-split-handle')),
      findsOneWidget,
    );
    expect(find.text('INSPECTOR'), findsOneWidget);
    expect(find.text('Draft task brief'), findsWidgets);
    expect(find.text('TASK'), findsOneWidget);

    await tester.tap(find.byTooltip('Stream'));
    await tester.pumpAndSettle();

    expect(find.text('Stream command panel'), findsNothing);
    expect(find.text('STREAM'), findsWidgets);
    expect(find.text('STREAM PROJECTION'), findsOneWidget);

    await tester.tap(find.byTooltip('Terrain'));
    await tester.pumpAndSettle();

    expect(find.text('TERRAIN'), findsWidgets);
    expect(find.text('All insights'), findsWidgets);
    expect(find.text('TERRAIN PROJECTION'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse details column'));
    await tester.pumpAndSettle();

    expect(find.text('TERRAIN'), findsWidgets);
    expect(find.text('Inspector'), findsNothing);
  });

  testWidgets('walks through first-launch model setup', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settingsStore = _MemoryAppSettingsStore();
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      appSettingsStore: settingsStore,
    );
    final profile = _settingsProfile();
    controller.runtimeProfile = profile.copyWith(
      harness: profile.harness.copyWith(
        modelConfigPath: '/tmp/onboarding-model.yaml',
      ),
    );
    controller.runtimeProfilePath = '/tmp/personal.json';

    await tester.pumpWidget(
      MaterialApp(home: SetupWizardShell(controller: controller)),
    );

    expect(
      find.byKey(const ValueKey<String>('getting-started-wizard')),
      findsOneWidget,
    );
    expect(find.text('Connect your model'), findsOneWidget);
    expect(find.text('Use API key'), findsOneWidget);
    expect(find.text('Run local model'), findsOneWidget);
    expect(find.textContaining('go run'), findsNothing);

    await tester.tap(find.text('Connect provider'));
    await tester.pumpAndSettle();

    expect(find.text('Add your API key'), findsOneWidget);
    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Verify connection'), findsOneWidget);

    await tester.tap(find.text('Use local model instead'));
    await tester.pumpAndSettle();

    expect(find.text('Run a local model'), findsOneWidget);
    expect(find.text('System check'), findsOneWidget);
    expect(find.textContaining('gemma-4-E2B-it.litertlm'), findsOneWidget);
    expect(find.textContaining('Apache-2.0'), findsOneWidget);
    expect(find.text('View source'), findsOneWidget);
    expect(find.text('Learn more'), findsNothing);
    expect(find.text('Download and continue'), findsOneWidget);
    expect(controller.gettingStartedCompleted, isFalse);
    expect(settingsStore.saved.gettingStartedCompleted, isFalse);
  });

  testWidgets('keeps the app shell chat unlocked during first setup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController(
      fileImporter: const _NoopFileImporter(),
    );
    controller.appSettings = const AgentAwesomeAppSettings();

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );

    expect(controller.hasConfiguredModel, isTrue);
    expect(controller.canStartChat, isTrue);
    expect(find.text('Connect your model'), findsNothing);
    expect(find.byTooltip('New chat'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('CONVERSATION'), findsOneWidget);
  });

  testWidgets('opens settings command workspace', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();
    controller.runtimeProfile = _settingsProfile();
    controller.runtimeProfilePath = '/tmp/personal.json';
    controller.availableProfiles = const <RuntimeProfileFileEntry>[
      RuntimeProfileFileEntry(
        path: '/tmp/personal.json',
        id: 'personal',
        label: 'Personal',
        active: true,
      ),
    ];
    controller.availableModelConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: '/tmp/summary-model.yaml',
        kind: ConfigFileKind.model,
        assigned: false,
        displayName: 'Summary Mini',
        modelChoices: <ModelConfigChoice>[
          ModelConfigChoice(
            providerId: 'openai',
            providerName: 'openai',
            modelId: 'gpt-mini',
            modelName: 'gpt-5-mini',
            isDefault: true,
          ),
        ],
      ),
    ];
    controller.availableToolConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: '/tmp/tool.yaml',
        kind: ConfigFileKind.tool,
        assigned: true,
        displayName: 'Personal Tools',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Settings').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Profiles'), findsWidgets);
    expect(find.text('App'), findsWidgets);
    expect(find.text('APP SETTINGS'), findsNothing);
    expect(find.text('CHAT DEFAULTS'), findsOneWidget);
    expect(find.text('Default profile'), findsOneWidget);
    expect(find.text('Personal'), findsWidgets);
    expect(find.text('APPLICATION MODELS'), findsOneWidget);
    expect(find.text('Summarize titles with a model.'), findsOneWidget);
    expect(find.text('Summary model'), findsOneWidget);
    expect(find.text('openai / gpt-mini'), findsOneWidget);

    await tester.tap(find.text('Profiles').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('ASSIGNMENTS'), findsOneWidget);
    expect(find.text('Model'), findsWidgets);
    expect(find.text('Agent'), findsWidgets);
    expect(find.text('Tools'), findsWidgets);
    expect(find.text('Memory'), findsWidgets);

    await tester.tap(find.text('Tools').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('OS Tools'), findsOneWidget);
    await tester.tap(find.text('TOOLS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('MCP Server'), findsOneWidget);
  });

  testWidgets('keeps selectors for editable single-item collection panels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollectionSwitcherPanel<String>(
            title: 'Agents',
            selectedId: 'agent',
            items: const <CollectionPanelItem<String>>[
              CollectionPanelItem<String>(
                id: 'agent',
                label: 'Agent Config',
                icon: Icons.psychology_outlined,
                value: 'agent',
              ),
            ],
            onSelect: (_) {},
            onCreate: () {},
            onDuplicate: (_) {},
            onDelete: (_) {},
            builder: (value, query) => Text('Selected $value'),
          ),
        ),
      ),
    );

    expect(find.text('Agent Config'), findsOneWidget);
    expect(find.byTooltip('Agent Config'), findsOneWidget);
    expect(find.byTooltip('Add'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollectionSwitcherPanel<String>(
            title: 'Memory',
            selectedId: 'memory',
            items: const <CollectionPanelItem<String>>[
              CollectionPanelItem<String>(
                id: 'memory',
                label: 'Memory Binding',
                icon: Icons.hub_outlined,
                value: 'memory',
              ),
            ],
            onSelect: (_) {},
            builder: (value, query) => Text('Selected $value'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Memory Binding'), findsNothing);
    expect(find.byTooltip('Memory Binding'), findsNothing);
    expect(find.byTooltip('Add'), findsNothing);
  });

  testWidgets('cycles multi-item collection panels from the title', (
    tester,
  ) async {
    var selected = 'first';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return CollectionSwitcherPanel<String>(
                title: 'Tools',
                selectedId: selected,
                items: const <CollectionPanelItem<String>>[
                  CollectionPanelItem<String>(
                    id: 'first',
                    label: 'OS Tools',
                    icon: Icons.terminal,
                    value: 'os-tools',
                  ),
                  CollectionPanelItem<String>(
                    id: 'second',
                    label: 'MCP Server',
                    icon: Icons.hub_outlined,
                    value: 'mcp-server',
                  ),
                ],
                onSelect: (id) => setState(() => selected = id),
                builder: (value, query) => Text('Selected $value'),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Selected os-tools'), findsOneWidget);
    await tester.tap(find.text('TOOLS'));
    await tester.pumpAndSettle();

    expect(find.text('Selected mcp-server'), findsOneWidget);
  });

  testWidgets('opens dedicated chat command shell', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();
    controller.runtimeProfile = _chatRuntimeProfile();
    controller.runtimeProfilePath = '/tmp/personal.json';
    controller.availableModelConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: '/tmp/model.yaml',
        kind: ConfigFileKind.model,
        assigned: true,
        displayName: 'Configured Model',
        modelChoices: <ModelConfigChoice>[
          ModelConfigChoice(
            providerId: 'openai',
            providerName: 'OpenAI',
            modelId: 'gpt-5-mini',
            modelName: 'GPT-5 Mini',
            isDefault: true,
          ),
          ModelConfigChoice(
            providerId: 'openai',
            providerName: 'OpenAI',
            modelId: 'gpt-5-pro',
            modelName: 'GPT-5 Pro',
            isDefault: false,
          ),
        ],
      ),
    ];
    controller.availableProfiles = const <RuntimeProfileFileEntry>[
      RuntimeProfileFileEntry(
        path: '/tmp/personal.json',
        id: 'personal',
        label: 'Personal',
        active: true,
      ),
    ];
    controller.sessions = <ChatSession>[
      ChatSession(
        id: 'session-live',
        title: 'Live chat',
        updatedAt: DateTime(2026, 4, 29, 9, 30),
      ),
      ChatSession(
        id: 'session-alt',
        title: 'Alternate planning chat',
        updatedAt: DateTime(2026, 4, 30, 7, 15),
      ),
    ];
    controller.selectedSessionId = 'session-live';
    controller.endpointStatuses = const <EndpointStatus>[
      EndpointStatus(
        name: 'Agent API',
        url: 'http://127.0.0.1:8080/api',
        state: ConnectionStateKind.connected,
        message: 'Connected',
      ),
      EndpointStatus(
        name: 'Memory',
        url: 'http://127.0.0.1:8070/mcp',
        state: ConnectionStateKind.connected,
        message: 'Today loaded',
      ),
      EndpointStatus(
        name: 'Project Memory',
        url: 'http://127.0.0.1:8071/mcp',
        state: ConnectionStateKind.connected,
        message: 'Connected',
      ),
    ];
    controller.localProcessStatuses = const <ServiceProcessStatus>[
      ServiceProcessStatus(
        name: 'Memory',
        url: 'http://127.0.0.1:8090/healthz',
        state: ConnectionStateKind.connected,
        message: 'Started locally',
      ),
      ServiceProcessStatus(
        name: 'Project Memory',
        url: 'http://127.0.0.1:8091/healthz',
        state: ConnectionStateKind.connected,
        message: 'Started locally',
      ),
      ServiceProcessStatus(
        name: 'Local Harness',
        url: 'http://127.0.0.1:8080/api/apps/test/users/user/sessions',
        state: ConnectionStateKind.connected,
        message: 'Started locally',
      ),
    ];
    controller.messages = <ChatMessage>[
      ChatMessage(
        id: 'message-1',
        role: ChatRole.assistant,
        author: 'Agent Awesome',
        text:
            'Connected chat message. Preference noted. Review Quarterly plan.pdf. Done - created Follow up report.',
        createdAt: DateTime(2026, 4, 29, 9, 31),
      ),
    ];
    controller.workspace = const ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live connected workspace',
      tasks: <WorkspaceTask>[
        WorkspaceTask(
          id: 'task-associated',
          title: 'Associated chat task',
          detail: 'Open',
          done: false,
          owner: 'Sam',
          idempotencyKey: 'agent_awesome:session-live:associated-chat-task',
        ),
        WorkspaceTask(
          id: 'task-unrelated',
          title: 'Unrelated chat task',
          detail: 'Open',
          done: false,
          idempotencyKey: 'agent_awesome:other-session:unrelated-chat-task',
        ),
        WorkspaceTask(
          id: 'task-mentioned',
          title: 'Follow up report',
          detail: 'Open',
          done: false,
        ),
      ],
      sources: <SourceItem>[
        SourceItem(
          id: '/docs/Quarterly plan.pdf',
          title: 'Quarterly plan.pdf',
          detail: '/docs/Quarterly plan.pdf',
        ),
      ],
      memoryRecords: <MemoryRecord>[
        MemoryRecord(
          id: 'cat-1',
          evidenceId: 'ev-1',
          title: 'Preference',
          summary: 'User prefers direct connected data.',
          kind: 'profile_fact',
          topics: <String>['ui'],
          sourceLabel: 'chat:1',
          sourceSystem: 'chat',
          sourceId: 'session-live',
          entityNames: <String>['Alex'],
        ),
        MemoryRecord(
          id: 'chat-message-1',
          evidenceId: 'chat-message-ev-1',
          title: 'Chat message from user in session-live',
          summary: 'A raw chat transcript row.',
          kind: 'conversation',
          topics: <String>['conversation'],
          sourceLabel: 'google_adk_session:session-live',
          sourceSystem: 'google_adk_session',
          sourceId: 'session-live',
        ),
        MemoryRecord(
          id: 'file-1',
          evidenceId: 'file-ev-1',
          title: 'Quarterly plan.pdf',
          summary: 'Planning file used in the current chat.',
          kind: 'document',
          topics: <String>['planning'],
          sourceLabel: 'local_file:/docs/Quarterly plan.pdf',
          sourceSystem: 'filesystem',
          sourceId: '/docs/Quarterly plan.pdf',
          rawPath: 'sources/file-ev-1.txt',
          rawMediaType: 'application/pdf',
          subjects: <String>['TODO.md'],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('CONVERSATION'), findsOneWidget);
    expect(find.text('MEMORY'), findsWidgets);
    expect(find.byTooltip('Memory'), findsOneWidget);
    expect(find.byTooltip('Tasks'), findsOneWidget);
    expect(find.byTooltip('Files'), findsOneWidget);
    expect(find.byTooltip('People'), findsOneWidget);
    expect(find.byTooltip('Runtime'), findsOneWidget);
    expect(find.text('Preference'), findsOneWidget);
    expect(find.text('Chat message from user in session-live'), findsNothing);
    expect(find.byTooltip('Select chat'), findsOneWidget);
    expect(find.byTooltip('Delete selected chat'), findsOneWidget);
    expect(find.byTooltip('New chat with profile'), findsNothing);
    expect(find.byTooltip('Chats'), findsNothing);
    expect(find.byTooltip('Sessions'), findsNothing);
    expect(find.text('Live chat'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    expect(
      find.text(
        'Connected chat message. Preference noted. Review Quarterly plan.pdf. Done - created Follow up report.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('MEMORY').first);
    await tester.pumpAndSettle();

    expect(find.text('TASKS'), findsWidgets);
    expect(find.text('Associated chat task'), findsOneWidget);
    expect(find.text('Follow up report'), findsWidgets);

    await tester.tap(find.byTooltip('Files'));
    await tester.pumpAndSettle();

    expect(find.text('FILES'), findsWidgets);
    expect(find.text('Quarterly plan.pdf'), findsOneWidget);

    await tester.tap(find.byTooltip('People'));
    await tester.pumpAndSettle();

    expect(find.text('PEOPLE'), findsWidgets);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('TODO.md'), findsNothing);

    await tester.tap(find.byTooltip('Runtime'));
    await tester.pumpAndSettle();

    expect(find.text('Selected model'), findsOneWidget);
    expect(find.text('OpenAI / gpt-5-mini - GPT-5 Mini'), findsOneWidget);
    expect(find.text('Selected for this chat'), findsNothing);
    expect(find.text('Available model'), findsOneWidget);
    expect(find.text('Can select before sending'), findsNothing);
    expect(find.text('OpenAI / gpt-5-pro - GPT-5 Pro'), findsOneWidget);
    expect(find.text('Memory'), findsWidgets);
    expect(find.text('Project Memory'), findsOneWidget);
    expect(find.textContaining('Today loaded'), findsNothing);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Personal'), findsWidgets);
    expect(
      tester.getTopLeft(find.text('Profile')).dy,
      lessThan(tester.getTopLeft(find.text('Selected model')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Selected model')).dy,
      lessThan(tester.getTopLeft(find.text('Project Memory')).dy),
    );
    expect(find.text('Local Harness'), findsNothing);
    expect(find.text('Agent API'), findsNothing);
    expect(find.text('Local processes'), findsNothing);
    expect(find.text('Service endpoints'), findsNothing);

    expect(find.byTooltip('Copy message'), findsOneWidget);
    expect(find.text('Message Agent Awesome in this chat...'), findsOneWidget);
    expect(find.byTooltip('Chat model'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('chat-thread-model-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI / gpt-5-pro'));
    await tester.pumpAndSettle();
    expect(controller.activeChatModelRef, 'openai:gpt-5-pro');
    expect(
      find.text('Command current screen, Ctrl/Shift+Enter for chat...'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('global-command-input')),
    );
    await tester.pump();
    expect(find.text('PROFILES'), findsOneWidget);
    expect(find.text('RECENT CHATS'), findsOneWidget);
    expect(find.text('WORKSPACES'), findsNothing);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('All Chats'), findsOneWidget);
    expect(find.text('Personal'), findsWidgets);
    await tester.tap(find.text('Personal').last);
    await tester.pumpAndSettle();
    expect(find.text('PROFILES'), findsOneWidget);
    expect(find.text('Selected for new chat'), findsOneWidget);
    final globalInput = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('global-command-input')),
    );
    expect(globalInput.focusNode?.hasFocus, isTrue);
    await tester.enterText(
      find.byKey(const ValueKey<String>('global-command-input')),
      'Start from selected profile',
    );
    await tester.pump();
    expect(find.text('PROFILES'), findsNothing);
    await tester.tap(find.byTooltip('People'));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    await tester.tap(find.byTooltip('Memory'));
    await tester.pumpAndSettle();
    expect(find.text('MEMORY'), findsWidgets);
    expect(find.text('Preference'), findsWidgets);
    expect(find.text('Chat message from user in session-live'), findsNothing);
    await tester.tap(find.byTooltip('Tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Associated chat task'), findsOneWidget);
    expect(find.text('Follow up report'), findsOneWidget);
    expect(find.text('Unrelated chat task'), findsNothing);
    await tester.tap(find.byTooltip('Select chat'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('search-picker-filter')),
      findsOneWidget,
    );
    expect(find.byTooltip('Delete chat'), findsWidgets);
    expect(find.text('Alternate planning chat'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('search-picker-filter')),
      'alt',
    );
    await tester.pump();
    expect(find.text('Alternate planning chat'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Live chat'),
      ),
      findsNothing,
    );
  });

  testWidgets('opens chat timeline at the latest message', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();
    controller.selectedSessionId = 'session-live';
    controller.sessions = <ChatSession>[
      ChatSession(
        id: 'session-live',
        title: 'Live chat',
        updatedAt: DateTime(2026, 5, 14, 20),
      ),
    ];
    controller.messages = <ChatMessage>[
      for (var index = 0; index < 30; index++)
        ChatMessage(
          id: 'message-$index',
          role: ChatRole.assistant,
          author: 'Agent Awesome',
          text: 'Timeline message $index',
          createdAt: DateTime(2026, 5, 14, 20, index % 60),
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    final timeline = tester.widget<ListView>(
      find.descendant(
        of: find.byType(ChatPanel),
        matching: find.byType(ListView),
      ),
    );
    final scrollController = timeline.controller!;

    expect(scrollController.offset, scrollController.position.maxScrollExtent);
    expect(find.text('Timeline message 29'), findsOneWidget);
  });

  testWidgets('keeps chat navigation unlocked without a configured model', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _unconfiguredModelController();

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );

    expect(controller.hasConfiguredModel, isFalse);
    expect(controller.canStartChat, isTrue);
    expect(find.byTooltip('New chat'), findsOneWidget);
    expect(find.text('Setup incomplete'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('CONVERSATION'), findsOneWidget);

    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();
    expect(find.text('SEARCH'), findsOneWidget);
    expect(find.text('No memory records'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('global-command-input')),
    );
    await tester.pump();
    expect(find.text('No profiles configured'), findsNothing);
    expect(find.text('Chat'), findsWidgets);
  });

  testWidgets('opens memory stewardship workspace', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();
    controller.workspace = _memoryWorkspace();

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('SEARCH'), findsOneWidget);
    expect(find.text('OVERVIEW'), findsOneWidget);
    expect(find.text('Preference'), findsWidgets);
    expect(find.text('MEMORY'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsNothing);
    await tester.tap(find.byTooltip('Metadata'));
    await tester.pumpAndSettle();

    expect(find.text('METADATA REPAIR'), findsOneWidget);

    await tester.tap(find.byTooltip('Pages'));
    await tester.pumpAndSettle();

    expect(find.text('PAGE TOOLS'), findsOneWidget);
    expect(find.text('No compiled page loaded'), findsOneWidget);

    await tester.tap(find.byTooltip('Browse'));
    await tester.pumpAndSettle();

    expect(find.text('Adk Chat'), findsNothing);
    expect(find.text('Chat'), findsWidgets);
  });

  testWidgets('shows memory safety event history', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();
    controller.memorySafetyEvents = <MemorySafetyEvent>[
      MemorySafetyEvent(
        id: 'event-1',
        kind: 'blocked_export',
        severity: 'warning',
        title: 'Export blocked',
        detail: 'Marriage cannot write to Side Project',
        sourceDomain: 'memory',
        targetDomain: 'memory',
        sourceMemoryId: 'liquid-capital',
        createdAt: DateTime(2026, 5, 12, 10),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Safety'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('SAFETY'), findsOneWidget);
    expect(find.text('Export blocked'), findsOneWidget);
    expect(find.text('Marriage cannot write to Side Project'), findsOneWidget);
    expect(find.text('liquid-capital'), findsOneWidget);
  });

  testWidgets('shows memory-backed route errors as generic pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();
    controller.memoryMessage =
        'Memory: McpException: HTTP 401 from http://127.0.0.1:8070/api/context/tools/call';

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );

    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();
    expect(find.text('Memory service unavailable'), findsOneWidget);
    expect(find.text('Connection failed'), findsOneWidget);
    expect(find.textContaining('HTTP 401'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('SEARCH'), findsNothing);
    expect(find.text('OVERVIEW'), findsNothing);
    expect(find.text('No memory records'), findsNothing);

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    expect(find.text('Memory service unavailable'), findsOneWidget);
    expect(find.text('No entities in memory'), findsNothing);
  });

  testWidgets('shows file manager with add-file empty action', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController(
      fileImporter: const _NoopFileImporter(),
    );

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('FILES'), findsOneWidget);
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('No files indexed yet'), findsWidgets);
    expect(find.textContaining('PDFs, spreadsheets, images'), findsWidgets);
    expect(find.text('Add file'), findsOneWidget);
    expect(find.byTooltip('Refresh files'), findsNothing);
    expect(find.text('Immutable source material from memory.'), findsNothing);
    expect(find.text('No source content loaded'), findsNothing);

    await tester.tap(find.text('Add file'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('File import is not connected yet'), findsNothing);
    expect(controller.memoryMessage, 'File import canceled');
  });

  testWidgets('shows only file records in the Files section', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();
    controller.workspace = const ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live connected workspace',
      tasks: <WorkspaceTask>[],
      sources: <SourceItem>[],
      memoryRecords: <MemoryRecord>[
        MemoryRecord(
          id: 'chat-memory',
          evidenceId: 'chat-evidence',
          title: 'Chat message from user in abc123',
          summary: 'Please remember to buy coffee.',
          kind: 'conversation',
          topics: <String>['conversation'],
          sourceLabel: 'google_adk_session:abc123',
          sourceSystem: 'google_adk_session',
          sourceId: 'abc123',
        ),
        MemoryRecord(
          id: 'file-memory',
          evidenceId: 'file-evidence',
          title: 'Quarterly budget',
          summary: 'Agent Awesome file evidence name: quarterly-budget.xlsx',
          kind: 'document',
          topics: <String>['finance'],
          sourceLabel: 'filesystem:/docs/quarterly-budget.xlsx',
          sourceSystem: 'filesystem',
          sourceId: '/docs/quarterly-budget.xlsx',
          rawPath: 'evidence/file-evidence.txt',
          rawMediaType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('quarterly-budget.xlsx'), findsWidgets);
    expect(find.text('Evidence id'), findsNothing);
    expect(find.textContaining('file evidence'), findsNothing);
    expect(find.textContaining('evidence/file-evidence.txt'), findsNothing);
    expect(find.text('Chat message from user in abc123'), findsNothing);
    expect(find.text('Sheets 1'), findsOneWidget);
  });

  testWidgets('shows contact manager from memory tasks and commitments', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();
    controller.workspace = ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live connected workspace',
      tasks: <WorkspaceTask>[
        WorkspaceTask(
          id: 'task-mina',
          title: 'Review launch checklist',
          detail: 'Open',
          done: false,
          status: 'open',
          priority: 'high',
          owner: 'Mina',
          project: 'Launch',
          topics: <String>['launch'],
        ),
      ],
      sources: const <SourceItem>[],
      memoryRecords: const <MemoryRecord>[
        MemoryRecord(
          id: 'mem-doug',
          evidenceId: 'ev-doug',
          title: 'Preference',
          summary: 'Doug likes concise UI.',
          kind: 'profile_fact',
          topics: <String>['ui'],
          sourceLabel: 'chat:1',
          entityIds: <String>['ent-doug'],
          entityNames: <String>['Doug'],
        ),
        MemoryRecord(
          id: 'mem-sam-fishing',
          evidenceId: 'ev-sam-fishing',
          title: 'Fishing trip plan',
          summary: 'Sam is bringing the canoe.',
          kind: 'profile_fact',
          firewall: 'user',
          subjects: <String>['people', 'Fishing trip'],
          topics: <String>['fishing'],
          sourceLabel: 'chat:2',
          entityIds: <String>['ent-sam'],
          entityNames: <String>['Sam'],
        ),
      ],
    );
    controller.taskCommitments = const <TaskCommitment>[
      TaskCommitment(
        id: 'commit-sam',
        taskId: 'task-sam',
        people: <String>['Sam'],
        project: 'Launch',
        responsibility: 'Reviews the customer promise',
        hardness: 'hard',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();

    expect(find.text('CONTACTS'), findsOneWidget);
    expect(find.text('PROFILE'), findsWidgets);
    expect(find.text('All contacts 3'), findsOneWidget);
    expect(find.text('Active 1'), findsOneWidget);
    expect(find.text('Multi-context 1'), findsOneWidget);
    expect(find.text('Commitments 1'), findsOneWidget);
    expect(find.text('Sources 2'), findsOneWidget);
    expect(find.text('Mina'), findsWidgets);
    expect(find.text('Sam'), findsWidgets);
    expect(find.byTooltip('Refresh contacts'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('command-subshell-filter')),
      'sam',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sam').first);
    await tester.tap(find.text('Sam').first);
    await tester.pumpAndSettle();
    expect(find.text('Sam is bringing the canoe.'), findsWidgets);
    expect(find.text('Entity id'), findsOneWidget);
    expect(find.text('ent-sam'), findsOneWidget);

    await tester.tap(find.byTooltip('Sources'));
    await tester.pumpAndSettle();
    expect(find.text('Fishing trip plan'), findsOneWidget);
    expect(find.text('chat:2'), findsOneWidget);

    await tester.tap(find.byTooltip('Contexts'));
    await tester.pumpAndSettle();
    expect(find.text('Project / Launch'), findsWidgets);
    expect(find.text('User / Fishing trip'), findsWidgets);
    expect(find.text('Sam is bringing the canoe.'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey<String>('command-subshell-filter')),
      'mina',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Mina').first);
    await tester.tap(find.text('Mina').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Review launch checklist'), findsOneWidget);
  });

  testWidgets('opens contact capture dialog from empty People section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    expect(find.text('No contacts yet'), findsOneWidget);

    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();

    expect(find.text('Add Contact'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Context'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('Topics'), findsOneWidget);
  });

  testWidgets('opens backlog workspace with queue and inspector', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();
    controller.workspace = const ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live connected workspace',
      tasks: <WorkspaceTask>[
        WorkspaceTask(
          id: 'task-brief',
          title: 'Draft task brief',
          detail: 'Open',
          done: false,
          status: 'open',
          priority: 'high',
          topics: <String>['brief'],
        ),
      ],
      sources: <SourceItem>[],
      memoryRecords: <MemoryRecord>[],
    );
    controller.taskStreamProjection = const TaskStreamProjection(
      lanes: <TaskStreamLane>[
        TaskStreamLane(
          id: 'now',
          title: 'Now',
          subtitle: 'Ready work',
          cards: <TaskStreamCard>[
            TaskStreamCard(
              taskId: 'task-brief',
              title: 'Analyze stream layout',
              status: 'open',
              priority: 'high',
              context: 'Focus',
              readyNow: true,
              estimateMinutes: 45,
            ),
          ],
        ),
        TaskStreamLane(
          id: 'next',
          title: 'Next',
          subtitle: 'Soon',
          cards: <TaskStreamCard>[
            TaskStreamCard(
              taskId: 'task-follow-up',
              title: 'Review canvas polish',
              status: 'open',
              priority: 'normal',
              context: 'Admin',
              estimateMinutes: 20,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Backlog').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('QUEUE'), findsOneWidget);
    expect(find.text('INSPECTOR'), findsOneWidget);
    expect(find.text('Draft task brief'), findsWidgets);
    expect(find.byTooltip('Delete backlog item'), findsNothing);
    expect(find.text('Delete'), findsWidgets);
    expect(find.text('Backlog Stream'), findsNothing);
    expect(find.byTooltip('Stream'), findsOneWidget);
    expect(find.byTooltip('Terrain'), findsOneWidget);
    expect(find.byTooltip('Constellation'), findsOneWidget);
    await tester.tap(find.byTooltip('Stream'));
    await tester.pumpAndSettle();
    expect(find.text('STREAM'), findsWidgets);
    expect(find.text('STREAM PROJECTION'), findsOneWidget);
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('Analyze stream layout'), findsOneWidget);
    expect(find.text('Backlog Stream'), findsNothing);
    expect(find.text('Workload'), findsNothing);
    await tester.tap(find.byTooltip('Queue'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Memory'), findsOneWidget);
    await tester.tap(find.byTooltip('Memory'));
    await tester.pumpAndSettle();
    expect(find.text('No memory selected'), findsOneWidget);
    expect(find.text('No linked memory'), findsOneWidget);
    await tester.tap(find.byTooltip('Inspector').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draft task brief').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pick Due date'), findsOneWidget);
    expect(find.byTooltip('Pick Scheduled date'), findsOneWidget);
    await tester.tap(find.byTooltip('Stream'));
    await tester.pumpAndSettle();
    expect(find.text('STREAM'), findsWidgets);
    expect(find.byTooltip('Collapse command column'), findsOneWidget);
    expect(find.byTooltip('Collapse details column'), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse command column'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand column'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand column'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Terrain'));
    await tester.pumpAndSettle();
    expect(find.text('TERRAIN'), findsWidgets);
    expect(find.text('TERRAIN PROJECTION'), findsOneWidget);
  });

  testWidgets(
    'shows Backlog AI review changes and restores inspector on task tap',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _readyController();
      controller.workspace = const ProjectWorkspace(
        title: 'Workspace',
        subtitle: 'Live connected workspace',
        tasks: <WorkspaceTask>[
          WorkspaceTask(
            id: 'task-brief',
            title: 'Draft task brief',
            detail: 'Open',
            done: false,
            status: 'open',
            priority: 'normal',
          ),
        ],
        sources: <SourceItem>[],
        memoryRecords: <MemoryRecord>[],
      );
      controller.activeScreenCommandRun = ScreenCommandRun(
        id: 'run-1',
        command: 'make it high priority',
        intent: ScreenCommandIntent.change,
        confidence: 0.9,
        createdAt: DateTime(2026, 5, 5),
        changes: const <ScreenChange>[
          ScreenChange(
            id: 'change-1',
            operation: ScreenChangeOperation.updateTask,
            target: ScreenChangeTarget(taskId: 'task-brief'),
            summary: 'Priority changed to high',
            confidence: 0.8,
            beforeValues: <String, dynamic>{'priority': 'normal'},
            afterValues: <String, dynamic>{'priority': 'high'},
            safety: ScreenChangeSafety.needsReview,
          ),
        ],
      );
      controller.backlogReviewPanelOpen = true;

      await tester.pumpWidget(
        MaterialApp(home: AgentAwesomeShell(controller: controller)),
      );
      await tester.tap(find.text('Backlog').first);
      await tester.pumpAndSettle();

      expect(find.text('Review Changes'), findsOneWidget);
      expect(find.text('Priority changed to high'), findsWidgets);
      await tester.tap(find.byTooltip('Focus change'));
      await tester.pumpAndSettle();
      expect(controller.focusedBacklogTaskId, 'task-brief');

      await tester.tap(find.text('Draft task brief').first);
      await tester.pumpAndSettle();

      expect(find.text('INSPECTOR'), findsOneWidget);
      expect(controller.backlogReviewPanelOpen, isFalse);
    },
  );

  testWidgets('shows Backlog chat as a third screen-command pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();
    controller.workspace = const ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live connected workspace',
      tasks: <WorkspaceTask>[
        WorkspaceTask(
          id: 'task-brief',
          title: 'Draft task brief',
          detail: 'Open',
          done: false,
        ),
      ],
      sources: <SourceItem>[],
      memoryRecords: <MemoryRecord>[],
    );
    controller.backlogChatPanelOpen = true;
    controller.messages = <ChatMessage>[
      ChatMessage(
        id: 'msg-1',
        role: ChatRole.user,
        author: 'You',
        text: 'What changed here?',
        createdAt: DateTime(2026, 5, 5),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Backlog').first);
    await tester.pumpAndSettle();

    expect(find.text('QUEUE'), findsOneWidget);
    expect(find.text('INSPECTOR'), findsOneWidget);
    expect(find.text('CONVERSATION'), findsOneWidget);
    expect(find.text('What changed here?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('global-command-input')),
      findsOneWidget,
    );
    expect(find.byTooltip('New chat'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsNothing);
  });

  testWidgets('keeps quick access stable when Backlog opens a third pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();
    controller.workspace = const ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live connected workspace',
      tasks: <WorkspaceTask>[
        WorkspaceTask(
          id: 'task-brief',
          title: 'Draft task brief',
          detail: 'Open',
          done: false,
        ),
      ],
      sources: <SourceItem>[],
      memoryRecords: <MemoryRecord>[],
    );

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Backlog').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('global-command-input')),
    );
    await tester.pump();
    expect(find.text('PROFILES'), findsOneWidget);

    controller.backlogChatPanelOpen = true;
    controller.notifyListeners();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('CONVERSATION'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('global-command-input')),
      findsOneWidget,
    );
    expect(
      find.text('Command current screen, Ctrl/Shift+Enter for chat...'),
      findsOneWidget,
    );
  });

  testWidgets('hides workflow and timeline routes for v1', (tester) async {
    final controller = _readyController();

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('WORK MANAGEMENT'), findsNothing);
    expect(find.text('Workflows'), findsNothing);
    expect(find.text('Timeline'), findsNothing);
    expect(find.text('View timeline'), findsNothing);
  });

  testWidgets('collapses sidebar without layout overflow', (tester) async {
    final controller = _readyController();

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('collapsed-sidebar-logo')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.text('AGENT AWESOME'), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer();
    await gesture.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('collapsed-sidebar-logo-button')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_double_arrow_right), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('collapsed-sidebar-logo-button')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('AGENT'), findsOneWidget);
    expect(find.text('AWESOME'), findsOneWidget);
  });
}

AgentAwesomeAppController _readyController({AgentFileImporter? fileImporter}) {
  final controller = AgentAwesomeAppController(
    config: _testConfig(),
    fileImporter: fileImporter,
  );
  controller.appSettings = const AgentAwesomeAppSettings(
    gettingStartedCompleted: true,
  );
  controller.runtimeProfile = _settingsProfile();
  controller.runtimeProfilePath = '/tmp/personal.json';
  controller.availableModelConfigs = const <ConfigFileEntry>[
    ConfigFileEntry(
      path: '/tmp/model.yaml',
      kind: ConfigFileKind.model,
      assigned: true,
      displayName: 'Configured Model',
      modelChoices: <ModelConfigChoice>[
        ModelConfigChoice(
          providerId: 'openai',
          providerName: 'OpenAI',
          modelId: 'gpt-5-mini',
          modelName: 'GPT-5 Mini',
          isDefault: true,
        ),
      ],
    ),
  ];
  return controller;
}

class _NoopFileImporter implements AgentFileImporter {
  const _NoopFileImporter();

  /// Returns null to simulate canceling the file picker.
  @override
  Future<ImportedAgentFile?> pickFile() async {
    return null;
  }
}

ExecutiveSummaryProjection _populatedTodayProjection() {
  return const ExecutiveSummaryProjection(
    metrics: <SummaryMetric>[
      SummaryMetric(
        id: 'decisions',
        label: 'Decide',
        value: '0',
        subtitle: 'Need your judgment',
      ),
      SummaryMetric(
        id: 'actions',
        label: 'Execute',
        value: '0',
        subtitle: 'Ready to act',
      ),
      SummaryMetric(
        id: 'relationships',
        label: 'Follow-ups',
        value: '0',
        subtitle: 'People or promises',
      ),
      SummaryMetric(
        id: 'agent_can_handle',
        label: 'Agent can handle',
        value: '0',
        subtitle: 'Ready to act',
      ),
      SummaryMetric(
        id: 'picture_quality',
        label: 'Data quality',
        value: 'Partial',
        subtitle: 'Some gaps known',
      ),
    ],
    timeHorizon: TimeHorizonProjection(
      buckets: <TimeHorizonBucket>[
        TimeHorizonBucket(id: 'now', label: 'Now', count: 0, summary: 'Clear'),
        TimeHorizonBucket(
          id: 'next',
          label: 'Next',
          count: 0,
          summary: 'No priority queued',
        ),
        TimeHorizonBucket(
          id: 'today',
          label: 'Today',
          count: 3,
          summary: 'High focus',
        ),
        TimeHorizonBucket(
          id: 'tomorrow',
          label: 'Tomorrow',
          count: 1,
          summary: 'Medium focus',
        ),
        TimeHorizonBucket(
          id: 'this_week',
          label: 'This Week',
          count: 6,
          summary: 'Plan ahead',
        ),
      ],
    ),
    coverage: CoverageProjection(
      good: <String>['Tasks & projects', 'Commitments'],
      partial: <String>[
        'No task relations recorded',
        'Some missing people context',
        '3 tasks missing due dates',
        '3 tasks missing projects',
      ],
      notConnected: <String>[
        'Calendar',
        'Email',
        'Health / Sleep',
        'Banking / Bills',
      ],
    ),
    quality: ProjectionQualitySummary(label: 'Partial', taskCount: 3),
  );
}

/// Returns a Today projection with explainable attention rows.
ExecutiveSummaryProjection _attentionTodayProjection() {
  return const ExecutiveSummaryProjection(
    generatedAt: null,
    metrics: <SummaryMetric>[
      SummaryMetric(
        id: 'decisions',
        label: 'Decide',
        value: '1',
        subtitle: 'Need your judgment',
        link: ProjectionLink(route: '/attention?metric=decisions'),
      ),
      SummaryMetric(
        id: 'actions',
        label: 'Execute',
        value: '3',
        subtitle: 'Ready to act',
        link: ProjectionLink(route: '/attention?metric=actions'),
      ),
      SummaryMetric(
        id: 'relationships',
        label: 'Follow-ups',
        value: '0',
        subtitle: 'People or promises',
        link: ProjectionLink(route: '/attention?metric=relationships'),
      ),
    ],
    attention: AttentionProjection(
      items: <ExecutiveSummaryItem>[
        ExecutiveSummaryItem(
          id: 'attention:do:task_buy_socks',
          kind: 'task',
          lane: 'do',
          title: 'Buy Socks',
          subtitle: 'Small isolated errand with no date.',
          reason: 'Small isolated errand with no date. Easy to forget.',
          score: 0.82,
          confidence: 0.78,
          status: 'open',
          priority: 'normal',
          taskId: 'task_buy_socks',
          estimateMinutes: 5,
          primaryAction: ExecutiveSummaryAction(
            label: 'Mark done',
            tool: 'complete_task',
            safety: 'safe',
            payload: <String, dynamic>{'task_id': 'task_buy_socks'},
          ),
          evidence: <ExecutiveSummaryEvidence>[
            ExecutiveSummaryEvidence(
              kind: 'task',
              id: 'task_buy_socks',
              label: 'Open task',
            ),
          ],
          links: <ProjectionLink>[
            ProjectionLink(route: '/attention?item=task_buy_socks'),
          ],
        ),
        ExecutiveSummaryItem(
          id: 'attention:protect:task_forecast',
          kind: 'task',
          lane: 'protect',
          title: 'Collect forecast inputs',
          reason: 'Waiting on Alex before the budget decision can move.',
          score: 0.72,
          confidence: 0.71,
          status: 'blocked',
          priority: 'high',
          taskId: 'task_forecast',
          primaryAction: ExecutiveSummaryAction(label: 'Nudge Alex'),
        ),
        ExecutiveSummaryItem(
          id: 'attention:do:task_coffee',
          kind: 'task',
          lane: 'do',
          title: 'Buy more coffee',
          reason: 'Small household item with no schedule.',
          score: 0.58,
          confidence: 0.68,
          status: 'open',
          priority: 'normal',
          taskId: 'task_coffee',
          primaryAction: ExecutiveSummaryAction(label: 'Add to groceries'),
        ),
        ExecutiveSummaryItem(
          id: 'attention:decide:task_budget',
          kind: 'task',
          lane: 'decide',
          title: 'Budget decision',
          reason: 'Needs your approval.',
          score: 0.67,
          confidence: 0.7,
          status: 'open',
          priority: 'high',
          taskId: 'task_budget',
        ),
      ],
    ),
  );
}

/// Returns workspace tasks linked to the attention projection fixture.
ProjectWorkspace _attentionWorkspace() {
  return const ProjectWorkspace(
    title: 'Workspace',
    subtitle: 'Live connected workspace',
    tasks: <WorkspaceTask>[
      WorkspaceTask(
        id: 'task_buy_socks',
        title: 'Buy Socks',
        detail: 'Open',
        done: false,
        status: 'open',
        priority: 'normal',
        description: 'Buy socks',
        estimateMinutes: 5,
        topics: <String>['Errands', 'Personal'],
      ),
      WorkspaceTask(
        id: 'task_forecast',
        title: 'Collect forecast inputs',
        detail: 'Blocked',
        done: false,
        status: 'blocked',
        priority: 'high',
      ),
      WorkspaceTask(
        id: 'task_coffee',
        title: 'Buy more coffee',
        detail: 'Open',
        done: false,
        status: 'open',
        priority: 'normal',
      ),
    ],
    sources: <SourceItem>[],
    memoryRecords: <MemoryRecord>[],
  );
}

AgentAwesomeAppController _unconfiguredModelController() {
  final controller = AgentAwesomeAppController(config: _testConfig());
  controller.appSettings = const AgentAwesomeAppSettings(
    gettingStartedCompleted: true,
  );
  controller.runtimeProfile = _settingsProfile();
  controller.runtimeProfilePath = '/tmp/personal.json';
  controller.availableModelConfigs = const <ConfigFileEntry>[
    ConfigFileEntry(
      path: '/tmp/model.yaml',
      kind: ConfigFileKind.model,
      assigned: true,
      displayName: 'Empty Model',
    ),
  ];
  return controller;
}

class _MemoryAppSettingsStore extends AgentAwesomeAppSettingsStore {
  _MemoryAppSettingsStore();

  AgentAwesomeAppSettings saved = const AgentAwesomeAppSettings();

  /// Loads the latest in-memory app settings.
  @override
  Future<AgentAwesomeAppSettings> load() async {
    return saved;
  }

  /// Saves app settings in memory for widget assertions.
  @override
  Future<void> save(
    AgentAwesomeAppSettings settings, {
    Iterable<String> extraPolicyActors = const <String>[],
  }) async {
    saved = settings;
  }
}

ProjectWorkspace _memoryWorkspace() {
  return const ProjectWorkspace(
    title: 'Workspace',
    subtitle: 'Live connected workspace',
    tasks: <WorkspaceTask>[],
    sources: <SourceItem>[],
    memoryRecords: <MemoryRecord>[
      MemoryRecord(
        id: 'cat-1',
        evidenceId: 'ev-1',
        title: 'Preference',
        summary: 'User prefers direct connected data.',
        kind: 'profile_fact',
        topics: <String>['ui'],
        sourceLabel: 'chat:1',
        sourceSystem: 'chat',
        sourceId: '1',
      ),
      MemoryRecord(
        id: 'chat-1',
        evidenceId: 'chat-ev-1',
        title: 'Chat message from user in session',
        summary: 'A remembered chat row.',
        kind: 'conversation',
        topics: <String>['adk_chat'],
        sourceLabel: 'google_adk_session:event-1',
        sourceSystem: 'google_adk_session',
        sourceId: 'event-1',
      ),
    ],
  );
}

RuntimeProfile _settingsProfile() {
  return const RuntimeProfile(
    id: 'personal',
    label: 'Personal',
    harness: HarnessRuntime(
      id: 'harness',
      label: 'Local Harness',
      apiBaseUrl: 'http://127.0.0.1:1/api',
      contextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
      appName: 'test',
      userId: 'user',
      workingDirectory: '/tmp/harness',
      packagePath: './cmd/agent-awesome',
      modelConfigPath: '/tmp/model.yaml',
      agentConfigPath: '/tmp/agent.yaml',
      toolConfigPath: '/tmp/tool.yaml',
      port: 1,
      autoStart: false,
    ),
    gateway: GatewayRuntime(
      id: 'gateway',
      label: 'Gateway',
      apiBaseUrl: 'http://127.0.0.1:2/api',
      healthUrl: 'http://127.0.0.1:2/healthz',
      workingDirectory: '/tmp/gateway',
      packagePath: './cmd/agent-gateway',
      harnessBaseUrl: 'http://127.0.0.1:1/api',
      contextBaseUrl: 'http://127.0.0.1:8081/api/context',
      memoryMcpUrl: 'http://127.0.0.1:1/mcp',
      appName: 'test',
      userId: 'user',
      port: 2,
      autoStart: false,
      enabled: true,
    ),
    memoryDomains: <McpServerRuntime>[
      McpServerRuntime(
        id: 'memory',
        label: 'Memory',
        kind: 'memory',
        endpoint: 'http://127.0.0.1:1/mcp',
        healthUrl: 'http://127.0.0.1:1/healthz',
        workingDirectory: '/tmp/memory',
        packagePath: './cmd/memoryd',
        dbPath: '/tmp/memory.db',
        dataDir: '/tmp/memory-files',
        arguments: <String>[],
        autoStart: false,
        enabled: true,
      ),
    ],
    agentMemory: AgentMemoryRuntime(
      actor: 'agent:test',
      readDomains: <String>['memory'],
      writeDomains: <String>['memory'],
      defaultWriteDomain: 'memory',
      allowedSensitivities: <String>['public', 'internal', 'private'],
    ),
  );
}

RuntimeProfile _chatRuntimeProfile() {
  return _settingsProfile().copyWith(
    memoryDomains: const <McpServerRuntime>[
      McpServerRuntime(
        id: 'memory',
        label: 'Memory',
        kind: 'memory',
        endpoint: 'http://127.0.0.1:1/mcp',
        healthUrl: 'http://127.0.0.1:1/healthz',
        workingDirectory: '/tmp/memory',
        packagePath: './cmd/memoryd',
        dbPath: '/tmp/memory.db',
        dataDir: '/tmp/memory-files',
        arguments: <String>[],
        autoStart: false,
        enabled: true,
      ),
      McpServerRuntime(
        id: 'project',
        label: 'Project Memory',
        kind: 'memory',
        endpoint: 'http://127.0.0.1:3/mcp',
        healthUrl: 'http://127.0.0.1:3/healthz',
        workingDirectory: '/tmp/project-memory',
        packagePath: './cmd/memoryd',
        dbPath: '/tmp/project-memory.db',
        dataDir: '/tmp/project-memory-files',
        arguments: <String>[],
        autoStart: false,
        enabled: true,
      ),
    ],
    agentMemory: const AgentMemoryRuntime(
      actor: 'agent:test',
      readDomains: <String>['memory', 'project'],
      writeDomains: <String>['memory', 'project'],
      defaultWriteDomain: 'memory',
      allowedSensitivities: <String>['public', 'internal', 'private'],
    ),
  );
}

AppConfig _testConfig() {
  return const AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:1/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:2/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:1/mcp',
    agentAppName: 'test',
    agentUserId: 'user',
    workspaceRoot: '/tmp/agentawesome-test',
    autoStartLocalServices: false,
    runtimeProfilePath: '',
  );
}
