/// Memory command shell and detail-mode coordination widgets.
part of 'agent_awesome_shell.dart';

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
      searchableDetailBuilder: (_, modeId, query) =>
          _buildDetailContent(modeId, query),
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
  Widget _buildDetailContent(String modeId, [String query = '']) {
    return switch (modeId) {
      _memorySourceDetailId => _MemorySourceContent(
        controller: widget.controller,
        query: query,
      ),
      _memoryRelationsDetailId => _MemoryRelationsContent(
        controller: widget.controller,
        query: query,
      ),
      _memoryMetadataDetailId => _MemoryMetadataContent(
        controller: widget.controller,
        query: query,
      ),
      _memoryCorrectionsDetailId => _MemoryCorrectionsContent(
        controller: widget.controller,
        query: query,
      ),
      _memoryPagesDetailId => _MemoryPagesContent(
        controller: widget.controller,
        query: query,
      ),
      _ => _MemoryOverviewContent(controller: widget.controller, query: query),
    };
  }
}
