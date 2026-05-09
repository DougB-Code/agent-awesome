/// Tests the primary Agent Awesome workspace widgets.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/app_settings.dart';
import 'package:agentawesome_ui/app/config_files.dart';
import 'package:agentawesome_ui/app/model_config.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/domain/screen_command.dart';
import 'package:agentawesome_ui/ui/agent_awesome_shell.dart';
import 'package:agentawesome_ui/ui/onboarding/setup_wizard_shell.dart';
import 'package:agentawesome_ui/ui/panels/panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs widget tests for the shell.
void main() {
  testWidgets('renders home workspace without local demo data', (tester) async {
    final controller = _readyController();

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );

    expect(find.text('Live Workspace'), findsOneWidget);
    expect(find.text('Execution Plan'), findsNothing);
    expect(find.text('No live chat messages'), findsOneWidget);
    expect(find.text('Prepare investor meeting brief'), findsNothing);
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
    final controller = _readyController();
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
            modelName: 'gpt-5.4-mini',
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
    await tester.tap(find.byTooltip('Settings'));
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
    expect(find.text('Personal Memory'), findsOneWidget);

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
    controller.messages = <ChatMessage>[
      ChatMessage(
        id: 'message-1',
        role: ChatRole.assistant,
        author: 'Agent Awesome',
        text: 'Connected chat message. Done - created Follow up report.',
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
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('CONVERSATION'), findsOneWidget);
    expect(find.text('CONTEXT'), findsOneWidget);
    expect(find.byTooltip('Select chat'), findsOneWidget);
    expect(find.byTooltip('Delete selected chat'), findsOneWidget);
    expect(find.byTooltip('New chat with profile'), findsNothing);
    expect(find.byTooltip('Chats'), findsNothing);
    expect(find.byTooltip('Sessions'), findsNothing);
    expect(find.text('Live chat'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    expect(
      find.text('Connected chat message. Done - created Follow up report.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Copy message'), findsOneWidget);
    expect(find.text('Message Agent Awesome in this chat...'), findsOneWidget);
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
    expect(find.text('WORKSPACES'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
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
    expect(find.text('Preference'), findsWidgets);
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
        'Personal Memory: McpException: HTTP 401 from http://127.0.0.1:8070/api/context/tools/call';

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );

    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();
    expect(find.text('Memory service unavailable'), findsOneWidget);
    expect(find.text('Connection failed'), findsOneWidget);
    expect(find.textContaining('HTTP 401'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('SEARCH'), findsNothing);
    expect(find.text('OVERVIEW'), findsNothing);
    expect(find.text('No memory records'), findsNothing);

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(find.text('Memory service unavailable'), findsOneWidget);
    expect(find.text('Topic Timelines'), findsNothing);

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    expect(find.text('Memory service unavailable'), findsOneWidget);
    expect(find.text('No entities in memory'), findsNothing);
  });

  testWidgets('shows files as agent files with add-file empty action', (
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

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('Files for your agent.'), findsOneWidget);
    expect(find.text('Add file'), findsOneWidget);
    expect(
      find.text('Immutable evidence and source material from memory.'),
      findsNothing,
    );
    expect(find.text('No source evidence loaded'), findsNothing);

    await tester.tap(find.text('Add file'));
    await tester.pumpAndSettle();
    expect(find.text('File import is not connected yet'), findsOneWidget);
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
    expect(find.text('BACKLOG INSPECTOR'), findsOneWidget);
    expect(find.text('Draft task brief'), findsWidgets);
    expect(find.byTooltip('Delete backlog item'), findsWidgets);
    expect(find.text('Backlog Stream'), findsNothing);
    expect(find.byTooltip('Stream'), findsOneWidget);
    expect(find.byTooltip('Terrain'), findsOneWidget);
    expect(find.byTooltip('Constellation'), findsOneWidget);
    await tester.tap(find.byTooltip('Stream'));
    await tester.pumpAndSettle();
    expect(find.text('STREAM'), findsOneWidget);
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('Analyze stream layout'), findsOneWidget);
    expect(find.text('Backlog Stream'), findsNothing);
    expect(find.text('Workload'), findsNothing);
    await tester.tap(find.byTooltip('Queue'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Memory Links'), findsOneWidget);
    await tester.tap(find.byTooltip('Memory Links'));
    await tester.pumpAndSettle();
    expect(find.text('MEMORY LINKS'), findsOneWidget);
    expect(find.text('No memory selected'), findsOneWidget);
    expect(find.text('No linked memory'), findsOneWidget);
    await tester.tap(find.byTooltip('Backlog Inspector').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draft task brief').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pick Due date'), findsOneWidget);
    expect(find.byTooltip('Pick Scheduled date'), findsOneWidget);
    await tester.tap(find.byTooltip('Stream'));
    await tester.pumpAndSettle();
    expect(find.text('STREAM'), findsOneWidget);
    expect(find.byTooltip('Collapse panel'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Collapse panel').first);
    await tester.pumpAndSettle();
    expect(find.text('STREAM'), findsNothing);
    expect(find.byTooltip('Expand panel'), findsOneWidget);
    expect(find.byTooltip('Terrain'), findsOneWidget);
    await tester.tap(find.byTooltip('Terrain'));
    await tester.pumpAndSettle();
    expect(find.text('TERRAIN'), findsNothing);
    await tester.tap(find.byTooltip('Expand panel'));
    await tester.pumpAndSettle();
    expect(find.text('TERRAIN'), findsOneWidget);
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

      expect(find.text('REVIEW CHANGES'), findsOneWidget);
      expect(find.text('Priority changed to high'), findsWidgets);
      await tester.tap(find.byTooltip('Focus change'));
      await tester.pumpAndSettle();
      expect(controller.focusedBacklogTaskId, 'task-brief');

      await tester.tap(find.text('Draft task brief').first);
      await tester.pumpAndSettle();

      expect(find.text('BACKLOG INSPECTOR'), findsOneWidget);
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
    expect(find.text('BACKLOG INSPECTOR'), findsOneWidget);
    expect(find.text('CONVERSATION'), findsOneWidget);
    expect(find.text('What changed here?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('global-command-input')),
      findsOneWidget,
    );
    expect(find.byTooltip('New chat'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
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

  testWidgets('loads workflow content inside the persistent app shell', (
    tester,
  ) async {
    final controller = _readyController();

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Workflows'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('New chat'), findsOneWidget);
    expect(find.text('Workspace'), findsWidgets);
    expect(find.text('MEMORY & CONTEXT'), findsOneWidget);
  });

  testWidgets('keeps workflow command panes side by side on wide screens', (
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
    await tester.tap(find.text('Workflows'));
    await tester.pumpAndSettle();

    final workflowLeft = tester.getRect(find.text('Workspace').first);
    final workflowRight = tester.getRect(find.text('MEMORY & CONTEXT'));

    expect(tester.takeException(), isNull);
    expect(workflowLeft.left, lessThan(workflowRight.left));
    expect(workflowRight.left, greaterThan(900));
  });

  testWidgets('resizes workflow command panes with the split handle', (
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
    await tester.tap(find.text('Workflows'));
    await tester.pumpAndSettle();

    final beforeRight = tester.getRect(find.text('MEMORY & CONTEXT')).left;
    await tester.drag(
      find.byKey(const ValueKey<String>('command-split-handle')),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();
    final afterRight = tester.getRect(find.text('MEMORY & CONTEXT')).left;

    expect(tester.takeException(), isNull);
    expect(afterRight, greaterThan(beforeRight + 80));
  });

  testWidgets('cycles and filters workflow command panel content', (
    tester,
  ) async {
    final controller = _readyController();
    controller.workspace = const ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live connected workspace',
      tasks: <WorkspaceTask>[
        WorkspaceTask(
          id: 'task-review',
          title: 'Review source material',
          detail: 'Open',
          done: false,
        ),
        WorkspaceTask(
          id: 'task-competitor',
          title: 'Analyze competitor positioning',
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
    await tester.tap(find.text('Workflows'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('WORKSPACE'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('command-panel-filter-Research Plan')),
      'competitor',
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('RESEARCH PLAN'), findsOneWidget);
    expect(find.text('Analyze competitor positioning'), findsOneWidget);
    expect(find.text('Review source material'), findsNothing);
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
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.text('AGENT AWESOME'), findsNothing);
  });
}

AgentAwesomeAppController _readyController() {
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
      displayName: 'Configured Model',
      modelChoices: <ModelConfigChoice>[
        ModelConfigChoice(
          providerId: 'openai',
          providerName: 'OpenAI',
          modelId: 'gpt-5.4-mini',
          modelName: 'GPT-5.4 Mini',
          isDefault: true,
        ),
      ],
    ),
  ];
  return controller;
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
  Future<void> save(AgentAwesomeAppSettings settings) async {
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
    memoryServerConfigPath: '/tmp/memory.json',
    mcpServers: <McpServerRuntime>[
      McpServerRuntime(
        id: 'memory',
        label: 'Personal Memory',
        kind: 'memory',
        endpoint: 'http://127.0.0.1:1/mcp',
        healthUrl: 'http://127.0.0.1:1/healthz',
        workingDirectory: '/tmp/memory',
        packagePath: './cmd/memoryd',
        arguments: <String>[],
        autoStart: false,
        enabled: true,
      ),
    ],
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
