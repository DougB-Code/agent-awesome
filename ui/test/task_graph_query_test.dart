/// Verifies canonical graph-query behavior for the constellation search.
library;

import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/domain/task_graph_query.dart';
import 'package:agentawesome_ui/domain/task_insight_index.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises SQL-like FIND and MATCH graph queries.
void main() {
  group('TaskGraphConstellationQuery', () {
    test('matches bounded dependency paths with row-linked path metadata', () {
      final index = TaskInsightIndex.build(
        workspaceTasks: const <WorkspaceTask>[],
        graph: _relationshipGraph(),
        now: DateTime(2026, 5, 4),
      );
      final result = TaskGraphConstellationQuery.run(
        index,
        'MATCH task -[depends_on*1..3]-> task WHERE from.status != "done" AND to.status != "done" RETURN from.title, path.depth, to.title, path.node_ids ORDER BY path.depth DESC LIMIT 10',
        now: DateTime(2026, 5, 4),
      );

      expect(result.hasError, isFalse);
      expect(result.expandResults, isTrue);
      expect(result.rows.first['path.depth'], 2);
      expect(result.paths.first.depth, 2);
      expect(
        result.projection.nodes.map((node) => node.taskId),
        containsAll(<String>['risk-api', 'api-contract', 'mobile-release']),
      );
      expect(
        result.projection.edges.map((edge) => edge.source).toSet(),
        <String>{'query_path'},
      );
      expect(
        result.projection.edges.map((edge) => edge.factSource).toSet(),
        <String>{'explicit'},
      );
      expect(
        result.projection.edges.map((edge) => edge.firewall).toSet(),
        <String>{'user'},
      );
      expect(
        result.projection.edges.expand((edge) => edge.evidenceIds),
        contains('evidence-api-contract'),
      );
      expect(result.summary, contains('paths'));
    });

    test('finds high-risk work by owner with typed rows', () {
      final index = TaskInsightIndex.build(
        workspaceTasks: const <WorkspaceTask>[],
        graph: _relationshipGraph(),
        now: DateTime(2026, 5, 4),
      );
      final result = TaskGraphConstellationQuery.run(
        index,
        'FIND task WHERE owner = "Priya" AND risk >= 0.6 RETURN id, owner, risk ORDER BY risk DESC LIMIT 10',
        now: DateTime(2026, 5, 4),
      );

      expect(result.group, TaskGraphQueryGroup.owner);
      expect(
        result.projection.nodes.map((node) => node.taskId),
        containsAll(<String>['risk-api', 'api-contract']),
      );
      expect(
        result.projection.nodes.map((node) => node.owner).toSet(),
        <String>{'Priya'},
      );
      expect(
        result.rows.first['risk'] as double,
        greaterThan(result.rows.last['risk'] as double),
      );
    });

    test(
      'reports syntax errors instead of falling back to phrase matching',
      () {
        final index = TaskInsightIndex.build(
          workspaceTasks: const <WorkspaceTask>[],
          graph: _relationshipGraph(),
          now: DateTime(2026, 5, 4),
        );
        final result = TaskGraphConstellationQuery.run(
          index,
          'which projects am I on the critical path?',
          now: DateTime(2026, 5, 4),
        );

        expect(result.hasError, isTrue);
        expect(result.projection.nodes, isEmpty);
        expect(result.summary, contains('Query error'));
      },
    );

    test(
      'keeps saved query examples outside the core parser but executable',
      () {
        final index = TaskInsightIndex.build(
          workspaceTasks: const <WorkspaceTask>[],
          graph: _relationshipGraph(),
          now: DateTime(2026, 5, 4),
        );

        for (final example in taskGraphConstellationQueryExamples) {
          final result = TaskGraphConstellationQuery.run(
            index,
            example.query,
            now: DateTime(2026, 5, 4),
          );

          expect(result.hasError, isFalse, reason: example.label);
        }
      },
    );
  });
}

/// Builds a graph with dependency depth and owner risk for query tests.
TaskProjectionGraph _relationshipGraph() {
  return TaskProjectionGraph(
    tasks: <TaskProjectionTask>[
      TaskProjectionTask(
        taskId: 'risk-api',
        title: 'Stabilize risk API',
        status: 'blocked',
        priority: 'urgent',
        dueAt: DateTime(2026, 5, 5, 12),
        estimateMinutes: 180,
        owner: 'Priya',
        project: 'Platform',
        scores: const TaskProjectionScores(
          reward: 0.86,
          pressure: 0.82,
          risk: 0.92,
          timePressure: 0.78,
          humanEffort: 0.72,
          elevation: 0.9,
        ),
      ),
      const TaskProjectionTask(
        taskId: 'api-contract',
        title: 'Publish API contract',
        status: 'waiting',
        priority: 'high',
        estimateMinutes: 90,
        owner: 'Priya',
        project: 'Platform',
        scores: TaskProjectionScores(
          reward: 0.74,
          pressure: 0.7,
          risk: 0.68,
          timePressure: 0.66,
          humanEffort: 0.48,
          elevation: 0.72,
        ),
      ),
      const TaskProjectionTask(
        taskId: 'mobile-release',
        title: 'Ship mobile release',
        status: 'open',
        priority: 'urgent',
        estimateMinutes: 240,
        owner: 'Mina',
        project: 'Mobile',
        scores: TaskProjectionScores(
          reward: 0.95,
          pressure: 0.9,
          risk: 0.72,
          timePressure: 0.84,
          humanEffort: 0.82,
          elevation: 0.94,
        ),
      ),
      const TaskProjectionTask(
        taskId: 'docs-refresh',
        title: 'Refresh docs',
        status: 'open',
        priority: 'normal',
        estimateMinutes: 45,
        owner: 'Noor',
        project: 'Enablement',
        scores: TaskProjectionScores(
          reward: 0.4,
          pressure: 0.2,
          risk: 0.18,
          humanEffort: 0.2,
          elevation: 0.26,
        ),
      ),
    ],
    edges: const <TaskProjectionEdge>[
      TaskProjectionEdge(
        fromTaskId: 'api-contract',
        toTaskId: 'risk-api',
        relationType: 'depends_on',
        source: 'explicit',
        sourceKind: 'explicit',
        firewall: 'user',
        sensitivity: 'private',
        confidence: 0.95,
        explanation: 'API contract depends on the risk API stabilizing.',
        evidenceIds: <String>['evidence-risk-api'],
        actor: 'seed',
      ),
      TaskProjectionEdge(
        fromTaskId: 'mobile-release',
        toTaskId: 'api-contract',
        relationType: 'depends_on',
        source: 'explicit',
        sourceKind: 'explicit',
        firewall: 'user',
        sensitivity: 'private',
        confidence: 0.94,
        explanation: 'Mobile release depends on the API contract.',
        evidenceIds: <String>['evidence-api-contract'],
        actor: 'seed',
      ),
      TaskProjectionEdge(
        fromTaskId: 'docs-refresh',
        toTaskId: 'api-contract',
        relationType: 'depends_on',
        source: 'explicit',
        sourceKind: 'explicit',
        firewall: 'user',
        sensitivity: 'private',
        confidence: 0.7,
        explanation: 'Docs need the API contract.',
        evidenceIds: <String>['evidence-docs'],
        actor: 'seed',
      ),
    ],
  );
}
