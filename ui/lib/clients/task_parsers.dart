/// Parsers for graph-backed task tool result payloads.
part of 'mcp_client.dart';

List<WorkspaceTask> parseWorkspaceTasks(dynamic content) {
  if (content is! List) {
    return const <WorkspaceTask>[];
  }
  return content
      .whereType<Map<String, dynamic>>()
      .map(parseWorkspaceTask)
      .toList();
}

/// Parses one workspace task from a graph-backed task tool result.
WorkspaceTask parseWorkspaceTask(dynamic content) {
  final task = content is Map<String, dynamic> ? content : <String, dynamic>{};
  final status = stringValue(task['status'], fallback: 'open');
  final priority = stringValue(task['priority'], fallback: 'normal');
  final dueAt = parseOptionalDateTime(task['due_at']);
  final scheduledAt = parseOptionalDateTime(task['scheduled_at']);
  final followUpAt = parseOptionalDateTime(task['follow_up_at']);
  final detailParts = <String>[statusLabel(status)];
  if (priority.isNotEmpty && priority != 'normal') {
    detailParts.add(priorityLabel(priority));
  }
  if (dueAt != null) {
    detailParts.add('Due ${formatLocalDate(dueAt)}');
  } else if (scheduledAt != null) {
    detailParts.add('Scheduled ${formatLocalDate(scheduledAt)}');
  } else if (followUpAt != null) {
    detailParts.add('Review ${formatLocalDate(followUpAt)}');
  }
  return WorkspaceTask(
    id: stringValue(task['id']),
    title: stringValue(task['title'], fallback: 'Untitled task'),
    detail: detailParts.join(' • '),
    done: status == 'done',
    description: stringValue(task['description']),
    status: status,
    priority: priority,
    dueAt: dueAt,
    scheduledAt: scheduledAt,
    followUpAt: followUpAt,
    topics: stringList(task['topics']),
    overdue: boolValue(task['overdue']),
    memoryLinks: parseTaskMemoryLinks(task['memory_links']),
    estimateMinutes: intValue(task['estimate_minutes']),
    urgency: doubleValue(task['urgency']),
    risk: doubleValue(task['risk']),
    project: stringValue(task['project']),
    location: stringValue(task['location']),
    owner: stringValue(task['person']),
    spendCents: intValue(task['spend_cents']),
    earnCents: intValue(task['earn_cents']),
    saveCents: intValue(task['save_cents']),
    currency: stringValue(task['currency']),
    workBreakdown: parseTaskWorkBreakdown(task['work_breakdown']),
    createdAt: parseOptionalDateTime(task['created_at']),
    updatedAt: parseOptionalDateTime(task['updated_at']),
    completedAt: parseOptionalDateTime(task['completed_at']),
    canceledAt: parseOptionalDateTime(task['canceled_at']),
    active: status == 'open' || status == 'waiting' || status == 'blocked',
    idempotencyKey: stringValue(task['idempotency_key']),
  );
}

/// Parses WBS metadata from a graph-backed task tool result.
TaskWorkBreakdown parseTaskWorkBreakdown(dynamic content) {
  final workBreakdown = _workBreakdownMap(content);
  return TaskWorkBreakdown(
    code: stringValue(workBreakdown['code']),
    deliverable: stringValue(workBreakdown['deliverable']),
    startCriteria: stringList(workBreakdown['start_criteria']),
    acceptanceCriteria: stringList(workBreakdown['acceptance_criteria']),
    requirementRefs: stringList(workBreakdown['requirement_refs']),
    rubricRefs: stringList(workBreakdown['rubric_refs']),
    resources: parseTaskResourceRequirements(workBreakdown['resources']),
    estimatedCostCents: intValue(workBreakdown['spend_cents']),
    costCurrency: stringValue(workBreakdown['spend_currency']),
  );
}

/// Parses graph query rows containing task WBS metadata.
Map<String, TaskWorkBreakdown> parseTaskWorkBreakdownRows(dynamic content) {
  final result = content is Map<String, dynamic>
      ? content
      : <String, dynamic>{};
  final rows = result['rows'];
  if (rows is! List) {
    return const <String, TaskWorkBreakdown>{};
  }
  final values = <String, TaskWorkBreakdown>{};
  for (final row in rows.whereType<Map<String, dynamic>>()) {
    final taskId = stringValue(row['id']);
    if (taskId.isEmpty) {
      continue;
    }
    final workBreakdown = parseTaskWorkBreakdown(row['work_breakdown']);
    if (taskWorkBreakdownHasContent(workBreakdown)) {
      values[taskId] = workBreakdown;
    }
  }
  return values;
}

/// Reports whether WBS metadata has useful content.
bool taskWorkBreakdownHasContent(TaskWorkBreakdown workBreakdown) {
  return workBreakdown.code.isNotEmpty ||
      workBreakdown.deliverable.isNotEmpty ||
      workBreakdown.startCriteria.isNotEmpty ||
      workBreakdown.acceptanceCriteria.isNotEmpty ||
      workBreakdown.requirementRefs.isNotEmpty ||
      workBreakdown.rubricRefs.isNotEmpty ||
      workBreakdown.resources.isNotEmpty ||
      workBreakdown.estimatedCostCents > 0 ||
      workBreakdown.costCurrency.isNotEmpty;
}

/// Converts JSON-object or JSON-string WBS payloads to maps.
Map<String, dynamic> _workBreakdownMap(dynamic content) {
  if (content is Map<String, dynamic>) {
    return content;
  }
  if (content is String && content.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return <String, dynamic>{};
    }
  }
  return <String, dynamic>{};
}

/// Parses WBS resource requirements from graph-backed task tool results.
List<TaskResourceRequirement> parseTaskResourceRequirements(dynamic content) {
  if (content is! List) {
    return const <TaskResourceRequirement>[];
  }
  return content.whereType<Map<String, dynamic>>().map((resource) {
    return TaskResourceRequirement(
      name: stringValue(resource['name']),
      type: stringValue(resource['type']),
      quantity: doubleValue(resource['quantity']),
      unit: stringValue(resource['unit']),
      estimatedCostCents: intValue(resource['spend_cents']),
      costCurrency: stringValue(resource['spend_currency']),
      notes: stringValue(resource['notes']),
    );
  }).toList();
}

/// Parses task memory links.
List<TaskMemoryLink> parseTaskMemoryLinks(dynamic content) {
  if (content is! List) {
    return const <TaskMemoryLink>[];
  }
  return content
      .whereType<Map<String, dynamic>>()
      .map(parseTaskMemoryLink)
      .toList();
}

/// Parses one task memory link.
TaskMemoryLink parseTaskMemoryLink(dynamic content) {
  final link = content is Map<String, dynamic> ? content : <String, dynamic>{};
  return TaskMemoryLink(
    id: stringValue(link['id']),
    memoryId: stringValue(link['memory_id']),
    memoryEvidenceId: stringValue(link['memory_evidence_id']),
    relationship: stringValue(link['relationship'], fallback: 'context'),
    note: stringValue(link['note']),
    createdAt: parseOptionalDateTime(link['created_at']),
  );
}

/// Parses explicit task relation records.
List<TaskRelationRecord> parseTaskRelations(dynamic content) {
  if (content is! List) {
    return const <TaskRelationRecord>[];
  }
  return content
      .whereType<Map<String, dynamic>>()
      .map(parseTaskRelation)
      .toList();
}

/// Parses one explicit task relation record.
TaskRelationRecord parseTaskRelation(dynamic content) {
  final relation = content is Map<String, dynamic>
      ? content
      : <String, dynamic>{};
  return TaskRelationRecord(
    id: stringValue(relation['id']),
    fromTaskId: stringValue(relation['from_task_id']),
    toTaskId: stringValue(relation['to_task_id']),
    relationType: stringValue(relation['type']),
    confidence: doubleValue(relation['confidence']),
    source: stringValue(relation['source']),
    explanation: stringValue(relation['explanation']),
    actor: stringValue(relation['actor']),
    createdAt: parseOptionalDateTime(relation['created_at']),
    updatedAt: parseOptionalDateTime(relation['updated_at']),
  );
}

/// Parses a canonical task projection graph.
TaskProjectionGraph parseTaskProjectionGraph(dynamic content) {
  final graph = content is Map<String, dynamic> ? content : <String, dynamic>{};
  return TaskProjectionGraph(
    schemaVersion: stringValue(graph['schema_version']),
    generatedAt: parseOptionalDateTime(graph['generated_at']),
    tasks: parseTaskProjectionTasks(graph['tasks']),
    facets: parseTaskProjectionFacets(graph['facets']),
    memberships: parseTaskProjectionMemberships(graph['memberships']),
    edges: parseTaskProjectionEdges(graph['relations']),
    insightSummaries: parseTaskInsightSummaries(graph['insight_summaries']),
    quality: parseTaskProjectionQuality(graph['quality']),
  );
}

/// Parses graph quality metrics.
TaskProjectionQuality parseTaskProjectionQuality(dynamic content) {
  final quality = content is Map<String, dynamic>
      ? content
      : <String, dynamic>{};
  return TaskProjectionQuality(
    schemaConfidence: doubleValue(quality['schema_confidence']),
    relationCoverage: doubleValue(quality['relation_coverage']),
    warnings: stringList(quality['warnings']),
  );
}

/// Parses canonical projected tasks.
List<TaskProjectionTask> parseTaskProjectionTasks(dynamic content) {
  if (content is! List) {
    return const <TaskProjectionTask>[];
  }
  return content.whereType<Map<String, dynamic>>().map((task) {
    return TaskProjectionTask(
      taskId: stringValue(task['id']),
      title: stringValue(task['title']),
      description: stringValue(task['description']),
      status: stringValue(task['status']),
      priority: stringValue(task['priority']),
      dueAt: parseOptionalDateTime(task['due_at']),
      scheduledAt: parseOptionalDateTime(task['scheduled_at']),
      topics: stringList(task['topics']),
      estimateMinutes: intValue(task['estimate_minutes']),
      project: stringValue(task['project']),
      location: stringValue(task['location']),
      owner: stringValue(task['person']),
      workBreakdown: parseTaskWorkBreakdown(task['work_breakdown']),
      scores: parseTaskProjectionScores(task['scores']),
      scoreComponents: parseTaskScoreComponents(task['score_components']),
      facetIds: stringList(task['facet_ids']),
      evidenceIds: stringList(task['evidence_ids']),
      missingFields: stringList(task['missing_fields']),
      confidence: doubleValue(task['confidence']),
      explanation: stringValue(task['explanation']),
    );
  }).toList();
}

/// Parses derived task projection scores.
TaskProjectionScores parseTaskProjectionScores(dynamic content) {
  final scores = content is Map<String, dynamic>
      ? content
      : <String, dynamic>{};
  return TaskProjectionScores(
    reward: doubleValue(scores['reward']),
    pressure: doubleValue(scores['pressure']),
    risk: doubleValue(scores['risk']),
    timePressure: doubleValue(scores['time_pressure']),
    humanEffort: doubleValue(scores['human_effort']),
    agentFit: doubleValue(scores['agent_fit']),
    obligation: doubleValue(scores['obligation']),
    consequenceSeverity: doubleValue(scores['consequence_severity']),
    agentSafety: doubleValue(scores['agent_safety']),
    handoffReadiness: doubleValue(scores['handoff_readiness']),
    contextReadiness: doubleValue(scores['context_readiness']),
    humanJudgmentNeed: doubleValue(scores['human_judgment_need']),
    downstreamValue: doubleValue(scores['downstream_value']),
    blockerEffort: doubleValue(scores['blocker_effort']),
    unblockLeverage: doubleValue(scores['unblock_leverage']),
    staleness: doubleValue(scores['staleness']),
    elevation: doubleValue(scores['elevation']),
    terrainZone: stringValue(scores['terrain_zone']),
  );
}

/// Parses score explanations keyed by score name.
Map<String, List<TaskScoreComponent>> parseTaskScoreComponents(
  dynamic content,
) {
  if (content is! Map<String, dynamic>) {
    return const <String, List<TaskScoreComponent>>{};
  }
  final output = <String, List<TaskScoreComponent>>{};
  for (final entry in content.entries) {
    final value = entry.value;
    if (value is! List) {
      continue;
    }
    final components = value.whereType<Map<String, dynamic>>().map((
      Map<String, dynamic> component,
    ) {
      return TaskScoreComponent(
        name: stringValue(component['name']),
        value: doubleValue(component['value']),
        explanation: stringValue(component['explanation']),
      );
    }).toList();
    output[entry.key] = components;
  }
  return output;
}

/// Parses reusable task projection facets.
List<TaskProjectionFacet> parseTaskProjectionFacets(dynamic content) {
  if (content is! List) {
    return const <TaskProjectionFacet>[];
  }
  return content.whereType<Map<String, dynamic>>().map((facet) {
    return TaskProjectionFacet(
      id: stringValue(facet['id']),
      dimension: stringValue(facet['kind']),
      label: stringValue(facet['label']),
      description: stringValue(facet['description']),
      source: stringValue(facet['source']),
      version: stringValue(facet['version']),
      sourceField: stringValue(facet['source_field']),
      provenance: stringValue(facet['provenance']),
      confidence: doubleValue(facet['confidence']),
    );
  }).toList();
}

/// Parses task projection facet memberships.
List<TaskProjectionMembership> parseTaskProjectionMemberships(dynamic content) {
  if (content is! List) {
    return const <TaskProjectionMembership>[];
  }
  return content.whereType<Map<String, dynamic>>().map((membership) {
    return TaskProjectionMembership(
      taskId: stringValue(membership['task_id']),
      facetId: stringValue(membership['facet_id']),
      dimension: stringValue(membership['dimension']),
      source: stringValue(membership['source']),
      confidence: doubleValue(membership['confidence']),
      explanation: stringValue(membership['explanation']),
    );
  }).toList();
}

/// Parses sparse task projection edges.
List<TaskProjectionEdge> parseTaskProjectionEdges(dynamic content) {
  if (content is! List) {
    return const <TaskProjectionEdge>[];
  }
  return content.whereType<Map<String, dynamic>>().map((edge) {
    return TaskProjectionEdge(
      id: stringValue(edge['id']),
      fromTaskId: stringValue(edge['from_task_id']),
      toTaskId: stringValue(edge['to_task_id']),
      relationType: stringValue(edge['type']),
      directionSemantics: stringValue(edge['direction_semantics']),
      source: stringValue(edge['source']),
      sourceKind: stringValue(edge['source_kind']),
      firewall: stringValue(edge['firewall']),
      sensitivity: stringValue(edge['sensitivity']),
      confidence: doubleValue(edge['confidence']),
      explanation: stringValue(edge['explanation']),
      evidenceIds: stringList(edge['evidence_ids']),
      actor: stringValue(edge['actor']),
      createdAt: parseOptionalDateTime(edge['created_at']),
      updatedAt: parseOptionalDateTime(edge['updated_at']),
      confirmedAt: parseOptionalDateTime(edge['confirmed_at']),
      dismissedAt: parseOptionalDateTime(edge['dismissed_at']),
    );
  }).toList();
}

/// Parses source-provided insight summaries.
List<TaskInsightSummary> parseTaskInsightSummaries(dynamic content) {
  if (content is! List) {
    return const <TaskInsightSummary>[];
  }
  return content.whereType<Map<String, dynamic>>().map((summary) {
    return TaskInsightSummary(
      id: stringValue(summary['id']),
      title: stringValue(summary['title']),
      question: stringValue(summary['question']),
      count: intValue(summary['count']),
      estimatedMinutes: intValue(summary['estimated_minutes']),
      primaryTaskIds: stringList(summary['primary_task_ids']),
      warningCount: intValue(summary['warning_count']),
      explanation: stringValue(summary['explanation']),
    );
  }).toList();
}

/// Converts backend task status values into compact display labels.
String statusLabel(String status) {
  switch (status) {
    case 'done':
      return 'Done';
    case 'waiting':
      return 'Waiting';
    case 'blocked':
      return 'Blocked';
    case 'canceled':
      return 'Canceled';
    default:
      return 'Open';
  }
}

/// Converts backend task priority values into compact display labels.
String priorityLabel(String priority) {
  switch (priority) {
    case 'urgent':
      return 'Urgent';
    case 'high':
      return 'High';
    case 'low':
      return 'Low';
    default:
      return 'Normal';
  }
}
