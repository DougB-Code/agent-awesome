/// Priority terrain projection widgets and filters.
part of 'task_concept_views.dart';

class _PriorityTerrainView extends StatefulWidget {
  const _PriorityTerrainView({required this.controller});

  final AgentAwesomeAppController controller;

  /// Creates state for terrain display filtering.
  @override
  State<_PriorityTerrainView> createState() => _PriorityTerrainViewState();
}

/// Stores terrain insight mode and area-overlay state.
class _PriorityTerrainViewState extends State<_PriorityTerrainView> {
  TaskTerrainInsightMode _insightMode = TaskTerrainInsightMode.priorityFocus;
  TaskTerrainFilterSelection _filterSelection =
      const TaskTerrainFilterSelection();
  bool _filtersOpen = false;
  Set<String> _revealedTerrainTaskIds = const <String>{};

  /// Builds the priority terrain projection.
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final insightProjection = TaskInsightProjectionAdapters.terrain(
      controller.taskInsightIndex,
      mode: _insightMode,
    );
    final projection = insightProjection.points.isEmpty
        ? controller.priorityTerrainProjection
        : insightProjection;
    if (projection.points.isEmpty) {
      return PanelEmptyBlock(
        label: _emptyProjectionLabel(
          controller,
          _emptyTerrainLabel(_insightMode),
        ),
      );
    }
    final lens = _TerrainInsightLens.fromController(controller);
    final filterModel = TaskTerrainFilterProjector.build(
      streamProjection: controller.taskStreamProjection,
      terrainProjection: projection,
    );
    final selection = _effectiveTerrainFilterSelection(filterModel);
    final filteredProjection = filterModel.apply(projection, selection);
    final filterControls = _buildTerrainFilterControls(filterModel, selection);
    final activeFilterCount = _activeTerrainFilterCount(selection);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ProjectionToolbar(
          left: <Widget>[
            _TerrainInsightModeSelector(
              value: _insightMode,
              onChanged: (mode) {
                setState(() {
                  _insightMode = mode;
                  _filterSelection = const TaskTerrainFilterSelection();
                  _revealedTerrainTaskIds = const <String>{};
                });
              },
            ),
            _TerrainInsightPresetMenu(controller: controller),
            _TerrainFiltersButton(
              activeCount: activeFilterCount,
              open: _filtersOpen,
              onTap: () {
                setState(() {
                  _filtersOpen = !_filtersOpen;
                });
              },
            ),
            if (activeFilterCount > 0)
              _TerrainClearFiltersButton(
                onTap: () {
                  setState(() {
                    _filterSelection = const TaskTerrainFilterSelection();
                    _revealedTerrainTaskIds = const <String>{};
                  });
                },
              ),
          ],
          right: const <Widget>[],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filteredProjection.points.isEmpty
              ? const PanelEmptyBlock(
                  label: 'No terrain items match these overlays',
                )
              : PanelSectionBlock(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final layout = TaskTerrainLayout.build(
                        filteredProjection,
                        constraints.biggest,
                        mode: TaskTerrainViewMode.all,
                      );
                      final selectedTaskId = controller.selectedGraphTaskId;
                      return Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _TerrainPainter(
                                layout,
                                context.agentAwesomeColors,
                              ),
                            ),
                          ),
                          for (final card in layout.cards)
                            if (_revealedTerrainTaskIds.contains(
                              card.point.taskId,
                            ))
                              _PositionedTerrainCard(
                                placement: card,
                                selected: selectedTaskId == card.point.taskId,
                                lens: lens,
                                onTap: () =>
                                    controller.selectTask(card.point.taskId),
                              ),
                          for (final cluster in layout.clusters)
                            _PositionedTerrainCluster(
                              cluster: cluster,
                              expanded: _isTerrainClusterRevealed(cluster),
                              lens: lens,
                              onTap: () {
                                _toggleTerrainReveal(
                                  cluster.points.map((point) => point.taskId),
                                  selectTaskId: cluster.points.first.taskId,
                                );
                              },
                            ),
                          for (final pin in layout.pins)
                            _PositionedTerrainPin(
                              pin: pin,
                              selected: selectedTaskId == pin.point.taskId,
                              expanded: _revealedTerrainTaskIds.contains(
                                pin.point.taskId,
                              ),
                              lens: lens,
                              onTap: () {
                                _toggleTerrainReveal(<String>[
                                  pin.point.taskId,
                                ], selectTaskId: pin.point.taskId);
                              },
                            ),
                          if (_filtersOpen)
                            _TerrainFilterDrawer(
                              controls: filterControls,
                              activeCount: activeFilterCount,
                              onClear: activeFilterCount == 0
                                  ? null
                                  : () {
                                      setState(() {
                                        _filterSelection =
                                            const TaskTerrainFilterSelection();
                                        _revealedTerrainTaskIds =
                                            const <String>{};
                                      });
                                    },
                              onClose: () {
                                setState(() {
                                  _filtersOpen = false;
                                });
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// Builds area overlay controls for the active terrain projection.
  List<Widget> _buildTerrainFilterControls(
    TaskTerrainFilterModel model,
    TaskTerrainFilterSelection selection,
  ) {
    final controls = <Widget>[];
    for (final dimension in TaskTerrainFilterProjector.overlayDimensions) {
      final options =
          model.areaOptionsByDimension[dimension] ??
          const <TaskTerrainFilterOption>[];
      if (!TaskTerrainFilterProjector.hasNarrowingOptions(options)) {
        continue;
      }
      controls.add(
        _TerrainFilterSelector(
          label: TaskStreamAxisProjector.dimensionLabel(dimension),
          value: selection.valueForAreaDimension(dimension),
          options: options,
          onChanged: (value) {
            setState(() {
              _filterSelection = _filterSelection.withAreaFilter(
                dimension,
                value,
              );
              _revealedTerrainTaskIds = const <String>{};
            });
          },
        ),
      );
    }
    return controls;
  }

  /// Returns the active terrain overlays that still exist in the current data.
  TaskTerrainFilterSelection _effectiveTerrainFilterSelection(
    TaskTerrainFilterModel model,
  ) {
    var next = const TaskTerrainFilterSelection();
    for (final dimension in TaskTerrainFilterProjector.overlayDimensions) {
      final value = _filterSelection.valueForAreaDimension(dimension);
      final options =
          model.areaOptionsByDimension[dimension] ??
          const <TaskTerrainFilterOption>[];
      if (_hasTerrainOption(options, value)) {
        next = next.withAreaFilter(dimension, value);
      }
    }
    return next;
  }

  /// Returns true when a filter value is present or represents the all option.
  bool _hasTerrainOption(List<TaskTerrainFilterOption> options, String value) {
    return value == TaskTerrainFilterProjector.allOptionId ||
        options.any((option) => option.id == value);
  }

  /// Returns the number of active narrowing terrain overlays.
  int _activeTerrainFilterCount(TaskTerrainFilterSelection selection) {
    var count = 0;
    for (final value in selection.areaFilters.values) {
      if (value != TaskTerrainFilterProjector.allOptionId) {
        count++;
      }
    }
    return count;
  }

  /// Returns true when every task in a cluster is currently revealed.
  bool _isTerrainClusterRevealed(TaskTerrainClusterPlacement cluster) {
    if (cluster.points.isEmpty) {
      return false;
    }
    return _setsMatch(
      _revealedTerrainTaskIds,
      cluster.points.map((point) => point.taskId).toSet(),
    );
  }

  /// Toggles the currently revealed terrain card group.
  void _toggleTerrainReveal(
    Iterable<String> taskIds, {
    required String selectTaskId,
  }) {
    final next = taskIds.toSet();
    setState(() {
      _revealedTerrainTaskIds = _setsMatch(_revealedTerrainTaskIds, next)
          ? const <String>{}
          : next;
    });
    widget.controller.selectTask(selectTaskId);
  }

  /// Returns true when two task id sets contain the same values.
  bool _setsMatch(Set<String> left, Set<String> right) {
    if (left.length != right.length) {
      return false;
    }
    return left.containsAll(right);
  }
}

/// Renders the terrain insight question selector.
class _TerrainInsightModeSelector extends StatelessWidget {
  const _TerrainInsightModeSelector({
    required this.value,
    required this.onChanged,
  });

  final TaskTerrainInsightMode value;
  final ValueChanged<TaskTerrainInsightMode> onChanged;

  /// Builds a compact selector for terrain insight questions.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: TaskTerrainModeRegistry.question(value),
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
          child: DropdownButton<TaskTerrainInsightMode>(
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
              fontWeight: FontWeight.w900,
            ),
            selectedItemBuilder: (context) {
              return <Widget>[
                for (final mode in TaskTerrainModeRegistry.modes)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(TaskTerrainModeRegistry.icon(mode), size: 16),
                      const SizedBox(width: 7),
                      Text(TaskTerrainModeRegistry.label(mode)),
                    ],
                  ),
              ];
            },
            items: <DropdownMenuItem<TaskTerrainInsightMode>>[
              for (final mode in TaskTerrainModeRegistry.modes)
                DropdownMenuItem<TaskTerrainInsightMode>(
                  value: mode,
                  child: Text(TaskTerrainModeRegistry.label(mode)),
                ),
            ],
            onChanged: (mode) {
              if (mode != null) {
                onChanged(mode);
              }
            },
          ),
        ),
      ),
    );
  }
}

/// Renders the terrain semantic insight preset selector.
class _TerrainInsightPresetMenu extends StatelessWidget {
  const _TerrainInsightPresetMenu({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds a compact selector for semantic terrain slices.
  @override
  Widget build(BuildContext context) {
    final selected = TaskInsightPresetRegistry.selectedTerrainPreset(
      controller.taskInsightPresetId,
    );
    final colors = context.agentAwesomeColors;
    return PopupMenuButton<String>(
      tooltip: selected.question,
      onSelected: (presetId) {
        unawaited(controller.applyTaskInsightPreset(presetId));
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        for (final preset in TaskInsightPresetRegistry.terrainPresets)
          CheckedPopupMenuItem<String>(
            value: preset.id,
            checked: preset.id == controller.taskInsightPresetId,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  TaskInsightPresetRegistry.iconFor(preset.iconName),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(preset.label)),
              ],
            ),
          ),
      ],
      child: Container(
        height: 34,
        constraints: const BoxConstraints(maxWidth: 210),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          gradient: context.agentAwesomeControlGradient,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              TaskInsightPresetRegistry.iconFor(selected.iconName),
              size: 16,
              color: colors.muted,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                selected.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down, size: 16, color: colors.muted),
          ],
        ),
      ),
    );
  }
}

/// Describes active terrain insight highlighting without hiding other work.
class _TerrainInsightLens {
  const _TerrainInsightLens({
    required this.preset,
    required this.activeCandidatesByTaskId,
    required this.candidatesByTaskId,
  });

  final TaskInsightPreset preset;
  final Map<String, TaskInsightCandidate> activeCandidatesByTaskId;
  final Map<String, List<TaskInsightCandidate>> candidatesByTaskId;

  /// Creates a lens from the shared task insight index.
  factory _TerrainInsightLens.fromController(
    AgentAwesomeAppController controller,
  ) {
    final preset = TaskInsightPresetRegistry.selectedTerrainPreset(
      controller.taskInsightPresetId,
    );
    final candidatesByTaskId = <String, List<TaskInsightCandidate>>{};
    for (final terrainPreset in TaskInsightPresetRegistry.terrainPresets) {
      if (terrainPreset.id == TaskInsightIds.all) {
        continue;
      }
      for (final candidate in controller.taskInsightIndex.tasksForInsight(
        terrainPreset.id,
      )) {
        candidatesByTaskId
            .putIfAbsent(candidate.taskId, () => <TaskInsightCandidate>[])
            .add(candidate);
      }
    }
    final activeCandidatesByTaskId = <String, TaskInsightCandidate>{};
    if (preset.id != TaskInsightIds.all) {
      for (final candidate in controller.taskInsightIndex.tasksForInsight(
        preset.id,
      )) {
        activeCandidatesByTaskId[candidate.taskId] = candidate;
      }
    }
    return _TerrainInsightLens(
      preset: preset,
      activeCandidatesByTaskId: activeCandidatesByTaskId,
      candidatesByTaskId: candidatesByTaskId,
    );
  }

  /// Whether the selected preset should visually emphasize matching tasks.
  bool get hasActivePreset => preset.id != TaskInsightIds.all;

  /// Returns true when a task belongs to the selected insight.
  bool highlights(String taskId) {
    return !hasActivePreset || activeCandidatesByTaskId.containsKey(taskId);
  }

  /// Returns the selected insight candidate for a task.
  TaskInsightCandidate? activeCandidateFor(String taskId) {
    return activeCandidatesByTaskId[taskId];
  }

  /// Returns all terrain insight candidates attached to one task.
  List<TaskInsightCandidate> candidatesFor(String taskId) {
    return candidatesByTaskId[taskId] ?? const <TaskInsightCandidate>[];
  }

  /// Returns display opacity for a task in the active lens.
  double opacityFor(String taskId) {
    return highlights(taskId) ? 1 : 0.36;
  }

  /// Counts highlighted points in a point collection.
  int highlightedPointCount(Iterable<PriorityTerrainPoint> points) {
    if (!hasActivePreset) {
      return 0;
    }
    return points.where((point) => highlights(point.taskId)).length;
  }

  /// Returns a tooltip that names the selected insight reason when available.
  String tooltipFor(PriorityTerrainPoint point, String fallback) {
    final active = activeCandidateFor(point.taskId);
    if (active != null) {
      return '${point.title}\n${preset.label}: ${TaskInsightPresetRegistry.candidateReason(active)}';
    }
    final candidates = candidatesFor(point.taskId);
    if (candidates.isNotEmpty && !hasActivePreset) {
      final labels = candidates
          .take(3)
          .map((candidate) {
            return TaskInsightPresetRegistry.labelForInsightId(
              candidate.insightId,
            );
          })
          .join(', ');
      return '${point.title}\nInsights: $labels';
    }
    return fallback;
  }
}

/// Renders the compact terrain area-overlay drawer toggle.
class _TerrainFiltersButton extends StatelessWidget {
  const _TerrainFiltersButton({
    required this.activeCount,
    required this.open,
    required this.onTap,
  });

  final int activeCount;
  final bool open;
  final VoidCallback onTap;

  /// Builds one toolbar button for the terrain overlay drawer.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final label = activeCount == 0 ? 'Overlays' : 'Overlays $activeCount';
    return Tooltip(
      message: 'Area overlays',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: open ? colors.greenSoft : colors.surface,
            gradient: open ? null : context.agentAwesomeControlGradient,
            border: Border.all(color: open ? colors.green : colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.tune,
                size: 16,
                color: open ? colors.green : colors.muted,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: open ? colors.green : colors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders a compact clear-overlays command.
class _TerrainClearFiltersButton extends StatelessWidget {
  const _TerrainClearFiltersButton({required this.onTap});

  final VoidCallback onTap;

  /// Builds one icon-only clear filter button.
  @override
  Widget build(BuildContext context) {
    return _IconBadgeButton(
      tooltip: 'Clear terrain overlays',
      icon: Icons.filter_alt_off_outlined,
      onTap: onTap,
    );
  }
}

/// Renders terrain area overlays as a right-side drawer over the map.
class _TerrainFilterDrawer extends StatelessWidget {
  const _TerrainFilterDrawer({
    required this.controls,
    required this.activeCount,
    required this.onClear,
    required this.onClose,
  });

  final List<Widget> controls;
  final int activeCount;
  final VoidCallback? onClear;
  final VoidCallback onClose;

  /// Builds the over-map overlay drawer.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Positioned(
      top: 10,
      right: 10,
      bottom: 10,
      width: 314,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.98),
          gradient: context.agentAwesomeSurfaceGradient,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: <BoxShadow>[
            BoxShadow(
              blurRadius: 22,
              offset: const Offset(0, 10),
              color: colors.shadow,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.tune, size: 16, color: colors.green),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      activeCount == 0
                          ? 'Area overlays'
                          : 'Area overlays $activeCount',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (onClear != null)
                    _IconBadgeButton(
                      tooltip: 'Clear terrain overlays',
                      icon: Icons.filter_alt_off_outlined,
                      onTap: onClear!,
                    ),
                  const SizedBox(width: 6),
                  _IconBadgeButton(
                    tooltip: 'Close terrain overlays',
                    icon: Icons.close,
                    onTap: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final control in controls) ...<Widget>[
                        control,
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders one terrain category filter selector.
class _TerrainFilterSelector extends StatelessWidget {
  const _TerrainFilterSelector({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<TaskTerrainFilterOption> options;
  final ValueChanged<String> onChanged;

  /// Builds a compact selector for one terrain filter dimension.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: label,
      child: _TerrainDropdownShell(
        child: Row(
          children: <Widget>[
            Text(
              '$label:',
              style: TextStyle(
                color: colors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  isDense: true,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(8),
                  dropdownColor: colors.surface,
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: colors.muted,
                  ),
                  style: _terrainDropdownTextStyle(context),
                  selectedItemBuilder: (context) {
                    return <Widget>[
                      for (final option in options)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            option.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ];
                  },
                  items: <DropdownMenuItem<String>>[
                    for (final option in options)
                      DropdownMenuItem<String>(
                        value: option.id,
                        child: Text(
                          option.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (option) {
                    if (option != null) {
                      onChanged(option);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// _TerrainDropdownShell provides consistent terrain selector styling.
class _TerrainDropdownShell extends StatelessWidget {
  const _TerrainDropdownShell({required this.child});

  final Widget child;

  /// Builds shared dropdown chrome for terrain controls.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeControlGradient,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

/// Shared text style for terrain dropdown controls.
TextStyle _terrainDropdownTextStyle(BuildContext context) {
  return TextStyle(
    color: context.agentAwesomeColors.ink,
    fontSize: 13,
    fontWeight: FontWeight.w900,
  );
}

/// Renders a tiny count for tasks with attached insight membership.
class _TerrainInsightCountPill extends StatelessWidget {
  const _TerrainInsightCountPill({required this.count, required this.color});

  final int count;
  final Color color;

  /// Builds a compact count chip inside terrain markers.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.34)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count == 1 ? '1 insight' : '$count insights',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Renders one full terrain task card from computed layout geometry.
class _PositionedTerrainCard extends StatelessWidget {
  const _PositionedTerrainCard({
    required this.placement,
    required this.selected,
    required this.lens,
    required this.onTap,
  });

  final TaskTerrainCardPlacement placement;
  final bool selected;
  final _TerrainInsightLens lens;
  final VoidCallback onTap;

  /// Builds one promoted task card on the terrain.
  @override
  Widget build(BuildContext context) {
    final point = placement.point;
    final color = placement.color;
    final colors = context.agentAwesomeColors;
    final activeCandidate = lens.activeCandidateFor(point.taskId);
    final candidates = lens.candidatesFor(point.taskId);
    final opacity = lens.opacityFor(point.taskId);
    final highlight = activeCandidate != null;
    return Positioned(
      left: placement.rect.left,
      top: placement.rect.top,
      width: placement.rect.width,
      height: placement.rect.height,
      child: Tooltip(
        message: lens.tooltipFor(point, point.explanation),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Opacity(
            opacity: opacity,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? colors.panelStrong : colors.surface,
                gradient: context.agentAwesomeCardGradient,
                border: Border.all(
                  color: selected || highlight ? colors.borderStrong : color,
                  width: highlight ? 1.8 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    blurRadius: highlight
                        ? 22
                        : point.riskScore >= 0.6
                        ? 18
                        : 12,
                    offset: const Offset(0, 5),
                    color: color.withValues(
                      alpha: highlight
                          ? 0.34
                          : point.riskScore >= 0.6
                          ? 0.24
                          : 0.15,
                    ),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Text(
                      (point.elevation * 9 + 1).round().toString(),
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                point.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (highlight)
                              Icon(
                                Icons.center_focus_strong,
                                size: 14,
                                color: color,
                              ),
                          ],
                        ),
                        Text(
                          activeCandidate == null
                              ? placement.cue
                              : TaskInsightPresetRegistry.candidateReason(
                                  activeCandidate,
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: activeCandidate == null
                                ? colors.muted
                                : color,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                point.dueAt == null
                                    ? placement.zone.label
                                    : 'Due ${formatOptionalLocalMonthDay(point.dueAt)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (candidates.isNotEmpty) ...<Widget>[
                              const SizedBox(width: 6),
                              _TerrainInsightCountPill(
                                count: candidates.length,
                                color: color,
                              ),
                            ],
                            if (point.agentFitScore >= 0.58) ...<Widget>[
                              const SizedBox(width: 6),
                              Icon(Icons.auto_awesome, size: 12, color: color),
                            ],
                            if (point.riskScore >= 0.6) ...<Widget>[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 13,
                                color: color,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders one compact terrain task marker.
class _PositionedTerrainPin extends StatelessWidget {
  const _PositionedTerrainPin({
    required this.pin,
    required this.selected,
    required this.expanded,
    required this.lens,
    required this.onTap,
  });

  final TaskTerrainPinPlacement pin;
  final bool selected;
  final bool expanded;
  final _TerrainInsightLens lens;
  final VoidCallback onTap;

  /// Builds one low-detail task pin.
  @override
  Widget build(BuildContext context) {
    final point = pin.point;
    final color = pin.color;
    final colors = context.agentAwesomeColors;
    final highlight = lens.activeCandidateFor(point.taskId) != null;
    final opacity = lens.opacityFor(point.taskId);
    return Positioned(
      left: pin.center.dx - 14,
      top: pin.center.dy - 14,
      width: 28,
      height: 28,
      child: Tooltip(
        message: lens.tooltipFor(point, '${point.title}\n${pin.zone.label}'),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Opacity(
            opacity: opacity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected || expanded
                    ? colors.green
                    : color.withValues(alpha: highlight ? 1 : 0.9),
                border: Border.all(
                  color: highlight || expanded ? colors.ink : colors.surface,
                  width: highlight || expanded ? 2.6 : 2,
                ),
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    blurRadius: highlight ? 16 : 8,
                    color: color.withValues(alpha: highlight ? 0.38 : 0.2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  pin.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders a terrain cluster marker for nearby low-detail tasks.
class _PositionedTerrainCluster extends StatelessWidget {
  const _PositionedTerrainCluster({
    required this.cluster,
    required this.expanded,
    required this.lens,
    required this.onTap,
  });

  final TaskTerrainClusterPlacement cluster;
  final bool expanded;
  final _TerrainInsightLens lens;
  final VoidCallback onTap;

  /// Builds one count badge for clustered low-detail tasks.
  @override
  Widget build(BuildContext context) {
    final color = cluster.color;
    final colors = context.agentAwesomeColors;
    final highlightedCount = lens.highlightedPointCount(cluster.points);
    final highlight = highlightedCount > 0;
    final opacity = lens.hasActivePreset && !highlight ? 0.36 : 1.0;
    final label =
        '${cluster.zone.label}\n${cluster.points.take(5).map((point) => point.title).join('\n')}';
    return Positioned(
      left: cluster.center.dx - 17,
      top: cluster.center.dy - 17,
      width: 34,
      height: 34,
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Opacity(
            opacity: opacity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: expanded ? colors.green : color.withValues(alpha: 0.9),
                border: Border.all(
                  color: expanded || highlight ? colors.ink : colors.surface,
                  width: expanded || highlight ? 2.6 : 2,
                ),
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    blurRadius: highlight ? 16 : 10,
                    color: color.withValues(alpha: highlight ? 0.36 : 0.22),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  highlight
                      ? '$highlightedCount/${cluster.points.length}'
                      : cluster.points.length.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
