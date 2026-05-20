/// Defines the app shell section labels shared by navigation and routing.
library;

/// AppSections stores canonical top-level workspace names.
abstract final class AppSections {
  /// Today dashboard section.
  static const String today = 'Today';

  /// Chat workspace section.
  static const String chat = 'Chat';

  /// Backlog workspace section backed by graph task data.
  static const String backlog = 'Backlog';

  /// Workflow run and approval operations section.
  static const String automationOperations = 'Operations';

  /// MCP server toolset configuration section.
  static const String automationMcpServers = 'MCP Servers';

  /// Harness OS/local tool configuration section.
  static const String automationTools = 'Tools';

  /// Memory workspace section.
  static const String memory = 'Memory';

  /// File/source workspace section.
  static const String files = 'Files';

  /// People workspace section.
  static const String people = 'People';

  /// Settings workspace section.
  static const String settings = 'Settings';
}
