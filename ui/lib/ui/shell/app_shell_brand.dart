/// App shell brand header and collapsed expand affordance widgets.
part of 'app_shell_frame.dart';

/// _AppBrandHeader renders the full-width top-left brand block.
class _AppBrandHeader extends StatelessWidget {
  /// Creates the brand block and sidebar collapse action.
  const _AppBrandHeader({
    required this.expanded,
    required this.onToggleExpanded,
  });

  final bool expanded;
  final VoidCallback onToggleExpanded;

  /// Builds the screenshot-style brand header.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.chrome,
        gradient: context.agentAwesomeChromeGradient,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: EdgeInsets.fromLTRB(expanded ? 24 : 14, 12, 14, 12),
      child: expanded
          ? Row(
              children: <Widget>[
                const Expanded(child: _AgentAwesomeLogo(compact: false)),
                PanelCollapseButton(
                  expanded: expanded,
                  onPressed: onToggleExpanded,
                  expandedTooltip: 'Collapse sidebar',
                  collapsedTooltip: 'Expand sidebar',
                ),
              ],
            )
          : Center(
              child: _CollapsedBrandExpandButton(onPressed: onToggleExpanded),
            ),
    );
  }
}

/// _CollapsedBrandExpandButton shows the app logo until hover reveals expand.
class _CollapsedBrandExpandButton extends StatefulWidget {
  /// Creates the collapsed sidebar expansion affordance.
  const _CollapsedBrandExpandButton({required this.onPressed});

  /// Expands the sidebar when the collapsed logo is clicked.
  final VoidCallback onPressed;

  @override
  State<_CollapsedBrandExpandButton> createState() =>
      _CollapsedBrandExpandButtonState();
}

class _CollapsedBrandExpandButtonState
    extends State<_CollapsedBrandExpandButton> {
  bool _hovered = false;

  /// Builds a logo button that swaps to the expand icon while hovered.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: 'Expand sidebar',
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: IconButton(
          key: const ValueKey<String>('collapsed-sidebar-logo-button'),
          alignment: Alignment.center,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 56, height: 56),
          onPressed: widget.onPressed,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            child: _hovered
                ? Icon(
                    Icons.keyboard_double_arrow_right,
                    key: const ValueKey<String>(
                      'collapsed-sidebar-expand-icon',
                    ),
                    color: colors.muted,
                    size: 22,
                  )
                : Image.asset(
                    'assets/images/agent-awesome-logo.png',
                    key: const ValueKey<String>('collapsed-sidebar-logo'),
                    height: 44,
                    width: 44,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) {
                      return const _LogoFallbackMark();
                    },
                  ),
          ),
        ),
      ),
    );
  }

  /// Updates hover state without rebuilding when the value is unchanged.
  void _setHovered(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() {
      _hovered = hovered;
    });
  }
}
