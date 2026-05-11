/// Tests structured Backlog screen-command planning and controller behavior.
library;

import 'dart:io';

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/runtime_profile.dart';
import 'package:agentawesome_ui/clients/mcp_client.dart';
import 'package:agentawesome_ui/clients/screen_command_client.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/domain/screen_command.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs screen-command unit and controller tests.
void main() {
  test('parses strict planner JSON into typed screen changes', () {
    final run = parseScreenCommandRun(
      '{"intent":"change","confidence":0.9,"changes":[{"operation":"update_task","target":{"task_id":"task-1"},"summary":"Make high priority","confidence":0.95,"fields":{"priority":"high"}}]}',
      command: 'make it high priority',
    );

    expect(run.intent, ScreenCommandIntent.change);
    expect(run.command, 'make it high priority');
    expect(run.changes.single.operation, ScreenChangeOperation.updateTask);
    expect(run.changes.single.fields['priority'], 'high');
  });

  test('rejects unknown planner operations', () {
    expect(
      () => parseScreenCommandRun(
        '{"intent":"change","changes":[{"operation":"teleport_task"}]}',
      ),
      throwsA(isA<ScreenCommandFormatException>()),
    );
  });

  test('auto-applies one high-confidence reversible backlog edit', () async {
    final fakeTasks = _FakeTasksClient(
      endpoint: _memoryEndpoint,
      tasks: <WorkspaceTask>[
        _task(id: 'task-1', title: 'Draft schema', priority: 'normal'),
      ],
    );
    final controller = _controller(
      planner: _FakePlanner(
        run: _run(
          changes: <ScreenChange>[
            _change(
              operation: ScreenChangeOperation.updateTask,
              taskId: 'task-1',
              confidence: 0.96,
              fields: <String, dynamic>{'priority': 'high'},
            ),
          ],
        ),
      ),
      tasksClient: fakeTasks,
    );
    controller.workspace = ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live',
      tasks: fakeTasks.tasks,
      sources: const <SourceItem>[],
      memoryRecords: const <MemoryRecord>[],
    );
    controller.primaryMemoryToolNames = const <String>{
      'update_task',
      'task_graph_projection',
    };

    await controller.runBacklogScreenCommand(
      text: 'make the schema task high priority',
      scopeLabel: 'Backlog / Queue',
    );

    final change = controller.activeScreenCommandRun!.changes.single;
    expect(change.status, ScreenChangeStatus.applied);
    expect(change.beforeValues['priority'], 'normal');
    expect(controller.workspace.tasks.single.priority, 'high');
  });

  test('stages destructive backlog changes for review', () async {
    final fakeTasks = _FakeTasksClient(
      endpoint: _memoryEndpoint,
      tasks: <WorkspaceTask>[_task(id: 'task-1', title: 'Draft schema')],
    );
    final controller = _controller(
      planner: _FakePlanner(
        run: _run(
          changes: <ScreenChange>[
            _change(
              operation: ScreenChangeOperation.deleteTask,
              taskId: 'task-1',
              confidence: 0.99,
            ),
          ],
        ),
      ),
      tasksClient: fakeTasks,
    );
    controller.workspace = ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live',
      tasks: fakeTasks.tasks,
      sources: const <SourceItem>[],
      memoryRecords: const <MemoryRecord>[],
    );
    controller.primaryMemoryToolNames = const <String>{
      'delete_task',
      'task_graph_projection',
    };

    await controller.runBacklogScreenCommand(
      text: 'delete the schema task',
      scopeLabel: 'Backlog / Queue',
    );

    final change = controller.activeScreenCommandRun!.changes.single;
    expect(change.status, ScreenChangeStatus.proposed);
    expect(change.safety, ScreenChangeSafety.needsReview);
    expect(controller.workspace.tasks.single.id, 'task-1');
    expect(controller.backlogReviewPanelOpen, isTrue);
  });

  test('undo restores an applied task edit from before values', () async {
    final fakeTasks = _FakeTasksClient(
      endpoint: _memoryEndpoint,
      tasks: <WorkspaceTask>[
        _task(id: 'task-1', title: 'Draft schema', priority: 'normal'),
      ],
    );
    final controller = _controller(
      planner: _FakePlanner(
        run: _run(
          changes: <ScreenChange>[
            _change(
              operation: ScreenChangeOperation.updateTask,
              taskId: 'task-1',
              confidence: 0.96,
              fields: <String, dynamic>{'priority': 'high'},
            ),
          ],
        ),
      ),
      tasksClient: fakeTasks,
    );
    controller.workspace = ProjectWorkspace(
      title: 'Workspace',
      subtitle: 'Live',
      tasks: fakeTasks.tasks,
      sources: const <SourceItem>[],
      memoryRecords: const <MemoryRecord>[],
    );
    controller.primaryMemoryToolNames = const <String>{
      'update_task',
      'task_graph_projection',
    };

    await controller.runBacklogScreenCommand(
      text: 'make the schema task high priority',
      scopeLabel: 'Backlog / Queue',
    );
    await controller.undoScreenChangeFromUi(
      controller.activeScreenCommandRun!.changes.single.id,
    );

    final change = controller.activeScreenCommandRun!.changes.single;
    expect(change.status, ScreenChangeStatus.undone);
    expect(controller.workspace.tasks.single.priority, 'normal');
  });
}

const String _memoryEndpoint = 'http://127.0.0.1:1/mcp';

/// Builds a fake planner run with supplied changes.
ScreenCommandRun _run({required List<ScreenChange> changes}) {
  return ScreenCommandRun(
    id: 'run-1',
    command: 'screen command',
    intent: ScreenCommandIntent.change,
    confidence: 0.9,
    changes: changes,
    createdAt: DateTime(2026, 5, 5),
  );
}

/// Builds a fake screen change for controller tests.
ScreenChange _change({
  required ScreenChangeOperation operation,
  String taskId = '',
  double confidence = 0.9,
  Map<String, dynamic> fields = const <String, dynamic>{},
}) {
  return ScreenChange(
    id: 'change-${operation.name}',
    operation: operation,
    target: ScreenChangeTarget(taskId: taskId),
    summary: 'Proposed ${operation.name}',
    confidence: confidence,
    fields: fields,
  );
}

/// Builds a controller with fake planner and task client dependencies.
AgentAwesomeAppController _controller({
  required ScreenCommandPlanner planner,
  required TasksClient tasksClient,
}) {
  final tempRoot = Directory.systemTemp.createTempSync(
    'agentawesome-screen-command-controller-test-',
  );
  addTearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });
  final modelConfig = File('${tempRoot.path}/model.yaml');
  modelConfig.writeAsStringSync(_modelConfig);
  final controller = AgentAwesomeAppController(
    config: _testConfig(),
    screenCommandPlanner: planner,
    tasksClient: tasksClient,
  );
  controller.runtimeProfile = _profile(modelConfig.path);
  controller.runtimeProfilePath = '/tmp/personal.json';
  return controller;
}

/// Builds a compact fake workspace task.
WorkspaceTask _task({
  required String id,
  required String title,
  String status = 'open',
  String priority = 'normal',
  bool done = false,
}) {
  return WorkspaceTask(
    id: id,
    title: title,
    detail: status,
    done: done,
    status: status,
    priority: priority,
  );
}

/// Returns a fake task copy with selected editable fields changed.
WorkspaceTask _copyTask(
  WorkspaceTask task, {
  String? title,
  String? description,
  String? status,
  String? priority,
  DateTime? dueAt,
  bool clearDueAt = false,
  DateTime? scheduledAt,
  bool clearScheduledAt = false,
  DateTime? followUpAt,
  bool clearFollowUpAt = false,
  List<String>? topics,
}) {
  final nextStatus = status ?? task.status;
  return WorkspaceTask(
    id: task.id,
    title: title ?? task.title,
    detail: nextStatus,
    done: nextStatus == 'done',
    description: description ?? task.description,
    status: nextStatus,
    priority: priority ?? task.priority,
    dueAt: clearDueAt ? null : dueAt ?? task.dueAt,
    scheduledAt: clearScheduledAt ? null : scheduledAt ?? task.scheduledAt,
    followUpAt: clearFollowUpAt ? null : followUpAt ?? task.followUpAt,
    topics: topics ?? task.topics,
    estimateMinutes: task.estimateMinutes,
    energyRequired: task.energyRequired,
    effort: task.effort,
    value: task.value,
    urgency: task.urgency,
    risk: task.risk,
    context: task.context,
    domain: task.domain,
    project: task.project,
    location: task.location,
    owner: task.owner,
    source: task.source,
    confidence: task.confidence,
  );
}

/// Builds a runtime profile with one fake memory server.
RuntimeProfile _profile(String modelConfigPath) {
  return RuntimeProfile(
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
      modelConfigPath: modelConfigPath,
      agentConfigPath: '/tmp/agent.yaml',
      toolConfigPath: '/tmp/tool.yaml',
      port: 1,
      autoStart: false,
    ),
    memoryServerConfigPath: '/tmp/memory.json',
    mcpServers: const <McpServerRuntime>[
      McpServerRuntime(
        id: 'memory',
        label: 'Personal Memory',
        kind: 'memory',
        endpoint: _memoryEndpoint,
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

/// Builds a minimal app config for controller tests.
AppConfig _testConfig() {
  return const AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:1/api',
    agentGatewayBaseUrl: 'http://127.0.0.1:2/api',
    agentContextApiBaseUrl: 'http://127.0.0.1:8081/api/context',
    memoryMcpUrl: _memoryEndpoint,
    agentAppName: 'test',
    agentUserId: 'user',
    workspaceRoot: '/tmp/agentawesome-test',
    autoStartLocalServices: false,
    runtimeProfilePath: '',
  );
}

class _FakePlanner implements ScreenCommandPlanner {
  /// Creates a fake planner that returns one configured run.
  _FakePlanner({required this.run});

  final ScreenCommandRun run;

  /// Returns the configured run without calling a model.
  @override
  Future<ScreenCommandRun> planBacklogCommand({
    required String modelConfigContent,
    String modelRef = '',
    required String command,
    required BacklogScreenSnapshot snapshot,
  }) async {
    return run.copyWith(command: command);
  }
}

const String _modelConfig = '''
default: openai:gpt-mini
providers:
  openai:
    adapter: openai
    url: https://api.openai.com/v1/chat/completions
    default: gpt-mini
    models:
      - id: gpt-mini
        model: gpt-5.4-mini
''';

class _FakeTasksClient extends TasksClient {
  /// Creates a fake task client for one endpoint.
  _FakeTasksClient({required String endpoint, required this.tasks})
    : super(rpc: McpJsonRpcClient(endpoint: endpoint));

  List<WorkspaceTask> tasks;

  /// Returns test tool capabilities.
  @override
  Future<List<String>> listToolNames() async {
    return const <String>[
      'list_tasks',
      'task_graph_projection',
      'update_task',
      'delete_task',
    ];
  }

  /// Returns the current fake task list.
  @override
  Future<List<WorkspaceTask>> listTasks({
    TaskFilterState filters = const TaskFilterState(),
    bool includeDone = true,
    bool includeLinks = true,
    int limit = 100,
  }) async {
    return tasks;
  }

  /// Updates one fake task.
  @override
  Future<WorkspaceTask> updateTask({
    required String taskId,
    String? title,
    String? description,
    String? status,
    String? priority,
    DateTime? dueAt,
    bool clearDueAt = false,
    DateTime? scheduledAt,
    bool clearScheduledAt = false,
    DateTime? followUpAt,
    bool clearFollowUpAt = false,
    List<String>? topics,
    bool replaceTopics = false,
    int? estimateMinutes,
    String? energyRequired,
    double? effort,
    double? value,
    double? urgency,
    double? risk,
    String? context,
    String? domain,
    String? project,
    String? location,
    String? owner,
    int? spendCents,
    int? earnCents,
    int? saveCents,
    String? currency,
    String? source,
    TaskWorkBreakdown? workBreakdown,
    double? confidence,
    String actor = 'agent_awesome_ui',
  }) async {
    final index = tasks.indexWhere((task) => task.id == taskId);
    if (index == -1) {
      throw StateError('missing task $taskId');
    }
    final replacement = _copyTask(
      tasks[index],
      title: title,
      description: description,
      status: status,
      priority: priority,
      dueAt: dueAt,
      clearDueAt: clearDueAt,
      scheduledAt: scheduledAt,
      clearScheduledAt: clearScheduledAt,
      followUpAt: followUpAt,
      clearFollowUpAt: clearFollowUpAt,
      topics: replaceTopics ? topics : null,
    );
    tasks = <WorkspaceTask>[
      ...tasks.take(index),
      replacement,
      ...tasks.skip(index + 1),
    ];
    return replacement;
  }

  /// Marks one fake task complete.
  @override
  Future<WorkspaceTask> completeTask(
    String taskId, {
    String actor = 'agent_awesome_ui',
  }) {
    return updateTask(taskId: taskId, status: 'done');
  }

  /// Deletes one fake task.
  @override
  Future<void> deleteTask(
    String taskId, {
    String actor = 'agent_awesome_ui',
  }) async {
    tasks = tasks.where((task) => task.id != taskId).toList();
  }

  /// Returns no fake WBS metadata.
  @override
  Future<Map<String, TaskWorkBreakdown>> getTaskWorkBreakdowns() async {
    return const <String, TaskWorkBreakdown>{};
  }

  /// Returns an empty fake projection.
  @override
  Future<TaskProjectionGraph> getTaskProjectionGraph() async {
    return const TaskProjectionGraph();
  }

  /// Returns no fake relations.
  @override
  Future<List<TaskRelationRecord>> listTaskRelations() async {
    return const <TaskRelationRecord>[];
  }

  /// Returns no fake relation suggestions.
  @override
  Future<List<TaskRelationSuggestion>> suggestTaskRelationships() async {
    return const <TaskRelationSuggestion>[];
  }

  /// Returns no fake metadata suggestions.
  @override
  Future<List<TaskMetadataSuggestion>> suggestTaskMetadata() async {
    return const <TaskMetadataSuggestion>[];
  }

  /// Returns no fake commitment suggestions.
  @override
  Future<List<TaskCommitmentSuggestion>> suggestCommitments() async {
    return const <TaskCommitmentSuggestion>[];
  }

  /// Returns no fake commitments.
  @override
  Future<List<TaskCommitment>> listCommitments() async {
    return const <TaskCommitment>[];
  }
}
