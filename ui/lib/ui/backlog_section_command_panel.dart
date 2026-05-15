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
  final Map<String, _BacklogDetailMode> _detailModesByArea =
      <String, _BacklogDetailMode>{};

  /// Builds backlog areas and details inside the reusable command subshell.
  @override
  Widget build(BuildContext context) {
    return CommandPanelSubShell(
      areas: _backlogCommandAreas(widget.controller),
      detailTitle: 'Backlog Inspector',
      detailModes: const <CommandPanelDetailMode>[],
      selectedDetailModeId: _backlogDetailModeId(_BacklogDetailMode.inspector),
      onDetailModeSelected: _selectDetailMode,
      detailBuilder: _buildDetailBody,
      detailModesBuilder: (area) =>
          _visibleBacklogDetailModes(widget.controller, area),
      selectedDetailModeIdBuilder: (area) =>
          _backlogDetailModeId(_effectiveDetailMode(area)),
      onAreaDetailModeSelected: _selectAreaDetailMode,
      areaDetailBuilder: _buildAreaDetailBody,
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
    _selectAreaDetailMode(
      const SwitcherPanelArea(
        id: _BacklogAreaIds.queue,
        title: 'Queue',
        icon: Icons.task_alt_outlined,
        builder: _emptyBacklogAreaBuilder,
      ),
      modeId,
    );
  }

  /// Selects an area-scoped details mode and mirrors review state to controller.
  void _selectAreaDetailMode(SwitcherPanelArea area, String modeId) {
    final mode = _backlogDetailModeForId(modeId);
    if (mode == _BacklogDetailMode.aiReview) {
      widget.controller.openBacklogReviewPanel();
    } else {
      widget.controller.openBacklogInspectorPanel();
    }
    setState(() {
      _detailModesByArea[_backlogAreaId(area)] = mode;
    });
  }

  /// Returns the visible details mode, honoring controller-owned AI review state.
  _BacklogDetailMode _effectiveDetailMode(SwitcherPanelArea area) {
    final hasReview = _backlogReviewAvailable(widget.controller);
    if (_backlogAreaId(area) == _BacklogAreaIds.queue &&
        widget.controller.backlogReviewPanelOpen &&
        hasReview) {
      return _BacklogDetailMode.aiReview;
    }
    final visibleModes = _visibleBacklogDetailModes(
      widget.controller,
      area,
    ).map((mode) => mode.id).toSet();
    final selected =
        _detailModesByArea[_backlogAreaId(area)] ??
        _defaultBacklogDetailModeForArea(area);
    if (visibleModes.contains(_backlogDetailModeId(selected))) {
      return selected;
    }
    return _defaultBacklogDetailModeForArea(area);
  }

  /// Builds the content for the current detail mode id.
  Widget _buildDetailBody(String modeId) {
    return _buildAreaDetailBody(
      const SwitcherPanelArea(
        id: _BacklogAreaIds.queue,
        title: 'Queue',
        icon: Icons.task_alt_outlined,
        builder: _emptyBacklogAreaBuilder,
      ),
      modeId,
    );
  }

  /// Builds the content for the active area and detail mode id.
  Widget _buildAreaDetailBody(SwitcherPanelArea area, String modeId) {
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
      _BacklogDetailMode.streamOverview => _BacklogStreamDetailPanel(
        controller: widget.controller,
      ),
      _BacklogDetailMode.terrainOverview => _BacklogTerrainDetailPanel(
        controller: widget.controller,
      ),
      _BacklogDetailMode.wbsOverview => _BacklogWbsDetailPanel(
        controller: widget.controller,
      ),
      _BacklogDetailMode.constellationOverview =>
        edge != null
            ? _TaskConstellationEdgeInspector(
                controller: widget.controller,
                edge: edge,
              )
            : _BacklogConstellationDetailPanel(controller: widget.controller),
      _BacklogDetailMode.captureContext => _BacklogCaptureDetailPanel(
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

/// Builds an empty area for detail-mode calls that do not supply an area.
Widget _emptyBacklogAreaBuilder(String query) {
  return const SizedBox.shrink();
}
