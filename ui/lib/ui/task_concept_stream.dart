/// Task stream projection widgets and controls.
part of 'task_concept_views.dart';

class _TaskStreamView extends StatefulWidget {
  const _TaskStreamView({required this.controller});

  final AgentAwesomeAppController controller;

  /// Creates state for stream axis selection.
  @override
  State<_TaskStreamView> createState() => _TaskStreamViewState();
}

class _TaskStreamViewState extends State<_TaskStreamView> {
  TaskStreamAxisDimension _columnAxis = TaskStreamAxisDimension.due;
  TaskStreamAxisDimension _rowAxis = TaskStreamAxisDimension.project;
  TaskStreamFilterSelection _streamFilters = const TaskStreamFilterSelection();

  /// Builds the task-fact stream projection.
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final projection = controller.taskStreamProjection;
    final sourceHasCards = projection.lanes.any(
      (lane) => lane.cards.isNotEmpty,
    );
    final filterModel = TaskStreamFilterProjector.build(
      projection,
      selection: _streamFilters,
    );
    final effectiveFilters = TaskStreamFilterProjector.effectiveSelection(
      _streamFilters,
      filterModel,
    );
    final effectiveFilterModel = effectiveFilters == _streamFilters
        ? filterModel
        : TaskStreamFilterProjector.build(
            projection,
            selection: effectiveFilters,
          );
    if (effectiveFilters != _streamFilters) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _streamFilters = effectiveFilters);
        }
      });
    }
    final effectiveColumnAxis = _effectiveStreamAxis(
      _columnAxis,
      TaskStreamAxisProjector.columnDimensions,
      TaskStreamAxisDimension.due,
    );
    final effectiveRowAxis = _effectiveStreamAxis(
      _rowAxis,
      TaskStreamAxisProjector.rowDimensions,
      TaskStreamAxisDimension.project,
    );
    if (effectiveColumnAxis != _columnAxis || effectiveRowAxis != _rowAxis) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _columnAxis = effectiveColumnAxis;
            _rowAxis = effectiveRowAxis;
          });
        }
      });
    }
    final axisView = TaskStreamAxisProjector.project(
      effectiveFilterModel.filteredProjection,
      columnAxis: effectiveColumnAxis,
      rowAxis: effectiveRowAxis,
    );
    if (!sourceHasCards) {
      return PanelEmptyBlock(
        label: _emptyProjectionLabel(
          controller,
          'No backlog stream projection yet',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TaskStreamControls(
          rowAxis: effectiveRowAxis,
          columnAxis: effectiveColumnAxis,
          filters: effectiveFilters,
          filterModel: effectiveFilterModel,
          onRowAxisChanged: (dimension) {
            setState(() => _rowAxis = dimension);
          },
          onColumnAxisChanged: (dimension) {
            setState(() => _columnAxis = dimension);
          },
          onFiltersChanged: (filters) {
            setState(() => _streamFilters = filters);
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: axisView.lanes.every((lane) => lane.cards.isEmpty)
              ? const PanelEmptyBlock(label: 'No stream backlog items match')
              : TaskStreamCanvas(
                  lanes: axisView.lanes,
                  links: effectiveFilterModel.filteredProjection.links,
                  rowAxis: axisView.rowAxis,
                  rowBucketsByTaskId: axisView.rowBucketsByTaskId,
                  controller: controller,
                ),
        ),
      ],
    );
  }
}

/// Returns a valid Stream axis after a hot reload or preset change.
TaskStreamAxisDimension _effectiveStreamAxis(
  TaskStreamAxisDimension selected,
  List<TaskStreamAxisDimension> available,
  TaskStreamAxisDimension fallback,
) {
  return available.contains(selected) ? selected : fallback;
}

class _TaskStreamControls extends StatelessWidget {
  const _TaskStreamControls({
    required this.rowAxis,
    required this.columnAxis,
    required this.filters,
    required this.filterModel,
    required this.onRowAxisChanged,
    required this.onColumnAxisChanged,
    required this.onFiltersChanged,
  });

  final TaskStreamAxisDimension rowAxis;
  final TaskStreamAxisDimension columnAxis;
  final TaskStreamFilterSelection filters;
  final TaskStreamFilterModel filterModel;
  final ValueChanged<TaskStreamAxisDimension> onRowAxisChanged;
  final ValueChanged<TaskStreamAxisDimension> onColumnAxisChanged;
  final ValueChanged<TaskStreamFilterSelection> onFiltersChanged;

  /// Builds axis and fact filters for the Stream projection.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _TaskStreamAxisSelector(
              tooltip: 'Vertical axis',
              icon: Icons.swap_vert,
              value: rowAxis,
              dimensions: TaskStreamAxisProjector.rowDimensions,
              onChanged: onRowAxisChanged,
            ),
            _TaskStreamAxisSelector(
              tooltip: 'Horizontal axis',
              icon: Icons.swap_horiz,
              value: columnAxis,
              dimensions: TaskStreamAxisProjector.columnDimensions,
              onChanged: onColumnAxisChanged,
            ),
            TaskFilterMenuButton(
              activeCount: _streamFilterActiveCount(filters),
              summary: _streamFilterSummary(filterModel),
              onClear: filters.hasActiveFilters
                  ? () => onFiltersChanged(const TaskStreamFilterSelection())
                  : null,
              sections: <TaskFilterMenuSection>[
                for (final dimension in TaskStreamFilterProjector.dimensions)
                  TaskFilterMenuSection(
                    title: TaskStreamAxisProjector.dimensionLabel(dimension),
                    icon: TaskStreamAxisProjector.dimensionIcon(dimension),
                    allLabel: _streamFilterAllLabel(dimension),
                    selectedValue: filters.valueFor(dimension),
                    options: <TaskFilterMenuOption>[
                      for (final option in filterModel.optionsFor(dimension))
                        TaskFilterMenuOption(
                          value: option.value,
                          label: option.label,
                          detail: _streamFilterOptionDetail(option),
                        ),
                    ],
                    onChanged: (value) {
                      onFiltersChanged(filters.withFilter(dimension, value));
                    },
                  ),
              ],
            ),
            _TaskStreamEstimateSummary(model: filterModel),
          ],
        ),
      ],
    );
  }
}

/// Formats stream estimate minutes for compact filter summaries.
String _formatStreamEstimate(int minutes) {
  if (minutes <= 0) {
    return '0m';
  }
  if (minutes < 60) {
    return '${minutes}m';
  }
  return '${(minutes / 60).toStringAsFixed(1)}h';
}

/// Returns the number of active stream filters.
int _streamFilterActiveCount(TaskStreamFilterSelection filters) {
  return filters.activeCount;
}

/// Returns compact dropdown summary text for active stream filters.
String _streamFilterSummary(TaskStreamFilterModel model) {
  return '${model.taskCount} items · ${_formatStreamEstimate(model.estimateMinutes)}';
}

/// Returns compact option metadata for one stream filter value.
String _streamFilterOptionDetail(TaskStreamFilterOption option) {
  return '${option.taskCount} · ${_formatStreamEstimate(option.estimateMinutes)}';
}

/// Returns the unfiltered label for one stream filter dimension.
String _streamFilterAllLabel(TaskStreamAxisDimension dimension) {
  return switch (dimension) {
    TaskStreamAxisDimension.time => 'All times',
    TaskStreamAxisDimension.due => 'All due dates',
    TaskStreamAxisDimension.scheduled => 'All schedules',
    TaskStreamAxisDimension.attention => 'All attention',
    TaskStreamAxisDimension.status => 'All statuses',
    TaskStreamAxisDimension.priority => 'All priorities',
    TaskStreamAxisDimension.project => 'All projects',
    TaskStreamAxisDimension.person => 'All people',
    TaskStreamAxisDimension.estimate => 'All estimates',
    TaskStreamAxisDimension.spend => 'All spend',
    TaskStreamAxisDimension.blockers => 'All blockers',
  };
}

class _TaskStreamAxisSelector extends StatelessWidget {
  const _TaskStreamAxisSelector({
    required this.tooltip,
    required this.icon,
    required this.value,
    required this.dimensions,
    required this.onChanged,
  });

  final String tooltip;
  final IconData icon;
  final TaskStreamAxisDimension value;
  final List<TaskStreamAxisDimension> dimensions;
  final ValueChanged<TaskStreamAxisDimension> onChanged;

  /// Builds one compact axis selector for a stream projection.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          gradient: context.agentAwesomeControlGradient,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 15, color: colors.green),
              const SizedBox(width: 6),
              DropdownButton<TaskStreamAxisDimension>(
                value: value,
                borderRadius: BorderRadius.circular(8),
                dropdownColor: colors.surface,
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: colors.muted,
                ),
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                items: <DropdownMenuItem<TaskStreamAxisDimension>>[
                  for (final dimension in dimensions)
                    DropdownMenuItem<TaskStreamAxisDimension>(
                      value: dimension,
                      child: Text(
                        TaskStreamAxisProjector.dimensionLabel(dimension),
                      ),
                    ),
                ],
                onChanged: (dimension) {
                  if (dimension != null) {
                    onChanged(dimension);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskStreamEstimateSummary extends StatelessWidget {
  const _TaskStreamEstimateSummary({required this.model});

  final TaskStreamFilterModel model;

  /// Builds the aggregate estimate answer for the active stream filters.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SizedBox(
      height: 34,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.timer_outlined, size: 15, color: colors.muted),
          const SizedBox(width: 6),
          Text(
            '${model.taskCount} items · ${_formatStreamEstimate(model.estimateMinutes)}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
