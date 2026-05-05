/// Builds a hierarchical work-breakdown tree from task WBS metadata.
library;

import 'models.dart';

/// TaskWbsTreeNodeKind identifies the role of one WBS tree node.
enum TaskWbsTreeNodeKind {
  /// First-level project or domain bucket.
  root,

  /// Intermediate decomposition bucket.
  bucket,

  /// Leaf work package backed by one task.
  workPackage,
}

/// TaskWbsTreeNode stores one immutable WBS decomposition node.
class TaskWbsTreeNode {
  /// Creates one WBS tree node.
  const TaskWbsTreeNode({
    required this.code,
    required this.title,
    required this.kind,
    this.task,
    this.children = const <TaskWbsTreeNode>[],
  });

  /// WBS code prefix represented by this node.
  final String code;

  /// Display label for the bucket or work package.
  final String title;

  /// Node role in the decomposition tree.
  final TaskWbsTreeNodeKind kind;

  /// Backing task when this node is a work package.
  final WorkspaceTask? task;

  /// Child buckets or work packages.
  final List<TaskWbsTreeNode> children;

  /// Whether this node is backed by a concrete task.
  bool get isWorkPackage => task != null;

  /// Number of leaf work packages contained by this node.
  int get workPackageCount {
    if (isWorkPackage) {
      return 1;
    }
    return children.fold<int>(
      0,
      (total, child) => total + child.workPackageCount,
    );
  }

  /// Total planned minutes contained by this node.
  int get estimateMinutes {
    final packageTask = task;
    if (packageTask != null) {
      return packageTask.estimateMinutes;
    }
    return children.fold<int>(
      0,
      (total, child) => total + child.estimateMinutes,
    );
  }

  /// Total estimated minor-unit cost contained by this node.
  int get estimatedCostCents {
    final packageTask = task;
    if (packageTask != null) {
      return packageTask.workBreakdown.estimatedCostCents;
    }
    return children.fold<int>(
      0,
      (total, child) => total + child.estimatedCostCents,
    );
  }

  /// Shared currency for this node, or blank when children differ.
  String get costCurrency {
    final currencies = workPackages
        .map((task) => task.workBreakdown.costCurrency.trim())
        .where((currency) => currency.isNotEmpty)
        .toSet();
    return currencies.length == 1 ? currencies.single : '';
  }

  /// Leaf tasks contained by this node in tree order.
  List<WorkspaceTask> get workPackages {
    final packageTask = task;
    if (packageTask != null) {
      return <WorkspaceTask>[packageTask];
    }
    return <WorkspaceTask>[for (final child in children) ...child.workPackages];
  }
}

/// Builds a WBS tree from task work-breakdown codes.
List<TaskWbsTreeNode> buildTaskWbsTree(List<WorkspaceTask> tasks) {
  final roots = <String, _MutableTaskWbsNode>{};
  final sorted =
      tasks.where((task) => _taskHasWbsContent(task.workBreakdown)).toList()
        ..sort(compareWorkspaceTasksByWbs);
  for (final task in sorted) {
    _insertTaskWbsNode(roots, task);
  }
  return _sortedFrozenNodes(roots.values);
}

/// Compares workspace tasks by WBS code and title.
int compareWorkspaceTasksByWbs(WorkspaceTask left, WorkspaceTask right) {
  final leftCode = left.workBreakdown.code.trim();
  final rightCode = right.workBreakdown.code.trim();
  if (leftCode.isNotEmpty && rightCode.isNotEmpty) {
    final codeOrder = compareTaskWbsCodes(leftCode, rightCode);
    if (codeOrder != 0) {
      return codeOrder;
    }
  } else if (leftCode.isNotEmpty) {
    return -1;
  } else if (rightCode.isNotEmpty) {
    return 1;
  }
  return left.title.compareTo(right.title);
}

/// Compares dotted WBS codes numerically where possible.
int compareTaskWbsCodes(String left, String right) {
  final leftParts = _wbsCodeParts(left);
  final rightParts = _wbsCodeParts(right);
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index++) {
    final leftPart = index < leftParts.length ? leftParts[index] : '';
    final rightPart = index < rightParts.length ? rightParts[index] : '';
    final leftNumber = int.tryParse(leftPart);
    final rightNumber = int.tryParse(rightPart);
    final order = leftNumber != null && rightNumber != null
        ? leftNumber.compareTo(rightNumber)
        : leftPart.compareTo(rightPart);
    if (order != 0) {
      return order;
    }
  }
  return left.compareTo(right);
}

/// Inserts one task into the mutable WBS tree.
void _insertTaskWbsNode(
  Map<String, _MutableTaskWbsNode> roots,
  WorkspaceTask task,
) {
  final parts = _taskWbsParts(task);
  final rootCode = parts.first;
  var node = roots.putIfAbsent(
    rootCode,
    () => _MutableTaskWbsNode(
      code: rootCode,
      title: _rootTitle(task, rootCode),
      kind: TaskWbsTreeNodeKind.root,
    ),
  );
  for (var index = 1; index < parts.length; index++) {
    final prefix = parts.take(index + 1).join('.');
    final isLeaf = index == parts.length - 1;
    node = node.children.putIfAbsent(
      prefix,
      () => _MutableTaskWbsNode(
        code: prefix,
        title: isLeaf ? task.title : _bucketTitle(task, prefix),
        kind: isLeaf
            ? TaskWbsTreeNodeKind.workPackage
            : TaskWbsTreeNodeKind.bucket,
      ),
    );
  }
  node.title = task.title;
  node.kind = TaskWbsTreeNodeKind.workPackage;
  node.task = task;
}

/// Returns WBS parts for a task, including an uncoded fallback branch.
List<String> _taskWbsParts(WorkspaceTask task) {
  final parts = _wbsCodeParts(task.workBreakdown.code);
  if (parts.length >= 2) {
    return parts;
  }
  if (parts.length == 1) {
    return <String>[parts.first, '${parts.first}.${_taskSegment(task)}'];
  }
  return <String>['uncoded', 'uncoded.${_taskSegment(task)}'];
}

/// Splits one dotted WBS code into non-empty parts.
List<String> _wbsCodeParts(String code) {
  return code
      .split('.')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}

/// Returns a stable fallback WBS segment for uncoded tasks.
String _taskSegment(WorkspaceTask task) {
  final id = task.id.trim();
  if (id.isNotEmpty) {
    return id.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
  }
  return task.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
}

/// Returns the root bucket title for a task.
String _rootTitle(WorkspaceTask task, String code) {
  final domain = task.domain.trim();
  if (domain.isNotEmpty) {
    return domain;
  }
  if (code == 'uncoded') {
    return 'Uncoded work';
  }
  return 'WBS $code';
}

/// Returns an intermediate bucket title for a task.
String _bucketTitle(WorkspaceTask task, String code) {
  for (final value in <String>[
    task.context,
    task.sourceLabel,
    task.source,
    task.domain,
  ]) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return 'Work package $code';
}

/// Reports whether WBS metadata has any visible content.
bool _taskHasWbsContent(TaskWorkBreakdown workBreakdown) {
  return workBreakdown.code.trim().isNotEmpty ||
      workBreakdown.deliverable.trim().isNotEmpty ||
      workBreakdown.startCriteria.isNotEmpty ||
      workBreakdown.acceptanceCriteria.isNotEmpty ||
      workBreakdown.requirementRefs.isNotEmpty ||
      workBreakdown.rubricRefs.isNotEmpty ||
      workBreakdown.resources.isNotEmpty ||
      workBreakdown.estimatedCostCents > 0 ||
      workBreakdown.costCurrency.trim().isNotEmpty;
}

/// Freezes mutable nodes in WBS code order.
List<TaskWbsTreeNode> _sortedFrozenNodes(Iterable<_MutableTaskWbsNode> nodes) {
  final frozen = nodes.map((node) => node.freeze()).toList()
    ..sort((left, right) => compareTaskWbsCodes(left.code, right.code));
  return List<TaskWbsTreeNode>.unmodifiable(frozen);
}

/// _MutableTaskWbsNode accumulates tree children before freezing.
class _MutableTaskWbsNode {
  /// Creates a mutable WBS tree node.
  _MutableTaskWbsNode({
    required this.code,
    required this.title,
    required this.kind,
  });

  /// WBS code represented by this node.
  final String code;

  /// Mutable display label.
  String title;

  /// Mutable node role.
  TaskWbsTreeNodeKind kind;

  /// Optional backing task.
  WorkspaceTask? task;

  /// Child nodes keyed by WBS code.
  final Map<String, _MutableTaskWbsNode> children =
      <String, _MutableTaskWbsNode>{};

  /// Converts this mutable node into an immutable node.
  TaskWbsTreeNode freeze() {
    return TaskWbsTreeNode(
      code: code,
      title: title,
      kind: kind,
      task: task,
      children: _sortedFrozenNodes(children.values),
    );
  }
}
