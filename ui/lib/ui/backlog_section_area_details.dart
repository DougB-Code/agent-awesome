/// Area-aware right-side detail panels for Backlog command areas.
part of 'backlog_section.dart';

class _BacklogWbsDetailPanel extends StatelessWidget {
  const _BacklogWbsDetailPanel({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds WBS-specific right pane content.
  @override
  Widget build(BuildContext context) {
    final tasks =
        controller.workspace.tasks
            .where((task) => taskWbsHasContent(task.workBreakdown))
            .toList()
          ..sort(compareWorkspaceTasksByWbs);
    final roots = buildTaskWbsTree(tasks);
    return _BacklogDetailScroll(
      children: <Widget>[
        PanelSectionBlock.gradient(
          title: 'Work Breakdown',
          child: _BacklogMetricGrid(
            metrics: <_BacklogMetric>[
              _BacklogMetric('Roots', roots.length.toString()),
              _BacklogMetric('Packages', tasks.length.toString()),
              _BacklogMetric(
                'Estimate',
                _formatBacklogMinutes(_taskMinutes(tasks)),
              ),
              _BacklogMetric('Spend', _formatBacklogWbsSpend(tasks)),
            ],
          ),
        ),
        _BacklogSelectedTaskSection(controller: controller),
        if (tasks.isNotEmpty)
          _BacklogTaskListSection(
            title: 'Work Packages',
            tasks: tasks.take(6).toList(),
            controller: controller,
          ),
      ],
    );
  }
}

class _BacklogConstellationDetailPanel extends StatelessWidget {
  const _BacklogConstellationDetailPanel({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds constellation-specific right pane content.
  @override
  Widget build(BuildContext context) {
    final projection = controller.taskConstellationProjection;
    return _BacklogDetailScroll(
      children: <Widget>[
        PanelSectionBlock.gradient(
          title: 'Constellation Graph',
          child: _BacklogMetricGrid(
            metrics: <_BacklogMetric>[
              _BacklogMetric('Nodes', projection.nodes.length.toString()),
              _BacklogMetric('Edges', projection.edges.length.toString()),
              _BacklogMetric(
                'Contexts',
                projection.nodes
                    .map((node) => node.category.trim())
                    .where((value) => value.isNotEmpty)
                    .toSet()
                    .length
                    .toString(),
              ),
              _BacklogMetric(
                'People',
                projection.nodes
                    .map((node) => node.owner.trim())
                    .where((value) => value.isNotEmpty)
                    .toSet()
                    .length
                    .toString(),
              ),
            ],
          ),
        ),
        _BacklogSelectedTaskSection(controller: controller),
      ],
    );
  }
}

class _BacklogCaptureDetailPanel extends StatelessWidget {
  const _BacklogCaptureDetailPanel({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds capture-specific right pane context.
  @override
  Widget build(BuildContext context) {
    final memory = controller.selectedMemory;
    return _BacklogDetailScroll(
      children: <Widget>[
        PanelSectionBlock.gradient(
          title: 'Capture Context',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _TaskMetadataRow(
                label: 'Tasks',
                value: controller.workspace.tasks.length.toString(),
              ),
              _TaskMetadataRow(
                label: 'Open',
                value: controller.workspace.tasks
                    .where((task) => task.status == 'open')
                    .length
                    .toString(),
              ),
              _TaskMetadataRow(
                label: 'Selected memory',
                value: memory?.title ?? '',
              ),
            ],
          ),
        ),
        if (memory != null)
          PanelSectionBlock.gradient(
            title: 'Memory To Link',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  memory.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(memory.summary),
              ],
            ),
          ),
        _BacklogSelectedTaskSection(controller: controller),
      ],
    );
  }
}

class _BacklogDetailScroll extends StatelessWidget {
  const _BacklogDetailScroll({required this.children});

  final List<Widget> children;

  /// Builds the standard scroll container for area detail panes.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 14),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _BacklogSelectedTaskSection extends StatelessWidget {
  const _BacklogSelectedTaskSection({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds a compact selected-task summary shared by projection details.
  @override
  Widget build(BuildContext context) {
    final task = controller.selectedTask;
    if (task == null) {
      return const PanelEmptyBlock(label: 'No backlog item selected');
    }
    return PanelSectionBlock.gradient(
      title: 'Selected Task',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(task.title, style: const TextStyle(fontWeight: FontWeight.w900)),
          if (task.description.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              task.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              PanelBadge(label: _taskLabel(task.status)),
              PanelBadge(label: _taskLabel(task.priority)),
              if (task.project.trim().isNotEmpty)
                PanelBadge(label: task.project.trim()),
              for (final topic in task.topics.take(3)) PanelBadge(label: topic),
            ],
          ),
          const SizedBox(height: 12),
          _TaskMetadataRow(
            label: 'Due',
            value: formatOptionalLocalDate(task.dueAt),
          ),
          _TaskMetadataRow(
            label: 'Scheduled',
            value: formatOptionalLocalDate(task.scheduledAt),
          ),
        ],
      ),
    );
  }
}

class _BacklogTaskListSection extends StatelessWidget {
  const _BacklogTaskListSection({
    required this.title,
    required this.tasks,
    required this.controller,
  });

  final String title;
  final List<WorkspaceTask> tasks;
  final AgentAwesomeAppController controller;

  /// Builds a compact task list for an area detail pane.
  @override
  Widget build(BuildContext context) {
    return PanelSectionBlock.gradient(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final task in tasks)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => controller.selectTask(task.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.task_alt_outlined,
                      size: 17,
                      color: context.agentAwesomeColors.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _taskLabel(task.status),
                      style: TextStyle(
                        color: context.agentAwesomeColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BacklogMetricGrid extends StatelessWidget {
  const _BacklogMetricGrid({required this.metrics});

  final List<_BacklogMetric> metrics;

  /// Builds a responsive grid of projection metrics.
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final metric in metrics) _BacklogMetricTile(metric: metric),
      ],
    );
  }
}

class _BacklogMetricTile extends StatelessWidget {
  const _BacklogMetricTile({required this.metric});

  final _BacklogMetric metric;

  /// Builds one compact metric tile.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      width: 128,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            metric.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            metric.value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _BacklogMetric {
  const _BacklogMetric(this.label, this.value);

  /// Metric label.
  final String label;

  /// Metric display value.
  final String value;
}

/// Returns total task estimate minutes.
int _taskMinutes(List<WorkspaceTask> tasks) {
  return tasks.fold<int>(0, (total, task) => total + task.estimateMinutes);
}

/// Returns compact total WBS spend for a task collection.
String _formatBacklogWbsSpend(List<WorkspaceTask> tasks) {
  var total = 0;
  var currency = '';
  for (final task in tasks) {
    final workBreakdown = task.workBreakdown;
    total += workBreakdown.estimatedCostCents;
    if (currency.isEmpty && workBreakdown.costCurrency.trim().isNotEmpty) {
      currency = workBreakdown.costCurrency.trim();
    }
  }
  if (total <= 0) {
    return '-';
  }
  return formatMinorUnitSpend(total, currency);
}

/// Formats minutes as a compact duration.
String _formatBacklogMinutes(int minutes) {
  if (minutes <= 0) {
    return '0m';
  }
  if (minutes < 60) {
    return '${minutes}m';
  }
  return '${(minutes / 60).toStringAsFixed(1)}h';
}
