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
}

/// _SidebarItem stores one app route shown in the left rail.
class _SidebarItem {
  /// Creates a navigation item.
  const _SidebarItem({
    required this.label,
    required this.section,
    required this.icon,
  });

  /// Display text.
  final String label;

  /// App section emitted when the item is selected.
  final String section;

  /// Material icon that matches the destination's command-panel purpose.
  final IconData icon;
}
