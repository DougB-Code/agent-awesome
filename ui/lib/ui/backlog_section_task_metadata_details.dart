/// Backlog selected-task metadata and WBS detail widgets.
part of 'backlog_section.dart';

class _TaskMetadataBlock extends StatelessWidget {
  const _TaskMetadataBlock({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  /// Builds context metadata details.
  @override
  Widget build(BuildContext context) {
    return PanelSectionBlock.gradient(
      title: 'Metadata',
      trailing: Tooltip(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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
    return PanelSectionBlock.gradient(
      title: 'WBS',
      trailing: Tooltip(
        message: 'Edit WBS',
        child: IconButton(
          onPressed: controller.tasksBusy
              ? null
              : () => unawaited(_showTaskWbsDialog(context, controller, task)),
          icon: const Icon(Icons.account_tree_outlined, size: 18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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
