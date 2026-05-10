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

  Widget _buildContent(BuildContext context) {
    if (_memoryMessageIsError(widget.controller) &&
        _memoryBackedSectionUnavailable(_section)) {
      return _MemoryUnavailableRoute(controller: widget.controller);
    }
    final panelLayout = _buildPanelLayout();
    if (panelLayout != null) {
      if (panelLayout.third != null) {
        return SplitPanelShell(
          split: panelLayout.outerSplit,
          left: SplitPanelShell(
            split: panelLayout.split,
            left: panelLayout.left,
            right: panelLayout.right,
          ),
          right: panelLayout.third!,
        );
      }
      return SplitPanelShell(
        split: panelLayout.split,
        left: panelLayout.left,
        right: panelLayout.right,
      );
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
      default:
        return HomeWorkspace(
          controller: widget.controller,
          onOpenSection: _selectSection,
        );
    }
  }

  /// Builds the reusable two-panel layout for sections that use command panels.
  SectionLayout? _buildPanelLayout() {
    switch (_section) {
      case AppSections.settings:
        return SectionLayout(
          split: const PanelSplit(left: 0.25, min: 0.2, max: 0.45),
          left: SettingsMenuPanel(
            selected: _settingsSection,
            onSelected: (section) {
              setState(() {
                _settingsSection = section;
              });
            },
          ),
          right: SettingsDetailsPanel(
            controller: widget.controller,
            section: _settingsSection,
          ),
        );
      default:
        return null;
    }
  }

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
      selectedMemoryId: widget.controller.selectedMemory?.id ?? '',
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
class _ChatCommandSubShell extends StatefulWidget {
  const _ChatCommandSubShell({required this.controller, this.onAreaChanged});

  final AgentAwesomeAppController controller;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  @override
  State<_ChatCommandSubShell> createState() => _ChatCommandSubShellState();
}

class _ChatCommandSubShellState extends State<_ChatCommandSubShell> {
  String _detailModeId = _chatMemoryDetailId;

  /// Builds conversation and context in the shared command subshell.
  @override
  Widget build(BuildContext context) {
    return CommandPanelSubShell(
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          title: 'Conversation',
          icon: Icons.forum_outlined,
          builder: (query) => _ChatConversationContent(
            controller: widget.controller,
            query: query,
          ),
        ),
      ],
      detailTitle: 'Overview',
      detailModes: const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _chatMemoryDetailId,
          label: 'Memory',
          icon: Icons.auto_awesome_mosaic_outlined,
        ),
        CommandPanelDetailMode(
          id: _chatTasksDetailId,
          label: 'Tasks',
          icon: Icons.checklist_rtl_outlined,
        ),
        CommandPanelDetailMode(
          id: _chatFilesDetailId,
          label: 'Files',
          icon: Icons.folder_copy_outlined,
        ),
        CommandPanelDetailMode(
          id: _chatPeopleDetailId,
          label: 'People',
          icon: Icons.people_alt_outlined,
        ),
        CommandPanelDetailMode(
          id: _chatRuntimeDetailId,
          label: 'Runtime',
          icon: Icons.bolt_outlined,
        ),
      ],
      selectedDetailModeId: _detailModeId,
      onDetailModeSelected: _selectDetailMode,
      detailBuilder: _buildDetailContent,
      onAreaChanged: widget.onAreaChanged,
      areaActionsBuilder: (context, area) =>
          _ChatSessionPicker(controller: widget.controller),
      filterHint: 'Filter...',
      split: const PanelSplit(left: 0.64, min: 0.48, max: 0.82),
    );
  }

  /// Selects the active chat detail mode.
  void _selectDetailMode(String modeId) {
    setState(() => _detailModeId = modeId);
  }

  /// Builds the selected right-side chat utility surface.
  Widget _buildDetailContent(String modeId) {
    return switch (modeId) {
      _chatTasksDetailId => _buildTasksContent(),
      _chatFilesDetailId => _buildFilesContent(),
      _chatPeopleDetailId => _buildPeopleContent(),
      _chatRuntimeDetailId => _buildRuntimeContent(),
      _ => _buildMemoryContent(),
    };
  }

  /// Builds non-transcript memory used by the selected chat.
  Widget _buildMemoryContent() {
    final memories = _chatMemoryRecords(widget.controller);
    if (memories.isEmpty) {
      return const _ChatContextEmpty(label: 'No memory used in this chat');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        const _MemoryPanelLabel('Memory'),
        const SizedBox(height: 10),
        for (final record in memories.take(12))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ChatMemoryContextTile(record: record),
          ),
      ],
    );
  }

  /// Builds task context associated with the selected chat.
  Widget _buildTasksContent() {
    final tasks = widget.controller.selectedChatTasks.toList();
    if (tasks.isEmpty) {
      return const _ChatContextEmpty(label: 'No tasks linked to this chat');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        const _MemoryPanelLabel('Tasks'),
        const SizedBox(height: 10),
        for (final task in tasks.take(12))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ChatTaskContextTile(task: task),
          ),
      ],
    );
  }

  /// Builds file context associated with the selected chat.
  Widget _buildFilesContent() {
    final fileRecords = _chatFileRecords(widget.controller);
    final sources = _chatSourceItems(widget.controller).where((source) {
      return !_sourceItemRepresentedByFileRecord(source, fileRecords);
    }).toList();
    if (fileRecords.isEmpty && sources.isEmpty) {
      return const _ChatContextEmpty(label: 'No files used in this chat');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        const _MemoryPanelLabel('Files'),
        const SizedBox(height: 10),
        for (final record in fileRecords.take(12))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ChatMemoryContextTile(record: record),
          ),
        for (final source in sources.take(12))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ChatSourceContextTile(source: source),
          ),
      ],
    );
  }

  /// Builds people and entities mentioned by the selected chat context.
  Widget _buildPeopleContent() {
    final people = _chatPeopleRows(widget.controller);
    if (people.isEmpty) {
      return const _ChatContextEmpty(label: 'No people linked to this chat');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        const _MemoryPanelLabel('People'),
        const SizedBox(height: 10),
        for (final person in people.take(16))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ChatPersonContextTile(person: person),
          ),
      ],
    );
  }

  /// Builds runtime status and pending tool approval utilities.
  Widget _buildRuntimeContent() {
    final summaries = _chatRuntimeSummaries(widget.controller);
    if (summaries.isEmpty && widget.controller.pendingConfirmation == null) {
      return const _ChatContextEmpty(label: 'No runtime activity right now');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (widget.controller.pendingConfirmation != null)
          _ChatConfirmationUtility(
            confirmation: widget.controller.pendingConfirmation!,
            onAnswer: (option) =>
                unawaited(widget.controller.answerConfirmation(option)),
          ),
        if (summaries.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          const _MemoryPanelLabel('Runtime'),
          const SizedBox(height: 10),
          for (final summary in summaries)
            _ChatRuntimeSummaryTile(summary: summary),
        ],
      ],
    );
  }
}

class _ChatCommandPanel extends StatefulWidget {
  const _ChatCommandPanel({required this.controller});

  final AgentAwesomeAppController controller;

  @override
  State<_ChatCommandPanel> createState() => _ChatCommandPanelState();
}

class _ChatCommandPanelState extends State<_ChatCommandPanel> {
  /// Builds the dedicated chat command panel with conversation and chat areas.
  @override
  Widget build(BuildContext context) {
    return SwitcherPanel(
      titleControl: _ChatSessionPicker(controller: widget.controller),
      showAreaQuickSelect: false,
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          title: 'Conversation',
          icon: Icons.forum_outlined,
          builder: (query) => _ChatConversationContent(
            controller: widget.controller,
            query: query,
          ),
        ),
      ],
    );
  }
}

class _ChatConversationContent extends StatefulWidget {
  const _ChatConversationContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  @override
  State<_ChatConversationContent> createState() =>
      _ChatConversationContentState();
}

class _ChatConversationContentState extends State<_ChatConversationContent> {
  final TextEditingController _replyController = TextEditingController();

  /// Cleans up the persistent chat composer.
  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  /// Builds the selected conversation body and composer.
  Widget _buildConversationContent(String query) {
    final messages = widget.controller.messages.where((message) {
      return _matchesFuzzyQuery('${message.author} ${message.text}', query);
    }).toList();
    final timelineChildren = <Widget>[
      for (final message in messages) ChatRow(message: message),
      if (widget.controller.sending)
        const _ChatRuntimeNotice(
          icon: Icons.sync,
          label: 'Agent Awesome is responding',
        ),
    ];
    return Column(
      children: <Widget>[
        Expanded(
          child: ChatPanel(
            empty: PanelEmptyState(query: query),
            children: timelineChildren,
          ),
        ),
        Divider(height: 1, color: context.agentAwesomeColors.border),
        _ChatComposer(
          controller: _replyController,
          sending: widget.controller.sending,
          onSubmit: _submitReply,
        ),
      ],
    );
  }

  /// Builds the conversation content for the current fuzzy query.
  @override
  Widget build(BuildContext context) {
    return _buildConversationContent(widget.query);
  }

  /// Sends the composer text into the selected chat thread.
  Future<void> _submitReply() async {
    final value = _replyController.text;
    _replyController.clear();
    await widget.controller.sendUserMessage(value);
  }
}

class _ChatSessionPicker extends StatelessWidget {
  const _ChatSessionPicker({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds the active chat selector for the conversation panel.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final selectedChat = controller.selectedChatEntry;
    final selectedSession = _selectedSession();
    final selectedChatKey = controller.selectedChatKey;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SearchPickerDropdown<String>(
          label: selectedChat?.title ?? selectedSession?.title ?? 'Select chat',
          tooltip: 'Select chat',
          emptyLabel: 'No chats found',
          width: 240,
          selectedValue: selectedChatKey.isEmpty ? null : selectedChatKey,
          options: _chatOptions(),
          onSelected: (chatKey) {
            unawaited(controller.selectHistoryChat(chatKey));
          },
          onDelete: controller.deleteHistoryChat,
          deleteTooltip: 'Delete chat',
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Delete selected chat',
          child: SizedBox.square(
            dimension: 38,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: colors.muted,
                side: BorderSide(color: colors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: selectedChatKey.isEmpty
                  ? null
                  : () {
                      unawaited(controller.deleteHistoryChat(selectedChatKey));
                    },
              child: const Icon(Icons.delete_outline, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  /// Returns the currently selected session, if it is loaded.
  ChatSession? _selectedSession() {
    for (final session in controller.sessions) {
      if (session.id == controller.selectedSessionId) {
        return session;
      }
    }
    return null;
  }

  /// Builds chat selector rows from the app history or active sessions.
  List<SearchPickerOption<String>> _chatOptions() {
    if (controller.chatHistory.isNotEmpty) {
      return <SearchPickerOption<String>>[
        for (final chat in controller.chatHistory)
          SearchPickerOption<String>(
            value: chat.key,
            title: chat.title,
            subtitle:
                '${chat.profileLabel} • ${formatLocalMonthDayTime(chat.updatedAt)}',
            searchText:
                '${chat.sessionId} ${chat.profileId} ${chat.profilePath}',
            icon: Icons.chat_bubble_outline,
          ),
      ];
    }
    return <SearchPickerOption<String>>[
      for (final session in controller.sessions)
        SearchPickerOption<String>(
          value: '${controller.runtimeProfilePath}::${session.id}',
          title: session.title,
          subtitle: formatLocalMonthDayTime(session.updatedAt),
          searchText: session.id,
          icon: Icons.chat_bubble_outline,
        ),
    ];
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.sending,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSubmit;

  /// Builds the sticky same-thread composer for the chat timeline.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(18),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.softShadow,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Icon(Icons.chat_bubble_outline, color: colors.muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('chat-thread-composer'),
                  controller: controller,
                  enabled: !sending,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  style: TextStyle(color: colors.ink),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Message Agent Awesome in this chat...',
                    hintStyle: TextStyle(color: colors.muted),
                  ),
                  onSubmitted: (_) {
                    if (!sending) {
                      onSubmit();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: colors.green,
                    foregroundColor: Colors.white,
                    fixedSize: const Size(42, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: sending ? null : onSubmit,
                  icon: Icon(
                    sending ? Icons.hourglass_top : Icons.arrow_upward,
                  ),
                  tooltip: 'Send message',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatRuntimeNotice extends StatelessWidget {
  const _ChatRuntimeNotice({required this.icon, required this.label});

  final IconData icon;
  final String label;

  /// Builds a compact live runtime notice in the chat stream.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: Row(
        children: <Widget>[
          Icon(icon, color: colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMemoryContextTile extends StatelessWidget {
  const _ChatMemoryContextTile({required this.record});

  final MemoryRecord record;

  /// Builds one memory context tile for chat utilities.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            record.title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          if (record.summary.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              _chatContextDisplayText(record.summary),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.muted),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _MemoryBadge(label: record.kind),
              _MemoryBadge(label: record.sensitivity),
              if (record.sourceLabel.isNotEmpty)
                _MemoryBadge(label: record.sourceLabel),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatTaskContextTile extends StatelessWidget {
  const _ChatTaskContextTile({required this.task});

  final WorkspaceTask task;

  /// Builds one associated context tile for the chat context panel.
  @override
  Widget build(BuildContext context) {
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TaskLine(task: task),
          if (task.sourceLabel.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            _MemoryBadge(label: task.sourceLabel),
          ],
        ],
      ),
    );
  }
}

/// _ChatSourceContextTile renders one source file referenced by the chat.
class _ChatSourceContextTile extends StatelessWidget {
  const _ChatSourceContextTile({required this.source});

  final SourceItem source;

  /// Builds a compact source tile for the chat files panel.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.insert_drive_file_outlined, color: colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  source.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (source.detail.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    source.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// _ChatPersonContextTile renders one person or entity tied to chat context.
class _ChatPersonContextTile extends StatelessWidget {
  const _ChatPersonContextTile({required this.person});

  final _ChatPersonContext person;

  /// Builds a person overview row for the chat people panel.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.person_outline, color: colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  person.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    _MemoryBadge(label: '${person.memoryCount} memories'),
                    _MemoryBadge(label: '${person.taskCount} tasks'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// _ChatContextEmpty renders a specific empty state for chat overview modes.
class _ChatContextEmpty extends StatelessWidget {
  const _ChatContextEmpty({required this.label});

  final String label;

  /// Builds the centered empty-state message.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: TextStyle(color: context.agentAwesomeColors.muted),
      ),
    );
  }
}

/// _ChatRuntimeSummary stores one user-facing runtime fact.
class _ChatRuntimeSummary {
  const _ChatRuntimeSummary({
    required this.title,
    required this.detail,
    required this.state,
    required this.icon,
    this.message = '',
  });

  final String title;
  final String detail;
  final ConnectionStateKind state;
  final IconData icon;
  final String message;
}

/// _ChatRuntimeSummaryTile renders one simplified runtime status.
class _ChatRuntimeSummaryTile extends StatelessWidget {
  const _ChatRuntimeSummaryTile({required this.summary});

  final _ChatRuntimeSummary summary;

  /// Builds one runtime fact without exposing internal service URLs.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final color = switch (summary.state) {
      ConnectionStateKind.connected => colors.green,
      ConnectionStateKind.disconnected => colors.coral,
      ConnectionStateKind.unknown => colors.muted,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PanelSectionBlock(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(summary.icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    summary.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summary.detail,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted),
                  ),
                  if (summary.message.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(summary.message, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatConfirmationUtility extends StatelessWidget {
  const _ChatConfirmationUtility({
    required this.confirmation,
    required this.onAnswer,
  });

  final ConfirmationRequest confirmation;
  final ValueChanged<ConfirmationOption> onAnswer;

  /// Builds the pending approval utility for chat tool calls.
  @override
  Widget build(BuildContext context) {
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _MemoryPanelLabel('Pending approval'),
          const SizedBox(height: 8),
          Text(confirmation.hint),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final option in confirmation.options)
                OutlinedButton(
                  onPressed: () => onAnswer(option),
                  child: Text(option.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// _ChatPersonContext stores aggregate person context for one chat.
class _ChatPersonContext {
  const _ChatPersonContext({
    required this.name,
    required this.memoryCount,
    required this.taskCount,
  });

  final String name;
  final int memoryCount;
  final int taskCount;
}

/// Builds the simplified runtime facts users expect from chat.
List<_ChatRuntimeSummary> _chatRuntimeSummaries(
  AgentAwesomeAppController controller,
) {
  return <_ChatRuntimeSummary>[
    _chatModelRuntimeSummary(controller),
    _chatMemoryRuntimeSummary(controller),
    _chatSessionRuntimeSummary(controller),
  ];
}

/// Returns the chat model selected by the active runtime profile.
_ChatRuntimeSummary _chatModelRuntimeSummary(
  AgentAwesomeAppController controller,
) {
  final entry = _activeModelConfigEntry(controller);
  final choice = _defaultModelChoice(entry);
  final label = choice == null ? 'No model configured' : choice.label;
  final modelName = choice?.modelName.trim() ?? '';
  final detail = modelName.isEmpty || modelName == choice?.modelId
      ? label
      : '$label - $modelName';
  return _ChatRuntimeSummary(
    title: 'Chat model',
    detail: detail,
    state: choice == null
        ? ConnectionStateKind.disconnected
        : ConnectionStateKind.connected,
    icon: Icons.memory_outlined,
    message: entry == null ? 'Select a model in Settings.' : '',
  );
}

/// Returns the default model choice from a config entry.
dynamic _defaultModelChoice(dynamic entry) {
  if (entry == null || entry.modelChoices.isEmpty) {
    return null;
  }
  for (final choice in entry.modelChoices) {
    if (choice.isDefault) {
      return choice;
    }
  }
  return entry.modelChoices.first;
}

/// Returns the memory source configured for the active runtime profile.
_ChatRuntimeSummary _chatMemoryRuntimeSummary(
  AgentAwesomeAppController controller,
) {
  final memoryServer = _activeMemoryServer(controller);
  final name = memoryServer?.label ?? 'Memory';
  final endpoint = _statusNamed(controller.endpointStatuses, name);
  final process = _statusNamed(controller.localProcessStatuses, name);
  final state = _combinedRuntimeState(endpoint?.state, process?.state);
  final message = endpoint?.message.isNotEmpty == true
      ? endpoint!.message
      : process?.message ?? '';
  return _ChatRuntimeSummary(
    title: 'Memory',
    detail: name,
    state: state,
    icon: Icons.auto_awesome_mosaic_outlined,
    message: message,
  );
}

/// Returns the first enabled memory server from the active runtime profile.
dynamic _activeMemoryServer(AgentAwesomeAppController controller) {
  final profile = controller.runtimeProfile;
  if (profile == null) {
    return null;
  }
  for (final server in profile.mcpServers) {
    if (server.enabled && server.kind == 'memory') {
      return server;
    }
  }
  return null;
}

/// Returns the active chat session runtime without exposing API plumbing names.
_ChatRuntimeSummary _chatSessionRuntimeSummary(
  AgentAwesomeAppController controller,
) {
  final gateway = controller.runtimeProfile?.gateway;
  final profile = controller.runtimeProfile;
  final label = profile?.label ?? 'No profile selected';
  final serviceLabel = gateway != null && gateway.enabled
      ? gateway.label
      : profile?.harness.label ?? '';
  final endpoint = _statusNamed(controller.endpointStatuses, 'Agent API');
  final process = _statusNamed(controller.localProcessStatuses, serviceLabel);
  final state = _combinedRuntimeState(endpoint?.state, process?.state);
  final message = endpoint?.message.isNotEmpty == true
      ? endpoint!.message
      : process?.message ?? '';
  return _ChatRuntimeSummary(
    title: 'Profile',
    detail: label,
    state: state,
    icon: Icons.forum_outlined,
    message: message,
  );
}

/// Returns the model config entry assigned to the active runtime profile.
dynamic _activeModelConfigEntry(AgentAwesomeAppController controller) {
  final path = controller.runtimeProfile?.harness.modelConfigPath.trim() ?? '';
  for (final entry in controller.availableModelConfigs) {
    if (entry.path == path || entry.assigned) {
      return entry;
    }
  }
  return null;
}

/// Returns a status by display name.
dynamic _statusNamed(Iterable<dynamic> statuses, String name) {
  for (final status in statuses) {
    if (status.name == name) {
      return status;
    }
  }
  return null;
}

/// Combines process and endpoint availability into one user-facing state.
ConnectionStateKind _combinedRuntimeState(
  ConnectionStateKind? endpoint,
  ConnectionStateKind? process,
) {
  if (endpoint == ConnectionStateKind.connected ||
      process == ConnectionStateKind.connected) {
    return ConnectionStateKind.connected;
  }
  if (endpoint == ConnectionStateKind.disconnected ||
      process == ConnectionStateKind.disconnected) {
    return ConnectionStateKind.disconnected;
  }
  return ConnectionStateKind.unknown;
}

/// Returns non-file memory records associated with the selected chat.
List<MemoryRecord> _chatMemoryRecords(AgentAwesomeAppController controller) {
  final records = _chatRelevantMemoryRecords(controller).where((record) {
    return !_chatContextRecordIsFile(record);
  }).toList();
  records.sort((left, right) => left.title.compareTo(right.title));
  return records;
}

/// Returns file-like memory records associated with the selected chat.
List<MemoryRecord> _chatFileRecords(AgentAwesomeAppController controller) {
  final records = _chatRelevantMemoryRecords(controller).where((record) {
    return _chatContextRecordIsFile(record);
  }).toList();
  records.sort((left, right) => left.title.compareTo(right.title));
  return records;
}

/// Returns source items associated with the selected chat transcript.
List<SourceItem> _chatSourceItems(AgentAwesomeAppController controller) {
  final transcript = _chatTranscript(controller);
  final sources = controller.workspace.sources.where((source) {
    return _sourceItemBelongsToChat(source, transcript);
  }).toList();
  sources.sort((left, right) => left.title.compareTo(right.title));
  return sources;
}

/// Returns memory records associated with the selected chat, excluding messages.
List<MemoryRecord> _chatRelevantMemoryRecords(
  AgentAwesomeAppController controller,
) {
  final sessionId = controller.selectedSessionId ?? '';
  final transcript = _chatTranscript(controller);
  return controller.workspace.memoryRecords.where((record) {
    return !_chatContextRecordIsChatMessage(record) &&
        _memoryRecordBelongsToChat(record, sessionId, transcript);
  }).toList();
}

/// Builds aggregate people rows from chat memory and task context.
List<_ChatPersonContext> _chatPeopleRows(AgentAwesomeAppController controller) {
  final memoryCounts = <String, int>{};
  final taskCounts = <String, int>{};
  for (final record in _chatRelevantMemoryRecords(controller)) {
    if (_chatContextRecordIsFile(record)) {
      continue;
    }
    for (final name in record.entityNames) {
      final normalized = name.trim();
      if (normalized.isNotEmpty) {
        memoryCounts[normalized] = (memoryCounts[normalized] ?? 0) + 1;
      }
    }
  }
  for (final task in controller.selectedChatTasks) {
    final owner = task.owner.trim();
    if (owner.isNotEmpty) {
      taskCounts[owner] = (taskCounts[owner] ?? 0) + 1;
    }
  }
  final names = <String>{...memoryCounts.keys, ...taskCounts.keys}.toList()
    ..sort();
  return <_ChatPersonContext>[
    for (final name in names)
      _ChatPersonContext(
        name: name,
        memoryCount: memoryCounts[name] ?? 0,
        taskCount: taskCounts[name] ?? 0,
      ),
  ];
}

/// Returns the selected chat transcript as searchable lowercase text.
String _chatTranscript(AgentAwesomeAppController controller) {
  return controller.messages
      .map((message) => '${message.author} ${message.text}')
      .join('\n')
      .toLowerCase();
}

/// Reports whether a memory record belongs to the selected chat.
bool _memoryRecordBelongsToChat(
  MemoryRecord record,
  String sessionId,
  String transcript,
) {
  final sessionNeedle = sessionId.trim().toLowerCase();
  final metadata = <String>[
    record.id,
    record.title,
    record.summary,
    record.sourceLabel,
    record.sourceSystem,
    record.sourceId,
    record.rawPath,
    record.rawMediaType,
    ...record.topics,
    ...record.subjects,
    ...record.entityNames,
  ].join(' ').toLowerCase();
  if (sessionNeedle.isNotEmpty && metadata.contains(sessionNeedle)) {
    return true;
  }
  return _anyMeaningfulTokenAppears(transcript, <String>[
    record.title,
    record.sourceLabel,
    record.sourceId,
    _lastPathSegment(record.rawPath),
    _lastPathSegment(record.sourceId),
    ...record.entityNames,
    ...record.subjects,
  ]);
}

/// Reports whether a source item appears in the selected chat transcript.
bool _sourceItemBelongsToChat(SourceItem source, String transcript) {
  return _anyMeaningfulTokenAppears(transcript, <String>[
    source.id,
    source.title,
    source.detail,
    _lastPathSegment(source.id),
    _lastPathSegment(source.detail),
  ]);
}

/// Reports whether a source row is already represented by a file memory record.
bool _sourceItemRepresentedByFileRecord(
  SourceItem source,
  List<MemoryRecord> fileRecords,
) {
  final sourceTokens =
      <String>[
        source.id,
        source.title,
        source.detail,
        _lastPathSegment(source.id),
        _lastPathSegment(source.title),
        _lastPathSegment(source.detail),
      ].map((value) => value.trim().toLowerCase()).where((value) {
        return value.isNotEmpty;
      }).toSet();
  for (final record in fileRecords) {
    final recordTokens =
        <String>[
          record.id,
          record.evidenceId,
          record.title,
          record.sourceLabel,
          record.sourceId,
          record.rawPath,
          _lastPathSegment(record.title),
          _lastPathSegment(record.sourceId),
          _lastPathSegment(record.rawPath),
        ].map((value) => value.trim().toLowerCase()).where((value) {
          return value.isNotEmpty;
        });
    if (recordTokens.any(sourceTokens.contains)) {
      return true;
    }
  }
  return false;
}

/// Removes storage/provenance jargon from chat overview display text.
String _chatContextDisplayText(String value) {
  return value
      .replaceAll(
        RegExp(r'\bAgent Awesome file evidence\b', caseSensitive: false),
        'Agent Awesome file',
      )
      .replaceAll(RegExp(r'\bfile evidence\b', caseSensitive: false), 'file')
      .replaceAll(
        RegExp(r'\bsource evidence\b', caseSensitive: false),
        'source content',
      )
      .replaceAll(
        RegExp(r'\braw evidence\b', caseSensitive: false),
        'source content',
      )
      .replaceAll(
        RegExp(r'\bevidence\b', caseSensitive: false),
        'source material',
      );
}

/// Reports whether any meaningful candidate appears in normalized text.
bool _anyMeaningfulTokenAppears(
  String normalizedText,
  Iterable<String> tokens,
) {
  for (final token in tokens) {
    final normalized = token.trim().toLowerCase();
    if (normalized.length >= 4 && normalizedText.contains(normalized)) {
      return true;
    }
  }
  return false;
}

/// Reports whether a memory record is a chat transcript row.
bool _chatContextRecordIsChatMessage(MemoryRecord record) {
  final kind = record.kind.toLowerCase();
  final title = record.title.toLowerCase();
  final source = '${record.sourceSystem} ${record.sourceId}'.toLowerCase();
  return kind == 'conversation' ||
      kind == 'chat' ||
      kind == 'chat_message' ||
      title.startsWith('chat message from ') ||
      source.contains('google_adk_session');
}

/// Reports whether a memory record represents a file context item.
bool _chatContextRecordIsFile(MemoryRecord record) {
  final mediaType = record.rawMediaType.toLowerCase();
  final path = record.rawPath.toLowerCase();
  final title = record.title.toLowerCase();
  final source = '${record.sourceSystem} ${record.sourceId}'.toLowerCase();
  final kind = record.kind.toLowerCase();
  return mediaType.startsWith('image/') ||
      mediaType.contains('pdf') ||
      mediaType.contains('spreadsheet') ||
      mediaType.contains('excel') ||
      mediaType.contains('word') ||
      mediaType.contains('presentation') ||
      mediaType.contains('csv') ||
      _chatTextHasKnownFileExtension(path) ||
      _chatTextHasKnownFileExtension(title) ||
      _chatTextHasKnownFileExtension(source) ||
      kind == 'file' ||
      kind == 'document' ||
      kind == 'source_file' ||
      kind == 'pdf' ||
      kind == 'spreadsheet' ||
      kind == 'image' ||
      source.contains('filesystem') ||
      source.contains('file_upload') ||
      source.contains('google_drive');
}

/// Reports whether text contains a known file extension.
bool _chatTextHasKnownFileExtension(String value) {
  return RegExp(
    r'\.(pdf|doc|docx|xls|xlsx|csv|ods|png|jpe?g|gif|webp|heic|ppt|pptx|zip|txt|md)\b',
  ).hasMatch(value);
}

/// Returns the last path segment from a path-like value.
String _lastPathSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final parts = trimmed
      .split(RegExp(r'[/\\]'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  return parts.isEmpty ? trimmed : parts.last.trim();
}

const List<String> _memoryKinds = <String>[
  'conversation',
  'document',
  'tool_output',
  'artifact',
  'summary',
  'entity_page',
  'timeline',
  'profile_fact',
];

const List<String> _memoryScopes = <String>[
  'session',
  'user',
  'household',
  'tenant',
  'project',
  'global',
];

const List<String> _memoryTrustLevels = <String>[
  'source_original',
  'user_asserted',
  'model_extracted',
  'model_synthesized',
  'externally_verified',
];

const List<String> _memorySensitivities = <String>[
  'public',
  'internal',
  'private',
  'restricted',
];

const List<String> _memoryStatuses = <String>[
  'active',
  'superseded',
  'deprecated',
  'archived',
];

const String _memoryOverviewDetailId = 'overview';
const String _memorySourceDetailId = 'source';
const String _memoryRelationsDetailId = 'relations';
const String _memoryMetadataDetailId = 'metadata';
const String _memoryCorrectionsDetailId = 'corrections';
const String _memoryPagesDetailId = 'pages';

/// Builds the memory discovery areas used by the command subshell.
List<SwitcherPanelArea> _memoryCommandAreas(
  AgentAwesomeAppController controller,
) {
  return <SwitcherPanelArea>[
    SwitcherPanelArea(
      title: 'Search',
      icon: Icons.manage_search,
      builder: (query) =>
          _MemorySearchContent(controller: controller, query: query),
    ),
    SwitcherPanelArea(
      title: 'Browse',
      icon: Icons.filter_alt_outlined,
      builder: (query) =>
          _MemoryBrowseContent(controller: controller, query: query),
    ),
    SwitcherPanelArea(
      title: 'Review',
      icon: Icons.rule_folder_outlined,
      builder: (query) =>
          _MemoryReviewContent(controller: controller, query: query),
    ),
    SwitcherPanelArea(
      title: 'Map',
      icon: Icons.account_tree_outlined,
      builder: (query) =>
          _MemoryMapContent(controller: controller, query: query),
    ),
    SwitcherPanelArea(
      title: 'Capture',
      icon: Icons.add_box_outlined,
      builder: (query) =>
          _MemoryCaptureContent(controller: controller, query: query),
    ),
  ];
}

/// Returns the selected-memory detail modes for the memory subshell.
List<CommandPanelDetailMode> _memoryDetailModes() {
  return const <CommandPanelDetailMode>[
    CommandPanelDetailMode(
      id: _memoryOverviewDetailId,
      label: 'Overview',
      icon: Icons.info_outline,
    ),
    CommandPanelDetailMode(
      id: _memorySourceDetailId,
      label: 'Source',
      icon: Icons.article_outlined,
    ),
    CommandPanelDetailMode(
      id: _memoryRelationsDetailId,
      label: 'Relations',
      icon: Icons.hub_outlined,
    ),
    CommandPanelDetailMode(
      id: _memoryMetadataDetailId,
      label: 'Metadata',
      icon: Icons.edit_note,
    ),
    CommandPanelDetailMode(
      id: _memoryCorrectionsDetailId,
      label: 'Corrections',
      icon: Icons.fact_check_outlined,
    ),
    CommandPanelDetailMode(
      id: _memoryPagesDetailId,
      label: 'Pages',
      icon: Icons.view_timeline_outlined,
    ),
  ];
}

/// _MemoryCommandSubShell renders memory in the official command subshell.
class _MemoryCommandSubShell extends StatefulWidget {
  const _MemoryCommandSubShell({required this.controller, this.onAreaChanged});

  final AgentAwesomeAppController controller;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  @override
  State<_MemoryCommandSubShell> createState() => _MemoryCommandSubShellState();
}

class _MemoryCommandSubShellState extends State<_MemoryCommandSubShell> {
  String _detailModeId = _memoryOverviewDetailId;

  /// Builds memory discovery and inspection inside the shared subshell.
  @override
  Widget build(BuildContext context) {
    return CommandPanelSubShell(
      areas: _memoryCommandAreas(widget.controller),
      detailTitle: 'Memory Inspector',
      detailModes: _memoryDetailModes(),
      selectedDetailModeId: _detailModeId,
      onDetailModeSelected: _selectDetailMode,
      detailBuilder: _buildDetailContent,
      onAreaChanged: widget.onAreaChanged,
      filterHint: 'Filter...',
      split: const PanelSplit(left: 0.58, min: 0.44, max: 0.82),
    );
  }

  /// Selects the right-side memory detail mode.
  void _selectDetailMode(String modeId) {
    setState(() => _detailModeId = modeId);
  }

  /// Builds one selected-memory detail mode.
  Widget _buildDetailContent(String modeId) {
    return switch (modeId) {
      _memorySourceDetailId => _MemorySourceContent(
        controller: widget.controller,
        query: '',
      ),
      _memoryRelationsDetailId => _MemoryRelationsContent(
        controller: widget.controller,
        query: '',
      ),
      _memoryMetadataDetailId => _MemoryMetadataContent(
        controller: widget.controller,
        query: '',
      ),
      _memoryCorrectionsDetailId => _MemoryCorrectionsContent(
        controller: widget.controller,
        query: '',
      ),
      _memoryPagesDetailId => _MemoryPagesContent(
        controller: widget.controller,
        query: '',
      ),
      _ => _MemoryOverviewContent(controller: widget.controller, query: ''),
    };
  }
}

class _MemorySearchContent extends StatelessWidget {
  const _MemorySearchContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds memory search results and retrieval filters.
  @override
  Widget build(BuildContext context) {
    final records = controller.filteredMemoryRecords.where((record) {
      return _matchesMemoryRecord(record, query);
    }).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MemoryFilterBar(controller: controller, query: query),
          const SizedBox(height: 14),
          _MemoryStatusStrip(controller: controller),
          if (controller.memoryBusy || _memoryMessageIsError(controller))
            const SizedBox(height: 14),
          if (records.isEmpty)
            PanelEmptyBlock(label: 'No memory records')
          else
            for (final record in records)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MemoryRecordTile(
                  record: record,
                  selected: controller.selectedMemory?.id == record.id,
                  onTap: () => unawaited(controller.selectMemory(record.id)),
                ),
              ),
        ],
      ),
    );
  }
}

class _MemoryFilterBar extends StatelessWidget {
  const _MemoryFilterBar({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds scope, sensitivity, and service-search controls.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final filters = controller.memoryFilters;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _MemoryDropdown(
                  value: filters.scope,
                  values: _memoryScopes,
                  tooltip: 'Scope',
                  onChanged: (value) {
                    unawaited(
                      controller.applyMemoryFilters(
                        filters.copyWith(scope: value),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Search service',
                child: IconButton.outlined(
                  onPressed: () {
                    unawaited(
                      controller.applyMemoryFilters(
                        filters.copyWith(text: query.trim()),
                      ),
                    );
                  },
                  icon: const Icon(Icons.travel_explore),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Refresh',
                child: IconButton.outlined(
                  onPressed: () =>
                      unawaited(controller.applyMemoryFilters(filters)),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final sensitivity in _memorySensitivities)
                Builder(
                  builder: (context) {
                    final selected = filters.allowedSensitivities.contains(
                      sensitivity,
                    );
                    return FilterChip(
                      label: Text(_memoryLabel(sensitivity)),
                      selected: selected,
                      showCheckmark: true,
                      backgroundColor: colors.surface,
                      selectedColor: colors.panelStrong,
                      checkmarkColor: colors.green,
                      side: BorderSide(
                        color: selected ? colors.borderStrong : colors.border,
                      ),
                      labelStyle: TextStyle(
                        color: selected ? colors.ink : colors.muted,
                        fontWeight: FontWeight.w800,
                      ),
                      onSelected: (_) {
                        unawaited(
                          controller.applyMemoryFilters(
                            filters.copyWith(
                              allowedSensitivities: toggleStringValue(
                                filters.allowedSensitivities,
                                sensitivity,
                                allowEmpty: false,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
          if (filters.text.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            _MemoryActiveFilter(
              label: 'Search: ${filters.text}',
              onClear: () {
                unawaited(
                  controller.applyMemoryFilters(filters.copyWith(text: '')),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _MemoryStatusStrip extends StatelessWidget {
  const _MemoryStatusStrip({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds a compact memory operation status strip.
  @override
  Widget build(BuildContext context) {
    if (controller.memoryBusy) {
      return const _RouteNoticePanel(
        icon: Icons.sync,
        title: 'Loading memory',
        message: 'Agent Awesome is reading memory, people, and timeline data.',
      );
    }
    if (!_memoryMessageIsError(controller)) {
      return const SizedBox.shrink();
    }
    return _RouteNoticePanel(
      icon: Icons.error_outline,
      title: 'Memory service unavailable',
      message: controller.memoryMessage,
      action: OutlinedButton.icon(
        onPressed: () => unawaited(controller.refreshMemoryFromUi()),
        icon: const Icon(Icons.refresh),
        label: const Text('Try again'),
      ),
    );
  }
}

class _RouteNoticePanel extends StatelessWidget {
  const _RouteNoticePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  /// Builds a prominent route-level status or error panel.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: colors.greenSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: colors.green),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  message,
                  style: TextStyle(color: colors.muted, height: 1.4),
                ),
                if (action != null) ...<Widget>[
                  const SizedBox(height: 14),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryUnavailableRoute extends StatelessWidget {
  const _MemoryUnavailableRoute({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds the full-page error state for memory-backed routes.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Memory service unavailable',
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 28),
          _RouteNoticePanel(
            icon: Icons.error_outline,
            title: 'Connection failed',
            message: controller.memoryMessage,
            action: OutlinedButton.icon(
              onPressed: () => unawaited(controller.refreshMemoryFromUi()),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryRecordTile extends StatelessWidget {
  const _MemoryRecordTile({
    required this.record,
    required this.selected,
    required this.onTap,
  });

  final MemoryRecord record;
  final bool selected;
  final VoidCallback onTap;

  /// Builds one selectable memory search result.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accentColor = _memoryRecordAccentColor(context, record);
    final borderColor = selected ? colors.borderStrong : colors.border;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          gradient: context.agentAwesomeCardGradient,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(width: 4, color: accentColor),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _MemoryKindBadge(record: record),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  record.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.ink,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                if (record.summary.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 8),
                                  Text(
                                    record.summary,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: colors.muted),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: <Widget>[
                                    _MemoryBadge(label: record.scope),
                                    _MemoryBadge(label: record.sensitivity),
                                    _MemoryBadge(
                                      label: _memoryLabel(record.trustLevel),
                                    ),
                                    if (record.status != 'active')
                                      _MemoryBadge(label: record.status),
                                    for (final topic in record.topics.take(3))
                                      _MemoryBadge(label: topic),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: colors.border),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.link_outlined,
                            size: 15,
                            color: colors.muted,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              record.sourceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryKindBadge extends StatelessWidget {
  const _MemoryKindBadge({required this.record});

  final MemoryRecord record;

  /// Builds the compact record-kind badge for memory cards.
  @override
  Widget build(BuildContext context) {
    final accent = _memoryRecordAccentColor(context, record);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_memoryRecordIcon(record), size: 16, color: accent),
          const SizedBox(width: 5),
          Text(
            _memoryLabel(record.kind),
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Returns the accent color used by a memory card.
Color _memoryRecordAccentColor(BuildContext context, MemoryRecord record) {
  final colors = context.agentAwesomeColors;
  if (record.status != 'active') {
    return colors.coral;
  }
  if (record.sensitivity == 'restricted') {
    return colors.coral;
  }
  if (record.sensitivity == 'private') {
    return context.agentAwesomeWarningAccent;
  }
  if (record.trustLevel == 'low') {
    return context.agentAwesomeWarningAccent;
  }
  return context.agentAwesomeLowAccent;
}

/// Returns the icon that represents one memory record kind.
IconData _memoryRecordIcon(MemoryRecord record) {
  if (record.kind == 'profile_fact') {
    return Icons.person_outline;
  }
  if (record.kind == 'source_original') {
    return Icons.article_outlined;
  }
  if (record.kind == 'relationship') {
    return Icons.hub_outlined;
  }
  if (record.kind == 'task') {
    return Icons.task_alt_outlined;
  }
  return Icons.chat_bubble_outline;
}

class _MemoryBrowseContent extends StatelessWidget {
  const _MemoryBrowseContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds facet-based discovery paths into memory.
  @override
  Widget build(BuildContext context) {
    final records = controller.filteredMemoryRecords;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MemoryFacetGroup(
            title: 'Kinds',
            values: _counts(records.map((record) => record.kind)),
            query: query,
            onSelected: (value) =>
                _applySingleFacet(controller, kinds: <String>[value]),
          ),
          _MemoryFacetGroup(
            title: 'Topics',
            values: _counts(records.expand((record) => record.topics)),
            query: query,
            onSelected: (value) =>
                _applySingleFacet(controller, topics: <String>[value]),
          ),
          _MemoryFacetGroup(
            title: 'Entities',
            values: _counts(records.expand((record) => record.entityNames)),
            query: query,
            onSelected: (value) => _selectFirstEntity(controller, value),
          ),
          _MemoryFacetGroup(
            title: 'Sensitivity',
            values: _counts(records.map((record) => record.sensitivity)),
            query: query,
            onSelected: (value) => _applySingleFacet(
              controller,
              allowedSensitivities: <String>[value],
            ),
          ),
          _MemoryFacetGroup(
            title: 'Trust',
            values: _counts(records.map((record) => record.trustLevel)),
            query: query,
            onSelected: (value) {
              unawaited(
                controller.applyMemoryFilters(
                  controller.memoryFilters.copyWith(localTrustLevel: value),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MemoryReviewContent extends StatelessWidget {
  const _MemoryReviewContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds the cross-cutting memory review queue.
  @override
  Widget build(BuildContext context) {
    final records = controller.filteredMemoryRecords.where((record) {
      return _memoryReviewReasons(record).isNotEmpty &&
          _matchesMemoryRecord(record, query);
    }).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MemoryStatusStrip(controller: controller),
          const SizedBox(height: 14),
          if (records.isEmpty)
            const PanelEmptyBlock(label: 'No records need review')
          else
            for (final record in records)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PanelSectionBlock(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _MemoryRecordTile(
                        record: record,
                        selected: controller.selectedMemory?.id == record.id,
                        onTap: () =>
                            unawaited(controller.selectMemory(record.id)),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final reason in _memoryReviewReasons(record))
                            _MemoryBadge(label: reason),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _MemoryFacetGroup extends StatelessWidget {
  const _MemoryFacetGroup({
    required this.title,
    required this.values,
    required this.query,
    required this.onSelected,
  });

  final String title;
  final Map<String, int> values;
  final String query;
  final ValueChanged<String> onSelected;

  /// Builds one group of browse facets.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final entries = values.entries.where((entry) {
      return _matchesFuzzyQuery('${entry.key} $title', query);
    }).toList();
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MemoryPanelLabel(title),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final entry in entries)
                ActionChip(
                  avatar: CircleAvatar(
                    backgroundColor: colors.greenSoft,
                    child: Text(
                      '${entry.value}',
                      style: TextStyle(color: colors.green, fontSize: 11),
                    ),
                  ),
                  label: Text(_memoryLabel(entry.key)),
                  labelStyle: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: colors.surface,
                  side: BorderSide(color: colors.border),
                  onPressed: () => onSelected(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemoryMapContent extends StatelessWidget {
  const _MemoryMapContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds relationship and discovery-path context for the selected memory.
  @override
  Widget build(BuildContext context) {
    final memory = controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    final related = controller.workspace.memoryRecords
        .where((record) {
          return memory.relationships.any((rel) => rel.toId == record.id) ||
              record.relationships.any((rel) => rel.toId == memory.id);
        })
        .where((record) {
          return _matchesMemoryRecord(record, query);
        })
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Selected Memory'),
                const SizedBox(height: 10),
                Text(
                  memory.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _MemoryBadge(label: memory.sourceLabel),
                    _MemoryBadge(label: memory.scope),
                    _MemoryBadge(label: _memoryLabel(memory.kind)),
                    for (final topic in memory.topics)
                      _MemoryBadge(label: topic),
                    for (final entity in memory.entityNames)
                      _MemoryBadge(label: entity),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Relationships'),
                const SizedBox(height: 10),
                if (memory.relationships.isEmpty)
                  Text(
                    'No relationship edges',
                    style: TextStyle(color: context.agentAwesomeColors.muted),
                  )
                else
                  for (final relationship in memory.relationships)
                    _MemoryRelationshipLine(relationship: relationship),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Related Records'),
                const SizedBox(height: 10),
                if (related.isEmpty)
                  Text(
                    'No related records in the current result set',
                    style: TextStyle(color: context.agentAwesomeColors.muted),
                  )
                else
                  for (final record in related)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemoryRecordTile(
                        record: record,
                        selected: false,
                        onTap: () =>
                            unawaited(controller.selectMemory(record.id)),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryCaptureContent extends StatefulWidget {
  const _MemoryCaptureContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  @override
  State<_MemoryCaptureContent> createState() => _MemoryCaptureContentState();
}

class _MemoryCaptureContentState extends State<_MemoryCaptureContent> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  final TextEditingController _sourceSystem = TextEditingController(
    text: 'agent_awesome_ui',
  );
  final TextEditingController _sourceId = TextEditingController();
  final TextEditingController _subjects = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  final TextEditingController _entities = TextEditingController();
  String _kind = 'document';
  String _scope = 'user';
  String _trust = 'source_original';
  String _sensitivity = 'private';

  /// Initializes live duplicate hint refresh.
  @override
  void initState() {
    super.initState();
    _title.addListener(_refreshDuplicateHints);
    _content.addListener(_refreshDuplicateHints);
  }

  /// Cleans up capture form controllers.
  @override
  void dispose() {
    _title.removeListener(_refreshDuplicateHints);
    _content.removeListener(_refreshDuplicateHints);
    _title.dispose();
    _content.dispose();
    _sourceSystem.dispose();
    _sourceId.dispose();
    _subjects.dispose();
    _topics.dispose();
    _entities.dispose();
    super.dispose();
  }

  /// Builds the careful memory accession form.
  @override
  Widget build(BuildContext context) {
    final duplicates = widget.controller.filteredMemoryRecords
        .where((record) {
          final probe = '${_title.text} ${_content.text} ${widget.query}';
          return probe.trim().isNotEmpty && _matchesMemoryRecord(record, probe);
        })
        .take(4)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              children: <Widget>[
                _MemoryTextField(controller: _title, label: 'Title'),
                const SizedBox(height: 10),
                _MemoryTextField(
                  controller: _content,
                  label: 'Source content',
                  maxLines: 8,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _MemoryTextField(
                        controller: _sourceSystem,
                        label: 'Source system',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MemoryTextField(
                        controller: _sourceId,
                        label: 'Source id',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _MemoryDropdown(
                        value: _kind,
                        values: _memoryKinds,
                        tooltip: 'Kind',
                        onChanged: (value) => setState(() => _kind = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MemoryDropdown(
                        value: _scope,
                        values: _memoryScopes,
                        tooltip: 'Scope',
                        onChanged: (value) => setState(() => _scope = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _MemoryDropdown(
                        value: _trust,
                        values: _memoryTrustLevels,
                        tooltip: 'Trust',
                        onChanged: (value) => setState(() => _trust = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MemoryDropdown(
                        value: _sensitivity,
                        values: _memorySensitivities,
                        tooltip: 'Sensitivity',
                        onChanged: (value) =>
                            setState(() => _sensitivity = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _MemoryTextField(controller: _subjects, label: 'Subjects'),
                const SizedBox(height: 10),
                _MemoryTextField(controller: _topics, label: 'Topics'),
                const SizedBox(height: 10),
                _MemoryTextField(controller: _entities, label: 'Entities'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Nearby Records'),
                const SizedBox(height: 10),
                if (duplicates.isEmpty)
                  Text(
                    'No nearby records',
                    style: TextStyle(color: context.agentAwesomeColors.muted),
                  )
                else
                  for (final record in duplicates)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemoryRecordTile(
                        record: record,
                        selected: false,
                        onTap: () => unawaited(
                          widget.controller.selectMemory(record.id),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: widget.controller.memoryBusy ? null : _save,
            icon: const Icon(Icons.library_add_check_outlined),
            label: const Text('Save Reviewed Memory'),
          ),
        ],
      ),
    );
  }

  /// Confirms and saves the drafted source-backed memory.
  Future<void> _save() async {
    final draft = MemoryCaptureDraft(
      content: _content.text.trim(),
      title: _title.text.trim(),
      kind: _kind,
      scope: _scope,
      trustLevel: _trust,
      sensitivity: _sensitivity,
      sourceSystem: _sourceSystem.text.trim(),
      sourceId: _sourceId.text.trim(),
      subjects: splitCommaSeparatedValues(_subjects.text),
      topics: splitCommaSeparatedValues(_topics.text),
      entityNames: splitCommaSeparatedValues(_entities.text),
    );
    if (draft.content.isEmpty) {
      return;
    }
    final approved = await _confirmWrite(
      context,
      'Save "${draft.title.isEmpty ? 'Untitled memory' : draft.title}"?',
    );
    if (!approved || !mounted) {
      return;
    }
    await widget.controller.saveMemoryCandidateFromUi(draft);
    if (!mounted) {
      return;
    }
    _content.clear();
    _title.clear();
    _sourceId.clear();
  }

  /// Refreshes nearby-record hints while accession fields change.
  void _refreshDuplicateHints() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _MemoryOverviewContent extends StatelessWidget {
  const _MemoryOverviewContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds selected memory metadata and stewardship posture.
  @override
  Widget build(BuildContext context) {
    final memory = controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    if (!_matchesMemoryRecord(memory, query)) {
      return PanelEmptyState(query: query);
    }
    final contradictionCount = memory.relationships
        .where((relationship) => relationship.type == 'contradicts')
        .length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        memory.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    if (contradictionCount > 0)
                      _MemoryBadge(label: '$contradictionCount conflicts'),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  memory.summary,
                  style: TextStyle(color: context.agentAwesomeColors.muted),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _MemoryBadge(label: _memoryLabel(memory.kind)),
                    _MemoryBadge(label: memory.scope),
                    _MemoryBadge(label: memory.sensitivity),
                    _MemoryBadge(label: _memoryLabel(memory.trustLevel)),
                    _MemoryBadge(label: memory.status),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Memory'),
                const SizedBox(height: 10),
                _MemoryMetadataRow(label: 'Memory id', value: memory.id),
                _MemoryMetadataRow(
                  label: 'Source record id',
                  value: memory.evidenceId,
                ),
                _MemoryMetadataRow(label: 'Source', value: memory.sourceLabel),
                _MemoryMetadataRow(
                  label: 'Created',
                  value: formatOptionalLocalDateTime(memory.createdAt),
                ),
                _MemoryMetadataRow(
                  label: 'Updated',
                  value: formatOptionalLocalDateTime(memory.updatedAt),
                ),
                _MemoryMetadataRow(
                  label: 'Event',
                  value: formatOptionalLocalDateTime(memory.eventTime),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Access Paths'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final subject in memory.subjects)
                      _MemoryBadge(label: subject),
                    for (final topic in memory.topics)
                      _MemoryBadge(label: topic),
                    for (final entity in memory.entityNames)
                      _MemoryBadge(label: entity),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemorySourceContent extends StatelessWidget {
  const _MemorySourceContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds immutable raw source preview for the selected memory.
  @override
  Widget build(BuildContext context) {
    final memory = controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    if (!_matchesFuzzyQuery(
      '${memory.rawContent} ${memory.rawPath} ${memory.rawChecksum}',
      query,
    )) {
      return PanelEmptyState(query: query);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Source'),
                const SizedBox(height: 10),
                _MemoryMetadataRow(
                  label: 'Source record id',
                  value: memory.evidenceId,
                ),
                _MemoryMetadataRow(label: 'Path', value: memory.rawPath),
                _MemoryMetadataRow(
                  label: 'Checksum',
                  value: memory.rawChecksum,
                ),
                _MemoryMetadataRow(
                  label: 'Media type',
                  value: memory.rawMediaType,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: controller.memoryBusy
                      ? null
                      : () =>
                            unawaited(controller.hydrateSelectedMemorySource()),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Load Source'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(minHeight: 260),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.agentAwesomeColors.surface,
              gradient: context.agentAwesomeCardGradient,
              border: Border.all(color: context.agentAwesomeColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              memory.rawContent.isEmpty
                  ? 'Source not loaded'
                  : memory.rawContent,
              style: TextStyle(
                color: context.agentAwesomeColors.ink,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryRelationsContent extends StatelessWidget {
  const _MemoryRelationsContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds relationship review for the selected memory.
  @override
  Widget build(BuildContext context) {
    final memory = controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    final relationships = memory.relationships.where((relationship) {
      return _matchesFuzzyQuery(
        '${relationship.type} ${relationship.toId} ${relationship.sourceId}',
        query,
      );
    }).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Outgoing Edges'),
                const SizedBox(height: 10),
                if (relationships.isEmpty)
                  Text(
                    'No matching relationship edges',
                    style: TextStyle(color: context.agentAwesomeColors.muted),
                  )
                else
                  for (final relationship in relationships)
                    _MemoryRelationshipLine(relationship: relationship),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Incoming Edges'),
                const SizedBox(height: 10),
                for (final record in controller.workspace.memoryRecords)
                  for (final relationship in record.relationships.where(
                    (rel) => rel.toId == memory.id,
                  ))
                    _MemoryRelationshipLine(relationship: relationship),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryMetadataContent extends StatefulWidget {
  const _MemoryMetadataContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  @override
  State<_MemoryMetadataContent> createState() => _MemoryMetadataContentState();
}

class _MemoryMetadataContentState extends State<_MemoryMetadataContent> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _summary = TextEditingController();
  final TextEditingController _subjects = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  final TextEditingController _entities = TextEditingController();
  String _recordId = '';
  String _kind = 'document';
  String _sensitivity = 'private';
  String _status = 'active';

  /// Initializes form state.
  @override
  void initState() {
    super.initState();
    _syncFromSelected();
  }

  /// Keeps form state aligned when the selected memory changes.
  @override
  void didUpdateWidget(covariant _MemoryMetadataContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.selectedMemory?.id !=
        widget.controller.selectedMemory?.id) {
      _syncFromSelected();
    }
  }

  /// Cleans up metadata editing form controllers.
  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _subjects.dispose();
    _topics.dispose();
    _entities.dispose();
    super.dispose();
  }

  /// Builds explicit metadata repair controls.
  @override
  Widget build(BuildContext context) {
    final memory = widget.controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    if (!_matchesMemoryRecord(memory, widget.query)) {
      return PanelEmptyState(query: widget.query);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              children: <Widget>[
                _MemoryTextField(controller: _title, label: 'Title'),
                const SizedBox(height: 10),
                _MemoryTextField(
                  controller: _summary,
                  label: 'Summary',
                  maxLines: 4,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _MemoryDropdown(
                        value: _kind,
                        values: _memoryKinds,
                        tooltip: 'Kind',
                        onChanged: (value) => setState(() => _kind = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MemoryDropdown(
                        value: _sensitivity,
                        values: _memorySensitivities,
                        tooltip: 'Sensitivity',
                        onChanged: (value) =>
                            setState(() => _sensitivity = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _MemoryDropdown(
                  value: _status,
                  values: _memoryStatuses,
                  tooltip: 'Status',
                  onChanged: (value) => setState(() => _status = value),
                ),
                const SizedBox(height: 10),
                _MemoryTextField(controller: _subjects, label: 'Subjects'),
                const SizedBox(height: 10),
                _MemoryTextField(controller: _topics, label: 'Topics'),
                const SizedBox(height: 10),
                _MemoryTextField(controller: _entities, label: 'Entities'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: widget.controller.memoryBusy ? null : _repair,
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('Repair Memory Metadata'),
          ),
        ],
      ),
    );
  }

  /// Copies selected memory metadata into the repair form.
  void _syncFromSelected() {
    final memory = widget.controller.selectedMemory;
    if (memory == null || memory.id == _recordId) {
      return;
    }
    _recordId = memory.id;
    _title.text = memory.title;
    _summary.text = memory.summary;
    _subjects.text = memory.subjects.join(', ');
    _topics.text = memory.topics.join(', ');
    _entities.text = memory.entityNames.join(', ');
    _kind = _coerceDropdownValue(_memoryKinds, memory.kind, 'document');
    _sensitivity = _coerceDropdownValue(
      _memorySensitivities,
      memory.sensitivity,
      'private',
    );
    _status = _coerceDropdownValue(_memoryStatuses, memory.status, 'active');
  }

  /// Confirms and submits memory metadata repairs.
  Future<void> _repair() async {
    final memory = widget.controller.selectedMemory;
    if (memory == null) {
      return;
    }
    final approved = await _confirmWrite(
      context,
      'Repair memory metadata for "${memory.title}"?',
    );
    if (!approved || !mounted) {
      return;
    }
    await widget.controller.repairMemoryFromUi(
      MemoryRepairDraft(
        memoryId: memory.id,
        title: _title.text.trim(),
        summary: _summary.text.trim(),
        kind: _kind,
        sensitivity: _sensitivity,
        status: _status,
        subjects: splitCommaSeparatedValues(_subjects.text),
        topics: splitCommaSeparatedValues(_topics.text),
        entityNames: splitCommaSeparatedValues(_entities.text),
      ),
    );
  }
}

class _MemoryCorrectionsContent extends StatefulWidget {
  const _MemoryCorrectionsContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  @override
  State<_MemoryCorrectionsContent> createState() =>
      _MemoryCorrectionsContentState();
}

class _MemoryCorrectionsContentState extends State<_MemoryCorrectionsContent> {
  final TextEditingController _correction = TextEditingController();

  /// Cleans up correction form state.
  @override
  void dispose() {
    _correction.dispose();
    super.dispose();
  }

  /// Builds correction capture controls.
  @override
  Widget build(BuildContext context) {
    final memory = widget.controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    if (!_matchesMemoryRecord(memory, widget.query)) {
      return PanelEmptyState(query: widget.query);
    }
    final corrections = widget.controller.workspace.memoryRecords.where((
      record,
    ) {
      return record.sourceSystem == 'memory_correction' &&
          record.sourceId == memory.id;
    }).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('New Correction'),
                const SizedBox(height: 10),
                _MemoryTextField(
                  controller: _correction,
                  label: 'Correction text',
                  maxLines: 6,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: widget.controller.memoryBusy ? null : _submit,
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('Submit Correction'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Existing Corrections'),
                const SizedBox(height: 10),
                if (corrections.isEmpty)
                  Text(
                    'No corrections in current results',
                    style: TextStyle(color: context.agentAwesomeColors.muted),
                  )
                else
                  for (final correction in corrections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemoryRecordTile(
                        record: correction,
                        selected: false,
                        onTap: () => unawaited(
                          widget.controller.selectMemory(correction.id),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Confirms and submits a source-backed correction.
  Future<void> _submit() async {
    final memory = widget.controller.selectedMemory;
    final text = _correction.text.trim();
    if (memory == null || text.isEmpty) {
      return;
    }
    final approved = await _confirmWrite(
      context,
      'Submit correction for "${memory.title}"?',
    );
    if (!approved || !mounted) {
      return;
    }
    await widget.controller.submitMemoryCorrectionFromUi(text);
    if (mounted) {
      _correction.clear();
    }
  }
}

class _MemoryPagesContent extends StatelessWidget {
  const _MemoryPagesContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds entity page and timeline controls for the selected memory.
  @override
  Widget build(BuildContext context) {
    final memory = controller.selectedMemory;
    final page = controller.selectedMemoryPage;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    if (!_matchesMemoryRecord(memory, query) &&
        !_matchesFuzzyQuery(
          '${page?.title ?? ''} ${page?.content ?? ''}',
          query,
        )) {
      return PanelEmptyState(query: query);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: controller.memoryBusy
                      ? null
                      : () =>
                            unawaited(controller.loadEntityPageFromUi(memory)),
                  icon: const Icon(Icons.person_search_outlined),
                  label: const Text('Entity Page'),
                ),
                for (final topic in memory.topics.take(3))
                  OutlinedButton.icon(
                    onPressed: controller.memoryBusy
                        ? null
                        : () => unawaited(controller.loadTimelineFromUi(topic)),
                    icon: const Icon(Icons.timeline_outlined),
                    label: Text(topic),
                  ),
                if (page != null)
                  OutlinedButton.icon(
                    onPressed: controller.memoryBusy
                        ? null
                        : () => unawaited(
                            controller.refreshSelectedMemoryPageFromUi(),
                          ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Page'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (page == null)
            const PanelEmptyBlock(label: 'No compiled page loaded')
          else
            PanelSectionBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    page.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _MemoryBadge(label: page.kind),
                      _MemoryBadge(label: page.scope),
                      _MemoryBadge(label: '${page.sourceIds.length} sources'),
                      if (page.stale) const _MemoryBadge(label: 'stale'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SelectableText(page.content),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MemoryPanelLabel extends StatelessWidget {
  const _MemoryPanelLabel(this.label);

  final String label;

  /// Builds an uppercase memory panel label.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Text(
      label.toUpperCase(),
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.subtle,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.4,
      ),
    );
  }
}

class _MemoryBadge extends StatelessWidget {
  const _MemoryBadge({required this.label});

  final String label;

  /// Builds a dense metadata badge.
  @override
  Widget build(BuildContext context) {
    return PanelBadge(label: _memoryLabel(label));
  }
}

class _MemoryActiveFilter extends StatelessWidget {
  const _MemoryActiveFilter({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  /// Builds a removable active filter chip.
  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label, overflow: TextOverflow.ellipsis),
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close, size: 16),
    );
  }
}

class _MemoryDropdown extends StatelessWidget {
  const _MemoryDropdown({
    required this.value,
    required this.values,
    required this.tooltip,
    required this.onChanged,
  });

  final String value;
  final List<String> values;
  final String tooltip;
  final ValueChanged<String> onChanged;

  /// Builds a compact dropdown for controlled memory vocabulary.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final dropdownValue = _coerceDropdownValue(values, value, values.first);
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          gradient: context.agentAwesomeControlGradient,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: dropdownValue,
            isDense: true,
            isExpanded: true,
            dropdownColor: colors.surface,
            icon: Icon(Icons.expand_more, size: 18, color: colors.muted),
            style: TextStyle(color: colors.ink),
            items: <DropdownMenuItem<String>>[
              for (final item in values)
                DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    _memoryLabel(item),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged(value);
              }
            },
          ),
        ),
      ),
    );
  }
}

class _MemoryTextField extends StatelessWidget {
  const _MemoryTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;

  /// Builds a compact text field for memory forms.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return TextField(
      controller: controller,
      minLines: maxLines == 1 ? 1 : 3,
      maxLines: maxLines,
      style: TextStyle(color: colors.ink),
      decoration: _memoryInputDecoration(context, label),
    );
  }
}

/// Builds the shared themed decoration for memory text fields.
InputDecoration _memoryInputDecoration(BuildContext context, String label) {
  final colors = context.agentAwesomeColors;
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: colors.muted),
    floatingLabelStyle: TextStyle(color: colors.green),
    filled: true,
    fillColor: colors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.searchBorder),
    ),
  );
}

class _MemoryMetadataRow extends StatelessWidget {
  const _MemoryMetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds one key/value metadata row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: colors.subtle,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '-' : value,
              style: TextStyle(color: colors.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryRelationshipLine extends StatelessWidget {
  const _MemoryRelationshipLine({required this.relationship});

  final MemoryRelationship relationship;

  /// Builds one relationship review row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final isConflict = relationship.type == 'contradicts';
    final accent = isConflict ? colors.coral : context.agentAwesomeLowAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isConflict ? colors.warningSoft : colors.surface,
        gradient: isConflict ? null : context.agentAwesomeCardGradient,
        border: Border.all(color: isConflict ? colors.coral : colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isConflict ? Icons.warning_amber : Icons.link,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _memoryLabel(relationship.type),
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _MemoryBadge(label: _memoryLabel(relationship.trustLevel)),
            ],
          ),
          const SizedBox(height: 8),
          _MemoryMetadataRow(label: 'From', value: relationship.fromId),
          _MemoryMetadataRow(label: 'To', value: relationship.toId),
          _MemoryMetadataRow(label: 'Source', value: relationship.sourceId),
        ],
      ),
    );
  }
}

class _MemorySelectionEmpty extends StatelessWidget {
  const _MemorySelectionEmpty();

  /// Builds the no-selection state for the stewardship panel.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Select a memory',
        style: TextStyle(color: context.agentAwesomeColors.muted),
      ),
    );
  }
}

/// Returns whether a memory record matches a command filter query.
bool _matchesMemoryRecord(MemoryRecord record, String query) {
  return _matchesFuzzyQuery(
    '${record.title} ${record.summary} ${record.kind} ${record.scope} '
    '${record.trustLevel} ${record.sensitivity} ${record.status} '
    '${record.sourceLabel} ${record.subjects.join(' ')} '
    '${record.topics.join(' ')} ${record.entityNames.join(' ')}',
    query,
  );
}

/// Reports whether the memory route status is an actionable error.
bool _memoryMessageIsError(AgentAwesomeAppController controller) {
  final message = controller.memoryMessage.trim().toLowerCase();
  if (message.isEmpty) {
    return false;
  }
  if (message.startsWith('no memory records') ||
      message.startsWith('loaded ') ||
      message == 'source content loaded' ||
      message.startsWith('searching memory')) {
    return false;
  }
  return message.contains('exception') ||
      message.contains('http 4') ||
      message.contains('http 5') ||
      message.contains('failed') ||
      message.contains('unauthorized') ||
      message.contains('not loaded');
}

/// Returns cross-cutting stewardship reasons for a record.
List<String> _memoryReviewReasons(MemoryRecord record) {
  final reasons = <String>[];
  if (record.sensitivity == 'restricted') {
    reasons.add('restricted');
  }
  if (record.status != 'active') {
    reasons.add(record.status);
  }
  if (record.trustLevel == 'model_extracted' ||
      record.trustLevel == 'model_synthesized') {
    reasons.add(record.trustLevel);
  }
  if (record.topics.isEmpty) {
    reasons.add('missing topics');
  }
  if (record.entityIds.isEmpty && record.entityNames.isEmpty) {
    reasons.add('missing entities');
  }
  if (record.relationships.any((rel) => rel.type == 'contradicts')) {
    reasons.add('contradiction');
  }
  return reasons;
}

/// Counts non-empty facet values.
Map<String, int> _counts(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    if (value.trim().isEmpty) {
      continue;
    }
    counts[value] = (counts[value] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final countCompare = b.value.compareTo(a.value);
      return countCompare == 0 ? a.key.compareTo(b.key) : countCompare;
    });
  return Map<String, int>.fromEntries(entries);
}

/// Applies one server-supported memory facet.
void _applySingleFacet(
  AgentAwesomeAppController controller, {
  List<String>? kinds,
  List<String>? topics,
  List<String>? allowedSensitivities,
}) {
  unawaited(
    controller.applyMemoryFilters(
      controller.memoryFilters.copyWith(
        kinds: kinds ?? const <String>[],
        topics: topics ?? const <String>[],
        allowedSensitivities:
            allowedSensitivities ??
            controller.memoryFilters.allowedSensitivities,
      ),
    ),
  );
}

/// Selects the first record with the requested entity label.
void _selectFirstEntity(AgentAwesomeAppController controller, String entity) {
  final matches = controller.workspace.memoryRecords.where((record) {
    return record.entityNames.contains(entity);
  });
  if (matches.isNotEmpty) {
    unawaited(controller.selectMemory(matches.first.id));
  }
}

/// Coerces a dropdown value to a valid controlled value.
String _coerceDropdownValue(
  List<String> values,
  String value,
  String defaultValue,
) {
  return values.contains(value) ? value : defaultValue;
}

/// Converts controlled vocabulary to readable labels.
String _memoryLabel(String value) {
  if (value.isEmpty) {
    return '';
  }
  return value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

Future<bool> _confirmWrite(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Confirm Write'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
