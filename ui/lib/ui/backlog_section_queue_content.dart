/// Backlog queue content widget.
part of 'backlog_section.dart';

class _BacklogQueueContent extends StatelessWidget {
  const _BacklogQueueContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds the filtered operational backlog queue.
  @override
  Widget build(BuildContext context) {
    final tasks = controller.filteredTasks.where((task) {
      return _matchesTask(task, query);
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
                ),
              ),
        ],
      ),
    );
  }
}
