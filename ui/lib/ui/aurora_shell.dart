/// Implements the Aurora assistant workspace shell and feature surfaces.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/theme.dart';
import '../domain/models.dart';
import 'command_bar/command_context.dart';
import 'command_bar/command_router.dart';
import 'backlog_section.dart';
import 'panels/panels.dart';
import 'settings/settings_panel.dart';
import 'shell/app_sections.dart';
import 'shell/app_shell_frame.dart';
import 'workspace/workspace_widgets.dart';

/// AuroraShell renders the desktop assistant workspace.
class AuroraShell extends StatefulWidget {
  /// Creates the shell bound to an app controller.
  const AuroraShell({super.key, required this.controller});

  /// Shared app controller.
  final AuroraAppController controller;

  @override
  State<AuroraShell> createState() => _AuroraShellState();
}

class _AuroraShellState extends State<AuroraShell> {
  final TextEditingController _commandController = TextEditingController();
  String _section = AppSections.today;
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
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          body: ColoredBox(
            color: AuroraColors.surface,
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
              content: _buildContent(context),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    final panelLayout = _buildPanelLayout();
    if (panelLayout != null) {
      return SplitPanelShell(
        split: panelLayout.split,
        left: panelLayout.left,
        right: panelLayout.right,
      );
    }
    switch (_section) {
      case AppSections.files:
        return _SourcesPage(workspace: widget.controller.workspace);
      case 'Calendar':
        return _MemoryTimelineRoute(controller: widget.controller);
      case AppSections.timeline:
        return _MemoryTimelineRoute(controller: widget.controller);
      case AppSections.people:
        return _MemoryPeopleRoute(controller: widget.controller);
      default:
        return HomeWorkspace(controller: widget.controller);
    }
  }

  /// Builds the reusable two-panel layout for sections that use command panels.
  SectionLayout? _buildPanelLayout() {
    switch (_section) {
      case AppSections.chat:
        return SectionLayout(
          split: const PanelSplit(left: 0.62),
          left: _ChatCommandPanel(controller: widget.controller),
          right: _ChatUtilitiesPanel(
            controller: widget.controller,
            onAreaChanged: _rememberArea('Chat'),
          ),
        );
      case AppSections.workflows:
        return SectionLayout(
          split: const PanelSplit(left: 0.5),
          left: _WorkflowCommandPanel(
            controller: widget.controller,
            onBackHome: () => _selectSection(AppSections.today),
            onAreaChanged: _rememberArea('Workflows'),
          ),
          right: _MemoryCommandPanel(
            controller: widget.controller,
            onAreaChanged: _rememberArea('Memory'),
          ),
        );
      case AppSections.memory:
        return SectionLayout(
          split: const PanelSplit(left: 0.5),
          left: _MemoryLibraryPanel(
            controller: widget.controller,
            onAreaChanged: _rememberArea('Memory'),
          ),
          right: _MemoryStewardshipPanel(
            controller: widget.controller,
            onAreaChanged: _rememberArea('Memory'),
          ),
        );
      case AppSections.backlog:
        return SectionLayout(
          split: const PanelSplit(left: 0.68, min: 0.42, max: 0.82),
          left: BacklogQueuePanel(
            controller: widget.controller,
            onAreaChanged: _rememberArea(AppSections.backlog),
          ),
          right: BacklogInspectorPanel(
            controller: widget.controller,
            onAreaChanged: _rememberArea('Backlog Inspector'),
          ),
        );
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
    });
    if (section == AppSections.chat) {
      widget.controller.openHome();
    } else if (section == AppSections.workflows) {
      widget.controller.openWorkspace();
    } else if (section == AppSections.today) {
      widget.controller.openHome();
    }
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
      area: _activeAreas[_section] ?? '',
      text: text,
      selectedTaskId: widget.controller.selectedGraphTaskId,
      selectedMemoryId: widget.controller.selectedMemory?.id ?? '',
      profilePath: profilePath,
    );
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
      case CommandRouteKind.assistant:
        await widget.controller.sendUserMessage(route.assistantText);
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

/// Formats a chat timestamp for dense chat utility rows.
String _chatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}

class _ChatCommandPanel extends StatefulWidget {
  const _ChatCommandPanel({required this.controller});

  final AuroraAppController controller;

  @override
  State<_ChatCommandPanel> createState() => _ChatCommandPanelState();
}

class _ChatCommandPanelState extends State<_ChatCommandPanel> {
  final TextEditingController _replyController = TextEditingController();

  /// Cleans up the persistent chat composer.
  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

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
          builder: _buildConversationContent,
        ),
      ],
    );
  }

  Widget _buildConversationContent(String query) {
    final messages = widget.controller.messages.where((message) {
      return _matchesFuzzyQuery('${message.author} ${message.text}', query);
    }).toList();
    final timelineChildren = <Widget>[
      for (final message in messages) ChatRow(message: message),
      if (widget.controller.sending)
        const _ChatRuntimeNotice(
          icon: Icons.sync,
          label: 'Aurora is responding',
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
        const Divider(height: 1, color: AuroraColors.border),
        _ChatComposer(
          controller: _replyController,
          sending: widget.controller.sending,
          onSubmit: _submitReply,
        ),
      ],
    );
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

  final AuroraAppController controller;

  /// Builds the active chat selector for the conversation panel.
  @override
  Widget build(BuildContext context) {
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
                foregroundColor: AuroraColors.muted,
                side: const BorderSide(color: AuroraColors.border),
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
                '${chat.profileLabel} • ${_chatTimestamp(chat.updatedAt)}',
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
          subtitle: _chatTimestamp(session.updatedAt),
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
    return ColoredBox(
      color: const Color(0xfffffcf8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AuroraColors.surface,
            border: Border.all(color: AuroraColors.border),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0d453421),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Icon(
                  Icons.chat_bubble_outline,
                  color: AuroraColors.muted,
                ),
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
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Message Aurora in this chat...',
                    hintStyle: TextStyle(color: AuroraColors.muted),
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
                    backgroundColor: AuroraColors.green,
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

class _ChatUtilitiesPanel extends StatelessWidget {
  const _ChatUtilitiesPanel({required this.controller, this.onAreaChanged});

  final AuroraAppController controller;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds live chat utilities for context, chats, and runtime state.
  @override
  Widget build(BuildContext context) {
    return SwitcherPanel(
      onAreaChanged: onAreaChanged,
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          title: 'Context',
          icon: Icons.account_tree_outlined,
          builder: _buildContextContent,
        ),
        SwitcherPanelArea(
          title: 'Runtime',
          icon: Icons.bolt_outlined,
          builder: _buildRuntimeContent,
        ),
      ],
    );
  }

  /// Builds memory and context items for the selected chat.
  Widget _buildContextContent(String query) {
    final memories = controller.workspace.memoryRecords.where((record) {
      return _matchesFuzzyQuery(
        '${record.title} ${record.summary} ${record.topics.join(' ')}',
        query,
      );
    }).toList();
    final tasks = controller.selectedChatTasks.where((task) {
      return _matchesFuzzyQuery('${task.title} ${task.detail}', query);
    }).toList();
    if (memories.isEmpty && tasks.isEmpty) {
      return PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (memories.isNotEmpty) ...<Widget>[
          const _MemoryPanelLabel('Memory in scope'),
          const SizedBox(height: 10),
          for (final record in memories.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ChatMemoryContextTile(record: record),
            ),
        ],
        if (tasks.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          const _MemoryPanelLabel('Associated context'),
          const SizedBox(height: 10),
          for (final task in tasks.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ChatTaskContextTile(task: task),
            ),
        ],
      ],
    );
  }

  /// Builds runtime status and pending tool approval utilities.
  Widget _buildRuntimeContent(String query) {
    final endpointStatuses = controller.endpointStatuses.where((status) {
      return _matchesFuzzyQuery(
        '${status.name} ${status.url} ${status.message}',
        query,
      );
    }).toList();
    final localStatuses = controller.localProcessStatuses.where((status) {
      return _matchesFuzzyQuery(
        '${status.name} ${status.url} ${status.message}',
        query,
      );
    }).toList();
    if (endpointStatuses.isEmpty &&
        localStatuses.isEmpty &&
        controller.pendingConfirmation == null) {
      return PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (controller.pendingConfirmation != null)
          _ChatConfirmationUtility(
            confirmation: controller.pendingConfirmation!,
            onAnswer: (option) =>
                unawaited(controller.answerConfirmation(option)),
          ),
        if (localStatuses.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          const _MemoryPanelLabel('Local processes'),
          const SizedBox(height: 10),
          for (final status in localStatuses)
            _ChatStatusTile(
              name: status.name,
              detail: status.url,
              state: status.state,
              message: status.message,
            ),
        ],
        if (endpointStatuses.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          const _MemoryPanelLabel('Service endpoints'),
          const SizedBox(height: 10),
          for (final status in endpointStatuses)
            _ChatStatusTile(
              name: status.name,
              detail: status.url,
              state: status.state,
              message: status.message,
            ),
        ],
      ],
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
    return PanelSectionBlock(
      child: Row(
        children: <Widget>[
          Icon(icon, color: AuroraColors.green),
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
              record.summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AuroraColors.muted),
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

class _ChatStatusTile extends StatelessWidget {
  const _ChatStatusTile({
    required this.name,
    required this.detail,
    required this.state,
    required this.message,
  });

  final String name;
  final String detail;
  final ConnectionStateKind state;
  final String message;

  /// Builds one runtime status tile for chat utilities.
  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      ConnectionStateKind.connected => AuroraColors.green,
      ConnectionStateKind.disconnected => AuroraColors.coral,
      ConnectionStateKind.unknown => AuroraColors.muted,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PanelSectionBlock(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.circle, size: 12, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AuroraColors.muted),
                  ),
                  if (message.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(message, overflow: TextOverflow.ellipsis),
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

class _WorkflowCommandPanel extends StatelessWidget {
  const _WorkflowCommandPanel({
    required this.controller,
    required this.onBackHome,
    this.onAreaChanged,
  });

  final AuroraAppController controller;
  final VoidCallback onBackHome;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the workflow command panel with switchable dense content areas.
  @override
  Widget build(BuildContext context) {
    return SwitcherPanel(
      onAreaChanged: onAreaChanged,
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          title: controller.workspace.title,
          icon: Icons.auto_awesome,
          builder: (query) => _buildOverviewContent(context, query),
        ),
        SwitcherPanelArea(
          title: 'Research Plan',
          icon: Icons.checklist,
          builder: _buildPlanContent,
        ),
      ],
    );
  }

  Widget _buildOverviewContent(BuildContext context, String query) {
    final filteredMessages = controller.messages.where((message) {
      return _matchesFuzzyQuery('${message.author} ${message.text}', query);
    }).toList();
    final hasResults = filteredMessages.isNotEmpty;
    if (!hasResults) {
      return PanelEmptyState(query: query);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: TextButton.icon(
                  onPressed: onBackHome,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text(
                    'Back to Home',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            controller.workspace.title,
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 10),
          Text(
            controller.workspace.subtitle,
            style: const TextStyle(color: AuroraColors.muted, fontSize: 17),
          ),
          for (final message in filteredMessages) ChatRow(message: message),
        ],
      ),
    );
  }

  Widget _buildPlanContent(String query) {
    final filteredTasks = controller.workspace.tasks.where((task) {
      return _matchesFuzzyQuery('${task.title} ${task.detail}', query);
    }).toList();
    if (filteredTasks.isEmpty) {
      return PanelEmptyState(query: query);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      child: _ResearchPlanCard(controller: controller, tasks: filteredTasks),
    );
  }
}

class _ResearchPlanCard extends StatelessWidget {
  const _ResearchPlanCard({required this.controller, this.tasks});

  final AuroraAppController controller;
  final List<WorkspaceTask>? tasks;

  /// Builds the workspace context card with confirmable actions.
  @override
  Widget build(BuildContext context) {
    final visibleTasks = tasks ?? controller.workspace.tasks;
    final done = visibleTasks.where((task) => task.done).length;
    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xfffffcf8),
        border: Border.all(color: AuroraColors.border),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Research Plan',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              Flexible(
                child: Text(
                  'In progress - $done/${visibleTasks.length}',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: AuroraColors.muted),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.outlined(
                tooltip: 'Add context',
                onPressed: () => _confirmCreateTask(context, controller),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final task in visibleTasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TaskLine(
                task: task,
                onComplete: task.done
                    ? null
                    : () => _confirmCompleteTask(context, controller, task),
              ),
            ),
        ],
      ),
    );
  }
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

class _MemoryLibraryPanel extends StatelessWidget {
  const _MemoryLibraryPanel({required this.controller, this.onAreaChanged});

  final AuroraAppController controller;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the memory discovery command panel.
  @override
  Widget build(BuildContext context) {
    return SwitcherPanel(
      onAreaChanged: onAreaChanged,
      areas: <SwitcherPanelArea>[
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
      ],
    );
  }
}

class _MemorySearchContent extends StatelessWidget {
  const _MemorySearchContent({required this.controller, required this.query});

  final AuroraAppController controller;
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

  final AuroraAppController controller;
  final String query;

  /// Builds scope, sensitivity, and service-search controls.
  @override
  Widget build(BuildContext context) {
    final filters = controller.memoryFilters;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AuroraColors.surface,
        border: Border.all(color: AuroraColors.border),
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
                FilterChip(
                  label: Text(_memoryLabel(sensitivity)),
                  selected: filters.allowedSensitivities.contains(sensitivity),
                  onSelected: (_) {
                    unawaited(
                      controller.applyMemoryFilters(
                        filters.copyWith(
                          allowedSensitivities: _toggleString(
                            filters.allowedSensitivities,
                            sensitivity,
                          ),
                        ),
                      ),
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

  final AuroraAppController controller;

  /// Builds a compact memory operation status strip.
  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (controller.memoryBusy)
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          const Icon(Icons.circle, size: 10, color: AuroraColors.green),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            controller.memoryMessage,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AuroraColors.muted, fontSize: 12),
          ),
        ),
      ],
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
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AuroraColors.greenSoft : AuroraColors.surface,
          border: Border.all(
            color: selected ? AuroraColors.green : AuroraColors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    record.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _MemoryBadge(label: _memoryLabel(record.kind)),
              ],
            ),
            if (record.summary.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                record.summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AuroraColors.muted),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                _MemoryBadge(label: record.scope),
                _MemoryBadge(label: record.sensitivity),
                _MemoryBadge(label: _memoryLabel(record.trustLevel)),
                if (record.status != 'active')
                  _MemoryBadge(label: record.status),
                for (final topic in record.topics.take(3))
                  _MemoryBadge(label: topic),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              record.sourceLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AuroraColors.green),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryBrowseContent extends StatelessWidget {
  const _MemoryBrowseContent({required this.controller, required this.query});

  final AuroraAppController controller;
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

  final AuroraAppController controller;
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
                    backgroundColor: AuroraColors.greenSoft,
                    child: Text(
                      '${entry.value}',
                      style: const TextStyle(
                        color: AuroraColors.green,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  label: Text(_memoryLabel(entry.key)),
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

  final AuroraAppController controller;
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
                  const Text(
                    'No relationship edges',
                    style: TextStyle(color: AuroraColors.muted),
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
                  const Text(
                    'No related records in the current result set',
                    style: TextStyle(color: AuroraColors.muted),
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

  final AuroraAppController controller;
  final String query;

  @override
  State<_MemoryCaptureContent> createState() => _MemoryCaptureContentState();
}

class _MemoryCaptureContentState extends State<_MemoryCaptureContent> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  final TextEditingController _sourceSystem = TextEditingController(
    text: 'aurora-ui',
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
                  const Text(
                    'No nearby records',
                    style: TextStyle(color: AuroraColors.muted),
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
      subjects: _splitList(_subjects.text),
      topics: _splitList(_topics.text),
      entityNames: _splitList(_entities.text),
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

class _MemoryStewardshipPanel extends StatelessWidget {
  const _MemoryStewardshipPanel({required this.controller, this.onAreaChanged});

  final AuroraAppController controller;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the selected-memory stewardship command panel.
  @override
  Widget build(BuildContext context) {
    return SwitcherPanel(
      onAreaChanged: onAreaChanged,
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          title: 'Overview',
          icon: Icons.info_outline,
          builder: (query) =>
              _MemoryOverviewContent(controller: controller, query: query),
        ),
        SwitcherPanelArea(
          title: 'Source',
          icon: Icons.article_outlined,
          builder: (query) =>
              _MemorySourceContent(controller: controller, query: query),
        ),
        SwitcherPanelArea(
          title: 'Relations',
          icon: Icons.hub_outlined,
          builder: (query) =>
              _MemoryRelationsContent(controller: controller, query: query),
        ),
        SwitcherPanelArea(
          title: 'Metadata',
          icon: Icons.edit_note,
          builder: (query) =>
              _MemoryMetadataContent(controller: controller, query: query),
        ),
        SwitcherPanelArea(
          title: 'Corrections',
          icon: Icons.fact_check_outlined,
          builder: (query) =>
              _MemoryCorrectionsContent(controller: controller, query: query),
        ),
        SwitcherPanelArea(
          title: 'Pages',
          icon: Icons.view_timeline_outlined,
          builder: (query) =>
              _MemoryPagesContent(controller: controller, query: query),
        ),
      ],
    );
  }
}

class _MemoryOverviewContent extends StatelessWidget {
  const _MemoryOverviewContent({required this.controller, required this.query});

  final AuroraAppController controller;
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
                  style: const TextStyle(color: AuroraColors.muted),
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
                  label: 'Evidence id',
                  value: memory.evidenceId,
                ),
                _MemoryMetadataRow(label: 'Source', value: memory.sourceLabel),
                _MemoryMetadataRow(
                  label: 'Created',
                  value: _formatDate(memory.createdAt),
                ),
                _MemoryMetadataRow(
                  label: 'Updated',
                  value: _formatDate(memory.updatedAt),
                ),
                _MemoryMetadataRow(
                  label: 'Event',
                  value: _formatDate(memory.eventTime),
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

  final AuroraAppController controller;
  final String query;

  /// Builds immutable raw evidence preview for the selected memory.
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
                _MemoryPanelLabel('Evidence'),
                const SizedBox(height: 10),
                _MemoryMetadataRow(
                  label: 'Evidence id',
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
              color: const Color(0xfffffcf8),
              border: Border.all(color: AuroraColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              memory.rawContent.isEmpty
                  ? 'Source not loaded'
                  : memory.rawContent,
              style: const TextStyle(height: 1.5),
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

  final AuroraAppController controller;
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
                  const Text(
                    'No matching relationship edges',
                    style: TextStyle(color: AuroraColors.muted),
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

  final AuroraAppController controller;
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
        subjects: _splitList(_subjects.text),
        topics: _splitList(_topics.text),
        entityNames: _splitList(_entities.text),
      ),
    );
  }
}

class _MemoryCorrectionsContent extends StatefulWidget {
  const _MemoryCorrectionsContent({
    required this.controller,
    required this.query,
  });

  final AuroraAppController controller;
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
                  const Text(
                    'No corrections in current results',
                    style: TextStyle(color: AuroraColors.muted),
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

  final AuroraAppController controller;
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
    return Text(
      label.toUpperCase(),
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AuroraColors.muted,
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
    final dropdownValue = _coerceDropdownValue(values, value, values.first);
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AuroraColors.surface,
          border: Border.all(color: AuroraColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: dropdownValue,
            isDense: true,
            isExpanded: true,
            icon: const Icon(Icons.expand_more, size: 18),
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
    return TextField(
      controller: controller,
      minLines: maxLines == 1 ? 1 : 3,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AuroraColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AuroraColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AuroraColors.border),
        ),
      ),
    );
  }
}

class _MemoryMetadataRow extends StatelessWidget {
  const _MemoryMetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds one key/value metadata row.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AuroraColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w600),
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
    final isConflict = relationship.type == 'contradicts';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isConflict ? const Color(0xffffefed) : AuroraColors.surface,
        border: Border.all(
          color: isConflict ? AuroraColors.coral : AuroraColors.border,
        ),
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
                color: isConflict ? AuroraColors.coral : AuroraColors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _memoryLabel(relationship.type),
                  style: const TextStyle(fontWeight: FontWeight.w900),
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
    return const Center(
      child: Text(
        'Select a memory',
        style: TextStyle(color: AuroraColors.muted),
      ),
    );
  }
}

class _MemoryEntityRow {
  const _MemoryEntityRow({
    required this.name,
    required this.primary,
    required this.count,
    required this.topics,
  });

  final String name;
  final MemoryRecord primary;
  final int count;
  final List<String> topics;
}

class _MemoryTopicRow {
  const _MemoryTopicRow({required this.name, required this.count});

  final String name;
  final int count;
}

/// Groups memory records into entity rows for the People route.
List<_MemoryEntityRow> _memoryEntityRows(List<MemoryRecord> records) {
  final grouped = <String, List<MemoryRecord>>{};
  for (final record in records) {
    for (final entity in record.entityNames) {
      if (entity.trim().isEmpty) {
        continue;
      }
      grouped.putIfAbsent(entity, () => <MemoryRecord>[]).add(record);
    }
  }
  final rows =
      grouped.entries.map((entry) {
        final topics = _counts(
          entry.value.expand((record) => record.topics),
        ).keys.toList();
        return _MemoryEntityRow(
          name: entry.key,
          primary: entry.value.first,
          count: entry.value.length,
          topics: topics,
        );
      }).toList()..sort((a, b) {
        final countCompare = b.count.compareTo(a.count);
        return countCompare == 0 ? a.name.compareTo(b.name) : countCompare;
      });
  return rows;
}

/// Groups memory records into topic timeline rows.
List<_MemoryTopicRow> _memoryTopicRows(List<MemoryRecord> records) {
  return _counts(records.expand((record) => record.topics)).entries
      .map((entry) => _MemoryTopicRow(name: entry.key, count: entry.value))
      .toList();
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
  AuroraAppController controller, {
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
void _selectFirstEntity(AuroraAppController controller, String entity) {
  final matches = controller.workspace.memoryRecords.where((record) {
    return record.entityNames.contains(entity);
  });
  if (matches.isNotEmpty) {
    unawaited(controller.selectMemory(matches.first.id));
  }
}

/// Toggles a value in a string list.
List<String> _toggleString(List<String> values, String value) {
  if (values.contains(value)) {
    if (values.length == 1) {
      return values;
    }
    return values.where((item) => item != value).toList();
  }
  return <String>[...values, value];
}

/// Splits comma-delimited user input into normalized labels.
List<String> _splitList(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

/// Coerces a dropdown value to a valid controlled value.
String _coerceDropdownValue(
  List<String> values,
  String value,
  String defaultValue,
) {
  return values.contains(value) ? value : defaultValue;
}

/// Formats a nullable timestamp for compact display.
String _formatDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
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

class _MemoryCommandPanel extends StatelessWidget {
  const _MemoryCommandPanel({required this.controller, this.onAreaChanged});

  final AuroraAppController controller;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the memory command panel with switchable dense content areas.
  @override
  Widget build(BuildContext context) {
    return SwitcherPanel(
      onAreaChanged: onAreaChanged,
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          title: 'Memory & Context',
          icon: Icons.account_tree_outlined,
          builder: _buildKnowledgeContent,
        ),
        SwitcherPanelArea(
          title: 'Backlog',
          icon: Icons.check_circle_outline,
          builder: _buildTasksContent,
        ),
        SwitcherPanelArea(
          title: 'Stewardship',
          icon: Icons.bolt_outlined,
          builder: _buildStewardshipContent,
        ),
      ],
    );
  }

  Widget _buildKnowledgeContent(String query) {
    final filteredRecords = controller.filteredMemoryRecords.where((record) {
      return _matchesMemoryRecord(record, query);
    }).toList();
    if (filteredRecords.isEmpty) {
      return PanelEmptyState(query: query);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final record in filteredRecords)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
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

  Widget _buildTasksContent(String query) {
    final filteredTasks = controller.workspace.tasks.where((task) {
      return _matchesFuzzyQuery('${task.title} ${task.detail}', query);
    }).toList();
    if (filteredTasks.isEmpty) {
      return PanelEmptyState(query: query);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      child: Column(
        children: <Widget>[
          for (final task in filteredTasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: TaskLine(task: task),
            ),
        ],
      ),
    );
  }

  Widget _buildStewardshipContent(String query) {
    final memory = controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    if (!_matchesMemoryRecord(memory, query)) {
      return PanelEmptyState(query: query);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MemoryPanelLabel('Selected Memory'),
          const SizedBox(height: 10),
          Text(
            memory.title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: controller.memoryBusy
                    ? null
                    : () => unawaited(controller.hydrateSelectedMemorySource()),
                icon: const Icon(Icons.article_outlined),
                label: const Text('Load Source'),
              ),
              OutlinedButton.icon(
                onPressed: controller.memoryBusy
                    ? null
                    : () => unawaited(controller.loadEntityPageFromUi(memory)),
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('Entity Page'),
              ),
              for (final topic in memory.topics.take(2))
                OutlinedButton.icon(
                  onPressed: controller.memoryBusy
                      ? null
                      : () => unawaited(controller.loadTimelineFromUi(topic)),
                  icon: const Icon(Icons.timeline_outlined),
                  label: Text(topic),
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (final reason in _memoryReviewReasons(memory))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MemoryBadge(label: reason),
            ),
        ],
      ),
    );
  }
}

class _MemoryPeopleRoute extends StatelessWidget {
  const _MemoryPeopleRoute({required this.controller});

  final AuroraAppController controller;

  /// Builds the entity page route from live memory records.
  @override
  Widget build(BuildContext context) {
    final entityRows = _memoryEntityRows(controller.workspace.memoryRecords);
    return _PaddedRoute(
      title: 'People',
      subtitle: 'Entity pages compiled from source-backed memory.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MemoryStatusStrip(controller: controller),
          const SizedBox(height: 18),
          if (entityRows.isEmpty)
            const PanelEmptyBlock(label: 'No entities in memory')
          else
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: <Widget>[
                for (final entity in entityRows)
                  SizedBox(
                    width: 360,
                    child: PanelSectionBlock(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            entity.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${entity.count} source-backed records',
                            style: const TextStyle(color: AuroraColors.muted),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              for (final topic in entity.topics.take(4))
                                _MemoryBadge(label: topic),
                            ],
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: controller.memoryBusy
                                ? null
                                : () => unawaited(
                                    controller.loadEntityPageFromUi(
                                      entity.primary,
                                    ),
                                  ),
                            icon: const Icon(Icons.person_search_outlined),
                            label: const Text('Load Entity Page'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          if (controller.selectedMemoryPage != null) ...<Widget>[
            const SizedBox(height: 28),
            _CompiledPagePreview(page: controller.selectedMemoryPage!),
          ],
        ],
      ),
    );
  }
}

class _MemoryTimelineRoute extends StatelessWidget {
  const _MemoryTimelineRoute({required this.controller});

  final AuroraAppController controller;

  /// Builds topic and event timelines from live memory records.
  @override
  Widget build(BuildContext context) {
    final topicRows = _memoryTopicRows(controller.workspace.memoryRecords);
    final datedRecords =
        controller.workspace.memoryRecords
            .where(
              (record) => record.eventTime != null || record.createdAt != null,
            )
            .toList()
          ..sort((a, b) {
            final left =
                a.eventTime ??
                a.createdAt ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final right =
                b.eventTime ??
                b.createdAt ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return right.compareTo(left);
          });
    return _PaddedRoute(
      title: 'Timeline',
      subtitle: 'Source-backed memory timelines by topic and event time.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MemoryStatusStrip(controller: controller),
          const SizedBox(height: 18),
          _MemoryPanelLabel('Topic Timelines'),
          const SizedBox(height: 12),
          if (topicRows.isEmpty)
            const PanelEmptyBlock(label: 'No topics in memory')
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                for (final topic in topicRows)
                  ActionChip(
                    avatar: CircleAvatar(
                      backgroundColor: AuroraColors.greenSoft,
                      child: Text(
                        '${topic.count}',
                        style: const TextStyle(
                          color: AuroraColors.green,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    label: Text(topic.name),
                    onPressed: controller.memoryBusy
                        ? null
                        : () => unawaited(
                            controller.loadTimelineFromUi(topic.name),
                          ),
                  ),
              ],
            ),
          const SizedBox(height: 28),
          _MemoryPanelLabel('Dated Records'),
          const SizedBox(height: 12),
          if (datedRecords.isEmpty)
            const PanelEmptyBlock(label: 'No dated memory records')
          else
            Column(
              children: <Widget>[
                for (final record in datedRecords)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PanelSectionBlock(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: 142,
                            child: Text(
                              _formatDate(record.eventTime ?? record.createdAt),
                              style: const TextStyle(
                                color: AuroraColors.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  record.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  record.summary,
                                  style: const TextStyle(
                                    color: AuroraColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          if (controller.selectedMemoryPage != null) ...<Widget>[
            const SizedBox(height: 28),
            _CompiledPagePreview(page: controller.selectedMemoryPage!),
          ],
        ],
      ),
    );
  }
}

class _CompiledPagePreview extends StatelessWidget {
  const _CompiledPagePreview({required this.page});

  final CompiledMemoryPage page;

  /// Builds a source-backed compiled page preview.
  @override
  Widget build(BuildContext context) {
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            page.title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _MemoryBadge(label: page.kind),
              _MemoryBadge(label: page.scope),
              _MemoryBadge(label: '${page.sourceIds.length} sources'),
            ],
          ),
          const SizedBox(height: 16),
          SelectableText(page.content),
        ],
      ),
    );
  }
}

class _SourcesPage extends StatelessWidget {
  const _SourcesPage({required this.workspace});

  final ProjectWorkspace workspace;

  /// Builds the sources and files route.
  @override
  Widget build(BuildContext context) {
    final records = workspace.memoryRecords;
    return _PaddedRoute(
      title: 'Files',
      subtitle: 'Immutable evidence and source material from memory.',
      child: records.isEmpty
          ? const PanelEmptyBlock(label: 'No source evidence loaded')
          : Wrap(
              spacing: 16,
              runSpacing: 16,
              children: records.map((record) {
                return SizedBox(
                  width: 360,
                  child: PanelSectionBlock(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          record.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _MemoryMetadataRow(
                          label: 'Evidence',
                          value: record.evidenceId,
                        ),
                        _MemoryMetadataRow(
                          label: 'Source',
                          value: record.sourceLabel,
                        ),
                        _MemoryMetadataRow(
                          label: 'Path',
                          value: record.rawPath,
                        ),
                        _MemoryMetadataRow(
                          label: 'Media',
                          value: record.rawMediaType,
                        ),
                        _MemoryMetadataRow(
                          label: 'Checksum',
                          value: record.rawChecksum,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _PaddedRoute extends StatelessWidget {
  const _PaddedRoute({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  /// Builds a standard sidebar route layout.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.displayLarge),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(color: AuroraColors.muted, fontSize: 17),
          ),
          const SizedBox(height: 32),
          child,
        ],
      ),
    );
  }
}

Future<void> _confirmCreateTask(
  BuildContext context,
  AuroraAppController controller,
) async {
  final input = TextEditingController();
  final title = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Create Backlog Item'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Backlog title'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(input.text),
            child: const Text('Create'),
          ),
        ],
      );
    },
  );
  input.dispose();
  if (title == null || title.trim().isEmpty || !context.mounted) {
    return;
  }
  final approved = await _confirmWrite(
    context,
    'Create backlog item "$title"?',
  );
  if (approved) {
    await controller.createTaskFromUi(title.trim());
  }
}

Future<void> _confirmCompleteTask(
  BuildContext context,
  AuroraAppController controller,
  WorkspaceTask task,
) async {
  final approved = await _confirmWrite(
    context,
    'Complete backlog item "${task.title}"?',
  );
  if (approved) {
    await controller.completeTaskFromUi(task.id);
  }
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
