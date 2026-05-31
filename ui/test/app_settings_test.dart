/// Tests app-owned settings serialization.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/app_settings.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs app settings tests.
void main() {
  test('environment config does not expose a topology override', () {
    final config = AppConfig.fromEnvironment();

    expect(config.runtimeProfilePath, '');
  });

  test('serializes exact summary model selection', () {
    const settings = AgentAwesomeAppSettings(
      defaultAgentConfigPath: '/tmp/agent.yaml',
      selectedMemoryDomainId: 'project',
      summaryModelConfigPath: '/tmp/models.yaml',
      summaryModelRef: 'openai:gpt-nano',
      activeWorkspaceView: workspaceViewWork,
      interfaceMode: interfaceModeBasic,
      chatTitleSummariesEnabled: true,
      watchWorkspaceChangesEnabled: false,
      gettingStartedCompleted: true,
    );

    final encoded = settings.toJson();
    final decoded = AgentAwesomeAppSettings.fromJson(encoded);

    expect(encoded['summary_model_ref'], 'openai:gpt-nano');
    expect(encoded['active_workspace_view'], workspaceViewWork);
    expect(encoded['interface_mode'], interfaceModeBasic);
    expect(encoded['watch_workspace_changes_enabled'], isFalse);
    expect(encoded['default_agent_config'], '/tmp/agent.yaml');
    expect(encoded['selected_memory_domain'], 'project');
    expect(decoded.defaultAgentConfigPath, '/tmp/agent.yaml');
    expect(decoded.selectedMemoryDomainId, 'project');
    expect(decoded.summaryModelConfigPath, '/tmp/models.yaml');
    expect(decoded.summaryModelRef, 'openai:gpt-nano');
    expect(decoded.activeWorkspaceView, workspaceViewWork);
    expect(decoded.interfaceMode, interfaceModeBasic);
    expect(decoded.watchWorkspaceChangesEnabled, isFalse);
    expect(encoded['getting_started_completed'], isTrue);
    expect(decoded.gettingStartedCompleted, isTrue);
    expect(
      decoded.memoryFirewalls.map((firewall) => firewall.id),
      contains('user'),
    );
    expect(decoded.memoryFirewalls.first.sharedWith, isNotEmpty);
  });

  test('defaults first launch guide and memory firewalls', () {
    final decoded = AgentAwesomeAppSettings.fromJson(const <String, dynamic>{});

    expect(decoded.gettingStartedCompleted, isFalse);
    expect(decoded.watchWorkspaceChangesEnabled, isTrue);
    expect(decoded.effectiveMemoryFirewalls.first.id, 'session');
    expect(
      decoded.effectiveMemoryFirewalls.map((firewall) => firewall.id),
      containsAll(<String>['user', 'project', 'global']),
    );
  });

  test('serializes saved task filter presets', () {
    const settings = AgentAwesomeAppSettings(
      savedTaskFilters: <SavedTaskFilter>[
        SavedTaskFilter(
          id: 'task-filter-high',
          label: 'High',
          filters: TaskFilterState(
            statuses: <String>['open'],
            priorities: <String>['high'],
            overdueOnly: true,
          ),
        ),
      ],
    );

    final encoded = settings.toJson();
    final decoded = AgentAwesomeAppSettings.fromJson(encoded);

    expect(encoded['saved_task_filters'], isA<List<Map<String, dynamic>>>());
    expect(decoded.savedTaskFilters.single.id, 'task-filter-high');
    expect(decoded.savedTaskFilters.single.label, 'High');
    expect(decoded.savedTaskFilters.single.filters.statuses, <String>['open']);
    expect(decoded.savedTaskFilters.single.filters.priorities, <String>[
      'high',
    ]);
    expect(decoded.savedTaskFilters.single.filters.overdueOnly, isTrue);
  });

  test('controller saves applies and deletes task filter presets', () async {
    final store = _MemoryAppSettingsStore();
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      appSettingsStore: store,
    );
    controller.appSettings = store.saved;
    const filters = TaskFilterState(
      statuses: <String>['blocked'],
      priorities: <String>['high'],
      topics: <String>['launch'],
      overdueOnly: true,
    );

    await controller.applyTaskFilters(filters);
    await controller.saveCurrentTaskFilterPreset();

    final preset = store.saved.savedTaskFilters.single;
    expect(preset.label, 'Blocked / High / Launch / Overdue');
    expect(controller.activeSavedTaskFilter()?.id, preset.id);

    await controller.applyTaskFilters(const TaskFilterState());
    await controller.applySavedTaskFilterPreset(preset.id);

    expect(controller.taskFilters.sameAs(filters), isTrue);

    await controller.deleteSavedTaskFilterPreset(preset.id);

    expect(store.saved.savedTaskFilters, isEmpty);
  });

  test('controller filters tasks by active workspace view', () async {
    final controller = AgentAwesomeAppController(
      config: _testConfig(),
      appSettingsStore: _MemoryAppSettingsStore(),
    );
    controller.workspace = const ProjectWorkspace(
      title: 'Workspace',
      subtitle: '',
      tasks: <WorkspaceTask>[
        WorkspaceTask(
          id: 'work-1',
          title: 'Work item',
          detail: '',
          done: false,
          project: 'Work',
        ),
        WorkspaceTask(
          id: 'life-1',
          title: 'Life item',
          detail: '',
          done: false,
          topics: <String>['life'],
        ),
        WorkspaceTask(
          id: 'loose-1',
          title: 'Loose item',
          detail: '',
          done: false,
        ),
      ],
      sources: <SourceItem>[],
      memoryRecords: <MemoryRecord>[],
    );

    await controller.selectWorkspaceView(workspaceViewWork);

    expect(controller.filteredTasks.map((task) => task.id), <String>['work-1']);

    await controller.selectWorkspaceView(workspaceViewLife);

    expect(controller.filteredTasks.map((task) => task.id), <String>['life-1']);

    await controller.selectWorkspaceView(workspaceViewProject);

    expect(controller.filteredTasks.map((task) => task.id), <String>['work-1']);
  });

  test('normalizes custom memory firewalls', () {
    final decoded = AgentAwesomeAppSettings.fromJson(<String, dynamic>{
      'memory_firewalls': <Map<String, dynamic>>[
        <String, dynamic>{'id': ' Acme Client ', 'label': 'Acme'},
        <String, dynamic>{
          'id': 'contoso-prod',
          'label': '',
          'shares': <Map<String, dynamic>>[
            <String, dynamic>{
              'kind': 'principal',
              'id': ' Pat ',
              'label': 'Pat',
            },
            <String, dynamic>{'kind': 'principal', 'id': 'pat', 'label': 'pat'},
            <String, dynamic>{
              'kind': 'principal',
              'id': 'Legal',
              'label': 'Legal',
            },
          ],
          'writers': <Map<String, dynamic>>[
            <String, dynamic>{'kind': 'project', 'id': 'ops', 'label': 'Ops'},
          ],
        },
        <String, dynamic>{'id': 'acme-client', 'label': 'Duplicate'},
      ],
    });

    expect(
      decoded.effectiveMemoryFirewalls.map((firewall) => firewall.id).toList(),
      <String>['acme-client', 'contoso-prod'],
    );
    expect(decoded.effectiveMemoryFirewalls.first.label, 'Acme');
    expect(decoded.effectiveMemoryFirewalls.last.label, 'Contoso Prod');
    expect(decoded.effectiveMemoryFirewalls.last.sharedWith, <String>[
      'Pat',
      'Legal',
    ]);
    expect(
      decoded.effectiveMemoryFirewalls.last.shares
          .map((share) => '${share.kind}:${share.id}')
          .toList(),
      <String>['principal:pat', 'principal:legal'],
    );
    expect(
      decoded.effectiveMemoryFirewalls.last.writers
          .map((share) => '${share.kind}:${share.id}')
          .toList(),
      <String>['project:ops'],
    );
  });

  test('encodes memory firewall policy for the local daemon', () {
    final policy = memoryFirewallPolicyJson(
      const <MemoryFirewall>[
        MemoryFirewall(
          id: 'acme-client',
          label: 'Acme Client',
          shares: <MemoryFirewallShare>[
            MemoryFirewallShare(
              kind: 'team',
              id: 'acme-legal',
              label: 'Acme Legal',
            ),
            MemoryFirewallShare(
              kind: 'public',
              id: 'everyone',
              label: 'Public',
            ),
          ],
          writers: <MemoryFirewallShare>[
            MemoryFirewallShare(kind: 'person', id: 'pat', label: 'Pat'),
          ],
        ),
      ],
      extraLocalActors: <String>['agent:test'],
    );

    expect(policy['default_allow'], isFalse);
    final rules = policy['firewalls'] as List<Map<String, dynamic>>;
    expect(rules.single['firewall'], 'acme-client');
    expect(
      rules.single['readers'],
      containsAll(<String>[
        'agent',
        'agent:test',
        'agent_awesome_ui',
        'acme-legal',
        'team:acme-legal',
        '*',
      ]),
    );
    expect(
      rules.single['writers'],
      containsAll(<String>[
        'agent',
        'agent:test',
        'agent_awesome_ui',
        'pat',
        'person:pat',
      ]),
    );
  });

  test('chat title model falls back to active agent model config', () {
    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.appSettings = const AgentAwesomeAppSettings(
      chatTitleSummariesEnabled: true,
    );
    controller.runtimeProfile = _testProfile('/tmp/general-model.yaml');

    expect(controller.summaryModelConfigPath, '/tmp/general-model.yaml');
    expect(controller.summaryModelRef, '');
  });

  test('controller exposes memory firewall audience labels', () {
    final controller = AgentAwesomeAppController(config: _testConfig());
    controller.appSettings = const AgentAwesomeAppSettings(
      memoryFirewalls: <MemoryFirewall>[
        MemoryFirewall(
          id: 'acme-client',
          label: 'Acme Client',
          shares: <MemoryFirewallShare>[
            MemoryFirewallShare(
              kind: 'team',
              id: 'acme-legal',
              label: 'Acme Legal',
            ),
            MemoryFirewallShare(kind: 'person', id: 'pat', label: 'Pat'),
          ],
          writers: <MemoryFirewallShare>[
            MemoryFirewallShare(kind: 'person', id: 'lee', label: 'Lee'),
          ],
        ),
      ],
    );

    expect(controller.memoryFirewallLabel('acme-client'), 'Acme Client');
    expect(
      controller.memoryFirewallAudienceLabel('acme-client'),
      'Acme Legal, Pat',
    );
    expect(
      controller.memoryFirewallPickerLabel('acme-client'),
      'Acme Client / Acme Legal, Pat',
    );
  });
}

class _MemoryAppSettingsStore extends AgentAwesomeAppSettingsStore {
  /// Creates an in-memory app settings store for controller tests.
  _MemoryAppSettingsStore();

  AgentAwesomeAppSettings saved = const AgentAwesomeAppSettings();

  /// Returns the last saved settings.
  @override
  Future<AgentAwesomeAppSettings> load() async {
    return saved;
  }

  /// Stores settings without touching the user config directory.
  @override
  Future<void> save(
    AgentAwesomeAppSettings settings, {
    Iterable<String> extraPolicyActors = const <String>[],
  }) async {
    saved = settings;
  }
}

/// Builds a minimal app config for settings-derived controller tests.
AppConfig _testConfig() {
  return const AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:8080/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:8070/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
    agentAppName: 'Agent Awesome',
    agentUserId: 'doug',
    workspaceRoot: '/tmp/agentawesome-ui-test',
    autoStartLocalServices: false,
    runtimeProfilePath: '',
  );
}

/// Builds a profile with the general chat model config selected.
RuntimeProfile _testProfile(String modelConfigPath) {
  return RuntimeProfile(
    id: 'personal',
    label: 'Personal',
    harness: HarnessRuntime(
      id: 'harness',
      label: 'Harness',
      apiBaseUrl: 'http://127.0.0.1:1/api',
      contextApiBaseUrl: 'http://127.0.0.1:1/api/context',
      appName: 'test',
      userId: 'user',
      workingDirectory: '/tmp/harness',
      executablePath: '/tmp/bin/agent-awesome',
      modelConfigPath: modelConfigPath,
      agentConfigPath: '/tmp/agent.yaml',
      toolConfigPath: '/tmp/tool.yaml',
      port: 1,
      autoStart: false,
    ),
    gateway: const GatewayRuntime(
      id: 'gateway',
      label: 'Gateway',
      apiBaseUrl: 'http://127.0.0.1:2/api',
      healthUrl: 'http://127.0.0.1:2/healthz',
      workingDirectory: '/tmp/gateway',
      executablePath: '/tmp/bin/agent-gateway',
      harnessBaseUrl: 'http://127.0.0.1:1/api',
      contextBaseUrl: 'http://127.0.0.1:1/api/context',
      memoryMcpUrl: 'http://127.0.0.1:1/mcp',
      appName: 'test',
      userId: 'user',
      port: 2,
      autoStart: false,
      enabled: true,
    ),
    memoryDomains: const <McpServerRuntime>[],
    agentMemory: const AgentMemoryRuntime(
      actor: 'agent:test',
      readDomains: <String>['memory'],
      writeDomains: <String>['memory'],
      defaultWriteDomain: 'memory',
      allowedSensitivities: <String>['public', 'internal', 'private'],
    ),
  );
}
