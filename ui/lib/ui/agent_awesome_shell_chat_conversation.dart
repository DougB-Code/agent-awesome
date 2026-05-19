/// Chat conversation panel, timeline content, and session picker widgets.
part of 'agent_awesome_shell.dart';

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
      detailTitle: '',
      detailModes: const <CommandPanelDetailMode>[],
      selectedDetailModeId: '',
      onDetailModeSelected: (_) {},
      detailBuilder: (_) => const SizedBox.shrink(),
      areaActionsBuilder: (context, area) =>
          _ChatSessionPicker(controller: widget.controller),
      filterHint: 'Filter...',
      showAreaTabs: false,
      showDetailPane: false,
      showPaneCollapseButtons: false,
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
  final ScrollController _timelineController = ScrollController();
  String _lastScrolledSessionId = '';
  int _lastScrolledMessageCount = -1;
  bool _scrollScheduled = false;

  /// Cleans up the persistent chat composer.
  @override
  void dispose() {
    _replyController.dispose();
    _timelineController.dispose();
    super.dispose();
  }

  /// Builds the selected conversation body and composer.
  Widget _buildConversationContent(String query) {
    final messages = widget.controller.messages.where((message) {
      return _matchesFuzzyQuery('${message.author} ${message.text}', query);
    }).toList();
    _scheduleScrollToBottom(messages.length);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final timelineChildren = <Widget>[
          for (final message in messages)
            ChatRow(message: message, compact: compact),
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
                controller: _timelineController,
                empty: PanelEmptyState(query: query),
                compact: compact,
                children: timelineChildren,
              ),
            ),
            Divider(height: 1, color: context.agentAwesomeColors.border),
            _ChatComposer(
              controller: _replyController,
              sending: widget.controller.sending,
              modelChoices: widget.controller.chatModelChoices,
              selectedModelRef: widget.controller.activeChatModelRef,
              onModelSelected: widget.controller.selectChatModelRef,
              onSubmit: _submitReply,
            ),
          ],
        );
      },
    );
  }

  /// Builds the conversation content for the current fuzzy query.
  @override
  Widget build(BuildContext context) {
    return _buildConversationContent(widget.query);
  }

  /// Schedules a bottom jump when a chat is opened or receives new messages.
  void _scheduleScrollToBottom(int messageCount) {
    if (messageCount == 0) {
      return;
    }
    final sessionId = widget.controller.selectedSessionId ?? '';
    final shouldScroll =
        sessionId != _lastScrolledSessionId ||
        messageCount != _lastScrolledMessageCount;
    if (!shouldScroll || _scrollScheduled) {
      return;
    }
    _lastScrolledSessionId = sessionId;
    _lastScrolledMessageCount = messageCount;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_timelineController.hasClients) {
        return;
      }
      _timelineController.jumpTo(_timelineController.position.maxScrollExtent);
    });
  }

  /// Sends the composer text into the selected chat thread.
  Future<void> _submitReply() async {
    final value = _replyController.text;
    _replyController.clear();
    await widget.controller.sendUserMessage(value);
  }
}

class _ChatSessionListContent extends StatelessWidget {
  const _ChatSessionListContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds the left-side chat session collection.
  @override
  Widget build(BuildContext context) {
    final entries = _chatSessionListEntries(controller).where((entry) {
      return _matchesFuzzyQuery(
        '${entry.title} ${entry.subtitle} ${entry.searchText}',
        query,
      );
    }).toList();
    if (entries.isEmpty) {
      return query.trim().isEmpty
          ? const PanelEmptyBlock(label: 'No chats yet')
          : PanelEmptyState(query: query);
    }
    final selectedKey = controller.selectedChatKey;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _ChatSessionTile(
          entry: entry,
          selected: entry.key == selectedKey,
          onTap: () => unawaited(controller.selectHistoryChat(entry.key)),
        );
      },
    );
  }
}

class _ChatSessionTile extends StatelessWidget {
  const _ChatSessionTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final _ChatSessionListEntry entry;
  final bool selected;
  final VoidCallback onTap;

  /// Builds one selectable chat session card.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: PanelSurface(
        fillWidth: true,
        padding: const EdgeInsets.all(12),
        style: PanelSurfaceStyle.card,
        selected: selected,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.chat_bubble_outline,
              color: selected ? colors.green : colors.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (entry.subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 5),
                    Text(
                      entry.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                  if (selected) ...<Widget>[
                    const SizedBox(height: 8),
                    const PanelBadge(label: 'Active'),
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

class _ChatSessionListEntry {
  const _ChatSessionListEntry({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.searchText,
  });

  final String key;
  final String title;
  final String subtitle;
  final String searchText;
}

/// Builds selectable chat session rows from history and live sessions.
List<_ChatSessionListEntry> _chatSessionListEntries(
  AgentAwesomeAppController controller,
) {
  final entries = <_ChatSessionListEntry>[];
  final seenKeys = <String>{};
  for (final chat in controller.chatHistory) {
    entries.add(
      _ChatSessionListEntry(
        key: chat.key,
        title: chat.title,
        subtitle:
            '${chat.profileLabel} • ${formatLocalMonthDayTime(chat.updatedAt)}',
        searchText:
            '${chat.sessionId} ${chat.profileId} ${chat.profilePath} ${chat.titleStatus}',
      ),
    );
    seenKeys.add(chat.key);
  }
  for (final session in controller.sessions) {
    final key = '${controller.runtimeProfilePath}::${session.id}';
    if (seenKeys.contains(key)) {
      continue;
    }
    entries.add(
      _ChatSessionListEntry(
        key: key,
        title: session.title,
        subtitle: formatLocalMonthDayTime(session.updatedAt),
        searchText: session.id,
      ),
    );
  }
  return entries;
}

class _ChatSessionPicker extends StatelessWidget {
  const _ChatSessionPicker({required this.controller});

  final AgentAwesomeAppController controller;

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
        ),
        const SizedBox(width: 8),
        PanelIconButton(
          icon: Icons.add_comment_outlined,
          tooltip: 'Start new chat',
          onPressed: () => unawaited(controller.createChat()),
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
    return <SearchPickerOption<String>>[
      for (final entry in _chatSessionListEntries(controller))
        SearchPickerOption<String>(
          value: entry.key,
          title: entry.title,
          subtitle: entry.subtitle,
          searchText: entry.searchText,
          icon: Icons.chat_bubble_outline,
        ),
    ];
  }
}
