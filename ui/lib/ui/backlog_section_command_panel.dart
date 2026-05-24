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
  _BacklogDetailMode _detailMode = _BacklogDetailMode.details;

  /// Builds backlog areas and details inside the reusable command subshell.
  @override
  Widget build(BuildContext context) {
    return CommandPanelSubShell(
      areas: _backlogCommandAreas(widget.controller),
      detailTitle: 'Backlog',
      detailModes: _visibleBacklogDetailModes(widget.controller),
      selectedDetailModeId: _backlogDetailModeId(_effectiveDetailMode()),
      onDetailModeSelected: _selectDetailMode,
      detailBuilder: _buildDetailBody,
      detailTabsBuilder: _buildDetailTabs,
      areaTabbedDetailBuilder: _buildTabbedDetailBody,
      onAreaChanged: widget.onAreaChanged,
      areaActionsBuilder: _buildAreaActions,
      detailActionsBuilder: _buildDetailActions,
      filterHint: 'Filter...',
      split: const PanelSplit(left: 0.30, min: 0.22, max: 0.48),
    );
  }

  /// Builds header actions for the active command area.
  Widget? _buildAreaActions(BuildContext context, SwitcherPanelArea area) {
    if (area.title != 'Queue') {
      return null;
    }
    return _BacklogQueueHeaderActions(
      active: _effectiveDetailMode() == _BacklogDetailMode.capture,
      onCapture: () =>
          _selectDetailMode(_backlogDetailModeId(_BacklogDetailMode.capture)),
    );
  }

  /// Builds selected-object actions for task-oriented detail modes.
  Widget? _buildDetailActions(
    BuildContext context,
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    final task = widget.controller.selectedTask;
    if (task == null) {
      return null;
    }
    final detailMode = _backlogDetailModeForId(mode.id);
    return switch (detailMode) {
      _BacklogDetailMode.details => _BacklogSelectedTaskActions(
        controller: widget.controller,
        task: task,
      ),
      _BacklogDetailMode.memoryLinks => _BacklogTaskMemoryActions(
        controller: widget.controller,
        task: task,
      ),
      _ => null,
    };
  }

  /// Selects the right-side work mode and mirrors review state to controller.
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
    final visibleModes = _visibleBacklogDetailModes(
      widget.controller,
    ).map((mode) => mode.id).toSet();
    final selected = _detailMode == _BacklogDetailMode.aiReview
        ? _BacklogDetailMode.details
        : _detailMode;
    if (visibleModes.contains(_backlogDetailModeId(selected))) {
      return selected;
    }
    return _BacklogDetailMode.details;
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
      _BacklogDetailMode.stream => TaskConceptProjectionPanel(
        controller: widget.controller,
        kind: TaskConceptKind.stream,
      ),
      _BacklogDetailMode.wbs => TaskConceptProjectionPanel(
        controller: widget.controller,
        kind: TaskConceptKind.wbs,
      ),
      _BacklogDetailMode.map => TaskConceptProjectionPanel(
        controller: widget.controller,
        kind: TaskConceptKind.constellation,
      ),
      _BacklogDetailMode.capture => _TaskCaptureContent(
        controller: widget.controller,
        query: '',
      ),
      _BacklogDetailMode.details =>
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

  /// Returns labeled tabs inside projection work modes.
  List<ShellTab> _buildDetailTabs(
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    final detailMode = _backlogDetailModeForId(mode.id);
    if (detailMode == _BacklogDetailMode.wbs) {
      return const <ShellTab>[
        ShellTab(id: 'tree', label: 'Tree', icon: Icons.account_tree_outlined),
        ShellTab(id: 'overview', label: 'Overview', icon: Icons.info_outline),
      ];
    }
    if (detailMode == _BacklogDetailMode.map) {
      return const <ShellTab>[
        ShellTab(id: 'canvas', label: 'Canvas', icon: Icons.hub_outlined),
        ShellTab(id: 'overview', label: 'Overview', icon: Icons.info_outline),
      ];
    }
    if (detailMode == _BacklogDetailMode.capture) {
      return const <ShellTab>[
        ShellTab(id: 'form', label: 'Form', icon: Icons.add_task_outlined),
        ShellTab(id: 'context', label: 'Context', icon: Icons.info_outline),
      ];
    }
    return const <ShellTab>[];
  }

  /// Builds content for the selected projection subview.
  Widget _buildTabbedDetailBody(
    SwitcherPanelArea area,
    String modeId,
    String tabId,
  ) {
    final mode = _backlogDetailModeForId(modeId);
    if (mode == _BacklogDetailMode.wbs && tabId == 'overview') {
      return _BacklogWbsDetailPanel(controller: widget.controller);
    }
    if (mode == _BacklogDetailMode.map && tabId == 'overview') {
      final edge = widget.controller.selectedConstellationEdge;
      if (edge != null) {
        return _TaskConstellationEdgeInspector(
          controller: widget.controller,
          edge: edge,
        );
      }
      return _BacklogConstellationDetailPanel(controller: widget.controller);
    }
    if (mode == _BacklogDetailMode.capture && tabId == 'context') {
      return _BacklogCaptureDetailPanel(controller: widget.controller);
    }
    return _buildDetailBody(modeId);
  }
}
