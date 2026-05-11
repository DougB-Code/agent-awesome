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
  _TaskStreamPreset _streamPreset = _TaskStreamPreset.custom;
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
            _streamPreset = _presetForAxes(_columnAxis, _rowAxis);
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
          preset: _streamPreset,
          rowAxis: effectiveRowAxis,
          columnAxis: effectiveColumnAxis,
          filters: effectiveFilters,
          filterModel: effectiveFilterModel,
          onPresetSelected: _applyPreset,
          onRowAxisChanged: (dimension) {
            setState(() {
              _rowAxis = dimension;
              _streamPreset = _presetForAxes(effectiveColumnAxis, _rowAxis);
            });
          },
          onColumnAxisChanged: (dimension) {
            setState(() {
              _columnAxis = dimension;
              _streamPreset = _presetForAxes(_columnAxis, effectiveRowAxis);
            });
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

  /// Applies a named stream question preset to the axis selectors.
  void _applyPreset(_TaskStreamPreset preset) {
    final axes = _streamPresetAxes[preset];
    if (axes == null) {
      setState(() => _streamPreset = preset);
      return;
    }
    setState(() {
      _streamPreset = preset;
      _columnAxis = axes.columnAxis;
      _rowAxis = axes.rowAxis;
    });
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
    required this.preset,
    required this.rowAxis,
    required this.columnAxis,
    required this.filters,
    required this.filterModel,
    required this.onPresetSelected,
    required this.onRowAxisChanged,
    required this.onColumnAxisChanged,
    required this.onFiltersChanged,
  });

  final _TaskStreamPreset preset;
  final TaskStreamAxisDimension rowAxis;
  final TaskStreamAxisDimension columnAxis;
  final TaskStreamFilterSelection filters;
  final TaskStreamFilterModel filterModel;
  final ValueChanged<_TaskStreamPreset> onPresetSelected;
  final ValueChanged<TaskStreamAxisDimension> onRowAxisChanged;
  final ValueChanged<TaskStreamAxisDimension> onColumnAxisChanged;
  final ValueChanged<TaskStreamFilterSelection> onFiltersChanged;

  /// Builds stream question shortcuts above axis and fact filters.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _TaskStreamPresetSelector(value: preset, onSelected: onPresetSelected),
        const SizedBox(height: 8),
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
            _TaskStreamEffortSummary(model: filterModel),
          ],
        ),
      ],
    );
  }
}

/// _TaskStreamPreset identifies one Stream question preset.
enum _TaskStreamPreset {
  /// Manual axis pairing outside the named question presets.
  custom,

  /// Due date by effort for workload scanning.
  dueEffort,

  /// Due date by spend for money scanning.
  dueSpend,

  /// Due date by context for context load scanning.
  contextLoad,

  /// Due date by person for responsibility load scanning.
  personLoad,

  /// Due date by project for project load scanning.
  projectLoad,
}

/// _TaskStreamPresetAxes stores the axes selected by one stream preset.
class _TaskStreamPresetAxes {
  const _TaskStreamPresetAxes({
    required this.columnAxis,
    required this.rowAxis,
  });

  /// Horizontal stream axis.
  final TaskStreamAxisDimension columnAxis;

  /// Vertical stream axis.
  final TaskStreamAxisDimension rowAxis;
}

const Map<_TaskStreamPreset, _TaskStreamPresetAxes> _streamPresetAxes =
    <_TaskStreamPreset, _TaskStreamPresetAxes>{
      _TaskStreamPreset.dueEffort: _TaskStreamPresetAxes(
        columnAxis: TaskStreamAxisDimension.due,
        rowAxis: TaskStreamAxisDimension.effort,
      ),
      _TaskStreamPreset.dueSpend: _TaskStreamPresetAxes(
        columnAxis: TaskStreamAxisDimension.due,
        rowAxis: TaskStreamAxisDimension.spend,
      ),
      _TaskStreamPreset.contextLoad: _TaskStreamPresetAxes(
        columnAxis: TaskStreamAxisDimension.due,
        rowAxis: TaskStreamAxisDimension.context,
      ),
      _TaskStreamPreset.personLoad: _TaskStreamPresetAxes(
        columnAxis: TaskStreamAxisDimension.due,
        rowAxis: TaskStreamAxisDimension.person,
      ),
      _TaskStreamPreset.projectLoad: _TaskStreamPresetAxes(
        columnAxis: TaskStreamAxisDimension.due,
        rowAxis: TaskStreamAxisDimension.project,
      ),
    };

/// Returns the preset represented by an axis pair, or custom when unmatched.
_TaskStreamPreset _presetForAxes(
  TaskStreamAxisDimension columnAxis,
  TaskStreamAxisDimension rowAxis,
) {
  for (final entry in _streamPresetAxes.entries) {
    if (entry.value.columnAxis == columnAxis &&
        entry.value.rowAxis == rowAxis) {
      return entry.key;
    }
  }
  return _TaskStreamPreset.custom;
}

class _TaskStreamPresetSelector extends StatelessWidget {
  const _TaskStreamPresetSelector({
    required this.value,
    required this.onSelected,
  });

  final _TaskStreamPreset value;
  final ValueChanged<_TaskStreamPreset> onSelected;

  /// Builds one-click question presets for the Stream view.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SegmentedButton<_TaskStreamPreset>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: WidgetStatePropertyAll(
          BorderSide(color: colors.border.withValues(alpha: 0.85)),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.greenSoft;
          }
          return colors.surface;
        }),
        foregroundColor: WidgetStatePropertyAll(colors.ink),
      ),
      segments: <ButtonSegment<_TaskStreamPreset>>[
        for (final preset in _TaskStreamPreset.values)
          ButtonSegment<_TaskStreamPreset>(
            value: preset,
            icon: Icon(_streamPresetIcon(preset), size: 15),
            tooltip: _streamPresetQuestion(preset),
            label: Text(_streamPresetLabel(preset)),
          ),
      ],
      selected: <_TaskStreamPreset>{value},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          onSelected(selection.first);
        }
      },
    );
  }
}

/// Returns the short label for one stream question preset.
String _streamPresetLabel(_TaskStreamPreset preset) {
  return switch (preset) {
    _TaskStreamPreset.custom => 'Custom',
    _TaskStreamPreset.dueEffort => 'Effort',
    _TaskStreamPreset.dueSpend => 'Spend',
    _TaskStreamPreset.contextLoad => 'Context',
    _TaskStreamPreset.personLoad => 'People',
    _TaskStreamPreset.projectLoad => 'Projects',
  };
}

/// Returns the tooltip question for one stream preset.
String _streamPresetQuestion(_TaskStreamPreset preset) {
  return switch (preset) {
    _TaskStreamPreset.custom => 'Use the selected axes.',
    _TaskStreamPreset.dueEffort => 'How much effort sits near each due date?',
    _TaskStreamPreset.dueSpend => 'Where does spend land against due dates?',
    _TaskStreamPreset.contextLoad => 'Which contexts carry dated work?',
    _TaskStreamPreset.personLoad => 'Who has dated work?',
    _TaskStreamPreset.projectLoad => 'Which projects carry dated work?',
  };
}

/// Returns the icon for one stream preset.
IconData _streamPresetIcon(_TaskStreamPreset preset) {
  return switch (preset) {
    _TaskStreamPreset.custom => Icons.tune,
    _TaskStreamPreset.dueEffort => Icons.speed,
    _TaskStreamPreset.dueSpend => Icons.price_change_outlined,
    _TaskStreamPreset.contextLoad => Icons.category_outlined,
    _TaskStreamPreset.personLoad => Icons.person_outline,
    _TaskStreamPreset.projectLoad => Icons.folder_copy_outlined,
  };
}

/// Formats stream effort minutes for compact filter summaries.
String _formatStreamEffort(int minutes) {
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
  return '${model.taskCount} items · ${_formatStreamEffort(model.estimateMinutes)}';
}

/// Returns compact option metadata for one stream filter value.
String _streamFilterOptionDetail(TaskStreamFilterOption option) {
  return '${option.taskCount} · ${_formatStreamEffort(option.estimateMinutes)}';
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
    TaskStreamAxisDimension.context => 'All contexts',
    TaskStreamAxisDimension.project => 'All projects',
    TaskStreamAxisDimension.view => 'All views',
    TaskStreamAxisDimension.person => 'All people',
    TaskStreamAxisDimension.effort => 'All effort',
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

class _TaskStreamEffortSummary extends StatelessWidget {
  const _TaskStreamEffortSummary({required this.model});

  final TaskStreamFilterModel model;

  /// Builds the aggregate effort answer for the active stream filters.
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
            '${model.taskCount} items · ${_formatStreamEffort(model.estimateMinutes)}',
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
