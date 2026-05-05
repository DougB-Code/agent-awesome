/// Verifies task stream canvas geometry and focus behavior.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/ui/task_stream_axes.dart';
import 'package:agentawesome_ui/ui/task_stream_canvas.dart';

void main() {
  group('TaskStreamCanvasLayout focus', () {
    test('focuses a stream route from a tapped curve', () {
      final layout = _buildFocusLayout();
      final link = layout.links.firstWhere((link) {
        return link.link.streamId == 'work-release';
      });
      final focus = layout.focusAt(
        Offset(
          (link.from.rect.right + link.to.rect.left) / 2,
          (link.from.rect.center.dy + link.to.rect.center.dy) / 2,
        ),
      );

      expect(focus, isNotNull);
      expect(focus!.streamId, 'work-release');
      expect(
        layout.placements
            .where((placement) {
              return layout.isFocusedCard(placement, focus);
            })
            .map((placement) => placement.card.taskId),
        containsAll(<String>['draft', 'budget']),
      );
    });

    test('keeps unrelated cards outside a focused stream route', () {
      final layout = _buildFocusLayout();
      final focus = TaskStreamFocus(streamId: 'work-release');
      final focused = layout.placements
          .where((placement) {
            return layout.isFocusedCard(placement, focus);
          })
          .map((placement) => placement.card.taskId);

      expect(focused, containsAll(<String>['draft', 'budget']));
      expect(focused, isNot(contains('groceries')));
      expect(focused, isNot(contains('readout')));
    });

    test('focuses only graph neighbors when a card is selected', () {
      final layout = _buildFocusLayout();
      final focus = TaskStreamFocus.card(
        layout.placements
            .singleWhere((placement) => placement.card.taskId == 'draft')
            .card,
      );
      final focused = layout.placements
          .where((placement) {
            return layout.isFocusedCard(placement, focus);
          })
          .map((placement) => placement.card.taskId);

      expect(focused, containsAll(<String>['draft', 'budget']));
      expect(focused, isNot(contains('readout')));
    });

    test('toggles additional task and stream targets into focus', () {
      final layout = _buildFocusLayout();
      final draft = layout.placements
          .singleWhere((placement) => placement.card.taskId == 'draft')
          .card;
      final combined = TaskStreamFocus.card(
        draft,
      ).toggled(const TaskStreamFocus(streamId: 'errand-loop'));
      final focused = layout.placements
          .where((placement) => layout.isFocusedCard(placement, combined))
          .map((placement) => placement.card.taskId);

      expect(
        focused,
        containsAll(<String>['draft', 'budget', 'groceries', 'readout']),
      );

      final removedDraft = combined.toggled(TaskStreamFocus.card(draft));
      final remaining = layout.placements
          .where((placement) => layout.isFocusedCard(placement, removedDraft))
          .map((placement) => placement.card.taskId);

      expect(remaining, containsAll(<String>['groceries', 'readout']));
      expect(remaining, isNot(contains('draft')));
      expect(remaining, isNot(contains('budget')));
    });

    test('uses denser geometry in compact focus layout', () {
      final regular = _buildFocusLayout();
      final compact = _buildFocusLayout(
        compact: true,
        focus: const TaskStreamFocus(taskId: 'draft'),
      );

      expect(compact.compact, isTrue);
      expect(compact.cardHeight, lessThan(regular.cardHeight));
      expect(compact.cardStackStep, lessThan(regular.cardStackStep));
      expect(compact.size.height, lessThan(regular.size.height));
    });

    test('compact focus hides unrelated cards and unused rows', () {
      final compact = _buildFocusLayout(
        compact: true,
        focus: const TaskStreamFocus(taskId: 'draft'),
      );
      final taskIds = compact.placements.map(
        (placement) => placement.card.taskId,
      );
      final rowTitles = compact.rows.map((row) => row.title);

      expect(taskIds, containsAll(<String>['draft', 'budget']));
      expect(taskIds, isNot(contains('groceries')));
      expect(taskIds, isNot(contains('readout')));
      expect(rowTitles, containsAll(<String>['Deep Work', 'Admin']));
      expect(rowTitles, isNot(contains('Errands')));
      expect(compact.links, hasLength(1));
    });

    test('stretches timeline columns when the panel widens', () {
      final regular = _buildFocusLayout();
      final wide = _buildFocusLayout(width: 1200);

      expect(
        wide.columns.first.width,
        greaterThan(regular.columns.first.width),
      );
      expect(wide.size.width, greaterThan(regular.size.width));
    });
  });
}

/// Builds a compact stream projection with one cross-lane relation.
TaskStreamCanvasLayout _buildFocusLayout({
  bool compact = false,
  double width = 680,
  TaskStreamFocus? focus,
}) {
  const lanes = <TaskStreamLane>[
    TaskStreamLane(
      id: 'now',
      title: 'Now',
      cards: <TaskStreamCard>[
        TaskStreamCard(
          taskId: 'draft',
          title: 'Draft launch plan',
          status: 'open',
          priority: 'normal',
          flowLane: 'Deep Work',
          streamId: 'work-release',
        ),
        TaskStreamCard(
          taskId: 'groceries',
          title: 'Buy groceries',
          status: 'open',
          priority: 'normal',
          flowLane: 'Errands',
          streamId: 'errand-loop',
        ),
      ],
    ),
    TaskStreamLane(
      id: 'next',
      title: 'Next',
      cards: <TaskStreamCard>[
        TaskStreamCard(
          taskId: 'budget',
          title: 'Update launch budget',
          status: 'open',
          priority: 'normal',
          flowLane: 'Admin',
          streamId: 'work-release',
        ),
        TaskStreamCard(
          taskId: 'readout',
          title: 'Prepare release readout',
          status: 'open',
          priority: 'normal',
          flowLane: 'Deep Work',
          streamId: 'work-release',
        ),
      ],
    ),
  ];
  const links = <TaskStreamLink>[
    TaskStreamLink(
      fromTaskId: 'draft',
      toTaskId: 'budget',
      relationType: 'depends_on',
      transitionType: 'enables',
      streamId: 'work-release',
      confidence: 1,
    ),
    TaskStreamLink(
      fromTaskId: 'groceries',
      toTaskId: 'readout',
      relationType: 'related',
      transitionType: 'cross_pollinates',
      streamId: 'errand-loop',
      confidence: 1,
    ),
  ];
  final rowBucketsByTaskId = <String, TaskStreamAxisBucket>{
    for (final lane in lanes)
      for (final card in lane.cards)
        card.taskId: TaskStreamAxisProjector.bucketFor(
          lane: lane,
          card: card,
          dimension: TaskStreamAxisDimension.attention,
        ),
  };
  return TaskStreamCanvasLayout.build(
    lanes,
    links,
    BoxConstraints.tightFor(width: width, height: 420),
    rowAxis: TaskStreamAxisDimension.attention,
    rowBucketsByTaskId: rowBucketsByTaskId,
    compact: compact,
    focus: focus,
  );
}
