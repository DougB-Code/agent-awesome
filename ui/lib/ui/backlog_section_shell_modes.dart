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

  /// Stream projection overview.
  streamOverview,

  /// Terrain projection overview.
  terrainOverview,

  /// Work-breakdown structure overview.
  wbsOverview,

  /// Constellation projection overview.
  constellationOverview,

  /// Capture context summary.
  captureContext,
}

/// _BacklogAreaIds stores stable ids for backlog command areas.
abstract final class _BacklogAreaIds {
  /// Queue task list area.
  static const String queue = 'queue';

  /// Stream projection area.
  static const String stream = 'stream';

  /// Terrain projection area.
  static const String terrain = 'terrain';

  /// Work-breakdown structure area.
  static const String wbs = 'wbs';

  /// Constellation projection area.
  static const String constellation = 'constellation';

  /// Task capture form area.
  static const String capture = 'capture';
}

/// Builds the canonical backlog command areas used by the command subshell.
List<SwitcherPanelArea> _backlogCommandAreas(
  AgentAwesomeAppController controller,
) {
  return <SwitcherPanelArea>[
    SwitcherPanelArea(
      id: _BacklogAreaIds.queue,
      title: 'Queue',
      icon: Icons.task_alt_outlined,
      builder: (query) =>
          _BacklogQueueContent(controller: controller, query: query),
    ),
    SwitcherPanelArea(
      id: _BacklogAreaIds.stream,
      title: 'Stream',
      icon: Icons.waves_outlined,
      builder: (query) => TaskConceptProjectionPanel(
        controller: controller,
        kind: TaskConceptKind.stream,
      ),
    ),
    SwitcherPanelArea(
      id: _BacklogAreaIds.terrain,
      title: 'Terrain',
      icon: Icons.terrain_outlined,
      builder: (query) => TaskConceptProjectionPanel(
        controller: controller,
        kind: TaskConceptKind.terrain,
      ),
    ),
    SwitcherPanelArea(
      id: _BacklogAreaIds.wbs,
      title: 'WBS',
      icon: Icons.account_tree_outlined,
      builder: (query) => TaskConceptProjectionPanel(
        controller: controller,
        kind: TaskConceptKind.wbs,
      ),
    ),
    SwitcherPanelArea(
      id: _BacklogAreaIds.constellation,
      title: 'Constellation',
      icon: Icons.hub_outlined,
      builder: (query) => TaskConceptProjectionPanel(
        controller: controller,
        kind: TaskConceptKind.constellation,
      ),
    ),
    SwitcherPanelArea(
      id: _BacklogAreaIds.capture,
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
  SwitcherPanelArea area,
) {
  switch (_backlogAreaId(area)) {
    case _BacklogAreaIds.queue:
      return <CommandPanelDetailMode>[
        _backlogDetailMode(_BacklogDetailMode.inspector),
        _backlogDetailMode(_BacklogDetailMode.memoryLinks),
        if (_backlogReviewAvailable(controller))
          _backlogDetailMode(_BacklogDetailMode.aiReview),
      ];
    case _BacklogAreaIds.stream:
      return <CommandPanelDetailMode>[
        _backlogDetailMode(_BacklogDetailMode.streamOverview),
        _backlogDetailMode(_BacklogDetailMode.inspector),
      ];
    case _BacklogAreaIds.terrain:
      return <CommandPanelDetailMode>[
        _backlogDetailMode(_BacklogDetailMode.terrainOverview),
        _backlogDetailMode(_BacklogDetailMode.inspector),
      ];
    case _BacklogAreaIds.wbs:
      return <CommandPanelDetailMode>[
        _backlogDetailMode(_BacklogDetailMode.wbsOverview),
        _backlogDetailMode(_BacklogDetailMode.inspector),
      ];
    case _BacklogAreaIds.constellation:
      return <CommandPanelDetailMode>[
        _backlogDetailMode(_BacklogDetailMode.constellationOverview),
        _backlogDetailMode(_BacklogDetailMode.inspector),
      ];
    case _BacklogAreaIds.capture:
      return <CommandPanelDetailMode>[
        _backlogDetailMode(_BacklogDetailMode.captureContext),
        _backlogDetailMode(_BacklogDetailMode.memoryLinks),
      ];
    default:
      return <CommandPanelDetailMode>[
        _backlogDetailMode(_BacklogDetailMode.inspector),
      ];
  }
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
    _BacklogDetailMode.streamOverview => 'stream_overview',
    _BacklogDetailMode.terrainOverview => 'terrain_overview',
    _BacklogDetailMode.wbsOverview => 'wbs_overview',
    _BacklogDetailMode.constellationOverview => 'constellation_overview',
    _BacklogDetailMode.captureContext => 'capture_context',
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
  if (id == _backlogDetailModeId(_BacklogDetailMode.streamOverview)) {
    return _BacklogDetailMode.streamOverview;
  }
  if (id == _backlogDetailModeId(_BacklogDetailMode.terrainOverview)) {
    return _BacklogDetailMode.terrainOverview;
  }
  if (id == _backlogDetailModeId(_BacklogDetailMode.wbsOverview)) {
    return _BacklogDetailMode.wbsOverview;
  }
  if (id == _backlogDetailModeId(_BacklogDetailMode.constellationOverview)) {
    return _BacklogDetailMode.constellationOverview;
  }
  if (id == _backlogDetailModeId(_BacklogDetailMode.captureContext)) {
    return _BacklogDetailMode.captureContext;
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
    _BacklogDetailMode.streamOverview => 'Stream',
    _BacklogDetailMode.terrainOverview => 'Terrain',
    _BacklogDetailMode.wbsOverview => 'WBS',
    _BacklogDetailMode.constellationOverview => 'Graph',
    _BacklogDetailMode.captureContext => 'Capture',
  };
}

/// Returns the icon for a backlog detail mode.
IconData _backlogDetailIcon(_BacklogDetailMode mode) {
  return switch (mode) {
    _BacklogDetailMode.inspector => Icons.edit_note_outlined,
    _BacklogDetailMode.memoryLinks => Icons.link_outlined,
    _BacklogDetailMode.aiReview => Icons.auto_awesome_outlined,
    _BacklogDetailMode.streamOverview => Icons.waves_outlined,
    _BacklogDetailMode.terrainOverview => Icons.terrain_outlined,
    _BacklogDetailMode.wbsOverview => Icons.account_tree_outlined,
    _BacklogDetailMode.constellationOverview => Icons.hub_outlined,
    _BacklogDetailMode.captureContext => Icons.add_task_outlined,
  };
}

/// Returns a stable area id for a backlog switcher area.
String _backlogAreaId(SwitcherPanelArea area) {
  return area.id.isEmpty ? area.title.toLowerCase() : area.id;
}

/// Returns the default right-side detail mode for a backlog area.
_BacklogDetailMode _defaultBacklogDetailModeForArea(SwitcherPanelArea area) {
  return switch (_backlogAreaId(area)) {
    _BacklogAreaIds.stream => _BacklogDetailMode.streamOverview,
    _BacklogAreaIds.terrain => _BacklogDetailMode.terrainOverview,
    _BacklogAreaIds.wbs => _BacklogDetailMode.wbsOverview,
    _BacklogAreaIds.constellation => _BacklogDetailMode.constellationOverview,
    _BacklogAreaIds.capture => _BacklogDetailMode.captureContext,
    _ => _BacklogDetailMode.inspector,
  };
}
