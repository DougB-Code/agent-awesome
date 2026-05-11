/// Backlog command shell, review queue, and task queue widgets.
part of 'backlog_section.dart';

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
            statuses: toggleStringValue(filters.statuses, value),
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
                priorities: toggleStringValue(filters.priorities, value),
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
                topics: toggleStringValue(filters.topics, value),
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
                                            'Due ${formatOptionalLocalDate(task.dueAt)}',
                                      ),
                                    if (task.scheduledAt != null)
                                      _TaskBadge(
                                        label:
                                            'Scheduled ${formatOptionalLocalDate(task.scheduledAt)}',
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
