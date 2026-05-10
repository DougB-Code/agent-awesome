/// Implements the first-class backlog workspace panels.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/theme.dart';
import '../domain/models.dart';
import '../domain/screen_command.dart';
import '../domain/task_insight_explanations.dart';
import '../domain/task_insight_query.dart';
import 'panels/panels.dart';
import 'task_concept_views.dart';
import 'task_insight_presets.dart';
import 'task_wbs_formatting.dart';

const List<String> _taskStatuses = <String>[
  'open',
  'waiting',
  'blocked',
  'done',
  'canceled',
];

const List<String> _activeTaskStatuses = <String>['open', 'waiting', 'blocked'];

const List<String> _taskPriorities = <String>[
  'urgent',
  'high',
  'normal',
  'low',
];

const List<String> _taskRelationTypes = <String>[
  'related_to',
  'depends_on',
  'blocks',
  'part_of',
  'enables',
];

/// _TaskFilterView identifies bundled queue filter modes.
enum _TaskFilterView {
  /// Open, waiting, and blocked backlog items.
  active,

  /// Every backlog item status.
  all,
}

/// _BacklogDetailMode identifies the right-side backlog details view.
enum _BacklogDetailMode {
  /// Task and relation inspector.
  inspector,

  /// Selected task memory linking tools.
  memoryLinks,

  /// Screen-command review queue.
  aiReview,
}

/// Builds the canonical backlog command areas used by the command subshell.
List<SwitcherPanelArea> _backlogCommandAreas(
  AgentAwesomeAppController controller,
) {
  return <SwitcherPanelArea>[
    SwitcherPanelArea(
      title: 'Queue',
      icon: Icons.task_alt_outlined,
      builder: (query) =>
          _BacklogQueueContent(controller: controller, query: query),
    ),
    SwitcherPanelArea(
      title: 'Stream',
      icon: Icons.waves_outlined,
      builder: (query) => TaskConceptProjectionPanel(
        controller: controller,
        kind: TaskConceptKind.stream,
      ),
    ),
    SwitcherPanelArea(
      title: 'Terrain',
      icon: Icons.terrain_outlined,
      builder: (query) => TaskConceptProjectionPanel(
        controller: controller,
        kind: TaskConceptKind.terrain,
      ),
    ),
    SwitcherPanelArea(
      title: 'WBS',
      icon: Icons.account_tree_outlined,
      builder: (query) => TaskConceptProjectionPanel(
        controller: controller,
        kind: TaskConceptKind.wbs,
      ),
    ),
    SwitcherPanelArea(
      title: 'Constellation',
      icon: Icons.hub_outlined,
      builder: (query) => TaskConceptProjectionPanel(
        controller: controller,
        kind: TaskConceptKind.constellation,
      ),
    ),
    SwitcherPanelArea(
      title: 'Capture',
      icon: Icons.add_task_outlined,
      builder: (query) =>
          _TaskCaptureContent(controller: controller, query: query),
    ),
  ];
}

/// Returns the details modes available for the current backlog state.
List<CommandPanelDetailMode> _visibleBacklogDetailModes(
  AgentAwesomeAppController controller,
) {
  return <CommandPanelDetailMode>[
    _backlogDetailMode(_BacklogDetailMode.inspector),
    _backlogDetailMode(_BacklogDetailMode.memoryLinks),
    if (_backlogReviewAvailable(controller))
      _backlogDetailMode(_BacklogDetailMode.aiReview),
  ];
}

/// Reports whether there is an AI screen-command run worth reviewing.
bool _backlogReviewAvailable(AgentAwesomeAppController controller) {
  return controller.activeScreenCommandRun?.changes.isNotEmpty ?? false;
}

/// Returns the stable id for a backlog detail mode.
String _backlogDetailModeId(_BacklogDetailMode mode) {
  return switch (mode) {
    _BacklogDetailMode.inspector => 'inspector',
    _BacklogDetailMode.memoryLinks => 'memory_links',
    _BacklogDetailMode.aiReview => 'ai_review',
  };
}

/// Converts a stable detail mode id into a backlog detail mode.
_BacklogDetailMode _backlogDetailModeForId(String id) {
  if (id == _backlogDetailModeId(_BacklogDetailMode.memoryLinks)) {
    return _BacklogDetailMode.memoryLinks;
  }
  if (id == _backlogDetailModeId(_BacklogDetailMode.aiReview)) {
    return _BacklogDetailMode.aiReview;
  }
  return _BacklogDetailMode.inspector;
}

/// Creates a reusable command-panel detail mode for one backlog mode.
CommandPanelDetailMode _backlogDetailMode(_BacklogDetailMode mode) {
  return CommandPanelDetailMode(
    id: _backlogDetailModeId(mode),
    label: _backlogDetailLabel(mode),
    icon: _backlogDetailIcon(mode),
  );
}

/// Returns the visible label for a backlog detail mode.
String _backlogDetailLabel(_BacklogDetailMode mode) {
  return switch (mode) {
    _BacklogDetailMode.inspector => 'Inspector',
    _BacklogDetailMode.memoryLinks => 'Memory',
    _BacklogDetailMode.aiReview => 'AI review',
  };
}

/// Returns the icon for a backlog detail mode.
IconData _backlogDetailIcon(_BacklogDetailMode mode) {
  return switch (mode) {
    _BacklogDetailMode.inspector => Icons.edit_note_outlined,
    _BacklogDetailMode.memoryLinks => Icons.link_outlined,
    _BacklogDetailMode.aiReview => Icons.auto_awesome_outlined,
  };
}

/// BacklogCommandPanel renders backlog work in the official command subshell.
class BacklogCommandPanel extends StatefulWidget {
  /// Creates the backlog command panel.
  const BacklogCommandPanel({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Reports the active command area to the app shell.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  @override
  State<BacklogCommandPanel> createState() => _BacklogCommandPanelState();
}

/// _BacklogCommandPanelState stores the selected backlog detail mode.
class _BacklogCommandPanelState extends State<BacklogCommandPanel> {
  _BacklogDetailMode _detailMode = _BacklogDetailMode.inspector;

  /// Builds backlog areas and details inside the reusable command subshell.
  @override
  Widget build(BuildContext context) {
    final selectedMode = _effectiveDetailMode();
    return CommandPanelSubShell(
      areas: _backlogCommandAreas(widget.controller),
      detailTitle: 'Backlog Inspector',
      detailModes: _visibleBacklogDetailModes(widget.controller),
      selectedDetailModeId: _backlogDetailModeId(selectedMode),
      onDetailModeSelected: _selectDetailMode,
      detailBuilder: _buildDetailBody,
      onAreaChanged: widget.onAreaChanged,
      areaActionsBuilder: _buildAreaActions,
      filterHint: 'Filter...',
    );
  }

  /// Builds header actions for the active command area.
  Widget? _buildAreaActions(BuildContext context, SwitcherPanelArea area) {
    if (area.title != 'Queue') {
      return null;
    }
    return _BacklogQueueHeaderActions(controller: widget.controller);
  }

  /// Selects the right-side details mode and mirrors review state to controller.
  void _selectDetailMode(String modeId) {
    final mode = _backlogDetailModeForId(modeId);
    if (mode == _BacklogDetailMode.aiReview) {
      widget.controller.openBacklogReviewPanel();
    } else {
      widget.controller.openBacklogInspectorPanel();
    }
    setState(() {
      _detailMode = mode;
    });
  }

  /// Returns the visible details mode, honoring controller-owned AI review state.
  _BacklogDetailMode _effectiveDetailMode() {
    final hasReview = _backlogReviewAvailable(widget.controller);
    if (widget.controller.backlogReviewPanelOpen && hasReview) {
      return _BacklogDetailMode.aiReview;
    }
    return _detailMode == _BacklogDetailMode.aiReview
        ? _BacklogDetailMode.inspector
        : _detailMode;
  }

  /// Builds the content for the current detail mode id.
  Widget _buildDetailBody(String modeId) {
    final mode = _backlogDetailModeForId(modeId);
    final edge = widget.controller.selectedConstellationEdge;
    final task = widget.controller.selectedTask;
    return switch (mode) {
      _BacklogDetailMode.memoryLinks =>
        task == null
            ? const _TaskSelectionEmpty()
            : _TaskMemoryLinkPanel(
                controller: widget.controller,
                task: task,
                query: '',
              ),
      _BacklogDetailMode.aiReview => _BacklogReviewContent(
        controller: widget.controller,
      ),
      _BacklogDetailMode.inspector =>
        edge != null
            ? _TaskConstellationEdgeInspector(
                controller: widget.controller,
                edge: edge,
              )
            : task == null
            ? const _TaskSelectionEmpty()
            : _TaskDetailEditor(controller: widget.controller, task: task),
    };
  }
}

/// _BacklogReviewContent renders screen-command changes in the detail panel.
class _BacklogReviewContent extends StatelessWidget {
  /// Creates the backlog review detail content.
  const _BacklogReviewContent({required this.controller});

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Builds the current screen-command review list.
  @override
  Widget build(BuildContext context) {
    final run = controller.activeScreenCommandRun;
    if (run == null) {
      return const PanelEmptyBlock(label: 'No AI changes to review');
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Review Changes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Tooltip(
                message: 'Show inspector',
                child: IconButton(
                  onPressed: controller.openBacklogInspectorPanel,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ScreenRunSummaryBlock(controller: controller, run: run),
          const SizedBox(height: 12),
          if (run.changes.isEmpty)
            const PanelEmptyBlock(label: 'No changes match this view')
          else
            for (final change in run.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ScreenChangeReviewCard(
                  controller: controller,
                  change: change,
                ),
              ),
        ],
      ),
    );
  }
}

class _ScreenRunSummaryBlock extends StatelessWidget {
  const _ScreenRunSummaryBlock({required this.controller, required this.run});

  final AgentAwesomeAppController controller;
  final ScreenCommandRun run;

  /// Builds summary counts for one screen-command run.
  @override
  Widget build(BuildContext context) {
    final applied = run.changes
        .where((change) => change.status == ScreenChangeStatus.applied)
        .length;
    final review = run.changes
        .where((change) => change.status == ScreenChangeStatus.proposed)
        .length;
    final rejected = run.changes
        .where((change) => change.status == ScreenChangeStatus.rejected)
        .length;
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'AI found ${run.changes.length} changes',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            controller.screenCommandMessage,
            style: TextStyle(color: context.agentAwesomeColors.muted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _TaskBadge(label: 'Applied $applied'),
              _TaskBadge(label: 'Needs review $review'),
              _TaskBadge(label: 'Rejected $rejected'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScreenChangeReviewCard extends StatelessWidget {
  const _ScreenChangeReviewCard({
    required this.controller,
    required this.change,
  });

  final AgentAwesomeAppController controller;
  final ScreenChange change;

  /// Builds one reviewable AI change card.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final focused = controller.focusedScreenChangeId == change.id;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => controller.focusBacklogScreenChange(change.id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: focused ? colors.greenSoft : colors.surface,
          gradient: focused
              ? context.agentAwesomeSelectedGradient
              : context.agentAwesomeCardGradient,
          border: Border.all(color: focused ? colors.green : colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  _screenChangeIcon(change),
                  size: 18,
                  color: _screenChangeColor(context, change),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    change.summary,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 8),
                _TaskBadge(label: _screenChangeStatusLabel(change)),
              ],
            ),
            if (change.reason.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(change.reason, style: TextStyle(color: colors.muted)),
            ],
            if (change.error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                change.error,
                style: const TextStyle(
                  color: AgentAwesomeColors.coral,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _ScreenChangeDiffList(change: change),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Tooltip(
                  message: 'Focus change',
                  child: IconButton.outlined(
                    onPressed: () =>
                        controller.focusBacklogScreenChange(change.id),
                    icon: const Icon(Icons.center_focus_strong, size: 18),
                  ),
                ),
                const Spacer(),
                if (change.status == ScreenChangeStatus.proposed &&
                    change.safety != ScreenChangeSafety.rejected) ...<Widget>[
                  Tooltip(
                    message: 'Apply change',
                    child: IconButton.filled(
                      onPressed: controller.screenCommandBusy
                          ? null
                          : () => unawaited(
                              controller.applyScreenChangeFromUi(change.id),
                            ),
                      icon: const Icon(Icons.check, size: 18),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Reject change',
                    child: IconButton.outlined(
                      onPressed: controller.screenCommandBusy
                          ? null
                          : () => unawaited(
                              controller.rejectScreenChangeFromUi(change.id),
                            ),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
                ],
                if (controller.screenChangeCanUndo(change))
                  Tooltip(
                    message: 'Undo change',
                    child: IconButton.outlined(
                      onPressed: controller.screenCommandBusy
                          ? null
                          : () => unawaited(
                              controller.undoScreenChangeFromUi(change.id),
                            ),
                      icon: const Icon(Icons.undo, size: 18),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenChangeDiffList extends StatelessWidget {
  const _ScreenChangeDiffList({required this.change});

  final ScreenChange change;

  /// Builds before/after diff rows for one change.
  @override
  Widget build(BuildContext context) {
    final keys = <String>{
      ...change.beforeValues.keys,
      ...change.afterValues.keys,
    }.toList();
    if (keys.isEmpty) {
      final colors = context.agentAwesomeColors;
      return Text(
        _screenChangeOperationLabel(change.operation),
        style: TextStyle(color: colors.muted),
      );
    }
    final colors = context.agentAwesomeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final key in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 110,
                  child: Text(
                    _taskLabel(key.replaceAll('_', ' ')),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _screenValueLabel(change.beforeValues[key]),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 16),
                ),
                Expanded(
                  child: Text(
                    _screenValueLabel(change.afterValues[key]),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.green,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// _TaskMemoryLinkScaffold renders selected-memory and linked-memory sections.
class _TaskMemoryLinkScaffold extends StatelessWidget {
  const _TaskMemoryLinkScaffold({
    required this.selectedMemory,
    required this.links,
    required this.onLink,
    required this.onUnlink,
  });

  final MemoryRecord? selectedMemory;
  final List<TaskMemoryLink> links;
  final VoidCallback? onLink;
  final ValueChanged<TaskMemoryLink>? onUnlink;

  /// Builds reusable selected-memory and linked-memory sections.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: _TaskPanelLabel('Selected Memory')),
              Tooltip(
                message: 'Link selected memory',
                child: OutlinedButton.icon(
                  onPressed: onLink,
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Link'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _TaskSelectedMemoryBlock(memory: selectedMemory),
          const SizedBox(height: 12),
          _TaskMemoryLinksBlock(links: links, onUnlink: onUnlink),
        ],
      ),
    );
  }
}

class _BacklogQueueContent extends StatelessWidget {
  const _BacklogQueueContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds the filtered operational backlog queue.
  @override
  Widget build(BuildContext context) {
    final presetTaskIds = _queuePresetTaskIds(controller);
    final tasks = controller.filteredTasks.where((task) {
      final presetMatches =
          controller.taskInsightPresetId == TaskInsightIds.all ||
          presetTaskIds.contains(task.id);
      return presetMatches && _matchesTask(task, query);
    }).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TaskQueueFilterStrip(controller: controller),
          const SizedBox(height: 14),
          if (tasks.isEmpty)
            const PanelEmptyBlock(label: 'No backlog items match this view')
          else
            for (final task in tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TaskQueueTile(
                  task: task,
                  selected: controller.selectedTask?.id == task.id,
                  focused: controller.focusedBacklogTaskId == task.id,
                  changes: controller.screenChangesForTask(task.id),
                  onTap: () => controller.inspectBacklogTask(task.id),
                  onScheduleToday: () => unawaited(
                    controller.updateTaskFromUi(
                      taskId: task.id,
                      scheduledAt: _todayDate(),
                    ),
                  ),
                  onSnooze: () => unawaited(
                    controller.updateTaskFromUi(
                      taskId: task.id,
                      scheduledAt: _todayDate().add(const Duration(days: 1)),
                    ),
                  ),
                  onComplete: task.done || task.status == 'canceled'
                      ? null
                      : () => unawaited(controller.completeTaskFromUi(task.id)),
                  onDelete: () =>
                      unawaited(controller.deleteTaskFromUi(task.id)),
                  insightBadges: _insightBadgesForTask(controller, task),
                ),
              ),
        ],
      ),
    );
  }
}

/// _BacklogQueueHeaderActions renders Queue commands in the subshell header.
class _BacklogQueueHeaderActions extends StatelessWidget {
  const _BacklogQueueHeaderActions({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds create controls beside the command-area icons.
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Tooltip(
          message: 'New backlog item',
          child: IconButton.filled(
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            onPressed: controller.tasksBusy
                ? null
                : () => unawaited(_showTaskCreateDialog(context, controller)),
            icon: const Icon(Icons.add, size: 20),
          ),
        ),
      ],
    );
  }
}

/// _TaskQueueFilterStrip consolidates queue filters into compact menus.
class _TaskQueueFilterStrip extends StatelessWidget {
  const _TaskQueueFilterStrip({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds a one-row dropdown filter surface for the backlog queue.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          _TaskInsightPresetMenu(controller: controller),
          _TaskViewMenu(controller: controller),
          _TaskStatusFilterMenu(controller: controller),
          _TaskPriorityFilterMenu(controller: controller),
          _TaskTopicFilterMenu(controller: controller),
        ],
      ),
    );
  }
}

/// _TaskInsightPresetMenu renders semantic Queue presets as one dropdown.
class _TaskInsightPresetMenu extends StatelessWidget {
  const _TaskInsightPresetMenu({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds the preset dropdown.
  @override
  Widget build(BuildContext context) {
    final selected = _selectedTaskInsightPreset(controller);
    return PopupMenuButton<String>(
      tooltip: 'Insight preset',
      onSelected: (presetId) {
        unawaited(controller.applyTaskInsightPreset(presetId));
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        for (final preset in TaskInsightPresetRegistry.queuePresets)
          CheckedPopupMenuItem<String>(
            value: preset.id,
            checked: controller.taskInsightPresetId == preset.id,
            child: _TaskFilterMenuItem(
              icon: TaskInsightPresetRegistry.iconFor(preset.iconName),
              label: _presetLabel(controller, preset),
            ),
          ),
      ],
      child: _TaskFilterMenuButton(
        icon: TaskInsightPresetRegistry.iconFor(selected.iconName),
        label: _presetButtonLabel(controller, selected),
        selected: true,
      ),
    );
  }
}

/// _TaskViewMenu renders bundled active/all queue filter choices.
class _TaskViewMenu extends StatelessWidget {
  const _TaskViewMenu({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds the view dropdown.
  @override
  Widget build(BuildContext context) {
    final filters = controller.taskFilters;
    return PopupMenuButton<_TaskFilterView>(
      tooltip: 'Task view',
      onSelected: (view) {
        unawaited(
          controller.applyTaskFilters(switch (view) {
            _TaskFilterView.active => filters.copyWith(
              statuses: _activeTaskStatuses,
              includeDone: true,
            ),
            _TaskFilterView.all => filters.copyWith(
              statuses: const <String>[],
              includeDone: true,
            ),
          }),
        );
      },
      itemBuilder: (context) => <PopupMenuEntry<_TaskFilterView>>[
        CheckedPopupMenuItem<_TaskFilterView>(
          value: _TaskFilterView.active,
          checked: _isActiveTaskView(filters),
          child: const _TaskFilterMenuItem(
            icon: Icons.playlist_play,
            label: 'Active',
          ),
        ),
        CheckedPopupMenuItem<_TaskFilterView>(
          value: _TaskFilterView.all,
          checked: filters.statuses.isEmpty,
          child: const _TaskFilterMenuItem(
            icon: Icons.all_inbox_outlined,
            label: 'All tasks',
          ),
        ),
      ],
      child: _TaskFilterMenuButton(
        icon: _taskViewIcon(filters),
        label: _taskViewLabel(filters),
        selected: true,
      ),
    );
  }
}

/// _TaskStatusFilterMenu renders status and overdue filters as one dropdown.
class _TaskStatusFilterMenu extends StatelessWidget {
  const _TaskStatusFilterMenu({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds the status dropdown.
  @override
  Widget build(BuildContext context) {
    final filters = controller.taskFilters;
    return PopupMenuButton<String>(
      tooltip: 'Status filters',
      onSelected: (value) {
        final next = switch (value) {
          '__any_status' => filters.copyWith(
            statuses: const <String>[],
            overdueOnly: false,
          ),
          '__overdue' => filters.copyWith(overdueOnly: !filters.overdueOnly),
          _ => filters.copyWith(
            statuses: _toggleFilterValue(filters.statuses, value),
          ),
        };
        unawaited(controller.applyTaskFilters(next));
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        CheckedPopupMenuItem<String>(
          value: '__any_status',
          checked: filters.statuses.isEmpty && !filters.overdueOnly,
          child: const _TaskFilterMenuItem(
            icon: Icons.clear_all,
            label: 'Any status',
          ),
        ),
        const PopupMenuDivider(),
        for (final status in _taskStatuses)
          CheckedPopupMenuItem<String>(
            value: status,
            checked: filters.statuses.contains(status),
            child: _TaskFilterMenuItem(
              icon: Icons.task_alt_outlined,
              label: _taskLabel(status),
            ),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<String>(
          value: '__overdue',
          checked: filters.overdueOnly,
          child: const _TaskFilterMenuItem(
            icon: Icons.warning_amber_outlined,
            label: 'Overdue',
          ),
        ),
      ],
      child: _TaskFilterMenuButton(
        icon: Icons.task_alt_outlined,
        label: _statusFilterLabel(filters),
        selected:
            (!_isActiveTaskView(filters) && filters.statuses.isNotEmpty) ||
            filters.overdueOnly,
      ),
    );
  }
}

/// _TaskPriorityFilterMenu renders priority filters as one dropdown.
class _TaskPriorityFilterMenu extends StatelessWidget {
  const _TaskPriorityFilterMenu({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds the priority dropdown.
  @override
  Widget build(BuildContext context) {
    final filters = controller.taskFilters;
    return PopupMenuButton<String>(
      tooltip: 'Priority filters',
      onSelected: (value) {
        final next = value == '__any_priority'
            ? filters.copyWith(priorities: const <String>[])
            : filters.copyWith(
                priorities: _toggleFilterValue(filters.priorities, value),
              );
        unawaited(controller.applyTaskFilters(next));
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        CheckedPopupMenuItem<String>(
          value: '__any_priority',
          checked: filters.priorities.isEmpty,
          child: const _TaskFilterMenuItem(
            icon: Icons.clear_all,
            label: 'Any priority',
          ),
        ),
        const PopupMenuDivider(),
        for (final priority in _taskPriorities)
          CheckedPopupMenuItem<String>(
            value: priority,
            checked: filters.priorities.contains(priority),
            child: _TaskFilterMenuItem(
              icon: Icons.flag_outlined,
              label: _taskLabel(priority),
            ),
          ),
      ],
      child: _TaskFilterMenuButton(
        icon: Icons.flag_outlined,
        label: _priorityFilterLabel(filters),
        selected: filters.priorities.isNotEmpty,
      ),
    );
  }
}

/// _TaskTopicFilterMenu renders topic filters as one dropdown.
class _TaskTopicFilterMenu extends StatelessWidget {
  const _TaskTopicFilterMenu({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds the topic dropdown.
  @override
  Widget build(BuildContext context) {
    final filters = controller.taskFilters;
    final topics = _topicFilterOptions(filters, controller.taskTopics);
    return PopupMenuButton<String>(
      enabled: topics.isNotEmpty,
      tooltip: 'Topic filters',
      onSelected: (value) {
        final next = value == '__any_topic'
            ? filters.copyWith(topics: const <String>[])
            : filters.copyWith(
                topics: _toggleFilterValue(filters.topics, value),
              );
        unawaited(controller.applyTaskFilters(next));
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        CheckedPopupMenuItem<String>(
          value: '__any_topic',
          checked: filters.topics.isEmpty,
          child: const _TaskFilterMenuItem(
            icon: Icons.clear_all,
            label: 'Any topic',
          ),
        ),
        const PopupMenuDivider(),
        for (final topic in topics)
          CheckedPopupMenuItem<String>(
            value: topic,
            checked: filters.topics.contains(topic),
            child: _TaskFilterMenuItem(icon: Icons.sell_outlined, label: topic),
          ),
      ],
      child: _TaskFilterMenuButton(
        icon: Icons.sell_outlined,
        label: _topicFilterLabel(filters),
        selected: filters.topics.isNotEmpty,
        enabled: topics.isNotEmpty,
      ),
    );
  }
}

/// _TaskFilterMenuButton renders the compact visible dropdown trigger.
class _TaskFilterMenuButton extends StatelessWidget {
  const _TaskFilterMenuButton({
    required this.icon,
    required this.label,
    this.selected = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;

  /// Builds the dropdown trigger surface.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final foreground = enabled ? colors.ink : colors.subtle;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.panel,
          gradient: context.agentAwesomeControlGradient,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 17, color: foreground),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 17, color: foreground),
          ],
        ),
      ),
    );
  }
}

/// _TaskFilterMenuItem renders one icon-labeled dropdown item.
class _TaskFilterMenuItem extends StatelessWidget {
  const _TaskFilterMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  /// Builds an item row used inside popup menus.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: colors.muted),
        const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _TaskQueueTile extends StatelessWidget {
  const _TaskQueueTile({
    required this.task,
    required this.selected,
    required this.focused,
    required this.changes,
    required this.onTap,
    required this.onScheduleToday,
    required this.onSnooze,
    required this.onComplete,
    required this.onDelete,
    required this.insightBadges,
  });

  final WorkspaceTask task;
  final bool selected;
  final bool focused;
  final List<ScreenChange> changes;
  final VoidCallback onTap;
  final VoidCallback onScheduleToday;
  final VoidCallback onSnooze;
  final VoidCallback? onComplete;
  final VoidCallback onDelete;
  final List<String> insightBadges;

  /// Builds one selectable context row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accentColor = _taskQueueAccentColor(context, task);
    final description = _taskQueueDescription(task);
    final suggestedAction = _taskSuggestedAction(task);
    final borderColor = selected
        ? colors.borderStrong
        : focused
        ? colors.borderStrong
        : changes.isNotEmpty
        ? colors.warningText
        : colors.border;
    final borderWidth = focused || changes.isNotEmpty ? 1.25 : 1.0;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          gradient: context.agentAwesomeCardGradient,
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(width: 4, color: accentColor),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _TaskActionTypeBadge(task: task),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  task.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                if (description.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 8),
                                  Text(
                                    description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: colors.muted),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                _TaskSuggestedActionLine(
                                  label: suggestedAction,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: <Widget>[
                                    _TaskBadge(label: _taskLabel(task.status)),
                                    if (task.overdue)
                                      const _TaskBadge(label: 'Overdue'),
                                    if (task.dueAt == null)
                                      const _TaskBadge(label: 'No due date')
                                    else
                                      _TaskBadge(
                                        label:
                                            'Due ${_formatTaskDate(task.dueAt)}',
                                      ),
                                    if (task.scheduledAt != null)
                                      _TaskBadge(
                                        label:
                                            'Scheduled ${_formatTaskDate(task.scheduledAt)}',
                                      ),
                                    if (task.estimateMinutes > 0)
                                      _TaskBadge(
                                        label: '${task.estimateMinutes} min',
                                      ),
                                    if (task.project.isEmpty)
                                      const _TaskBadge(label: 'No project'),
                                    if (task.memoryLinks.isNotEmpty)
                                      _TaskBadge(
                                        label:
                                            '${task.memoryLinks.length} memories',
                                      ),
                                    if (task.sourceLabel.isNotEmpty)
                                      _TaskBadge(label: task.sourceLabel),
                                    for (final badge in insightBadges)
                                      _TaskBadge(label: badge),
                                    for (final topic in task.topics.take(3))
                                      _TaskBadge(label: topic),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _TaskQueueScoreBlock(task: task),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: colors.border),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Row(
                        children: <Widget>[
                          _TaskQuickActionButton(
                            label: 'Schedule',
                            icon: Icons.today_outlined,
                            filled: task.scheduledAt == null,
                            onPressed: onScheduleToday,
                          ),
                          const SizedBox(width: 8),
                          _TaskQuickActionButton(
                            label: 'Mark done',
                            icon: Icons.check,
                            onPressed: onComplete,
                          ),
                          const SizedBox(width: 8),
                          _TaskQuickActionButton(
                            label: 'Snooze',
                            icon: Icons.schedule_outlined,
                            onPressed: onSnooze,
                          ),
                          const Spacer(),
                          Tooltip(
                            message: 'Delete backlog item',
                            child: TextButton.icon(
                              onPressed: onDelete,
                              icon: const Icon(Icons.delete_outline, size: 17),
                              label: const Text('Dismiss'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (changes.isNotEmpty) ...<Widget>[
                      Divider(height: 1, color: colors.border),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: _TaskTileScreenChanges(changes: changes),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// _TaskActionTypeBadge renders the queue action category for one task.
class _TaskActionTypeBadge extends StatelessWidget {
  const _TaskActionTypeBadge({required this.task});

  final WorkspaceTask task;

  /// Builds the compact action-type badge.
  @override
  Widget build(BuildContext context) {
    final label = _taskActionTypeLabel(task);
    final icon = _taskActionTypeIcon(task);
    final accent = _taskQueueAccentColor(context, task);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// _TaskSuggestedActionLine renders the recommended next action text.
class _TaskSuggestedActionLine extends StatelessWidget {
  const _TaskSuggestedActionLine({required this.label});

  final String label;

  /// Builds the suggested-action copy.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(
          context,
        ).style.copyWith(color: colors.ink, fontWeight: FontWeight.w800),
        children: <InlineSpan>[
          const TextSpan(text: 'Suggested next action: '),
          TextSpan(
            text: label,
            style: TextStyle(color: colors.green, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

/// _TaskQueueScoreBlock renders a compact attention-style queue score.
class _TaskQueueScoreBlock extends StatelessWidget {
  const _TaskQueueScoreBlock({required this.task});

  final WorkspaceTask task;

  /// Builds a score and urgency label for the queue tile.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final score = _taskQueueScore(task);
    final label = _taskQueueScoreLabel(score);
    final labelColor = _taskQueueScoreColor(context, score);
    return SizedBox(
      width: 86,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            'Queue score',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: colors.ink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            score.toString(),
            style: TextStyle(
              color: colors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// _TaskQuickActionButton renders one queue-row quick action.
class _TaskQuickActionButton extends StatelessWidget {
  const _TaskQuickActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;

  /// Builds a compact action button for queue items.
  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _TaskCaptureContent extends StatefulWidget {
  const _TaskCaptureContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  @override
  State<_TaskCaptureContent> createState() => _TaskCaptureContentState();
}

class _TaskCaptureContentState extends State<_TaskCaptureContent> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  final TextEditingController _dueAt = TextEditingController();
  final TextEditingController _scheduledAt = TextEditingController();
  String _status = 'open';
  String _priority = 'normal';
  bool _linkMemory = false;
  String _message = '';

  /// Cleans up capture form controllers.
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _topics.dispose();
    _dueAt.dispose();
    _scheduledAt.dispose();
    super.dispose();
  }

  /// Builds the quick context capture form.
  @override
  Widget build(BuildContext context) {
    final matches = widget.controller.workspace.tasks
        .where((task) {
          return _title.text.trim().isNotEmpty &&
              _matchesTask(task, '${_title.text} ${widget.query}');
        })
        .take(4);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              children: <Widget>[
                _TaskTextField(controller: _title, label: 'Title'),
                const SizedBox(height: 10),
                _TaskTextField(
                  controller: _description,
                  label: 'Description',
                  maxLines: 4,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _TaskDropdown(
                        value: _status,
                        values: _taskStatuses,
                        tooltip: 'Status',
                        onChanged: (value) => setState(() => _status = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TaskDropdown(
                        value: _priority,
                        values: _taskPriorities,
                        tooltip: 'Priority',
                        onChanged: (value) => setState(() => _priority = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _TaskDatePickerField(
                        controller: _dueAt,
                        label: 'Due date',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TaskDatePickerField(
                        controller: _scheduledAt,
                        label: 'Scheduled date',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _TaskTextField(controller: _topics, label: 'Topics'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Link selected memory'),
                  value: _linkMemory,
                  onChanged: widget.controller.selectedMemory == null
                      ? null
                      : (value) => setState(() => _linkMemory = value ?? false),
                ),
              ],
            ),
          ),
          if (_message.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _message,
              style: const TextStyle(color: AgentAwesomeColors.coral),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: widget.controller.tasksBusy ? null : _save,
            icon: const Icon(Icons.add_task),
            label: const Text('Create Backlog Item'),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _TaskPanelLabel('Nearby Backlog'),
                const SizedBox(height: 10),
                if (matches.isEmpty)
                  Text(
                    'No nearby context',
                    style: TextStyle(color: context.agentAwesomeColors.muted),
                  )
                else
                  for (final task in matches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TaskQueueTile(
                        task: task,
                        selected: widget.controller.selectedTask?.id == task.id,
                        focused: false,
                        changes: const <ScreenChange>[],
                        onTap: () =>
                            widget.controller.inspectBacklogTask(task.id),
                        onScheduleToday: () => unawaited(
                          widget.controller.updateTaskFromUi(
                            taskId: task.id,
                            scheduledAt: _todayDate(),
                          ),
                        ),
                        onSnooze: () => unawaited(
                          widget.controller.updateTaskFromUi(
                            taskId: task.id,
                            scheduledAt: _todayDate().add(
                              const Duration(days: 1),
                            ),
                          ),
                        ),
                        onComplete: null,
                        onDelete: () => unawaited(
                          widget.controller.deleteTaskFromUi(task.id),
                        ),
                        insightBadges: _insightBadgesForTask(
                          widget.controller,
                          task,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Saves the captured backlog item.
  Future<void> _save() async {
    final dueAt = _parseTaskDateInput(_dueAt.text);
    final scheduledAt = _parseTaskDateInput(_scheduledAt.text);
    if (_dueAt.text.trim().isNotEmpty && dueAt == null) {
      setState(() => _message = 'Due date could not be parsed');
      return;
    }
    if (_scheduledAt.text.trim().isNotEmpty && scheduledAt == null) {
      setState(() => _message = 'Scheduled date could not be parsed');
      return;
    }
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _message = 'Title is required');
      return;
    }
    await widget.controller.createTaskFromUi(
      title,
      description: _description.text.trim(),
      status: _status,
      priority: _priority,
      dueAt: dueAt,
      scheduledAt: scheduledAt,
      topics: _splitTaskList(_topics.text),
      linkSelectedMemory: _linkMemory,
    );
    if (!mounted) {
      return;
    }
    _title.clear();
    _description.clear();
    _topics.clear();
    _dueAt.clear();
    _scheduledAt.clear();
    setState(() {
      _message = '';
      _linkMemory = false;
    });
  }
}

class _TaskDetailEditor extends StatefulWidget {
  const _TaskDetailEditor({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  @override
  State<_TaskDetailEditor> createState() => _TaskDetailEditorState();
}

class _TaskDetailEditorState extends State<_TaskDetailEditor> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  final TextEditingController _dueAt = TextEditingController();
  final TextEditingController _scheduledAt = TextEditingController();
  String _status = 'open';
  String _priority = 'normal';
  String _message = '';

  /// Initializes editor fields from the selected backlog item.
  @override
  void initState() {
    super.initState();
    _syncFromTask();
  }

  /// Reloads editor fields when context selection changes.
  @override
  void didUpdateWidget(covariant _TaskDetailEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _syncFromTask();
    }
  }

  /// Cleans up editor controllers.
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _topics.dispose();
    _dueAt.dispose();
    _scheduledAt.dispose();
    super.dispose();
  }

  /// Builds the selected backlog editor.
  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final terminal = task.status == 'done' || task.status == 'canceled';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              children: <Widget>[
                _TaskTextField(controller: _title, label: 'Title'),
                const SizedBox(height: 10),
                _TaskTextField(
                  controller: _description,
                  label: 'Description',
                  maxLines: 5,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _TaskDropdown(
                        value: _status,
                        values: _taskStatuses,
                        tooltip: 'Status',
                        onChanged: (value) => setState(() => _status = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TaskDropdown(
                        value: _priority,
                        values: _taskPriorities,
                        tooltip: 'Priority',
                        onChanged: (value) => setState(() => _priority = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _TaskDatePickerField(
                        controller: _dueAt,
                        label: 'Due date',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TaskDatePickerField(
                        controller: _scheduledAt,
                        label: 'Scheduled date',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _TaskTextField(controller: _topics, label: 'Topics'),
              ],
            ),
          ),
          if (_message.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _message,
              style: const TextStyle(color: AgentAwesomeColors.coral),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: widget.controller.tasksBusy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
              OutlinedButton.icon(
                onPressed: widget.controller.tasksBusy || terminal
                    ? null
                    : () => unawaited(_complete()),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Complete'),
              ),
              OutlinedButton.icon(
                onPressed: widget.controller.tasksBusy || terminal
                    ? null
                    : () => unawaited(_cancel()),
                icon: const Icon(Icons.block_outlined),
                label: const Text('Cancel'),
              ),
              OutlinedButton.icon(
                onPressed: widget.controller.tasksBusy
                    ? null
                    : () => unawaited(_delete()),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _TaskMetadataBlock(controller: widget.controller, task: task),
          const SizedBox(height: 14),
          _TaskWbsBlock(controller: widget.controller, task: task),
          const SizedBox(height: 14),
          _TaskInsightDetailsBlock(controller: widget.controller, task: task),
          const SizedBox(height: 14),
          _TaskGraphDetailsBlock(controller: widget.controller, task: task),
        ],
      ),
    );
  }

  /// Copies selected backlog data into text fields.
  void _syncFromTask() {
    _title.text = widget.task.title;
    _description.text = widget.task.description;
    _topics.text = widget.task.topics.join(', ');
    _dueAt.text = _formatTaskDate(widget.task.dueAt);
    _scheduledAt.text = _formatTaskDate(widget.task.scheduledAt);
    _status = widget.task.status;
    _priority = widget.task.priority;
    _message = '';
  }

  /// Saves editor changes through graph-backed context tools.
  Future<void> _save() async {
    final dueAt = _parseTaskDateInput(_dueAt.text);
    final scheduledAt = _parseTaskDateInput(_scheduledAt.text);
    if (_dueAt.text.trim().isNotEmpty && dueAt == null) {
      setState(() => _message = 'Due date could not be parsed');
      return;
    }
    if (_scheduledAt.text.trim().isNotEmpty && scheduledAt == null) {
      setState(() => _message = 'Scheduled date could not be parsed');
      return;
    }
    if (_title.text.trim().isEmpty) {
      setState(() => _message = 'Title is required');
      return;
    }
    await widget.controller.updateTaskFromUi(
      taskId: widget.task.id,
      title: _title.text.trim(),
      description: _description.text.trim(),
      status: _status,
      priority: _priority,
      dueAt: dueAt,
      clearDueAt: _dueAt.text.trim().isEmpty && widget.task.dueAt != null,
      scheduledAt: scheduledAt,
      clearScheduledAt:
          _scheduledAt.text.trim().isEmpty && widget.task.scheduledAt != null,
      topics: _splitTaskList(_topics.text),
    );
    if (mounted) {
      setState(() => _message = '');
    }
  }

  /// Completes the selected backlog item after confirmation.
  Future<void> _complete() async {
    if (!await _confirmTaskWrite(
      context,
      'Complete backlog item "${widget.task.title}"?',
    )) {
      return;
    }
    await widget.controller.completeTaskFromUi(widget.task.id);
  }

  /// Cancels the selected backlog item after confirmation.
  Future<void> _cancel() async {
    if (!await _confirmTaskWrite(
      context,
      'Cancel backlog item "${widget.task.title}"?',
    )) {
      return;
    }
    await widget.controller.cancelTaskFromUi(widget.task.id);
  }

  /// Deletes the selected backlog item after confirmation.
  Future<void> _delete() async {
    if (!await _confirmTaskWrite(
      context,
      'Delete backlog item "${widget.task.title}"?',
    )) {
      return;
    }
    await widget.controller.deleteTaskFromUi(widget.task.id);
  }
}

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
            value: _formatTaskDateTime(task.createdAt),
          ),
          _TaskMetadataRow(
            label: 'Updated',
            value: _formatTaskDateTime(task.updatedAt),
          ),
          _TaskMetadataRow(
            label: 'Completed',
            value: _formatTaskDateTime(task.completedAt),
          ),
          _TaskMetadataRow(
            label: 'Canceled',
            value: _formatTaskDateTime(task.canceledAt),
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
          value: _formatTaskDateTime(createdAt),
        ),
      );
    }
    if (updatedAt != null) {
      rows.add(
        _TaskMetadataRow(
          label: 'Updated',
          value: _formatTaskDateTime(updatedAt),
        ),
      );
    }
    if (edge.confirmedAt != null) {
      rows.add(
        _TaskMetadataRow(
          label: 'Confirmed',
          value: _formatTaskDateTime(edge.confirmedAt),
        ),
      );
    }
    if (edge.dismissedAt != null) {
      rows.add(
        _TaskMetadataRow(
          label: 'Dismissed',
          value: _formatTaskDateTime(edge.dismissedAt),
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

class _TaskPanelLabel extends StatelessWidget {
  const _TaskPanelLabel(this.label);

  final String label;

  /// Builds an uppercase context panel label.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Text(
      label.toUpperCase(),
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.4,
      ),
    );
  }
}

class _TaskTileScreenChanges extends StatelessWidget {
  const _TaskTileScreenChanges({required this.changes});

  final List<ScreenChange> changes;

  /// Builds inline AI annotations for a queue tile.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.warningSoft,
        border: Border.all(color: colors.warningBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final change in changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    _screenChangeIcon(change),
                    size: 16,
                    color: _screenChangeColor(context, change),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          change.summary,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: colors.green,
                          ),
                        ),
                        if (change.afterValues.isNotEmpty)
                          Text(
                            _inlineScreenChangeDiff(change),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TaskBadge(label: _screenChangeStatusLabel(change)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskBadge extends StatelessWidget {
  const _TaskBadge({required this.label});

  final String label;

  /// Builds a dense context metadata badge.
  @override
  Widget build(BuildContext context) {
    return PanelBadge(label: _taskLabel(label));
  }
}

class _TaskDropdown extends StatelessWidget {
  const _TaskDropdown({
    required this.value,
    required this.values,
    required this.tooltip,
    required this.onChanged,
  });

  final String value;
  final List<String> values;
  final String tooltip;
  final ValueChanged<String> onChanged;

  /// Builds a compact dropdown for context controlled vocabulary.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final dropdownValue = values.contains(value) ? value : values.first;
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          gradient: context.agentAwesomeControlGradient,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: dropdownValue,
            isDense: true,
            isExpanded: true,
            dropdownColor: colors.surface,
            icon: Icon(Icons.expand_more, size: 18, color: colors.muted),
            style: TextStyle(color: colors.ink),
            items: <DropdownMenuItem<String>>[
              for (final item in values)
                DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    _taskLabel(item),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged(value);
              }
            },
          ),
        ),
      ),
    );
  }
}

class _TaskTextField extends StatelessWidget {
  const _TaskTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;

  /// Builds a compact context form field.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: maxLines == 1 ? 1 : 3,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.searchBorder),
        ),
      ),
    );
  }
}

/// _TaskDatePickerField renders a task date value with a popup date picker.
class _TaskDatePickerField extends StatefulWidget {
  const _TaskDatePickerField({required this.controller, required this.label});

  /// Text controller that stores the formatted date.
  final TextEditingController controller;

  /// Field label shown in the editor.
  final String label;

  /// Creates state that can refresh suffix icons after date changes.
  @override
  State<_TaskDatePickerField> createState() => _TaskDatePickerFieldState();
}

/// _TaskDatePickerFieldState owns picker and clear interactions.
class _TaskDatePickerFieldState extends State<_TaskDatePickerField> {
  /// Builds a button-like date field backed by a date picker dialog.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final colors = context.agentAwesomeColors;
        final value = widget.controller.text.trim();
        final hasValue = value.isNotEmpty;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _pickDate,
            child: InputDecorator(
              isEmpty: !hasValue,
              decoration: InputDecoration(
                labelText: widget.label,
                floatingLabelBehavior: FloatingLabelBehavior.always,
                filled: true,
                fillColor: colors.surface,
                suffixIcon: IconButton(
                  tooltip: hasValue
                      ? 'Clear ${widget.label}'
                      : 'Pick ${widget.label}',
                  onPressed: hasValue ? _clearDate : _pickDate,
                  icon: Icon(
                    hasValue ? Icons.close : Icons.calendar_today_outlined,
                    size: 18,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.searchBorder),
                ),
              ),
              child: Text(
                hasValue ? _datePickerFieldLabel(value) : 'Select date',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: hasValue ? colors.ink : colors.muted),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Opens a date picker and writes the selected date into the text controller.
  Future<void> _pickDate() async {
    final selectedDate = _parseTaskDateInput(widget.controller.text);
    final now = DateTime.now();
    final firstDate = DateTime(2000);
    final lastDate = DateTime(2100);
    final picked = await showDatePicker(
      context: context,
      initialDate: _clampDate(selectedDate ?? now, firstDate, lastDate),
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      widget.controller.text = _formatTaskDate(picked);
    });
  }

  /// Clears the selected date.
  void _clearDate() {
    setState(() {
      widget.controller.clear();
    });
  }
}

/// Returns a normalized visible label for a date picker field value.
String _datePickerFieldLabel(String value) {
  final parsed = _parseTaskDateInput(value);
  if (parsed == null) {
    return value;
  }
  return _formatTaskDate(parsed);
}

/// Returns a date constrained to a picker-supported range.
DateTime _clampDate(DateTime value, DateTime firstDate, DateTime lastDate) {
  if (value.isBefore(firstDate)) {
    return firstDate;
  }
  if (value.isAfter(lastDate)) {
    return lastDate;
  }
  return value;
}

class _TaskMetadataRow extends StatelessWidget {
  const _TaskMetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds one key/value metadata row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: colors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskSelectionEmpty extends StatelessWidget {
  const _TaskSelectionEmpty();

  /// Builds the context inspector no-selection state.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Center(
      child: Text(
        'Select a backlog item or list',
        style: TextStyle(color: colors.muted),
      ),
    );
  }
}

/// Shows the graph metadata editing dialog.
Future<void> _showTaskMetadataDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  WorkspaceTask task,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskMetadataDialog(controller: controller, task: task);
    },
  );
}

class _TaskMetadataDialog extends StatefulWidget {
  const _TaskMetadataDialog({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  @override
  State<_TaskMetadataDialog> createState() => _TaskMetadataDialogState();
}

class _TaskMetadataDialogState extends State<_TaskMetadataDialog> {
  final TextEditingController _estimate = TextEditingController();
  final TextEditingController _energy = TextEditingController();
  final TextEditingController _context = TextEditingController();
  final TextEditingController _domain = TextEditingController();
  final TextEditingController _location = TextEditingController();
  final TextEditingController _owner = TextEditingController();
  final TextEditingController _source = TextEditingController();
  final TextEditingController _effort = TextEditingController();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _urgency = TextEditingController();
  final TextEditingController _risk = TextEditingController();
  final TextEditingController _confidence = TextEditingController();
  String _message = '';

  /// Initializes metadata fields from the selected backlog item.
  @override
  void initState() {
    super.initState();
    _estimate.text = widget.task.estimateMinutes <= 0
        ? ''
        : widget.task.estimateMinutes.toString();
    _energy.text = widget.task.energyRequired;
    _context.text = widget.task.context;
    _domain.text = widget.task.domain;
    _location.text = widget.task.location;
    _owner.text = widget.task.owner;
    _source.text = widget.task.source;
    _effort.text = _scoreInputText(widget.task.effort);
    _value.text = _scoreInputText(widget.task.value);
    _urgency.text = _scoreInputText(widget.task.urgency);
    _risk.text = _scoreInputText(widget.task.risk);
    _confidence.text = _scoreInputText(widget.task.confidence);
  }

  /// Cleans up metadata field controllers.
  @override
  void dispose() {
    _estimate.dispose();
    _energy.dispose();
    _context.dispose();
    _domain.dispose();
    _location.dispose();
    _owner.dispose();
    _source.dispose();
    _effort.dispose();
    _value.dispose();
    _urgency.dispose();
    _risk.dispose();
    _confidence.dispose();
    super.dispose();
  }

  /// Builds the metadata editing dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Graph Metadata'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _TaskTextField(
                controller: _estimate,
                label: 'Estimate minutes',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _TaskTextField(controller: _energy, label: 'Energy'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _context, label: 'Context'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _domain, label: 'View'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _location, label: 'Location'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _owner, label: 'Person'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _source, label: 'Source'),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _TaskTextField(
                      controller: _effort,
                      label: 'Effort 0-1',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TaskTextField(
                      controller: _value,
                      label: 'Value 0-1',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _TaskTextField(
                      controller: _urgency,
                      label: 'Urgency 0-1',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TaskTextField(
                      controller: _risk,
                      label: 'Risk 0-1',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _confidence,
                label: 'Confidence 0-1',
                keyboardType: TextInputType.number,
              ),
              if (_message.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _message,
                  style: const TextStyle(color: AgentAwesomeColors.coral),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  /// Saves the edited metadata through graph-backed task tools.
  Future<void> _save() async {
    final estimateText = _estimate.text.trim();
    final estimate = estimateText.isEmpty ? 0 : int.tryParse(estimateText);
    if (estimate == null || estimate < 0) {
      setState(() => _message = 'Estimate must be zero or greater');
      return;
    }
    final effort = _parseDialogScore(_effort.text);
    final value = _parseDialogScore(_value.text);
    final urgency = _parseDialogScore(_urgency.text);
    final risk = _parseDialogScore(_risk.text);
    final confidence = _parseDialogScore(_confidence.text);
    if (<double?>[effort, value, urgency, risk, confidence].contains(null)) {
      setState(() => _message = 'Scores must be between 0 and 1');
      return;
    }
    await widget.controller.updateTaskFromUi(
      taskId: widget.task.id,
      estimateMinutes: estimate,
      energyRequired: _energy.text.trim(),
      effort: effort,
      value: value,
      urgency: urgency,
      risk: risk,
      context: _context.text.trim(),
      domain: _domain.text.trim(),
      location: _location.text.trim(),
      owner: _owner.text.trim(),
      source: _source.text.trim(),
      confidence: confidence,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// Shows the WBS editing dialog.
Future<void> _showTaskWbsDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  WorkspaceTask task,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskWbsDialog(controller: controller, task: task);
    },
  );
}

class _TaskWbsDialog extends StatefulWidget {
  const _TaskWbsDialog({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  @override
  State<_TaskWbsDialog> createState() => _TaskWbsDialogState();
}

class _TaskWbsDialogState extends State<_TaskWbsDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _deliverable = TextEditingController();
  final TextEditingController _startCriteria = TextEditingController();
  final TextEditingController _acceptanceCriteria = TextEditingController();
  final TextEditingController _requirementRefs = TextEditingController();
  final TextEditingController _rubricRefs = TextEditingController();
  final TextEditingController _resources = TextEditingController();
  final TextEditingController _estimatedCost = TextEditingController();
  final TextEditingController _costCurrency = TextEditingController();
  String _message = '';

  /// Initializes WBS fields from the selected task.
  @override
  void initState() {
    super.initState();
    final workBreakdown = widget.task.workBreakdown;
    _code.text = workBreakdown.code;
    _deliverable.text = workBreakdown.deliverable;
    _startCriteria.text = workBreakdown.startCriteria.join('\n');
    _acceptanceCriteria.text = workBreakdown.acceptanceCriteria.join('\n');
    _requirementRefs.text = workBreakdown.requirementRefs.join('\n');
    _rubricRefs.text = workBreakdown.rubricRefs.join('\n');
    _resources.text = workBreakdown.resources
        .map(taskResourceRequirementLine)
        .join('\n');
    _estimatedCost.text = workBreakdown.estimatedCostCents <= 0
        ? ''
        : workBreakdown.estimatedCostCents.toString();
    _costCurrency.text = workBreakdown.costCurrency;
  }

  /// Cleans up WBS field controllers.
  @override
  void dispose() {
    _code.dispose();
    _deliverable.dispose();
    _startCriteria.dispose();
    _acceptanceCriteria.dispose();
    _requirementRefs.dispose();
    _rubricRefs.dispose();
    _resources.dispose();
    _estimatedCost.dispose();
    _costCurrency.dispose();
    super.dispose();
  }

  /// Builds the WBS editing dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit WBS'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _TaskTextField(controller: _code, label: 'Code'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TaskTextField(
                      controller: _costCurrency,
                      label: 'Currency',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _deliverable,
                label: 'Deliverable',
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _estimatedCost,
                label: 'Spend cents',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _startCriteria,
                label: 'Start criteria',
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _acceptanceCriteria,
                label: 'Done criteria',
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _requirementRefs,
                label: 'Requirement refs',
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _rubricRefs,
                label: 'Rubric refs',
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _resources,
                label: 'Resources',
                maxLines: 5,
              ),
              if (_message.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _message,
                  style: const TextStyle(color: AgentAwesomeColors.coral),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  /// Saves the edited WBS metadata through graph-backed task tools.
  Future<void> _save() async {
    final costText = _estimatedCost.text.trim();
    final cost = costText.isEmpty ? 0 : int.tryParse(costText);
    if (cost == null || cost < 0) {
      setState(() => _message = 'Spend must be zero or greater');
      return;
    }
    final resources = parseTaskResourceRequirementLines(_resources.text);
    if (resources == null) {
      setState(() => _message = 'Resource quantities and spend must be valid');
      return;
    }
    await widget.controller.updateTaskFromUi(
      taskId: widget.task.id,
      workBreakdown: TaskWorkBreakdown(
        code: _code.text.trim(),
        deliverable: _deliverable.text.trim(),
        startCriteria: splitWbsLines(_startCriteria.text),
        acceptanceCriteria: splitWbsLines(_acceptanceCriteria.text),
        requirementRefs: splitWbsLines(_requirementRefs.text),
        rubricRefs: splitWbsLines(_rubricRefs.text),
        resources: resources,
        estimatedCostCents: cost,
        costCurrency: _costCurrency.text.trim(),
      ),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// Shows the backlog relation creation dialog.
Future<void> _showTaskRelationDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  WorkspaceTask task,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskRelationDialog(controller: controller, task: task);
    },
  );
}

class _TaskRelationDialog extends StatefulWidget {
  const _TaskRelationDialog({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  @override
  State<_TaskRelationDialog> createState() => _TaskRelationDialogState();
}

class _TaskRelationDialogState extends State<_TaskRelationDialog> {
  final TextEditingController _explanation = TextEditingController();
  String _targetTaskId = '';
  String _relationType = 'related_to';

  /// Initializes the first available target backlog item.
  @override
  void initState() {
    super.initState();
    final targets = _relationTargets;
    if (targets.isNotEmpty) {
      _targetTaskId = targets.first.id;
    }
  }

  /// Cleans up dialog controllers.
  @override
  void dispose() {
    _explanation.dispose();
    super.dispose();
  }

  List<WorkspaceTask> get _relationTargets {
    return widget.controller.workspace.tasks.where((task) {
      return task.id != widget.task.id;
    }).toList();
  }

  /// Builds the backlog relation creation dialog.
  @override
  Widget build(BuildContext context) {
    final targets = _relationTargets;
    return AlertDialog(
      title: const Text('Add Relation'),
      content: SizedBox(
        width: 460,
        child: targets.isEmpty
            ? const Text(
                'Create another backlog item before adding a relation.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: _targetTaskId.isEmpty ? null : _targetTaskId,
                    decoration: _taskDialogDecoration(
                      context,
                      'Related backlog item',
                    ),
                    isExpanded: true,
                    items: <DropdownMenuItem<String>>[
                      for (final target in targets)
                        DropdownMenuItem<String>(
                          value: target.id,
                          child: Text(
                            target.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _targetTaskId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _TaskDropdown(
                    value: _relationType,
                    values: _taskRelationTypes,
                    tooltip: 'Relation type',
                    onChanged: (value) => setState(() => _relationType = value),
                  ),
                  const SizedBox(height: 10),
                  _TaskTextField(
                    controller: _explanation,
                    label: 'Explanation',
                    maxLines: 3,
                  ),
                ],
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: targets.isEmpty ? null : _save,
          child: const Text('Add'),
        ),
      ],
    );
  }

  /// Saves the explicit relation through graph-backed context tools.
  Future<void> _save() async {
    if (_targetTaskId.isEmpty) {
      return;
    }
    await widget.controller.upsertTaskRelationFromUi(
      fromTaskId: widget.task.id,
      toTaskId: _targetTaskId,
      relationType: _relationType,
      explanation: _explanation.text.trim(),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// Shows the commitment create or edit dialog.
Future<void> _showTaskCommitmentDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  WorkspaceTask task, {
  TaskCommitment? commitment,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskCommitmentDialog(
        controller: controller,
        task: task,
        commitment: commitment,
      );
    },
  );
}

class _TaskCommitmentDialog extends StatefulWidget {
  const _TaskCommitmentDialog({
    required this.controller,
    required this.task,
    this.commitment,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;
  final TaskCommitment? commitment;

  @override
  State<_TaskCommitmentDialog> createState() => _TaskCommitmentDialogState();
}

class _TaskCommitmentDialogState extends State<_TaskCommitmentDialog> {
  final TextEditingController _people = TextEditingController();
  final TextEditingController _domain = TextEditingController();
  final TextEditingController _project = TextEditingController();
  final TextEditingController _timeWindow = TextEditingController();
  final TextEditingController _responsibility = TextEditingController();
  final TextEditingController _promiseSource = TextEditingController();
  final TextEditingController _hardness = TextEditingController();
  final TextEditingController _consequence = TextEditingController();

  /// Initializes commitment fields from the existing commitment when present.
  @override
  void initState() {
    super.initState();
    final commitment = widget.commitment;
    if (commitment == null) {
      _domain.text = widget.task.domain;
      _project.text = widget.task.context;
      _people.text = widget.task.owner;
      return;
    }
    _people.text = commitment.people.join(', ');
    _domain.text = commitment.domain;
    _project.text = commitment.project;
    _timeWindow.text = commitment.timeWindow;
    _responsibility.text = commitment.responsibility;
    _promiseSource.text = commitment.promiseSource;
    _hardness.text = commitment.hardness;
    _consequence.text = commitment.consequence;
  }

  /// Cleans up commitment field controllers.
  @override
  void dispose() {
    _people.dispose();
    _domain.dispose();
    _project.dispose();
    _timeWindow.dispose();
    _responsibility.dispose();
    _promiseSource.dispose();
    _hardness.dispose();
    _consequence.dispose();
    super.dispose();
  }

  /// Builds the commitment create or edit dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.commitment == null ? 'Add Commitment' : 'Edit Commitment',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _TaskTextField(controller: _people, label: 'People'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _domain, label: 'View'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _project, label: 'Project'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _timeWindow, label: 'Time window'),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _responsibility,
                label: 'Responsibility',
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _promiseSource,
                label: 'Promise source',
              ),
              const SizedBox(height: 10),
              _TaskTextField(controller: _hardness, label: 'Hardness'),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _consequence,
                label: 'Consequence',
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  /// Saves the commitment through graph-backed task tools.
  Future<void> _save() async {
    await widget.controller.upsertTaskCommitmentFromUi(
      commitmentId: widget.commitment?.id ?? '',
      taskId: widget.task.id,
      people: _splitTaskList(_people.text),
      domain: _domain.text.trim(),
      project: _project.text.trim(),
      timeWindow: _timeWindow.text.trim(),
      responsibility: _responsibility.text.trim(),
      promiseSource: _promiseSource.text.trim(),
      hardness: _hardness.text.trim(),
      consequence: _consequence.text.trim(),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// Shows the context creation dialog.
Future<void> _showTaskCreateDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskCreateDialog(controller: controller);
    },
  );
}

class _TaskCreateDialog extends StatefulWidget {
  const _TaskCreateDialog({required this.controller});

  final AgentAwesomeAppController controller;

  @override
  State<_TaskCreateDialog> createState() => _TaskCreateDialogState();
}

class _TaskCreateDialogState extends State<_TaskCreateDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  String _priority = 'normal';
  bool _linkMemory = false;

  /// Cleans up dialog controllers.
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _topics.dispose();
    super.dispose();
  }

  /// Builds the context creation dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Backlog Item'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _TaskTextField(controller: _title, label: 'Title'),
            const SizedBox(height: 10),
            _TaskTextField(
              controller: _description,
              label: 'Description',
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            _TaskDropdown(
              value: _priority,
              values: _taskPriorities,
              tooltip: 'Priority',
              onChanged: (value) => setState(() => _priority = value),
            ),
            const SizedBox(height: 10),
            _TaskTextField(controller: _topics, label: 'Topics'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Link selected memory'),
              value: _linkMemory,
              onChanged: widget.controller.selectedMemory == null
                  ? null
                  : (value) => setState(() => _linkMemory = value ?? false),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _create, child: const Text('Create')),
      ],
    );
  }

  /// Creates the dialog backlog item.
  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      return;
    }
    await widget.controller.createTaskFromUi(
      title,
      description: _description.text.trim(),
      priority: _priority,
      topics: _splitTaskList(_topics.text),
      linkSelectedMemory: _linkMemory,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// Confirms a context write operation.
Future<bool> _confirmTaskWrite(BuildContext context, String message) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Confirm Change'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );
  return approved ?? false;
}

/// Returns whether a backlog item matches a panel query.
bool _matchesTask(WorkspaceTask task, String query) {
  return _matchesText(
    '${task.title} ${task.description} ${task.status} ${task.priority} '
    '${task.sourceLabel} ${task.topics.join(' ')}',
    query,
  );
}

/// Returns graph task ids for the active Queue insight preset.
Set<String> _queuePresetTaskIds(AgentAwesomeAppController controller) {
  final presetId = controller.taskInsightPresetId;
  if (presetId == TaskInsightIds.all) {
    return const <String>{};
  }
  return controller.taskInsightIndex
      .tasksForInsight(presetId)
      .map((candidate) => candidate.taskId)
      .toSet();
}

/// Returns compact insight badges for one queue backlog item.
List<String> _insightBadgesForTask(
  AgentAwesomeAppController controller,
  WorkspaceTask task,
) {
  final taskId = task.id;
  final badges = <String>[];
  if (controller.taskInsightIndex.candidateForTask(
        taskId,
        TaskInsightIds.agentHandoff,
      ) !=
      null) {
    final score = controller.taskInsightIndex.scoresFor(taskId);
    badges.add(
      (score?.agentSafety ?? 0) >=
              controller.taskInsightIndex.policy.safeAgentThreshold
          ? 'Agent-ready'
          : 'Needs review',
    );
  }
  final downstream = controller.taskInsightIndex.downstreamTasksFor(taskId);
  if (downstream.isNotEmpty) {
    badges.add('Blocks ${downstream.length}');
  }
  final gaps = controller.taskInsightIndex.metadataGapsFor(taskId);
  if (gaps.isNotEmpty) {
    badges.add('Missing ${gaps.first.field.replaceAll('_', ' ')}');
  }
  return badges.take(3).toList();
}

/// Returns the local date used by queue quick actions.
DateTime _todayDate() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Returns the task card accent color from the displayed score band.
Color _taskQueueAccentColor(BuildContext context, WorkspaceTask task) {
  return _taskQueueScoreColor(context, _taskQueueScore(task));
}

/// Returns a compact task description for queue cards.
String _taskQueueDescription(WorkspaceTask task) {
  if (task.description.trim().isNotEmpty) {
    return task.description.trim();
  }
  if (task.detail.trim().isNotEmpty) {
    return task.detail.trim();
  }
  if (task.dueAt == null && task.scheduledAt == null) {
    return 'No date is attached yet.';
  }
  return '';
}

/// Returns the suggested next action for a queue card.
String _taskSuggestedAction(WorkspaceTask task) {
  if (task.done) {
    return 'Already complete';
  }
  if (task.status == 'blocked') {
    return 'Clarify the blocker';
  }
  if (task.status == 'waiting') {
    return 'Follow up or snooze';
  }
  if (task.scheduledAt == null) {
    return 'Schedule for today';
  }
  return 'Mark done when finished';
}

/// Returns the action category label for a queue card.
String _taskActionTypeLabel(WorkspaceTask task) {
  if (task.status == 'blocked' || task.description.trim().isEmpty) {
    return 'Clarify';
  }
  if (task.scheduledAt == null) {
    return 'Schedule';
  }
  return 'Do';
}

/// Returns the action category icon for a queue card.
IconData _taskActionTypeIcon(WorkspaceTask task) {
  if (task.status == 'blocked' || task.description.trim().isEmpty) {
    return Icons.format_list_bulleted_add;
  }
  if (task.scheduledAt == null) {
    return Icons.calendar_today_outlined;
  }
  return Icons.task_alt_outlined;
}

/// Returns a simple queue priority score for attention-style display.
int _taskQueueScore(WorkspaceTask task) {
  var score = 48;
  if (task.overdue) {
    score += 22;
  }
  if (task.dueAt == null && task.scheduledAt == null) {
    score += 10;
  }
  if (task.priority == 'urgent') {
    score += 22;
  } else if (task.priority == 'high') {
    score += 15;
  } else if (task.priority == 'low') {
    score -= 8;
  }
  if (task.status == 'blocked') {
    score += 12;
  }
  if (task.description.trim().isEmpty) {
    score += 8;
  }
  return score.clamp(0, 99);
}

/// Returns the queue score band label.
String _taskQueueScoreLabel(int score) {
  if (score >= 75) {
    return 'High';
  }
  if (score >= 55) {
    return 'Medium';
  }
  return 'Low';
}

/// Returns the queue score band color.
Color _taskQueueScoreColor(BuildContext context, int score) {
  final colors = context.agentAwesomeColors;
  if (score >= 75) {
    return colors.coral;
  }
  if (score >= 55) {
    return context.agentAwesomeWarningAccent;
  }
  return context.agentAwesomeLowAccent;
}

/// Returns memory links filtered by the panel query.
List<TaskMemoryLink> _filteredLinks(List<TaskMemoryLink> links, String query) {
  return links.where((link) {
    return _matchesText(
      '${link.relationship} ${link.note} ${link.memoryId} '
      '${link.memoryEvidenceId}',
      query,
    );
  }).toList();
}

/// Returns whether text contains every query character in order.
bool _matchesText(String value, String query) {
  final normalizedValue = value.toLowerCase();
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }
  var cursor = 0;
  for (final codeUnit in normalizedQuery.codeUnits) {
    cursor = normalizedValue.indexOf(String.fromCharCode(codeUnit), cursor);
    if (cursor == -1) {
      return false;
    }
    cursor++;
  }
  return true;
}

/// Returns the selected semantic Queue preset, falling back to All.
TaskInsightPreset _selectedTaskInsightPreset(
  AgentAwesomeAppController controller,
) {
  for (final preset in TaskInsightPresetRegistry.queuePresets) {
    if (preset.id == controller.taskInsightPresetId) {
      return preset;
    }
  }
  return TaskInsightPresetRegistry.queuePresets.first;
}

/// Returns a preset label with candidate count when the preset is semantic.
String _presetLabel(
  AgentAwesomeAppController controller,
  TaskInsightPreset preset,
) {
  if (preset.id == TaskInsightIds.all) {
    return preset.label;
  }
  final count = controller.taskInsightIndex.tasksForInsight(preset.id).length;
  return '${preset.label} $count';
}

/// Returns the visible insight dropdown label.
String _presetButtonLabel(
  AgentAwesomeAppController controller,
  TaskInsightPreset preset,
) {
  if (preset.id == TaskInsightIds.all) {
    return preset.label;
  }
  return _presetLabel(controller, preset);
}

/// Reports whether the filter state matches the bundled Active view.
bool _isActiveTaskView(TaskFilterState filters) {
  return _sameFilterValues(filters.statuses, _activeTaskStatuses);
}

/// Returns the visible icon for the bundled task view control.
IconData _taskViewIcon(TaskFilterState filters) {
  if (_isActiveTaskView(filters)) {
    return Icons.playlist_play;
  }
  if (filters.statuses.isEmpty) {
    return Icons.all_inbox_outlined;
  }
  return Icons.tune;
}

/// Returns the visible label for the bundled task view control.
String _taskViewLabel(TaskFilterState filters) {
  if (_isActiveTaskView(filters)) {
    return 'Active tasks';
  }
  if (filters.statuses.isEmpty) {
    return 'All tasks';
  }
  return 'Custom tasks';
}

/// Returns the compact status filter summary.
String _statusFilterLabel(TaskFilterState filters) {
  if (filters.statuses.isEmpty || _isActiveTaskView(filters)) {
    return filters.overdueOnly ? 'Overdue' : 'Status';
  }
  final statusLabel = filters.statuses.length == 1
      ? _taskLabel(filters.statuses.first)
      : 'Status ${filters.statuses.length}';
  return filters.overdueOnly ? '$statusLabel + overdue' : statusLabel;
}

/// Returns the compact priority filter summary.
String _priorityFilterLabel(TaskFilterState filters) {
  if (filters.priorities.isEmpty) {
    return 'Priority';
  }
  if (filters.priorities.length == 1) {
    return _taskLabel(filters.priorities.first);
  }
  return 'Priority ${filters.priorities.length}';
}

/// Returns the compact topic filter summary.
String _topicFilterLabel(TaskFilterState filters) {
  if (filters.topics.isEmpty) {
    return 'Topics';
  }
  if (filters.topics.length == 1) {
    return filters.topics.first;
  }
  return 'Topics ${filters.topics.length}';
}

/// Returns topic filter choices with selected topics kept visible.
List<String> _topicFilterOptions(
  TaskFilterState filters,
  Iterable<String> availableTopics,
) {
  final seen = <String>{};
  final topics = <String>[];
  for (final topic in <String>[
    ...filters.topics,
    ...availableTopics.take(16),
  ]) {
    final trimmed = topic.trim();
    if (trimmed.isNotEmpty && seen.add(trimmed)) {
      topics.add(trimmed);
    }
  }
  return topics;
}

/// Reports whether two filter value lists contain the same values.
bool _sameFilterValues(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  final rightValues = right.toSet();
  return left.every(rightValues.contains);
}

/// Toggles one filter value.
List<String> _toggleFilterValue(List<String> values, String value) {
  if (values.contains(value)) {
    return values.where((item) => item != value).toList();
  }
  return <String>[...values, value];
}

/// Splits comma-delimited context labels.
List<String> _splitTaskList(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

/// Formats a normalized score for inspector display.
String _formatTaskScore(double value) {
  if (value <= 0) {
    return '';
  }
  return '${(value * 100).round()}%';
}

/// Summarizes proposed task metadata fields for the inspector.
String _metadataSuggestionSummary(TaskMetadataSuggestion suggestion) {
  final parts = <String>[
    if (suggestion.estimateMinutes > 0) '${suggestion.estimateMinutes} min',
    if (suggestion.energyRequired.isNotEmpty) suggestion.energyRequired,
    if (suggestion.context.isNotEmpty) suggestion.context,
    if (suggestion.domain.isNotEmpty) suggestion.domain,
    if (suggestion.location.isNotEmpty) suggestion.location,
    if (suggestion.effort > 0) 'effort ${_formatTaskScore(suggestion.effort)}',
    if (suggestion.value > 0) 'value ${_formatTaskScore(suggestion.value)}',
    if (suggestion.urgency > 0)
      'urgency ${_formatTaskScore(suggestion.urgency)}',
    if (suggestion.risk > 0) 'risk ${_formatTaskScore(suggestion.risk)}',
  ];
  if (parts.isEmpty) {
    return suggestion.explanation;
  }
  return parts.join(' • ');
}

/// Summarizes proposed commitment fields for the inspector.
String _commitmentSuggestionSummary(TaskCommitmentSuggestion suggestion) {
  final parts = <String>[
    if (suggestion.domain.isNotEmpty) suggestion.domain,
    if (suggestion.project.isNotEmpty) suggestion.project,
    if (suggestion.timeWindow.isNotEmpty) suggestion.timeWindow,
    if (suggestion.responsibility.isNotEmpty) suggestion.responsibility,
    if (suggestion.promiseSource.isNotEmpty) suggestion.promiseSource,
    if (suggestion.consequence.isNotEmpty) suggestion.consequence,
  ];
  if (parts.isEmpty) {
    return suggestion.explanation;
  }
  return parts.join(' • ');
}

/// Formats a normalized score for dialog input.
String _scoreInputText(double value) {
  if (value <= 0) {
    return '';
  }
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Parses a dialog score where blank means no explicit signal.
double? _parseDialogScore(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return 0;
  }
  final score = double.tryParse(text);
  if (score == null || score < 0 || score > 1) {
    return null;
  }
  return score;
}

/// Builds dialog field decoration consistent with context text fields.
InputDecoration _taskDialogDecoration(BuildContext context, String label) {
  final colors = context.agentAwesomeColors;
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: colors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.searchBorder),
    ),
  );
}

/// Resolves a task title for graph rows.
String _taskTitleFor(AgentAwesomeAppController controller, String taskId) {
  final indexedTitle = controller.taskInsightIndex.titleForTaskId(taskId);
  if (indexedTitle != taskId) {
    return indexedTitle;
  }
  for (final task in controller.workspace.tasks) {
    if (task.id == taskId) {
      return task.title;
    }
  }
  return taskId.isEmpty ? 'Unknown backlog item' : taskId;
}

/// Reports whether an edge endpoint is a constellation anchor, not a task.
bool _isConstellationAnchorEndpoint(String id) {
  return id.startsWith('anchor:');
}

/// Resolves task and anchor endpoint labels for graph rows.
String _constellationEndpointLabel(
  AgentAwesomeAppController controller,
  String endpointId,
) {
  if (_isConstellationAnchorEndpoint(endpointId)) {
    return endpointId.substring('anchor:'.length);
  }
  return _taskTitleFor(controller, endpointId);
}

/// Returns an icon for one AI screen change.
IconData _screenChangeIcon(ScreenChange change) {
  if (change.status == ScreenChangeStatus.rejected) {
    return Icons.block_outlined;
  }
  if (change.status == ScreenChangeStatus.failed) {
    return Icons.error_outline;
  }
  if (change.status == ScreenChangeStatus.applied) {
    return Icons.check_circle_outline;
  }
  return switch (change.operation) {
    ScreenChangeOperation.createTask => Icons.add_task_outlined,
    ScreenChangeOperation.updateTask => Icons.edit_outlined,
    ScreenChangeOperation.completeTask => Icons.task_alt_outlined,
    ScreenChangeOperation.cancelTask => Icons.cancel_outlined,
    ScreenChangeOperation.deleteTask => Icons.delete_outline,
    ScreenChangeOperation.upsertTaskRelation => Icons.account_tree_outlined,
    ScreenChangeOperation.deleteTaskRelation => Icons.link_off_outlined,
    ScreenChangeOperation.linkTaskMemory => Icons.link_outlined,
  };
}

/// Returns a color for one AI screen change status.
Color _screenChangeColor(BuildContext context, ScreenChange change) {
  final colors = context.agentAwesomeColors;
  return switch (change.status) {
    ScreenChangeStatus.applied => context.agentAwesomeLowAccent,
    ScreenChangeStatus.rejected || ScreenChangeStatus.failed => colors.coral,
    ScreenChangeStatus.undone => colors.muted,
    ScreenChangeStatus.proposed =>
      change.safety == ScreenChangeSafety.autoApply
          ? context.agentAwesomeLowAccent
          : context.agentAwesomeWarningAccent,
  };
}

/// Formats one AI screen change operation label.
String _screenChangeOperationLabel(ScreenChangeOperation operation) {
  return screenChangeOperationToolName(operation).replaceAll('_', ' ');
}

/// Formats one AI screen change status label.
String _screenChangeStatusLabel(ScreenChange change) {
  return switch (change.status) {
    ScreenChangeStatus.proposed =>
      change.safety == ScreenChangeSafety.autoApply
          ? 'Auto safe'
          : 'Needs review',
    ScreenChangeStatus.applied => 'Applied',
    ScreenChangeStatus.rejected => 'Rejected',
    ScreenChangeStatus.failed => 'Failed',
    ScreenChangeStatus.undone => 'Undone',
  };
}

/// Formats a screen-change diff value.
String _screenValueLabel(dynamic value) {
  if (value == null || value.toString().trim().isEmpty) {
    return '-';
  }
  if (value is List) {
    return value.map((item) => item.toString()).join(', ');
  }
  return value.toString();
}

/// Formats a compact inline diff for a task tile.
String _inlineScreenChangeDiff(ScreenChange change) {
  final keys = <String>{
    ...change.beforeValues.keys,
    ...change.afterValues.keys,
  }.take(3);
  return keys
      .map((key) {
        final before = _screenValueLabel(change.beforeValues[key]);
        final after = _screenValueLabel(change.afterValues[key]);
        return '${_taskLabel(key)}: $before -> $after';
      })
      .join(' • ');
}

/// Parses a human-entered task date.
DateTime? _parseTaskDateInput(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  final direct = DateTime.tryParse(text);
  if (direct != null) {
    return direct;
  }
  final spaced = DateTime.tryParse(text.replaceFirst(' ', 'T'));
  if (spaced != null) {
    return spaced;
  }
  final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (dateOnly == null) {
    return null;
  }
  return DateTime(
    int.parse(dateOnly.group(1)!),
    int.parse(dateOnly.group(2)!),
    int.parse(dateOnly.group(3)!),
  );
}

/// Formats a nullable task date.
String _formatTaskDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// Formats a nullable task timestamp.
String _formatTaskDateTime(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// Converts controlled task vocabulary to readable labels.
String _taskLabel(String value) {
  if (value.isEmpty) {
    return '';
  }
  return value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}
