/// Backlog task graph label helpers.
part of 'backlog_section.dart';

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
