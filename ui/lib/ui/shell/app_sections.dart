/// Defines the app shell section labels shared by navigation and routing.
library;

/// AppSections stores canonical top-level workspace names.
abstract final class AppSections {
  /// Today dashboard section.
  static const String today = 'Today';

  /// Chat workspace section.
  static const String chat = 'Chat';

  /// Workflow workspace section.
  static const String workflows = 'Workflows';

  /// Backlog workspace section backed by graph task data.
  static const String backlog = 'Backlog';

  /// Memory workspace section.
  static const String memory = 'Memory';

  /// File/source workspace section.
  static const String files = 'Files';

  /// Timeline workspace section.
  static const String timeline = 'Timeline';

  /// People workspace section.
  static const String people = 'People';

  /// Settings workspace section.
  static const String settings = 'Settings';
}
