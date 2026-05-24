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
import 'package:agentawesome_ui/domain/automation_contracts.dart';
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
    expect(find.text('INSPECTOR'), findsOneWidget);
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
          name: 'workflow.run',
          label: 'Run Workflow',
          description: 'Start a nested workflow.',
          risk: 'workflow',
          available: true,
        ),
      ]
      ..automationToolNames = const <String>{'email.search', 'browser.read'}
      ..automationDefinitions = const <AutomationDefinition>[
        AutomationDefinition(
          id: 'daily_email',
          kind: automationWorkflowKind,
          name: 'Daily Email',
          hash: 'abc',
        ),
      ]
      ..automationDrafts = const <AutomationDraft>[
        AutomationDraft(
          id: 'draft_review',
          kind: automationWorkflowKind,
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
        AutomationDraft(
          id: 'draft_task',
          kind: automationTaskGraphKind,
          name: 'Task Flow',
          status: 'draft',
          body: <String, dynamic>{
            'kind': automationTaskGraphKind,
            'id': 'task_flow',
            'nodes': <Object>[
              <String, Object>{
                'id': 'fetch_email',
                'uses': 'mcp.call',
                'with': <String, Object>{
                  'endpoint': 'http://127.0.0.1:8090/mcp',
                  'tool': 'email.search',
                  'arguments': <String, Object>{},
                },
              },
              <String, Object>{
                'id': 'classify_email',
                'uses': 'tool.call',
                'depends_on': <Object>['fetch_email'],
                'with': <String, Object>{'name': 'email.classify'},
              },
              <String, Object>{
                'id': 'summarize_email',
                'uses': 'tool.call',
                'depends_on': <Object>['fetch_email'],
                'with': <String, Object>{'name': 'email.summarize'},
              },
              <String, Object>{
                'id': 'prepare_review',
                'uses': 'workflow.run',
                'depends_on': <Object>['classify_email', 'summarize_email'],
                'with': <String, Object>{'workflow': 'review_flow'},
              },
            ],
          },
        ),
      ]
      ..automationRuns = const <AutomationRun>[
        AutomationRun(
          id: 'run_1',
          definitionId: 'daily_email',
          kind: automationWorkflowKind,
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
          usableInWorkflows: true,
          invocation: <String, Object>{
            'direct_tool_name': 'command_execute',
            'workflow_action': 'command.execute',
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
    expect(find.text('Operations'), findsWidgets);
    expect(find.text('Workflows'), findsOneWidget);
    expect(find.text('Tasks'), findsNothing);
    expect(find.text('Agents'), findsNothing);
    expect(find.text('MCP Servers'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('›'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Operations')));
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
    expect(find.text('INBOX'), findsWidgets);
    expect(find.byTooltip('Inbox'), findsOneWidget);
    expect(find.byTooltip('Files'), findsOneWidget);
    expect(find.byTooltip('Operations'), findsWidgets);
    expect(find.byTooltip('Codebases'), findsOneWidget);
    expect(find.byTooltip('Computers'), findsOneWidget);
    expect(find.byTooltip('Schedules'), findsOneWidget);
    expect(find.byTooltip('Artifacts'), findsOneWidget);
    expect(find.byTooltip('Runs'), findsWidgets);
    expect(find.byTooltip('Refresh automations'), findsNothing);
    expect(find.text('Approve archive?'), findsOneWidget);
    expect(find.text('Daily Email'), findsNothing);
    await tester.tap(find.byTooltip('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Daily Email'), findsWidgets);
    await tester.tap(find.byTooltip('Operations').last);
    await tester.pumpAndSettle();
    expect(find.text('Daily Email Setup'), findsOneWidget);
    await tester.tap(find.byTooltip('Codebases'));
    await tester.pumpAndSettle();
    expect(find.text('Agent Awesome'), findsWidgets);
    await tester.tap(find.byTooltip('Computers'));
    await tester.pumpAndSettle();
    expect(find.text('This computer'), findsWidgets);
    expect(find.text('Status: healthy'), findsOneWidget);
    await tester.tap(find.byTooltip('Schedules'));
    await tester.pumpAndSettle();
    expect(find.text('No scheduled operations'), findsOneWidget);
    await tester.tap(find.byTooltip('Artifacts'));
    await tester.pumpAndSettle();
    expect(find.text('No artifacts'), findsOneWidget);
    await tester.tap(find.byTooltip('Runs').first);
    await tester.pumpAndSettle();
    expect(find.text('run_1 / running'), findsNothing);
    expect(find.text('running'), findsWidgets);

    expect(find.byKey(const ValueKey<String>('sidebar-Agents')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('sidebar-Workflows')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('sidebar-Tasks')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
    await tester.pumpAndSettle();

    expect(find.text('ACTIONS'), findsWidgets);
    expect(find.byTooltip('Builder'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('task-graph-canvas')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('task-graph-action-data.assert')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('sidebar-Tasks')), findsNothing);
    expect(find.byTooltip('Capabilities'), findsOneWidget);

    await tester.tap(find.byTooltip('Files'));
    await tester.pumpAndSettle();

    expect(find.text('FILES'), findsWidgets);
    expect(find.text('Filter files...'), findsOneWidget);
    expect(find.text('Review Flow'), findsWidgets);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('task-graph-action-data.assert')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('task-graph-canvas')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Capabilities'));
    await tester.pumpAndSettle();

    expect(find.text('CAPABILITIES'), findsWidgets);
    expect(find.text('Go test all'), findsWidgets);
    expect(find.text('Workflow action: command.execute'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-MCP Servers')));
    await tester.pumpAndSettle();

    expect(find.text('FILES'), findsWidgets);
    expect(find.text('SERVERS'), findsWidgets);
    expect(find.text('No MCP server files configured'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Tools')));
    await tester.pumpAndSettle();

    expect(find.text('FILES'), findsWidgets);
    expect(find.text('COMMANDS'), findsWidgets);
    expect(find.text('No tool files configured'), findsWidgets);
  });

  testWidgets('does not render passive Automations status blocks', (
    tester,
  ) async {
    final controller = _readyController()
      ..automationsMessage = 'Automations refreshed'
      ..automationDefinitions = const <AutomationDefinition>[
        AutomationDefinition(
          id: 'ready',
          kind: automationWorkflowKind,
          name: 'Ready',
          hash: 'sha256:ready',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Operations')));
    await tester.pumpAndSettle();

    expect(find.text('Status'), findsNothing);
    expect(find.text('Automations refreshed'), findsNothing);
  });

  testWidgets('opens Operations workflow run input dialog', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDefinitions(<AutomationDefinition>[
      _professionalCodingDefinitionForRunTest(),
    ]);
    controller.automationDefinitions = harness.client.definitions;
    controller.selectedAutomationDefinitionId = 'professional_coding_change';
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Operations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Files'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('automation-start-run-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Run Professional Coding Change'), findsOneWidget);
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
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('automation-run-input-remote')),
      findsNothing,
    );
  });

  testWidgets('creates reusable Operations from typed fields', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDefinitions(<AutomationDefinition>[
      _professionalCodingDefinitionForRunTest(),
    ]);
    controller.automationDefinitions = harness.client.definitions;
    controller.selectedAutomationDefinitionId = 'professional_coding_change';

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Operations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Files'));
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

    expect(find.text('Create Operation'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('automation-run-setup-name')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('automation-run-setup-codebase')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('automation-run-setup-target')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('automation-run-setup-safety')),
      findsOneWidget,
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

    expect(find.widgetWithText(FilledButton, 'Create'), findsOneWidget);
  });

  testWidgets('shows enabled right-aligned workflow create action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(<AutomationDraft>[_workflowGraphDraft()]);
    controller.automationDrafts = harness.client.drafts;
    controller.selectedAutomationDraftId = harness.client.drafts.first.id;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Files'));
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
      const ValueKey<String>('automation-new-workflow-draft-button'),
    );
    expect(createButton, findsOneWidget);
    final createTapTarget = find.descendant(
      of: createButton,
      matching: find.byType(GestureDetector),
    );
    expect(createTapTarget, findsOneWidget);
    expect(tester.widget<GestureDetector>(createTapTarget).onTap, isNotNull);
    final paneRight = tester
        .getTopRight(
          find.byKey(const ValueKey<String>('main-content-left-pane')),
        )
        .dx;
    final buttonRight = tester.getTopRight(createTapTarget).dx;
    expect(paneRight - buttonRight, lessThanOrEqualTo(28));
    expect(find.text('Workflow name'), findsNothing);

    await tester.tap(createTapTarget);
    await tester.pumpAndSettle();
    expect(find.text('FILES'), findsWidgets);
    expect(find.text('Filter files...'), findsOneWidget);
    expect(find.text('draft_workflow_graph'), findsNothing);
  });

  testWidgets('renames workflow drafts from the catalog title', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(<AutomationDraft>[_workflowGraphDraft()]);
    controller.automationDrafts = harness.client.drafts;
    controller.selectedAutomationDraftId = harness.client.drafts.first.id;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Files'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Workflow Graph'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('automation-draft-title-editor')),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Rename workflow file'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('automation-draft-title-editor')),
      'Renamed Workflow',
    );
    await tester.tap(find.text('FILES'));
    await tester.pump();

    expect(controller.automationsMessage, 'Saving Renamed Workflow');
    expect(find.text('draft_workflow_graph'), findsNothing);
  });

  testWidgets('shows workflow graph fields in Inspect mode', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _readyCapturingController();
    final controller = harness.controller;
    harness.client.seedDrafts(<AutomationDraft>[_workflowGraphDraft()]);
    controller.automationDrafts = harness.client.drafts;
    controller.selectedAutomationDraftId = harness.client.drafts.first.id;

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('task-graph-canvas')),
      findsOneWidget,
    );
    expect(find.text('ACTIONS'), findsOneWidget);

    await tester.tap(find.byTooltip('Inspect'));
    await tester.pumpAndSettle();

    expect(find.text('INSPECT'), findsOneWidget);
    expect(find.text('FILES'), findsWidgets);
    expect(find.text('Workflow name'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('task-graph-canvas')),
      findsNothing,
    );
  });

  testWidgets('shows state-machine definitions as workflow files', (
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
        id: 'draft_professional_coding_change',
        kind: 'state_machine',
        name: 'Professional Coding Change',
        status: 'published',
        body: <String, dynamic>{
          'kind': 'state_machine',
          'id': 'professional_coding_change',
          'initial': 'intake',
          'states': <Object>[
            <String, Object>{'id': 'intake'},
            <String, Object>{'id': 'source_control_prep'},
          ],
        },
      ),
    ]);
    controller.automationDrafts = harness.client.drafts;
    controller.selectedAutomationDraftId = 'draft_professional_coding_change';

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('state-machine-node-intake')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Professional Coding Change'), findsWidgets);
    expect(find.text('workflow'), findsWidgets);
  });

  test('creates workflow drafts with the workflow API kind', () async {
    final harness = _readyCapturingController();
    harness.client.seedDrafts(const <AutomationDraft>[]);

    await harness.controller.createAutomationDraftFromUi(
      kind: automationWorkflowKind,
      name: 'New Workflow',
    );

    expect(
      harness.client.createdKind,
      automationWorkflowKind,
      reason: harness.controller.automationsMessage,
    );
    expect(harness.controller.selectedAutomationDraftId, 'draft_1');
  });

  test('starts workflow definitions with input payloads', () async {
    final harness = _readyCapturingController();
    const definition = AutomationDefinition(
      id: 'professional_coding_change',
      kind: automationWorkflowKind,
      name: 'Professional Coding Change',
      hash: 'sha256:professional',
    );

    await harness.controller.startAutomationDefinitionFromUi(
      definition,
      input: const <String, dynamic>{
        'repository_path': '/repo',
        'change_request': 'Fix it',
      },
    );

    expect(harness.client.startedDefinitionId, 'professional_coding_change');
    expect(harness.client.startedInput['repository_path'], '/repo');
    expect(harness.client.startedInput['change_request'], 'Fix it');
    expect(harness.controller.selectedAutomationRunId, 'run_1');
  });

  test('creates and starts reusable Operations', () async {
    final harness = _readyCapturingController();
    const definition = AutomationDefinition(
      id: 'professional_coding_change',
      kind: automationWorkflowKind,
      name: 'Professional Coding Change',
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

  test('previews reusable Operations without starting runs', () async {
    final harness = _readyCapturingController();
    const definition = AutomationDefinition(
      id: 'professional_coding_change',
      kind: automationWorkflowKind,
      name: 'Professional Coding Change',
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
      harness.controller.selectedAutomationOperationPreview?.missingSetup,
      <String>['change_request'],
    );
    expect(harness.controller.selectedAutomationRunId, isEmpty);
  });

  test('updates reusable Operations from typed setup fields', () async {
    final harness = _readyCapturingController();
    const setup = AutomationRunSetup(
      id: 'setup_1',
      definitionId: 'professional_coding_change',
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

  test('loads Operation run snapshots for selected runs', () async {
    final harness = _readyCapturingController();
    const run = AutomationRun(
      id: 'run_1',
      definitionId: 'professional_coding_change',
      kind: automationWorkflowKind,
      status: 'completed',
      state: 'done',
    );
    harness.controller.automationRuns = const <AutomationRun>[run];
    harness.client.runs = const <AutomationRun>[run];
    harness.client.snapshotsByRunId =
        const <String, AutomationOperationRunSnapshot>{
          'run_1': AutomationOperationRunSnapshot(
            runId: 'run_1',
            operationId: 'setup_1',
            resolvedInput: <String, dynamic>{'change_request': 'Fix it'},
          ),
        };

    await harness.controller.selectAutomationRun('run_1');

    expect(
      harness.controller.selectedAutomationOperationRunSnapshot?.operationId,
      'setup_1',
    );
    expect(
      harness
          .controller
          .selectedAutomationOperationRunSnapshot
          ?.resolvedInput['change_request'],
      'Fix it',
    );
  });

  testWidgets('shows Operation preview details in Test mode', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final setup = const AutomationRunSetup(
      id: 'setup_1',
      definitionId: 'professional_coding_change',
      name: 'Agent Awesome Repo',
      codebaseId: 'agent_awesome',
      input: <String, dynamic>{'repository_path': '/repo/agent'},
    );
    final controller = _readyController()
      ..automationRunSetups = <AutomationRunSetup>[setup]
      ..selectedAutomationRunSetupId = setup.id
      ..selectedAutomationOperationPreview = AutomationOperationPreview(
        operation: setup,
        status: 'needs_input',
        resolvedInput: const <String, dynamic>{
          'repository_path': '/repo/agent',
          'remote': 'origin',
        },
        missingSetup: const <String>['change_request'],
        policyDecision: const AutomationOperationPolicyDecision(
          status: 'allowed',
        ),
      );

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Operations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Operations').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Test'));
    await tester.pumpAndSettle();

    expect(find.text('TEST RUN'), findsOneWidget);
    expect(find.text('Status: Needs Setup'), findsOneWidget);
    expect(find.text('Needs Setup: Change Request'), findsOneWidget);
    expect(find.text('Repository Path: /repo/agent'), findsOneWidget);
    expect(find.text('Remote: origin'), findsOneWidget);
  });

  testWidgets('shows distinct saved Operation detail modes', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const setup = AutomationRunSetup(
      id: 'setup_1',
      definitionId: 'professional_coding_change',
      name: 'Agent Awesome Repo',
      codebaseId: 'agent_awesome',
      runtimeTargetId: 'local',
      input: <String, dynamic>{'repository_path': '/repo/agent'},
      policy: <String, dynamic>{
        'source_control': 'open_pr_only',
        'destructive_action': 'deny',
        'allowed_codebases': <String>['agent_awesome'],
        'allowed_targets': <String>['local'],
      },
      schedule: <String, dynamic>{'enabled': true, 'cron': '0 9 * * *'},
    );
    final controller = _readyController()
      ..automationDefinitions = const <AutomationDefinition>[
        AutomationDefinition(
          id: 'professional_coding_change',
          kind: automationWorkflowKind,
          name: 'Professional Coding Change',
          hash: 'sha256:professional',
        ),
      ]
      ..automationRunSetups = const <AutomationRunSetup>[setup]
      ..selectedAutomationRunSetupId = setup.id
      ..automationCodebases = const <AutomationCodebase>[
        AutomationCodebase(
          id: 'agent_awesome',
          name: 'Agent Awesome',
          repositoryPath: '/repo/agent',
        ),
      ]
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
          definitionId: 'professional_coding_change',
          kind: automationWorkflowKind,
          status: 'completed',
          state: 'done',
          output: <String, dynamic>{
            'pull_request_url': 'https://github.com/acme/agent/pull/7',
          },
        ),
      ]
      ..selectedAutomationRunId = 'run_1'
      ..selectedAutomationOperationRunSnapshot =
          const AutomationOperationRunSnapshot(
            runId: 'run_1',
            operationId: 'setup_1',
            operationVersion: 3,
            workflowId: 'professional_coding_change',
            resolvedInput: <String, dynamic>{'repository_path': '/repo/agent'},
            target: <String, dynamic>{'runtime_target_id': 'local'},
            policy: <String, dynamic>{'source_control': 'open_pr_only'},
            secretRefs: <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'github_token',
                'ref': 'secret://github',
              },
            ],
          );

    await tester.pumpWidget(
      MaterialApp(home: AgentAwesomeShell(controller: controller)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Operations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Operations').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Setup'));
    await tester.pumpAndSettle();
    expect(find.text('Run on: This computer'), findsOneWidget);

    await tester.tap(find.byTooltip('Inputs'));
    await tester.pumpAndSettle();
    expect(find.text('Repository Path: /repo/agent'), findsOneWidget);

    await tester.tap(find.byTooltip('Targets'));
    await tester.pumpAndSettle();
    expect(find.text('Allowed targets: This computer'), findsOneWidget);

    await tester.tap(find.byTooltip('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule: Daily at 09:00'), findsOneWidget);

    await tester.tap(find.byTooltip('Safety'));
    await tester.pumpAndSettle();
    expect(find.text('Source control: Open PR only'), findsOneWidget);

    await tester.tap(find.byTooltip('Runs').last);
    await tester.pumpAndSettle();
    expect(find.text('Runs: 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Artifacts'));
    await tester.pumpAndSettle();
    expect(find.text('Pull request'), findsOneWidget);
    expect(find.text('https://github.com/acme/agent/pull/7'), findsOneWidget);
  });

  testWidgets('shows process-state workflow lifecycle in Builder', (
    tester,
  ) async {
    final controller = _readyController()
      ..automationDrafts = const <AutomationDraft>[
        AutomationDraft(
          id: 'draft_lifecycle',
          kind: automationWorkflowKind,
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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
    expect(find.byTooltip('Inspect'), findsOneWidget);
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
          kind: automationWorkflowKind,
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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

  testWidgets('lays out workflow nodes in compact semantic ranks and lanes', (
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
          kind: automationWorkflowKind,
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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

  testWidgets('collapses and expands composite workflow phases in Builder', (
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
          kind: automationWorkflowKind,
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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

  testWidgets('drops workflow states into expanded composite phases', (
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
          kind: automationWorkflowKind,
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'intake');
    await tester.tap(find.byTooltip('Focus phase'));
    await tester.pumpAndSettle();

    expect(find.text('Workflow'), findsOneWidget);
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
    expect(find.byTooltip('Back to workflow'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to workflow'));
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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

  testWidgets('inspector auto-maps action inputs from workflow contracts', (
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
          kind: automationWorkflowKind,
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
                          'path': 'workflow_input.base_ref',
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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
    expect(find.text('Workflow input / base_ref'), findsOneWidget);
    expect(find.text(r'${workflow_input.base_ref}'), findsNothing);
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
            kind: automationWorkflowKind,
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
      await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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
          kind: automationWorkflowKind,
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
                          'path': 'workflow_input.base_ref',
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
    await tester.pumpAndSettle();

    await _tapStateMachineNode(tester, 'assert_input');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Checks'), findsOneWidget);
    expect(find.textContaining('workflow_input.base_ref'), findsOneWidget);
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
          kind: automationWorkflowKind,
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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

  testWidgets('edits process-state workflow nodes in Builder', (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _readyController()
      ..automationDrafts = const <AutomationDraft>[
        AutomationDraft(
          id: 'draft_lifecycle',
          kind: automationWorkflowKind,
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Workflows')));
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
          kind: automationWorkflowKind,
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
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Operations')));
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
    expect(find.byTooltip('Profiles'), findsOneWidget);
    expect(find.byTooltip('App'), findsOneWidget);
    expect(find.byTooltip('Models'), findsOneWidget);
    expect(find.byTooltip('Memory'), findsOneWidget);
    expect(find.text('APP SETTINGS'), findsNothing);
    expect(find.text('CHAT DEFAULTS'), findsOneWidget);
    expect(find.text('Default profile'), findsOneWidget);
    expect(find.text('Personal'), findsWidgets);
    expect(find.text('APPLICATION MODELS'), findsOneWidget);
    expect(find.text('Summarize titles with a model.'), findsOneWidget);
    expect(find.text('Summary model'), findsOneWidget);
    expect(find.text('openai / gpt-mini'), findsOneWidget);

    await tester.tap(find.byTooltip('Profiles'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('ASSIGNMENTS'), findsOneWidget);
    expect(find.text('Model'), findsWidgets);
    expect(find.text('Agent'), findsWidgets);
    expect(find.text('Tools'), findsWidgets);
    expect(find.text('Memory'), findsWidgets);

    expect(find.text('OS Tools'), findsNothing);
    expect(find.text('MCP Server'), findsNothing);

    await tester.tap(find.byTooltip('Models'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Summary Mini'), findsWidgets);
    expect(find.byTooltip('Add model config'), findsOneWidget);
    expect(find.byTooltip('Duplicate model config'), findsOneWidget);
    expect(find.byTooltip('Delete model config'), findsOneWidget);

    await tester.tap(find.byTooltip('Memory'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byTooltip('Add memory domain'), findsOneWidget);
    expect(find.byTooltip('Remove memory domain'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-MCP Servers')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('SERVERS'), findsWidgets);
    expect(find.text('Memory MCP'), findsOneWidget);
    expect(find.text('FILES'), findsWidgets);
    expect(find.byTooltip('Servers'), findsOneWidget);
    expect(find.byTooltip('Presets'), findsOneWidget);
    expect(find.byTooltip('Scenarios'), findsOneWidget);
    expect(find.byTooltip('Source'), findsOneWidget);
    expect(find.byTooltip('Add MCP config'), findsOneWidget);
    expect(find.byTooltip('Duplicate MCP config'), findsOneWidget);
    expect(find.byTooltip('Delete MCP config'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-Tools')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('COMMANDS'), findsWidgets);
    expect(find.text('Personal Tools'), findsOneWidget);
    expect(find.text('FILES'), findsWidgets);
    expect(find.byTooltip('Commands'), findsOneWidget);
    expect(find.byTooltip('Presets'), findsOneWidget);
    expect(find.byTooltip('Scenarios'), findsOneWidget);
    expect(find.byTooltip('Source'), findsOneWidget);
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
    expect(find.byTooltip('Delete selected chat'), findsNothing);
    expect(find.byTooltip('New chat with profile'), findsNothing);
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
    expect(find.byTooltip('New chat'), findsOneWidget);
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
    expect(find.text('RECORDS'), findsOneWidget);
    expect(find.text('OVERVIEW'), findsOneWidget);
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
    expect(find.text('INSPECTOR'), findsOneWidget);
    expect(find.text('Draft task brief'), findsWidgets);
    expect(find.byTooltip('Delete backlog item'), findsOneWidget);
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

/// Returns a workflow definition with schema-backed run inputs for UI tests.
AutomationDefinition _professionalCodingDefinitionForRunTest() {
  return const AutomationDefinition(
    id: 'professional_coding_change',
    kind: automationWorkflowKind,
    name: 'Professional Coding Change',
    hash: 'sha256:professional',
    body: <String, dynamic>{
      'authoring': <String, Object>{
        'input_defaults': <String, Object>{
          'repository_path': r'${app.workspace_root}',
        },
        'run_setup': <String, Object>{
          'setup_fields': <Object>[
            'repository_path',
            'go_module_path',
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
                'input': r'${workflow_input}',
                'defaults': <String, Object>{
                  'remote': 'origin',
                  'branch_summary': r'${workflow_input.change_request}',
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

/// _CapturingAutomationsClient stores workflow drafts in memory for UI tests.
class _CapturingAutomationsClient extends AutomationsClient {
  /// Creates a fake workflow client.
  _CapturingAutomationsClient() : super(baseUrl: 'http://127.0.0.1:1');

  /// Editable draft list returned by [listDrafts].
  List<AutomationDraft> drafts = const <AutomationDraft>[];

  /// Published definition list returned by [listDefinitions].
  List<AutomationDefinition> definitions = const <AutomationDefinition>[];

  /// Run list returned by [listRuns].
  List<AutomationRun> runs = const <AutomationRun>[];

  /// Saved Operation list returned by [listRunSetups].
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

  /// Operation run snapshots keyed by run id.
  Map<String, AutomationOperationRunSnapshot> snapshotsByRunId =
      const <String, AutomationOperationRunSnapshot>{};

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

  /// Replaces the in-memory Operation list.
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
    bool? usableInWorkflows,
  }) async {
    return capabilities.where((capability) {
      if (kind.trim().isNotEmpty && capability.kind != kind.trim()) {
        return false;
      }
      if (usableInChat != null && capability.usableInChat != usableInChat) {
        return false;
      }
      if (usableInWorkflows != null &&
          capability.usableInWorkflows != usableInWorkflows) {
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
              'apiVersion': automationWorkflowApiVersion,
              'kind': kind,
              'id': 'workflow_${drafts.length + 1}',
              'nodes': const <Object>[],
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
      kind: automationWorkflowKind,
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
  Future<AutomationOperationPreview> previewRunSetup(
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
    return AutomationOperationPreview(
      operation: setup,
      status: missing.isEmpty ? 'ready' : 'needs_input',
      resolvedInput: resolved,
      missingSetup: missing,
      policyDecision: const AutomationOperationPolicyDecision(
        status: 'allowed',
      ),
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
      kind: automationWorkflowKind,
      status: 'running',
      state: 'running',
    );
    runs = <AutomationRun>[run, ...runs];
    return run;
  }

  @override
  Future<AutomationOperationRunSnapshot> operationRunSnapshot(
    String runId,
  ) async {
    final snapshot = snapshotsByRunId[runId];
    if (snapshot == null) {
      throw StateError('snapshot not found');
    }
    return snapshot;
  }
}

/// Creates a workflow graph draft for Builder shell tests.
AutomationDraft _workflowGraphDraft() {
  return const AutomationDraft(
    id: 'draft_workflow_graph',
    kind: automationWorkflowKind,
    name: 'Workflow Graph',
    status: 'draft',
    body: <String, dynamic>{
      'apiVersion': automationWorkflowApiVersion,
      'kind': automationWorkflowKind,
      'id': 'workflow_graph',
      'nodes': <Object>[],
    },
  );
}

/// Creates a nested state-machine draft for hierarchy editing tests.
AutomationDraft _hierarchyEditDraft() {
  return const AutomationDraft(
    id: 'draft_hierarchy_edit',
    kind: automationWorkflowKind,
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
    kind: automationWorkflowKind,
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
    kind: automationWorkflowKind,
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

AppConfig _testConfig({String runtimeProfilePath = ''}) {
  return AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:1/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:2/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:1/mcp',
    agentAppName: 'test',
    agentUserId: 'user',
    workspaceRoot: '/tmp/agentawesome-test',
    autoStartLocalServices: false,
    runtimeProfilePath: runtimeProfilePath,
  );
}
