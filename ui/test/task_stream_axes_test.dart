/// Verifies reusable task stream axis projection behavior.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/ui/task_stream_axes.dart';

void main() {
  group('TaskStreamAxisProjector', () {
    test('rebuckets columns while preserving row buckets by task id', () {
      final view = TaskStreamAxisProjector.project(
        _projection,
        columnAxis: TaskStreamAxisDimension.priority,
        rowAxis: TaskStreamAxisDimension.status,
      );

      expect(view.lanes.map((lane) => lane.id), <String>['high', 'normal']);
      expect(view.lanes.first.cards.map((card) => card.taskId), <String>[
        'draft',
      ]);
      expect(view.rowBucketsByTaskId['draft']!.title, 'Open');
      expect(view.rowBucketsByTaskId['approval']!.title, 'Waiting');
    });

    test('supports spend buckets from explicit spend scores', () {
      final view = TaskStreamAxisProjector.project(
        _projection,
        columnAxis: TaskStreamAxisDimension.spend,
        rowAxis: TaskStreamAxisDimension.attention,
      );

      expect(view.lanes.map((lane) => lane.id), <String>[
        'low-spend',
        'high-spend',
      ]);
      expect(view.lanes.last.title, 'High spend');
    });

    test('exposes encoded fact dimensions for stream selection', () {
      expect(
        TaskStreamAxisProjector.factDimensions,
        containsAll(<TaskStreamAxisDimension>[
          TaskStreamAxisDimension.due,
          TaskStreamAxisDimension.scheduled,
          TaskStreamAxisDimension.estimate,
          TaskStreamAxisDimension.spend,
          TaskStreamAxisDimension.person,
          TaskStreamAxisDimension.project,
        ]),
      );
      expect(
        TaskStreamAxisProjector.factDimensions,
        isNot(contains(TaskStreamAxisDimension.attention)),
      );
      expect(
        TaskStreamAxisProjector.factDimensions,
        isNot(contains(TaskStreamAxisDimension.blockers)),
      );
    });

    test('does not promote attention labels into lifecycle status buckets', () {
      final view = TaskStreamAxisProjector.project(
        const TaskStreamProjection(
          lanes: <TaskStreamLane>[
            TaskStreamLane(
              id: 'now',
              title: 'Now',
              cards: <TaskStreamCard>[
                TaskStreamCard(
                  taskId: 'bad-status',
                  title: 'Clean up status metadata',
                  status: 'Deep Focus',
                  priority: 'normal',
                ),
              ],
            ),
          ],
        ),
        columnAxis: TaskStreamAxisDimension.attention,
        rowAxis: TaskStreamAxisDimension.status,
      );

      expect(view.lanes.single.title, 'General');
      expect(view.rowBucketsByTaskId['bad-status']!.title, 'Other status');
      expect(view.rowBucketsByTaskId['bad-status']!.title, isNot('Deep Focus'));
    });
  });
}

const _projection = TaskStreamProjection(
  lanes: <TaskStreamLane>[
    TaskStreamLane(
      id: 'now',
      title: 'Now',
      subtitle: 'Ready work',
      cards: <TaskStreamCard>[
        TaskStreamCard(
          taskId: 'draft',
          title: 'Draft proposal',
          status: 'open',
          priority: 'high',
          project: 'Pilot',
          owner: 'Doug',
          spendScore: 0.2,
          estimateMinutes: 45,
        ),
      ],
    ),
    TaskStreamLane(
      id: 'later',
      title: 'Later',
      subtitle: 'This week',
      cards: <TaskStreamCard>[
        TaskStreamCard(
          taskId: 'approval',
          title: 'Follow up on approval',
          status: 'waiting',
          priority: 'normal',
          spendLabel: 'High switch',
          spendScore: 0.8,
          estimateMinutes: 10,
        ),
      ],
    ),
  ],
);
