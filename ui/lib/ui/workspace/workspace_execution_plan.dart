/// Workspace execution plan and task line widgets.
part of 'workspace_widgets.dart';

/// ExecutionPlan renders active workspace tasks as an objective list.
class ExecutionPlan extends StatelessWidget {
  /// Creates a task plan.
  const ExecutionPlan({super.key, required this.tasks});

  /// Plan task rows.
  final List<WorkspaceTask> tasks;

  /// Builds the active objective task plan.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.circle, size: 10, color: colors.green),
            const SizedBox(width: 12),
            _WorkspaceEyebrow('EXECUTION PLAN', color: colors.green),
          ],
        ),
        const SizedBox(height: 24),
        for (final task in tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: TaskLine(task: task),
          ),
      ],
    );
  }
}

/// TaskLine renders one workspace task row.
class TaskLine extends StatelessWidget {
  /// Creates one plan or task row.
  const TaskLine({super.key, required this.task, this.onComplete});

  /// Task data to display.
  final WorkspaceTask task;

  /// Optional completion callback.
  final VoidCallback? onComplete;

  /// Builds one plan or task row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final mark = task.done
        ? Icon(Icons.check, size: 16, color: colors.green)
        : task.active
        ? Icon(Icons.circle, size: 13, color: colors.green)
        : const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onComplete,
          child: Container(
            height: 30,
            width: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: task.done ? colors.greenSoft : Colors.transparent,
              border: Border.all(
                color: task.done || task.active ? colors.green : colors.border,
              ),
            ),
            child: Center(child: mark),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                task.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(task.detail, style: TextStyle(color: colors.muted)),
            ],
          ),
        ),
      ],
    );
  }
}
