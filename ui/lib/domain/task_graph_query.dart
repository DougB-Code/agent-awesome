/// Provides canonical graph-query evaluation for the constellation surface.
library;

import 'models.dart';
import 'task_insight_index.dart';
import 'task_projection_adapters.dart';

/// TaskGraphQueryGroup identifies the best visual grouping for query results.
enum TaskGraphQueryGroup {
  /// Group by task metadata and context.
  metadata,

  /// Group by owning project or delivery stream.
  project,

  /// Group by responsible owner.
  owner,

  /// Group by lifecycle status.
  status,

  /// Group by task time horizon.
  time,
}

/// TaskGraphQueryExample stores one saved canonical query for the UI.
class TaskGraphQueryExample {
  /// Creates one saved query example.
  const TaskGraphQueryExample({
    required this.id,
    required this.label,
    required this.query,
  });

  /// Stable example id.
  final String id;

  /// Short UI label.
  final String label;

  /// Canonical graph query text.
  final String query;
}

/// Saved Constellation queries kept outside the core graph language.
const List<TaskGraphQueryExample>
taskGraphConstellationQueryExamples = <TaskGraphQueryExample>[
  TaskGraphQueryExample(
    id: 'open-work',
    label: 'Open Work',
    query:
        'FIND task WHERE status != "done" RETURN id, title, status, owner, project ORDER BY title ASC LIMIT 20',
  ),
  TaskGraphQueryExample(
    id: 'dependency-paths',
    label: 'Dependency Paths',
    query:
        'MATCH task -[depends_on*1..6]-> task WHERE from.status != "done" AND to.status != "done" RETURN from.title, path.depth, to.title, path.node_ids ORDER BY path.depth DESC LIMIT 10',
  ),
  TaskGraphQueryExample(
    id: 'high-risk',
    label: 'High Risk',
    query:
        'FIND task WHERE risk >= 0.6 RETURN id, title, owner, risk ORDER BY risk DESC LIMIT 10',
  ),
  TaskGraphQueryExample(
    id: 'direct-dependencies',
    label: 'Direct Dependencies',
    query:
        'MATCH task -[depends_on]-> task RETURN from.title, edge.type, to.title, edge.confidence LIMIT 20',
  ),
];

/// TaskGraphQueryPath stores one row-linked graph path.
class TaskGraphQueryPath {
  /// Creates one query path result.
  const TaskGraphQueryPath({
    required this.rowIndex,
    required this.nodeIds,
    required this.edgeIds,
  });

  /// Row index that produced this path.
  final int rowIndex;

  /// Ordered node ids in the path.
  final List<String> nodeIds;

  /// Ordered edge ids in the path.
  final List<String> edgeIds;

  /// Number of edges in the path.
  int get depth => edgeIds.length;
}

/// TaskGraphQueryResult stores the projection and rows for one graph query.
class TaskGraphQueryResult {
  /// Creates one evaluated graph query result.
  const TaskGraphQueryResult({
    required this.query,
    required this.projection,
    required this.summary,
    this.rows = const <Map<String, Object?>>[],
    this.paths = const <TaskGraphQueryPath>[],
    this.group = TaskGraphQueryGroup.metadata,
    this.expandResults = false,
    this.error = '',
  });

  /// Raw query text entered by the user.
  final String query;

  /// Constellation projection containing matching graph nodes and edges.
  final TaskConstellationProjection projection;

  /// Concise deterministic answer for the result set.
  final String summary;

  /// Result rows projected by RETURN fields.
  final List<Map<String, Object?>> rows;

  /// Row-linked graph paths for MATCH results.
  final List<TaskGraphQueryPath> paths;

  /// Preferred grouping dimension for displaying the result graph.
  final TaskGraphQueryGroup group;

  /// Whether the UI should reveal matching task nodes immediately.
  final bool expandResults;

  /// Parse or execution error, if any.
  final String error;

  /// Whether this query produced no visible nodes.
  bool get isEmpty => projection.nodes.isEmpty;

  /// Whether the query failed before graph projection.
  bool get hasError => error.isNotEmpty;
}

/// TaskGraphConstellationQuery evaluates canonical graph queries for tasks.
class TaskGraphConstellationQuery {
  const TaskGraphConstellationQuery._();

  /// Evaluates one canonical query against the task insight graph.
  static TaskGraphQueryResult run(
    TaskInsightIndex index,
    String query, {
    String selectedTaskId = '',
    DateTime? now,
  }) {
    final trimmed = query.trim();
    final base = TaskInsightProjectionAdapters.constellation(
      index,
      selectedTaskId: selectedTaskId,
    );
    if (trimmed.isEmpty) {
      return TaskGraphQueryResult(
        query: query,
        projection: base,
        summary:
            '${base.nodes.length} tasks and ${base.edges.length} relations.',
      );
    }
    try {
      final statement = _GraphQueryParser.parse(trimmed);
      final result = switch (statement.mode) {
        _GraphQueryMode.find => _executeFind(index, base, statement),
        _GraphQueryMode.match => _executeMatch(index, base, statement),
      };
      return result.copyWith(query: query);
    } on _GraphQueryException catch (error) {
      return TaskGraphQueryResult(
        query: query,
        projection: const TaskConstellationProjection(),
        summary: 'Query error: ${error.message}',
        error: error.message,
        expandResults: true,
      );
    }
  }
}

/// _GraphExecution stores mutable result pieces before creating a public result.
class _GraphExecution {
  /// Creates one internal execution result.
  const _GraphExecution({
    required this.nodes,
    required this.edges,
    required this.rows,
    required this.paths,
    required this.group,
  });

  /// Visible constellation nodes.
  final List<TaskConstellationNode> nodes;

  /// Visible constellation edges.
  final List<TaskConstellationEdge> edges;

  /// Projected query rows.
  final List<Map<String, Object?>> rows;

  /// Projected graph paths.
  final List<TaskGraphQueryPath> paths;

  /// Preferred anchor grouping.
  final TaskGraphQueryGroup group;
}

/// Adds a query value to an existing result.
extension on TaskGraphQueryResult {
  /// Returns this result with a replacement query string.
  TaskGraphQueryResult copyWith({required String query}) {
    return TaskGraphQueryResult(
      query: query,
      projection: projection,
      summary: summary,
      rows: rows,
      paths: paths,
      group: group,
      expandResults: expandResults,
      error: error,
    );
  }
}

/// Executes a FIND task statement over task nodes.
TaskGraphQueryResult _executeFind(
  TaskInsightIndex index,
  TaskConstellationProjection base,
  _GraphStatement statement,
) {
  if (statement.kind != 'task') {
    throw _GraphQueryException('FIND currently supports task nodes.');
  }
  var candidates = <TaskConstellationNode>[
    for (final node in base.nodes)
      if (_conditionsMatchNode(index, node, statement.where)) node,
  ];
  candidates = _orderedNodes(index, candidates, statement);
  candidates = candidates.take(statement.limit).toList();
  final visibleIds = candidates.map((node) => node.taskId).toSet();
  final edges = <TaskConstellationEdge>[
    for (final edge in base.edges)
      if (visibleIds.contains(edge.fromTaskId) &&
          visibleIds.contains(edge.toTaskId))
        edge,
  ];
  final rows = <Map<String, Object?>>[
    for (final node in candidates)
      _nodeRow(index, node, statement.returnFieldsOrDefault(_findReturnFields)),
  ];
  final execution = _GraphExecution(
    nodes: candidates,
    edges: edges,
    rows: rows,
    paths: const <TaskGraphQueryPath>[],
    group: _groupForFields(statement.allFields),
  );
  return _resultForExecution(statement, execution);
}

/// Executes a MATCH task relation statement over task edges.
TaskGraphQueryResult _executeMatch(
  TaskInsightIndex index,
  TaskConstellationProjection base,
  _GraphStatement statement,
) {
  if (statement.fromKind != 'task' || statement.toKind != 'task') {
    throw _GraphQueryException('MATCH currently supports task-to-task paths.');
  }
  final nodeById = <String, TaskConstellationNode>{
    for (final node in base.nodes) node.taskId: node,
  };
  final paths = _matchingPaths(index, nodeById, statement);
  final rows = <Map<String, Object?>>[];
  final publicPaths = <TaskGraphQueryPath>[];
  for (final path in paths.take(statement.limit)) {
    final row = _matchRow(
      index,
      path,
      statement.returnFieldsOrDefault(_matchReturnFields),
    );
    rows.add(row);
    publicPaths.add(
      TaskGraphQueryPath(
        rowIndex: rows.length - 1,
        nodeIds: path.nodeIds,
        edgeIds: path.edgeIds,
      ),
    );
  }
  final visibleIds = <String>{for (final path in publicPaths) ...path.nodeIds};
  final visibleEdgeIds = <String>{
    for (final path in publicPaths) ...path.edgeIds,
  };
  final queryEdges = <TaskConstellationEdge>[
    for (final edge in base.edges)
      if (visibleEdgeIds.contains(_constellationEdgeKey(edge)))
        _queryPathEdge(edge),
  ];
  final execution = _GraphExecution(
    nodes: <TaskConstellationNode>[
      for (final id in visibleIds)
        if (nodeById[id] != null) nodeById[id]!,
    ],
    edges: queryEdges,
    rows: rows,
    paths: publicPaths,
    group: _groupForFields(statement.allFields),
  );
  return _resultForExecution(statement, execution);
}

/// Creates the public result from an internal execution result.
TaskGraphQueryResult _resultForExecution(
  _GraphStatement statement,
  _GraphExecution execution,
) {
  return TaskGraphQueryResult(
    query: '',
    projection: TaskConstellationProjection(
      nodes: execution.nodes,
      edges: execution.edges,
    ),
    summary: _summaryFor(statement, execution),
    rows: execution.rows,
    paths: execution.paths,
    group: execution.group,
    expandResults: true,
  );
}

/// Builds a concise deterministic summary for a query result.
String _summaryFor(_GraphStatement statement, _GraphExecution execution) {
  if (execution.rows.isEmpty) {
    return '0 rows.';
  }
  if (statement.mode == _GraphQueryMode.match) {
    final depth = execution.paths.fold<int>(
      0,
      (current, path) => path.depth > current ? path.depth : current,
    );
    return '${execution.rows.length} rows, ${execution.paths.length} paths, max depth $depth.';
  }
  return '${execution.rows.length} rows, ${execution.nodes.length} tasks, ${execution.edges.length} relations.';
}

/// Returns all matching paths for one MATCH statement.
List<_TaskGraphPath> _matchingPaths(
  TaskInsightIndex index,
  Map<String, TaskConstellationNode> nodeById,
  _GraphStatement statement,
) {
  final output = <_TaskGraphPath>[];
  final outgoing = <String, List<TaskProjectionEdge>>{};
  for (final edge in index.edges) {
    if (edge.relationType == statement.relation) {
      outgoing
          .putIfAbsent(edge.fromTaskId, () => <TaskProjectionEdge>[])
          .add(edge);
    }
  }
  for (final root in nodeById.values) {
    _walkPaths(
      index: index,
      nodeById: nodeById,
      outgoing: outgoing,
      statement: statement,
      current: root.taskId,
      nodeIds: <String>[root.taskId],
      edgeIds: const <String>[],
      seen: <String>{root.taskId},
      output: output,
    );
  }
  if (statement.orderBy.isNotEmpty) {
    output.sort((left, right) {
      final comparison = _compareValues(
        _matchFieldValue(index, left, statement.orderBy),
        _matchFieldValue(index, right, statement.orderBy),
      );
      return statement.descending ? -comparison : comparison;
    });
  }
  return output;
}

/// Recursively walks bounded relation paths.
void _walkPaths({
  required TaskInsightIndex index,
  required Map<String, TaskConstellationNode> nodeById,
  required Map<String, List<TaskProjectionEdge>> outgoing,
  required _GraphStatement statement,
  required String current,
  required List<String> nodeIds,
  required List<String> edgeIds,
  required Set<String> seen,
  required List<_TaskGraphPath> output,
}) {
  if (edgeIds.length >= statement.maxDepth) {
    return;
  }
  for (final edge in outgoing[current] ?? const <TaskProjectionEdge>[]) {
    if (seen.contains(edge.toTaskId) || nodeById[edge.toTaskId] == null) {
      continue;
    }
    final nextNodeIds = <String>[...nodeIds, edge.toTaskId];
    final nextEdgeIds = <String>[...edgeIds, _projectionEdgeKey(edge)];
    final path = _TaskGraphPath(
      nodeIds: nextNodeIds,
      edgeIds: nextEdgeIds,
      edges: <TaskProjectionEdge>[..._edgesForPath(index, edgeIds), edge],
    );
    if (nextEdgeIds.length >= statement.minDepth &&
        _conditionsMatchPath(index, path, statement.where)) {
      output.add(path);
    }
    _walkPaths(
      index: index,
      nodeById: nodeById,
      outgoing: outgoing,
      statement: statement,
      current: edge.toTaskId,
      nodeIds: nextNodeIds,
      edgeIds: nextEdgeIds,
      seen: <String>{...seen, edge.toTaskId},
      output: output,
    );
  }
}

/// Returns graph edges for stored path edge ids.
List<TaskProjectionEdge> _edgesForPath(
  TaskInsightIndex index,
  List<String> edgeIds,
) {
  return <TaskProjectionEdge>[
    for (final id in edgeIds)
      for (final edge in index.edges)
        if (_projectionEdgeKey(edge) == id) edge,
  ];
}

/// Returns whether all node conditions match.
bool _conditionsMatchNode(
  TaskInsightIndex index,
  TaskConstellationNode node,
  List<_GraphCondition> conditions,
) {
  for (final condition in conditions) {
    final value = _nodeFieldValue(
      index,
      node,
      _unprefixedField(condition.field),
    );
    if (!_conditionMatches(value, condition)) {
      return false;
    }
  }
  return true;
}

/// Returns whether all path conditions match.
bool _conditionsMatchPath(
  TaskInsightIndex index,
  _TaskGraphPath path,
  List<_GraphCondition> conditions,
) {
  for (final condition in conditions) {
    final value = _matchFieldValue(index, path, condition.field);
    if (!_conditionMatches(value, condition)) {
      return false;
    }
  }
  return true;
}

/// Returns a projected row for one task node.
Map<String, Object?> _nodeRow(
  TaskInsightIndex index,
  TaskConstellationNode node,
  List<String> fields,
) {
  return <String, Object?>{
    for (final field in fields)
      field: _nodeFieldValue(index, node, _unprefixedField(field)),
  };
}

/// Returns a projected row for one match path.
Map<String, Object?> _matchRow(
  TaskInsightIndex index,
  _TaskGraphPath path,
  List<String> fields,
) {
  return <String, Object?>{
    for (final field in fields) field: _matchFieldValue(index, path, field),
  };
}

/// Returns the value for one MATCH field.
Object? _matchFieldValue(
  TaskInsightIndex index,
  _TaskGraphPath path,
  String field,
) {
  if (field.isEmpty) {
    return '';
  }
  if (field.startsWith('from.')) {
    return _nodeFieldValue(
      index,
      _nodeForPath(index, path.nodeIds.first),
      field.substring(5),
    );
  }
  if (field.startsWith('to.')) {
    return _nodeFieldValue(
      index,
      _nodeForPath(index, path.nodeIds.last),
      field.substring(3),
    );
  }
  if (field.startsWith('edge.')) {
    return _edgeFieldValue(path.edges.last, field.substring(5));
  }
  if (field.startsWith('path.')) {
    return _pathFieldValue(path, field.substring(5));
  }
  return '';
}

/// Returns one path node as a constellation node.
TaskConstellationNode _nodeForPath(TaskInsightIndex index, String taskId) {
  final task = index.projectionTasksById[taskId];
  return TaskConstellationNode(
    taskId: taskId,
    title: index.titleForTaskId(taskId),
    status: task?.status ?? index.workspaceTasksById[taskId]?.status ?? '',
    owner: _ownerFor(index, taskId),
    project: _projectFor(index, taskId),
  );
}

/// Returns the value for one task field.
Object? _nodeFieldValue(
  TaskInsightIndex index,
  TaskConstellationNode node,
  String field,
) {
  final taskId = node.taskId;
  final workspace = index.workspaceTasksById[taskId];
  final projection = index.projectionTasksById[taskId];
  final scores = index.scoresFor(taskId);
  return switch (field) {
    'id' || 'node_id' => node.taskId,
    'kind' => 'task',
    'title' => node.title,
    'status' => node.status,
    'priority' => workspace?.priority ?? projection?.priority ?? '',
    'owner' ||
    'person' => node.owner.isNotEmpty ? node.owner : _ownerFor(index, taskId),
    'project' =>
      node.project.isNotEmpty ? node.project : _projectFor(index, taskId),
    'context' => _contextFor(index, taskId),
    'view' || 'domain' => _viewFor(index, taskId),
    'source' =>
      workspace?.sourceLabel ?? workspace?.source ?? projection?.source ?? '',
    'due_at' || 'due' => workspace?.dueAt ?? projection?.dueAt,
    'scheduled_at' ||
    'scheduled' => workspace?.scheduledAt ?? projection?.scheduledAt,
    'estimate_minutes' || 'estimate' =>
      workspace?.estimateMinutes ?? projection?.estimateMinutes ?? 0,
    'risk' => scores?.risk ?? workspace?.risk ?? projection?.scores.risk ?? 0,
    'pressure' || 'urgency' =>
      scores?.pressure ??
          workspace?.urgency ??
          projection?.scores.pressure ??
          0,
    'reward' || 'value' =>
      scores?.reward ?? workspace?.value ?? projection?.scores.reward ?? 0,
    'effort' =>
      scores?.humanEffort ??
          workspace?.effort ??
          projection?.scores.humanEffort ??
          0,
    'confidence' =>
      scores?.confidence ??
          workspace?.confidence ??
          projection?.confidence ??
          0,
    'downstream_count' ||
    'downstream' => index.downstreamTasksFor(taskId).length,
    'blocker_count' || 'upstream' => index.blockersFor(taskId).length,
    _ => '',
  };
}

/// Returns the value for one edge field.
Object? _edgeFieldValue(TaskProjectionEdge edge, String field) {
  return switch (field) {
    'id' => _projectionEdgeKey(edge),
    'type' || 'relation_type' => edge.relationType,
    'from_id' || 'from_node_id' => edge.fromTaskId,
    'to_id' || 'to_node_id' => edge.toTaskId,
    'confidence' => edge.confidence,
    'source' => edge.source,
    'source_kind' => edge.sourceKind,
    'scope' => edge.scope,
    'sensitivity' => edge.sensitivity,
    'evidence_ids' => edge.evidenceIds,
    'actor' => edge.actor,
    'created_at' => edge.createdAt,
    'updated_at' => edge.updatedAt,
    'confirmed_at' => edge.confirmedAt,
    'dismissed_at' => edge.dismissedAt,
    _ => '',
  };
}

/// Returns the value for one path field.
Object? _pathFieldValue(_TaskGraphPath path, String field) {
  return switch (field) {
    'depth' => path.edgeIds.length,
    'node_ids' => path.nodeIds,
    'edge_ids' => path.edgeIds,
    _ => '',
  };
}

/// Returns whether a condition matches a resolved value.
bool _conditionMatches(Object? value, _GraphCondition condition) {
  final comparison = _compareLiteral(value, condition.value);
  return switch (condition.operator) {
    '=' => comparison == 0,
    '!=' => comparison != 0,
    '<' => comparison < 0,
    '<=' => comparison <= 0,
    '>' => comparison > 0,
    '>=' => comparison >= 0,
    _ => false,
  };
}

/// Compares a typed value with a query literal.
int _compareLiteral(Object? value, String literal) {
  if (value is num) {
    final right = num.tryParse(literal);
    if (right != null) {
      return value.compareTo(right);
    }
  }
  if (value is DateTime) {
    final right = DateTime.tryParse(literal);
    if (right != null) {
      return value.compareTo(right);
    }
  }
  final leftText = _valueText(value).toLowerCase();
  final rightText = literal.toLowerCase();
  if (leftText == rightText) {
    return 0;
  }
  if (leftText.contains(rightText)) {
    return 0;
  }
  return leftText.compareTo(rightText);
}

/// Orders visible nodes using one optional ORDER BY field.
List<TaskConstellationNode> _orderedNodes(
  TaskInsightIndex index,
  List<TaskConstellationNode> nodes,
  _GraphStatement statement,
) {
  if (statement.orderBy.isEmpty) {
    return nodes;
  }
  return <TaskConstellationNode>[...nodes]..sort((left, right) {
    final comparison = _compareValues(
      _nodeFieldValue(index, left, _unprefixedField(statement.orderBy)),
      _nodeFieldValue(index, right, _unprefixedField(statement.orderBy)),
    );
    return statement.descending ? -comparison : comparison;
  });
}

/// Compares two projected values.
int _compareValues(Object? left, Object? right) {
  if (left is num && right is num) {
    return left.compareTo(right);
  }
  if (left is DateTime && right is DateTime) {
    return left.compareTo(right);
  }
  return _valueText(left).compareTo(_valueText(right));
}

/// Converts a projected value to readable text.
String _valueText(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is Iterable) {
    return value.map(_valueText).join(',');
  }
  return value.toString();
}

/// Returns a query-highlighted copy of an edge.
TaskConstellationEdge _queryPathEdge(TaskConstellationEdge edge) {
  return TaskConstellationEdge(
    id: edge.id,
    fromTaskId: edge.fromTaskId,
    toTaskId: edge.toTaskId,
    relationType: edge.relationType,
    confidence: edge.confidence,
    source: 'query_path',
    factSource: edge.factSource.isEmpty ? edge.source : edge.factSource,
    sourceKind: edge.sourceKind,
    scope: edge.scope,
    sensitivity: edge.sensitivity,
    explanation: edge.explanation,
    evidenceIds: edge.evidenceIds,
    actor: edge.actor,
    createdAt: edge.createdAt,
    updatedAt: edge.updatedAt,
    confirmedAt: edge.confirmedAt,
    dismissedAt: edge.dismissedAt,
  );
}

/// Returns an edge id for path metadata.
String _projectionEdgeKey(TaskProjectionEdge edge) {
  return '${edge.fromTaskId}:${edge.relationType}:${edge.toTaskId}';
}

/// Returns an edge key for constellation edge metadata.
String _constellationEdgeKey(TaskConstellationEdge edge) {
  return '${edge.fromTaskId}:${edge.relationType}:${edge.toTaskId}';
}

/// Returns a canonical field without a node prefix.
String _unprefixedField(String field) {
  if (field.startsWith('node.')) {
    return field.substring(5);
  }
  if (field.startsWith('from.') || field.startsWith('to.')) {
    return field.substring(field.indexOf('.') + 1);
  }
  return field;
}

/// Returns the owner label for one task.
String _ownerFor(TaskInsightIndex index, String taskId) {
  return index.facetLabelForTask(taskId, 'person').isNotEmpty
      ? index.facetLabelForTask(taskId, 'person')
      : index.workspaceTasksById[taskId]?.owner ??
            index.projectionTasksById[taskId]?.owner ??
            '';
}

/// Returns the project label for one task.
String _projectFor(TaskInsightIndex index, String taskId) {
  return index.facetLabelForTask(taskId, 'project').isNotEmpty
      ? index.facetLabelForTask(taskId, 'project')
      : index.workspaceTasksById[taskId]?.project ??
            index.projectionTasksById[taskId]?.project ??
            '';
}

/// Returns the context label for one task.
String _contextFor(TaskInsightIndex index, String taskId) {
  return index.facetLabelForTask(taskId, 'context').isNotEmpty
      ? index.facetLabelForTask(taskId, 'context')
      : index.workspaceTasksById[taskId]?.context ??
            index.projectionTasksById[taskId]?.context ??
            '';
}

/// Returns the view label for one task.
String _viewFor(TaskInsightIndex index, String taskId) {
  return index.facetLabelForTask(taskId, 'view').isNotEmpty
      ? index.facetLabelForTask(taskId, 'view')
      : index.workspaceTasksById[taskId]?.domain ??
            index.projectionTasksById[taskId]?.domain ??
            '';
}

/// Returns the preferred visual group for fields.
TaskGraphQueryGroup _groupForFields(Iterable<String> fields) {
  final joined = fields.join(' ');
  if (joined.contains('project')) {
    return TaskGraphQueryGroup.project;
  }
  if (joined.contains('owner') || joined.contains('person')) {
    return TaskGraphQueryGroup.owner;
  }
  if (joined.contains('status')) {
    return TaskGraphQueryGroup.status;
  }
  if (joined.contains('due') || joined.contains('scheduled')) {
    return TaskGraphQueryGroup.time;
  }
  return TaskGraphQueryGroup.metadata;
}

const List<String> _findReturnFields = <String>['id', 'title', 'status'];
const List<String> _matchReturnFields = <String>[
  'from.title',
  'edge.type',
  'to.title',
  'path.depth',
];

/// _TaskGraphPath stores one internal traversal result.
class _TaskGraphPath {
  /// Creates one internal task graph path.
  const _TaskGraphPath({
    required this.nodeIds,
    required this.edgeIds,
    required this.edges,
  });

  /// Ordered task ids.
  final List<String> nodeIds;

  /// Ordered relation ids.
  final List<String> edgeIds;

  /// Ordered relation records.
  final List<TaskProjectionEdge> edges;
}

/// _GraphQueryMode describes supported statement families.
enum _GraphQueryMode {
  /// FIND scans task nodes.
  find,

  /// MATCH traverses task relation edges.
  match,
}

/// _GraphStatement stores one parsed canonical graph query.
class _GraphStatement {
  /// Creates one parsed graph statement.
  const _GraphStatement({
    required this.mode,
    this.kind = '',
    this.fromKind = '',
    this.toKind = '',
    this.relation = '',
    this.minDepth = 1,
    this.maxDepth = 1,
    this.where = const <_GraphCondition>[],
    this.returnFields = const <String>[],
    this.orderBy = '',
    this.descending = false,
    this.limit = 20,
  });

  /// Statement family.
  final _GraphQueryMode mode;

  /// FIND node kind.
  final String kind;

  /// MATCH source node kind.
  final String fromKind;

  /// MATCH target node kind.
  final String toKind;

  /// MATCH relation type.
  final String relation;

  /// Minimum traversal depth.
  final int minDepth;

  /// Maximum traversal depth.
  final int maxDepth;

  /// WHERE conditions.
  final List<_GraphCondition> where;

  /// RETURN fields.
  final List<String> returnFields;

  /// ORDER BY field.
  final String orderBy;

  /// Whether ORDER BY is descending.
  final bool descending;

  /// Row limit.
  final int limit;

  /// Returns explicit or default return fields.
  List<String> returnFieldsOrDefault(List<String> defaults) {
    return returnFields.isEmpty ? defaults : returnFields;
  }

  /// Returns all fields used by the statement.
  Iterable<String> get allFields sync* {
    yield* returnFields;
    yield orderBy;
    for (final condition in where) {
      yield condition.field;
    }
  }
}

/// _GraphCondition stores one WHERE predicate.
class _GraphCondition {
  /// Creates one parsed condition.
  const _GraphCondition({
    required this.field,
    required this.operator,
    required this.value,
  });

  /// Field path.
  final String field;

  /// Comparison operator.
  final String operator;

  /// Literal value.
  final String value;
}

/// _GraphQueryParser parses the Constellation query subset.
class _GraphQueryParser {
  _GraphQueryParser._(this.tokens);

  /// Parses a canonical graph query.
  static _GraphStatement parse(String input) {
    final parser = _GraphQueryParser._(_lex(input));
    return parser._statement();
  }

  final List<_GraphToken> tokens;
  int _pos = 0;

  /// Parses one statement.
  _GraphStatement _statement() {
    if (_matchKeyword('FIND')) {
      return _find();
    }
    if (_matchKeyword('MATCH')) {
      return _match();
    }
    throw _GraphQueryException('Expected FIND or MATCH.');
  }

  /// Parses a FIND statement.
  _GraphStatement _find() {
    final kind = _expectIdentifier('node kind').toLowerCase();
    var statement = _GraphStatement(mode: _GraphQueryMode.find, kind: kind);
    statement = _trailingClauses(statement);
    _expectEnd();
    return statement;
  }

  /// Parses a MATCH statement.
  _GraphStatement _match() {
    final fromKind = _expectIdentifier('from node kind').toLowerCase();
    _expect(_GraphTokenType.dash, '-');
    _expect(_GraphTokenType.leftBracket, '[');
    final relation = _expectIdentifier('relation type').toLowerCase();
    final depth = _depth();
    _expect(_GraphTokenType.rightBracket, ']');
    _expect(_GraphTokenType.arrow, '->');
    final toKind = _expectIdentifier('to node kind').toLowerCase();
    var statement = _GraphStatement(
      mode: _GraphQueryMode.match,
      fromKind: fromKind,
      relation: relation,
      toKind: toKind,
      minDepth: depth.min,
      maxDepth: depth.max,
    );
    statement = _trailingClauses(statement);
    _expectEnd();
    return statement;
  }

  /// Parses optional traversal depth.
  ({int min, int max}) _depth() {
    if (!_matchToken(_GraphTokenType.star)) {
      return (min: 1, max: 1);
    }
    var min = 1;
    var max = 6;
    if (_current.type == _GraphTokenType.number) {
      min = int.parse(_consume().value);
      max = min;
    }
    if (_matchToken(_GraphTokenType.range)) {
      max = int.parse(_expect(_GraphTokenType.number, 'maximum depth').value);
    }
    if (min <= 0 || max < min || max > 12) {
      throw _GraphQueryException('Traversal depth must be between 1 and 12.');
    }
    return (min: min, max: max);
  }

  /// Parses WHERE, RETURN, ORDER BY, and LIMIT clauses.
  _GraphStatement _trailingClauses(_GraphStatement statement) {
    var where = statement.where;
    var returnFields = statement.returnFields;
    var orderBy = statement.orderBy;
    var descending = statement.descending;
    var limit = statement.limit;
    if (_matchKeyword('WHERE')) {
      where = _conditions();
    }
    if (_matchKeyword('RETURN')) {
      returnFields = _fieldList();
    }
    if (_matchKeyword('ORDER')) {
      _expectKeyword('BY');
      orderBy = _expectIdentifier('order field').toLowerCase();
      if (_matchKeyword('DESC')) {
        descending = true;
      } else {
        _matchKeyword('ASC');
      }
    }
    if (_matchKeyword('LIMIT')) {
      limit = int.parse(_expect(_GraphTokenType.number, 'limit').value);
      if (limit <= 0 || limit > 100) {
        throw _GraphQueryException('LIMIT must be between 1 and 100.');
      }
    }
    return _GraphStatement(
      mode: statement.mode,
      kind: statement.kind,
      fromKind: statement.fromKind,
      toKind: statement.toKind,
      relation: statement.relation,
      minDepth: statement.minDepth,
      maxDepth: statement.maxDepth,
      where: where,
      returnFields: returnFields,
      orderBy: orderBy,
      descending: descending,
      limit: limit,
    );
  }

  /// Parses conditions joined by AND.
  List<_GraphCondition> _conditions() {
    final conditions = <_GraphCondition>[];
    while (true) {
      final field = _expectIdentifier('where field').toLowerCase();
      final operator = _operator();
      final value = _literal();
      conditions.add(
        _GraphCondition(field: field, operator: operator, value: value),
      );
      if (!_matchKeyword('AND')) {
        break;
      }
    }
    return conditions;
  }

  /// Parses one comparison operator.
  String _operator() {
    final token = _consume();
    return switch (token.type) {
      _GraphTokenType.equal => '=',
      _GraphTokenType.notEqual => '!=',
      _GraphTokenType.less => '<',
      _GraphTokenType.lessEqual => '<=',
      _GraphTokenType.greater => '>',
      _GraphTokenType.greaterEqual => '>=',
      _ => throw _GraphQueryException('Expected comparison operator.'),
    };
  }

  /// Parses a comma-separated field list.
  List<String> _fieldList() {
    final fields = <String>[];
    while (true) {
      fields.add(_expectIdentifier('return field').toLowerCase());
      if (!_matchToken(_GraphTokenType.comma)) {
        break;
      }
    }
    return fields;
  }

  /// Parses one literal value.
  String _literal() {
    final token = _consume();
    if (token.type == _GraphTokenType.string ||
        token.type == _GraphTokenType.number ||
        token.type == _GraphTokenType.identifier) {
      return token.value;
    }
    throw _GraphQueryException('Expected literal value.');
  }

  /// Expects one keyword.
  void _expectKeyword(String keyword) {
    if (!_matchKeyword(keyword)) {
      throw _GraphQueryException('Expected $keyword.');
    }
  }

  /// Expects one identifier.
  String _expectIdentifier(String label) {
    return _expect(_GraphTokenType.identifier, label).value;
  }

  /// Expects one token type.
  _GraphToken _expect(_GraphTokenType type, String label) {
    if (_current.type != type) {
      throw _GraphQueryException('Expected $label.');
    }
    return _consume();
  }

  /// Expects the end of input.
  void _expectEnd() {
    if (_current.type != _GraphTokenType.eof) {
      throw _GraphQueryException('Unexpected token "${_current.value}".');
    }
  }

  /// Consumes a keyword when present.
  bool _matchKeyword(String keyword) {
    if (_current.type == _GraphTokenType.identifier &&
        _current.value.toUpperCase() == keyword) {
      _pos++;
      return true;
    }
    return false;
  }

  /// Consumes a token when present.
  bool _matchToken(_GraphTokenType type) {
    if (_current.type == type) {
      _pos++;
      return true;
    }
    return false;
  }

  /// Consumes and returns the current token.
  _GraphToken _consume() {
    final token = _current;
    _pos++;
    return token;
  }

  /// Current token.
  _GraphToken get _current => tokens[_pos];
}

/// _GraphQueryException reports a parse or execution issue.
class _GraphQueryException implements Exception {
  /// Creates one graph query exception.
  const _GraphQueryException(this.message);

  /// Display message.
  final String message;
}

/// _GraphTokenType classifies query tokens.
enum _GraphTokenType {
  /// End of input.
  eof,

  /// Identifier, keyword, or field path.
  identifier,

  /// Quoted string literal.
  string,

  /// Number literal.
  number,

  /// Comma separator.
  comma,

  /// Equality operator.
  equal,

  /// Inequality operator.
  notEqual,

  /// Less-than operator.
  less,

  /// Less-than-or-equal operator.
  lessEqual,

  /// Greater-than operator.
  greater,

  /// Greater-than-or-equal operator.
  greaterEqual,

  /// Left bracket.
  leftBracket,

  /// Right bracket.
  rightBracket,

  /// Dash.
  dash,

  /// Arrow.
  arrow,

  /// Star.
  star,

  /// Range marker.
  range,
}

/// _GraphToken stores one lexical token.
class _GraphToken {
  /// Creates one query token.
  const _GraphToken(this.type, [this.value = '']);

  /// Token type.
  final _GraphTokenType type;

  /// Token text.
  final String value;
}

/// Lexes a graph query string into tokens.
List<_GraphToken> _lex(String input) {
  final tokens = <_GraphToken>[];
  var index = 0;
  while (index < input.length) {
    final char = input[index];
    if (char.trim().isEmpty) {
      index++;
      continue;
    }
    if (char == ',') {
      tokens.add(const _GraphToken(_GraphTokenType.comma, ','));
      index++;
    } else if (char == '=') {
      tokens.add(const _GraphToken(_GraphTokenType.equal, '='));
      index++;
    } else if (char == '!' && _nextIs(input, index, '=')) {
      tokens.add(const _GraphToken(_GraphTokenType.notEqual, '!='));
      index += 2;
    } else if (char == '<' && _nextIs(input, index, '=')) {
      tokens.add(const _GraphToken(_GraphTokenType.lessEqual, '<='));
      index += 2;
    } else if (char == '<') {
      tokens.add(const _GraphToken(_GraphTokenType.less, '<'));
      index++;
    } else if (char == '>' && _nextIs(input, index, '=')) {
      tokens.add(const _GraphToken(_GraphTokenType.greaterEqual, '>='));
      index += 2;
    } else if (char == '>') {
      tokens.add(const _GraphToken(_GraphTokenType.greater, '>'));
      index++;
    } else if (char == '.' && _nextIs(input, index, '.')) {
      tokens.add(const _GraphToken(_GraphTokenType.range, '..'));
      index += 2;
    } else if (char == '[') {
      tokens.add(const _GraphToken(_GraphTokenType.leftBracket, '['));
      index++;
    } else if (char == ']') {
      tokens.add(const _GraphToken(_GraphTokenType.rightBracket, ']'));
      index++;
    } else if (char == '-' && _nextIs(input, index, '>')) {
      tokens.add(const _GraphToken(_GraphTokenType.arrow, '->'));
      index += 2;
    } else if (char == '-') {
      tokens.add(const _GraphToken(_GraphTokenType.dash, '-'));
      index++;
    } else if (char == '*') {
      tokens.add(const _GraphToken(_GraphTokenType.star, '*'));
      index++;
    } else if (char == '"') {
      final result = _quotedString(input, index);
      tokens.add(_GraphToken(_GraphTokenType.string, result.value));
      index = result.nextIndex;
    } else if (_isNumberStart(char)) {
      final result = _number(input, index);
      tokens.add(_GraphToken(_GraphTokenType.number, result.value));
      index = result.nextIndex;
    } else if (_isIdentifierRune(char)) {
      final result = _identifier(input, index);
      tokens.add(_GraphToken(_GraphTokenType.identifier, result.value));
      index = result.nextIndex;
    } else {
      throw _GraphQueryException('Unexpected character "$char".');
    }
  }
  tokens.add(const _GraphToken(_GraphTokenType.eof));
  return tokens;
}

/// Returns whether the next input character matches.
bool _nextIs(String input, int index, String value) {
  return index + 1 < input.length && input[index + 1] == value;
}

/// Reads one quoted string literal.
({String value, int nextIndex}) _quotedString(String input, int start) {
  final buffer = StringBuffer();
  var index = start + 1;
  while (index < input.length) {
    final char = input[index++];
    if (char == '"') {
      return (value: buffer.toString(), nextIndex: index);
    }
    if (char == r'\' && index < input.length) {
      buffer.write(input[index++]);
    } else {
      buffer.write(char);
    }
  }
  throw const _GraphQueryException('Unterminated string literal.');
}

/// Reads one number literal.
({String value, int nextIndex}) _number(String input, int start) {
  var index = start;
  while (index < input.length &&
      (RegExp(r'[0-9]').hasMatch(input[index]) ||
          (input[index] == '.' && !_nextIs(input, index, '.')))) {
    index++;
  }
  return (value: input.substring(start, index), nextIndex: index);
}

/// Reads one identifier.
({String value, int nextIndex}) _identifier(String input, int start) {
  var index = start;
  while (index < input.length && _isIdentifierRune(input[index])) {
    index++;
  }
  return (value: input.substring(start, index), nextIndex: index);
}

/// Returns whether a character begins a number.
bool _isNumberStart(String char) {
  return RegExp(r'[0-9]').hasMatch(char);
}

/// Returns whether a character can appear in an identifier.
bool _isIdentifierRune(String char) {
  return RegExp(r'[A-Za-z0-9_.-]').hasMatch(char);
}
