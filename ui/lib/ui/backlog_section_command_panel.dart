/// Backlog command-panel shell widget.
part of 'backlog_section.dart';

/// BacklogCommandPanel renders backlog work in the official command subshell.
class BacklogCommandPanel extends StatefulWidget {
  /// Creates the backlog command panel.
  const BacklogCommandPanel({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Reports the active command area to the app shell.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  @override
  State<BacklogCommandPanel> createState() => _BacklogCommandPanelState();
}

/// _BacklogCommandPanelState stores the selected backlog detail mode.
class _BacklogCommandPanelState extends State<BacklogCommandPanel> {
  _BacklogDetailMode _detailMode = _BacklogDetailMode.inspector;

  /// Builds backlog areas and details inside the reusable command subshell.
  @override
  Widget build(BuildContext context) {
    final selectedMode = _effectiveDetailMode();
    return CommandPanelSubShell(
      areas: _backlogCommandAreas(widget.controller),
      detailTitle: 'Backlog Inspector',
      detailModes: _visibleBacklogDetailModes(widget.controller),
      selectedDetailModeId: _backlogDetailModeId(selectedMode),
      onDetailModeSelected: _selectDetailMode,
      detailBuilder: _buildDetailBody,
      onAreaChanged: widget.onAreaChanged,
      areaActionsBuilder: _buildAreaActions,
      filterHint: 'Filter...',
    );
  }

  /// Builds header actions for the active command area.
  Widget? _buildAreaActions(BuildContext context, SwitcherPanelArea area) {
    if (area.title != 'Queue') {
      return null;
    }
    return _BacklogQueueHeaderActions(controller: widget.controller);
  }

  /// Selects the right-side details mode and mirrors review state to controller.
  void _selectDetailMode(String modeId) {
    final mode = _backlogDetailModeForId(modeId);
    if (mode == _BacklogDetailMode.aiReview) {
      widget.controller.openBacklogReviewPanel();
    } else {
      widget.controller.openBacklogInspectorPanel();
    }
    setState(() {
      _detailMode = mode;
    });
  }

  /// Returns the visible details mode, honoring controller-owned AI review state.
  _BacklogDetailMode _effectiveDetailMode() {
    final hasReview = _backlogReviewAvailable(widget.controller);
    if (widget.controller.backlogReviewPanelOpen && hasReview) {
      return _BacklogDetailMode.aiReview;
    }
    return _detailMode == _BacklogDetailMode.aiReview
        ? _BacklogDetailMode.inspector
        : _detailMode;
  }

  /// Builds the content for the current detail mode id.
  Widget _buildDetailBody(String modeId) {
    final mode = _backlogDetailModeForId(modeId);
    final edge = widget.controller.selectedConstellationEdge;
    final task = widget.controller.selectedTask;
    return switch (mode) {
      _BacklogDetailMode.memoryLinks =>
        task == null
            ? const _TaskSelectionEmpty()
            : _TaskMemoryLinkPanel(
                controller: widget.controller,
                task: task,
                query: '',
              ),
      _BacklogDetailMode.aiReview => _BacklogReviewContent(
        controller: widget.controller,
      ),
      _BacklogDetailMode.inspector =>
        edge != null
            ? _TaskConstellationEdgeInspector(
                controller: widget.controller,
                edge: edge,
              )
            : task == null
            ? const _TaskSelectionEmpty()
            : _TaskDetailEditor(controller: widget.controller, task: task),
    };
  }
}
