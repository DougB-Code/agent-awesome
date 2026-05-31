/// Tests the primary Agent Awesome workspace widgets.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/file_import.dart';
import 'package:agentawesome_ui/app/app_settings.dart';
import 'package:agentawesome_ui/app/config_files.dart';
import 'package:agentawesome_ui/app/local_services.dart';
import 'package:agentawesome_ui/app/process_supervisor.dart';
import 'package:agentawesome_ui/clients/automations_client.dart';
import 'package:agentawesome_ui/clients/assistant_client.dart';
import 'package:agentawesome_ui/clients/executive_summary_client.dart';
import 'package:agentawesome_ui/clients/mcp_client.dart';
import 'package:agentawesome_ui/domain/agent_validation_result.dart';
import 'package:agentawesome_ui/domain/automation_contracts.dart';
import 'package:agentawesome_ui/domain/date_formatting.dart';
import 'package:agentawesome_ui/domain/tool_config.dart';
import 'package:agentawesome_ui/domain/tool_validation_result.dart';
import 'package:agentawesome_ui/ui/theme.dart';
import 'package:agentawesome_ui/domain/model_config.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:agentawesome_ui/domain/executive_summary.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/domain/models_automation.dart';
import 'package:agentawesome_ui/domain/screen_command.dart';
import 'package:agentawesome_ui/domain/today_state.dart';
import 'package:agentawesome_ui/features/today/widgets/today_schedule_card.dart';
import 'package:agentawesome_ui/ui/agent_awesome_shell.dart';
import 'package:agentawesome_ui/ui/onboarding/setup_wizard_shell.dart';
import 'package:agentawesome_ui/ui/panels/panels.dart';
import 'package:agentawesome_ui/ui/settings/settings_panel.dart';
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
    expect(find.text('Updated just now'), findsNothing);
    expect(find.text("TODAY'S ATTENTION"), findsOneWidget);
    expect(find.text('Prepare investor meeting brief'), findsNothing);
  });

  testWidgets('makes Today errors selectable', (tester) async {
    const error =
        'ClientException with SocketException: Connection refused, uri=http://127.0.0.1:8070/api/context/tools/call';
    final controller = _readyController()
      ..todayState = const TodayState(error: error);

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SelectableText, error), findsOneWidget);
    expect(find.byTooltip('Copy error'), findsNothing);
  });

  test('builds the Today gateway memory MCP route', () {
    final profile = _settingsProfile();
    expect(
      gatewayMemoryMcpEndpointFor(profile, profile.memoryServers.single),
      'http://127.0.0.1:2/mcp/memory',
    );
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
    expect(find.text('SCHEDULE'), findsOneWidget);
    expect(find.text('Review weekly plan'), findsWidgets);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.textContaining('Banking / Bills'), findsNothing);
    expect(find.text('Manage connections'), findsNothing);
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

  testWidgets('opens Today attention view from decision metric', (
    tester,
  ) async {
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
    await tester.tap(find.text('Decide').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('1 decision require your input'), findsOneWidget);
    expect(find.text('Budget decision'), findsWidgets);
    expect(find.text('Needs your approval.'), findsWidgets);
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
    expect(find.byIcon(Icons.save_outlined), findsNothing);
    expect(find.text('All insights'), findsNothing);
    expect(find.text('Open, Waiting, Blocked'), findsOneWidget);
    expect(find.text('Active tasks'), findsNothing);
    expect(find.text('Queue score'), findsNothing);
    expect(find.text('Schedule'), findsNothing);
    expect(find.text('Mark done'), findsNothing);
    expect(
      find.byTooltip('Schedule selected backlog item today'),
      findsOneWidget,
    );
    expect(find.byTooltip('Complete backlog item'), findsOneWidget);
    expect(find.textContaining('Data quality'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('command-split-handle')),
      findsOneWidget,
    );
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('Draft task brief'), findsWidgets);
    expect(find.text('TASK'), findsOneWidget);

    await tester.tap(find.byTooltip('Stream'));
    await tester.pumpAndSettle();

    expect(find.text('Stream command panel'), findsNothing);
    expect(find.text('STREAM'), findsWidgets);
    expect(find.text('TASK'), findsNothing);

    await tester.tap(find.byTooltip('Collapse details column'));
    await tester.pumpAndSettle();

    expect(find.text('STREAM'), findsWidgets);
    expect(find.text('Inspector'), findsNothing);
  });

  testWidgets('opens exposed Automations menu sections', (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationActionTypes = const <AutomationActionType>[
        AutomationActionType(
          name: 'tool.call',
          label: 'Run Tool',
          description: 'Call a harness-exposed tool.',
          risk: 'tool',
          available: true,
        ),
        AutomationActionType(
          name: 'mcp.call',
          label: 'Call MCP Tool',
          description: 'Call an installed MCP tool endpoint.',
          risk: 'tool',
          available: true,
        ),
        AutomationActionType(
          name: 'runbook.run',
          label: 'Run Runbook',
          description: 'Start a nested runbook.',
          risk: 'runbook',
          available: true,
        ),
      ]
      ..automationToolNames = const <String>{'email.search', 'browser.read'}
      ..automationDefinitions = const <AutomationDefinition>[
        AutomationDefinition(
          id: 'daily_email',
          kind: automationRunbookKind,
          name: 'Daily Email',
          hash: 'abc',
        ),
      ]
      ..automationDrafts = const <AutomationDraft>[
        AutomationDraft(
          id: 'draft_review',
          kind: automationRunbookKind,
          name: 'Review Flow',
          status: 'draft',
          body: <String, dynamic>{
            'kind': 'state_machine',
            'id': 'review_flow',
            'states': <Object>[
              <String, Object>{
                'id': 'fetch_context',
                'type': 'task',
                'uses': 'mcp.call',
                'with': <String, Object>{
                  'endpoint': 'http://127.0.0.1:8090/mcp',
                  'tool': 'sourcecontrol.status',
                  'arguments': <String, Object>{},
                },
              },
              <String, Object>{
                'id': 'assert_context',
                'type': 'task',
                'uses': 'data.assert',
                'depends_on': <Object>['fetch_context'],
                'with': <String, Object>{'checks': <Object>[]},
              },
            ],
          },
        ),
      ]
      ..automationRuns = const <AutomationRun>[
        AutomationRun(
          id: 'run_1',
          definitionId: 'daily_email',
          kind: automationRunbookKind,
          status: 'waiting',
          state: 'running',
        ),
      ]
      ..automationRunSetups = const <AutomationRunSetup>[
        AutomationRunSetup(
          id: 'setup_1',
          definitionId: 'daily_email',
          name: 'Daily Email Setup',
        ),
      ]
      ..automationCodebases = const <AutomationCodebase>[
        AutomationCodebase(
          id: 'agent_awesome',
          name: 'Agent Awesome',
          repositoryPath: '/tmp/agentawesome-test',
          defaultRemote: 'origin',
          defaultBranch: 'main',
        ),
      ]
      ..automationRuntimeTargets = const <AutomationRuntimeTarget>[
        AutomationRuntimeTarget(
          id: 'local',
          name: 'This computer',
          kind: 'local',
          status: 'healthy',
          version: 'dev',
          capabilities: <String>['command:go_test_all'],
          allowedCodebaseIds: <String>['agent_awesome'],
          secretRefCount: 1,
          currentRunCount: 0,
          os: 'linux',
          hostname: 'workstation',
        ),
      ]
      ..selectedAutomationRuntimeTargetId = 'local'
      ..selectedAutomationTargetHealth = const AutomationTargetHealth(
        targetId: 'local',
        status: 'healthy',
        version: 'dev',
        os: 'linux',
        hostname: 'workstation',
      )
      ..selectedAutomationTargetLogs = const <AutomationTargetLogEntry>[
        AutomationTargetLogEntry(
          id: 1,
          targetId: 'local',
          level: 'info',
          message: 'Local target registered',
        ),
      ]
      ..selectedAutomationTargetSecrets = const AutomationTargetSecretMetadata(
        targetId: 'local',
        count: 1,
      )
      ..automationCapabilities = const <AutomationCapability>[
        AutomationCapability(
          id: 'command:go_test_all',
          kind: 'command',
          name: 'go_test_all',
          label: 'Go test all',
          description: 'Run Go tests.',
          usableInChat: true,
          usableInRunbooks: true,
          invocation: <String, Object>{
            'direct_tool_name': 'command_execute',
            'runbook_action': 'command.execute',
            'command_template': 'go_test_all',
          },
          risk: <String, Object>{'level': 'tool'},
          availability: AutomationCapabilityAvailability(status: 'available'),
          testResults: <AutomationCapabilityTestResult>[
            AutomationCapabilityTestResult(type: 'schema', status: 'available'),
          ],
        ),
      ]
      ..automationInbox = const <AutomationPendingItem>[
        AutomationPendingItem(
          id: 'pending_1',
          runId: 'run_1',
          stepId: 'approve',
          status: 'open',
          prompt: 'Approve archive?',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    expect(find.text('AUTOMATIONS'), findsOneWidget);
    expect(find.text('Launchpad'), findsWidgets);
    expect(find.text('Runbooks'), findsOneWidget);
    expect(find.text('Tasks'), findsNothing);
    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('MCP Servers'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('›'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Launchpad')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('main-content-sub-shell')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('main-content-left-pane')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('main-content-right-pane')),
      findsOneWidget,
    );
    expect(find.text('OPERATIONS'), findsWidgets);
    expect(find.byTooltip('Inbox'), findsOneWidget);
    expect(find.byTooltip('Launchpad'), findsWidgets);
    expect(find.byTooltip('Files'), findsNothing);
    expect(find.byTooltip('Computers'), findsOneWidget);
    expect(find.byTooltip('Refresh automations'), findsNothing);
    expect(find.text('Daily Email'), findsWidgets);
    expect(find.byTooltip('Codebases'), findsNothing);
    expect(find.byTooltip('Overview'), findsOneWidget);
    expect(find.byTooltip('Schedules'), findsOneWidget);
    expect(find.byTooltip('Artifacts'), findsOneWidget);
    expect(find.byTooltip('Runs'), findsWidgets);
    expect(find.byTooltip('Safety'), findsNothing);
    await tester.tap(find.byTooltip('Overview'));
    await tester.pumpAndSettle();
    expect(find.text('Daily Email Setup'), findsWidgets);
    await tester.tap(find.byTooltip('Inbox'));
    await tester.pumpAndSettle();
    expect(find.text('Approve archive?'), findsOneWidget);
    await tester.tap(find.byTooltip('Launchpad').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schedules'));
    await tester.pumpAndSettle();
    expect(find.text('No scheduled launchpad'), findsOneWidget);
    await tester.tap(find.byTooltip('Artifacts'));
    await tester.pumpAndSettle();
    expect(find.text('No artifacts'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Runs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Runs').last);
    await tester.pumpAndSettle();
    expect(find.text('run_1 / running'), findsNothing);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Ran'), findsOneWidget);
    expect(find.text('Daily Email'), findsWidgets);
    expect(find.text('waiting'), findsOneWidget);
    await tester.tap(find.byTooltip('Computers'));
    await tester.pumpAndSettle();
    expect(find.text('This computer'), findsWidgets);
    expect(find.text('Allowed codebases: Agent Awesome'), findsOneWidget);
    expect(find.byTooltip('Capabilities'), findsOneWidget);
    expect(find.byTooltip('Secrets'), findsOneWidget);
    expect(find.byTooltip('Logs'), findsOneWidget);
    expect(find.byTooltip('Updates'), findsOneWidget);
    expect(find.byTooltip('Codebases'), findsNothing);
    expect(find.byTooltip('Schedules'), findsNothing);
    await tester.tap(find.byTooltip('Capabilities'));
    await tester.pumpAndSettle();
    expect(find.text('Go test all'), findsOneWidget);

    expect(
      find.byKey(const ValueKey<String>('sidebar-Agents')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sidebar-Runbooks')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('sidebar-Tasks')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    expect(find.text('ACTIONS'), findsNothing);
    expect(find.byTooltip('Builder'), findsOneWidget);
    expect(find.byTooltip('State'), findsOneWidget);
    expect(find.byTooltip('States'), findsNothing);
    expect(find.byTooltip('Map'), findsNothing);
    expect(find.byTooltip('Safety'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('state-machine-canvas')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-palette')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('sidebar-Tasks')), findsNothing);

    await tester.tap(find.byTooltip('Runbooks'));
    await tester.pumpAndSettle();

    expect(find.text('RUNBOOKS'), findsWidgets);
    expect(find.text('Filter runbooks...'), findsOneWidget);
    expect(find.text('Review Flow'), findsWidgets);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-palette')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-canvas')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-MCP Servers')));
    await tester.pumpAndSettle();

    expect(find.text('MCP SERVERS'), findsWidgets);
    expect(find.text('DETAILS'), findsWidgets);
    expect(find.text('No MCP server files configured'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Tools')));
    await tester.pumpAndSettle();

    expect(find.text('TOOLS'), findsWidgets);
    expect(find.text('DETAILS'), findsWidgets);
    expect(find.text('No tool files configured'), findsWidgets);
  });

  testWidgets('renders Launchpad detail empty state with shared guidance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()..automationsBusy = true;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Launchpad')));
    await tester.pumpAndSettle();

    void expectLeftEmptyCentered(String label) {
      final text = find.text(label);
      expect(text, findsOneWidget);
      final paneRect = tester.getRect(
        find.byKey(const ValueKey<String>('main-content-left-pane')),
      );
      final textRect = tester.getRect(text);
      expect((paneRect.center.dy - textRect.center.dy).abs(), lessThan(120));
    }

    expectLeftEmptyCentered('No launchpad');
    await tester.tap(find.byTooltip('Inbox'));
    await tester.pumpAndSettle();
    expectLeftEmptyCentered('No pending automation items');
    await tester.tap(find.byTooltip('Computers'));
    await tester.pumpAndSettle();
    expectLeftEmptyCentered('No computers');
    await tester.tap(find.byTooltip('Launchpad').first);
    await tester.pumpAndSettle();

    final emptyText = find.text('No launch selected');
    expect(emptyText, findsOneWidget);
    expect(
      find.text('Select or create an item in the left panel to continue.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    final ancestorSurfaces = tester.widgetList<PanelSurface>(
      find.ancestor(of: emptyText, matching: find.byType(PanelSurface)),
    );
    expect(
      ancestorSurfaces.where(
        (surface) => surface.style == PanelSurfaceStyle.card,
      ),
      isEmpty,
    );
    final paneRect = tester.getRect(
      find.byKey(const ValueKey<String>('main-content-right-pane')),
    );
    final textRect = tester.getRect(emptyText);
    expect((paneRect.center.dy - textRect.center.dy).abs(), lessThan(80));
  });

  testWidgets('does not render passive Automations status blocks', (
    tester,
  ) async {
    final controller = _readyController()
      ..automationsMessage = 'Automations refreshed'
      ..automationDefinitions = const <AutomationDefinition>[
        AutomationDefinition(
          id: 'ready',
          kind: automationRunbookKind,
          name: 'Ready',
          hash: 'sha256:ready',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Launchpad')));
    await tester.pumpAndSettle();

    expect(find.text('Status'), findsNothing);
    expect(find.text('Automations refreshed'), findsNothing);
  });

  testWidgets('shows saved Launchpad in Launchpad', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDefinitions(<AutomationDefinition>[
      _sourceChangeDefinitionForRunTest(),
    ]);
    harness.client.seedRunSetups(const <AutomationRunSetup>[
      AutomationRunSetup(
        id: 'setup_1',
        definitionId: 'source_change_runbook',
        name: 'Agent Awesome Repo',
        description: 'Run source changes for the app repo.',
      ),
    ]);
    controller.automationDefinitions = harness.client.definitions;
    controller.automationRunSetups = harness.client.runSetups;
    controller.selectedAutomationRunSetupId = 'setup_1';

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Launchpad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Launchpad').first);
    await tester.pumpAndSettle();

    expect(find.text('Agent Awesome Repo'), findsWidgets);
    expect(find.text('Source Change Runbook'), findsWidgets);
    await tester.tap(find.text('Agent Awesome Repo').first);
    await tester.pump();
    expect(controller.selectedAutomationRunSetupId, 'setup_1');
  });

  testWidgets('opens Launchpad runbook run input dialog', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDefinitions(<AutomationDefinition>[
      _yamlOkDefinitionForRunTest(),
    ]);
    harness.client.seedRunSetups(const <AutomationRunSetup>[
      AutomationRunSetup(
        id: 'setup_1',
        definitionId: 'yaml_ok_branch',
        name: 'YAML OK Branch Test',
      ),
    ]);
    controller.automationDefinitions = harness.client.definitions;
    controller.automationRunSetups = harness.client.runSetups;
    controller.selectedAutomationRunSetupId = 'setup_1';
    controller.automationCodebases = const <AutomationCodebase>[
      AutomationCodebase(
        id: 'agent_awesome',
        name: 'Agent Awesome',
        repositoryPath: '/repo/agent',
        defaultRemote: 'origin',
        defaultBranch: 'main',
      ),
    ];
    controller.selectedAutomationCodebaseId = 'agent_awesome';
    controller.automationRuntimeTargets = const <AutomationRuntimeTarget>[
      AutomationRuntimeTarget(
        id: 'local',
        name: 'This computer',
        kind: 'local',
        status: 'healthy',
        allowedCodebaseIds: <String>['agent_awesome'],
      ),
    ];
    controller.selectedAutomationRuntimeTargetId = 'local';

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Launchpad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Launchpad').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('automation-start-run-setup-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Run YAML OK Branch Test'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('automation-run-input-json')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('automation-run-input-repository_path'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('automation-run-input-change_request')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('automation-run-input-workdir')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('automation-run-input-remote')),
      findsNothing,
    );
  });

  testWidgets('creates reusable Launchpad from typed fields', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDefinitions(<AutomationDefinition>[
      _yamlOkDefinitionForRunTest(),
    ]);
    controller.automationDefinitions = harness.client.definitions;
    controller.selectedAutomationDefinitionId = 'yaml_ok_branch';

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Launchpad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Launchpad').first);
    await tester.pumpAndSettle();
    controller.automationCodebases = const <AutomationCodebase>[
      AutomationCodebase(
        id: 'agent_awesome',
        name: 'Agent Awesome',
        repositoryPath: '/repo/agent',
        defaultRemote: 'origin',
        defaultBranch: 'main',
      ),
    ];
    controller.selectedAutomationCodebaseId = 'agent_awesome';
    controller.automationRuntimeTargets = const <AutomationRuntimeTarget>[
      AutomationRuntimeTarget(
        id: 'local',
        name: 'This computer',
        kind: 'local',
        status: 'healthy',
        allowedCodebaseIds: <String>['agent_awesome'],
      ),
    ];
    controller.selectedAutomationRuntimeTargetId = 'local';
    await tester.tap(
      find.byKey(const ValueKey<String>('automation-create-run-setup-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create Launch'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('automation-run-setup-name')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('automation-run-setup-codebase')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('automation-run-setup-target')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('automation-run-setup-safety')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('automation-run-input-workdir')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('automation-run-input-change_request')),
      findsNothing,
    );

    expect(find.widgetWithText(FilledButton, 'Create'), findsOneWidget);
  });

  testWidgets('shows enabled right-aligned runbook create action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(<AutomationDraft>[_runbookGraphDraft()]);
    controller.automationDrafts = harness.client.drafts;
    controller.selectedAutomationDraftId = harness.client.drafts.first.id;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Runbooks'));
    await tester.pumpAndSettle();
    for (
      var attempt = 0;
      attempt < 100 && controller.automationsBusy;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(controller.automationsBusy, isFalse);

    final createButton = find.byKey(
      const ValueKey<String>('automation-new-runbook-draft-button'),
    );
    final deleteButton = find.byKey(
      const ValueKey<String>('automation-delete-runbook-button'),
    );
    expect(createButton, findsOneWidget);
    expect(deleteButton, findsOneWidget);
    final createTapTarget = find.descendant(
      of: createButton,
      matching: find.byType(GestureDetector),
    );
    final deleteTapTarget = find.descendant(
      of: deleteButton,
      matching: find.byType(GestureDetector),
    );
    expect(createTapTarget, findsOneWidget);
    expect(deleteTapTarget, findsOneWidget);
    expect(tester.widget<GestureDetector>(createTapTarget).onTap, isNotNull);
    final paneRight = tester
        .getTopRight(
          find.byKey(const ValueKey<String>('main-content-left-pane')),
        )
        .dx;
    final buttonRight = tester.getTopRight(deleteTapTarget).dx;
    expect(paneRight - buttonRight, lessThanOrEqualTo(28));
    expect(find.text('Runbook name'), findsNothing);

    await tester.tap(createTapTarget);
    await tester.pumpAndSettle();
    expect(find.text('RUNBOOKS'), findsWidgets);
    expect(find.text('Filter runbooks...'), findsOneWidget);
    expect(find.text('New Runbook'), findsWidgets);
    expect(controller.selectedAutomationDraftId, 'draft_2');
    await tester.tap(createTapTarget);
    await tester.pumpAndSettle();
    expect(find.text('New Runbook 2'), findsWidgets);
    expect(controller.selectedAutomationDraftId, 'draft_3');
    expect(find.text('draft_runbook_graph'), findsNothing);
  });

  testWidgets('renames runbook drafts from Details metadata', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(<AutomationDraft>[
      const AutomationDraft(
        id: 'draft_runbook_graph',
        kind: automationRunbookKind,
        name: 'Runbook Graph',
        status: 'draft',
        updatedAt: '2026-05-28T21:27:28.926Z',
        body: <String, dynamic>{
          'apiVersion': automationRunbookApiVersion,
          'kind': automationRunbookKind,
          'id': 'runbook_graph',
          'nodes': <Object>[],
        },
      ),
    ]);
    controller.automationDrafts = harness.client.drafts;
    controller.selectedAutomationDraftId = harness.client.drafts.first.id;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Runbooks'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Runbook Graph').first);
    await tester.pump();
    expect(find.byTooltip('Rename runbook file'), findsNothing);

    await tester.tap(find.byTooltip('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Updated 2026-05-28'), findsNothing);
    expect(find.textContaining('2026-05-28T21:27:28.926Z'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey<String>('runbook-metadata-name')),
      'Renamed Runbook',
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(harness.client.savedDraft?.name, 'Renamed Runbook');
    expect(find.text('draft_runbook_graph'), findsNothing);
  });

  testWidgets('shows runbook graph fields in Details mode', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(<AutomationDraft>[_runbookGraphDraft()]);
    controller.automationDrafts = harness.client.drafts;
    controller.selectedAutomationDraftId = harness.client.drafts.first.id;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-canvas')),
      findsNothing,
    );
    expect(find.text('ACTIONS'), findsNothing);

    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('RUNBOOKS'), findsWidgets);
    expect(find.text('Runbook Graph'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('state-machine-canvas')),
      findsNothing,
    );
  });

  testWidgets('shows state-machine definitions as runbook files', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(const <AutomationDraft>[
      AutomationDraft(
        id: 'draft_source_change_runbook',
        kind: 'state_machine',
        name: 'Source Change Runbook',
        status: 'published',
        body: <String, dynamic>{
          'kind': 'state_machine',
          'id': 'source_change_runbook',
          'initial': 'intake',
          'states': <Object>[
            <String, Object>{'id': 'intake'},
            <String, Object>{'id': 'source_control_prep'},
          ],
        },
      ),
    ]);
    controller.automationDrafts = harness.client.drafts;
    controller.selectedAutomationDraftId = 'draft_source_change_runbook';

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-intake')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Runbooks'));
    await tester.pumpAndSettle();
    expect(find.text('Source Change Runbook'), findsWidgets);
    expect(find.text('runbook'), findsWidgets);
  });

  test('creates runbook drafts with the runbook API kind', () async {
    final harness = _readyCapturingController();
    harness.client.seedDrafts(const <AutomationDraft>[]);

    await harness.controller.createAutomationDraftFromUi(
      kind: automationRunbookKind,
      name: 'New Runbook',
    );

    expect(
      harness.client.createdKind,
      automationRunbookKind,
      reason: harness.controller.automationsMessage,
    );
    expect(harness.controller.selectedAutomationDraftId, 'draft_1');
  });

  test('starts runbook definitions with input payloads', () async {
    final harness = _readyCapturingController();
    const definition = AutomationDefinition(
      id: 'source_change_runbook',
      kind: automationRunbookKind,
      name: 'Source Change Runbook',
      hash: 'sha256:professional',
    );

    await harness.controller.startAutomationDefinitionFromUi(
      definition,
      input: const <String, dynamic>{
        'repository_path': '/repo',
        'change_request': 'Fix it',
      },
    );

    expect(harness.client.startedDefinitionId, 'source_change_runbook');
    expect(harness.client.startedInput['repository_path'], '/repo');
    expect(harness.client.startedInput['change_request'], 'Fix it');
    expect(harness.controller.selectedAutomationRunId, 'run_1');
  });

  test('creates and starts reusable Launchpad', () async {
    final harness = _readyCapturingController();
    const definition = AutomationDefinition(
      id: 'source_change_runbook',
      kind: automationRunbookKind,
      name: 'Source Change Runbook',
      hash: 'sha256:professional',
    );

    await harness.controller.createAutomationRunSetupFromUi(
      definition: definition,
      name: 'Agent Awesome Repo',
      codebaseId: 'agent_awesome',
      runtimeTargetId: 'local',
      input: const <String, dynamic>{'repository_path': '/repo'},
      policy: const <String, dynamic>{'source_control': 'open_pr_only'},
    );
    final setup = harness.client.createdRunSetup;
    expect(setup?.name, 'Agent Awesome Repo');
    expect(setup?.codebaseId, 'agent_awesome');
    expect(setup?.runtimeTargetId, 'local');
    expect(setup?.policy['source_control'], 'open_pr_only');
    expect(harness.controller.selectedAutomationRunSetupId, setup?.id);

    await harness.controller.startAutomationRunSetupFromUi(
      setup!,
      input: const <String, dynamic>{'change_request': 'Fix it'},
    );

    expect(harness.client.startedRunSetupId, setup.id);
    expect(harness.client.startedInput['change_request'], 'Fix it');
    expect(harness.controller.selectedAutomationRunId, 'run_1');
  });

  test('previews reusable Launchpad without starting runs', () async {
    final harness = _readyCapturingController();
    const definition = AutomationDefinition(
      id: 'source_change_runbook',
      kind: automationRunbookKind,
      name: 'Source Change Runbook',
      hash: 'sha256:professional',
    );

    await harness.controller.createAutomationRunSetupFromUi(
      definition: definition,
      name: 'Agent Awesome Repo',
      codebaseId: 'agent_awesome',
      runtimeTargetId: 'local',
      input: const <String, dynamic>{'repository_path': '/repo'},
    );
    final setup = harness.client.createdRunSetup!;

    await harness.controller.previewAutomationRunSetupFromUi(setup);

    expect(harness.client.previewedRunSetupId, setup.id);
    expect(
      harness.controller.selectedAutomationLaunchPreview?.missingSetup,
      <String>['change_request'],
    );
    expect(harness.controller.selectedAutomationRunId, isEmpty);
  });

  test('updates reusable Launchpad from typed setup fields', () async {
    final harness = _readyCapturingController();
    const setup = AutomationRunSetup(
      id: 'setup_1',
      definitionId: 'source_change_runbook',
      name: 'Agent Awesome Repo',
      codebaseId: 'agent_awesome',
      runtimeTargetId: 'local',
    );
    harness.client.seedRunSetups(const <AutomationRunSetup>[setup]);

    await harness.controller.updateAutomationRunSetupFromUi(
      setup.copyWith(
        name: 'Agent Awesome PRs',
        policy: const <String, dynamic>{
          'source_control': 'open_pr_only',
          'allowed_targets': <String>['local'],
        },
      ),
    );

    expect(harness.client.updatedRunSetup?.name, 'Agent Awesome PRs');
    expect(
      harness.client.updatedRunSetup?.policy['source_control'],
      'open_pr_only',
    );
    expect(harness.controller.selectedAutomationRunSetupId, setup.id);
  });

  test('loads Launch run snapshots for selected runs', () async {
    final harness = _readyCapturingController();
    const run = AutomationRun(
      id: 'run_1',
      definitionId: 'source_change_runbook',
      kind: automationRunbookKind,
      status: 'completed',
      state: 'done',
    );
    harness.controller.automationRuns = const <AutomationRun>[run];
    harness.client.runs = const <AutomationRun>[run];
    harness.client.snapshotsByRunId =
        const <String, AutomationLaunchRunSnapshot>{
          'run_1': AutomationLaunchRunSnapshot(
            runId: 'run_1',
            launchId: 'setup_1',
            resolvedInput: <String, dynamic>{'change_request': 'Fix it'},
          ),
        };

    await harness.controller.selectAutomationRun('run_1');

    expect(
      harness.controller.selectedAutomationLaunchRunSnapshot?.launchId,
      'setup_1',
    );
    expect(
      harness
          .controller
          .selectedAutomationLaunchRunSnapshot
          ?.resolvedInput['change_request'],
      'Fix it',
    );
  });

  testWidgets('shows distinct saved Launch detail modes', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const setup = AutomationRunSetup(
      id: 'setup_1',
      definitionId: 'yaml_ok_branch',
      name: 'YAML OK Branch Test',
      runtimeTargetId: 'local',
    );
    final controller = _readyController()
      ..automationDefinitions = <AutomationDefinition>[
        _yamlOkDefinitionForRunTest(),
      ]
      ..automationRunSetups = const <AutomationRunSetup>[setup]
      ..selectedAutomationRunSetupId = setup.id
      ..automationRuntimeTargets = const <AutomationRuntimeTarget>[
        AutomationRuntimeTarget(
          id: 'local',
          name: 'This computer',
          kind: 'local',
          status: 'healthy',
        ),
      ]
      ..automationRuns = const <AutomationRun>[
        AutomationRun(
          id: 'run_1',
          definitionId: 'yaml_ok_branch',
          kind: automationRunbookKind,
          status: 'completed',
          state: 'done',
          input: <String, dynamic>{'workdir': '/tmp/yaml-ok'},
          output: <String, dynamic>{
            'files': <String>['/tmp/yaml-ok/result.txt'],
          },
          createdAt: '2026-05-28T10:00:00Z',
          updatedAt: '2026-05-28T10:03:05Z',
        ),
      ]
      ..selectedAutomationRunId = 'run_1'
      ..selectedAutomationLaunchRunSnapshot = const AutomationLaunchRunSnapshot(
        runId: 'run_1',
        launchId: 'setup_1',
        launchVersion: 3,
        runbookId: 'yaml_ok_branch',
        resolvedInput: <String, dynamic>{'workdir': '/tmp/yaml-ok'},
        target: <String, dynamic>{'runtime_target_id': 'local'},
      )
      ..selectedAutomationEvents = const <AutomationEvent>[
        AutomationEvent(
          id: 1,
          runId: 'run_1',
          type: 'step_started',
          message: 'runbook state action started',
          createdAt: '2026-05-28T10:00:01Z',
        ),
        AutomationEvent(
          id: 2,
          runId: 'run_1',
          type: 'step_succeeded',
          message: 'runbook state action succeeded',
          createdAt: '2026-05-28T10:00:02Z',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Launchpad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Launchpad').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Overview'));
    await tester.pumpAndSettle();

    expect(find.text('Setup'), findsNothing);
    expect(find.text('Inputs'), findsNothing);
    expect(find.text('Test'), findsNothing);

    await tester.tap(find.byTooltip('Details').last);
    await tester.pumpAndSettle();
    expect(find.text('Run on'), findsOneWidget);
    expect(find.text('This computer'), findsWidgets);
    expect(find.text('Codebase'), findsNothing);
    expect(find.text('Safety'), findsNothing);
    expect(find.text('Run Defaults'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('automation-run-input-workdir')),
      findsNothing,
    );

    await tester.ensureVisible(find.byTooltip('Runs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Runs'));
    await tester.pumpAndSettle();
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Ran'), findsOneWidget);
    expect(find.text('Status'), findsWidgets);
    final runTitle = find.text('YAML OK Branch');
    expect(runTitle, findsWidgets);
    expect(
      find.text(
        'Started ${formatStoredTimestampLocal('2026-05-28T10:00:00Z')}, '
        'updated ${formatStoredTimestampLocal('2026-05-28T10:03:05Z')}',
      ),
      findsOneWidget,
    );
    expect(find.text('Success'), findsOneWidget);

    await tester.tap(runTitle.last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Copy metrics'), findsOneWidget);
    expect(find.textContaining('Duration: 3m 5s'), findsOneWidget);
    expect(find.textContaining('Input fields: 1'), findsOneWidget);
    expect(find.textContaining('Output fields: 1'), findsOneWidget);
    expect(find.textContaining('Artifacts: 1'), findsOneWidget);
    expect(find.textContaining('Launch: YAML OK Branch Test'), findsOneWidget);
    expect(find.textContaining('Resolved inputs: 1'), findsOneWidget);
    expect(find.byTooltip('Copy events'), findsOneWidget);
    expect(find.textContaining('step_started'), findsOneWidget);
    expect(find.textContaining('step_succeeded'), findsOneWidget);

    await tester.tap(find.byTooltip('Artifacts'));
    await tester.pumpAndSettle();
    expect(find.text('File'), findsOneWidget);
    expect(find.text('/tmp/yaml-ok/result.txt'), findsOneWidget);
  });

  testWidgets('shows process-state runbook lifecycle in Builder', (
    tester,
  ) async {
    final controller = _readyController()
      ..automationDrafts = const <AutomationDraft>[
        AutomationDraft(
          id: 'draft_lifecycle',
          kind: automationRunbookKind,
          name: 'Lifecycle Flow',
          status: 'draft',
          body: <String, dynamic>{
            'kind': 'state_machine',
            'id': 'lifecycle_flow',
            'initial': 'plan',
            'authoring': <String, Object>{
              'builder': <String, Object>{
                'positions': <String, Object>{
                  'plan': <String, Object>{'x': 84.0, 'y': 84.0},
                  'done': <String, Object>{'x': 2200.0, 'y': 1400.0},
                },
              },
            },
            'states': <Object>[
              <String, Object>{
                'id': 'plan',
                'on_entry': <Object>[
                  <String, Object>{'id': 'plan_change', 'uses': 'mcp.call'},
                ],
                'transitions': <Object>[
                  <String, Object>{'trigger': 'succeeded', 'to': 'done'},
                  <String, Object>{'trigger': 'failed', 'to': 'blocked'},
                ],
              },
              <String, Object>{'id': 'blocked'},
              <String, Object>{'id': 'done'},
            ],
          },
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Builder'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('state-machine-canvas')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-palette')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-inspector')),
      findsNothing,
    );
    expect(find.byTooltip('Details'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-plan')),
      findsOneWidget,
    );
    expect(find.text('Plan'), findsWidgets);
    expect(find.text('Succeeded -> Done'), findsOneWidget);
    expect(find.text('Failed -> Blocked'), findsWidgets);
    expect(
      find.byKey(
        const ValueKey<String>('state-machine-exit-badge-plan-failed-blocked'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('task-graph-canvas')),
      findsNothing,
    );
  });

  testWidgets('filters state-machine edges and centers badge targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationDrafts = const <AutomationDraft>[
        AutomationDraft(
          id: 'draft_lifecycle',
          kind: automationRunbookKind,
          name: 'Lifecycle Flow',
          status: 'draft',
          body: <String, dynamic>{
            'kind': 'state_machine',
            'id': 'lifecycle_flow',
            'initial': 'plan',
            'authoring': <String, Object>{
              'builder': <String, Object>{
                'positions': <String, Object>{
                  'plan': <String, Object>{'x': 84.0, 'y': 84.0},
                  'review': <String, Object>{'x': 330.0, 'y': 84.0},
                  'blocked': <String, Object>{'x': 84.0, 'y': 320.0},
                  'done': <String, Object>{'x': 576.0, 'y': 84.0},
                },
              },
            },
            'states': <Object>[
              <String, Object>{
                'id': 'plan',
                'on_entry': <Object>[
                  <String, Object>{'id': 'plan_change', 'uses': 'mcp.call'},
                ],
                'transitions': <Object>[
                  <String, Object>{'trigger': 'succeeded', 'to': 'review'},
                  <String, Object>{'trigger': 'failed', 'to': 'blocked'},
                ],
              },
              <String, Object>{
                'id': 'review',
                'on_entry': <Object>[
                  <String, Object>{
                    'id': 'ask_operator',
                    'uses': 'human.request',
                  },
                ],
                'transitions': <Object>[
                  <String, Object>{'trigger': 'approved', 'to': 'done'},
                  <String, Object>{'trigger': 'rejected', 'to': 'blocked'},
                ],
              },
              <String, Object>{'id': 'blocked'},
              <String, Object>{'id': 'done'},
            ],
          },
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    final failedBadge = find.byKey(
      const ValueKey<String>('state-machine-exit-badge-plan-failed-blocked'),
    );
    expect(failedBadge, findsOneWidget);
    final reviewRect = tester.getRect(
      find.byKey(const ValueKey<String>('state-machine-node-review')),
    );
    final failedBadgeRect = tester.getRect(failedBadge);
    final planRect = tester.getRect(
      find.byKey(const ValueKey<String>('state-machine-node-plan')),
    );
    expect(failedBadgeRect.top, greaterThan(planRect.top + 72));
    expect(failedBadgeRect.right, lessThan(reviewRect.left));
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-toolbar-plan')),
      findsOneWidget,
    );

    await tester.tap(failedBadge);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-toolbar-blocked')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('state-machine-edge-mode-all')),
    );
    await tester.pump();
    expect(failedBadge, findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('state-machine-edge-mode-failures')),
    );
    await tester.pump();
    expect(failedBadge, findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('state-machine-edge-mode-decisions')),
    );
    await tester.pump();
    expect(failedBadge, findsNothing);
    expect(find.text('Rejected -> Blocked'), findsWidgets);
  });

  testWidgets('lays out runbook nodes in compact semantic ranks and lanes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, Object> actionState(
      String id,
      List<Map<String, Object>> transitions,
    ) {
      return <String, Object>{
        'id': id,
        'on_entry': <Object>[
          <String, Object>{'id': id, 'uses': 'mcp.call'},
        ],
        'transitions': transitions,
      };
    }

    final controller = _readyController()
      ..automationDrafts = <AutomationDraft>[
        AutomationDraft(
          id: 'draft_semantic_layout',
          kind: automationRunbookKind,
          name: 'Semantic Layout',
          status: 'draft',
          body: <String, dynamic>{
            'kind': 'state_machine',
            'id': 'semantic_layout',
            'initial': 'plan_change',
            'states': <Object>[
              actionState('plan_change', <Map<String, Object>>[
                <String, Object>{
                  'trigger': 'succeeded',
                  'to': 'implement_change',
                },
                <String, Object>{
                  'trigger': 'failed',
                  'to': 'operator_decision',
                },
              ]),
              actionState('implement_change', <Map<String, Object>>[
                <String, Object>{'trigger': 'succeeded', 'to': 'verify_change'},
                <String, Object>{
                  'trigger': 'failed',
                  'to': 'operator_decision',
                },
              ]),
              actionState('verify_change', <Map<String, Object>>[
                <String, Object>{'trigger': 'succeeded', 'to': 'review_change'},
                <String, Object>{'trigger': 'failed', 'to': 'repair_change'},
                <String, Object>{
                  'trigger': 'blocked',
                  'to': 'operator_decision',
                },
              ]),
              actionState('review_change', <Map<String, Object>>[
                <String, Object>{'trigger': 'succeeded', 'to': 'completed'},
                <String, Object>{'trigger': 'failed', 'to': 'repair_change'},
              ]),
              actionState('repair_change', <Map<String, Object>>[
                <String, Object>{
                  'trigger': 'succeeded',
                  'to': 'implement_change',
                },
                <String, Object>{
                  'trigger': 'failed',
                  'to': 'operator_decision',
                },
              ]),
              <String, Object>{
                'id': 'operator_decision',
                'on_entry': <Object>[
                  <String, Object>{
                    'id': 'operator_decision',
                    'uses': 'human.request',
                  },
                ],
                'transitions': <Object>[
                  <String, Object>{'trigger': 'revise', 'to': 'plan_change'},
                  <String, Object>{'trigger': 'approve', 'to': 'review_change'},
                  <String, Object>{'trigger': 'abandon', 'to': 'abandoned'},
                ],
              },
              <String, Object>{'id': 'completed'},
              <String, Object>{'id': 'abandoned'},
            ],
          },
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    Rect node(String id) =>
        tester.getRect(find.byKey(ValueKey<String>('state-machine-node-$id')));

    final plan = node('plan_change');
    final implement = node('implement_change');
    final verify = node('verify_change');
    final review = node('review_change');
    final repair = node('repair_change');
    final operator = node('operator_decision');
    final abandoned = node('abandoned');

    expect(implement.left, greaterThan(plan.left));
    expect(verify.left, greaterThan(implement.left));
    expect(review.left, greaterThan(verify.left));
    expect(implement.left - plan.left, lessThan(620));
    expect(verify.left - implement.left, lessThan(620));
    expect(repair.left, closeTo(review.left, 1));
    expect(repair.top, greaterThan(verify.bottom));
    expect(operator.top, greaterThan(repair.bottom));
    expect(abandoned.top, greaterThan(operator.bottom));
  });

  testWidgets('collapses and expands composite runbook phases in Builder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationDrafts = const <AutomationDraft>[
        AutomationDraft(
          id: 'draft_hierarchy',
          kind: automationRunbookKind,
          name: 'Hierarchical Flow',
          status: 'draft',
          body: <String, dynamic>{
            'kind': 'state_machine',
            'id': 'hierarchical_flow',
            'initial': 'intake',
            'authoring': <String, Object>{
              'builder': <String, Object>{
                'collapsed_phases': <Object>['intake'],
              },
            },
            'states': <Object>[
              <String, Object>{
                'id': 'intake',
                'initial': 'collect',
                'states': <Object>[
                  <String, Object>{
                    'id': 'collect',
                    'transitions': <Object>[
                      <String, Object>{'trigger': 'succeeded', 'to': 'done'},
                    ],
                  },
                ],
              },
              <String, Object>{'id': 'done'},
            ],
          },
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-intake')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-collect')),
      findsNothing,
    );
    expect(find.text('collapsed'), findsOneWidget);

    await tester.tap(find.byTooltip('Expand phase'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-collect')),
      findsOneWidget,
    );
  });

  testWidgets('drops runbook states into expanded composite phases', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationDrafts = const <AutomationDraft>[
        AutomationDraft(
          id: 'draft_hierarchy',
          kind: automationRunbookKind,
          name: 'Hierarchical Flow',
          status: 'draft',
          body: <String, dynamic>{
            'kind': 'state_machine',
            'id': 'hierarchical_flow',
            'initial': 'intake',
            'states': <Object>[
              <String, Object>{
                'id': 'intake',
                'initial': 'collect',
                'states': <Object>[
                  <String, Object>{'id': 'collect'},
                ],
              },
              <String, Object>{'id': 'done'},
            ],
          },
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    final paletteItem = find.byKey(
      const ValueKey<String>('state-machine-palette-mcp.call'),
    );
    final phaseDrop = find.byKey(
      const ValueKey<String>('state-machine-phase-drop-intake'),
    );
    expect(paletteItem, findsOneWidget);
    expect(phaseDrop, findsOneWidget);

    await tester.dragFrom(
      tester.getCenter(paletteItem),
      tester.getCenter(phaseDrop) - tester.getCenter(paletteItem),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-call_mcp_tool')),
      findsOneWidget,
    );
  });

  testWidgets('renames nested phase initial child in Builder', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(<AutomationDraft>[_hierarchyEditDraft()]);
    controller.automationDrafts = harness.client.drafts;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'collect');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('state-machine-state-id-field')),
        matching: find.byType(EditableText),
      ),
      'gather',
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-gather')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-collect')),
      findsNothing,
    );
  });

  testWidgets('deleting phase initial child selects remaining child', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(<AutomationDraft>[_hierarchyEditDraft()]);
    controller.automationDrafts = harness.client.drafts;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'collect');
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('state-machine-node-toolbar-collect'),
        ),
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-collect')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-review')),
      findsOneWidget,
    );
  });

  testWidgets('setting nested initial updates containing phase', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(<AutomationDraft>[_hierarchyEditDraft()]);
    controller.automationDrafts = harness.client.drafts;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'review');
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('state-machine-node-toolbar-review'),
        ),
        matching: find.byIcon(Icons.flag_outlined),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('state-machine-node-review')),
        matching: find.text('initial'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('state-machine-node-collect')),
        matching: find.text('initial'),
      ),
      findsNothing,
    );
  });

  testWidgets('focuses composite phases with breadcrumb navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(<AutomationDraft>[_hierarchyEditDraft()]);
    controller.automationDrafts = harness.client.drafts;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'intake');
    await tester.tap(find.byTooltip('Focus phase'));
    await tester.pumpAndSettle();

    expect(find.text('Runbook'), findsOneWidget);
    expect(find.text('Intake'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-collect')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-review')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-intake')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-done')),
      findsNothing,
    );
    expect(find.byTooltip('Back to runbook'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to runbook'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-intake')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-done')),
      findsOneWidget,
    );

    await _tapStateMachineNode(tester, 'intake');
    await tester.tap(find.byTooltip('Focus phase'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-collect')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-intake')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('state-machine-focus-empty')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-intake')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-done')),
      findsOneWidget,
    );
  });

  testWidgets('palette add in phase focus creates a child state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(<AutomationDraft>[_hierarchyEditDraft()]);
    controller.automationDrafts = harness.client.drafts;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'intake');
    await tester.tap(find.byTooltip('Focus phase'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('state-machine-palette-mcp.call')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-call_mcp_tool')),
      findsOneWidget,
    );
    expect(find.text('Call MCP Tool'), findsWidgets);
  });

  testWidgets('focused phase initials update the phase not root', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(<AutomationDraft>[_hierarchyEditDraft()]);
    controller.automationDrafts = harness.client.drafts;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'intake');
    await tester.tap(find.byTooltip('Focus phase'));
    await tester.pumpAndSettle();
    await _tapStateMachineNode(tester, 'review');
    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('state-machine-node-toolbar-review'),
        ),
        matching: find.byIcon(Icons.flag_outlined),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('state-machine-node-review')),
        matching: find.text('initial'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('state-machine-focus-empty')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('state-machine-node-intake')),
        matching: find.text('initial'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('focus supports nested phases independently', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationDrafts = <AutomationDraft>[_nestedPhaseFocusDraft()];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'quality');
    await tester.tap(find.byTooltip('Focus phase'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-review_phase')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-review')),
      findsNothing,
    );

    await _tapStateMachineNode(tester, 'review_phase');
    await tester.tap(find.byTooltip('Focus phase'));
    await tester.pumpAndSettle();

    expect(find.text('Quality'), findsWidgets);
    expect(find.text('Review Phase'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-review')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-test')),
      findsNothing,
    );
  });

  testWidgets('dragging onto a focused child phase reparents the state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationDrafts = <AutomationDraft>[_nestedPhaseFocusDraft()];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'quality');
    await tester.tap(find.byTooltip('Focus phase'));
    await tester.pumpAndSettle();

    final testNode = find.byKey(
      const ValueKey<String>('state-machine-node-test'),
    );
    final reviewPhaseNode = find.byKey(
      const ValueKey<String>('state-machine-node-review_phase'),
    );
    final delta =
        tester.getCenter(reviewPhaseNode) - tester.getCenter(testNode);
    final dragGesture = await tester.startGesture(tester.getCenter(testNode));
    await tester.pump();
    await dragGesture.moveBy(delta);
    await tester.pump();
    await dragGesture.up();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-test')),
      findsNothing,
    );

    await _tapStateMachineNode(tester, 'review_phase');
    await tester.tap(find.byTooltip('Focus phase'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-test')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-review')),
      findsOneWidget,
    );
  });

  testWidgets('focused external exits render as badges and navigate scope', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationDrafts = <AutomationDraft>[_focusedExitDraft()];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'intake');
    await tester.tap(find.byTooltip('Focus phase'));
    await tester.pumpAndSettle();

    final badge = find.byKey(
      const ValueKey<String>('state-machine-exit-badge-collect-succeeded-done'),
    );
    expect(badge, findsOneWidget);
    expect(find.text('Succeeded -> Done'), findsWidgets);

    await tester.tap(badge);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-done')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-intake')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-node-collect')),
      findsOneWidget,
    );
  });

  testWidgets('inspector auto-maps action inputs from runbook contracts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationDrafts = const <AutomationDraft>[
        AutomationDraft(
          id: 'draft_structured_action',
          kind: automationRunbookKind,
          name: 'Structured Action',
          status: 'draft',
          body: <String, dynamic>{
            'kind': 'state_machine',
            'id': 'structured_action',
            'initial': 'assert_input',
            'states': <Object>[
              <String, Object>{
                'id': 'assert_input',
                'on_entry': <Object>[
                  <String, Object>{
                    'id': 'assert_input',
                    'uses': 'data.assert',
                    'with': <String, Object>{
                      'checks': <Object>[
                        <String, Object>{
                          'path': 'runbook_input.base_ref',
                          'mode': 'exists',
                        },
                      ],
                    },
                  },
                ],
                'transitions': <Object>[
                  <String, Object>{'trigger': 'succeeded', 'to': 'prepare'},
                ],
              },
              <String, Object>{
                'id': 'prepare',
                'on_entry': <Object>[
                  <String, Object>{
                    'id': 'prepare',
                    'uses': 'mcp.call',
                    'with': <String, Object>{
                      'endpoint': 'command',
                      'tool': 'source.prepare',
                      'arguments': <String, Object>{'base_ref': ''},
                    },
                  },
                ],
                'transitions': <Object>[
                  <String, Object>{'trigger': 'succeeded', 'to': 'done'},
                ],
              },
              <String, Object>{'id': 'done'},
            ],
          },
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'prepare');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Arguments JSON'), findsNothing);
    expect(find.text('Raw arguments JSON'), findsNothing);
    expect(find.text('Endpoint'), findsOneWidget);
    expect(find.text('Tool'), findsWidgets);
    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('base_ref'), findsOneWidget);
    expect(find.text('Runbook input / base_ref'), findsOneWidget);
    expect(find.text(r'${runbook_input.base_ref}'), findsNothing);
    expect(find.text('Advanced definition'), findsOneWidget);
  });

  testWidgets(
    'inspector offers incoming envelope instead of every state output',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _readyController()
        ..automationDrafts = const <AutomationDraft>[
          AutomationDraft(
            id: 'draft_incoming_sources',
            kind: automationRunbookKind,
            name: 'Incoming Sources',
            status: 'draft',
            body: <String, dynamic>{
              'kind': 'state_machine',
              'id': 'incoming_sources',
              'initial': 'source',
              'states': <Object>[
                <String, Object>{
                  'id': 'source',
                  'on_entry': <Object>[
                    <String, Object>{
                      'id': 'source_action',
                      'uses': 'mcp.call',
                      'with': <String, Object>{
                        'endpoint': 'command',
                        'tool': 'source.fetch',
                        'arguments': <String, Object>{},
                      },
                    },
                  ],
                  'transitions': <Object>[
                    <String, Object>{'trigger': 'succeeded', 'to': 'target'},
                  ],
                },
                <String, Object>{
                  'id': 'target',
                  'on_entry': <Object>[
                    <String, Object>{
                      'id': 'target_action',
                      'uses': 'mcp.call',
                      'with': <String, Object>{
                        'endpoint': 'command',
                        'tool': 'target.apply',
                        'arguments': <String, Object>{'ticket_id': ''},
                      },
                    },
                  ],
                },
                <String, Object>{
                  'id': 'unrelated',
                  'on_entry': <Object>[
                    <String, Object>{
                      'id': 'unrelated_action',
                      'uses': 'mcp.call',
                      'with': <String, Object>{
                        'endpoint': 'command',
                        'tool': 'other.fetch',
                        'arguments': <String, Object>{},
                      },
                    },
                  ],
                },
              ],
            },
          ),
        ];

      await tester.pumpWidget(
        MaterialApp(home: AgentAwesomeShell(controller: controller)),
      );
      await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
      await tester.pumpAndSettle();

      await _tapStateMachineNode(tester, 'target');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Incoming result / ticket_id'), findsOneWidget);
      expect(find.text('Output from unrelated'), findsNothing);

      await tester.tap(find.text('Incoming result / ticket_id'));
      await tester.pumpAndSettle();

      expect(find.text('Literal value'), findsOneWidget);
      expect(find.text('Incoming result / ticket_id'), findsWidgets);
      expect(find.text('Incoming result / data'), findsNothing);
      expect(find.text('Incoming trigger'), findsNothing);
      expect(find.text('Output from source'), findsNothing);
      expect(find.text('Output from unrelated'), findsNothing);
    },
  );

  testWidgets('inspector handles list-valued action inputs', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationDrafts = const <AutomationDraft>[
        AutomationDraft(
          id: 'draft_list_input',
          kind: automationRunbookKind,
          name: 'List Input',
          status: 'draft',
          body: <String, dynamic>{
            'kind': 'state_machine',
            'id': 'list_input',
            'initial': 'assert_input',
            'states': <Object>[
              <String, Object>{
                'id': 'assert_input',
                'on_entry': <Object>[
                  <String, Object>{
                    'id': 'assert_input',
                    'uses': 'data.assert',
                    'with': <String, Object>{
                      'checks': <Object>[
                        <String, Object>{
                          'path': 'runbook_input.base_ref',
                          'mode': 'exists',
                        },
                      ],
                    },
                  },
                ],
              },
            ],
          },
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'assert_input');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Checks'), findsOneWidget);
    expect(find.textContaining('runbook_input.base_ref'), findsOneWidget);
  });

  testWidgets('aggregates repeated phase failure exits into one badge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationDrafts = const <AutomationDraft>[
        AutomationDraft(
          id: 'draft_quality',
          kind: automationRunbookKind,
          name: 'Quality Flow',
          status: 'draft',
          body: <String, dynamic>{
            'kind': 'state_machine',
            'id': 'quality_flow',
            'initial': 'quality',
            'states': <Object>[
              <String, Object>{
                'id': 'quality',
                'initial': 'test',
                'states': <Object>[
                  <String, Object>{
                    'id': 'test',
                    'transitions': <Object>[
                      <String, Object>{'trigger': 'succeeded', 'to': 'review'},
                      <String, Object>{'trigger': 'failed', 'to': 'blocked'},
                    ],
                  },
                  <String, Object>{
                    'id': 'review',
                    'transitions': <Object>[
                      <String, Object>{'trigger': 'succeeded', 'to': 'done'},
                      <String, Object>{'trigger': 'failed', 'to': 'blocked'},
                    ],
                  },
                ],
              },
              <String, Object>{'id': 'blocked'},
              <String, Object>{'id': 'done'},
            ],
          },
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>(
          'state-machine-exit-badge-quality-failed-blocked',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('failed x2 -> blocked'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('state-machine-exit-badge-test-failed-blocked'),
      ),
      findsNothing,
    );
  });

  testWidgets('edits process-state runbook nodes in Builder', (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationDrafts = const <AutomationDraft>[
        AutomationDraft(
          id: 'draft_lifecycle',
          kind: automationRunbookKind,
          name: 'Lifecycle Flow',
          status: 'draft',
          body: <String, dynamic>{
            'kind': 'state_machine',
            'id': 'lifecycle_flow',
            'initial': 'plan',
            'states': <Object>[
              <String, Object>{
                'id': 'plan',
                'on_entry': <Object>[
                  <String, Object>{'id': 'plan_change', 'uses': 'mcp.call'},
                ],
                'transitions': <Object>[
                  <String, Object>{'trigger': 'succeeded', 'to': 'done'},
                ],
              },
              <String, Object>{'id': 'done'},
            ],
          },
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Runbooks')));
    await tester.pumpAndSettle();

    final nodeFinder = find.byKey(
      const ValueKey<String>('state-machine-node-plan'),
    );
    final before = tester.getTopLeft(nodeFinder);
    final dragGesture = await tester.startGesture(tester.getCenter(nodeFinder));
    await tester.pump();
    await dragGesture.moveBy(const Offset(72, 36));
    await tester.pump();
    final during = tester.getTopLeft(nodeFinder);

    expect(during.dx, greaterThan(before.dx));
    expect(during.dy, greaterThan(before.dy));

    await dragGesture.up();
    await tester.pump();
    final after = tester.getTopLeft(nodeFinder);

    expect(after.dx, greaterThan(before.dx));
    expect(after.dy, greaterThan(before.dy));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('state-machine-inspector')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('state-machine-canvas')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-inspector')),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('state-machine-inspector')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final horizontalScroll = find.byKey(
      const PageStorageKey<String>('state-machine-canvas-horizontal-scroll'),
    );
    final verticalScroll = find.byKey(
      const PageStorageKey<String>('state-machine-canvas-vertical-scroll'),
    );
    final canvasCenter = tester.getCenter(horizontalScroll);
    await tester.dragFrom(canvasCenter, const Offset(-220, 0));
    await tester.pump();
    await tester.dragFrom(canvasCenter, const Offset(0, -180));
    await tester.pump();
    final horizontalBeforeInspect = tester
        .widget<SingleChildScrollView>(horizontalScroll)
        .controller!
        .offset;
    final verticalBeforeInspect = tester
        .widget<SingleChildScrollView>(verticalScroll)
        .controller!
        .offset;

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('state-machine-inspector')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('state-machine-canvas')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-inspector')),
      findsNothing,
    );
    expect(
      tester.widget<SingleChildScrollView>(horizontalScroll).controller!.offset,
      closeTo(horizontalBeforeInspect, 0.1),
    );
    expect(
      tester.widget<SingleChildScrollView>(verticalScroll).controller!.offset,
      closeTo(verticalBeforeInspect, 0.1),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('state-machine-state-id-field')),
        matching: find.byType(EditableText),
      ),
      'planning',
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-planning')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('state-machine-inspector')),
      findsNothing,
    );
    expect(
      tester.widget<SingleChildScrollView>(horizontalScroll).controller!.offset,
      closeTo(horizontalBeforeInspect, 0.1),
    );
    expect(
      tester.widget<SingleChildScrollView>(verticalScroll).controller!.offset,
      closeTo(verticalBeforeInspect, 0.1),
    );
  });

  testWidgets('opens global AI chat as a third pane from any workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationDefinitions = const <AutomationDefinition>[
        AutomationDefinition(
          id: 'daily_email',
          kind: automationRunbookKind,
          name: 'Daily Email',
          hash: 'abc',
        ),
      ]
      ..messages = <ChatMessage>[
        ChatMessage(
          id: 'm1',
          role: ChatRole.assistant,
          author: 'Agent Awesome',
          text: 'Draft ready.',
          createdAt: DateTime(2026, 5, 16, 10),
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Launchpad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AI chat'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.assistantChatPanelOpen, isTrue);
    expect(find.text('INBOX'), findsWidgets);
    expect(find.text('CONVERSATION'), findsOneWidget);
    expect(find.text('Draft ready.'), findsOneWidget);
    expect(find.byTooltip('Start new chat'), findsOneWidget);
    expect(find.byTooltip('Delete selected chat'), findsNothing);
    expect(find.byTooltip('Delete chat'), findsNothing);
  });

  testWidgets('keeps command panels side-by-side when AI chat opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController();

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Backlog').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AI chat'));
    await tester.pumpAndSettle();

    final queueOffset = tester.getTopLeft(find.text('QUEUE').first);
    final detailsOffset = tester.getTopLeft(find.text('DETAILS').first);
    final conversationOffset = tester.getTopLeft(
      find.text('CONVERSATION').first,
    );
    expect(controller.assistantChatPanelOpen, isTrue);
    expect((queueOffset.dy - detailsOffset.dy).abs(), lessThan(8));
    expect(detailsOffset.dx, greaterThan(queueOffset.dx));
    expect(conversationOffset.dx, greaterThan(detailsOffset.dx));
    final assistantPane = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('assistant-chat-split-pane')),
    );
    expect(assistantPane.position, DecorationPosition.foreground);
    final assistantDecoration = assistantPane.decoration;
    expect(assistantDecoration, isA<BoxDecoration>());
    final border = (assistantDecoration as BoxDecoration).border;
    expect(border, isA<Border>());
    expect(
      (border! as Border).left.width,
      AgentAwesomeStrokeTokens.dividerWidth,
    );
  });

  testWidgets('keeps chat command fields on the shared input fill', (
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
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    final commandFrame = tester.widget<Container>(
      find.byKey(const ValueKey<String>('global-command-input-frame')),
    );
    final commandDecoration = commandFrame.decoration;
    expect(commandDecoration, isA<BoxDecoration>());
    final commandColor = (commandDecoration! as BoxDecoration).color;
    final commandField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('global-command-input')),
    );
    expect(commandField.decoration?.filled, isFalse);
    expect(commandField.decoration?.hoverColor, Colors.transparent);

    final composerFrame = tester.widget<Container>(
      find.byKey(const ValueKey<String>('chat-thread-composer-frame')),
    );
    final composerDecoration = composerFrame.decoration;
    expect(composerDecoration, isA<BoxDecoration>());
    final composerColor = (composerDecoration! as BoxDecoration).color;
    expect(commandColor, composerColor);
    expect(commandColor, isNot(Colors.transparent));
    final composerField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('chat-thread-composer')),
    );
    expect(composerField.decoration?.filled, isFalse);
    expect(composerField.decoration?.hoverColor, Colors.transparent);
    expect(find.text('Message Agent Awesome in this chat...'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('chat-thread-composer')),
    );
    await tester.pump();
    expect(find.text('Message Agent Awesome in this chat...'), findsNothing);
    expect(find.text('No results for ""'), findsNothing);

    final filterFields = tester.widgetList<TextField>(
      find.byKey(const ValueKey<String>('command-subshell-filter')),
    );
    expect(filterFields, isNotEmpty);
    for (final field in filterFields) {
      expect(field.decoration?.filled, isFalse);
    }
  });

  testWidgets(
    'global AI chat header starts chats without local delete/collapse',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _readyController();

      await tester.pumpWidget(
        MaterialApp(home: AgentAwesomeShell(controller: controller)),
      );
      await tester.tap(find.byTooltip('AI chat'));
      await tester.pumpAndSettle();

      expect(find.text('CONVERSATION'), findsOneWidget);
      expect(find.byTooltip('Start new chat'), findsOneWidget);
      expect(find.byTooltip('Delete selected chat'), findsNothing);
      expect(find.byTooltip('Delete chat'), findsNothing);
      expect(find.byTooltip('Collapse panel'), findsNothing);
    },
  );

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
    expect(find.textContaining(RegExp(r'go\s+run')), findsNothing);

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
    expect(find.text('View source'), findsWidgets);
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
    expect(find.byTooltip('New chat'), findsNothing);

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
    controller.availableAgentConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: '/tmp/agent.yaml',
        kind: ConfigFileKind.agent,
        assigned: true,
        displayName: 'Personal',
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
    controller.availableAgentConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: '/tmp/agent.yaml',
        kind: ConfigFileKind.agent,
        assigned: true,
        displayName: 'Default Agent',
      ),
    ];
    controller.availableToolConfigs = <ConfigFileEntry>[
      ConfigFileEntry(
        path: '/tmp/tool.yaml',
        kind: ConfigFileKind.tool,
        assigned: true,
        displayName: 'Personal Tools',
      ),
    ];
    controller.availableMcpConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: '/tmp/mcp/memory/mcp.yaml',
        kind: ConfigFileKind.mcp,
        assigned: false,
        displayName: 'Memory MCP',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.text('Settings').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Settings'), findsWidgets);
    expect(find.byTooltip('App'), findsOneWidget);
    expect(find.byTooltip('Models'), findsOneWidget);
    expect(find.byTooltip('Memory'), findsOneWidget);
    expect(find.text('App settings'), findsOneWidget);
    expect(find.text('APP SETTINGS'), findsNothing);
    expect(find.text('CHAT DEFAULTS'), findsOneWidget);
    expect(find.text('Default agent'), findsOneWidget);
    expect(find.text('Default Agent'), findsWidgets);
    expect(find.text('APPLICATION MODELS'), findsOneWidget);
    expect(find.text('Summarize titles with a model.'), findsOneWidget);
    expect(find.text('Summary model'), findsOneWidget);
    expect(find.text('openai / gpt-mini'), findsOneWidget);

    expect(find.text('OS Tools'), findsNothing);
    expect(find.text('MCP Server'), findsNothing);

    await tester.tap(find.byTooltip('Models'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Summary Mini'), findsWidgets);
    expect(find.byTooltip('Add model config'), findsOneWidget);
    expect(find.byTooltip('Duplicate model config'), findsOneWidget);
    expect(find.byTooltip('Delete model config'), findsOneWidget);
    expect(find.byTooltip('Validations'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Agents')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Default Agent'), findsWidgets);
    expect(find.byTooltip('Agents'), findsWidgets);
    expect(find.byTooltip('Add agent config'), findsOneWidget);
    expect(find.byTooltip('Duplicate agent config'), findsWidgets);
    expect(find.byTooltip('Delete agent config'), findsWidgets);
    expect(find.text('Instruction'), findsWidgets);
    expect(find.byTooltip('Instructions'), findsNothing);
    expect(find.byTooltip('Validations'), findsNothing);
    expect(find.text('EFFECTIVE ACCESS'), findsOneWidget);
    expect(find.text('AGENT ACCESS'), findsOneWidget);
    expect(find.text('Readable domains'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byTooltip('Memory'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byTooltip('Add memory domain'), findsOneWidget);
    expect(find.byTooltip('Remove memory domain'), findsOneWidget);
    expect(find.text('EFFECTIVE ACCESS'), findsNothing);
    expect(find.text('AGENT ACCESS'), findsNothing);
    expect(find.text('Readable domains'), findsNothing);
    expect(find.text('Auto-start server'), findsOneWidget);
    expect(find.text('Memory domain enabled'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Managed'), findsNothing);
    expect(find.text('Domain ID'), findsNothing);
    expect(find.text('Endpoint'), findsNothing);
    expect(find.text('Health URL'), findsNothing);
    expect(find.text('Database path'), findsNothing);
    expect(find.text('Data directory'), findsNothing);
    expect(find.text('Working directory'), findsNothing);
    expect(find.text('Executable path'), findsNothing);
    expect(find.text('Arguments, one per line'), findsNothing);
    expect(find.text('http://127.0.0.1:1/mcp'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Auto-start server')).dy,
      lessThan(tester.getTopLeft(find.text('Name')).dy),
    );

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-MCP Servers')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('MCP SERVERS'), findsWidgets);
    expect(find.text('Memory MCP'), findsOneWidget);
    expect(find.text('DETAILS'), findsWidgets);
    expect(find.byTooltip('Details'), findsOneWidget);
    expect(find.byTooltip('Servers'), findsOneWidget);
    expect(find.byTooltip('Validations'), findsOneWidget);
    expect(find.byTooltip('Source'), findsNothing);
    expect(find.byTooltip('Add MCP config'), findsOneWidget);
    expect(find.byTooltip('Duplicate MCP config'), findsOneWidget);
    expect(find.byTooltip('Delete MCP config'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Tools')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('TOOLS'), findsWidgets);
    expect(find.text('Personal Tools'), findsOneWidget);
    expect(find.text('DETAILS'), findsWidgets);
    expect(find.byTooltip('Details'), findsOneWidget);
    expect(find.byTooltip('Commands'), findsOneWidget);
    expect(find.byTooltip('Launchpad'), findsOneWidget);
    expect(find.byTooltip('Validations'), findsOneWidget);
    expect(find.byTooltip('Source'), findsNothing);
    expect(find.text('Assigned'), findsNothing);
  });

  testWidgets('shows configured model validations in settings', (tester) async {
    const modelPath = '/tmp/model.yaml';
    const modelConfig = '''
default: openai:gpt-mini
providers:
  openai:
    name: OpenAI
    adapter: openai
    api-key: env:OPENAI_API_KEY
    default: gpt-mini
    url: https://api.openai.com/v1/chat/completions
    models:
      - id: gpt-mini
        model: gpt-5-mini
validations:
  - id: asks_for_context
    label: Asks for context
    mode: mocked
    prompt: Help me with the thing.
    assertions:
      - type: response-contains
        contains: context
''';
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      configFiles: _MemoryConfigFileStore(<String, String>{
        modelPath: modelConfig,
      }),
    );
    controller.runtimeProfile = _settingsProfile().copyWith(
      harness: _settingsProfile().harness.copyWith(modelConfigPath: modelPath),
    );
    controller.availableModelConfigs = <ConfigFileEntry>[
      const ConfigFileEntry(
        path: modelPath,
        kind: ConfigFileKind.model,
        assigned: true,
        displayName: 'OpenAI',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: Scaffold(
          body: SettingsDetailsPanel(
            controller: controller,
            section: 'Models',
            selectedModelConfigPath: modelPath,
            modeId: 'model-validations',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Asks for context', skipOffstage: false), findsWidgets);
    expect(find.text('Help me with the thing.'), findsWidgets);
    expect(find.text('1 assertions'), findsOneWidget);
    expect(find.byTooltip('Run validation'), findsOneWidget);
  });

  testWidgets('adds model validation cases from settings', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const modelPath = '/tmp/model.yaml';
    final store = _MemoryConfigFileStore(<String, String>{
      modelPath: '''
default: openai:gpt-mini
providers:
  openai:
    name: OpenAI
    adapter: openai
    api-key: env:OPENAI_API_KEY
    default: gpt-mini
    url: https://api.openai.com/v1/chat/completions
    models:
      - id: gpt-mini
        model: gpt-5-mini
''',
    });
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      configFiles: store,
    );
    controller.runtimeProfile = _settingsProfile().copyWith(
      harness: _settingsProfile().harness.copyWith(modelConfigPath: modelPath),
    );
    controller.availableModelConfigs = <ConfigFileEntry>[
      const ConfigFileEntry(
        path: modelPath,
        kind: ConfigFileKind.model,
        assigned: true,
        displayName: 'OpenAI',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: Scaffold(
          body: SettingsDetailsPanel(
            controller: controller,
            section: 'Models',
            selectedModelConfigPath: modelPath,
            modeId: 'model-validations',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('No model validations configured'), findsOneWidget);

    final addButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey<String>('agent-validations-add')),
    );
    addButton.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    expect(
      ModelConfigDocument.parse(store.files[modelPath]!).validations,
      hasLength(1),
    );
    expect(find.text('New validation', skipOffstage: false), findsWidgets);

    final labelField = find.widgetWithText(TextFormField, 'New validation');
    final modeField = find.byType(DropdownButtonFormField<String>).first;
    expect(labelField, findsOneWidget);
    expect(modeField, findsOneWidget);
    expect(
      (tester.getSize(labelField).height - tester.getSize(modeField).height)
          .abs(),
      lessThanOrEqualTo(1),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'New validation'),
      'Asks for context',
    );
    await tester.pump(const Duration(milliseconds: 650));
    await tester.enterText(
      find.byType(TextFormField).last,
      'command:rg.search_text',
    );
    await tester.pump(const Duration(milliseconds: 650));
    await tester.tap(find.text('Add parameter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'parameter'),
      'pattern',
    );
    await tester.pump(const Duration(milliseconds: 650));
    await tester.enterText(find.widgetWithText(TextFormField, 'value'), 'TODO');
    await tester.pump(const Duration(milliseconds: 650));

    final saved = ModelConfigDocument.parse(store.files[modelPath]!);
    expect(saved.validations, hasLength(1));
    expect(saved.validations.first.id, 'validation');
    expect(saved.validations.first.label, 'Asks for context');
    expect(
      saved.validations.first.assertions
          .where((assertion) => assertion.type == 'response-contains')
          .single
          .contains,
      'Expected',
    );
    expect(
      saved.validations.first.assertions
          .where((assertion) => assertion.type == 'tool-call')
          .single
          .equals,
      'command:rg.search_text',
    );
    expect(
      saved.validations.first.assertions
          .where((assertion) => assertion.path.endsWith('.pattern'))
          .single
          .equals,
      'TODO',
    );
  });

  testWidgets('renders agent validation run evidence', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: const Scaffold(
          body: SettingsAgentValidationEvidenceView(
            result: AgentValidationRunResult(
              id: 'asks_for_context',
              label: 'Asks for context',
              mode: 'mocked',
              prompt: 'Help me with the thing.',
              input: <String, dynamic>{'topic': 'docs'},
              fixtures: <String, dynamic>{'memory': 'Buy milk'},
              status: 'passed',
              response: AgentValidationResponseResult(
                text: 'I need more context before I search.',
                toolCalls: <AgentValidationToolCallResult>[
                  AgentValidationToolCallResult(
                    id: 'command:rg.search_text',
                    name: 'rg.search_text',
                    arguments: <String, dynamic>{'pattern': 'TODO'},
                  ),
                ],
                output: null,
              ),
              assertions: <AgentValidationAssertionResult>[
                AgentValidationAssertionResult(
                  type: 'response-contains',
                  path: 'response.text',
                  passed: true,
                  expected: 'context',
                  actual: 'I need more context before I search.',
                  message: '',
                ),
                AgentValidationAssertionResult(
                  type: 'required-assertion',
                  path: '',
                  passed: false,
                  expected: null,
                  actual: null,
                  message: 'agent validation has no real assertions',
                ),
              ],
              diagnostics: <AgentValidationDiagnostic>[],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Response'), findsOneWidget);
    expect(find.text('I need more context before I search.'), findsOneWidget);
    expect(find.text('Tool calls'), findsOneWidget);
    expect(find.textContaining('rg.search_text'), findsOneWidget);
    expect(find.text('Assertions'), findsOneWidget);
    expect(find.textContaining('passed response.text'), findsOneWidget);
    expect(
      find.textContaining('agent validation has no real assertions'),
      findsOneWidget,
    );
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Fixtures'), findsOneWidget);
  });

  testWidgets('renders agent validation tool-call references', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: const Scaffold(
          body: SettingsAgentValidationSummaryView(
            result: AgentValidationSuiteResult(
              total: 2,
              passed: 2,
              failed: 0,
              unsupported: 0,
              toolCallReferences: <String>[
                'command:rg.search_text',
                'mcp:memory.search_memory',
              ],
              results: <AgentValidationRunResult>[],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Tool calls 2'), findsOneWidget);
    expect(find.text('Tool call references'), findsOneWidget);
    expect(find.textContaining('command:rg.search_text'), findsOneWidget);
    expect(find.textContaining('mcp:memory.search_memory'), findsOneWidget);
  });

  testWidgets('renders agent validation package gate issues', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: const Scaffold(
          body: SettingsAgentValidationPackageIssuesView(
            result: AgentValidationFileResult(
              path: '/tmp/agent.yaml',
              name: 'agent',
              passed: false,
              unsupported: false,
              error: 'agent has no behavior validations',
              missingAssertions: <String>['placeholder_case'],
              missingToolCalls: <String>['agent'],
              unknownToolCalls: <String>['uses_search: command:missing.search'],
              invalidToolArguments: <String>[
                'uses_search: command:rg.search_text',
              ],
              result: AgentValidationSuiteResult(
                total: 0,
                passed: 0,
                failed: 0,
                unsupported: 0,
                toolCallReferences: <String>[],
                results: <AgentValidationRunResult>[],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Package error'), findsOneWidget);
    expect(find.text('agent has no behavior validations'), findsOneWidget);
    expect(find.text('Missing assertions'), findsOneWidget);
    expect(find.text('placeholder_case'), findsOneWidget);
    expect(find.text('Missing tool calls'), findsOneWidget);
    expect(find.text('agent'), findsOneWidget);
    expect(find.text('Unknown tool calls'), findsOneWidget);
    expect(find.textContaining('command:missing.search'), findsOneWidget);
    expect(find.text('Invalid tool arguments'), findsOneWidget);
    expect(find.textContaining('command:rg.search_text'), findsOneWidget);
  });

  testWidgets('runs tool validation coverage checks without configured cases', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const toolPath = '/tmp/tool.yaml';
    const toolConfig = '''
name: test-tools
local-exec:
  enabled: true
  default-timeout: 10s
  default-max-output-bytes: 65536
  commands:
    - name: rg
      executable: rg
      description: Search text.
      operations:
        - name: search_text
          description: Search text.
          args:
            - "{{pattern}}"
          input-schema:
            type: object
            properties:
              pattern:
                type: string
            required:
              - pattern
''';
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      configFiles: _MemoryConfigFileStore(<String, String>{
        toolPath: toolConfig,
      }),
    );
    controller.runtimeProfile = _settingsProfile().copyWith(
      harness: _settingsProfile().harness.copyWith(toolConfigPath: toolPath),
    );
    controller.availableToolConfigs = <ConfigFileEntry>[
      ConfigFileEntry(
        path: toolPath,
        kind: ConfigFileKind.tool,
        assigned: true,
        displayName: 'test-tools',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: Scaffold(body: ToolsCommandPanel(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byIcon(Icons.fact_check_outlined).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('No validations configured'), findsOneWidget);
    final runAllText = find.text('Run all');
    expect(runAllText, findsOneWidget);
    final runAll = tester.widget<SettingsValidationRunModeButton>(
      find.byType(SettingsValidationRunModeButton).first,
    );
    expect(runAll.onRun, isNotNull);
  });

  testWidgets('adds one authored command validation from tools screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const toolPath = '/tmp/tool.yaml';
    final store = _MemoryConfigFileStore(<String, String>{
      toolPath: '''
name: test-tools
local-exec:
  enabled: true
  default-timeout: 10s
  default-max-output-bytes: 65536
  commands:
    - name: rg
      executable: rg
      description: Search text.
      operations:
        - name: search_text
          description: Search text.
          args:
            - "{{pattern}}"
          input-schema:
            type: object
            properties:
              pattern:
                type: string
            required:
              - pattern
''',
    });
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      configFiles: store,
    );
    controller.runtimeProfile = _settingsProfile().copyWith(
      harness: _settingsProfile().harness.copyWith(toolConfigPath: toolPath),
    );
    controller.availableToolConfigs = <ConfigFileEntry>[
      ConfigFileEntry(
        path: toolPath,
        kind: ConfigFileKind.tool,
        assigned: true,
        displayName: 'test-tools',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: Scaffold(body: ToolsCommandPanel(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byIcon(Icons.fact_check_outlined).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.tap(find.text('Add validation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Mode'), findsNothing);
    expect(find.text('Description'), findsNothing);
    expect(find.text('Scenario'), findsOneWidget);
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Expected output'), findsOneWidget);
    expect(find.text('Expected error'), findsOneWidget);
    expect(find.text('None'), findsWidgets);
    expect(find.text('Agent tool call'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Add').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    final saved = ToolConfigDocument.parse(store.files[toolPath]!);
    expect(saved.validations, hasLength(2));
    final validation = saved.validations
        .where((validation) => validation.target.type == 'command-operation')
        .single;
    final runbookValidation = saved.validations
        .where((validation) => validation.target.type == 'runbook-node')
        .single;
    expect(validation.target.type, 'command-operation');
    expect(validation.target.command, 'rg');
    expect(validation.target.operation, 'search_text');
    expect(validation.mode, 'mocked');
    expect(validation.input['pattern'], 'sample');
    expect(validation.assertions.first.type, 'status');
    expect(validation.assertions.first.equals, 'succeeded');
    expect(
      validation.assertions
          .where((assertion) => assertion.path == 'stdout')
          .single
          .equals,
      '',
    );
    expect(runbookValidation.target.command, 'rg');
    expect(runbookValidation.target.operation, 'search_text');
    expect(runbookValidation.mode, 'mocked');
  });

  testWidgets('adds command and runbook envelope validations from one form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const toolPath = '/tmp/tool.yaml';
    final store = _MemoryConfigFileStore(<String, String>{
      toolPath: '''
name: test-tools
local-exec:
  enabled: true
  default-timeout: 10s
  default-max-output-bytes: 65536
  commands:
    - name: grep
      executable: grep
      description: Search text.
      operations:
        - name: recursive_search
          description: Search text.
          args:
            - -R
            - -n
            - "{{pattern}}"
            - "{{path}}"
          input-schema:
            type: object
            properties:
              pattern:
                type: string
              path:
                type: string
            required:
              - pattern
              - path
''',
    });
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      configFiles: store,
    );
    controller.runtimeProfile = _settingsProfile().copyWith(
      harness: _settingsProfile().harness.copyWith(toolConfigPath: toolPath),
    );
    controller.availableToolConfigs = <ConfigFileEntry>[
      ConfigFileEntry(
        path: toolPath,
        kind: ConfigFileKind.tool,
        assigned: true,
        displayName: 'test-tools',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: Scaffold(body: ToolsCommandPanel(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byIcon(Icons.fact_check_outlined).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.tap(find.text('Add validation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Expected status'), findsOneWidget);
    expect(find.text('Expected return code'), findsOneWidget);
    expect(find.text('Expected output'), findsOneWidget);
    expect(find.text('Expected error'), findsOneWidget);
    await tester.tap(find.text('None').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Contains').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(
      find.widgetWithText(TextField, 'Text').first,
      'needle',
    );
    await tester.tap(find.byTooltip('Add Expected output check'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.widgetWithText(TextField, 'Text'), findsNWidgets(3));
    await tester.tap(find.byTooltip('Delete check').at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.widgetWithText(FilledButton, 'Add').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    final saved = ToolConfigDocument.parse(store.files[toolPath]!);
    expect(saved.validations, hasLength(2));
    final commandValidation = saved.validations
        .where((validation) => validation.target.type == 'command-operation')
        .single;
    final validation = saved.validations
        .where((validation) => validation.target.type == 'runbook-node')
        .single;
    expect(commandValidation.target.command, 'grep');
    expect(commandValidation.target.operation, 'recursive_search');
    expect(
      commandValidation.assertions
          .where((assertion) => assertion.type == 'stdout-contains')
          .single
          .contains,
      'needle',
    );
    expect(
      commandValidation.assertions
          .where((assertion) => assertion.path == 'stderr')
          .single
          .equals,
      '',
    );
    expect(validation.target.type, 'runbook-node');
    expect(validation.target.command, 'grep');
    expect(validation.target.operation, 'recursive_search');
    expect(validation.mode, 'mocked');
    expect(
      validation.assertions.map((assertion) => assertion.path),
      containsAll(<String>[
        'output.request.template_id',
        'output.request.parameters.pattern',
        'output.request.parameters.path',
      ]),
    );
    expect(
      validation.assertions
          .where((assertion) => assertion.type == 'stdout-contains')
          .single
          .contains,
      'needle',
    );
  });

  testWidgets('adds one authored MCP validation from servers screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const mcpPath = '/tmp/mcp.yaml';
    final store = _MemoryConfigFileStore(<String, String>{
      mcpPath: '''
name: memory-mcp
mcp:
  enabled: true
  servers:
    - name: memory_memory
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
      tools:
        allow:
          - remember
''',
    });
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      configFiles: store,
    );
    controller.runtimeProfile = _settingsProfile();
    controller.availableMcpConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: mcpPath,
        kind: ConfigFileKind.mcp,
        assigned: true,
        displayName: 'memory_memory',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: Scaffold(body: McpServersCommandPanel(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byIcon(Icons.fact_check_outlined).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.tap(find.text('Add validation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Agent tool call'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Add').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    final saved = ToolConfigDocument.parse(store.files[mcpPath]!);
    expect(saved.validations, hasLength(2));
    final validation = saved.validations
        .where((validation) => validation.target.type == 'mcp-tool')
        .single;
    final runbookValidation = saved.validations
        .where((validation) => validation.target.type == 'runbook-node')
        .single;
    expect(validation.target.type, 'mcp-tool');
    expect(validation.target.mcpServer, 'memory_memory');
    expect(validation.target.mcpTool, 'remember');
    expect(validation.mode, 'mocked');
    expect(validation.assertions.first.type, 'status');
    expect(validation.assertions.first.equals, 'succeeded');
    expect(runbookValidation.target.mcpServer, 'memory_memory');
    expect(runbookValidation.target.mcpTool, 'remember');
  });

  testWidgets('groups tool validations by operation tabs', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const toolPath = '/tmp/tool.yaml';
    final store = _MemoryConfigFileStore(<String, String>{
      toolPath: '''
name: curl
local-exec:
  enabled: true
  default-timeout: 10s
  default-max-output-bytes: 65536
  commands:
    - name: curl
      executable: curl
      description: Transfer data.
      operations:
        - name: http_get
          description: Fetch text.
          args:
            - "{{url}}"
        - name: download_file
          description: Download a file.
          args:
            - "{{url}}"
            - "--output"
            - "{{output_path}}"
validations:
  - id: curl_http_get_mocked
    label: curl HTTP GET
    description: Fetches text with curl.
    mode: mocked
    target:
      type: command-operation
      command: curl
      operation: http_get
    expected:
      status: succeeded
    assertions:
      - type: status
        equals: succeeded
  - id: curl_download_file_mocked
    label: curl download file
    description: Downloads a file with curl.
    mode: mocked
    target:
      type: command-operation
      command: curl
      operation: download_file
    expected:
      status: succeeded
    assertions:
      - type: status
        equals: succeeded
''',
    });
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      configFiles: store,
    );
    controller.runtimeProfile = _settingsProfile().copyWith(
      harness: _settingsProfile().harness.copyWith(toolConfigPath: toolPath),
    );
    controller.availableToolConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: toolPath,
        kind: ConfigFileKind.tool,
        assigned: true,
        displayName: 'curl',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: Scaffold(body: ToolsCommandPanel(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byIcon(Icons.fact_check_outlined).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('http_get'), findsOneWidget);
    expect(find.text('download_file'), findsOneWidget);
    expect(find.text('curl HTTP GET'), findsOneWidget);
    expect(find.text('curl download file'), findsNothing);

    await tester.tap(find.text('download_file'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('curl HTTP GET'), findsNothing);
    expect(find.text('curl download file'), findsOneWidget);
  });

  testWidgets('shows cached failed tool validation evidence by target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final workspace = Directory.systemTemp.createTempSync(
      'aa-tool-validation-test-',
    );
    addTearDown(() {
      if (workspace.existsSync()) {
        workspace.deleteSync(recursive: true);
      }
    });
    final config = _testConfig(workspaceRoot: workspace.path);
    const toolPath = '/tmp/df-tool.yaml';
    final encoded = base64Url.encode(utf8.encode(toolPath)).replaceAll('=', '');
    final cacheFile = File(
      '${config.workspaceRoot}/build/tool-validations/$encoded.json',
    );
    cacheFile.parent.createSync(recursive: true);
    cacheFile.writeAsStringSync(
      jsonEncode(
        const ToolValidationSuiteResult(
          total: 1,
          passed: 0,
          failed: 1,
          unsupported: 0,
          coverage: ToolValidationCoverageResult(
            required: 0,
            covered: 0,
            missing: <ToolValidationCoverageItem>[],
          ),
          inputSchemaCoverage: ToolValidationCoverageResult(
            required: 0,
            covered: 0,
            missing: <ToolValidationCoverageItem>[],
          ),
          agentToolCalls: <String>[],
          agentToolContracts: <String, ToolValidationAgentToolContractResult>{},
          missingAssertions: <String>[],
          results: <ToolValidationRunResult>[
            ToolValidationRunResult(
              id: 'runner_df_failed',
              label: 'df filesystem usage',
              description: 'Command operation for df.filesystem_usage.',
              mode: 'mocked',
              status: 'failed',
              target: ToolValidationTargetResult(
                type: 'command-operation',
                presetId: '',
                command: 'df',
                operation: 'filesystem_usage',
                mcpServer: '',
                mcpTool: '',
                templateId: 'df.filesystem_usage',
                boundary: 'command.execute',
              ),
              command: ToolValidationCommandResult(
                jobId: 'job-1',
                status: 'failed',
                exitCode: 1,
                stdoutTail: '',
                stderrTail: 'df: /missing: No such file or directory',
                truncated: false,
                timedOut: false,
                error: '',
                startedAt: '2026-05-25T00:00:00Z',
                endedAt: '2026-05-25T00:00:01Z',
                output: <String, dynamic>{'text': ''},
                diagnostics: <ToolValidationCommandDiagnostic>[],
                artifacts: <ToolValidationCommandArtifact>[],
                validation: ToolValidationCommandOutputValidation(
                  checked: true,
                  valid: true,
                  errors: <String>[],
                ),
              ),
              assertions: <ToolValidationAssertionResult>[
                ToolValidationAssertionResult(
                  type: 'status',
                  path: '',
                  passed: false,
                  expected: 'succeeded',
                  actual: 'failed',
                  message: '',
                ),
              ],
              diagnostics: <ToolValidationDiagnostic>[],
            ),
          ],
        ).toJson(),
      ),
    );
    final cachedResult = ToolValidationSuiteResult.fromJson(
      jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>,
    );
    expect(cachedResult.failed, 1);
    final store = _MemoryConfigFileStore(<String, String>{
      toolPath: '''
name: df
local-exec:
  enabled: true
  default-timeout: 10s
  default-max-output-bytes: 65536
  commands:
    - name: df
      executable: df
      description: Show filesystem usage.
      operations:
        - name: filesystem_usage
          description: Show filesystem usage.
          args:
            - "{{path}}"
validations:
  - id: df_filesystem_usage_mocked
    label: df filesystem usage
    description: Validates the command boundary for df.filesystem_usage.
    mode: mocked
    target:
      type: command-operation
      command: df
      operation: filesystem_usage
    input:
      path: /missing
    expected:
      status: succeeded
    assertions:
      - type: status
        equals: succeeded
''',
    });
    final controller = AgentAwesomeAppController(
      config: config,
      configFiles: store,
    );
    controller.runtimeProfile = _settingsProfile().copyWith(
      harness: _settingsProfile().harness.copyWith(toolConfigPath: toolPath),
    );
    controller.availableToolConfigs = const <ConfigFileEntry>[
      ConfigFileEntry(
        path: toolPath,
        kind: ConfigFileKind.tool,
        assigned: true,
        displayName: 'df',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: Scaffold(body: ToolsCommandPanel(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('Validations').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('COMMAND VALIDATIONS'), findsOneWidget);
    expect(find.text('Failed 1'), findsOneWidget);
    expect(find.text('failed'), findsWidgets);
    expect(find.text('not run'), findsNothing);

    await tester.tap(find.text('df filesystem usage').first);
    await tester.pump();
    expect(find.text('Stderr'), findsOneWidget);
    expect(find.textContaining('No such file or directory'), findsOneWidget);
    expect(find.textContaining('df /missing'), findsOneWidget);
  });

  testWidgets('validation scenario table runs modes and deletes rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SettingsValidationRunRequest? requested;
    SettingsValidationScenario? deleted;
    final scenario = SettingsValidationScenario(
      id: 'curl.http_get',
      label: 'curl HTTP GET',
      description: 'Fetches text with curl.',
      status: 'succeeded',
      modeStates: const <String, SettingsValidationModeState>{
        'mocked': SettingsValidationModeState(
          mode: 'mocked',
          validationIds: <String>['curl_http_get_mocked'],
          status: 'succeeded',
        ),
        'live': SettingsValidationModeState(
          mode: 'live',
          validationIds: <String>['curl_http_get_live'],
          status: 'failed',
        ),
      },
      details: const Text('Expanded evidence'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: Scaffold(
          body: SettingsValidationScenarioTable(
            scenarios: <SettingsValidationScenario>[scenario],
            selectedRunMode: 'mocked',
            runningMode: '',
            runningValidationIds: const <String>{},
            runningAll: false,
            onRunAll: (request) => requested = request,
            onRunScenario: (request) => requested = request,
            onDeleteScenario: (scenario) => deleted = scenario,
            onAddValidation: () {},
          ),
        ),
      ),
    );

    expect(find.text('Validation'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Mocked'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Success'), findsWidgets);

    await tester.tap(find.text('Run all'));
    expect(requested!.mode, 'mocked');
    expect(requested!.validationIds, <String>['curl_http_get_mocked']);

    await tester.tap(find.byTooltip('Choose validation mode').first);
    await tester.pumpAndSettle();
    final allItem = tester.widget<PopupMenuItem<String>>(
      find.widgetWithText(PopupMenuItem<String>, 'All'),
    );
    expect(allItem.enabled, isTrue);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(requested!.mode, 'all');
    expect(requested!.validationIds, <String>[
      'curl_http_get_mocked',
      'curl_http_get_live',
    ]);

    await tester.tap(find.byTooltip('Delete validation'));
    expect(deleted!.id, 'curl.http_get');
  });

  testWidgets('validation scenario table gates live and all modes', (
    tester,
  ) async {
    final scenario = SettingsValidationScenario(
      id: 'curl.http_get',
      label: 'curl HTTP GET',
      description: 'Fetches text with curl.',
      status: '',
      modeStates: const <String, SettingsValidationModeState>{
        'mocked': SettingsValidationModeState(
          mode: 'mocked',
          validationIds: <String>['curl_http_get_mocked'],
          status: '',
        ),
        'live': SettingsValidationModeState(
          mode: 'live',
          validationIds: <String>['curl_http_get_live'],
          status: '',
        ),
      },
      details: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: Scaffold(
          body: SettingsValidationScenarioTable(
            scenarios: <SettingsValidationScenario>[scenario],
            selectedRunMode: 'mocked',
            runningMode: '',
            runningValidationIds: const <String>{},
            runningAll: false,
            liveAvailable: false,
            onRunAll: (_) {},
            onRunScenario: (_) {},
            onDeleteScenario: (_) {},
            onAddValidation: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Choose validation mode').first);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.widgetWithText(PopupMenuItem<String>, 'Live'),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.widgetWithText(PopupMenuItem<String>, 'All'),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('renders tool validation run evidence', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgentAwesomeTheme(),
        home: const Scaffold(
          body: SettingsToolValidationEvidenceView(
            targetLabel: 'rg TODO src',
            result: ToolValidationRunResult(
              id: 'rg_search_text_runbook',
              label: 'Runbook search',
              description: 'Runs rg through the runbook boundary.',
              mode: 'mocked',
              status: 'passed',
              target: ToolValidationTargetResult(
                type: 'runbook-node',
                presetId: '',
                command: 'rg',
                operation: 'search_text',
                mcpServer: '',
                mcpTool: '',
                templateId: 'rg.search_text',
                boundary: 'command.execute',
              ),
              command: ToolValidationCommandResult(
                jobId: 'job-1',
                status: 'succeeded',
                exitCode: 0,
                stdoutTail: 'src/example.go:TODO',
                stderrTail: '',
                truncated: false,
                timedOut: false,
                error: '',
                startedAt: '2026-05-25T00:00:00Z',
                endedAt: '2026-05-25T00:00:01Z',
                output: <String, dynamic>{'matches': 1},
                diagnostics: <ToolValidationCommandDiagnostic>[],
                artifacts: <ToolValidationCommandArtifact>[
                  ToolValidationCommandArtifact(
                    path: 'build/results.json',
                    size: 42,
                  ),
                ],
                validation: ToolValidationCommandOutputValidation(
                  checked: true,
                  valid: true,
                  errors: <String>[],
                ),
              ),
              assertions: <ToolValidationAssertionResult>[
                ToolValidationAssertionResult(
                  type: 'status',
                  path: '',
                  passed: true,
                  expected: 'succeeded',
                  actual: 'succeeded',
                  message: '',
                ),
              ],
              diagnostics: <ToolValidationDiagnostic>[
                ToolValidationDiagnostic(
                  severity: 'warning',
                  message: 'diagnostic detail',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Target'), findsOneWidget);
    expect(find.textContaining('rg TODO src'), findsOneWidget);
    expect(find.textContaining('Runbook node: rg.search_text'), findsNothing);
    expect(find.text('Command'), findsOneWidget);
    expect(find.textContaining('status succeeded'), findsOneWidget);
    expect(find.text('Stdout'), findsOneWidget);
    expect(find.text('src/example.go:TODO'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
    expect(find.textContaining('matches'), findsOneWidget);
    expect(find.text('Artifacts'), findsOneWidget);
    expect(find.textContaining('build/results.json'), findsOneWidget);
    expect(find.text('Assertions'), findsOneWidget);
    expect(find.textContaining('passed status'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.textContaining('diagnostic detail'), findsOneWidget);
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
    expect(find.text('CHATS'), findsOneWidget);
    expect(find.text('CONVERSATION'), findsOneWidget);
    expect(find.byTooltip('Memory'), findsOneWidget);
    expect(find.byTooltip('Tasks'), findsOneWidget);
    expect(find.byTooltip('Files'), findsOneWidget);
    expect(find.byTooltip('People'), findsOneWidget);
    expect(find.byTooltip('Runtime'), findsOneWidget);
    expect(find.text('Chat message from user in session-live'), findsNothing);
    expect(find.byTooltip('Select chat'), findsNothing);
    expect(find.byTooltip('Start new chat'), findsOneWidget);
    expect(find.byTooltip('Delete selected chat'), findsOneWidget);
    expect(find.byTooltip('Chats'), findsOneWidget);
    expect(find.byTooltip('Sessions'), findsNothing);
    expect(find.text('Live chat'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    expect(
      find.text(
        'Connected chat message. Preference noted. Review Quarterly plan.pdf. Done - created Follow up report.',
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip('AI chat is unavailable in this view'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('AI chat is unavailable in this view'));
    await tester.pumpAndSettle();
    expect(controller.assistantChatPanelOpen, isFalse);

    await tester.tap(find.byTooltip('Memory'));
    await tester.pumpAndSettle();

    expect(find.text('MEMORY'), findsWidgets);
    expect(find.text('Preference'), findsWidgets);
    expect(find.byTooltip('AI chat'), findsOneWidget);
    await tester.tap(find.byTooltip('AI chat'));
    await tester.pumpAndSettle();
    expect(controller.assistantChatPanelOpen, isTrue);
    expect(find.text('CONVERSATION'), findsOneWidget);
    await tester.tap(find.byTooltip('AI chat'));
    await tester.pumpAndSettle();
    expect(controller.assistantChatPanelOpen, isFalse);

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

    await tester.tap(find.byTooltip('Conversation'));
    await tester.pumpAndSettle();
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
    expect(find.text('AGENTS'), findsOneWidget);
    expect(find.text('RECENT CHATS'), findsOneWidget);
    expect(find.text('WORKSPACES'), findsNothing);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('All Chats'), findsOneWidget);
    expect(find.text('Personal'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey<String>('global-command-input')),
      'Start from selected agent',
    );
    await tester.pump();
    expect(find.text('AGENTS'), findsNothing);
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
    expect(find.byTooltip('Delete chat'), findsNothing);
    expect(find.text('Alternate planning chat'), findsOneWidget);
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
    expect(find.byTooltip('New chat'), findsNothing);
    expect(find.text('Setup incomplete'), findsNothing);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('CONVERSATION'), findsOneWidget);

    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();
    expect(find.text('RECORDS'), findsOneWidget);
    expect(find.text('No memory records'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('global-command-input')),
    );
    await tester.pump();
    expect(find.text('No runtime agents configured'), findsNothing);
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
    expect(find.text('RECORDS'), findsOneWidget);
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('Preference'), findsWidgets);
    expect(find.text('MEMORY'), findsWidgets);
    expect(find.byTooltip('Refresh'), findsNothing);
    await tester.tap(find.byTooltip('Metadata'));
    await tester.pumpAndSettle();

    expect(find.text('METADATA REPAIR'), findsOneWidget);

    await tester.tap(find.byTooltip('Pages'));
    await tester.pumpAndSettle();

    expect(find.text('PAGE TOOLS'), findsOneWidget);
    expect(find.text('No compiled page loaded'), findsOneWidget);
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
    expect(find.text('RECORDS'), findsNothing);
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
    expect(find.text('Add file'), findsNothing);
    expect(find.byTooltip('Add file'), findsOneWidget);
    expect(find.byTooltip('Refresh files'), findsNothing);
    expect(find.text('Immutable source material from memory.'), findsNothing);
    expect(find.text('No source content loaded'), findsNothing);

    await tester.tap(find.byTooltip('Add file'));
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

  testWidgets('shows contact manager from memory and tasks', (tester) async {
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
    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();

    expect(find.text('CONTACTS'), findsOneWidget);
    expect(find.text('PROFILE'), findsWidgets);
    expect(find.text('All contacts 3'), findsOneWidget);
    expect(find.text('Active 1'), findsOneWidget);
    expect(find.text('Sources 2'), findsOneWidget);
    expect(find.text('Mina'), findsWidgets);
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

    expect(find.text('Add contact'), findsNothing);
    expect(find.byTooltip('Add contact'), findsOneWidget);
    await tester.tap(find.byTooltip('Add contact'));
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
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('Draft task brief'), findsWidgets);
    expect(find.byTooltip('Delete backlog item'), findsWidgets);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Backlog Stream'), findsNothing);
    expect(find.byTooltip('Stream'), findsOneWidget);
    expect(find.byTooltip('Map'), findsOneWidget);
    await tester.tap(find.byTooltip('Stream'));
    await tester.pumpAndSettle();
    expect(find.text('STREAM'), findsWidgets);
    expect(find.text('TASK'), findsNothing);
    expect(find.text('Analyze stream layout'), findsOneWidget);
    expect(find.text('Backlog Stream'), findsNothing);
    expect(find.text('Workload'), findsNothing);
    expect(find.byTooltip('Memory'), findsOneWidget);
    await tester.tap(find.byTooltip('Memory'));
    await tester.pumpAndSettle();
    expect(find.text('No memory selected'), findsOneWidget);
    expect(find.text('No linked memory'), findsOneWidget);
    await tester.tap(find.byTooltip('Details').last);
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

      expect(find.text('REVIEW'), findsOneWidget);
      expect(find.text('Priority changed to high'), findsWidgets);
      await tester.tap(find.byTooltip('Focus change'));
      await tester.pumpAndSettle();
      expect(controller.focusedBacklogTaskId, 'task-brief');

      await tester.tap(find.text('Draft task brief').first);
      await tester.pumpAndSettle();

      expect(find.text('DETAILS'), findsOneWidget);
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
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('CONVERSATION'), findsOneWidget);
    expect(find.text('What changed here?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('global-command-input')),
      findsOneWidget,
    );
    expect(find.byTooltip('New chat'), findsNothing);
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
    expect(find.text('AGENTS'), findsOneWidget);

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

  testWidgets('hides old work-management timeline routes', (tester) async {
    final controller = _readyController();

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('WORK MANAGEMENT'), findsNothing);
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

/// Returns a runbook definition with schema-backed run inputs for UI tests.
AutomationDefinition _sourceChangeDefinitionForRunTest() {
  return const AutomationDefinition(
    id: 'source_change_runbook',
    kind: automationRunbookKind,
    name: 'Source Change Runbook',
    hash: 'sha256:professional',
    body: <String, dynamic>{
      'authoring': <String, Object>{
        'input_defaults': <String, Object>{
          'repository_path': r'${app.workspace_root}',
        },
        'run_setup': <String, Object>{
          'setup_fields': <Object>[
            'repository_path',
            'package_path',
            'binary_package',
          ],
          'run_fields': <Object>['change_request'],
        },
      },
      'states': <Object>[
        <String, Object>{
          'id': 'intake',
          'on_entry': <Object>[
            <String, Object>{
              'id': 'normalized_input',
              'uses': 'data.defaults',
              'with': <String, Object>{
                'input': r'${runbook_input}',
                'defaults': <String, Object>{
                  'remote': 'origin',
                  'branch_summary': r'${runbook_input.change_request}',
                  'pull_request_draft': false,
                },
              },
            },
            <String, Object>{
              'id': 'assert_input',
              'uses': 'data.assert',
              'with': <String, Object>{
                'mode': 'schema',
                'schema': <String, Object>{
                  'type': 'object',
                  'required': <Object>[
                    'repository_path',
                    'change_request',
                    'remote',
                    'pull_request_draft',
                  ],
                  'properties': <String, Object>{
                    'repository_path': <String, Object>{'type': 'string'},
                    'change_request': <String, Object>{'type': 'string'},
                    'remote': <String, Object>{'type': 'string'},
                    'pull_request_draft': <String, Object>{'type': 'boolean'},
                  },
                },
              },
            },
          ],
        },
      ],
    },
  );
}

/// Returns the YAML branch runbook used by generic Launch UI tests.
AutomationDefinition _yamlOkDefinitionForRunTest() {
  return const AutomationDefinition(
    id: 'yaml_ok_branch',
    kind: automationRunbookKind,
    name: 'YAML OK Branch',
    hash: 'sha256:yaml-ok',
    body: <String, dynamic>{
      'input_schema': <String, Object>{
        'type': 'object',
        'required': <Object>['workdir'],
        'properties': <String, Object>{
          'workdir': <String, Object>{'type': 'string'},
        },
      },
    },
  );
}

/// Creates a ready app controller with an injectable automation client.
_CapturingAutomationHarness _readyCapturingController() {
  final profile = _managedTestProfile();
  final profileDirectory = Directory('/tmp/agentawesome-test');
  profileDirectory.createSync(recursive: true);
  final profileFile = File('${profileDirectory.path}/runtime-profile-test.json')
    ..writeAsStringSync(jsonEncode(profile.toJson()));
  final config = _testConfig(runtimeProfilePath: profileFile.path);
  final processSupervisor = ProcessSupervisor(
    logDirectory: config.serviceLogDirectory,
    workspaceRoot: config.workspaceRoot,
  );
  final client = _CapturingAutomationsClient();
  final settingsStore = _MemoryAppSettingsStore()
    ..saved = const AgentAwesomeAppSettings(gettingStartedCompleted: true);
  final toolRpc = _EmptyToolRpcClient();
  final controller = AgentAwesomeAppController(
    config: config,
    processSupervisor: processSupervisor,
    assistantClient: _EmptyAssistantClient(),
    memoryClient: MemoryClient(rpc: toolRpc),
    tasksClient: TasksClient(rpc: toolRpc),
    executiveSummaryClient: ExecutiveSummaryClient(rpc: toolRpc),
    automationsClient: client,
    appSettingsStore: settingsStore,
    localServices: _ReadyLocalServiceSupervisor(
      config: config,
      processSupervisor: processSupervisor,
    ),
  );
  controller.appSettings = const AgentAwesomeAppSettings(
    gettingStartedCompleted: true,
  );
  controller.runtimeProfile = profile;
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
  return _CapturingAutomationHarness(controller: controller, client: client);
}

/// _CapturingAutomationHarness groups the controller under test and fake client.
class _CapturingAutomationHarness {
  /// Creates a harness for builder hierarchy assertions.
  const _CapturingAutomationHarness({
    required this.controller,
    required this.client,
  });

  /// App controller configured with [client].
  final AgentAwesomeAppController controller;

  /// Fake automation client that keeps drafts in memory.
  final _CapturingAutomationsClient client;
}

/// _ReadyLocalServiceSupervisor avoids subprocess startup in UI tests.
class _ReadyLocalServiceSupervisor extends LocalServiceSupervisor {
  /// Creates a supervisor that reports all required services as ready.
  _ReadyLocalServiceSupervisor({
    required super.config,
    required super.processSupervisor,
  });

  /// Reports readiness without launching or probing local services.
  @override
  Future<List<ServiceProcessStatus>> startRequiredServices(
    RuntimeProfile profile, {
    bool restartAutoStarted = false,
    bool includeHarness = true,
    bool includeMcpServers = true,
  }) async {
    return const <ServiceProcessStatus>[];
  }
}

/// _EmptyAssistantClient keeps controller initialization offline.
class _EmptyAssistantClient extends AssistantClient {
  /// Creates an assistant client that returns no remote sessions.
  _EmptyAssistantClient()
    : super(baseUrl: 'http://127.0.0.1:1/api', appName: 'test', userId: 'user');

  /// Returns no chat sessions.
  @override
  Future<List<ChatSession>> listSessions() async {
    return const <ChatSession>[];
  }
}

/// _EmptyToolRpcClient returns empty projections for initialization tests.
class _EmptyToolRpcClient implements ToolRpcClient {
  /// Creates an offline tool RPC client.
  const _EmptyToolRpcClient();

  /// Synthetic endpoint shown in client metadata.
  @override
  String get endpoint => 'memory://empty';

  /// Returns empty structured content for read-only startup tools.
  @override
  Future<dynamic> callTool(
    String name, [
    Map<String, dynamic>? arguments,
  ]) async {
    return switch (name) {
      'list_tasks' => const <Object>[],
      'list_task_relations' => const <Object>[],
      'query_context_graph' => const <String, Object>{'rows': <Object>[]},
      'task_graph_projection' => const <String, Object>{},
      'search_memory' => const <String, Object>{'primary_memory': <Object>[]},
      'search_sources' => const <String, Object>{'primary_memory': <Object>[]},
      'project_executive_summary' => const <String, Object>{},
      _ => const <String, Object>{},
    };
  }

  /// Lists enough tool names for projection checks to pass.
  @override
  Future<List<String>> listToolNames() async {
    return const <String>['task_graph_projection'];
  }

  /// Closes no resources.
  @override
  void close() {}
}

/// _CapturingAutomationsClient stores runbook drafts in memory for UI tests.
class _CapturingAutomationsClient extends AutomationsClient {
  /// Creates a fake runbook client.
  _CapturingAutomationsClient() : super(baseUrl: 'http://127.0.0.1:1');

  /// Editable draft list returned by [listDrafts].
  List<AutomationDraft> drafts = const <AutomationDraft>[];

  /// Published definition list returned by [listDefinitions].
  List<AutomationDefinition> definitions = const <AutomationDefinition>[];

  /// Run list returned by [listRuns].
  List<AutomationRun> runs = const <AutomationRun>[];

  /// Saved Launch list returned by [listRunSetups].
  List<AutomationRunSetup> runSetups = const <AutomationRunSetup>[];

  /// Capability list returned by [listCapabilities].
  List<AutomationCapability> capabilities = const <AutomationCapability>[];

  /// Computer or Server targets returned by [listRuntimeTargets].
  List<AutomationRuntimeTarget> runtimeTargets =
      const <AutomationRuntimeTarget>[];

  /// Health metadata keyed by target id.
  Map<String, AutomationTargetHealth> targetHealthById =
      const <String, AutomationTargetHealth>{};

  /// Log rows keyed by target id.
  Map<String, List<AutomationTargetLogEntry>> targetLogsById =
      const <String, List<AutomationTargetLogEntry>>{};

  /// Secret metadata keyed by target id.
  Map<String, AutomationTargetSecretMetadata> targetSecretsById =
      const <String, AutomationTargetSecretMetadata>{};

  /// Last draft passed to [updateDraft].
  AutomationDraft? savedDraft;

  /// Last setup passed to [createRunSetup].
  AutomationRunSetup? createdRunSetup;

  /// Last setup passed to [updateRunSetup].
  AutomationRunSetup? updatedRunSetup;

  /// Last kind passed to [createDraft].
  String createdKind = '';

  /// Last definition id passed to [startRun].
  String startedDefinitionId = '';

  /// Last input payload passed to [startRun].
  Map<String, dynamic> startedInput = const <String, dynamic>{};

  /// Last reusable setup id passed to [startRunSetup].
  String startedRunSetupId = '';

  /// Last reusable setup id passed to [previewRunSetup].
  String previewedRunSetupId = '';

  /// Launch run snapshots keyed by run id.
  Map<String, AutomationLaunchRunSnapshot> snapshotsByRunId =
      const <String, AutomationLaunchRunSnapshot>{};

  /// Replaces the in-memory draft list.
  void seedDrafts(List<AutomationDraft> value) {
    drafts = List<AutomationDraft>.of(value);
    savedDraft = null;
    createdKind = '';
  }

  /// Replaces the in-memory published definition list.
  void seedDefinitions(List<AutomationDefinition> value) {
    definitions = List<AutomationDefinition>.of(value);
    startedDefinitionId = '';
    startedInput = const <String, dynamic>{};
  }

  /// Replaces the in-memory Launch list.
  void seedRunSetups(List<AutomationRunSetup> value) {
    runSetups = List<AutomationRunSetup>.of(value);
    createdRunSetup = null;
    updatedRunSetup = null;
    startedRunSetupId = '';
    startedInput = const <String, dynamic>{};
  }

  @override
  Future<List<AutomationDraft>> listDrafts() async {
    return drafts;
  }

  @override
  Future<List<AutomationActionType>> listActionTypes() async {
    return const <AutomationActionType>[];
  }

  @override
  Future<List<AutomationDefinition>> listDefinitions() async {
    return definitions;
  }

  @override
  Future<List<AutomationPackage>> listPackages() async {
    return const <AutomationPackage>[];
  }

  @override
  Future<List<AutomationCapability>> listCapabilities({
    String kind = '',
    bool? usableInChat,
    bool? usableInRunbooks,
  }) async {
    return capabilities.where((capability) {
      if (kind.trim().isNotEmpty && capability.kind != kind.trim()) {
        return false;
      }
      if (usableInChat != null && capability.usableInChat != usableInChat) {
        return false;
      }
      if (usableInRunbooks != null &&
          capability.usableInRunbooks != usableInRunbooks) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<List<AutomationRuntimeTarget>> listRuntimeTargets() async {
    return runtimeTargets;
  }

  @override
  Future<AutomationTargetHealth> targetHealth(String targetId) async {
    final recorded = targetHealthById[targetId];
    if (recorded != null) {
      return recorded;
    }
    AutomationRuntimeTarget? target;
    for (final candidate in runtimeTargets) {
      if (candidate.id == targetId) {
        target = candidate;
        break;
      }
    }
    return AutomationTargetHealth(
      targetId: targetId,
      status: target?.status ?? 'unknown',
      version: target?.version ?? '',
      os: target?.os ?? '',
      hostname: target?.hostname ?? '',
      currentRunCount: target?.currentRunCount ?? 0,
    );
  }

  @override
  Future<List<AutomationTargetLogEntry>> targetLogs(String targetId) async {
    return targetLogsById[targetId] ?? const <AutomationTargetLogEntry>[];
  }

  @override
  Future<AutomationTargetSecretMetadata> targetSecrets(String targetId) async {
    var count = 0;
    for (final target in runtimeTargets) {
      if (target.id == targetId) {
        count = target.secretRefCount;
        break;
      }
    }
    return targetSecretsById[targetId] ??
        AutomationTargetSecretMetadata(targetId: targetId, count: count);
  }

  @override
  Future<List<AutomationRun>> listRuns({
    String status = '',
    String definitionId = '',
    int limit = 100,
  }) async {
    return runs;
  }

  @override
  Future<List<AutomationRunSetup>> listRunSetups({
    String definitionId = '',
  }) async {
    if (definitionId.trim().isEmpty) {
      return runSetups;
    }
    return runSetups
        .where((setup) => setup.definitionId == definitionId)
        .toList();
  }

  @override
  Future<List<AutomationPendingItem>> inbox() async {
    return const <AutomationPendingItem>[];
  }

  @override
  Future<List<AutomationEvent>> history(String runId) async {
    return const <AutomationEvent>[];
  }

  @override
  Future<AutomationDraft> createDraft({
    required String kind,
    required String name,
    String description = '',
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    createdKind = kind;
    final draft = AutomationDraft(
      id: 'draft_${drafts.length + 1}',
      kind: kind,
      name: name,
      description: description,
      status: 'draft',
      body: body.isEmpty
          ? <String, dynamic>{
              'apiVersion': automationRunbookApiVersion,
              'kind': 'state_machine',
              'id': 'runbook_${drafts.length + 1}',
              'initial': 'start',
              'states': const <Object>[
                <String, Object>{'id': 'start'},
              ],
            }
          : body,
    );
    drafts = <AutomationDraft>[draft, ...drafts];
    return draft;
  }

  @override
  Future<AutomationDraft> updateDraft(AutomationDraft draft) async {
    savedDraft = draft;
    drafts = <AutomationDraft>[
      for (final existing in drafts) existing.id == draft.id ? draft : existing,
    ];
    if (!drafts.any((existing) => existing.id == draft.id)) {
      drafts = <AutomationDraft>[...drafts, draft];
    }
    return draft;
  }

  @override
  Future<AutomationRun> startRun(
    String definitionId, {
    Map<String, dynamic> input = const <String, dynamic>{},
  }) async {
    startedDefinitionId = definitionId;
    startedInput = Map<String, dynamic>.from(input);
    final run = AutomationRun(
      id: 'run_${runs.length + 1}',
      definitionId: definitionId,
      kind: automationRunbookKind,
      status: 'running',
      state: 'running',
    );
    runs = <AutomationRun>[run, ...runs];
    return run;
  }

  @override
  Future<AutomationRunSetup> createRunSetup({
    required String definitionId,
    required String name,
    String description = '',
    String codebaseId = '',
    String runtimeTargetId = '',
    String agentProfileId = '',
    Map<String, dynamic> input = const <String, dynamic>{},
    Map<String, dynamic> policy = const <String, dynamic>{},
    Map<String, dynamic> schedule = const <String, dynamic>{},
  }) async {
    final setup = AutomationRunSetup(
      id: 'setup_${runSetups.length + 1}',
      definitionId: definitionId,
      name: name,
      description: description,
      codebaseId: codebaseId,
      runtimeTargetId: runtimeTargetId,
      agentProfileId: agentProfileId,
      input: Map<String, dynamic>.from(input),
      policy: Map<String, dynamic>.from(policy),
      schedule: Map<String, dynamic>.from(schedule),
    );
    createdRunSetup = setup;
    runSetups = <AutomationRunSetup>[setup, ...runSetups];
    return setup;
  }

  @override
  Future<AutomationRunSetup> updateRunSetup(AutomationRunSetup setup) async {
    updatedRunSetup = setup;
    runSetups = <AutomationRunSetup>[
      for (final existing in runSetups)
        if (existing.id == setup.id) setup else existing,
    ];
    if (!runSetups.any((existing) => existing.id == setup.id)) {
      runSetups = <AutomationRunSetup>[setup, ...runSetups];
    }
    return setup;
  }

  @override
  Future<AutomationLaunchPreview> previewRunSetup(
    String setupId, {
    Map<String, dynamic> input = const <String, dynamic>{},
  }) async {
    previewedRunSetupId = setupId;
    final setup = runSetups.firstWhere(
      (candidate) => candidate.id == setupId,
      orElse: () => AutomationRunSetup(
        id: setupId,
        definitionId: 'unknown',
        name: 'Unknown',
      ),
    );
    final resolved = <String, dynamic>{...setup.input, ...input};
    final missing = <String>[
      if ('${resolved['change_request'] ?? ''}'.trim().isEmpty)
        'change_request',
    ];
    return AutomationLaunchPreview(
      launch: setup,
      status: missing.isEmpty ? 'ready' : 'needs_input',
      resolvedInput: resolved,
      missingSetup: missing,
      policyDecision: const AutomationLaunchPolicyDecision(status: 'allowed'),
    );
  }

  @override
  Future<AutomationRun> startRunSetup(
    String setupId, {
    Map<String, dynamic> input = const <String, dynamic>{},
  }) async {
    startedRunSetupId = setupId;
    startedInput = Map<String, dynamic>.from(input);
    final setup = runSetups.firstWhere(
      (candidate) => candidate.id == setupId,
      orElse: () => AutomationRunSetup(
        id: setupId,
        definitionId: 'unknown',
        name: 'Unknown',
      ),
    );
    final run = AutomationRun(
      id: 'run_${runs.length + 1}',
      definitionId: setup.definitionId,
      kind: automationRunbookKind,
      status: 'running',
      state: 'running',
    );
    runs = <AutomationRun>[run, ...runs];
    return run;
  }

  @override
  Future<AutomationLaunchRunSnapshot> launchRunSnapshot(String runId) async {
    final snapshot = snapshotsByRunId[runId];
    if (snapshot == null) {
      throw StateError('snapshot not found');
    }
    return snapshot;
  }
}

/// Creates a runbook graph draft for Builder shell tests.
AutomationDraft _runbookGraphDraft() {
  return const AutomationDraft(
    id: 'draft_runbook_graph',
    kind: automationRunbookKind,
    name: 'Runbook Graph',
    status: 'draft',
    body: <String, dynamic>{
      'apiVersion': automationRunbookApiVersion,
      'kind': automationRunbookKind,
      'id': 'runbook_graph',
      'nodes': <Object>[],
    },
  );
}

/// Creates a nested state-machine draft for hierarchy editing tests.
AutomationDraft _hierarchyEditDraft() {
  return const AutomationDraft(
    id: 'draft_hierarchy_edit',
    kind: automationRunbookKind,
    name: 'Hierarchy Edit',
    status: 'draft',
    body: <String, dynamic>{
      'kind': 'state_machine',
      'id': 'hierarchy_edit',
      'initial': 'intake',
      'states': <Object>[
        <String, Object>{
          'id': 'intake',
          'initial': 'collect',
          'states': <Object>[
            <String, Object>{'id': 'collect'},
            <String, Object>{'id': 'review'},
          ],
        },
        <String, Object>{'id': 'done'},
      ],
      'authoring': <String, Object>{
        'builder': <String, Object>{
          'positions': <String, Object>{
            'intake': <String, double>{'x': 96, 'y': 140},
            'collect': <String, double>{'x': 508, 'y': 140},
            'review': <String, double>{'x': 508, 'y': 380},
            'done': <String, double>{'x': 920, 'y': 140},
          },
        },
      },
    },
  );
}

/// Creates a nested phase draft for focused hierarchy navigation tests.
AutomationDraft _nestedPhaseFocusDraft() {
  return const AutomationDraft(
    id: 'draft_nested_focus',
    kind: automationRunbookKind,
    name: 'Nested Focus',
    status: 'draft',
    body: <String, dynamic>{
      'kind': 'state_machine',
      'id': 'nested_focus',
      'initial': 'quality',
      'authoring': <String, Object>{
        'builder': <String, Object>{
          'positions': <String, Object>{
            'quality': <String, double>{'x': 96, 'y': 140},
            'test': <String, double>{'x': 96, 'y': 140},
            'review_phase': <String, double>{'x': 508, 'y': 140},
            'review': <String, double>{'x': 96, 'y': 140},
            'done': <String, double>{'x': 920, 'y': 140},
          },
        },
      },
      'states': <Object>[
        <String, Object>{
          'id': 'quality',
          'initial': 'test',
          'states': <Object>[
            <String, Object>{'id': 'test'},
            <String, Object>{
              'id': 'review_phase',
              'initial': 'review',
              'states': <Object>[
                <String, Object>{'id': 'review'},
              ],
            },
          ],
        },
        <String, Object>{'id': 'done'},
      ],
    },
  );
}

/// Creates a focused phase draft with an exit that leaves the current scope.
AutomationDraft _focusedExitDraft() {
  return const AutomationDraft(
    id: 'draft_focused_exit',
    kind: automationRunbookKind,
    name: 'Focused Exit',
    status: 'draft',
    body: <String, dynamic>{
      'kind': 'state_machine',
      'id': 'focused_exit',
      'initial': 'intake',
      'states': <Object>[
        <String, Object>{
          'id': 'intake',
          'initial': 'collect',
          'states': <Object>[
            <String, Object>{
              'id': 'collect',
              'transitions': <Object>[
                <String, Object>{'trigger': 'succeeded', 'to': 'done'},
              ],
            },
          ],
        },
        <String, Object>{'id': 'done'},
      ],
    },
  );
}

/// Taps the card face for one state-machine node.
Future<void> _tapStateMachineNode(WidgetTester tester, String stateId) async {
  final finder = find.byKey(ValueKey<String>('state-machine-node-$stateId'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final rect = tester.getRect(finder);
  await tester.tapAt(rect.topLeft + const Offset(36, 110));
  await tester.pumpAndSettle();
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
      good: <String>['Tasks & projects'],
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

class _MemoryConfigFileStore extends ConfigFileStore {
  _MemoryConfigFileStore(this.files);

  final Map<String, String> files;

  /// Reads a test configuration file from memory.
  @override
  Future<String> read(String path) async {
    final content = files[path];
    if (content == null) {
      throw FileSystemException('Missing config file', path);
    }
    return content;
  }

  /// Writes a test configuration file to memory.
  @override
  Future<void> write(String path, String content) async {
    files[path] = content;
  }

  /// Lists in-memory configuration files for collection refreshes.
  @override
  Future<List<ConfigFileEntry>> list({
    required ConfigFileKind kind,
    String assignedPath = '',
  }) async {
    return <ConfigFileEntry>[
      for (final path in files.keys)
        ConfigFileEntry(
          path: path,
          kind: kind,
          assigned: path == assignedPath,
          displayName: path.split('/').last,
        ),
    ];
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
      executablePath: '/tmp/bin/agent-awesome',
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
      executablePath: '/tmp/bin/agent-gateway',
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
        executablePath: '/tmp/bin/memoryd',
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

/// Returns a test profile whose config paths pass managed-path validation.
RuntimeProfile _managedTestProfile() {
  final profile = _settingsProfile();
  return profile.copyWith(
    harness: profile.harness.copyWith(
      modelConfigPath: defaultModelConfigPath(),
      agentConfigPath: '${agentConfigsDirectoryPath()}/agent.yaml',
      toolConfigPath: toolPackageConfigPath('test-tools'),
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
        executablePath: '/tmp/bin/memoryd',
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
        executablePath: '/tmp/bin/memoryd',
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

AppConfig _testConfig({
  String runtimeProfilePath = '',
  String workspaceRoot = '/tmp/agentawesome-test',
}) {
  return AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:1/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:2/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:1/mcp',
    agentAppName: 'test',
    agentUserId: 'user',
    workspaceRoot: workspaceRoot,
    autoStartLocalServices: false,
    runtimeProfilePath: runtimeProfilePath,
  );
}
