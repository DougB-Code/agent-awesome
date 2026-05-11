/// Backlog metadata, insight, graph, and memory detail widgets.
part of 'backlog_section.dart';

class _TaskMetadataBlock extends StatelessWidget {
  const _TaskMetadataBlock({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  /// Builds context metadata details.
  @override
  Widget build(BuildContext context) {
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: _TaskPanelLabel('Metadata')),
              Tooltip(
                message: 'Edit graph metadata',
                child: IconButton(
                  onPressed: controller.tasksBusy
                      ? null
                      : () => unawaited(
                          _showTaskMetadataDialog(context, controller, task),
                        ),
                  icon: const Icon(Icons.tune_outlined, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _TaskMetadataRow(
            label: 'Estimate',
            value: task.estimateMinutes <= 0
                ? ''
                : '${task.estimateMinutes} min',
          ),
          _TaskMetadataRow(label: 'Energy', value: task.energyRequired),
          _TaskMetadataRow(label: 'Context', value: task.context),
          _TaskMetadataRow(label: 'View', value: task.domain),
          _TaskMetadataRow(label: 'Location', value: task.location),
          _TaskMetadataRow(label: 'Person', value: task.owner),
          _TaskMetadataRow(label: 'Source', value: task.source),
          _TaskMetadataRow(
            label: 'Effort',
            value: _formatTaskScore(task.effort),
          ),
          _TaskMetadataRow(label: 'Value', value: _formatTaskScore(task.value)),
          _TaskMetadataRow(
            label: 'Urgency',
            value: _formatTaskScore(task.urgency),
          ),
          _TaskMetadataRow(label: 'Risk', value: _formatTaskScore(task.risk)),
          _TaskMetadataRow(
            label: 'Confidence',
            value: _formatTaskScore(task.confidence),
          ),
          _TaskMetadataRow(label: 'Backlog id', value: task.id),
          _TaskMetadataRow(label: 'Server', value: task.sourceLabel),
          _TaskMetadataRow(
            label: 'Created',
            value: formatOptionalLocalDateTime(task.createdAt),
          ),
          _TaskMetadataRow(
            label: 'Updated',
            value: formatOptionalLocalDateTime(task.updatedAt),
          ),
          _TaskMetadataRow(
            label: 'Completed',
            value: formatOptionalLocalDateTime(task.completedAt),
          ),
          _TaskMetadataRow(
            label: 'Canceled',
            value: formatOptionalLocalDateTime(task.canceledAt),
          ),
        ],
      ),
    );
  }
}

class _TaskWbsBlock extends StatelessWidget {
  const _TaskWbsBlock({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  /// Builds task WBS planning details.
  @override
  Widget build(BuildContext context) {
    final workBreakdown = task.workBreakdown;
    final hasContent = taskWbsHasContent(workBreakdown);
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: _TaskPanelLabel('WBS')),
              Tooltip(
                message: 'Edit WBS',
                child: IconButton(
                  onPressed: controller.tasksBusy
                      ? null
                      : () => unawaited(
                          _showTaskWbsDialog(context, controller, task),
                        ),
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!hasContent)
            Text(
              'No WBS metadata',
              style: TextStyle(color: context.agentAwesomeColors.muted),
            )
          else ...<Widget>[
            _TaskMetadataRow(label: 'Code', value: workBreakdown.code),
            _TaskMetadataRow(
              label: 'Deliverable',
              value: workBreakdown.deliverable,
            ),
            _TaskMetadataRow(
              label: 'Spend',
              value: formatTaskWbsSpend(workBreakdown),
            ),
            _TaskListRows(label: 'Start', values: workBreakdown.startCriteria),
            _TaskListRows(
              label: 'Done',
              values: workBreakdown.acceptanceCriteria,
            ),
            _TaskListRows(
              label: 'Requirements',
              values: workBreakdown.requirementRefs,
            ),
            _TaskListRows(label: 'Rubric', values: workBreakdown.rubricRefs),
            if (workBreakdown.resources.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              for (final resource in workBreakdown.resources)
                _TaskResourceRow(resource: resource),
            ],
          ],
        ],
      ),
    );
  }
}

class _TaskListRows extends StatelessWidget {
  const _TaskListRows({required this.label, required this.values});

  final String label;
  final List<String> values;

  /// Builds an ordered list of WBS metadata values.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: colors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(value, style: const TextStyle(height: 1.3)),
            ),
        ],
      ),
    );
  }
}

class _TaskResourceRow extends StatelessWidget {
  const _TaskResourceRow({required this.resource});

  final TaskResourceRequirement resource;

  /// Builds one compact WBS resource row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final details = <String>[
      if (resource.type.isNotEmpty) resource.type,
      if (resource.quantity > 0)
        '${formatTaskQuantity(resource.quantity)} ${resource.unit}'.trim(),
      formatTaskResourceSpend(resource),
      if (resource.notes.isNotEmpty) resource.notes,
    ].where((item) => item.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.construction_outlined, size: 16, color: colors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  resource.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' • '),
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// _TaskInsightDetailsBlock explains selected-task insight membership.
class _TaskInsightDetailsBlock extends StatelessWidget {
  const _TaskInsightDetailsBlock({
    required this.controller,
    required this.task,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  /// Builds insight summary, unblock plan, handoff, and metadata gaps.
  @override
  Widget build(BuildContext context) {
    final index = controller.taskInsightIndex;
    final taskId = task.id;
    final scores = index.scoresFor(taskId);
    final candidates = index.candidatesForTask(taskId);
    final plan = index.unblockPlanFor(taskId);
    final gaps = index.metadataGapsFor(taskId);
    final handoff = index.candidateForTask(taskId, TaskInsightIds.agentHandoff);
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _TaskPanelLabel('Insights'),
          const SizedBox(height: 10),
          Text(
            TaskInsightExplanations.whyThisMatters(
              task: task,
              scores: scores,
              candidates: candidates,
            ),
            style: TextStyle(
              color: context.agentAwesomeColors.ink,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              if (scores != null) ...<Widget>[
                _TaskBadge(label: 'Reward ${_formatTaskScore(scores.reward)}'),
                _TaskBadge(
                  label: 'Pressure ${_formatTaskScore(scores.pressure)}',
                ),
                _TaskBadge(label: 'Risk ${_formatTaskScore(scores.risk)}'),
                _TaskBadge(
                  label: 'Confidence ${_formatTaskScore(scores.confidence)}',
                ),
              ],
              for (final candidate in candidates.take(3))
                _TaskBadge(label: _insightCandidateLabel(candidate)),
            ],
          ),
          if (plan.hasExplicitBlocker ||
              task.status == 'blocked' ||
              task.status == 'waiting') ...<Widget>[
            const Divider(height: 22),
            _TaskGraphRow(
              icon: Icons.lock_open_outlined,
              title: 'Unblock plan',
              subtitle: plan.explanation,
              badges: <String>[
                if (plan.primaryBlockerId.isNotEmpty)
                  'Blocked by ${index.titleForTaskId(plan.primaryBlockerId)}',
                if (plan.downstreamTaskIds.isNotEmpty)
                  'Unlocks ${plan.downstreamTaskIds.length}',
                _formatTaskScore(plan.confidence),
              ],
              actions: const <Widget>[],
            ),
            _TaskMetadataRow(
              label: 'Next action',
              value: plan.smallestNextAction,
            ),
            if (plan.agentAssistOptions.isNotEmpty)
              _TaskMetadataRow(
                label: 'Agent can help',
                value: plan.agentAssistOptions.take(2).join(' '),
              ),
          ],
          if (handoff != null) ...<Widget>[
            const Divider(height: 22),
            _TaskGraphRow(
              icon: Icons.smart_toy_outlined,
              title: 'Agent handoff readiness',
              subtitle: handoff.explanation,
              badges: <String>[
                handoff.severity == 'warning' ? 'Needs review' : 'Ready',
                if (scores != null) 'Fit ${_formatTaskScore(scores.agentFit)}',
                if (scores != null)
                  'Safety ${_formatTaskScore(scores.agentSafety)}',
              ],
              actions: const <Widget>[],
            ),
          ],
          if (gaps.isNotEmpty) ...<Widget>[
            const Divider(height: 22),
            for (final gap in gaps.take(3))
              _TaskGraphRow(
                icon: Icons.manage_search_outlined,
                title: 'Missing ${gap.field.replaceAll('_', ' ')}',
                subtitle: gap.message.isEmpty
                    ? gap.proposedAction
                    : gap.message,
                badges: <String>[
                  _taskLabel(gap.severity),
                  for (final insight in gap.blocksInsights.take(2))
                    _taskLabel(insight),
                ],
                actions: const <Widget>[],
              ),
          ],
        ],
      ),
    );
  }

  /// Returns a compact badge label for one insight candidate.
  String _insightCandidateLabel(TaskInsightCandidate candidate) {
    final label = switch (candidate.insightId) {
      TaskInsightIds.todayActions => 'Execute',
      TaskInsightIds.todayDecisions => 'Decide',
      TaskInsightIds.todayRelationships => 'Follow-up',
      TaskInsightIds.agentHandoff => 'Agent handoff',
      TaskInsightIds.nextWeekHighValue => 'Next week value',
      TaskInsightIds.quickUnblocks => 'Quick unblock',
      TaskInsightIds.metadataGaps => 'Metadata gap',
      TaskInsightIds.highRiskLowConfidence => 'Risk gap',
      _ => 'Insight',
    };
    return '$label ${_formatTaskScore(candidate.score)}';
  }
}

class _TaskGraphDetailsBlock extends StatelessWidget {
  const _TaskGraphDetailsBlock({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  /// Builds relationship, suggestion, and commitment controls.
  @override
  Widget build(BuildContext context) {
    final relationSuggestions = controller.selectedTaskRelationSuggestions;
    final metadataSuggestions = controller.selectedTaskMetadataSuggestions;
    final commitmentSuggestions = controller.selectedTaskCommitmentSuggestions;
    final relations = controller.selectedTaskRelations;
    final commitments = controller.selectedTaskCommitments;
    final canUpsertRelation = controller.primaryMemoryToolAvailable(
      'upsert_task_relation',
    );
    final canUpsertCommitment = controller.primaryMemoryToolAvailable(
      'upsert_commitment',
    );
    final suggestionWidgets = <Widget>[
      for (final suggestion in relationSuggestions)
        _TaskRelationSuggestionTile(
          controller: controller,
          task: task,
          suggestion: suggestion,
        ),
      for (final suggestion in metadataSuggestions)
        _TaskMetadataSuggestionTile(
          controller: controller,
          suggestion: suggestion,
        ),
      for (final suggestion in commitmentSuggestions)
        _TaskCommitmentSuggestionTile(
          controller: controller,
          suggestion: suggestion,
        ),
    ];
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: _TaskPanelLabel('Graph')),
              if (canUpsertRelation)
                Tooltip(
                  message: 'Add relation',
                  child: IconButton(
                    onPressed: controller.tasksBusy
                        ? null
                        : () => unawaited(
                            _showTaskRelationDialog(context, controller, task),
                          ),
                    icon: const Icon(Icons.account_tree_outlined, size: 18),
                  ),
                ),
              if (canUpsertCommitment)
                Tooltip(
                  message: 'Add commitment',
                  child: IconButton(
                    onPressed: controller.tasksBusy
                        ? null
                        : () => unawaited(
                            _showTaskCommitmentDialog(
                              context,
                              controller,
                              task,
                            ),
                          ),
                    icon: const Icon(Icons.handshake_outlined, size: 18),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _TaskGraphSubsection(
            title: 'Suggestions',
            emptyLabel: 'No graph suggestions',
            children: suggestionWidgets,
          ),
          const Divider(height: 22),
          _TaskGraphSubsection(
            title: 'Relations',
            emptyLabel: 'No explicit relations',
            children: <Widget>[
              for (final relation in relations)
                _TaskRelationTile(
                  controller: controller,
                  task: task,
                  relation: relation,
                ),
            ],
          ),
          const Divider(height: 22),
          _TaskGraphSubsection(
            title: 'Commitments',
            emptyLabel: 'No first-class commitments',
            children: <Widget>[
              for (final commitment in commitments)
                _TaskCommitmentTile(
                  controller: controller,
                  task: task,
                  commitment: commitment,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskGraphSubsection extends StatelessWidget {
  const _TaskGraphSubsection({
    required this.title,
    required this.emptyLabel,
    required this.children,
  });

  final String title;
  final String emptyLabel;
  final List<Widget> children;

  /// Builds one compact graph data subsection.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (children.isEmpty)
          Text(
            emptyLabel,
            style: TextStyle(color: context.agentAwesomeColors.muted),
          )
        else
          ...children,
      ],
    );
  }
}

class _TaskMetadataSuggestionTile extends StatelessWidget {
  const _TaskMetadataSuggestionTile({
    required this.controller,
    required this.suggestion,
  });

  final AgentAwesomeAppController controller;
  final TaskMetadataSuggestion suggestion;

  /// Builds one inferred metadata suggestion row.
  @override
  Widget build(BuildContext context) {
    return _TaskGraphRow(
      icon: Icons.tune_outlined,
      title: 'Fill context metadata',
      subtitle: _metadataSuggestionSummary(suggestion),
      badges: <String>['Metadata', _formatTaskScore(suggestion.confidence)],
      actions: <Widget>[
        if (controller.primaryMemoryToolAvailable('apply_task_suggestion'))
          Tooltip(
            message: 'Accept suggestion',
            child: IconButton(
              onPressed: controller.tasksBusy
                  ? null
                  : () => unawaited(
                      controller.applyTaskSuggestionFromUi(suggestion.id),
                    ),
              icon: const Icon(Icons.check_circle_outline, size: 18),
            ),
          ),
        if (controller.primaryMemoryToolAvailable('dismiss_task_suggestion'))
          Tooltip(
            message: 'Dismiss suggestion',
            child: IconButton(
              onPressed: controller.tasksBusy
                  ? null
                  : () => unawaited(
                      controller.dismissTaskSuggestionFromUi(suggestion.id),
                    ),
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
      ],
    );
  }
}

class _TaskCommitmentSuggestionTile extends StatelessWidget {
  const _TaskCommitmentSuggestionTile({
    required this.controller,
    required this.suggestion,
  });

  final AgentAwesomeAppController controller;
  final TaskCommitmentSuggestion suggestion;

  /// Builds one inferred commitment suggestion row.
  @override
  Widget build(BuildContext context) {
    return _TaskGraphRow(
      icon: Icons.handshake_outlined,
      title: 'Create commitment',
      subtitle: _commitmentSuggestionSummary(suggestion),
      badges: <String>[
        'Commitment',
        if (suggestion.hardness.isNotEmpty) suggestion.hardness,
        _formatTaskScore(suggestion.confidence),
      ],
      actions: <Widget>[
        if (controller.primaryMemoryToolAvailable('apply_task_suggestion'))
          Tooltip(
            message: 'Accept suggestion',
            child: IconButton(
              onPressed: controller.tasksBusy
                  ? null
                  : () => unawaited(
                      controller.applyTaskSuggestionFromUi(suggestion.id),
                    ),
              icon: const Icon(Icons.check_circle_outline, size: 18),
            ),
          ),
        if (controller.primaryMemoryToolAvailable('dismiss_task_suggestion'))
          Tooltip(
            message: 'Dismiss suggestion',
            child: IconButton(
              onPressed: controller.tasksBusy
                  ? null
                  : () => unawaited(
                      controller.dismissTaskSuggestionFromUi(suggestion.id),
                    ),
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
      ],
    );
  }
}

/// _TaskConstellationEdgeInspector shows one selected projection relation.
class _TaskConstellationEdgeInspector extends StatelessWidget {
  const _TaskConstellationEdgeInspector({
    required this.controller,
    required this.edge,
  });

  final AgentAwesomeAppController controller;
  final TaskConstellationEdge edge;

  /// Builds read-only details for a selected constellation edge.
  @override
  Widget build(BuildContext context) {
    final explicit = _matchingExplicitRelation();
    final fromIsAnchor = _isConstellationAnchorEndpoint(edge.fromTaskId);
    final toIsAnchor = _isConstellationAnchorEndpoint(edge.toTaskId);
    final factRows = _graphFactMetadataRows(explicit);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _TaskPanelLabel('Relation Edge'),
                const SizedBox(height: 12),
                _TaskGraphRow(
                  icon: Icons.account_tree_outlined,
                  title: _taskLabel(edge.relationType),
                  subtitle: edge.explanation,
                  badges: <String>[
                    _edgeRoleLabel(),
                    if (edge.sourceKind.isNotEmpty) _taskLabel(edge.sourceKind),
                    _formatTaskScore(edge.confidence),
                    if (explicit != null || edge.id.isNotEmpty) 'Graph fact',
                  ],
                  actions: const <Widget>[],
                ),
                const Divider(height: 22),
                _TaskMetadataRow(
                  label: 'From',
                  value: _constellationEndpointLabel(
                    controller,
                    edge.fromTaskId,
                  ),
                ),
                _TaskMetadataRow(
                  label: 'To',
                  value: _constellationEndpointLabel(controller, edge.toTaskId),
                ),
                _TaskMetadataRow(
                  label: 'Relationship',
                  value: _taskLabel(edge.relationType),
                ),
                _TaskMetadataRow(label: 'Role', value: _edgeRoleLabel()),
                _TaskMetadataRow(
                  label: 'Confidence',
                  value: _formatTaskScore(edge.confidence),
                ),
                ...factRows,
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (!fromIsAnchor || !toIsAnchor)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                if (!fromIsAnchor)
                  OutlinedButton.icon(
                    onPressed: () => controller.selectTask(edge.fromTaskId),
                    icon: const Icon(Icons.arrow_back_outlined),
                    label: const Text('Open From Backlog'),
                  ),
                if (!toIsAnchor)
                  OutlinedButton.icon(
                    onPressed: () => controller.selectTask(edge.toTaskId),
                    icon: const Icon(Icons.arrow_forward_outlined),
                    label: const Text('Open To Backlog'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Returns the display role attached to this edge in the projection.
  String _edgeRoleLabel() {
    return edge.source.isEmpty ? 'Projected' : _taskLabel(edge.source);
  }

  /// Returns provenance and access metadata rows for the selected graph fact.
  List<Widget> _graphFactMetadataRows(TaskRelationRecord? explicit) {
    final rows = <Widget>[];
    final factSource = _edgeFactSource();
    final id = edge.id.isNotEmpty ? edge.id : explicit?.id ?? '';
    final actor = edge.actor.isNotEmpty ? edge.actor : explicit?.actor ?? '';
    final createdAt = edge.createdAt ?? explicit?.createdAt;
    final updatedAt = edge.updatedAt ?? explicit?.updatedAt;
    if (id.isNotEmpty) {
      rows.add(_TaskMetadataRow(label: 'Relation id', value: id));
    }
    if (factSource.isNotEmpty) {
      rows.add(_TaskMetadataRow(label: 'Provenance', value: factSource));
    }
    if (edge.sourceKind.isNotEmpty) {
      rows.add(_TaskMetadataRow(label: 'Source kind', value: edge.sourceKind));
    }
    if (edge.scope.isNotEmpty) {
      rows.add(_TaskMetadataRow(label: 'Scope', value: edge.scope));
    }
    if (edge.sensitivity.isNotEmpty) {
      rows.add(_TaskMetadataRow(label: 'Sensitivity', value: edge.sensitivity));
    }
    if (edge.evidenceIds.isNotEmpty) {
      rows.add(
        _TaskMetadataRow(label: 'Sources', value: edge.evidenceIds.join(', ')),
      );
    }
    if (actor.isNotEmpty) {
      rows.add(_TaskMetadataRow(label: 'Actor', value: actor));
    }
    if (createdAt != null) {
      rows.add(
        _TaskMetadataRow(
          label: 'Created',
          value: formatOptionalLocalDateTime(createdAt),
        ),
      );
    }
    if (updatedAt != null) {
      rows.add(
        _TaskMetadataRow(
          label: 'Updated',
          value: formatOptionalLocalDateTime(updatedAt),
        ),
      );
    }
    if (edge.confirmedAt != null) {
      rows.add(
        _TaskMetadataRow(
          label: 'Confirmed',
          value: formatOptionalLocalDateTime(edge.confirmedAt),
        ),
      );
    }
    if (edge.dismissedAt != null) {
      rows.add(
        _TaskMetadataRow(
          label: 'Dismissed',
          value: formatOptionalLocalDateTime(edge.dismissedAt),
        ),
      );
    }
    if (rows.isEmpty) {
      rows.add(
        const _TaskMetadataRow(
          label: 'Provenance',
          value: 'No graph fact metadata in current projection',
        ),
      );
    }
    return rows;
  }

  /// Returns the original graph fact source when role highlighting replaced it.
  String _edgeFactSource() {
    if (edge.factSource.isNotEmpty) {
      return edge.factSource;
    }
    return switch (edge.source) {
      'query_path' ||
      'critical_path' ||
      'dependency_context' ||
      'materialized_risk' ||
      'risk_context' ||
      'constellation_anchor' => '',
      _ => edge.source,
    };
  }

  /// Finds an explicit relation backing this projection edge, when present.
  TaskRelationRecord? _matchingExplicitRelation() {
    if (_isConstellationAnchorEndpoint(edge.fromTaskId) ||
        _isConstellationAnchorEndpoint(edge.toTaskId)) {
      return null;
    }
    for (final relation in controller.taskRelations) {
      final relationFrom = relation.fromTaskId;
      final relationTo = relation.toTaskId;
      final sameDirection =
          relationFrom == edge.fromTaskId && relationTo == edge.toTaskId;
      final reverseDirection =
          relationFrom == edge.toTaskId && relationTo == edge.fromTaskId;
      if ((sameDirection || reverseDirection) &&
          relation.relationType == edge.relationType) {
        return relation;
      }
    }
    return null;
  }
}

class _TaskRelationSuggestionTile extends StatelessWidget {
  const _TaskRelationSuggestionTile({
    required this.controller,
    required this.task,
    required this.suggestion,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;
  final TaskRelationSuggestion suggestion;

  /// Builds one inferred relation suggestion row.
  @override
  Widget build(BuildContext context) {
    final otherId = suggestion.fromTaskId == task.id
        ? suggestion.toTaskId
        : suggestion.fromTaskId;
    return _TaskGraphRow(
      icon: Icons.auto_awesome_outlined,
      title: _taskTitleFor(controller, otherId),
      subtitle: suggestion.explanation,
      badges: <String>[
        _taskLabel(suggestion.relationType),
        _formatTaskScore(suggestion.confidence),
      ],
      actions: <Widget>[
        if (controller.primaryMemoryToolAvailable('apply_task_suggestion'))
          Tooltip(
            message: 'Accept suggestion',
            child: IconButton(
              onPressed: controller.tasksBusy
                  ? null
                  : () => unawaited(
                      controller.applyTaskSuggestionFromUi(suggestion.id),
                    ),
              icon: const Icon(Icons.check_circle_outline, size: 18),
            ),
          ),
        if (controller.primaryMemoryToolAvailable('dismiss_task_suggestion'))
          Tooltip(
            message: 'Dismiss suggestion',
            child: IconButton(
              onPressed: controller.tasksBusy
                  ? null
                  : () => unawaited(
                      controller.dismissTaskSuggestionFromUi(suggestion.id),
                    ),
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
      ],
    );
  }
}

class _TaskRelationTile extends StatelessWidget {
  const _TaskRelationTile({
    required this.controller,
    required this.task,
    required this.relation,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;
  final TaskRelationRecord relation;

  /// Builds one explicit relation row.
  @override
  Widget build(BuildContext context) {
    final outgoing = relation.fromTaskId == task.id;
    final otherId = outgoing ? relation.toTaskId : relation.fromTaskId;
    final direction = outgoing ? 'To' : 'From';
    final canDeleteRelation = controller.primaryMemoryToolAvailable(
      'delete_task_relation',
    );
    return _TaskGraphRow(
      icon: outgoing ? Icons.arrow_forward : Icons.arrow_back,
      title: '$direction ${_taskTitleFor(controller, otherId)}',
      subtitle: relation.explanation,
      badges: <String>[
        _taskLabel(relation.relationType),
        relation.source.isEmpty ? 'Explicit' : _taskLabel(relation.source),
        _formatTaskScore(relation.confidence),
      ],
      actions: <Widget>[
        if (canDeleteRelation)
          Tooltip(
            message: 'Delete relation',
            child: IconButton(
              onPressed: controller.tasksBusy
                  ? null
                  : () => unawaited(_deleteRelation(context, relation)),
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ),
      ],
    );
  }

  Future<void> _deleteRelation(
    BuildContext context,
    TaskRelationRecord relation,
  ) async {
    if (!await _confirmTaskWrite(context, 'Delete this backlog relation?')) {
      return;
    }
    await controller.deleteTaskRelationFromUi(relation);
  }
}

class _TaskCommitmentTile extends StatelessWidget {
  const _TaskCommitmentTile({
    required this.controller,
    required this.task,
    required this.commitment,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;
  final TaskCommitment commitment;

  /// Builds one first-class commitment row.
  @override
  Widget build(BuildContext context) {
    final title = commitment.project.isNotEmpty
        ? commitment.project
        : commitment.domain.isNotEmpty
        ? commitment.domain
        : task.title;
    final subtitleParts = <String>[
      if (commitment.timeWindow.isNotEmpty) commitment.timeWindow,
      if (commitment.responsibility.isNotEmpty) commitment.responsibility,
      if (commitment.promiseSource.isNotEmpty) commitment.promiseSource,
      if (commitment.consequence.isNotEmpty) commitment.consequence,
    ];
    final canUpsertCommitment = controller.primaryMemoryToolAvailable(
      'upsert_commitment',
    );
    final canDeleteCommitment = controller.primaryMemoryToolAvailable(
      'delete_commitment',
    );
    return _TaskGraphRow(
      icon: Icons.handshake_outlined,
      title: title,
      subtitle: subtitleParts.join(' • '),
      badges: <String>[
        for (final person in commitment.people.take(3)) person,
        if (commitment.hardness.isNotEmpty) _taskLabel(commitment.hardness),
      ],
      actions: <Widget>[
        if (canUpsertCommitment)
          Tooltip(
            message: 'Edit commitment',
            child: IconButton(
              onPressed: controller.tasksBusy
                  ? null
                  : () => unawaited(
                      _showTaskCommitmentDialog(
                        context,
                        controller,
                        task,
                        commitment: commitment,
                      ),
                    ),
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          ),
        if (canDeleteCommitment)
          Tooltip(
            message: 'Delete commitment',
            child: IconButton(
              onPressed: controller.tasksBusy
                  ? null
                  : () => unawaited(_deleteCommitment(context, commitment)),
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ),
      ],
    );
  }

  Future<void> _deleteCommitment(
    BuildContext context,
    TaskCommitment commitment,
  ) async {
    if (!await _confirmTaskWrite(context, 'Delete this commitment?')) {
      return;
    }
    await controller.deleteTaskCommitmentFromUi(commitment);
  }
}

class _TaskGraphRow extends StatelessWidget {
  const _TaskGraphRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badges,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> badges;
  final List<Widget> actions;

  /// Builds a compact graph metadata row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ],
                if (badges.where((badge) => badge.isNotEmpty).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final badge in badges)
                          if (badge.isNotEmpty) _TaskBadge(label: badge),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          for (final action in actions) action,
        ],
      ),
    );
  }
}

/// _TaskMemoryLinkPanel links selected memory to a backlog item.
class _TaskMemoryLinkPanel extends StatelessWidget {
  const _TaskMemoryLinkPanel({
    required this.controller,
    required this.task,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;
  final String query;

  /// Builds the context memory-linking panel.
  @override
  Widget build(BuildContext context) {
    final selectedMemory = controller.selectedMemory;
    return _TaskMemoryLinkScaffold(
      selectedMemory: selectedMemory,
      links: _filteredLinks(task.memoryLinks, query),
      onLink: controller.tasksBusy || selectedMemory == null
          ? null
          : () => unawaited(controller.linkSelectedMemoryToTaskFromUi(task.id)),
      onUnlink: controller.primaryMemoryToolAvailable('unlink_task_memory')
          ? (link) => unawaited(
              controller.unlinkTaskMemoryFromUi(
                taskId: task.id,
                linkId: link.id,
              ),
            )
          : null,
    );
  }
}

class _TaskSelectedMemoryBlock extends StatelessWidget {
  const _TaskSelectedMemoryBlock({required this.memory});

  final MemoryRecord? memory;

  /// Builds a compact preview of the memory selected elsewhere in the app.
  @override
  Widget build(BuildContext context) {
    final record = memory;
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: record == null
          ? Text('No memory selected', style: TextStyle(color: colors.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 17,
                      color: colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        record.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (record.kind.isNotEmpty) _TaskBadge(label: record.kind),
                  ],
                ),
                if (record.summary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    record.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ],
              ],
            ),
    );
  }
}

class _TaskMemoryLinksBlock extends StatelessWidget {
  const _TaskMemoryLinksBlock({required this.links, required this.onUnlink});

  final List<TaskMemoryLink> links;
  final ValueChanged<TaskMemoryLink>? onUnlink;

  /// Builds memory link rows for context objects.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (links.isEmpty)
            Text('No linked memory', style: TextStyle(color: colors.muted))
          else
            for (final link in links)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            link.note.isEmpty ? link.relationship : link.note,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            link.memoryId.isEmpty
                                ? link.memoryEvidenceId
                                : link.memoryId,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    _TaskBadge(label: link.relationship),
                    const SizedBox(width: 6),
                    if (onUnlink != null)
                      Tooltip(
                        message: 'Unlink memory',
                        child: IconButton.outlined(
                          onPressed: () => onUnlink!(link),
                          icon: const Icon(Icons.link_off, size: 18),
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
