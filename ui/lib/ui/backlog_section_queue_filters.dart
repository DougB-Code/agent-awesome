/// Backlog queue header actions and filter menu widgets.
part of 'backlog_section.dart';

class _BacklogQueueHeaderActions extends StatelessWidget {
  const _BacklogQueueHeaderActions({
    required this.active,
    required this.onCapture,
  });

  final bool active;
  final VoidCallback onCapture;

  /// Builds the collection-level create entry beside the command-area icons.
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PanelIconButton(
          icon: Icons.add_task_outlined,
          tooltip: 'New backlog item',
          selected: active,
          onPressed: onCapture,
        ),
      ],
    );
  }
}

class _BacklogSelectedTaskActions extends StatelessWidget {
  const _BacklogSelectedTaskActions({
    required this.controller,
    required this.task,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  /// Builds selected-task actions beside the right-mode selector.
  @override
  Widget build(BuildContext context) {
    final terminal = task.status == 'done' || task.status == 'canceled';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PanelIconButton(
          icon: Icons.today_outlined,
          tooltip: 'Schedule selected backlog item today',
          onPressed: controller.tasksBusy || terminal
              ? null
              : () => unawaited(_scheduleToday()),
        ),
        const SizedBox(width: 8),
        PanelIconButton(
          icon: Icons.schedule_outlined,
          tooltip: 'Snooze selected backlog item',
          onPressed: controller.tasksBusy || terminal
              ? null
              : () => unawaited(_snooze()),
        ),
        const SizedBox(width: 8),
        PanelIconButton(
          icon: Icons.check_circle_outline,
          tooltip: 'Complete backlog item',
          onPressed: controller.tasksBusy || terminal
              ? null
              : () => unawaited(_complete(context)),
        ),
        const SizedBox(width: 8),
        PanelIconButton(
          icon: Icons.block_outlined,
          tooltip: 'Cancel backlog item',
          onPressed: controller.tasksBusy || terminal
              ? null
              : () => unawaited(_cancel(context)),
        ),
        const SizedBox(width: 8),
        PanelIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete backlog item',
          onPressed: controller.tasksBusy
              ? null
              : () => unawaited(_delete(context)),
        ),
      ],
    );
  }

  /// Schedules the selected backlog item for today.
  Future<void> _scheduleToday() {
    return controller.updateTaskFromUi(
      taskId: task.id,
      scheduledAt: _todayDate(),
    );
  }

  /// Moves the selected backlog item to tomorrow's schedule.
  Future<void> _snooze() {
    return controller.updateTaskFromUi(
      taskId: task.id,
      scheduledAt: _todayDate().add(const Duration(days: 1)),
    );
  }

  /// Completes the selected backlog item after confirmation.
  Future<void> _complete(BuildContext context) async {
    if (!await _confirmTaskWrite(
      context,
      'Complete backlog item "${task.title}"?',
    )) {
      return;
    }
    await controller.completeTaskFromUi(task.id);
  }

  /// Cancels the selected backlog item after confirmation.
  Future<void> _cancel(BuildContext context) async {
    if (!await _confirmTaskWrite(
      context,
      'Cancel backlog item "${task.title}"?',
    )) {
      return;
    }
    await controller.cancelTaskFromUi(task.id);
  }

  /// Deletes the selected backlog item after confirmation.
  Future<void> _delete(BuildContext context) async {
    if (!await _confirmTaskWrite(
      context,
      'Delete backlog item "${task.title}"?',
    )) {
      return;
    }
    await controller.deleteTaskFromUi(task.id);
  }
}

class _BacklogTaskMemoryActions extends StatelessWidget {
  const _BacklogTaskMemoryActions({
    required this.controller,
    required this.task,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  /// Builds selected-task memory actions beside the right-mode selector.
  @override
  Widget build(BuildContext context) {
    return PanelIconButton(
      icon: Icons.link_outlined,
      tooltip: 'Link selected memory to backlog item',
      onPressed: controller.tasksBusy || controller.selectedMemory == null
          ? null
          : () => unawaited(controller.linkSelectedMemoryToTaskFromUi(task.id)),
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
          _TaskStatusFilterMenu(controller: controller),
          _TaskPriorityFilterMenu(controller: controller),
          _TaskTopicFilterMenu(controller: controller),
        ],
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
          '__active_statuses' => filters.copyWith(
            statuses: _activeTaskStatuses,
            includeDone: true,
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
            label: 'Any statuses',
          ),
        ),
        CheckedPopupMenuItem<String>(
          value: '__active_statuses',
          checked: _isActiveTaskView(filters) && !filters.overdueOnly,
          child: const _TaskFilterMenuItem(
            icon: Icons.playlist_play,
            label: 'Active statuses',
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
        selected: filters.statuses.isNotEmpty || filters.overdueOnly,
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
