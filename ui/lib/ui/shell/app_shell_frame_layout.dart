/// App shell frame layout widget.
part of 'app_shell_frame.dart';

/// AppShellFrame lays out the persistent sidebar, command bar, and content.
class AppShellFrame extends StatelessWidget {
  /// Creates the app frame for the current workspace content.
  const AppShellFrame({
    super.key,
    required this.selectedSection,
    required this.controller,
    required this.commandController,
    required this.commandContext,
    required this.onSubmitScreenCommand,
    required this.sidebarExpanded,
    required this.onSelected,
    required this.onToggleSidebar,
    required this.onSubmit,
    required this.onNewChat,
    required this.onToggleAssistantChat,
    required this.onStartChatWithProfile,
    required this.onSelectHistoryChat,
    required this.onOpenSection,
    required this.onOpenSettingsSection,
    required this.onOpenSettings,
    required this.onOpenSetup,
    required this.content,
    this.assistantChatEnabled = true,
  });

  /// Currently selected sidebar section.
  final String selectedSection;

  /// Shared app controller for command-bar shortcuts.
  final AgentAwesomeAppController controller;

  /// Text controller for the global command input.
  final TextEditingController commandController;

  /// Builds the current screen command context.
  final CommandContext Function(String text, {String profilePath})
  commandContext;

  /// Sends text as a command for the current screen.
  final Future<void> Function(CommandContext context) onSubmitScreenCommand;

  /// Whether the sidebar is expanded.
  final bool sidebarExpanded;

  /// Sidebar section selection callback.
  final ValueChanged<String> onSelected;

  /// Sidebar expand/collapse callback.
  final VoidCallback onToggleSidebar;

  /// Sends the global command input into a new chat.
  final Future<void> Function({String profilePath}) onSubmit;

  /// Starts a blank default-profile chat.
  final VoidCallback onNewChat;

  /// Toggles the auxiliary AI chat panel.
  final VoidCallback onToggleAssistantChat;

  /// Starts a blank chat with a selected runtime profile.
  final ValueChanged<String> onStartChatWithProfile;

  /// Opens a saved chat from quick access.
  final ValueChanged<String> onSelectHistoryChat;

  /// Opens a top-level app section.
  final ValueChanged<String> onOpenSection;

  /// Opens a specific settings section.
  final ValueChanged<String> onOpenSettingsSection;

  /// Opens the settings workspace.
  final VoidCallback onOpenSettings;

  /// Reopens the first-run setup shell.
  final VoidCallback onOpenSetup;

  /// Whether the global auxiliary AI chat can open for the current content.
  final bool assistantChatEnabled;

  /// Main workspace content.
  final Widget content;

  /// Builds the single app shell that owns navigation and panel placement.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final sidebarWidth = sidebarExpanded
        ? _AppSidebar.expandedWidth
        : _AppSidebar.compactWidth;
    return Row(
      children: <Widget>[
        _AppSidebarColumn(
          width: sidebarWidth,
          expanded: sidebarExpanded,
          selected: selectedSection,
          onSelected: onSelected,
          onToggleExpanded: onToggleSidebar,
        ),
        Expanded(
          child: Column(
            children: <Widget>[
              CommandBar(
                commandController: commandController,
                appController: controller,
                commandContext: commandContext,
                onSubmitScreenCommand: onSubmitScreenCommand,
                onSubmit: onSubmit,
                onNewChat: onNewChat,
                onToggleAssistantChat: onToggleAssistantChat,
                onStartChatWithProfile: onStartChatWithProfile,
                onSelectHistoryChat: onSelectHistoryChat,
                onOpenSection: onOpenSection,
                onOpenSettingsSection: onOpenSettingsSection,
                onOpenSettings: onOpenSettings,
                onOpenSetup: onOpenSetup,
                assistantChatEnabled: assistantChatEnabled,
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.page,
                    gradient: context.agentAwesomeWorkspaceGradient,
                  ),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
