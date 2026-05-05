/// Tests hierarchical WBS tree construction.
library;

import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/domain/task_wbs_tree.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs WBS tree tests.
void main() {
  test('builds root buckets, intermediate buckets, and leaf work packages', () {
    final roots = buildTaskWbsTree(<WorkspaceTask>[
      _task(
        id: 'packet',
        title: 'Prep packet',
        domain: 'Work',
        context: 'Focus',
        code: '1.1.1',
        minutes: 60,
        cost: 7500,
      ),
      _task(
        id: 'notes',
        title: 'Finish notes',
        domain: 'Work',
        context: 'Focus',
        code: '1.1.2',
        minutes: 30,
        cost: 3750,
      ),
      _task(
        id: 'tax',
        title: 'Pay tax',
        domain: 'Finance',
        context: 'Admin',
        code: '2.1.1',
        minutes: 15,
        cost: 1875,
      ),
    ]);

    expect(roots.map((node) => node.code), <String>['1', '2']);
    expect(roots.first.title, 'Work');
    expect(roots.first.children.single.code, '1.1');
    expect(roots.first.children.single.title, 'Focus');
    expect(roots.first.children.single.children.length, 2);
    expect(roots.first.workPackageCount, 2);
    expect(roots.first.estimateMinutes, 90);
    expect(roots.first.estimatedCostCents, 11250);
    expect(roots.first.children.single.children.first.task?.id, 'packet');
  });

  test('keeps deeply nested WBS codes as decomposition levels', () {
    final roots = buildTaskWbsTree(<WorkspaceTask>[
      _task(
        id: 'deep',
        title: 'Wire nested agent loop',
        domain: 'Agent',
        context: 'Runtime',
        code: '1.2.3.4.5.6',
        minutes: 45,
        cost: 5625,
      ),
    ]);

    var node = roots.single;
    for (final code in <String>[
      '1',
      '1.2',
      '1.2.3',
      '1.2.3.4',
      '1.2.3.4.5',
      '1.2.3.4.5.6',
    ]) {
      expect(node.code, code);
      if (node.code != '1.2.3.4.5.6') {
        node = node.children.single;
      }
    }
    expect(node.kind, TaskWbsTreeNodeKind.workPackage);
    expect(node.task?.id, 'deep');
  });
}

/// Builds one workspace task with WBS metadata.
WorkspaceTask _task({
  required String id,
  required String title,
  required String domain,
  required String context,
  required String code,
  required int minutes,
  required int cost,
}) {
  return WorkspaceTask(
    id: id,
    title: title,
    detail: '',
    done: false,
    description: '',
    status: 'open',
    priority: 'normal',
    estimateMinutes: minutes,
    context: context,
    domain: domain,
    active: true,
    workBreakdown: TaskWorkBreakdown(
      code: code,
      deliverable: title,
      estimatedCostCents: cost,
      costCurrency: 'CAD',
    ),
  );
}
