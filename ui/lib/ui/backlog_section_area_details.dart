/// Area-aware right-side detail panels for Backlog command areas.
part of 'backlog_section.dart';

class _BacklogStreamDetailPanel extends StatelessWidget {
  const _BacklogStreamDetailPanel({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds stream-specific right pane content.
  @override
  Widget build(BuildContext context) {
    final projection = controller.taskStreamProjection;
    final cards = _backlogStreamCards(projection);
    final taskIds = cards.map((card) => card.taskId).toSet();
    return _BacklogDetailScroll(
      children: <Widget>[
        PanelSectionBlock.gradient(
          title: 'Stream Projection',
          child: _BacklogMetricGrid(
            metrics: <_BacklogMetric>[
              _BacklogMetric('Lanes', projection.lanes.length.toString()),
              _BacklogMetric('Tasks', taskIds.length.toString()),
              _BacklogMetric('Links', projection.links.length.toString()),
              _BacklogMetric(
                'Effort',
                _formatBacklogMinutes(_streamEstimateMinutes(cards)),
              ),
            ],
          ),
        ),
        _BacklogSelectedTaskSection(controller: controller),
        if (cards.isNotEmpty)
          _BacklogTaskListSection(
            title: 'Largest Stream Items',
            tasks: _streamLargestTasks(controller, cards),
            controller: controller,
          ),
      ],
    );
  }
}

class _BacklogTerrainDetailPanel extends StatelessWidget {
  const _BacklogTerrainDetailPanel({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds terrain-specific right pane content.
  @override
  Widget build(BuildContext context) {
    final projection = controller.priorityTerrainProjection;
    final selectedPoint = _terrainPointForSelectedTask(controller, projection);
    final preset = TaskInsightPresetRegistry.selectedTerrainPreset(
      controller.taskInsightPresetId,
    );
    final insightTasks = _backlogTerrainInsightTasks(controller, preset.id);
    return _BacklogDetailScroll(
      children: <Widget>[
        PanelSectionBlock.gradient(
          title: 'Terrain Projection',
          child: _BacklogMetricGrid(
            metrics: <_BacklogMetric>[
              _BacklogMetric('Tasks', projection.points.length.toString()),
              _BacklogMetric('Zones', projection.bands.length.toString()),
              _BacklogMetric(
                'Avg value',
                _formatBacklogScore(
                  _averageTerrainScore(
                    projection.points.map((point) => point.valueScore),
                  ),
                ),
              ),
              _BacklogMetric(
                'Avg risk',
                _formatBacklogScore(
                  _averageTerrainScore(
                    projection.points.map((point) => point.riskScore),
                  ),
                ),
              ),
            ],
          ),
        ),
        PanelSectionBlock.gradient(
          title: 'Selected Insight',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                preset.label,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(preset.question),
            ],
          ),
        ),
        if (selectedPoint != null)
          PanelSectionBlock.gradient(
            title: 'Selected Terrain Point',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _TaskMetadataRow(
                  label: 'Zone',
                  value: selectedPoint.terrainZone,
                ),
                _TaskMetadataRow(
                  label: 'Next',
                  value: selectedPoint.recommendedNextStep,
                ),
                _TaskMetadataRow(
                  label: 'Confidence',
                  value: _formatBacklogScore(selectedPoint.confidence),
                ),
              ],
            ),
          ),
        _BacklogSelectedTaskSection(controller: controller),
        if (preset.id != TaskInsightIds.all && insightTasks.isNotEmpty)
          _BacklogTaskListSection(
            title: 'Insight Tasks',
            tasks: insightTasks.take(6).toList(),
            controller: controller,
          ),
      ],
    );
  }
}

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
                'Effort',
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

/// Returns all stream cards in lane order.
List<TaskStreamCard> _backlogStreamCards(TaskStreamProjection projection) {
  return <TaskStreamCard>[for (final lane in projection.lanes) ...lane.cards];
}

/// Returns the total estimated stream effort in minutes.
int _streamEstimateMinutes(List<TaskStreamCard> cards) {
  return cards.fold<int>(0, (total, card) => total + card.estimateMinutes);
}

/// Returns stream tasks ordered by estimate for compact detail lists.
List<WorkspaceTask> _streamLargestTasks(
  AgentAwesomeAppController controller,
  List<TaskStreamCard> cards,
) {
  final ordered = <TaskStreamCard>[...cards]
    ..sort(
      (left, right) => right.estimateMinutes.compareTo(left.estimateMinutes),
    );
  final tasksById = <String, WorkspaceTask>{
    for (final task in controller.workspace.tasks) task.id: task,
  };
  return <WorkspaceTask>[
    for (final card in ordered.take(6))
      if (tasksById[card.taskId] != null) tasksById[card.taskId]!,
  ];
}

/// Returns the selected task's terrain point when visible.
PriorityTerrainPoint? _terrainPointForSelectedTask(
  AgentAwesomeAppController controller,
  PriorityTerrainProjection projection,
) {
  final selectedTaskId = controller.selectedGraphTaskId;
  if (selectedTaskId.isEmpty) {
    return null;
  }
  for (final point in projection.points) {
    if (point.taskId == selectedTaskId) {
      return point;
    }
  }
  return null;
}

/// Returns concrete workspace tasks matching the selected terrain insight.
List<WorkspaceTask> _backlogTerrainInsightTasks(
  AgentAwesomeAppController controller,
  String insightId,
) {
  if (insightId == TaskInsightIds.all) {
    return const <WorkspaceTask>[];
  }
  final tasksById = <String, WorkspaceTask>{
    for (final task in controller.workspace.tasks) task.id: task,
  };
  return <WorkspaceTask>[
    for (final candidate in controller.taskInsightIndex.tasksForInsight(
      insightId,
    ))
      if (tasksById[candidate.taskId] != null) tasksById[candidate.taskId]!,
  ];
}

/// Returns an average score from normalized terrain values.
double _averageTerrainScore(Iterable<double> values) {
  var count = 0;
  var total = 0.0;
  for (final value in values) {
    count++;
    total += value;
  }
  return count == 0 ? 0 : total / count;
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

/// Formats normalized scores as percentages.
String _formatBacklogScore(double value) {
  return '${(value.clamp(0, 1) * 100).round()}%';
}
