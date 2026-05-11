/// Backlog screen-change display helpers.
part of 'backlog_section.dart';

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
