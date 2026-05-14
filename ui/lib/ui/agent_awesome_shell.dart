/// Implements the Agent Awesome assistant workspace shell and feature surfaces.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/theme.dart';
import '../domain/date_formatting.dart';
import '../domain/models.dart';
import '../features/today/attention_screen.dart';
import '../features/today/today_screen.dart';
import 'command_bar/command_context.dart';
import 'command_bar/command_router.dart';
import 'backlog_section.dart';
import 'files_section.dart';
import 'panels/panels.dart';
import 'people_section.dart';
import 'settings/settings_panel.dart';
import 'shell/app_sections.dart';
import 'shell/app_shell_frame.dart';
import 'string_list_values.dart';
import 'workspace/workspace_widgets.dart';

part 'agent_awesome_shell_chat.dart';
part 'agent_awesome_shell_chat_composer.dart';
part 'agent_awesome_shell_chat_context_helpers.dart';
part 'agent_awesome_shell_chat_context_widgets.dart';
part 'agent_awesome_shell_chat_conversation.dart';
part 'agent_awesome_shell_chat_runtime.dart';
part 'agent_awesome_shell_chat_shell.dart';
part 'agent_awesome_shell_memory.dart';
part 'agent_awesome_shell_memory_browse.dart';
part 'agent_awesome_shell_memory_capture.dart';
part 'agent_awesome_shell_memory_controls.dart';
part 'agent_awesome_shell_memory_corrections.dart';
part 'agent_awesome_shell_memory_details.dart';
part 'agent_awesome_shell_memory_metadata.dart';
part 'agent_awesome_shell_memory_pages.dart';
part 'agent_awesome_shell_memory_safety.dart';
part 'agent_awesome_shell_memory_search.dart';
part 'agent_awesome_shell_memory_shell.dart';
part 'agent_awesome_shell_memory_vocabulary.dart';

/// AgentAwesomeShell renders the desktop assistant workspace.
class AgentAwesomeShell extends StatefulWidget {
  /// Creates the shell bound to an app controller.
  const AgentAwesomeShell({super.key, required this.controller});

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  @override
  State<AgentAwesomeShell> createState() => _AgentAwesomeShellState();
}

class _AgentAwesomeShellState extends State<AgentAwesomeShell> {
  final TextEditingController _commandController = TextEditingController();
  String _section = AppSections.today;
  String _todayRoute = '';
  String _settingsSection = 'App';
  bool _sidebarExpanded = true;
  final Map<String, String> _activeAreas = <String, String>{};

  /// Cleans up text input state.
  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  /// Builds the main desktop shell.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          body: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              gradient: context.agentAwesomeWorkspaceGradient,
            ),
            child: AppShellFrame(
              selectedSection: _section,
              controller: widget.controller,
              commandController: _commandController,
              commandContext: _commandContext,
              onSubmitScreenCommand: _submitScreenCommand,
              sidebarExpanded: _sidebarExpanded,
              onSelected: _selectSection,
              onToggleSidebar: _toggleSidebar,
              onSubmit: _submitCommand,
              onNewChat: _startNewChat,
              onStartChatWithProfile: _startNewChatWithProfile,
              onSelectHistoryChat: _selectHistoryChat,
              onOpenSection: _selectSection,
              onOpenSettingsSection: _openSettingsSection,
              onOpenSettings: () => _selectSection(AppSections.settings),
              onOpenSetup: _openSetupWizard,
              content: _buildContent(context),
            ),
          ),
        );
      },
    );
  }

  /// Leaves the workspace shell so the dedicated setup wizard can be shown.
  void _openSetupWizard() {
    unawaited(widget.controller.setGettingStartedCompleted(false));
  }

  /// Builds the selected top-level workspace content.
  Widget _buildContent(BuildContext context) {
    if (_memoryMessageIsError(widget.controller) &&
        _memoryBackedSectionUnavailable(_section)) {
      return _MemoryUnavailableRoute(controller: widget.controller);
    }
    switch (_section) {
      case AppSections.today:
        if (_todayRoute.startsWith('/attention')) {
          return TodayAttentionScreen(
            controller: widget.controller,
            route: _todayRoute,
            onOpenToday: () => _selectSection(AppSections.today),
            onOpenBacklogTask: _openBacklogTask,
          );
        }
        return TodayScreen(
          controller: widget.controller,
          onOpenRoute: _openProjectionRoute,
        );
      case AppSections.chat:
        return _ChatCommandSubShell(
          controller: widget.controller,
          onAreaChanged: _rememberArea(AppSections.chat),
        );
      case AppSections.memory:
        return _MemoryCommandSubShell(
          controller: widget.controller,
          onAreaChanged: _rememberArea(AppSections.memory),
        );
      case AppSections.backlog:
        final backlogPanel = BacklogCommandPanel(
          controller: widget.controller,
          onAreaChanged: _rememberArea(AppSections.backlog),
        );
        if (widget.controller.backlogChatPanelOpen) {
          return SplitPanelShell(
            split: const PanelSplit(left: 0.74, min: 0.52, max: 0.86),
            left: backlogPanel,
            right: _ChatCommandPanel(controller: widget.controller),
          );
        }
        return backlogPanel;
      case AppSections.files:
        return FilesCommandSubShell(
          controller: widget.controller,
          onAreaChanged: _rememberArea(AppSections.files),
        );
      case AppSections.people:
        return PeopleCommandSubShell(
          controller: widget.controller,
          onAreaChanged: _rememberArea(AppSections.people),
        );
      case AppSections.settings:
        return SettingsCommandSubShell(
          controller: widget.controller,
          selectedSection: _settingsSection,
          onSectionSelected: _selectSettingsSection,
          onAreaChanged: _rememberArea(AppSections.settings),
        );
      default:
        return HomeWorkspace(
          controller: widget.controller,
          onOpenSection: _selectSection,
        );
    }
  }

  /// Selects a top-level app section from sidebar or command navigation.
  void _selectSection(String section) {
    setState(() {
      _section = section;
      _todayRoute = '';
    });
    if (section == AppSections.chat) {
      widget.controller.openHome();
    } else if (section == AppSections.today) {
      widget.controller.openHome();
    }
  }

  /// Opens a reserved route emitted by a projection-backed Today card.
  void _openProjectionRoute(String route) {
    if (route.startsWith('/attention')) {
      setState(() {
        _section = AppSections.today;
        _todayRoute = route;
      });
      widget.controller.openHome();
      return;
    }
    final uri = Uri.tryParse(route);
    if (uri != null && uri.path == '/backlog') {
      final insightId = uri.queryParameters['insight'] ?? '';
      if (insightId.isNotEmpty) {
        unawaited(widget.controller.applyTaskInsightPreset(insightId));
      }
      _selectSection(AppSections.backlog);
      return;
    }
    final section = _sectionForProjectionRoute(route);
    if (section.isNotEmpty) {
      _selectSection(section);
    }
  }

  /// Opens one backing task in the Backlog inspector.
  void _openBacklogTask(String taskId) {
    if (taskId.isNotEmpty) {
      widget.controller.inspectBacklogTask(taskId);
    }
    _selectSection(AppSections.backlog);
  }

  /// Starts a new chat from the global command input.
  Future<void> _submitCommand({String profilePath = ''}) async {
    final value = _commandController.text;
    _commandController.clear();
    setState(() {
      _section = AppSections.chat;
    });
    final created = await widget.controller.createChat(
      profilePath: profilePath,
    );
    if (created && value.trim().isNotEmpty) {
      await widget.controller.sendUserMessage(value);
    }
  }

  /// Builds the context used by Enter-submitted global commands.
  CommandContext _commandContext(String text, {String profilePath = ''}) {
    return CommandContext(
      section: _section,
      area: _commandAreaForSection(),
      text: text,
      selectedTaskId: widget.controller.selectedGraphTaskId,
      selectedMemoryId: widget.controller.selectedMemory == null
          ? ''
          : widget.controller.memorySelectionKey(
              widget.controller.selectedMemory!,
            ),
      profilePath: profilePath,
    );
  }

  /// Returns the active command area for the current shell route.
  String _commandAreaForSection() {
    if (_section == AppSections.today && _todayRoute.startsWith('/attention')) {
      return 'Attention';
    }
    return _activeAreas[_section] ?? '';
  }

  /// Applies top-bar text to the current screen instead of starting a chat.
  Future<void> _submitScreenCommand(CommandContext context) async {
    final route = CommandRouter(
      taskFilters: widget.controller.taskFilters,
      memoryFilters: widget.controller.memoryFilters,
    ).route(context);
    switch (route.kind) {
      case CommandRouteKind.none:
        return;
      case CommandRouteKind.navigateSection:
        _selectSection(route.section);
      case CommandRouteKind.openSettings:
        _openSettingsSection(route.settingsSection);
      case CommandRouteKind.taskFilter:
        await widget.controller.applyTaskFilters(route.taskFilters!);
      case CommandRouteKind.refreshTasks:
        await widget.controller.refreshTasksFromUi();
      case CommandRouteKind.memoryFilter:
        await widget.controller.applyMemoryFilters(route.memoryFilters!);
      case CommandRouteKind.refreshMemory:
        await widget.controller.refreshMemoryFromUi();
      case CommandRouteKind.screenAi:
        await widget.controller.runBacklogScreenCommand(
          text: context.text,
          scopeLabel: context.scopeLabel,
        );
      case CommandRouteKind.assistant:
        await widget.controller.sendUserMessage(
          route.assistantText,
          displayText: route.displayText,
        );
    }
  }

  /// Remembers the currently active subview for top-bar command routing.
  ValueChanged<SwitcherPanelArea> _rememberArea(String section) {
    return (area) {
      final label = area.id.isEmpty ? area.title : area.id;
      if (_activeAreas[section] == label) {
        return;
      }
      setState(() {
        _activeAreas[section] = label;
      });
    };
  }

  /// Starts a blank chat from the global app bar.
  Future<void> _startNewChat() async {
    setState(() {
      _section = 'Chat';
    });
    await widget.controller.createChat();
  }

  /// Starts a blank chat with a specific runtime profile.
  Future<void> _startNewChatWithProfile(String profilePath) async {
    setState(() {
      _section = 'Chat';
    });
    await widget.controller.createChat(profilePath: profilePath);
  }

  /// Selects an existing saved chat from quick access.
  Future<void> _selectHistoryChat(String chatKey) async {
    setState(() {
      _section = 'Chat';
    });
    await widget.controller.selectHistoryChat(chatKey);
  }

  /// Opens a specific settings section from quick access.
  void _openSettingsSection(String section) {
    setState(() {
      _section = 'Settings';
      _settingsSection = section;
    });
  }

  /// Selects a settings section from the command subshell.
  void _selectSettingsSection(String section) {
    setState(() {
      _settingsSection = section;
    });
  }

  /// Toggles the primary workspace sidebar.
  void _toggleSidebar() {
    setState(() {
      _sidebarExpanded = !_sidebarExpanded;
    });
  }
}

/// Reports whether a top-level route depends on the memory service.
bool _memoryBackedSectionUnavailable(String section) {
  return section == AppSections.memory ||
      section == AppSections.people ||
      section == 'Calendar';
}

/// Maps non-Today projection routes onto existing top-level sections.
String _sectionForProjectionRoute(String route) {
  if (route.startsWith('/timeline')) {
    return '';
  }
  if (route.startsWith('/memory')) {
    return AppSections.memory;
  }
  if (route.startsWith('/open-loops') ||
      route.startsWith('/delegation') ||
      route.startsWith('/risks')) {
    return AppSections.backlog;
  }
  return '';
}

/// Returns whether a value matches a query using ordered fuzzy characters.
bool _matchesFuzzyQuery(String value, String query) {
  final normalizedValue = value.toLowerCase();
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }
  var cursor = 0;
  for (final codeUnit in normalizedQuery.codeUnits) {
    cursor = normalizedValue.indexOf(String.fromCharCode(codeUnit), cursor);
    if (cursor == -1) {
      return false;
    }
    cursor++;
  }
  return true;
}

const String _chatMemoryDetailId = 'memory';
const String _chatTasksDetailId = 'tasks';
const String _chatFilesDetailId = 'files';
const String _chatPeopleDetailId = 'people';
const String _chatRuntimeDetailId = 'runtime';

/// _ChatCommandSubShell renders chat in the official command-panel subshell.
