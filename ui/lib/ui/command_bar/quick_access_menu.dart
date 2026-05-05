/// Provides reusable quick-access menu widgets for the command bar.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// QuickAccessGroup describes one quick-access menu column.
class QuickAccessGroup {
  /// Creates a grouped collection of quick-access actions.
  const QuickAccessGroup({
    required this.title,
    required this.icon,
    required this.actions,
    required this.emptyLabel,
  });

  /// Column title.
  final String title;

  /// Column icon.
  final IconData icon;

  /// Selectable actions in this group.
  final List<QuickAccessAction> actions;

  /// Text shown when no actions are available.
  final String emptyLabel;
}

/// QuickAccessAction describes one executable quick-access row.
class QuickAccessAction {
  /// Creates one selectable quick-access action.
  const QuickAccessAction({
    required this.label,
    required this.detail,
    required this.icon,
    required this.onTap,
  });

  /// Primary action label.
  final String label;

  /// Optional supporting detail.
  final String detail;

  /// Leading action icon.
  final IconData icon;

  /// Callback invoked when the action is selected.
  final VoidCallback onTap;
}

/// QuickAccessMenu renders global shortcuts under the command bar.
class QuickAccessMenu extends StatelessWidget {
  /// Creates a menu from grouped actions.
  const QuickAccessMenu({
    super.key,
    required this.groups,
    required this.onViewSettings,
  });

  /// Grouped action columns.
  final List<QuickAccessGroup> groups;

  /// Opens the settings workspace from the menu footer.
  final VoidCallback onViewSettings;

  /// Builds the global quick-access dropdown.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AuroraColors.surface,
        border: Border.all(color: AuroraColors.border),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33453421),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columnCount = constraints.maxWidth < 860 ? 2 : 4;
                    final spacing = columnCount == 2 ? 18.0 : 24.0;
                    final columnWidth =
                        (constraints.maxWidth - spacing * (columnCount - 1)) /
                        columnCount;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: 18,
                      children: <Widget>[
                        for (final group in groups)
                          SizedBox(
                            width: columnWidth.clamp(180.0, 320.0).toDouble(),
                            child: _QuickAccessColumn(group: group),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const Divider(height: 1, color: AuroraColors.border),
            _QuickAccessFooter(onViewSettings: onViewSettings),
          ],
        ),
      ),
    );
  }
}

class _QuickAccessColumn extends StatelessWidget {
  const _QuickAccessColumn({required this.group});

  final QuickAccessGroup group;

  /// Builds one grouped quick-access column.
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(group.icon, size: 16, color: AuroraColors.green),
            const SizedBox(width: 8),
            Expanded(child: _QuickAccessLabel(group.title.toUpperCase())),
          ],
        ),
        const SizedBox(height: 8),
        if (group.actions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              group.emptyLabel,
              style: const TextStyle(color: AuroraColors.muted, fontSize: 13),
            ),
          )
        else
          for (final action in group.actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _QuickAccessItem(action: action),
            ),
      ],
    );
  }
}

class _QuickAccessItem extends StatelessWidget {
  const _QuickAccessItem({required this.action});

  final QuickAccessAction action;

  /// Builds one quick-access action row.
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: action.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(action.icon, size: 18, color: AuroraColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (action.detail.isNotEmpty)
                    Text(
                      action.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AuroraColors.muted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAccessFooter extends StatelessWidget {
  const _QuickAccessFooter({required this.onViewSettings});

  final VoidCallback onViewSettings;

  /// Builds the quick-access footer action.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onViewSettings,
          icon: const Icon(Icons.chevron_right, size: 18),
          label: const Text('View all settings'),
        ),
      ),
    );
  }
}

class _QuickAccessLabel extends StatelessWidget {
  const _QuickAccessLabel(this.text);

  final String text;

  /// Builds a compact uppercase quick-access label.
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AuroraColors.green,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 4,
      ),
    );
  }
}
