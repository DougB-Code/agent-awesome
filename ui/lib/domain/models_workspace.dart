/// Workspace aggregate data models shared by controllers and widgets.
part of 'models.dart';

/// ProjectWorkspace represents the focused workspace state.
class ProjectWorkspace {
  /// Creates a focused project workspace.
  const ProjectWorkspace({
    required this.title,
    required this.subtitle,
    required this.tasks,
    required this.sources,
    required this.memoryRecords,
  });

  /// Workspace title.
  final String title;

  /// Workspace subtitle.
  final String subtitle;

  /// Project tasks and plan steps.
  final List<WorkspaceTask> tasks;

  /// Source list.
  final List<SourceItem> sources;

  /// Contextual memory records.
  final List<MemoryRecord> memoryRecords;
}

/// EndpointStatus summarizes one service connection.
class EndpointStatus {
  /// Creates a service status row.
  const EndpointStatus({
    required this.name,
    required this.url,
    required this.state,
    this.message = '',
  });

  /// Service name.
  final String name;

  /// Service URL.
  final String url;

  /// Availability state.
  final ConnectionStateKind state;

  /// Optional status detail.
  final String message;
}
