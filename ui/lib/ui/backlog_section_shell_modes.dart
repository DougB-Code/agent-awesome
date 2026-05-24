/// Backlog command-area and detail-mode configuration helpers.
part of 'backlog_section.dart';

/// _BacklogDetailMode identifies the right-side backlog details view.
enum _BacklogDetailMode {
  /// Task and relation details.
  details,

  /// Selected task memory linking tools.
  memoryLinks,

  /// Screen-command review queue.
  aiReview,

  /// Task-fact stream projection.
  stream,

  /// Work-breakdown structure projection.
  wbs,

  /// Relationship-first task map.
  map,

  /// Task capture form.
  capture,
}

/// _BacklogAreaIds stores stable ids for backlog command areas.
abstract final class _BacklogAreaIds {
  /// Queue task list area.
  static const String queue = 'queue';
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
  ];
}

/// Returns the details modes available for the current backlog state.
List<CommandPanelDetailMode> _visibleBacklogDetailModes(
  AgentAwesomeAppController controller,
) {
  return <CommandPanelDetailMode>[
    _backlogDetailMode(_BacklogDetailMode.details),
    _backlogDetailMode(_BacklogDetailMode.memoryLinks),
    if (_backlogReviewAvailable(controller))
      _backlogDetailMode(_BacklogDetailMode.aiReview),
    _backlogDetailMode(_BacklogDetailMode.stream),
    _backlogDetailMode(_BacklogDetailMode.wbs),
    _backlogDetailMode(_BacklogDetailMode.map),
    _backlogDetailMode(_BacklogDetailMode.capture),
  ];
}

/// Reports whether there is an AI screen-command run worth reviewing.
bool _backlogReviewAvailable(AgentAwesomeAppController controller) {
  return controller.activeScreenCommandRun?.changes.isNotEmpty ?? false;
}

/// Returns the stable id for a backlog detail mode.
String _backlogDetailModeId(_BacklogDetailMode mode) {
  return switch (mode) {
    _BacklogDetailMode.details => 'details',
    _BacklogDetailMode.memoryLinks => 'memory_links',
    _BacklogDetailMode.aiReview => 'ai_review',
    _BacklogDetailMode.stream => 'stream',
    _BacklogDetailMode.wbs => 'wbs',
    _BacklogDetailMode.map => 'map',
    _BacklogDetailMode.capture => 'capture',
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
  if (id == _backlogDetailModeId(_BacklogDetailMode.stream)) {
    return _BacklogDetailMode.stream;
  }
  if (id == _backlogDetailModeId(_BacklogDetailMode.wbs)) {
    return _BacklogDetailMode.wbs;
  }
  if (id == _backlogDetailModeId(_BacklogDetailMode.map)) {
    return _BacklogDetailMode.map;
  }
  if (id == _backlogDetailModeId(_BacklogDetailMode.capture)) {
    return _BacklogDetailMode.capture;
  }
  return _BacklogDetailMode.details;
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
    _BacklogDetailMode.details => 'Details',
    _BacklogDetailMode.memoryLinks => 'Memory',
    _BacklogDetailMode.aiReview => 'Review',
    _BacklogDetailMode.stream => 'Stream',
    _BacklogDetailMode.wbs => 'WBS',
    _BacklogDetailMode.map => 'Map',
    _BacklogDetailMode.capture => 'Capture',
  };
}

/// Returns the icon for a backlog detail mode.
IconData _backlogDetailIcon(_BacklogDetailMode mode) {
  return switch (mode) {
    _BacklogDetailMode.details => Icons.info_outline,
    _BacklogDetailMode.memoryLinks => Icons.link_outlined,
    _BacklogDetailMode.aiReview => Icons.auto_awesome_outlined,
    _BacklogDetailMode.stream => Icons.waves_outlined,
    _BacklogDetailMode.wbs => Icons.account_tree_outlined,
    _BacklogDetailMode.map => Icons.hub_outlined,
    _BacklogDetailMode.capture => Icons.add_task_outlined,
  };
}
