/// Chat command surface widgets for the Agent Awesome shell.
part of 'agent_awesome_shell.dart';

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
