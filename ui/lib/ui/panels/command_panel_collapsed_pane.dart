/// Command-panel collapsed split-pane rail widget.
part of 'panels.dart';

/// _CommandSubShellCollapsedPane renders a collapsed split-pane rail.
class _CommandSubShellCollapsedPane extends StatelessWidget {
  const _CommandSubShellCollapsedPane({
    required this.title,
    required this.icon,
    required this.collapseScope,
  });

  final String title;
  final IconData icon;
  final SplitPaneCollapseScope collapseScope;

  /// Builds the compact collapsed column.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeSurfaceGradient,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          children: <Widget>[
            PanelCollapseButton(
              expanded: false,
              direction: collapseScope.side.direction,
              onPressed: collapseScope.onToggle,
              expandedTooltip: 'Collapse column',
              collapsedTooltip: 'Expand column',
            ),
            const SizedBox(height: 14),
            Icon(icon, size: 20, color: colors.green),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
