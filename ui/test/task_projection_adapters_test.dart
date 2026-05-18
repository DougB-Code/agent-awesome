/// Verifies canonical task projection parsing and UI adapter behavior.
library;

import 'package:agentawesome_ui/clients/mcp_client.dart';
import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/domain/task_insight_index.dart';
import 'package:agentawesome_ui/domain/task_projection_adapters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the canonical projection graph contract used by task views.
void main() {
  group('TaskProjectionGraph parsing', () {
    test('parses task facts, facets, memberships, scores, and edges', () {
      final graph = parseTaskProjectionGraph(<String, dynamic>{
        'generated_at': '2026-05-03T10:00:00Z',
        'scope': <String, dynamic>{
          'id': 'personal-default',
          'kind': 'workspace',
          'label': 'Personal workspace',
        },
        'tasks': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'task-a',
            'title': 'Draft proposal',
            'description': 'Write the first version.',
            'status': 'open',
            'priority': 'high',
            'due_at': '2026-05-04T12:00:00Z',
            'topics': <String>['proposal'],
            'estimate_minutes': 45,
            'work_breakdown': <String, dynamic>{
              'code': '1.1',
              'deliverable': 'Proposal draft',
              'start_criteria': <String>['Source notes ready'],
              'acceptance_criteria': <String>['Rubric checked'],
              'requirement_refs': <String>['R1'],
              'rubric_refs': <String>['C1'],
              'spend_cents': 2500,
              'spend_currency': 'USD',
              'resources': <Map<String, dynamic>>[
                <String, dynamic>{'name': 'Source notes'},
              ],
            },
            'scores': <String, dynamic>{
              'reward': 0.8,
              'pressure': 0.7,
              'risk': 0.4,
              'time_pressure': 0.6,
              'human_effort': 0.5,
              'agent_fit': 0.75,
              'elevation': 0.72,
            },
            'facet_ids': <String>['time:now', 'attention:deep-work'],
            'confidence': 0.9,
            'explanation': 'Projected from task metadata.',
          },
        ],
        'facets': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'time:now',
            'kind': 'time',
            'label': 'Now',
            'source': 'derived',
            'confidence': 0.9,
          },
        ],
        'memberships': <Map<String, dynamic>>[
          <String, dynamic>{
            'task_id': 'task-a',
            'facet_id': 'time:now',
            'dimension': 'time',
            'source': 'derived',
            'confidence': 0.9,
          },
        ],
        'relations': <Map<String, dynamic>>[
          <String, dynamic>{
            'from_task_id': 'task-b',
            'to_task_id': 'task-a',
            'type': 'enables',
            'source': 'explicit',
            'confidence': 0.8,
            'explanation': 'B enables A.',
          },
        ],
      });

      expect(graph.generatedAt, DateTime.parse('2026-05-03T10:00:00Z'));
      expect(graph.tasks.single.workBreakdown.deliverable, 'Proposal draft');
      expect(
        graph.tasks.single.workBreakdown.resources.single.name,
        'Source notes',
      );
      expect(graph.facets.single.id, 'time:now');
      expect(graph.memberships.single.dimension, 'time');
      expect(graph.edges.single.relationType, 'enables');
    });

    test('parses graph-backed task and relation field names', () {
      final graph = parseTaskProjectionGraph(<String, dynamic>{
        'tasks': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'task-from-graph',
            'title': 'Graph-backed task',
            'status': 'open',
            'priority': 'high',
          },
        ],
        'relations': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'relation-1',
            'from_task_id': 'task-from-graph',
            'to_task_id': 'task-other',
            'type': 'depends_on',
          },
        ],
      });

      expect(graph.tasks.single.taskId, 'task-from-graph');
      expect(graph.edges.single.relationType, 'depends_on');
    });
  });

  group('TaskProjectionAdapters', () {
    test('groups stream cards from canonical facets', () {
      final stream = TaskProjectionAdapters.stream(_projectionGraph());
      final nowLane = stream.lanes.firstWhere((lane) => lane.id == 'now');
      final nextLane = stream.lanes.firstWhere((lane) => lane.id == 'next');

      expect(nowLane.cards.map((card) => card.taskId), contains('task-a'));
      expect(nextLane.cards.map((card) => card.taskId), contains('task-b'));
      expect(stream.links, hasLength(1));
      expect(stream.links.single.fromTaskId, 'task-b');
      expect(stream.links.single.toTaskId, 'task-a');
      expect(stream.links.single.transitionType, 'enables');
    });

    test('constellation draws only sparse canonical task edges', () {
      final constellation = TaskProjectionAdapters.constellation(
        _projectionGraph(),
      );

      expect(
        constellation.nodes.map((node) => node.taskId),
        containsAll(<String>['task-a', 'task-b']),
      );
      expect(constellation.edges, hasLength(1));
      expect(constellation.edges.single.relationType, 'depends_on');
      expect(constellation.edges.single.source, 'explicit');
    });

    test('critical path constellation highlights longest dependency chain', () {
      final index = TaskInsightIndex.build(
        workspaceTasks: const <WorkspaceTask>[],
        graph: _relationshipLensGraph(),
      );
      final constellation = TaskInsightProjectionAdapters.constellation(
        index,
        mode: TaskConstellationInsightMode.criticalPath,
      );

      expect(
        constellation.nodes.map((node) => node.taskId),
        containsAll(<String>['risk-api', 'api-contract', 'mobile-release']),
      );
      expect(
        constellation.nodes.map((node) => node.project),
        containsAll(<String>['Platform', 'Mobile']),
      );
      expect(
        constellation.edges.where((edge) => edge.source == 'critical_path'),
        hasLength(2),
      );
      expect(
        constellation.edges.any(
          (edge) => edge.explanation.contains('Platform into Mobile'),
        ),
        isTrue,
      );
    });

    test('risk owner constellation groups materialized risks by person', () {
      final index = TaskInsightIndex.build(
        workspaceTasks: const <WorkspaceTask>[],
        graph: _relationshipLensGraph(),
      );
      final constellation = TaskInsightProjectionAdapters.constellation(
        index,
        mode: TaskConstellationInsightMode.riskOwners,
      );

      expect(
        constellation.nodes.map((node) => node.owner),
        containsAll(<String>['Priya', 'Mina']),
      );
      expect(
        constellation.edges.map((edge) => edge.source),
        contains('materialized_risk'),
      );
    });
  });
}

/// Builds a small canonical graph for adapter assertions.
TaskProjectionGraph _projectionGraph() {
  return TaskProjectionGraph(
    generatedAt: DateTime.parse('2026-05-03T10:00:00Z'),
    tasks: const <TaskProjectionTask>[
      TaskProjectionTask(
        taskId: 'task-a',
        title: 'Draft proposal',
        status: 'open',
        priority: 'high',
        description: 'Write the first version.',
        estimateMinutes: 45,
        scores: TaskProjectionScores(
          reward: 0.84,
          pressure: 0.68,
          risk: 0.42,
          timePressure: 0.52,
          humanEffort: 0.58,
          agentFit: 0.78,
          elevation: 0.74,
        ),
        facetIds: <String>['time:now', 'attention:deep-work', 'topic:proposal'],
        confidence: 0.9,
      ),
      TaskProjectionTask(
        taskId: 'task-b',
        title: 'Collect source notes',
        status: 'open',
        priority: 'normal',
        estimateMinutes: 20,
        scores: TaskProjectionScores(
          reward: 0.44,
          pressure: 0.32,
          risk: 0.18,
          timePressure: 0.2,
          humanEffort: 0.22,
          agentFit: 0.64,
          elevation: 0.42,
        ),
        facetIds: <String>['time:next', 'attention:admin', 'view:work'],
        confidence: 0.8,
      ),
    ],
    facets: const <TaskProjectionFacet>[
      TaskProjectionFacet(
        id: 'time:now',
        dimension: 'time',
        label: 'Now',
        source: 'derived',
      ),
      TaskProjectionFacet(
        id: 'time:next',
        dimension: 'time',
        label: 'Next',
        source: 'derived',
      ),
      TaskProjectionFacet(
        id: 'attention:deep-work',
        dimension: 'attention',
        label: 'Deep Work',
        source: 'derived',
      ),
      TaskProjectionFacet(
        id: 'attention:admin',
        dimension: 'attention',
        label: 'Admin',
        source: 'derived',
      ),
      TaskProjectionFacet(
        id: 'topic:proposal',
        dimension: 'topic',
        label: 'Proposal',
        source: 'task',
      ),
    ],
    memberships: const <TaskProjectionMembership>[
      TaskProjectionMembership(
        taskId: 'task-a',
        facetId: 'time:now',
        dimension: 'time',
      ),
      TaskProjectionMembership(
        taskId: 'task-b',
        facetId: 'time:next',
        dimension: 'time',
      ),
    ],
    edges: const <TaskProjectionEdge>[
      TaskProjectionEdge(
        fromTaskId: 'task-a',
        toTaskId: 'task-b',
        relationType: 'depends_on',
        source: 'explicit',
        confidence: 0.88,
        explanation: 'A depends on B.',
      ),
    ],
  );
}

/// Builds a graph with enough depth and owner risk for relationship lenses.
TaskProjectionGraph _relationshipLensGraph() {
  return const TaskProjectionGraph(
    tasks: <TaskProjectionTask>[
      TaskProjectionTask(
        taskId: 'risk-api',
        title: 'Stabilize risk API',
        status: 'blocked',
        priority: 'urgent',
        estimateMinutes: 180,
        owner: 'Priya',
        project: 'Platform',
        scores: TaskProjectionScores(
          reward: 0.86,
          pressure: 0.82,
          risk: 0.92,
          timePressure: 0.78,
          humanEffort: 0.72,
          elevation: 0.9,
        ),
      ),
      TaskProjectionTask(
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
      TaskProjectionTask(
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
      TaskProjectionTask(
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
    edges: <TaskProjectionEdge>[
      TaskProjectionEdge(
        fromTaskId: 'api-contract',
        toTaskId: 'risk-api',
        relationType: 'depends_on',
        source: 'explicit',
        confidence: 0.95,
        explanation: 'API contract depends on the risk API stabilizing.',
      ),
      TaskProjectionEdge(
        fromTaskId: 'mobile-release',
        toTaskId: 'api-contract',
        relationType: 'depends_on',
        source: 'explicit',
        confidence: 0.94,
        explanation: 'Mobile release depends on the API contract.',
      ),
      TaskProjectionEdge(
        fromTaskId: 'docs-refresh',
        toTaskId: 'api-contract',
        relationType: 'depends_on',
        source: 'explicit',
        confidence: 0.7,
        explanation: 'Docs need the API contract.',
      ),
    ],
  );
}
