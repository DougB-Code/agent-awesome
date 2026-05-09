/// Verifies task graph fact derivations.
library;

import 'package:agentawesome_ui/domain/task_graph_derivations.dart';
import 'package:agentawesome_ui/domain/task_graph_facts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs task graph derivation tests.
void main() {
  group('TaskGraphDeriver', () {
    test('derives blockers from blocks and depends-on edges', () {
      const graph = TaskGraphSnapshot(
        edges: <TaskGraphEdge>[
          TaskGraphEdge(
            fromTaskId: 'design',
            toTaskId: 'build',
            kind: TaskGraphEdgeKind.blocks,
          ),
          TaskGraphEdge(
            fromTaskId: 'build',
            toTaskId: 'approval',
            kind: TaskGraphEdgeKind.dependsOn,
          ),
        ],
      );

      expect(TaskGraphDeriver.blockerIdsFor(graph, 'build'), <String>[
        'approval',
        'design',
      ]);
      expect(TaskGraphDeriver.blockedTaskIdsFor(graph, 'design'), <String>[
        'build',
      ]);
      expect(TaskGraphDeriver.blockedTaskIdsFor(graph, 'approval'), <String>[
        'build',
      ]);
    });

    test('derives slipping status when schedule is after due date', () {
      final now = DateTime(2026, 5, 4, 9);
      final node = TaskGraphNode(
        id: 'report',
        title: 'Finish report',
        dueAt: DateTime(2026, 5, 5, 17),
        scheduledAt: DateTime(2026, 5, 6, 9),
        person: 'Bob',
        estimateMinutes: 90,
        project: 'Crazy',
        view: 'Work',
        priority: 'high',
      );

      final state = TaskGraphDeriver.stateFor(
        graph: const TaskGraphSnapshot(nodes: <TaskGraphNode>[]),
        node: node,
        now: now,
      );

      expect(state.status, TaskGraphDerivedStatus.slipping);
      expect(state.attentionTarget, TaskGraphAttentionTarget.deadlineRisk);
    });

    test(
      'repurposes attention toward blockers, spend, return, and ready work',
      () {
        final now = DateTime(2026, 5, 4, 9);
        const graph = TaskGraphSnapshot(
          edges: <TaskGraphEdge>[
            TaskGraphEdge(
              fromTaskId: 'legal',
              toTaskId: 'launch',
              kind: TaskGraphEdgeKind.blocks,
            ),
          ],
        );

        expect(
          TaskGraphDeriver.stateFor(
            graph: graph,
            node: const TaskGraphNode(id: 'launch', title: 'Launch'),
            now: now,
          ).attentionTarget,
          TaskGraphAttentionTarget.clearBlocker,
        );
        expect(
          TaskGraphDeriver.stateFor(
            graph: const TaskGraphSnapshot(),
            node: const TaskGraphNode(
              id: 'tool',
              title: 'Buy tool',
              spendCents: 12000,
            ),
            now: now,
          ).attentionTarget,
          TaskGraphAttentionTarget.spendReview,
        );
        expect(
          TaskGraphDeriver.stateFor(
            graph: const TaskGraphSnapshot(),
            node: const TaskGraphNode(
              id: 'invoice',
              title: 'Send invoice',
              earnCents: 200000,
              priority: 'urgent',
            ),
            now: now,
          ).attentionTarget,
          TaskGraphAttentionTarget.highReturn,
        );
        expect(
          TaskGraphDeriver.stateFor(
            graph: const TaskGraphSnapshot(),
            node: TaskGraphNode(
              id: 'desk',
              title: 'Clear desk',
              scheduledAt: now.subtract(const Duration(minutes: 5)),
            ),
            now: now,
          ).attentionTarget,
          TaskGraphAttentionTarget.readyNow,
        );
      },
    );
  });
}
