/// App shell sidebar column and grouped navigation widget.
part of 'app_shell_frame.dart';

/// _AppSidebarColumn keeps the logo and navigation in one left rail.
class _AppSidebarColumn extends StatelessWidget {
  /// Creates a full-height sidebar column with one continuous divider.
  const _AppSidebarColumn({
    required this.width,
    required this.expanded,
    required this.selected,
    required this.onSelected,
    required this.onToggleExpanded,
  });

  /// Width of the sidebar column.
  final double width;

  /// Whether the sidebar shows labels or compact icons.
  final bool expanded;

  /// Currently selected section id.
  final String selected;

  /// Emits section ids when a navigation item is selected.
  final ValueChanged<String> onSelected;

  /// Expands or collapses the sidebar.
  final VoidCallback onToggleExpanded;

  /// Builds the two-part left column as one structural frame.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      width: width,
      foregroundDecoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: colors.border,
            width: AgentAwesomeStrokeTokens.dividerWidth,
          ),
        ),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 84,
            child: _AppBrandHeader(
              expanded: expanded,
              onToggleExpanded: onToggleExpanded,
            ),
          ),
          Expanded(
            child: _AppSidebar(
              selected: selected,
              expanded: expanded,
              onSelected: onSelected,
            ),
          ),
        ],
      ),
    );
  }
}

/// _AppSidebar renders the grouped documentation-style navigation rail.
class _AppSidebar extends StatelessWidget {
  /// Creates the grouped sidebar for the current shell state.
  const _AppSidebar({
    required this.selected,
    required this.expanded,
    required this.onSelected,
  });

  /// Width used by the documentation-style expanded navigation.
  static const double expandedWidth = 352;

  /// Width used by collapsed icon-only navigation.
  static const double compactWidth = 84;

  final String selected;
  final bool expanded;
  final ValueChanged<String> onSelected;

  static const List<_SidebarGroup> _groups = <_SidebarGroup>[
    _SidebarGroup(
      title: 'HOME & CHAT',
      items: <_SidebarItem>[
        _SidebarItem(
          label: AppSections.today,
          section: AppSections.today,
          icon: Icons.today_outlined,
        ),
        _SidebarItem(
          label: AppSections.chat,
          section: AppSections.chat,
          icon: Icons.chat_bubble_outline,
        ),
        _SidebarItem(
          label: AppSections.backlog,
          section: AppSections.backlog,
          icon: Icons.task_alt_outlined,
        ),
      ],
    ),
    _SidebarGroup(
      title: 'AUTOMATIONS',
      items: <_SidebarItem>[
        _SidebarItem(
          label: AppSections.automationOperations,
          section: AppSections.automationOperations,
          icon: Icons.monitor_heart_outlined,
        ),
        _SidebarItem(
          label: AppSections.automationWorkflows,
          section: AppSections.automationWorkflows,
          icon: Icons.route_outlined,
        ),
        _SidebarItem(
          label: AppSections.automationAgents,
          section: AppSections.automationAgents,
          icon: Icons.psychology_outlined,
        ),
        _SidebarItem(
          label: AppSections.automationMcpServers,
          section: AppSections.automationMcpServers,
          icon: Icons.hub_outlined,
        ),
        _SidebarItem(
          label: AppSections.automationTools,
          section: AppSections.automationTools,
          icon: Icons.terminal,
        ),
      ],
    ),
    _SidebarGroup(
      title: 'KNOWLEDGE',
      items: <_SidebarItem>[
        _SidebarItem(
          label: AppSections.memory,
          section: AppSections.memory,
          icon: Icons.account_tree_outlined,
        ),
        _SidebarItem(
          label: AppSections.files,
          section: AppSections.files,
          icon: Icons.folder_outlined,
        ),
        _SidebarItem(
          label: AppSections.people,
          section: AppSections.people,
          icon: Icons.people_alt_outlined,
        ),
      ],
    ),
    _SidebarGroup(
      title: 'SYSTEM',
      items: <_SidebarItem>[
        _SidebarItem(
          label: AppSections.settings,
          section: AppSections.settings,
          icon: Icons.tune,
        ),
      ],
    ),
  ];

  /// Builds the left navigation rail.
  @override
  Widget build(BuildContext context) {
    final compact = !expanded;
    final colors = context.agentAwesomeColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.sidebar,
        gradient: context.agentAwesomeSidebarGradient,
      ),
      padding: EdgeInsets.fromLTRB(14, 24, expanded ? 14 : 12, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                for (final group in _groups)
                  _SidebarGroupView(
                    group: group,
                    selected: selected,
                    compact: compact,
                    onSelected: onSelected,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
