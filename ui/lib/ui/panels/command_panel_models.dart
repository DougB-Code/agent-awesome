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

/// CommandPanelContentItem describes one selectable item inside a detail pane.
class CommandPanelContentItem {
  /// Creates detail-pane item metadata for shared shell selectors.
  const CommandPanelContentItem({
    required this.id,
    required this.label,
    required this.icon,
    this.detail = '',
    this.badge = '',
  });

  /// Stable item identifier.
  final String id;

  /// Display label.
  final String label;

  /// Display icon.
  final IconData icon;

  /// Optional supporting detail.
  final String detail;

  /// Optional status badge.
  final String badge;
}

/// CommandPanelFilterOption describes a shell-owned quick filter.
class CommandPanelFilterOption {
  /// Creates one command-pane quick filter option.
  const CommandPanelFilterOption({
    required this.id,
    required this.label,
    required this.icon,
    this.badge = '',
  });

  /// Stable filter id.
  final String id;

  /// Visible filter label.
  final String label;

  /// Visible filter icon.
  final IconData icon;

  /// Optional count or status text.
  final String badge;
}

/// CommandPanelAreaActionsBuilder builds trailing controls for a command area.
typedef CommandPanelAreaActionsBuilder =
    Widget? Function(BuildContext context, SwitcherPanelArea area);

/// CommandPanelAreaFiltersBuilder builds left-pane quick filters.
typedef CommandPanelAreaFiltersBuilder =
    List<CommandPanelFilterOption> Function(
      BuildContext context,
      SwitcherPanelArea area,
    );

/// CommandPanelSelectedAreaFilterBuilder resolves the active quick filter id.
typedef CommandPanelSelectedAreaFilterBuilder =
    String Function(SwitcherPanelArea area);

/// CommandPanelAreaFilterChanged reports left-pane quick-filter changes.
typedef CommandPanelAreaFilterChanged =
    void Function(SwitcherPanelArea area, String filterId);

/// CommandPanelAreaFilterHintBuilder resolves one command-area filter hint.
typedef CommandPanelAreaFilterHintBuilder =
    String Function(SwitcherPanelArea area);

/// CommandPanelDetailActionsBuilder builds trailing controls for detail modes.
typedef CommandPanelDetailActionsBuilder =
    Widget? Function(
      BuildContext context,
      SwitcherPanelArea area,
      CommandPanelDetailMode mode,
    );

/// CommandPanelDetailModesBuilder builds detail modes for the active area.
typedef CommandPanelDetailModesBuilder =
    List<CommandPanelDetailMode> Function(SwitcherPanelArea area);

/// CommandPanelSelectedDetailModeBuilder returns the selected mode per area.
typedef CommandPanelSelectedDetailModeBuilder =
    String Function(SwitcherPanelArea area);

/// CommandPanelAreaDetailBuilder builds detail content for an active area.
typedef CommandPanelAreaDetailBuilder =
    Widget Function(SwitcherPanelArea area, String modeId);

/// CommandPanelSearchableDetailBuilder builds detail content with shell search.
typedef CommandPanelSearchableDetailBuilder =
    Widget Function(SwitcherPanelArea area, String modeId, String query);

/// CommandPanelAreaDetailModeChanged reports area-scoped detail selection.
typedef CommandPanelAreaDetailModeChanged =
    void Function(SwitcherPanelArea area, String modeId);

/// CommandPanelDetailTabsBuilder returns tabs inside the active right mode.
typedef CommandPanelDetailTabsBuilder =
    List<ShellTab> Function(
      SwitcherPanelArea area,
      CommandPanelDetailMode mode,
    );

/// CommandPanelAreaTabbedDetailBuilder builds content for a mode/tab pair.
typedef CommandPanelAreaTabbedDetailBuilder =
    Widget Function(SwitcherPanelArea area, String modeId, String tabId);

/// CommandPanelDetailItemsBuilder builds selectable right-pane content items.
typedef CommandPanelDetailItemsBuilder =
    List<CommandPanelContentItem> Function(
      SwitcherPanelArea area,
      CommandPanelDetailMode mode,
    );

/// CommandPanelSelectedDetailItemBuilder resolves the selected right-pane item.
typedef CommandPanelSelectedDetailItemBuilder =
    String? Function(SwitcherPanelArea area, CommandPanelDetailMode mode);

/// CommandPanelDetailItemChanged reports right-pane item selection changes.
typedef CommandPanelDetailItemChanged =
    void Function(
      SwitcherPanelArea area,
      CommandPanelDetailMode mode,
      String itemId,
    );

/// CommandPanelDetailItemActionsBuilder builds item-level right-pane actions.
typedef CommandPanelDetailItemActionsBuilder =
    Widget? Function(
      BuildContext context,
      SwitcherPanelArea area,
      CommandPanelDetailMode mode,
      CommandPanelContentItem? item,
    );

/// CommandPanelItemDetailBuilder builds selected item content with search.
typedef CommandPanelItemDetailBuilder =
    Widget Function(
      SwitcherPanelArea area,
      String modeId,
      CommandPanelContentItem? item,
      String query,
    );

/// CommandPanelCompanionAreaBuilder returns a mode's preferred left area id.
typedef CommandPanelCompanionAreaBuilder = String Function(String modeId);

/// ShellArea is the canonical left-pane content area model.
typedef ShellArea = SwitcherPanelArea;

/// ShellMode is the canonical right-pane quick-access mode model.
typedef ShellMode = CommandPanelDetailMode;

/// ShellTab is the canonical right-pane labeled tab model.
typedef ShellTab = CommandPanelDetailMode;

/// ShellSplit is the canonical resizable content split model.
typedef ShellSplit = PanelSplit;
