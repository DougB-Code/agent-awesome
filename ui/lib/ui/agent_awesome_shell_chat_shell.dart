/// Chat command subshell and detail-mode coordination widgets.
part of 'agent_awesome_shell.dart';

class _ChatCommandSubShell extends StatefulWidget {
  const _ChatCommandSubShell({
    required this.controller,
    this.initialDetailModeId = _chatConversationDetailId,
    this.onAreaChanged,
    this.onDetailModeChanged,
  });

  final AgentAwesomeAppController controller;
  final String initialDetailModeId;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;
  final ValueChanged<String>? onDetailModeChanged;

  @override
  State<_ChatCommandSubShell> createState() => _ChatCommandSubShellState();
}

class _ChatCommandSubShellState extends State<_ChatCommandSubShell> {
  late String _detailModeId;

  /// Reports the initial right-side Chat mode to the owning app shell.
  @override
  void initState() {
    super.initState();
    _detailModeId = _validChatDetailModeId(widget.initialDetailModeId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onDetailModeChanged?.call(_detailModeId);
    });
  }

  /// Keeps the selected right-side mode stable when shell chrome changes.
  @override
  void didUpdateWidget(covariant _ChatCommandSubShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextMode = _validChatDetailModeId(widget.initialDetailModeId);
    if (nextMode != _detailModeId) {
      _detailModeId = nextMode;
    }
  }

  /// Builds conversation and context in the shared command subshell.
  @override
  Widget build(BuildContext context) {
    return CommandPanelSubShell(
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          id: 'chats',
          title: 'Chats',
          icon: Icons.chat_bubble_outline,
          builder: (query) => _ChatSessionListContent(
            controller: widget.controller,
            query: query,
          ),
        ),
      ],
      detailTitle: 'Chat',
      detailModes: const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _chatConversationDetailId,
          label: 'Conversation',
          icon: Icons.forum_outlined,
        ),
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
      searchableDetailBuilder: (_, modeId, query) =>
          _buildDetailContent(modeId, query),
      onAreaChanged: widget.onAreaChanged,
      areaActionsBuilder: (context, area) => PanelIconButton(
        icon: Icons.add_comment_outlined,
        tooltip: 'Start new chat',
        onPressed: () => unawaited(widget.controller.createChat()),
      ),
      filterHint: 'Filter chats...',
      detailFilterHint: 'Filter selected chat...',
      split: const PanelSplit(left: 0.28, min: 0.18, max: 0.48),
    );
  }

  /// Selects the active chat detail mode.
  void _selectDetailMode(String modeId) {
    setState(() => _detailModeId = modeId);
    widget.onDetailModeChanged?.call(modeId);
  }

  /// Builds the selected right-side chat utility surface.
  Widget _buildDetailContent(String modeId, [String query = '']) {
    return switch (modeId) {
      _chatConversationDetailId => _ChatConversationContent(
        controller: widget.controller,
        query: query,
      ),
      _chatTasksDetailId => _buildTasksContent(query),
      _chatFilesDetailId => _buildFilesContent(query),
      _chatPeopleDetailId => _buildPeopleContent(query),
      _chatRuntimeDetailId => _buildRuntimeContent(query),
      _ => _buildMemoryContent(query),
    };
  }

  /// Builds non-transcript memory used by the selected chat.
  Widget _buildMemoryContent(String query) {
    final memories = _chatMemoryRecords(widget.controller).where((record) {
      return _matchesFuzzyQuery(
        '${record.title} ${record.summary} ${record.kind} ${record.sourceLabel}',
        query,
      );
    }).toList();
    if (memories.isEmpty) {
      return query.trim().isEmpty
          ? const _ChatContextEmpty(label: 'No memory used in this chat')
          : PanelEmptyState(query: query);
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
  Widget _buildTasksContent(String query) {
    final tasks = widget.controller.selectedChatTasks.where((task) {
      return _matchesFuzzyQuery(
        '${task.title} ${task.detail} ${task.status} ${task.priority} ${task.owner} ${task.sourceLabel}',
        query,
      );
    }).toList();
    if (tasks.isEmpty) {
      return query.trim().isEmpty
          ? const _ChatContextEmpty(label: 'No tasks linked to this chat')
          : PanelEmptyState(query: query);
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
  Widget _buildFilesContent(String query) {
    final allFileRecords = _chatFileRecords(widget.controller);
    final fileRecords = allFileRecords.where((record) {
      return _matchesFuzzyQuery(
        '${record.title} ${record.summary} ${record.sourceLabel} ${record.sourceId}',
        query,
      );
    }).toList();
    final sources = _chatSourceItems(widget.controller).where((source) {
      return !_sourceItemRepresentedByFileRecord(source, allFileRecords) &&
          _matchesFuzzyQuery('${source.title} ${source.detail}', query);
    }).toList();
    if (fileRecords.isEmpty && sources.isEmpty) {
      return query.trim().isEmpty
          ? const _ChatContextEmpty(label: 'No files used in this chat')
          : PanelEmptyState(query: query);
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
  Widget _buildPeopleContent(String query) {
    final people = _chatPeopleRows(widget.controller).where((person) {
      return _matchesFuzzyQuery(person.name, query);
    }).toList();
    if (people.isEmpty) {
      return query.trim().isEmpty
          ? const _ChatContextEmpty(label: 'No people linked to this chat')
          : PanelEmptyState(query: query);
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
  Widget _buildRuntimeContent(String query) {
    final summaries = _chatRuntimeSummaries(widget.controller).where((summary) {
      return _matchesFuzzyQuery(
        '${summary.title} ${summary.detail} ${summary.message}',
        query,
      );
    }).toList();
    final confirmation = widget.controller.pendingConfirmation;
    final showConfirmation =
        confirmation != null &&
        _matchesFuzzyQuery(
          'pending approval ${confirmation.hint} ${confirmation.options.map((option) => option.label).join(' ')}',
          query,
        );
    if (summaries.isEmpty && !showConfirmation) {
      return query.trim().isEmpty
          ? const _ChatContextEmpty(label: 'No runtime activity right now')
          : PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (showConfirmation)
          _ChatConfirmationUtility(
            confirmation: confirmation,
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

/// Returns a supported Chat detail mode id.
String _validChatDetailModeId(String modeId) {
  return switch (modeId) {
    _chatMemoryDetailId ||
    _chatTasksDetailId ||
    _chatFilesDetailId ||
    _chatPeopleDetailId ||
    _chatRuntimeDetailId => modeId,
    _ => _chatConversationDetailId,
  };
}
