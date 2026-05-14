/// Command-panel detail pane widget.
part of 'panels.dart';

/// _CommandSubShellDetailPane renders detail mode tabs and content.
class _CommandSubShellDetailPane extends StatelessWidget {
  const _CommandSubShellDetailPane({
    required this.title,
    required this.modes,
    required this.selectedMode,
    required this.onModeSelected,
    required this.showHeader,
    required this.onTitleTap,
    required this.child,
  });

  final String title;
  final List<CommandPanelDetailMode> modes;
  final CommandPanelDetailMode selectedMode;
  final ValueChanged<CommandPanelDetailMode> onModeSelected;
  final bool showHeader;
  final VoidCallback? onTitleTap;
  final Widget child;

  /// Builds the detail column.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final collapseScope = SplitPaneCollapseScope.maybeOf(context);
    if (collapseScope?.collapsed ?? false) {
      return _CommandSubShellCollapsedPane(
        title: title,
        icon: selectedMode.icon,
        collapseScope: collapseScope!,
      );
    }
    return PanelSurface(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showHeader) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: PanelSectionLabel(title, onTap: onTitleTap),
                      ),
                      if (collapseScope != null)
                        PanelCollapseButton(
                          expanded: true,
                          direction: collapseScope.side.direction,
                          onPressed: collapseScope.onToggle,
                          expandedTooltip: 'Collapse details column',
                          collapsedTooltip: 'Expand details column',
                        ),
                    ],
                  ),
                  if (modes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    _CommandSubShellDetailTabs(
                      modes: modes,
                      selectedMode: selectedMode,
                      onSelected: onModeSelected,
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
          ],
          Expanded(child: PanelBodySurface(child: child)),
        ],
      ),
    );
  }
}
