/// Renders task graph projections inside the shared task command panel.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/theme.dart';
import '../domain/models.dart';
import '../domain/task_graph_query.dart';
import '../domain/task_projection_adapters.dart';
import '../domain/task_wbs_tree.dart';
import 'panels/panels.dart';
import 'task_constellation_layout.dart';
import 'task_filter_menu.dart';
import 'task_stream_axes.dart';
import 'task_stream_canvas.dart';
import 'task_stream_filters.dart';
import 'task_terrain_filters.dart';
import 'task_terrain_layout.dart';
import 'task_terrain_modes.dart';
import 'task_wbs_formatting.dart';

/// TaskConceptKind identifies one task projection workspace.
enum TaskConceptKind {
  /// Relationship-first spatial task map.
  constellation,

  /// Encoded task-fact stream.
  stream,

  /// Priority landscape for planning.
  terrain,

  /// Work-breakdown structure table.
  wbs,
}

/// TaskConceptProjectionPanel renders one projection without command-panel chrome.
class TaskConceptProjectionPanel extends StatelessWidget {
  /// Creates a task projection panel.
  const TaskConceptProjectionPanel({
    super.key,
    required this.controller,
    required this.kind,
  });

  /// Shared app controller.
  final AuroraAppController controller;

  /// Projection view to render.
  final TaskConceptKind kind;

  /// Builds the selected projection surface.
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AuroraColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: _buildView(),
      ),
    );
  }

  /// Builds the projection matching the current kind.
  Widget _buildView() {
    switch (kind) {
      case TaskConceptKind.constellation:
        return _TaskConstellationView(controller: controller);
      case TaskConceptKind.stream:
        return _TaskStreamView(controller: controller);
      case TaskConceptKind.terrain:
        return _PriorityTerrainView(controller: controller);
      case TaskConceptKind.wbs:
        return _TaskWbsView(controller: controller);
    }
  }
}

class _TaskWbsView extends StatelessWidget {
  const _TaskWbsView({required this.controller});

  final AuroraAppController controller;

  /// Builds the work-breakdown structure tree.
  @override
  Widget build(BuildContext context) {
    final tasks =
        controller.workspace.tasks
            .where((task) => taskWbsHasContent(task.workBreakdown))
            .toList()
          ..sort(compareWorkspaceTasksByWbs);
    if (tasks.isEmpty) {
      return PanelEmptyBlock(
        label: _emptyProjectionLabel(
          controller,
          'No WBS metadata yet. Add WBS details to a backlog item or generate a project breakdown.',
        ),
      );
    }
    final roots = buildTaskWbsTree(tasks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: PanelSectionBlock(
            child: ListView.builder(
              itemCount: roots.length,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemBuilder: (context, index) {
                return _WbsTreeNodeView(
                  node: roots[index],
                  controller: controller,
                  depth: 0,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _WbsTreeNodeView extends StatelessWidget {
  const _WbsTreeNodeView({
    required this.node,
    required this.controller,
    required this.depth,
  });

  final TaskWbsTreeNode node;
  final AuroraAppController controller;
  final int depth;

  /// Builds one recursive WBS tree node.
  @override
  Widget build(BuildContext context) {
    if (node.isWorkPackage) {
      return _WbsWorkPackageNode(
        node: node,
        controller: controller,
        depth: depth,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _WbsBranchNode(node: node, depth: depth),
        for (final child in node.children)
          _WbsTreeNodeView(
            node: child,
            controller: controller,
            depth: depth + 1,
          ),
      ],
    );
  }
}

const int _maxWbsVisualDepth = 8;
const double _baseWbsIndent = 14;
const double _wbsIndentStep = 18;

/// Returns bounded WBS indentation for deeply decomposed project trees.
double _wbsIndentForDepth(int depth) {
  final boundedDepth = math.max(0, math.min(depth, _maxWbsVisualDepth));
  return _baseWbsIndent + boundedDepth * _wbsIndentStep;
}

class _WbsBranchNode extends StatelessWidget {
  const _WbsBranchNode({required this.node, required this.depth});

  final TaskWbsTreeNode node;
  final int depth;

  /// Builds one non-leaf WBS decomposition bucket.
  @override
  Widget build(BuildContext context) {
    final isRoot = node.kind == TaskWbsTreeNodeKind.root;
    return Container(
      margin: EdgeInsets.only(top: isRoot && depth == 0 ? 8 : 0),
      padding: EdgeInsets.fromLTRB(_wbsIndentForDepth(depth), 10, 14, 10),
      decoration: BoxDecoration(
        color: isRoot
            ? AuroraColors.greenSoft.withValues(alpha: 0.32)
            : const Color(0xfffffcf8),
        border: Border(
          bottom: BorderSide(color: AuroraColors.border.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isRoot ? Icons.account_tree_outlined : Icons.folder_open_outlined,
            size: isRoot ? 20 : 18,
            color: AuroraColors.green,
          ),
          const SizedBox(width: 10),
          _WbsCodeBadge(code: node.code),
          Expanded(
            child: Text(
              node.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isRoot ? AuroraColors.green : AuroraColors.ink,
                fontSize: isRoot ? 15 : 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _WbsNodeStats(node: node),
        ],
      ),
    );
  }
}

class _WbsWorkPackageNode extends StatelessWidget {
  const _WbsWorkPackageNode({
    required this.node,
    required this.controller,
    required this.depth,
  });

  final TaskWbsTreeNode node;
  final AuroraAppController controller;
  final int depth;

  /// Builds one leaf WBS work package.
  @override
  Widget build(BuildContext context) {
    final task = node.task;
    if (task == null) {
      return const SizedBox.shrink();
    }
    final workBreakdown = task.workBreakdown;
    final gaps = _wbsMissingFields(task);
    return InkWell(
      onTap: () => controller.selectTask(task.id),
      child: Container(
        padding: EdgeInsets.fromLTRB(_wbsIndentForDepth(depth), 10, 14, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AuroraColors.border.withValues(alpha: 0.62),
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.task_alt_outlined,
              size: 18,
              color: AuroraColors.muted,
            ),
            const SizedBox(width: 10),
            _WbsCodeBadge(code: workBreakdown.code),
            Expanded(
              child: _WbsWorkPackageContent(task: task, gaps: gaps),
            ),
          ],
        ),
      ),
    );
  }
}

class _WbsNodeStats extends StatelessWidget {
  const _WbsNodeStats({required this.node});

  final TaskWbsTreeNode node;

  /// Builds aggregate stats for a WBS bucket.
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: <Widget>[
        _MiniBadge(label: '${node.workPackageCount} packages'),
        if (node.estimateMinutes > 0)
          _MiniBadge(
            label: '${(node.estimateMinutes / 60).toStringAsFixed(1)}h',
          ),
        if (node.estimatedCostCents > 0)
          _MiniBadge(
            label: formatMinorUnitSpend(
              node.estimatedCostCents,
              node.costCurrency,
            ),
          ),
      ],
    );
  }
}

class _WbsCodeBadge extends StatelessWidget {
  const _WbsCodeBadge({required this.code});

  final String code;

  /// Builds the WBS hierarchy code badge.
  @override
  Widget build(BuildContext context) {
    final label = code.isEmpty ? 'No code' : code;
    return Tooltip(
      message: label,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xfffffcf8),
          border: Border.all(color: AuroraColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _WbsWorkPackageContent extends StatelessWidget {
  const _WbsWorkPackageContent({required this.task, required this.gaps});

  final WorkspaceTask task;
  final List<String> gaps;

  /// Builds one leaf task plus its WBS evidence.
  @override
  Widget build(BuildContext context) {
    final workBreakdown = task.workBreakdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _WbsTaskSummary(task: task, gaps: gaps),
            ),
            const SizedBox(width: 12),
            _WbsLeafSpend(workBreakdown: workBreakdown),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 18,
          runSpacing: 12,
          children: <Widget>[
            _WbsDetailBlock(
              label: 'Start',
              child: _WbsTextList(values: workBreakdown.startCriteria),
            ),
            _WbsDetailBlock(
              label: 'Done',
              child: _WbsTextList(values: workBreakdown.acceptanceCriteria),
            ),
            _WbsDetailBlock(
              label: 'Resources',
              child: _WbsResourceSummary(resources: workBreakdown.resources),
            ),
          ],
        ),
      ],
    );
  }
}

class _WbsLeafSpend extends StatelessWidget {
  const _WbsLeafSpend({required this.workBreakdown});

  final TaskWorkBreakdown workBreakdown;

  /// Builds the leaf package spend label.
  @override
  Widget build(BuildContext context) {
    final label = formatTaskWbsSpend(workBreakdown);
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 128),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _WbsDetailBlock extends StatelessWidget {
  const _WbsDetailBlock({required this.label, required this.child});

  final String label;
  final Widget child;

  /// Builds one compact leaf detail block.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AuroraColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          child,
        ],
      ),
    );
  }
}

class _WbsTaskSummary extends StatelessWidget {
  const _WbsTaskSummary({required this.task, required this.gaps});

  final WorkspaceTask task;
  final List<String> gaps;

  /// Builds title, deliverable, traceability, and gap badges.
  @override
  Widget build(BuildContext context) {
    final workBreakdown = task.workBreakdown;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          if (workBreakdown.deliverable.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              workBreakdown.deliverable,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AuroraColors.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              if (task.estimateMinutes > 0)
                _MiniBadge(label: '${task.estimateMinutes}m'),
              for (final ref in workBreakdown.requirementRefs.take(2))
                _MiniBadge(label: ref),
              for (final ref in workBreakdown.rubricRefs.take(2))
                _MiniBadge(label: ref),
              if (gaps.isNotEmpty) _MiniBadge(label: '${gaps.length} gaps'),
            ],
          ),
        ],
      ),
    );
  }
}

class _WbsTextList extends StatelessWidget {
  const _WbsTextList({required this.values});

  final List<String> values;

  /// Builds compact multi-line WBS criteria text.
  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Text(
        'Missing',
        style: TextStyle(color: AuroraColors.muted, fontSize: 12),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final value in values.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.25),
              ),
            ),
        ],
      ),
    );
  }
}

class _WbsResourceSummary extends StatelessWidget {
  const _WbsResourceSummary({required this.resources});

  final List<TaskResourceRequirement> resources;

  /// Builds compact resource requirements for a WBS row.
  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) {
      return const Text(
        'Missing',
        style: TextStyle(color: AuroraColors.muted, fontSize: 12),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final resource in resources.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _resourceSummary(resource),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.25),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label});

  final String label;

  /// Builds a small inline WBS badge.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AuroraColors.greenSoft.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AuroraColors.green,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TaskStreamView extends StatefulWidget {
  const _TaskStreamView({required this.controller});

  final AuroraAppController controller;

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
    return SegmentedButton<_TaskStreamPreset>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: WidgetStatePropertyAll(
          BorderSide(color: AuroraColors.border.withValues(alpha: 0.85)),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AuroraColors.green.withValues(alpha: 0.16);
          }
          return AuroraColors.panel;
        }),
        foregroundColor: const WidgetStatePropertyAll(AuroraColors.ink),
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
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AuroraColors.panel,
          border: Border.all(color: AuroraColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 15, color: AuroraColors.green),
              const SizedBox(width: 6),
              DropdownButton<TaskStreamAxisDimension>(
                value: value,
                borderRadius: BorderRadius.circular(8),
                icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                style: const TextStyle(
                  color: AuroraColors.ink,
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
    return SizedBox(
      height: 34,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.timer_outlined, size: 15, color: AuroraColors.muted),
          const SizedBox(width: 6),
          Text(
            '${model.taskCount} items · ${_formatStreamEffort(model.estimateMinutes)}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AuroraColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskConstellationView extends StatefulWidget {
  const _TaskConstellationView({required this.controller});

  final AuroraAppController controller;

  /// Creates state for relationship focus toggling.
  @override
  State<_TaskConstellationView> createState() => _TaskConstellationViewState();
}

class _TaskConstellationViewState extends State<_TaskConstellationView>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _constellationQueryController;
  final TransformationController _constellationTransform =
      TransformationController();
  late final AnimationController _constellationCameraController;
  Animation<Matrix4>? _constellationCameraAnimation;
  String _constellationQuery = '';
  Set<String> _expandedAnchorIds = const <String>{};
  Set<String> _expandedTaskIds = const <String>{};
  bool _autoExpandQueryResults = true;
  Size? _constellationViewportSize;
  Rect? _constellationFocusBounds;
  Offset? _constellationPointerDownPosition;

  /// Creates animation state for constellation camera moves.
  @override
  void initState() {
    super.initState();
    _constellationQueryController = TextEditingController();
    _constellationCameraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(_applyConstellationCameraFrame);
  }

  /// Disposes the constellation viewport transform controller.
  @override
  void dispose() {
    _constellationCameraController.dispose();
    _constellationQueryController.dispose();
    _constellationTransform.dispose();
    super.dispose();
  }

  /// Builds the relationship-first constellation projection.
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final queryResult = TaskGraphConstellationQuery.run(
      controller.taskInsightIndex,
      _constellationQuery,
      selectedTaskId: controller.selectedGraphTaskId,
    );
    final queryHasText = _constellationQuery.trim().isNotEmpty;
    final projection = queryResult.projection.nodes.isEmpty && !queryHasText
        ? controller.taskConstellationProjection
        : queryResult.projection;
    final anchorDimension = _constellationAnchorDimensionForQuery(
      queryResult.group,
    );
    const layoutStrategy = TaskConstellationLayoutStrategyKind.anchoredForce;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ProjectionToolbar(
          left: <Widget>[
            _ConstellationQueryField(
              controller: _constellationQueryController,
              onChanged: _setConstellationQuery,
              onSubmitted: (_) => _scheduleConstellationRefocus(),
            ),
            _ConstellationSavedQueryMenu(
              onSelected: _applyConstellationExample,
            ),
            if (queryHasText)
              _IconBadgeButton(
                tooltip: 'Clear graph query',
                icon: Icons.close,
                onTap: _clearConstellationQuery,
              ),
            _IconBadgeButton(
              tooltip: 'Collapse constellation',
              icon: Icons.compress_outlined,
              onTap: () {
                setState(() {
                  _expandedAnchorIds = const <String>{};
                  _expandedTaskIds = const <String>{};
                  _autoExpandQueryResults = false;
                });
                _scheduleConstellationRefocus();
              },
            ),
          ],
        ),
        if (queryHasText) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            queryResult.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AuroraColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (queryResult.rows.isNotEmpty ||
              queryResult.paths.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _ConstellationQueryRows(
              rows: queryResult.rows,
              paths: queryResult.paths,
            ),
          ],
        ],
        const SizedBox(height: 12),
        Expanded(
          child: projection.nodes.isEmpty
              ? PanelEmptyBlock(
                  label: queryHasText
                      ? queryResult.summary
                      : _emptyProjectionLabel(controller, queryResult.summary),
                )
              : PanelSectionBlock(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final viewportSize = constraints.biggest;
                      final terrainProjection =
                          TaskInsightProjectionAdapters.terrain(
                            controller.taskInsightIndex,
                          );
                      final terrainPointsByTaskId =
                          <String, PriorityTerrainPoint>{
                            for (final point
                                in (terrainProjection.points.isEmpty
                                        ? controller.priorityTerrainProjection
                                        : terrainProjection)
                                    .points)
                              point.taskId: point,
                          };
                      final canvasSize = TaskConstellationLayout.canvasSizeFor(
                        projection,
                        viewportSize,
                        anchorDimension: anchorDimension,
                        terrainPointsByTaskId: terrainPointsByTaskId,
                        layoutStrategy: layoutStrategy,
                      );
                      final baseLayout = TaskConstellationLayout.build(
                        projection,
                        canvasSize,
                        anchorDimension: anchorDimension,
                        terrainPointsByTaskId: terrainPointsByTaskId,
                        layoutStrategy: layoutStrategy,
                      );
                      final effectiveExpandedAnchorIds =
                          _expandedAnchorIds.isEmpty &&
                              _expandedTaskIds.isEmpty &&
                              _autoExpandQueryResults &&
                              queryResult.expandResults
                          ? baseLayout.anchors
                                .map((anchor) => anchor.id)
                                .toSet()
                          : _expandedAnchorIds;
                      final expandedCanvasSize =
                          TaskConstellationLayout.canvasSizeFor(
                            projection,
                            viewportSize,
                            anchorDimension: anchorDimension,
                            expandedAnchorIds: effectiveExpandedAnchorIds,
                            expandedTaskIds: _expandedTaskIds,
                            terrainPointsByTaskId: terrainPointsByTaskId,
                            layoutStrategy: layoutStrategy,
                          );
                      final layout = TaskConstellationLayout.build(
                        projection,
                        expandedCanvasSize,
                        anchorDimension: anchorDimension,
                        expandedAnchorIds: effectiveExpandedAnchorIds,
                        expandedTaskIds: _expandedTaskIds,
                        terrainPointsByTaskId: terrainPointsByTaskId,
                        layoutStrategy: layoutStrategy,
                      );
                      _rememberConstellationFrame(viewportSize, layout);
                      return Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (event) {
                                _constellationPointerDownPosition =
                                    event.localPosition;
                              },
                              onPointerCancel: (_) {
                                _constellationPointerDownPosition = null;
                              },
                              onPointerUp: (event) {
                                _selectConstellationEdgeAt(
                                  layout,
                                  event.localPosition,
                                );
                              },
                              child: ClipRect(
                                child: InteractiveViewer(
                                  transformationController:
                                      _constellationTransform,
                                  constrained: false,
                                  minScale: 0.22,
                                  maxScale: 1.8,
                                  boundaryMargin: const EdgeInsets.all(640),
                                  onInteractionStart: (_) {
                                    _constellationCameraController.stop();
                                  },
                                  child: SizedBox(
                                    width: layout.size.width,
                                    height: layout.size.height,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: <Widget>[
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: _ConstellationPainter(
                                              layout: layout,
                                              selectedEdge: controller
                                                  .selectedConstellationEdge,
                                            ),
                                          ),
                                        ),
                                        for (final anchor in layout.anchors)
                                          _PositionedConstellationAnchor(
                                            anchor: anchor,
                                            expanded: layout.expandedAnchorIds
                                                .contains(anchor.id),
                                            onTap: () =>
                                                _toggleAnchor(anchor.id),
                                          ),
                                        for (final placement in layout.nodes)
                                          _PositionedConstellationNode(
                                            placement: placement,
                                            selected:
                                                controller
                                                    .selectedGraphTaskId ==
                                                placement.node.taskId,
                                            expanded: layout.expandedTaskIds
                                                .contains(
                                                  placement.node.taskId,
                                                ),
                                            onTap: () => _toggleTask(
                                              placement.node.taskId,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: _ConstellationOffscreenIndicators(
                                layout: layout,
                                viewportSize: viewportSize,
                                transform: _constellationTransform,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                _IconBadgeButton(
                                  tooltip: 'Zoom out',
                                  icon: Icons.remove,
                                  onTap: () => _zoomConstellation(0.9),
                                ),
                                const SizedBox(width: 6),
                                _IconBadgeButton(
                                  tooltip: 'Recenter constellation',
                                  icon: Icons.center_focus_strong_outlined,
                                  onTap: _fitConstellationToViewport,
                                ),
                                const SizedBox(width: 6),
                                _IconBadgeButton(
                                  tooltip: 'Zoom in',
                                  icon: Icons.add,
                                  onTap: () => _zoomConstellation(1.1),
                                ),
                              ],
                            ),
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

  /// Toggles one mind-map anchor expansion.
  void _toggleAnchor(String anchorId) {
    setState(() {
      final next = Set<String>.from(_expandedAnchorIds);
      if (!next.add(anchorId)) {
        next.remove(anchorId);
      }
      _expandedAnchorIds = next;
      _autoExpandQueryResults = false;
    });
    _scheduleConstellationRefocus();
  }

  /// Toggles one task node expansion.
  void _toggleTask(String taskId) {
    setState(() {
      final next = Set<String>.from(_expandedTaskIds);
      if (!next.add(taskId)) {
        next.remove(taskId);
      }
      _expandedTaskIds = next;
      _autoExpandQueryResults = false;
    });
    widget.controller.selectTask(taskId);
    _scheduleConstellationRefocus();
  }

  /// Applies a graph query and resets the result expansion state.
  void _setConstellationQuery(String query) {
    setState(() {
      _constellationQuery = query;
      _expandedAnchorIds = const <String>{};
      _expandedTaskIds = const <String>{};
      _autoExpandQueryResults = true;
    });
    _scheduleConstellationRefocus();
  }

  /// Clears the graph query and returns to the overview constellation.
  void _clearConstellationQuery() {
    _constellationQueryController.clear();
    _setConstellationQuery('');
  }

  /// Applies one saved canonical query example.
  void _applyConstellationExample(String query) {
    _constellationQueryController
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    _setConstellationQuery(query);
  }

  /// Selects a visible constellation edge near the tapped viewport point.
  void _selectConstellationEdgeAt(
    TaskConstellationLayout layout,
    Offset viewportPosition,
  ) {
    final pointerDownPosition = _constellationPointerDownPosition;
    _constellationPointerDownPosition = null;
    final scale = _constellationScale();
    if (pointerDownPosition != null &&
        (viewportPosition - pointerDownPosition).distance > 8) {
      return;
    }
    final position = _constellationCanvasPointFor(viewportPosition);
    if (layout.containsNodeOrAnchorAt(position)) {
      return;
    }
    final edge = layout.edgeAt(
      position,
      tolerance: math.max(6, 8 / math.max(0.22, scale)),
    );
    if (edge == null) {
      widget.controller.clearConstellationEdgeSelection();
      return;
    }
    widget.controller.selectConstellationEdge(edge);
  }

  /// Converts a viewport pointer coordinate into virtual canvas coordinates.
  Offset _constellationCanvasPointFor(Offset viewportPosition) {
    final inverse = Matrix4.copy(_constellationTransform.value)..invert();
    return MatrixUtils.transformPoint(inverse, viewportPosition);
  }

  /// Returns the current constellation canvas scale factor.
  double _constellationScale() {
    final value = _constellationTransform.value.storage[0];
    if (value <= 0) {
      return 1;
    }
    return value;
  }

  /// Stores the latest visible and virtual constellation camera inputs.
  void _rememberConstellationFrame(
    Size viewportSize,
    TaskConstellationLayout layout,
  ) {
    _constellationViewportSize = viewportSize;
    _constellationFocusBounds = layout.focusBounds();
  }

  /// Refits the constellation after the next layout pass.
  void _scheduleConstellationRefocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _fitConstellationToViewport();
    });
  }

  /// Fits the current focus neighborhood within the visible viewport.
  void _fitConstellationToViewport() {
    final viewport = _constellationViewportSize;
    final bounds = _constellationFocusBounds;
    if (viewport == null || bounds == null) {
      return;
    }
    _animateConstellationTo(_constellationMatrixForBounds(viewport, bounds));
  }

  /// Returns a camera matrix that keeps one canvas rectangle visible.
  Matrix4 _constellationMatrixForBounds(Size viewport, Rect bounds) {
    final width = math.max(80.0, bounds.width);
    final height = math.max(80.0, bounds.height);
    final scale = math.min(
      1.36,
      math.max(
        0.28,
        math.min(viewport.width / width, viewport.height / height) * 0.94,
      ),
    );
    final center = bounds.center;
    final dx = viewport.width / 2 - center.dx * scale;
    final dy = viewport.height / 2 - center.dy * scale;
    return _constellationMatrix(scale: scale, dx: dx, dy: dy);
  }

  /// Zooms the constellation around the center of the viewport.
  void _zoomConstellation(double factor) {
    final viewport = _constellationViewportSize;
    if (viewport == null) {
      return;
    }
    final focalPoint = Offset(viewport.width / 2, viewport.height / 2);
    final current = _constellationTransform.value.storage;
    final currentScale = _constellationScale();
    final nextScale = (currentScale * factor).clamp(0.22, 1.8).toDouble();
    final scaleChange = nextScale / currentScale;
    final dx = focalPoint.dx - (focalPoint.dx - current[12]) * scaleChange;
    final dy = focalPoint.dy - (focalPoint.dy - current[13]) * scaleChange;
    _animateConstellationTo(
      _constellationMatrix(scale: nextScale, dx: dx, dy: dy),
      duration: const Duration(milliseconds: 260),
    );
  }

  /// Applies the current smooth camera animation frame.
  void _applyConstellationCameraFrame() {
    final animation = _constellationCameraAnimation;
    if (animation == null) {
      return;
    }
    _constellationTransform.value = animation.value;
  }

  /// Animates the constellation camera to a target transform.
  void _animateConstellationTo(
    Matrix4 target, {
    Duration duration = const Duration(milliseconds: 420),
  }) {
    _constellationCameraController
      ..stop()
      ..duration = duration;
    _constellationCameraAnimation =
        Matrix4Tween(
          begin: Matrix4.copy(_constellationTransform.value),
          end: target,
        ).animate(
          CurvedAnimation(
            parent: _constellationCameraController,
            curve: Curves.easeOutCubic,
          ),
        );
    _constellationCameraController.forward(from: 0);
  }

  /// Builds a two-dimensional pan/zoom matrix without deprecated mutators.
  Matrix4 _constellationMatrix({
    required double scale,
    required double dx,
    required double dy,
  }) {
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, dx)
      ..setEntry(1, 3, dy);
  }
}

/// Renders saved canonical graph queries for Constellation.
class _ConstellationSavedQueryMenu extends StatelessWidget {
  const _ConstellationSavedQueryMenu({required this.onSelected});

  final ValueChanged<String> onSelected;

  /// Builds the saved query picker.
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Saved graph queries',
      child: SizedBox(
        height: 34,
        width: 38,
        child: PopupMenuButton<String>(
          tooltip: '',
          icon: const Icon(
            Icons.saved_search_outlined,
            size: 18,
            color: AuroraColors.green,
          ),
          color: AuroraColors.panel,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AuroraColors.border),
          ),
          onSelected: onSelected,
          itemBuilder: (context) {
            return <PopupMenuEntry<String>>[
              for (final example in taskGraphConstellationQueryExamples)
                PopupMenuItem<String>(
                  value: example.query,
                  child: _ConstellationSavedQueryItem(example: example),
                ),
            ];
          },
        ),
      ),
    );
  }
}

/// Renders one saved graph query option.
class _ConstellationSavedQueryItem extends StatelessWidget {
  const _ConstellationSavedQueryItem({required this.example});

  final TaskGraphQueryExample example;

  /// Builds a compact saved query menu item.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            example.label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AuroraColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            example.query,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AuroraColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the constellation canonical graph query input.
class _ConstellationQueryField extends StatelessWidget {
  const _ConstellationQueryField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  /// Builds a compact query field for canonical graph syntax.
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 720),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AuroraColors.panel,
          border: Border.all(color: AuroraColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.search, size: 16, color: AuroraColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                style: const TextStyle(
                  color: AuroraColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText:
                      'MATCH task -[depends_on*1..3]-> task RETURN from.title, path.depth, to.title LIMIT 10',
                  hintStyle: TextStyle(color: AuroraColors.muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders compact row and path previews returned by a graph query.
class _ConstellationQueryRows extends StatelessWidget {
  const _ConstellationQueryRows({required this.rows, required this.paths});

  final List<Map<String, Object?>> rows;
  final List<TaskGraphQueryPath> paths;

  /// Builds a horizontal strip of deterministic query result values.
  @override
  Widget build(BuildContext context) {
    final previews = <_ConstellationQueryPreview>[
      for (final path in paths.take(3))
        _ConstellationQueryPreview(
          text: _constellationPathPreview(path),
          isPath: true,
        ),
      for (final row in rows.take(4))
        _ConstellationQueryPreview(
          text: _constellationRowPreview(row),
          isPath: false,
        ),
    ];
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: previews.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final preview = previews[index];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: preview.isPath
                  ? AuroraColors.coral.withValues(alpha: 0.1)
                  : AuroraColors.greenSoft.withValues(alpha: 0.26),
              border: Border.all(
                color: preview.isPath
                    ? AuroraColors.coral.withValues(alpha: 0.24)
                    : AuroraColors.green.withValues(alpha: 0.24),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              preview.text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AuroraColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// _ConstellationQueryPreview stores one compact query preview chip.
class _ConstellationQueryPreview {
  /// Creates one query preview chip description.
  const _ConstellationQueryPreview({required this.text, required this.isPath});

  /// Chip label.
  final String text;

  /// Whether the chip represents path metadata instead of row values.
  final bool isPath;
}

/// Returns compact text for one graph query path.
String _constellationPathPreview(TaskGraphQueryPath path) {
  final label = path.depth == 1 ? 'edge' : 'edges';
  final nodes = path.nodeIds.take(5).join(' > ');
  final overflow = path.nodeIds.length > 5 ? ' > ...' : '';
  return 'path ${path.rowIndex + 1}: ${path.depth} $label $nodes$overflow';
}

/// Returns compact text for one graph query row.
String _constellationRowPreview(Map<String, Object?> row) {
  return row.entries
      .take(3)
      .map((entry) {
        return '${entry.key}: ${_constellationRowValue(entry.value)}';
      })
      .join(' · ');
}

/// Returns compact text for one graph query row value.
String _constellationRowValue(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is DateTime) {
    return '${value.month}/${value.day}';
  }
  if (value is Iterable) {
    return value.join('>');
  }
  final text = value.toString();
  if (text.length <= 28) {
    return text;
  }
  return '${text.substring(0, 27)}…';
}

/// Renders a compact icon badge button.
class _IconBadgeButton extends StatelessWidget {
  const _IconBadgeButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  /// Builds an icon-only projection toolbar button.
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AuroraColors.panel,
            border: Border.all(color: AuroraColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AuroraColors.green),
        ),
      ),
    );
  }
}

/// Renders one constellation mind-map anchor node.
class _PositionedConstellationAnchor extends StatelessWidget {
  const _PositionedConstellationAnchor({
    required this.anchor,
    required this.expanded,
    required this.onTap,
  });

  final TaskConstellationAnchorPlacement anchor;
  final bool expanded;
  final VoidCallback onTap;

  /// Builds one anchor node used as a constellation starting point.
  @override
  Widget build(BuildContext context) {
    final bounds = anchor.bounds;
    return Positioned(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
      child: Tooltip(
        message: '${anchor.label}\n${anchor.count} backlog items',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: expanded ? AuroraColors.greenSoft : AuroraColors.panel,
              border: Border.all(
                color: expanded ? AuroraColors.green : AuroraColors.border,
                width: expanded ? 2.2 : 1.2,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  blurRadius: expanded ? 22 : 10,
                  color: AuroraColors.green.withValues(
                    alpha: expanded ? 0.22 : 0.08,
                  ),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  anchor.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${anchor.count} items',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AuroraColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PositionedConstellationNode extends StatelessWidget {
  const _PositionedConstellationNode({
    required this.placement,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final TaskConstellationNodePlacement placement;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  /// Builds a constellation node at a normalized projection position.
  @override
  Widget build(BuildContext context) {
    final node = placement.node;
    final bounds = placement.bounds;
    final color = _categoryColor(node.category);
    return Positioned(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
      child: Tooltip(
        message: node.explanation,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: selected || expanded
                  ? AuroraColors.greenSoft
                  : const Color(0xfffffcf8),
              border: Border.all(
                color: selected || expanded ? AuroraColors.green : color,
                width: expanded
                    ? 2.3
                    : selected
                    ? 1.8
                    : 1,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  blurRadius: expanded ? 20 : 10 + 8 * node.urgency,
                  color: color.withValues(alpha: expanded ? 0.26 : 0.13),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  node.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _nodeMetaLabel(node),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AuroraColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns a concise metadata line for a constellation task card.
String _nodeMetaLabel(TaskConstellationNode node) {
  final parts = <String>[
    if (node.category.trim().isNotEmpty) _taskConceptLabel(node.category),
    if (node.owner.trim().isNotEmpty &&
        node.owner.toLowerCase() != node.category.toLowerCase())
      _taskConceptLabel(node.owner),
    if (node.project.trim().isNotEmpty &&
        node.project.toLowerCase() != node.category.toLowerCase())
      _taskConceptLabel(node.project),
    if (node.status.trim().isNotEmpty) _taskConceptLabel(node.status),
  ];
  if (parts.isEmpty) {
    return 'Context';
  }
  return parts.take(2).join(' • ');
}

/// Returns a readable label for compact task projection metadata.
String _taskConceptLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

/// Paints viewport-edge hints for constellation items outside the view.
class _ConstellationOffscreenIndicators extends StatelessWidget {
  const _ConstellationOffscreenIndicators({
    required this.layout,
    required this.viewportSize,
    required this.transform,
  });

  final TaskConstellationLayout layout;
  final Size viewportSize;
  final TransformationController transform;

  /// Builds indicators that move as the constellation is panned or zoomed.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: transform,
      builder: (context, _) {
        return CustomPaint(
          size: viewportSize,
          painter: _ConstellationOffscreenIndicatorPainter(
            layout: layout,
            transform: Matrix4.copy(transform.value),
          ),
        );
      },
    );
  }
}

/// Draws grouped edge bars for offscreen constellation items.
class _ConstellationOffscreenIndicatorPainter extends CustomPainter {
  const _ConstellationOffscreenIndicatorPainter({
    required this.layout,
    required this.transform,
  });

  final TaskConstellationLayout layout;
  final Matrix4 transform;

  /// Paints edge bars where offscreen items project onto the viewport edge.
  @override
  void paint(Canvas canvas, Size size) {
    final viewport = Offset.zero & size;
    final visible = viewport.deflate(16);
    final buckets =
        <_ConstellationIndicatorKey, _ConstellationIndicatorBucket>{};
    for (final anchor in layout.anchors) {
      _collectIndicator(
        buckets,
        size,
        visible,
        anchor.center,
        AuroraColors.green,
      );
    }
    for (final node in layout.nodes) {
      _collectIndicator(
        buckets,
        size,
        visible,
        node.center,
        _categoryColor(node.node.category),
      );
    }
    for (final bucket in buckets.values) {
      _paintBucket(canvas, size, bucket);
    }
  }

  /// Adds one offscreen item to a grouped edge indicator bucket.
  void _collectIndicator(
    Map<_ConstellationIndicatorKey, _ConstellationIndicatorBucket> buckets,
    Size size,
    Rect visible,
    Offset canvasPoint,
    Color color,
  ) {
    final viewportPoint = MatrixUtils.transformPoint(transform, canvasPoint);
    if (visible.contains(viewportPoint)) {
      return;
    }
    final hit = _edgeHit(size, viewportPoint);
    if (hit == null) {
      return;
    }
    final bucketIndex = hit.side.isVertical
        ? (hit.point.dy / 44).floor()
        : (hit.point.dx / 44).floor();
    final key = _ConstellationIndicatorKey(hit.side, bucketIndex);
    final bucket = buckets[key];
    if (bucket == null) {
      buckets[key] = _ConstellationIndicatorBucket(
        side: hit.side,
        point: hit.point,
        color: color,
      );
      return;
    }
    bucket.add(hit.point);
  }

  /// Returns the viewport-edge hit for a line from center to target.
  _ConstellationEdgeHit? _edgeHit(Size size, Offset target) {
    final center = Offset(size.width / 2, size.height / 2);
    final delta = target - center;
    if (delta.distance < 0.01) {
      return null;
    }
    final halfWidth = math.max(1.0, size.width / 2 - 8);
    final halfHeight = math.max(1.0, size.height / 2 - 8);
    final tx = delta.dx.abs() < 0.01
        ? double.infinity
        : halfWidth / delta.dx.abs();
    final ty = delta.dy.abs() < 0.01
        ? double.infinity
        : halfHeight / delta.dy.abs();
    final useVertical = tx < ty;
    final t = math.min(tx, ty);
    final raw = center + delta * t;
    if (useVertical) {
      final side = delta.dx < 0
          ? _ConstellationIndicatorSide.left
          : _ConstellationIndicatorSide.right;
      return _ConstellationEdgeHit(
        side: side,
        point: Offset(
          side == _ConstellationIndicatorSide.left ? 4 : size.width - 4,
          raw.dy.clamp(16, size.height - 16).toDouble(),
        ),
      );
    }
    final side = delta.dy < 0
        ? _ConstellationIndicatorSide.top
        : _ConstellationIndicatorSide.bottom;
    return _ConstellationEdgeHit(
      side: side,
      point: Offset(
        raw.dx.clamp(16, size.width - 16).toDouble(),
        side == _ConstellationIndicatorSide.top ? 4 : size.height - 4,
      ),
    );
  }

  /// Paints one grouped edge indicator.
  void _paintBucket(
    Canvas canvas,
    Size size,
    _ConstellationIndicatorBucket bucket,
  ) {
    final countBoost = math.min(28.0, bucket.count * 5.0);
    final length = 30.0 + countBoost;
    final thickness = math.min(12.0, 6.0 + bucket.count * 0.7);
    final center = bucket.edgeCenter(size);
    final rect = Rect.fromCenter(
      center: center,
      width: bucket.side.isVertical ? thickness : length,
      height: bucket.side.isVertical ? length : thickness,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(99));
    final shadow = Paint()
      ..style = PaintingStyle.fill
      ..color = bucket.color.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = bucket.color.withValues(alpha: 0.68);
    canvas
      ..drawRRect(rrect.shift(const Offset(0, 1)), shadow)
      ..drawRRect(rrect, paint);
    if (bucket.count > 1) {
      _paintBucketCount(canvas, bucket, center);
    }
  }

  /// Paints a small count beside grouped indicators.
  void _paintBucketCount(
    Canvas canvas,
    _ConstellationIndicatorBucket bucket,
    Offset center,
  ) {
    final label = bucket.count.toString();
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  /// Reports whether the edge hints need repainting.
  @override
  bool shouldRepaint(
    covariant _ConstellationOffscreenIndicatorPainter oldDelegate,
  ) {
    return oldDelegate.layout != layout || oldDelegate.transform != transform;
  }
}

/// _ConstellationIndicatorSide identifies one viewport edge.
enum _ConstellationIndicatorSide {
  /// Top viewport edge.
  top,

  /// Right viewport edge.
  right,

  /// Bottom viewport edge.
  bottom,

  /// Left viewport edge.
  left;

  /// Returns true for left/right edge indicators.
  bool get isVertical {
    return this == _ConstellationIndicatorSide.left ||
        this == _ConstellationIndicatorSide.right;
  }
}

/// _ConstellationEdgeHit stores an offscreen projection edge hit.
class _ConstellationEdgeHit {
  /// Creates an edge hit from a projected offscreen item.
  const _ConstellationEdgeHit({required this.side, required this.point});

  /// Viewport side hit by the projected line.
  final _ConstellationIndicatorSide side;

  /// Viewport edge point.
  final Offset point;
}

/// _ConstellationIndicatorKey groups nearby offscreen item hints.
class _ConstellationIndicatorKey {
  /// Creates a stable indicator bucket key.
  const _ConstellationIndicatorKey(this.side, this.index);

  /// Viewport side.
  final _ConstellationIndicatorSide side;

  /// Quantized side position.
  final int index;

  /// Compares indicator keys by side and bucket index.
  @override
  bool operator ==(Object other) {
    return other is _ConstellationIndicatorKey &&
        other.side == side &&
        other.index == index;
  }

  /// Hashes the side and bucket index.
  @override
  int get hashCode => Object.hash(side, index);
}

/// _ConstellationIndicatorBucket stores grouped offscreen indicator state.
class _ConstellationIndicatorBucket {
  /// Creates a grouped offscreen indicator.
  _ConstellationIndicatorBucket({
    required this.side,
    required this.point,
    required this.color,
  });

  /// Viewport side for this group.
  final _ConstellationIndicatorSide side;

  /// Representative edge point.
  Offset point;

  /// Representative item color.
  final Color color;

  /// Number of grouped items.
  int count = 1;

  /// Adds another projected item to this group.
  void add(Offset nextPoint) {
    point = Offset.lerp(point, nextPoint, 1 / (count + 1))!;
    count++;
  }

  /// Returns the bar center nudged inside the viewport.
  Offset edgeCenter(Size size) {
    return switch (side) {
      _ConstellationIndicatorSide.left => Offset(6, point.dy),
      _ConstellationIndicatorSide.right => Offset(size.width - 6, point.dy),
      _ConstellationIndicatorSide.top => Offset(point.dx, 6),
      _ConstellationIndicatorSide.bottom => Offset(point.dx, size.height - 6),
    };
  }
}

/// Shows the qualitative terrain insight projection.
class _PriorityTerrainView extends StatefulWidget {
  const _PriorityTerrainView({required this.controller});

  final AuroraAppController controller;

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
          child: PanelSectionBlock(
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
                      child: CustomPaint(painter: _TerrainPainter(layout)),
                    ),
                    for (final card in layout.cards)
                      if (_revealedTerrainTaskIds.contains(card.point.taskId))
                        _PositionedTerrainCard(
                          placement: card,
                          selected: selectedTaskId == card.point.taskId,
                          onTap: () => controller.selectTask(card.point.taskId),
                        ),
                    for (final cluster in layout.clusters)
                      _PositionedTerrainCluster(
                        cluster: cluster,
                        expanded: _isTerrainClusterRevealed(cluster),
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
                                  _revealedTerrainTaskIds = const <String>{};
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
    return Tooltip(
      message: TaskTerrainModeRegistry.question(value),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AuroraColors.panel,
          border: Border.all(color: AuroraColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<TaskTerrainInsightMode>(
            value: value,
            borderRadius: BorderRadius.circular(8),
            icon: const Icon(Icons.keyboard_arrow_down, size: 16),
            style: const TextStyle(
              color: AuroraColors.ink,
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
            color: open ? AuroraColors.greenSoft : AuroraColors.panel,
            border: Border.all(
              color: open ? AuroraColors.green : AuroraColors.border,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.tune,
                size: 16,
                color: open ? AuroraColors.green : AuroraColors.muted,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: open ? AuroraColors.green : AuroraColors.ink,
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
    return Positioned(
      top: 10,
      right: 10,
      bottom: 10,
      width: 314,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AuroraColors.surface.withValues(alpha: 0.98),
          border: Border.all(color: AuroraColors.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: <BoxShadow>[
            BoxShadow(
              blurRadius: 22,
              offset: const Offset(0, 10),
              color: Colors.black.withValues(alpha: 0.08),
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
                  const Icon(Icons.tune, size: 16, color: AuroraColors.green),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      activeCount == 0
                          ? 'Area overlays'
                          : 'Area overlays $activeCount',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AuroraColors.ink,
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
    return Tooltip(
      message: label,
      child: _TerrainDropdownShell(
        child: Row(
          children: <Widget>[
            Text(
              '$label:',
              style: const TextStyle(
                color: AuroraColors.muted,
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
                  icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                  style: _terrainDropdownTextStyle,
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
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AuroraColors.panel,
        border: Border.all(color: AuroraColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

/// Shared text style for terrain dropdown controls.
const TextStyle _terrainDropdownTextStyle = TextStyle(
  color: AuroraColors.ink,
  fontSize: 13,
  fontWeight: FontWeight.w900,
);

/// Renders one full terrain task card from computed layout geometry.
class _PositionedTerrainCard extends StatelessWidget {
  const _PositionedTerrainCard({
    required this.placement,
    required this.selected,
    required this.onTap,
  });

  final TaskTerrainCardPlacement placement;
  final bool selected;
  final VoidCallback onTap;

  /// Builds one promoted task card on the terrain.
  @override
  Widget build(BuildContext context) {
    final point = placement.point;
    final color = placement.color;
    return Positioned(
      left: placement.rect.left,
      top: placement.rect.top,
      width: placement.rect.width,
      height: placement.rect.height,
      child: Tooltip(
        message: point.explanation,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AuroraColors.greenSoft
                  : const Color(0xfffffcf8),
              border: Border.all(color: selected ? AuroraColors.green : color),
              borderRadius: BorderRadius.circular(8),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  blurRadius: point.riskScore >= 0.6 ? 18 : 12,
                  offset: const Offset(0, 5),
                  color: color.withValues(
                    alpha: point.riskScore >= 0.6 ? 0.24 : 0.15,
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
                      Text(
                        point.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        placement.cue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AuroraColors.muted,
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
                                  : 'Due ${_formatShortDate(point.dueAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
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
    );
  }
}

/// Renders one compact terrain task marker.
class _PositionedTerrainPin extends StatelessWidget {
  const _PositionedTerrainPin({
    required this.pin,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final TaskTerrainPinPlacement pin;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  /// Builds one low-detail task pin.
  @override
  Widget build(BuildContext context) {
    final point = pin.point;
    final color = pin.color;
    return Positioned(
      left: pin.center.dx - 14,
      top: pin.center.dy - 14,
      width: 28,
      height: 28,
      child: Tooltip(
        message: '${point.title}\n${pin.zone.label}',
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected || expanded
                  ? AuroraColors.green
                  : color.withValues(alpha: 0.9),
              border: Border.all(
                color: expanded ? AuroraColors.ink : const Color(0xfffffcf8),
                width: expanded ? 2.4 : 2,
              ),
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(blurRadius: 8, color: color.withValues(alpha: 0.2)),
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
    );
  }
}

/// Renders a terrain cluster marker for nearby low-detail tasks.
class _PositionedTerrainCluster extends StatelessWidget {
  const _PositionedTerrainCluster({
    required this.cluster,
    required this.expanded,
    required this.onTap,
  });

  final TaskTerrainClusterPlacement cluster;
  final bool expanded;
  final VoidCallback onTap;

  /// Builds one count badge for clustered low-detail tasks.
  @override
  Widget build(BuildContext context) {
    final color = cluster.color;
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: expanded
                  ? AuroraColors.green
                  : color.withValues(alpha: 0.9),
              border: Border.all(
                color: expanded ? AuroraColors.ink : const Color(0xfffffcf8),
                width: expanded ? 2.4 : 2,
              ),
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(blurRadius: 10, color: color.withValues(alpha: 0.22)),
              ],
            ),
            child: Center(
              child: Text(
                cluster.points.length.toString(),
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
    );
  }
}

class _ProjectionToolbar extends StatelessWidget {
  const _ProjectionToolbar({required this.left, this.right = const <Widget>[]});

  final List<Widget> left;
  final List<Widget> right;

  /// Builds compact projection controls above canvases.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: left)),
        if (right.isNotEmpty) ...<Widget>[
          const SizedBox(width: 12),
          Wrap(spacing: 8, runSpacing: 8, children: right),
        ],
      ],
    );
  }
}

class _ConstellationPainter extends CustomPainter {
  const _ConstellationPainter({required this.layout, this.selectedEdge});

  final TaskConstellationLayout layout;
  final TaskConstellationEdge? selectedEdge;

  /// Paints anchor spokes and relation edges.
  @override
  void paint(Canvas canvas, Size size) {
    final anchors = layout.anchorById;
    final nodes = layout.nodeByTaskId;
    for (final node in layout.nodes) {
      final anchorId = node.anchorId;
      final anchor = anchorId == null ? null : anchors[anchorId];
      if (anchor == null || !layout.expandedAnchorIds.contains(anchor.id)) {
        continue;
      }
      final edge = layout.anchorMembershipEdge(anchor, node);
      final selected = _sameConstellationEdge(edge, selectedEdge);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3.2 : 1
        ..strokeCap = StrokeCap.round
        ..color = AuroraColors.green.withValues(alpha: selected ? 0.82 : 0.1);
      if (selected) {
        final halo = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = AuroraColors.green.withValues(alpha: 0.14);
        canvas.drawLine(anchor.center, node.center, halo);
      }
      canvas.drawLine(anchor.center, node.center, paint);
    }
    final selectedEdges = <TaskConstellationEdge>[];
    for (final edge in layout.visibleEdges) {
      if (_sameConstellationEdge(edge, selectedEdge)) {
        selectedEdges.add(edge);
        continue;
      }
      final from = nodes[edge.fromTaskId];
      final to = nodes[edge.toTaskId];
      if (from == null || to == null) {
        continue;
      }
      final highlighted = _constellationEdgeIsHighlighted(edge);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlighted ? 3 : 1
        ..strokeCap = StrokeCap.round
        ..color = _edgeColor(edge).withValues(alpha: highlighted ? 0.76 : 0.18);
      if (highlighted) {
        final halo = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = _edgeColor(edge).withValues(alpha: 0.12);
        canvas.drawLine(from.center, to.center, halo);
      }
      canvas.drawLine(from.center, to.center, paint);
    }
    for (final edge in selectedEdges) {
      final from = nodes[edge.fromTaskId];
      final to = nodes[edge.toTaskId];
      if (from == null || to == null) {
        continue;
      }
      final color = _edgeColor(edge);
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.16);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.8
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.9);
      canvas
        ..drawLine(from.center, to.center, halo)
        ..drawLine(from.center, to.center, paint);
    }
  }

  /// Reports whether this painter needs repainting.
  @override
  bool shouldRepaint(covariant _ConstellationPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        !_sameConstellationEdge(oldDelegate.selectedEdge, selectedEdge);
  }
}

/// Paints the terrain atlas behind terrain markers.
class _TerrainPainter extends CustomPainter {
  const _TerrainPainter(this.layout);

  final TaskTerrainLayout layout;

  /// Paints the visible terrain atlas and score guides.
  @override
  void paint(Canvas canvas, Size size) {
    _paintZones(canvas);
    _paintAxes(canvas);
  }

  /// Paints touching named terrain zones so placement boundaries are visible.
  void _paintZones(Canvas canvas) {
    for (final zone in layout.zones) {
      final rect = zone.rect;
      final color = zone.definition.color;
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.045);
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.14);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, border);
      _paintZoneLabel(canvas, zone);
    }
  }

  /// Paints one terrain zone label and visible task count.
  void _paintZoneLabel(Canvas canvas, TaskTerrainZoneRegion zone) {
    final color = zone.definition.color;
    final count = zone.taskCount == 0 ? '' : '  ${zone.taskCount}';
    final text = TextSpan(
      children: <InlineSpan>[
        TextSpan(
          text: '${zone.definition.label.toUpperCase()}$count\n',
          style: TextStyle(
            color: color.withValues(alpha: 0.72),
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        TextSpan(
          text: zone.definition.description,
          style: TextStyle(
            color: AuroraColors.muted.withValues(alpha: 0.72),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    final painter = TextPainter(
      text: text,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    )..layout(maxWidth: math.max(64, zone.rect.width - 18));
    painter.paint(canvas, zone.rect.topLeft + const Offset(10, 9));
  }

  /// Paints quiet reward and pressure score axes.
  void _paintAxes(Canvas canvas) {
    final paint = Paint()
      ..color = AuroraColors.border.withValues(alpha: 0.42)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(
        layout.mapArea.left + layout.mapArea.width / 2,
        layout.mapArea.top,
      ),
      Offset(
        layout.mapArea.left + layout.mapArea.width / 2,
        layout.mapArea.bottom,
      ),
      paint,
    );
    canvas.drawLine(
      Offset(
        layout.mapArea.left,
        layout.mapArea.top + layout.mapArea.height / 2,
      ),
      Offset(
        layout.mapArea.right,
        layout.mapArea.top + layout.mapArea.height / 2,
      ),
      paint,
    );
    _paintAxisLabel(
      canvas,
      layout.xAxisLabel,
      Offset(layout.mapArea.right - 116, layout.mapArea.bottom - 18),
    );
    _paintAxisLabel(
      canvas,
      layout.yAxisLabel,
      Offset(layout.mapArea.left + 12, layout.mapArea.bottom - 18),
    );
  }

  /// Paints a small axis label.
  void _paintAxisLabel(Canvas canvas, String label, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: AuroraColors.muted.withValues(alpha: 0.72),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 130);
    painter.paint(canvas, offset);
  }

  /// Reports whether this painter needs repainting.
  @override
  bool shouldRepaint(covariant _TerrainPainter oldDelegate) {
    return oldDelegate.layout != layout;
  }
}

/// Returns an empty-state label with projection loading detail when available.
String _emptyProjectionLabel(AuroraAppController controller, String fallback) {
  final message = _firstNonEmpty(<String>[
    controller.taskInsightMessage.trim(),
    controller.taskProjectionMessage.trim(),
  ]);
  if (message.isEmpty) {
    return fallback;
  }
  return message;
}

/// Returns missing WBS fields for display diagnostics.
List<String> _wbsMissingFields(WorkspaceTask task) {
  final workBreakdown = task.workBreakdown;
  return <String>[
    if (workBreakdown.code.trim().isEmpty) 'code',
    if (workBreakdown.deliverable.trim().isEmpty) 'deliverable',
    if (workBreakdown.startCriteria.isEmpty) 'start',
    if (workBreakdown.acceptanceCriteria.isEmpty) 'done',
    if (workBreakdown.resources.isEmpty) 'resources',
    if (workBreakdown.requirementRefs.isEmpty) 'requirements',
    if (workBreakdown.rubricRefs.isEmpty) 'rubric',
    if (task.estimateMinutes <= 0) 'time',
    if (workBreakdown.estimatedCostCents <= 0) 'spend',
  ];
}

/// Summarizes one WBS resource for a table cell.
String _resourceSummary(TaskResourceRequirement resource) {
  final details = <String>[
    if (resource.type.isNotEmpty) resource.type,
    if (resource.quantity > 0)
      '${formatTaskQuantity(resource.quantity)} ${resource.unit}'.trim(),
    formatTaskResourceSpend(resource),
  ].where((item) => item.isNotEmpty).toList();
  if (details.isEmpty) {
    return resource.name;
  }
  return '${resource.name} · ${details.join(' · ')}';
}

/// Returns a terrain empty state tailored to the selected insight mode.
String _emptyTerrainLabel(TaskTerrainInsightMode mode) {
  return switch (mode) {
    TaskTerrainInsightMode.agentHandoff =>
      'No agent handoff candidates found. Add safety, obligation, and context metadata to enable handoff analysis.',
    TaskTerrainInsightMode.nextWeekHighValue =>
      'No high-value next-week backlog items found. Add due dates, value type, consequence, or commitments to improve this view.',
    TaskTerrainInsightMode.unblockLeverage =>
      'No quick unblocks found. Add dependency relations or mark waiting/blocking backlog items to enable unblock analysis.',
    TaskTerrainInsightMode.riskConfidence =>
      'No risk confidence gaps found. Low-confidence or high-risk backlog items will appear here.',
    TaskTerrainInsightMode.priorityFocus =>
      'No terrain projection available. The graph service did not return a canonical insight graph, or there are no active backlog items.',
  };
}

/// Returns the layout grouping that best matches a graph query result.
TaskConstellationAnchorDimension _constellationAnchorDimensionForQuery(
  TaskGraphQueryGroup group,
) {
  return switch (group) {
    TaskGraphQueryGroup.project => TaskConstellationAnchorDimension.project,
    TaskGraphQueryGroup.owner => TaskConstellationAnchorDimension.owner,
    TaskGraphQueryGroup.status => TaskConstellationAnchorDimension.status,
    TaskGraphQueryGroup.time => TaskConstellationAnchorDimension.time,
    TaskGraphQueryGroup.metadata => TaskConstellationAnchorDimension.category,
  };
}

/// Returns the first non-empty text value.
String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

/// Formats a compact date.
String _formatShortDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  return '${local.month}/${local.day}';
}

/// Returns a color for a constellation category.
Color _categoryColor(String category) {
  final normalized = category.toLowerCase();
  if (normalized.contains('errand') || normalized.contains('shopping')) {
    return const Color(0xffd99a22);
  }
  if (normalized.contains('work')) {
    return AuroraColors.green;
  }
  if (normalized.contains('health')) {
    return const Color(0xff5f87b4);
  }
  if (normalized.contains('personal')) {
    return const Color(0xff7b6398);
  }
  return AuroraColors.border;
}

/// Returns a color for a constellation edge.
Color _edgeColor(TaskConstellationEdge edge) {
  if (edge.source == 'query_path') {
    return AuroraColors.green;
  }
  if (edge.source == 'critical_path') {
    return AuroraColors.coral;
  }
  if (edge.source == 'materialized_risk') {
    return const Color(0xff7b6398);
  }
  if (edge.relationType == 'depends_on' || edge.relationType == 'blocks') {
    return AuroraColors.coral;
  }
  if (edge.source == 'explicit') {
    return AuroraColors.green;
  }
  return AuroraColors.muted;
}

/// Returns whether a constellation edge should be visually emphasized.
bool _constellationEdgeIsHighlighted(TaskConstellationEdge edge) {
  return edge.source == 'query_path' ||
      edge.source == 'critical_path' ||
      edge.source == 'materialized_risk';
}

/// Returns true when two constellation edges represent the same relation.
bool _sameConstellationEdge(
  TaskConstellationEdge? left,
  TaskConstellationEdge? right,
) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.fromTaskId == right.fromTaskId &&
      left.toTaskId == right.toTaskId &&
      left.relationType == right.relationType &&
      left.source == right.source &&
      left.explanation == right.explanation;
}
