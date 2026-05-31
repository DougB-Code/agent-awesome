/// App shell sidebar navigation data models.
part of 'app_shell_frame.dart';

/// _SidebarGroup stores one labeled navigation group.
class _SidebarGroup {
  /// Creates a sidebar group with related navigation items.
  const _SidebarGroup({required this.title, required this.items});

  /// Group heading shown above the items.
  final String title;

  /// Navigation items in this group.
  final List<_SidebarItem> items;

  /// Returns a copy with selected values changed.
  _SidebarGroup copyWith({String? title, List<_SidebarItem>? items}) {
    return _SidebarGroup(
      title: title ?? this.title,
      items: items ?? this.items,
    );
  }
}

/// _SidebarItem stores one app route shown in the left rail.
class _SidebarItem {
  /// Creates a navigation item.
  const _SidebarItem({
    required this.label,
    required this.section,
    required this.icon,
    this.advanced = false,
  });

  /// Display text.
  final String label;

  /// App section emitted when the item is selected.
  final String section;

  /// Material icon that matches the destination's command-panel purpose.
  final IconData icon;

  /// Whether this route is visible only in Advanced mode.
  final bool advanced;
}

/// Maps plugin manifest icon names onto approved Material symbols.
IconData appPluginIconFor(String name) {
  return switch (name.trim().toLowerCase()) {
    'board' || 'kanban' || 'columns' => Icons.view_kanban_outlined,
    'calendar' || 'schedule' => Icons.calendar_month_outlined,
    'dashboard' => Icons.dashboard_outlined,
    'form' => Icons.dynamic_form_outlined,
    'list' || 'collection' => Icons.list_alt_outlined,
    'tool' => Icons.handyman_outlined,
    'integration' => Icons.extension_outlined,
    _ => Icons.apps_outlined,
  };
}
