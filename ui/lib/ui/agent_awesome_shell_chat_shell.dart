/// Chat command subshell and detail-mode coordination widgets.
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
