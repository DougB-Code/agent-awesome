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

/// BacklogQueuePanel renders backlog navigation, graph projections, and capture.
class BacklogQueuePanel extends StatelessWidget {
  /// Creates a backlog queue panel.
  const BacklogQueuePanel({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  /// Shared app controller.
  final AuroraAppController controller;

  /// Reports the active backlog queue area to the app shell.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the left backlog command surface.
  @override
  Widget build(BuildContext context) {
    return SwitcherPanel(
      onAreaChanged: onAreaChanged,
      areas: <SwitcherPanelArea>[
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
      ],
    );
  }
}

/// BacklogInspectorPanel renders the selected backlog item or list editor.
class BacklogInspectorPanel extends StatelessWidget {
  /// Creates a backlog inspector panel.
  const BacklogInspectorPanel({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  /// Shared app controller.
  final AuroraAppController controller;

  /// Reports the active inspector area to the app shell.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the right backlog inspector surface.
  @override
  Widget build(BuildContext context) {
    return SwitcherPanel(
      onAreaChanged: onAreaChanged,
      titleControl: _BacklogReviewTitleControl(controller: controller),
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          title: 'Backlog Inspector',
          icon: Icons.edit_note_outlined,
          builder: _buildInspectorArea,
        ),
        SwitcherPanelArea(
          title: 'Memory Links',
          icon: Icons.link_outlined,
          builder: _buildMemoryLinksArea,
        ),
      ],
    );
  }

  /// Builds the right-side inspector area for the selected backlog item or edge.
  Widget _buildInspectorArea(String query) {
    final edge = controller.selectedConstellationEdge;
    final task = controller.selectedTask;
    if (edge != null) {
      return _TaskConstellationEdgeInspector(
        controller: controller,
        edge: edge,
      );
    }
    if (task != null) {
      return _TaskDetailEditor(controller: controller, task: task);
    }
    return const _TaskSelectionEmpty();
  }

  /// Builds the right-side memory-link area for the selected backlog item.
  Widget _buildMemoryLinksArea(String query) {
    final task = controller.selectedTask;
    if (task != null) {
      return _TaskMemoryLinkPanel(
        controller: controller,
        task: task,
        query: query,
      );
    }
    return const _TaskSelectionEmpty();
  }
}

class _BacklogReviewTitleControl extends StatelessWidget {
  const _BacklogReviewTitleControl({required this.controller});

  final AuroraAppController controller;

  /// Builds an inspector header action for returning to AI review.
  @override
  Widget build(BuildContext context) {
    final run = controller.activeScreenCommandRun;
    if (run == null || run.changes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: 'Review AI changes',
      child: IconButton(
        onPressed: controller.openBacklogReviewPanel,
        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
      ),
    );
  }
}

/// BacklogReviewPanel renders AI-proposed screen changes for review.
class BacklogReviewPanel extends StatelessWidget {
  /// Creates the Backlog AI change review panel.
  const BacklogReviewPanel({super.key, required this.controller});

  /// Shared app controller.
  final AuroraAppController controller;

  /// Builds the right-side AI change review surface.
  @override
  Widget build(BuildContext context) {
    final run = controller.activeScreenCommandRun;
    return SwitcherPanel(
      showAreaQuickSelect: false,
      titleControl: Tooltip(
        message: 'Show inspector',
        child: IconButton(
          onPressed: controller.openBacklogInspectorPanel,
          icon: const Icon(Icons.close, size: 18),
        ),
      ),
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          title: 'Review Changes',
          icon: Icons.auto_awesome_outlined,
          builder: (query) {
            if (run == null) {
              return const PanelEmptyBlock(label: 'No AI changes to review');
            }
            final changes = run.changes.where((change) {
              return _matchesTaskChange(change, query);
            }).toList();
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _ScreenRunSummaryBlock(controller: controller, run: run),
                  const SizedBox(height: 12),
                  if (changes.isEmpty)
                    const PanelEmptyBlock(label: 'No changes match this view')
                  else
                    for (final change in changes)
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
          },
        ),
      ],
    );
  }
}

class _ScreenRunSummaryBlock extends StatelessWidget {
  const _ScreenRunSummaryBlock({required this.controller, required this.run});

  final AuroraAppController controller;
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
            style: const TextStyle(color: AuroraColors.muted),
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

  final AuroraAppController controller;
  final ScreenChange change;

  /// Builds one reviewable AI change card.
  @override
  Widget build(BuildContext context) {
    final focused = controller.focusedScreenChangeId == change.id;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => controller.focusBacklogScreenChange(change.id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: focused ? AuroraColors.greenSoft : const Color(0xfffffcf8),
          border: Border.all(
            color: focused ? AuroraColors.green : AuroraColors.border,
          ),
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
                  color: _screenChangeColor(change),
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
              Text(
                change.reason,
                style: const TextStyle(color: AuroraColors.muted),
              ),
            ],
            if (change.error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                change.error,
                style: const TextStyle(
                  color: AuroraColors.coral,
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
      return Text(
        _screenChangeOperationLabel(change.operation),
        style: const TextStyle(color: AuroraColors.muted),
      );
    }
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
                    style: const TextStyle(
                      color: AuroraColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _screenValueLabel(change.beforeValues[key]),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AuroraColors.muted),
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
                    style: const TextStyle(
                      color: AuroraColors.green,
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

  final AuroraAppController controller;
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
          _TaskInsightPresetRow(controller: controller),
          const SizedBox(height: 10),
          _TaskFilterBar(controller: controller),
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

/// _TaskInsightPresetRow renders one-click semantic task query presets.
class _TaskInsightPresetRow extends StatelessWidget {
  const _TaskInsightPresetRow({required this.controller});

  final AuroraAppController controller;

  /// Builds queue insight preset chips.
  @override
  Widget build(BuildContext context) {
    return PanelSectionBlock(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final preset in TaskInsightPresetRegistry.queuePresets)
            ChoiceChip(
              avatar: Icon(
                TaskInsightPresetRegistry.iconFor(preset.iconName),
                size: 17,
              ),
              label: Text(_presetLabel(controller, preset)),
              selected: controller.taskInsightPresetId == preset.id,
              onSelected: (_) {
                unawaited(controller.applyTaskInsightPreset(preset.id));
              },
            ),
        ],
      ),
    );
  }

  /// Returns label with candidate count when the preset is semantic.
  String _presetLabel(
    AuroraAppController controller,
    TaskInsightPreset preset,
  ) {
    if (preset.id == TaskInsightIds.all) {
      return preset.label;
    }
    final count = controller.taskInsightIndex.tasksForInsight(preset.id).length;
    return '${preset.label} $count';
  }
}

class _TaskFilterBar extends StatelessWidget {
  const _TaskFilterBar({required this.controller});

  final AuroraAppController controller;

  /// Builds queue filter chips and context action controls.
  @override
  Widget build(BuildContext context) {
    final filters = controller.taskFilters;
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    ActionChip(
                      avatar: const Icon(Icons.playlist_play, size: 18),
                      label: const Text('Active'),
                      onPressed: () {
                        unawaited(
                          controller.applyTaskFilters(
                            filters.copyWith(
                              statuses: _activeTaskStatuses,
                              includeDone: true,
                            ),
                          ),
                        );
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.all_inbox, size: 18),
                      label: const Text('All'),
                      onPressed: () {
                        unawaited(
                          controller.applyTaskFilters(
                            filters.copyWith(
                              statuses: const <String>[],
                              includeDone: true,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: 'Refresh context',
                child: IconButton.outlined(
                  onPressed: controller.tasksBusy
                      ? null
                      : () => unawaited(controller.refreshTasksFromUi()),
                  icon: const Icon(Icons.refresh),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'New backlog item',
                child: IconButton.filled(
                  onPressed: controller.tasksBusy
                      ? null
                      : () => unawaited(
                          _showTaskCreateDialog(context, controller),
                        ),
                  icon: const Icon(Icons.add),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final status in _taskStatuses)
                FilterChip(
                  label: Text(_taskLabel(status)),
                  selected: filters.statuses.contains(status),
                  onSelected: (_) {
                    unawaited(
                      controller.applyTaskFilters(
                        filters.copyWith(
                          statuses: _toggleFilterValue(
                            filters.statuses,
                            status,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              FilterChip(
                label: const Text('Overdue'),
                selected: filters.overdueOnly,
                onSelected: (selected) {
                  unawaited(
                    controller.applyTaskFilters(
                      filters.copyWith(overdueOnly: selected),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final priority in _taskPriorities)
                FilterChip(
                  label: Text(_taskLabel(priority)),
                  selected: filters.priorities.contains(priority),
                  onSelected: (_) {
                    unawaited(
                      controller.applyTaskFilters(
                        filters.copyWith(
                          priorities: _toggleFilterValue(
                            filters.priorities,
                            priority,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              for (final topic in controller.taskTopics.take(8))
                FilterChip(
                  label: Text(topic),
                  selected: filters.topics.contains(topic),
                  onSelected: (_) {
                    unawaited(
                      controller.applyTaskFilters(
                        filters.copyWith(
                          topics: _toggleFilterValue(filters.topics, topic),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
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
    required this.onComplete,
    required this.onDelete,
    required this.insightBadges,
  });

  final WorkspaceTask task;
  final bool selected;
  final bool focused;
  final List<ScreenChange> changes;
  final VoidCallback onTap;
  final VoidCallback? onComplete;
  final VoidCallback onDelete;
  final List<String> insightBadges;

  /// Builds one selectable context row.
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected || focused
              ? AuroraColors.greenSoft
              : const Color(0xfffffcf8),
          border: Border.all(
            color: focused
                ? AuroraColors.coral
                : selected
                ? AuroraColors.green
                : changes.isNotEmpty
                ? const Color(0xffc98219)
                : AuroraColors.border,
            width: focused || changes.isNotEmpty ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Checkbox(
              value: task.done,
              onChanged: onComplete == null ? null : (_) => onComplete!(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _TaskPriorityBadge(priority: task.priority),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Delete backlog item',
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 17,
                            color: AuroraColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (task.description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      task.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AuroraColors.muted),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      _TaskBadge(label: _taskLabel(task.status)),
                      if (task.overdue) const _TaskBadge(label: 'Overdue'),
                      if (task.dueAt != null)
                        _TaskBadge(label: 'Due ${_formatTaskDate(task.dueAt)}'),
                      if (task.scheduledAt != null)
                        _TaskBadge(
                          label:
                              'Scheduled ${_formatTaskDate(task.scheduledAt)}',
                        ),
                      if (task.memoryLinks.isNotEmpty)
                        _TaskBadge(
                          label: '${task.memoryLinks.length} memories',
                        ),
                      if (task.sourceLabel.isNotEmpty)
                        _TaskBadge(label: task.sourceLabel),
                      for (final badge in insightBadges)
                        _TaskBadge(label: badge),
                      for (final topic in task.topics.take(3))
                        _TaskBadge(label: topic),
                    ],
                  ),
                  if (changes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    _TaskTileScreenChanges(changes: changes),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskPriorityBadge extends StatelessWidget {
  const _TaskPriorityBadge({required this.priority});

  final String priority;

  /// Builds a priority badge with urgency-aware color.
  @override
  Widget build(BuildContext context) {
    final urgent = priority == 'urgent' || priority == 'high';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: urgent ? const Color(0xffffefed) : AuroraColors.panel,
        border: Border.all(
          color: urgent ? AuroraColors.coral : AuroraColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _taskLabel(priority),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: urgent ? AuroraColors.coral : AuroraColors.green,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TaskCaptureContent extends StatefulWidget {
  const _TaskCaptureContent({required this.controller, required this.query});

  final AuroraAppController controller;
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
            Text(_message, style: const TextStyle(color: AuroraColors.coral)),
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
                  const Text(
                    'No nearby context',
                    style: TextStyle(color: AuroraColors.muted),
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

  final AuroraAppController controller;
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
            Text(_message, style: const TextStyle(color: AuroraColors.coral)),
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

  final AuroraAppController controller;
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

  final AuroraAppController controller;
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
            const Text(
              'No WBS metadata',
              style: TextStyle(color: AuroraColors.muted),
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
            style: const TextStyle(
              color: AuroraColors.muted,
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
          const Icon(
            Icons.construction_outlined,
            size: 16,
            color: AuroraColors.muted,
          ),
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
                    style: const TextStyle(
                      color: AuroraColors.muted,
                      fontSize: 12,
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

/// _TaskInsightDetailsBlock explains selected-task insight membership.
class _TaskInsightDetailsBlock extends StatelessWidget {
  const _TaskInsightDetailsBlock({
    required this.controller,
    required this.task,
  });

  final AuroraAppController controller;
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
            style: const TextStyle(color: AuroraColors.ink, height: 1.35),
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

  final AuroraAppController controller;
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
          Text(emptyLabel, style: const TextStyle(color: AuroraColors.muted))
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

  final AuroraAppController controller;
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

  final AuroraAppController controller;
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

  final AuroraAppController controller;
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
        _TaskMetadataRow(label: 'Evidence', value: edge.evidenceIds.join(', ')),
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

  final AuroraAppController controller;
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

  final AuroraAppController controller;
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

  final AuroraAppController controller;
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: AuroraColors.green),
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
                    style: const TextStyle(
                      color: AuroraColors.muted,
                      fontSize: 12,
                    ),
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

  final AuroraAppController controller;
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
    return PanelSectionBlock(
      child: record == null
          ? const Text(
              'No memory selected',
              style: TextStyle(color: AuroraColors.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 17,
                      color: AuroraColors.green,
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
                    style: const TextStyle(
                      color: AuroraColors.muted,
                      fontSize: 13,
                    ),
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
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (links.isEmpty)
            const Text(
              'No linked memory',
              style: TextStyle(color: AuroraColors.muted),
            )
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
                            style: const TextStyle(
                              color: AuroraColors.muted,
                              fontSize: 12,
                            ),
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
    return Text(
      label.toUpperCase(),
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AuroraColors.muted,
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
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xfffffbf1),
        border: Border.all(color: const Color(0xffeed7ad)),
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
                    color: _screenChangeColor(change),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          change.summary,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AuroraColors.green,
                          ),
                        ),
                        if (change.afterValues.isNotEmpty)
                          Text(
                            _inlineScreenChangeDiff(change),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AuroraColors.muted,
                            ),
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
    final dropdownValue = values.contains(value) ? value : values.first;
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AuroraColors.surface,
          border: Border.all(color: AuroraColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: dropdownValue,
            isDense: true,
            isExpanded: true,
            icon: const Icon(Icons.expand_more, size: 18),
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
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: maxLines == 1 ? 1 : 3,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AuroraColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AuroraColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AuroraColors.border),
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
                fillColor: AuroraColors.surface,
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
                  borderSide: const BorderSide(color: AuroraColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AuroraColors.border),
                ),
              ),
              child: Text(
                hasValue ? _datePickerFieldLabel(value) : 'Select date',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasValue ? AuroraColors.ink : AuroraColors.muted,
                ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AuroraColors.muted,
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
    return const Center(
      child: Text(
        'Select a backlog item or list',
        style: TextStyle(color: AuroraColors.muted),
      ),
    );
  }
}

/// Shows the graph metadata editing dialog.
Future<void> _showTaskMetadataDialog(
  BuildContext context,
  AuroraAppController controller,
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

  final AuroraAppController controller;
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
                  style: const TextStyle(color: AuroraColors.coral),
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
  AuroraAppController controller,
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

  final AuroraAppController controller;
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
                  style: const TextStyle(color: AuroraColors.coral),
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
  AuroraAppController controller,
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

  final AuroraAppController controller;
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
                    decoration: _taskDialogDecoration('Related backlog item'),
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
  AuroraAppController controller,
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

  final AuroraAppController controller;
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
  AuroraAppController controller,
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

  final AuroraAppController controller;

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
Set<String> _queuePresetTaskIds(AuroraAppController controller) {
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
  AuroraAppController controller,
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
InputDecoration _taskDialogDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AuroraColors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AuroraColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AuroraColors.border),
    ),
  );
}

/// Resolves a task title for graph rows.
String _taskTitleFor(AuroraAppController controller, String taskId) {
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
  AuroraAppController controller,
  String endpointId,
) {
  if (_isConstellationAnchorEndpoint(endpointId)) {
    return endpointId.substring('anchor:'.length);
  }
  return _taskTitleFor(controller, endpointId);
}

/// Reports whether one screen change matches a review filter query.
bool _matchesTaskChange(ScreenChange change, String query) {
  final text = <String>[
    change.summary,
    change.reason,
    change.error,
    change.target.taskId,
    change.target.taskTitle,
    _screenChangeOperationLabel(change.operation),
    _screenChangeStatusLabel(change),
  ].join(' ');
  return _matchesText(text, query);
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
Color _screenChangeColor(ScreenChange change) {
  return switch (change.status) {
    ScreenChangeStatus.applied => AuroraColors.green,
    ScreenChangeStatus.rejected ||
    ScreenChangeStatus.failed => AuroraColors.coral,
    ScreenChangeStatus.undone => AuroraColors.muted,
    ScreenChangeStatus.proposed =>
      change.safety == ScreenChangeSafety.autoApply
          ? AuroraColors.green
          : const Color(0xffc98219),
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
