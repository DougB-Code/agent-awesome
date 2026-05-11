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
