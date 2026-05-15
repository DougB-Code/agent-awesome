/// Command-panel area and detail-mode models.
part of 'panels.dart';

class SwitcherPanelArea {
  /// Creates a selectable panel area.
  const SwitcherPanelArea({
    required this.title,
    required this.icon,
    required this.builder,
    this.id = '',
  });

  /// Stable area id used by global command routing.
  final String id;

  /// Area title.
  final String title;

  /// Area icon.
  final IconData icon;

  /// Builds filtered area content.
  final Widget Function(String query) builder;
}

/// CommandPanelDetailMode describes one selectable detail panel mode.
class CommandPanelDetailMode {
  /// Creates a command-panel detail mode.
  const CommandPanelDetailMode({
    required this.id,
    required this.label,
    required this.icon,
  });

  /// Stable mode id.
  final String id;

  /// Visible detail mode label.
  final String label;

  /// Visible detail mode icon.
  final IconData icon;
}

/// CommandPanelAreaActionsBuilder builds trailing controls for a command area.
typedef CommandPanelAreaActionsBuilder =
    Widget? Function(BuildContext context, SwitcherPanelArea area);

/// CommandPanelDetailModesBuilder builds detail modes for the active area.
typedef CommandPanelDetailModesBuilder =
    List<CommandPanelDetailMode> Function(SwitcherPanelArea area);

/// CommandPanelSelectedDetailModeBuilder returns the selected mode per area.
typedef CommandPanelSelectedDetailModeBuilder =
    String Function(SwitcherPanelArea area);

/// CommandPanelAreaDetailBuilder builds detail content for an active area.
typedef CommandPanelAreaDetailBuilder =
    Widget Function(SwitcherPanelArea area, String modeId);

/// CommandPanelAreaDetailModeChanged reports area-scoped detail selection.
typedef CommandPanelAreaDetailModeChanged =
    void Function(SwitcherPanelArea area, String modeId);
