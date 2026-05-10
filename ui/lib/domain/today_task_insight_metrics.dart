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
  final executeCount = _count(index, TaskInsightIds.todayActions);
  final decideCount = _count(index, TaskInsightIds.todayDecisions);
  final followUpCount = _count(index, TaskInsightIds.todayRelationships);
  final agentCount = _count(index, TaskInsightIds.agentHandoff);
  final metadataGapCount = _count(index, TaskInsightIds.metadataGaps);
  final activeTaskCount = _activeTaskCount(index);
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
        id: 'actions',
        label: 'Execute',
        count: executeCount,
        subtitle: 'Ready to act',
        severity: executeCount > 0 ? 'good' : 'normal',
        insightId: TaskInsightIds.todayActions,
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
      _dataQualityMetric(
        existingMetrics: existingMetrics,
        metadataGapCount: metadataGapCount,
        activeTaskCount: activeTaskCount,
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

/// Counts active tasks known to the insight index.
int _activeTaskCount(TaskInsightIndex index) {
  final taskIds = <String>{
    ...index.workspaceTasksById.keys,
    ...index.projectionTasksById.keys,
  };
  return taskIds.where(index.isActiveTask).length;
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

/// Builds the non-numeric data quality metric from metadata gap candidates.
SummaryMetric _dataQualityMetric({
  required Map<String, SummaryMetric> existingMetrics,
  required int metadataGapCount,
  required int activeTaskCount,
}) {
  final existing = existingMetrics['picture_quality'];
  final value = activeTaskCount == 0
      ? 'Sparse'
      : metadataGapCount == 0
      ? 'Good'
      : 'Partial';
  final subtitle = activeTaskCount == 0
      ? 'No active backlog'
      : metadataGapCount == 0
      ? 'No gaps known'
      : '$metadataGapCount ${metadataGapCount == 1 ? 'gap' : 'gaps'} limit insights';
  return SummaryMetric(
    id: 'picture_quality',
    label: existing?.label ?? 'Data quality',
    value: value,
    subtitle: subtitle,
    severity: metadataGapCount > 0
        ? 'warning'
        : activeTaskCount > 0
        ? 'good'
        : 'normal',
    link: ProjectionLink(
      label: existing?.link.label ?? '',
      route: '/backlog?insight=${TaskInsightIds.metadataGaps}',
    ),
  );
}
