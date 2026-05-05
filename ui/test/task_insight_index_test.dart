/// Verifies the task insight read model and named query behavior.
library;

import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/domain/task_insight_index.dart';
import 'package:agentawesome_ui/domain/task_insight_query.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises insight candidates, graph traversal, and unblock plans.
void main() {
  final now = DateTime.parse('2026-05-03T12:00:00Z');

  test('includes must-do safe agent handoff candidates', () {
    final index = TaskInsightIndex.build(
      workspaceTasks: <WorkspaceTask>[
        _workspaceTask(
          id: 'invoice',
          title: 'Review vendor invoices',
          description: 'Compare duplicate source numbers.',
          estimateMinutes: 25,
          context: 'Admin',
          domain: 'Work',
        ),
      ],
      graph: TaskProjectionGraph(
        tasks: <TaskProjectionTask>[
          _projectionTask(
            id: 'invoice',
            title: 'Review vendor invoices',
            scores: const TaskProjectionScores(
              reward: 0.38,
              pressure: 0.70,
              risk: 0.30,
              humanEffort: 0.20,
              agentFit: 0.72,
              obligation: 0.75,
              agentSafety: 0.68,
              handoffReadiness: 0.62,
              metadataCompleteness: 0.82,
            ),
          ),
        ],
      ),
      now: now,
    );

    final candidates = index.tasksForInsight(TaskInsightIds.agentHandoff);

    expect(
      candidates.map((candidate) => candidate.taskId),
      contains('invoice'),
    );
    expect(candidates.single.severity, 'info');
  });

  test('keeps agent-capable unsafe work as needs review', () {
    final index = TaskInsightIndex.build(
      workspaceTasks: <WorkspaceTask>[
        _workspaceTask(
          id: 'payment',
          title: 'Send vendor payment',
          description: 'Prepare the payment note.',
          estimateMinutes: 20,
          context: 'Admin',
          domain: 'Finance',
        ),
      ],
      graph: TaskProjectionGraph(
        tasks: <TaskProjectionTask>[
          _projectionTask(
            id: 'payment',
            title: 'Send vendor payment',
            scores: const TaskProjectionScores(
              reward: 0.35,
              pressure: 0.70,
              risk: 0.45,
              humanEffort: 0.20,
              agentFit: 0.80,
              obligation: 0.78,
              agentSafety: 0.42,
              handoffReadiness: 0.40,
              metadataCompleteness: 0.76,
            ),
          ),
        ],
      ),
      now: now,
    );

    final candidate = index.tasksForInsight(TaskInsightIds.agentHandoff).single;

    expect(candidate.taskId, 'payment');
    expect(candidate.severity, 'warning');
    expect(candidate.missingRules, contains('agent_safety'));
  });

  test('includes high-value work due next week', () {
    final index = TaskInsightIndex.build(
      workspaceTasks: <WorkspaceTask>[
        _workspaceTask(
          id: 'renewal',
          title: 'Prepare client renewal packet',
          dueAt: DateTime.parse('2026-05-10T12:00:00Z'),
          estimateMinutes: 90,
          context: 'Focus',
          domain: 'Work',
        ),
      ],
      graph: TaskProjectionGraph(
        tasks: <TaskProjectionTask>[
          _projectionTask(
            id: 'renewal',
            title: 'Prepare client renewal packet',
            dueAt: DateTime.parse('2026-05-10T12:00:00Z'),
            valueType: 'client',
            scores: const TaskProjectionScores(
              reward: 0.72,
              pressure: 0.50,
              consequenceSeverity: 0.76,
              commitmentHardness: 0.74,
              metadataCompleteness: 0.80,
            ),
          ),
        ],
      ),
      now: now,
    );

    expect(
      index
          .tasksForInsight(TaskInsightIds.nextWeekHighValue)
          .map((candidate) => candidate.taskId),
      contains('renewal'),
    );
  });

  test('finds quick unblocks and selected-task unblock plans', () {
    final index = TaskInsightIndex.build(
      workspaceTasks: <WorkspaceTask>[
        _workspaceTask(
          id: 'collect',
          title: 'Collect forecast inputs',
          estimateMinutes: 20,
        ),
        _workspaceTask(
          id: 'review',
          title: 'Review May budget',
          status: 'blocked',
          estimateMinutes: 60,
        ),
      ],
      graph: TaskProjectionGraph(
        tasks: <TaskProjectionTask>[
          _projectionTask(
            id: 'collect',
            title: 'Collect forecast inputs',
            scores: const TaskProjectionScores(
              reward: 0.42,
              pressure: 0.45,
              humanEffort: 0.12,
              metadataCompleteness: 0.78,
            ),
          ),
          _projectionTask(
            id: 'review',
            title: 'Review May budget',
            status: 'blocked',
            scores: const TaskProjectionScores(
              reward: 0.92,
              pressure: 0.92,
              risk: 0.70,
              metadataCompleteness: 0.78,
            ),
          ),
        ],
        edges: const <TaskProjectionEdge>[
          TaskProjectionEdge(
            fromTaskId: 'collect',
            toTaskId: 'review',
            relationType: 'blocks',
            source: 'explicit',
            confidence: 1,
          ),
        ],
      ),
      now: now,
    );

    expect(
      index
          .tasksForInsight(TaskInsightIds.quickUnblocks)
          .map((candidate) => candidate.taskId),
      contains('collect'),
    );
    expect(index.unblockPlanFor('review').primaryBlockerId, 'collect');
  });

  test('reports projection coverage mismatches', () {
    final index = TaskInsightIndex.build(
      workspaceTasks: <WorkspaceTask>[
        _workspaceTask(id: 'queue-only', title: 'Queue only'),
      ],
      graph: const TaskProjectionGraph(
        tasks: <TaskProjectionTask>[
          TaskProjectionTask(
            taskId: 'graph-only',
            title: 'Graph only',
            status: 'open',
            priority: 'normal',
          ),
        ],
      ),
      now: now,
    );

    expect(index.projectionCoverageMessage, contains('queue backlog items'));
    expect(index.projectionCoverageMessage, contains('insight backlog items'));
  });

  test('ignores completed queue tasks in projection coverage', () {
    final index = TaskInsightIndex.build(
      workspaceTasks: <WorkspaceTask>[
        _workspaceTask(id: 'active', title: 'Active task'),
        _workspaceTask(id: 'done', title: 'Done task', status: 'done'),
      ],
      graph: const TaskProjectionGraph(
        tasks: <TaskProjectionTask>[
          TaskProjectionTask(
            taskId: 'active',
            title: 'Active task',
            status: 'open',
            priority: 'normal',
          ),
        ],
      ),
      now: now,
    );

    expect(index.projectionCoverageMessage, isEmpty);
  });

  test('reports dependency cycles as metadata gaps', () {
    final index = TaskInsightIndex.build(
      workspaceTasks: <WorkspaceTask>[
        _workspaceTask(id: 'task-a', title: 'Task A'),
        _workspaceTask(id: 'task-b', title: 'Task B'),
      ],
      graph: TaskProjectionGraph(
        tasks: <TaskProjectionTask>[
          _projectionTask(
            id: 'task-a',
            title: 'Task A',
            scores: const TaskProjectionScores(metadataCompleteness: 0.90),
          ),
          _projectionTask(
            id: 'task-b',
            title: 'Task B',
            scores: const TaskProjectionScores(metadataCompleteness: 0.90),
          ),
        ],
        edges: const <TaskProjectionEdge>[
          TaskProjectionEdge(
            fromTaskId: 'task-a',
            toTaskId: 'task-b',
            relationType: 'depends_on',
            source: 'explicit',
            confidence: 1,
          ),
          TaskProjectionEdge(
            fromTaskId: 'task-b',
            toTaskId: 'task-a',
            relationType: 'depends_on',
            source: 'explicit',
            confidence: 1,
          ),
        ],
      ),
      now: now,
    );

    expect(
      index.metadataGapsFor('task-a').map((gap) => gap.field),
      contains('dependency_cycle'),
    );
    expect(
      index.metadataGapsFor('task-b').map((gap) => gap.field),
      contains('dependency_cycle'),
    );
  });
}

/// Builds a workspace task with practical defaults for insight tests.
WorkspaceTask _workspaceTask({
  required String id,
  required String title,
  String description = '',
  String status = 'open',
  String priority = 'normal',
  DateTime? dueAt,
  int estimateMinutes = 30,
  String context = '',
  String domain = '',
}) {
  return WorkspaceTask(
    id: id,
    title: title,
    detail: status,
    done: status == 'done',
    description: description,
    status: status,
    priority: priority,
    dueAt: dueAt,
    estimateMinutes: estimateMinutes,
    context: context,
    domain: domain,
    confidence: 0.80,
    active: status != 'done' && status != 'canceled',
  );
}

/// Builds a projected task with practical defaults for insight tests.
TaskProjectionTask _projectionTask({
  required String id,
  required String title,
  String status = 'open',
  DateTime? dueAt,
  String valueType = '',
  TaskProjectionScores scores = const TaskProjectionScores(),
}) {
  return TaskProjectionTask(
    taskId: id,
    title: title,
    status: status,
    priority: 'normal',
    dueAt: dueAt,
    valueType: valueType,
    scores: scores,
    confidence: 0.80,
  );
}
