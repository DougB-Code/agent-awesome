/// Backlog command-area and detail-mode configuration helpers.
part of 'backlog_section.dart';

/// _TaskFilterView identifies bundled queue filter modes.
enum _TaskFilterView {
  /// Open, waiting, and blocked backlog items.
  active,

  /// Every backlog item status.
  all,
}

/// _BacklogDetailMode identifies the right-side backlog details view.
enum _BacklogDetailMode {
  /// Task and relation inspector.
  inspector,

  /// Selected task memory linking tools.
  memoryLinks,

  /// Screen-command review queue.
  aiReview,
}

/// Builds the canonical backlog command areas used by the command subshell.
List<SwitcherPanelArea> _backlogCommandAreas(
  AgentAwesomeAppController controller,
) {
  return <SwitcherPanelArea>[
    SwitcherPanelArea(
      title: 'Queue',
      icon: Icons.task_alt_outlined,
      builder: (query) =>
          _BacklogQueueContent(controller: controller, query: query),
    ),
    SwitcherPanelArea(
      title: 'Stream',
      icon: Icons.waves_outlined,
      builder: (query) => TaskConceptProjectionPanel(
        controller: controller,
        kind: TaskConceptKind.stream,
      ),
    ),
    SwitcherPanelArea(
      title: 'Terrain',
      icon: Icons.terrain_outlined,
      builder: (query) => TaskConceptProjectionPanel(
        controller: controller,
        kind: TaskConceptKind.terrain,
      ),
    ),
    SwitcherPanelArea(
      title: 'WBS',
      icon: Icons.account_tree_outlined,
      builder: (query) => TaskConceptProjectionPanel(
        controller: controller,
        kind: TaskConceptKind.wbs,
      ),
    ),
    SwitcherPanelArea(
      title: 'Constellation',
      icon: Icons.hub_outlined,
      builder: (query) => TaskConceptProjectionPanel(
        controller: controller,
        kind: TaskConceptKind.constellation,
      ),
    ),
    SwitcherPanelArea(
      title: 'Capture',
      icon: Icons.add_task_outlined,
      builder: (query) =>
          _TaskCaptureContent(controller: controller, query: query),
    ),
  ];
}

/// Returns the details modes available for the current backlog state.
List<CommandPanelDetailMode> _visibleBacklogDetailModes(
  AgentAwesomeAppController controller,
) {
  return <CommandPanelDetailMode>[
    _backlogDetailMode(_BacklogDetailMode.inspector),
    _backlogDetailMode(_BacklogDetailMode.memoryLinks),
    if (_backlogReviewAvailable(controller))
      _backlogDetailMode(_BacklogDetailMode.aiReview),
  ];
}

/// Reports whether there is an AI screen-command run worth reviewing.
bool _backlogReviewAvailable(AgentAwesomeAppController controller) {
  return controller.activeScreenCommandRun?.changes.isNotEmpty ?? false;
}

/// Returns the stable id for a backlog detail mode.
String _backlogDetailModeId(_BacklogDetailMode mode) {
  return switch (mode) {
    _BacklogDetailMode.inspector => 'inspector',
    _BacklogDetailMode.memoryLinks => 'memory_links',
    _BacklogDetailMode.aiReview => 'ai_review',
  };
}

/// Converts a stable detail mode id into a backlog detail mode.
_BacklogDetailMode _backlogDetailModeForId(String id) {
  if (id == _backlogDetailModeId(_BacklogDetailMode.memoryLinks)) {
    return _BacklogDetailMode.memoryLinks;
  }
  if (id == _backlogDetailModeId(_BacklogDetailMode.aiReview)) {
    return _BacklogDetailMode.aiReview;
  }
  return _BacklogDetailMode.inspector;
}

/// Creates a reusable command-panel detail mode for one backlog mode.
CommandPanelDetailMode _backlogDetailMode(_BacklogDetailMode mode) {
  return CommandPanelDetailMode(
    id: _backlogDetailModeId(mode),
    label: _backlogDetailLabel(mode),
    icon: _backlogDetailIcon(mode),
  );
}

/// Returns the visible label for a backlog detail mode.
String _backlogDetailLabel(_BacklogDetailMode mode) {
  return switch (mode) {
    _BacklogDetailMode.inspector => 'Inspector',
    _BacklogDetailMode.memoryLinks => 'Memory',
    _BacklogDetailMode.aiReview => 'AI review',
  };
}

/// Returns the icon for a backlog detail mode.
IconData _backlogDetailIcon(_BacklogDetailMode mode) {
  return switch (mode) {
    _BacklogDetailMode.inspector => Icons.edit_note_outlined,
    _BacklogDetailMode.memoryLinks => Icons.link_outlined,
    _BacklogDetailMode.aiReview => Icons.auto_awesome_outlined,
  };
}
