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
    return Padding(
      padding: PanelFormMetrics.panelPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TaskQueueFilterStrip(controller: controller),
          const SizedBox(height: PanelFormMetrics.compactGap),
          if (tasks.isEmpty)
            const Expanded(
              child: PanelEmptyBlock(
                icon: Icons.check_circle_outline,
                label: 'No backlog items match this view',
                message: 'Adjust the filters or create a backlog item.',
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  return _TaskQueueTile(
                    controller: controller,
                    task: task,
                    selected: controller.selectedTask?.id == task.id,
                    focused: controller.focusedBacklogTaskId == task.id,
                    changes: controller.screenChangesForTask(task.id),
                    onTap: () => controller.inspectBacklogTask(task.id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
