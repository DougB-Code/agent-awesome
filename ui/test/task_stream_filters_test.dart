/// Verifies task stream axis filtering.
library;

import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/ui/task_stream_axes.dart';
import 'package:agentawesome_ui/ui/task_stream_filters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs task stream filter projector tests.
void main() {
  test('filters cards and links by person and project buckets', () {
    final model = TaskStreamFilterProjector.build(
      _projection,
      selection: const TaskStreamFilterSelection(
        filters: <TaskStreamAxisDimension, String>{
          TaskStreamAxisDimension.person: 'bob',
          TaskStreamAxisDimension.project: 'crazy',
        },
      ),
    );

    expect(model.taskCount, 1);
    expect(model.estimateMinutes, 90);
    expect(model.filteredProjection.lanes.first.cards.single.taskId, 'agent');
    expect(model.filteredProjection.links, isEmpty);
  });

  test('scopes filter options by the other selected filters', () {
    final model = TaskStreamFilterProjector.build(
      _projection,
      selection: const TaskStreamFilterSelection(
        filters: <TaskStreamAxisDimension, String>{
          TaskStreamAxisDimension.project: 'crazy',
        },
      ),
    );

    expect(
      model.optionsFor(TaskStreamAxisDimension.person).map((option) {
        return option.label;
      }),
      <String>['Bob', 'Dana'],
    );
    expect(
      model.optionsFor(TaskStreamAxisDimension.project).map((option) {
        return option.label;
      }),
      <String>['Crazy', 'Quiet'],
    );
  });

  test('exposes filter options for every stream axis dimension', () {
    final model = TaskStreamFilterProjector.build(
      _projection,
      selection: const TaskStreamFilterSelection(),
    );

    for (final dimension in TaskStreamFilterProjector.dimensions) {
      expect(model.optionsFor(dimension), isNotEmpty);
    }
  });
}

const _projection = TaskStreamProjection(
  lanes: <TaskStreamLane>[
    TaskStreamLane(
      id: 'now',
      title: 'Now',
      cards: <TaskStreamCard>[
        TaskStreamCard(
          taskId: 'agent',
          title: 'Wire agent',
          status: 'open',
          priority: 'high',
          project: 'Crazy',
          owner: 'Bob',
          estimateMinutes: 90,
        ),
        TaskStreamCard(
          taskId: 'brief',
          title: 'Review brief',
          status: 'open',
          priority: 'normal',
          project: 'Quiet',
          owner: 'Bob',
          estimateMinutes: 30,
        ),
      ],
    ),
    TaskStreamLane(
      id: 'next',
      title: 'Next',
      cards: <TaskStreamCard>[
        TaskStreamCard(
          taskId: 'follow-up',
          title: 'Follow up',
          status: 'waiting',
          priority: 'normal',
          project: 'Crazy',
          owner: 'Dana',
          spendLabel: 'High switch',
          spendScore: 0.8,
          bottleneckScore: 0.8,
          estimateMinutes: 15,
        ),
      ],
    ),
  ],
  links: <TaskStreamLink>[
    TaskStreamLink(
      fromTaskId: 'agent',
      toTaskId: 'follow-up',
      relationType: 'blocks',
    ),
  ],
);
