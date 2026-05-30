/// Provides reusable quick-access menu widgets for the command bar.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// QuickAccessGroup describes one quick-access menu column.
class QuickAccessGroup {
  /// Creates a grouped collection of quick-access actions.
  const QuickAccessGroup({
    required this.title,
    required this.icon,
    required this.actions,
    required this.emptyLabel,
    this.linkLabel = '',
    this.onLinkTap,
  });

  /// Column title.
  final String title;

  /// Column icon.
  final IconData icon;

  /// Selectable actions in this group.
  final List<QuickAccessAction> actions;

  /// Text shown when no actions are available.
  final String emptyLabel;

  /// Optional compact navigation label shown at the bottom of the column.
  final String linkLabel;

  /// Optional callback for the compact group-level navigation link.
  final VoidCallback? onLinkTap;
}

/// QuickAccessAction describes one executable quick-access row.
class QuickAccessAction {
  /// Creates one selectable quick-access action.
  const QuickAccessAction({
    required this.label,
    required this.detail,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  /// Primary action label.
  final String label;

  /// Optional supporting detail.
  final String detail;

  /// Leading action icon.
  final IconData icon;

  /// Callback invoked when the action is selected.
  final VoidCallback onTap;

  /// Whether the row can currently be selected.
  final bool enabled;
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

  static const double _compactColumnWidth = 220;
  static const double _wideColumnWidth = 320;

  /// Builds the global quick-access dropdown.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(
          color: colors.border,
          width: AgentAwesomeStrokeTokens.borderWidth,
        ),
        borderRadius: BorderRadius.circular(8),
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
                    final maxColumns = constraints.maxWidth < 860 ? 2 : 4;
                    final columnCount = groups.isEmpty
                        ? 1
                        : groups.length < maxColumns
                        ? groups.length
                        : maxColumns;
                    final spacing = columnCount == 2 ? 18.0 : 24.0;
                    final fallbackColumnWidth =
                        (constraints.maxWidth - spacing * (columnCount - 1)) /
                        columnCount;
                    final preferredWidths = <double>[
                      for (final group in groups) _preferredColumnWidth(group),
                    ];
                    final preferredTotal =
                        preferredWidths.fold<double>(
                          0,
                          (sum, width) => sum + width,
                        ) +
                        spacing * (preferredWidths.length - 1);
                    final usePreferredWidths =
                        constraints.maxWidth >= 860 &&
                        preferredTotal <= constraints.maxWidth;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        alignment: WrapAlignment.start,
                        runAlignment: WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.start,
                        spacing: spacing,
                        runSpacing: 18,
                        children: <Widget>[
                          for (var index = 0; index < groups.length; index++)
                            SizedBox(
                              width: usePreferredWidths
                                  ? preferredWidths[index]
                                  : fallbackColumnWidth
                                        .clamp(180.0, _wideColumnWidth)
                                        .toDouble(),
                              child: _QuickAccessColumn(group: groups[index]),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Divider(
              height: AgentAwesomeStrokeTokens.dividerWidth,
              thickness: AgentAwesomeStrokeTokens.dividerWidth,
              color: colors.border,
            ),
            _QuickAccessFooter(onViewSettings: onViewSettings),
          ],
        ),
      ),
    );
  }

  /// Estimates a stable quick-access column width from visible text.
  double _preferredColumnWidth(QuickAccessGroup group) {
    final maxTextLength = <int>[
      group.title.length,
      group.linkLabel.length,
      group.emptyLabel.length,
      for (final action in group.actions) action.label.length,
      for (final action in group.actions) action.detail.length,
    ].fold<int>(0, (max, length) => length > max ? length : max);
    final estimatedWidth = 56 + maxTextLength * 8.2;
    return estimatedWidth
        .clamp(_compactColumnWidth, _wideColumnWidth)
        .toDouble();
  }
}

class _QuickAccessColumn extends StatelessWidget {
  const _QuickAccessColumn({required this.group});

  final QuickAccessGroup group;

  /// Builds one grouped quick-access column.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final content = <Widget>[
      Row(
        children: <Widget>[
          Icon(group.icon, size: 16, color: colors.green),
          const SizedBox(width: 8),
          Expanded(child: _QuickAccessLabel(group.title.toUpperCase())),
        ],
      ),
      const SizedBox(height: 8),
    ];
    final link = group.linkLabel.isNotEmpty && group.onLinkTap != null
        ? _QuickAccessGroupLink(label: group.linkLabel, onTap: group.onLinkTap!)
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ...content,
        _QuickAccessActionList(group: group),
        ?link,
      ],
    );
  }
}

class _QuickAccessActionList extends StatelessWidget {
  const _QuickAccessActionList({required this.group});

  final QuickAccessGroup group;

  /// Builds the action rows within a quick-access group.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    if (group.actions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          group.emptyLabel,
          style: TextStyle(color: colors.muted, fontSize: 13),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final action in group.actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _QuickAccessItem(action: action),
          ),
      ],
    );
  }
}

class _QuickAccessGroupLink extends StatelessWidget {
  const _QuickAccessGroupLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  /// Builds a compact group-level quick-access link.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(left: 36),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 28),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: colors.green,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

class _QuickAccessItem extends StatelessWidget {
  const _QuickAccessItem({required this.action});

  final QuickAccessAction action;

  /// Builds one quick-access action row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: action.enabled ? action.onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(
              action.enabled ? action.icon : Icons.lock_outline,
              size: 18,
              color: action.enabled
                  ? colors.muted
                  : colors.muted.withValues(alpha: 0.52),
            ),
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
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: action.enabled
                          ? colors.ink
                          : colors.muted.withValues(alpha: 0.62),
                    ),
                  ),
                  if (action.detail.isNotEmpty)
                    Text(
                      action.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, fontSize: 12),
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
    final colors = context.agentAwesomeColors;
    return Text(
      text,
      style: TextStyle(
        color: colors.green,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 4,
      ),
    );
  }
}
