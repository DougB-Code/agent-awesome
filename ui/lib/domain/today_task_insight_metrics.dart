/// Aligns Today top metrics with deterministic backlog insight predicates.
library;

import 'executive_summary.dart';
import 'task_insight_index.dart';
import 'task_insight_query.dart';

/// Returns a Today projection whose top cards use local task insight counts.
ExecutiveSummaryProjection alignTodayProjectionWithTaskInsights({
  required ExecutiveSummaryProjection projection,
  required TaskInsightIndex index,
}) {
  if (!_hasIndexedTasks(index)) {
    return projection;
  }
  final existingMetrics = <String, SummaryMetric>{
    for (final metric in projection.metrics) metric.id: metric,
  };
  final decideCount = _count(index, TaskInsightIds.todayDecisions);
  final followUpCount = _count(index, TaskInsightIds.todayRelationships);
  final agentCount = _count(index, TaskInsightIds.agentHandoff);
  return projection.copyWith(
    metrics: <SummaryMetric>[
      _countMetric(
        existingMetrics: existingMetrics,
        id: 'decisions',
        label: 'Decide',
        count: decideCount,
        subtitle: 'Need your judgment',
        severity: decideCount > 0 ? 'warning' : 'normal',
        insightId: TaskInsightIds.todayDecisions,
      ),
      _countMetric(
        existingMetrics: existingMetrics,
        id: 'relationships',
        label: 'Follow-ups',
        count: followUpCount,
        subtitle: 'People or promises',
        severity: followUpCount > 0 ? 'warning' : 'normal',
        insightId: TaskInsightIds.todayRelationships,
      ),
      _countMetric(
        existingMetrics: existingMetrics,
        id: 'agent_can_handle',
        label: 'Agent can handle',
        count: agentCount,
        subtitle: 'Ready to act',
        severity: agentCount > 0 ? 'good' : 'normal',
        insightId: TaskInsightIds.agentHandoff,
      ),
    ],
  );
}

/// Returns true when the local insight index has task facts to count.
bool _hasIndexedTasks(TaskInsightIndex index) {
  return index.workspaceTasksById.isNotEmpty ||
      index.projectionTasksById.isNotEmpty;
}

/// Counts matching candidates for one insight id.
int _count(TaskInsightIndex index, String insightId) {
  return index.tasksForInsight(insightId).length;
}

/// Builds one numeric Today metric linked to its matching backlog preset.
SummaryMetric _countMetric({
  required Map<String, SummaryMetric> existingMetrics,
  required String id,
  required String label,
  required int count,
  required String subtitle,
  required String severity,
  required String insightId,
}) {
  final existing = existingMetrics[id];
  return SummaryMetric(
    id: id,
    label: label,
    value: count.toString(),
    subtitle: subtitle,
    severity: severity,
    link: ProjectionLink(
      label: existing?.link.label ?? '',
      route: '/backlog?insight=$insightId',
    ),
  );
}
