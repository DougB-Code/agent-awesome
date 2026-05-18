/// App shell sidebar group rendering widget.
part of 'app_shell_frame.dart';

/// _SidebarGroupView renders one grouped set of sidebar links.
class _SidebarGroupView extends StatelessWidget {
  /// Creates a rendered sidebar group.
  const _SidebarGroupView({
    required this.group,
    required this.selected,
    required this.compact,
    required this.onSelected,
  });

  /// Group data to render.
  final _SidebarGroup group;

  /// Currently selected section id.
  final String selected;

  /// Whether the sidebar is icon-only.
  final bool compact;

  /// Emits section ids when a row is selected.
  final ValueChanged<String> onSelected;

  /// Builds a grouped navigation section.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 14 : 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                group.title,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: 0.92,
                ),
              ),
            ),
          for (final item in group.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _NavButton(
                key: ValueKey<String>('sidebar-${item.section}'),
                label: item.label,
                iconGlyph: item.iconGlyph,
                selected: selected == item.section,
                onTap: () => onSelected(item.section),
                compact: compact,
              ),
            ),
        ],
      ),
    );
  }
}
