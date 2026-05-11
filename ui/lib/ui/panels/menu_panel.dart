/// Menu and empty-state panel widgets.
part of 'panels.dart';

class PanelEmptyState extends StatelessWidget {
  /// Creates a panel empty state for a search query.
  const PanelEmptyState({super.key, required this.query});

  /// Filter query that produced no results.
  final String query;

  /// Builds a compact empty state for filtered command panel content.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Center(
      child: Text(
        'No results for "$query"',
        style: TextStyle(color: colors.muted),
      ),
    );
  }
}

/// MenuPanelItem describes one item in a reusable menu panel.
class MenuPanelItem {
  /// Creates a menu item for panel navigation.
  const MenuPanelItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.detail,
  });

  /// Stable selection key.
  final String key;

  /// Display label.
  final String label;

  /// Display icon.
  final IconData icon;

  /// Short supporting description.
  final String detail;
}

/// MenuPanel renders a vertical sub-navigation panel.
class MenuPanel extends StatelessWidget {
  /// Creates a reusable menu panel.
  const MenuPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.selectedKey,
    required this.onSelected,
  });

  /// Panel title.
  final String title;

  /// Supporting subtitle.
  final String subtitle;

  /// Menu items.
  final List<MenuPanelItem> items;

  /// Currently selected item key.
  final String selectedKey;

  /// Selection callback.
  final ValueChanged<String> onSelected;

  /// Builds the menu panel.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.displayMedium),
                const SizedBox(height: 8),
                Text(subtitle, style: TextStyle(color: colors.muted)),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                for (final item in items)
                  _MenuPanelTile(
                    item: item,
                    selected: selectedKey == item.key,
                    onTap: () => onSelected(item.key),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuPanelTile extends StatelessWidget {
  const _MenuPanelTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final MenuPanelItem item;
  final bool selected;
  final VoidCallback onTap;

  /// Builds one menu panel tile.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? colors.greenSoft : colors.surface,
            gradient: selected
                ? context.agentAwesomeSelectedGradient
                : context.agentAwesomeCardGradient,
            border: Border.all(color: selected ? colors.green : colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Icon(item.icon, color: selected ? colors.green : colors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.label,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
