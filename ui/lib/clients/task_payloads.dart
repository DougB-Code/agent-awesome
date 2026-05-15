/// Payload builders for graph-backed task tool calls.
part of 'mcp_client.dart';

Map<String, dynamic> _taskQueryArguments({
  required TaskFilterState filters,
  required bool includeDone,
  required bool includeLinks,
  required int limit,
}) {
  final arguments = <String, dynamic>{
    'include_done': includeDone,
    'include_links': includeLinks,
    'limit': limit,
  };
  if (filters.statuses.isNotEmpty) {
    arguments['statuses'] = filters.statuses;
  }
  if (filters.priorities.isNotEmpty) {
    arguments['priorities'] = filters.priorities;
  }
  if (filters.topics.isNotEmpty) {
    arguments['topics'] = filters.topics;
  }
  if (filters.search.trim().isNotEmpty) {
    arguments['search'] = filters.search.trim();
  }
  if (filters.overdueOnly) {
    arguments['overdue_only'] = true;
  }
  return arguments;
}

/// Adds non-empty task graph metadata arguments to a create payload.
void _addTaskMetadataArguments(
  Map<String, dynamic> arguments, {
  required int estimateMinutes,
  required double urgency,
  required String project,
  required String location,
  required String owner,
  required int spendCents,
  required int earnCents,
  required int saveCents,
  required String currency,
}) {
  if (estimateMinutes > 0) {
    arguments['estimate_minutes'] = estimateMinutes;
  }
  if (urgency > 0) {
    arguments['urgency'] = urgency;
  }
  if (project.trim().isNotEmpty) {
    arguments['project'] = project.trim();
  }
  if (location.trim().isNotEmpty) {
    arguments['location'] = location.trim();
  }
  if (owner.trim().isNotEmpty) {
    arguments['person'] = owner.trim();
  }
  if (spendCents > 0) {
    arguments['spend_cents'] = spendCents;
  }
  if (earnCents > 0) {
    arguments['earn_cents'] = earnCents;
  }
  if (saveCents > 0) {
    arguments['save_cents'] = saveCents;
  }
  if (currency.trim().isNotEmpty) {
    arguments['currency'] = currency.trim();
  }
}

/// Adds WBS metadata to a create payload when any WBS field exists.
void _addTaskWorkBreakdownArgument(
  Map<String, dynamic> arguments,
  TaskWorkBreakdown workBreakdown,
) {
  final payload = _taskWorkBreakdownPayload(workBreakdown);
  if (payload.isNotEmpty) {
    arguments['work_breakdown'] = payload;
  }
}

/// Adds nullable task graph metadata arguments to an update payload.
void _addOptionalTaskMetadataArguments(
  Map<String, dynamic> arguments, {
  required int? estimateMinutes,
  required double? urgency,
  required String? project,
  required String? location,
  required String? owner,
  required int? spendCents,
  required int? earnCents,
  required int? saveCents,
  required String? currency,
}) {
  if (estimateMinutes != null) {
    arguments['estimate_minutes'] = estimateMinutes;
  }
  if (urgency != null) {
    arguments['urgency'] = urgency;
  }
  if (project != null) {
    arguments['project'] = project.trim();
  }
  if (location != null) {
    arguments['location'] = location.trim();
  }
  if (owner != null) {
    arguments['person'] = owner.trim();
  }
  if (spendCents != null) {
    arguments['spend_cents'] = spendCents;
  }
  if (earnCents != null) {
    arguments['earn_cents'] = earnCents;
  }
  if (saveCents != null) {
    arguments['save_cents'] = saveCents;
  }
  if (currency != null) {
    arguments['currency'] = currency.trim();
  }
}

/// Converts WBS metadata to graph-backed task tool arguments.
Map<String, dynamic> _taskWorkBreakdownPayload(
  TaskWorkBreakdown workBreakdown,
) {
  final payload = <String, dynamic>{};
  if (workBreakdown.code.trim().isNotEmpty) {
    payload['code'] = workBreakdown.code.trim();
  }
  if (workBreakdown.deliverable.trim().isNotEmpty) {
    payload['deliverable'] = workBreakdown.deliverable.trim();
  }
  if (workBreakdown.startCriteria.isNotEmpty) {
    payload['start_criteria'] = workBreakdown.startCriteria;
  }
  if (workBreakdown.acceptanceCriteria.isNotEmpty) {
    payload['acceptance_criteria'] = workBreakdown.acceptanceCriteria;
  }
  if (workBreakdown.requirementRefs.isNotEmpty) {
    payload['requirement_refs'] = workBreakdown.requirementRefs;
  }
  if (workBreakdown.rubricRefs.isNotEmpty) {
    payload['rubric_refs'] = workBreakdown.rubricRefs;
  }
  if (workBreakdown.resources.isNotEmpty) {
    payload['resources'] = workBreakdown.resources
        .map(_taskResourceRequirementPayload)
        .toList();
  }
  if (workBreakdown.estimatedCostCents > 0) {
    payload['spend_cents'] = workBreakdown.estimatedCostCents;
  }
  if (workBreakdown.costCurrency.trim().isNotEmpty) {
    payload['spend_currency'] = workBreakdown.costCurrency.trim();
  }
  return payload;
}

/// Converts one WBS resource requirement to graph-backed task tool arguments.
Map<String, dynamic> _taskResourceRequirementPayload(
  TaskResourceRequirement resource,
) {
  final payload = <String, dynamic>{'name': resource.name.trim()};
  if (resource.type.trim().isNotEmpty) {
    payload['type'] = resource.type.trim();
  }
  if (resource.quantity > 0) {
    payload['quantity'] = resource.quantity;
  }
  if (resource.unit.trim().isNotEmpty) {
    payload['unit'] = resource.unit.trim();
  }
  if (resource.estimatedCostCents > 0) {
    payload['spend_cents'] = resource.estimatedCostCents;
  }
  if (resource.costCurrency.trim().isNotEmpty) {
    payload['spend_currency'] = resource.costCurrency.trim();
  }
  if (resource.notes.trim().isNotEmpty) {
    payload['notes'] = resource.notes.trim();
  }
  return payload;
}

/// Formats a timestamp for graph-backed task tool arguments.
String _dateArgument(DateTime value) {
  return value.toUtc().toIso8601String();
}

/// Converts a memory link draft to graph-backed task tool arguments.
Map<String, dynamic> _memoryLinkDraftPayload(TaskMemoryLinkDraft draft) {
  final payload = <String, dynamic>{'relationship': draft.relationship};
  if (draft.memoryId.isNotEmpty) {
    payload['memory_id'] = draft.memoryId;
  }
  if (draft.memoryEvidenceId.isNotEmpty) {
    payload['memory_evidence_id'] = draft.memoryEvidenceId;
  }
  if (draft.note.isNotEmpty) {
    payload['note'] = draft.note;
  }
  return payload;
}
