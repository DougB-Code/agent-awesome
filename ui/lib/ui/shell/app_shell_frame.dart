/// Provides the top-level Agent Awesome app frame and sidebar navigation.
library;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../command_bar/command_bar.dart';
import '../command_bar/command_context.dart';
import '../panels/panels.dart';
import 'app_sections.dart';

/// AppShellFrame lays out the persistent sidebar, command bar, and content.
class AppShellFrame extends StatelessWidget {
  /// Creates the app frame for the current workspace content.
  const AppShellFrame({
    super.key,
    required this.selectedSection,
    required this.controller,
    required this.commandController,
    required this.commandContext,
    required this.onSubmitScreenCommand,
    required this.sidebarExpanded,
    required this.onSelected,
    required this.onToggleSidebar,
    required this.onSubmit,
    required this.onNewChat,
    required this.onStartChatWithProfile,
    required this.onSelectHistoryChat,
    required this.onOpenSection,
    required this.onOpenSettingsSection,
    required this.onOpenSettings,
    required this.onOpenSetup,
    required this.content,
  });

  /// Currently selected sidebar section.
  final String selectedSection;

  /// Shared app controller for command-bar shortcuts.
  final AgentAwesomeAppController controller;

  /// Text controller for the global command input.
  final TextEditingController commandController;

  /// Builds the current screen command context.
  final CommandContext Function(String text, {String profilePath})
  commandContext;

  /// Sends text as a command for the current screen.
  final Future<void> Function(CommandContext context) onSubmitScreenCommand;

  /// Whether the sidebar is expanded.
  final bool sidebarExpanded;

  /// Sidebar section selection callback.
  final ValueChanged<String> onSelected;

  /// Sidebar expand/collapse callback.
  final VoidCallback onToggleSidebar;

  /// Sends the global command input into a new chat.
  final Future<void> Function({String profilePath}) onSubmit;

  /// Starts a blank default-profile chat.
  final VoidCallback onNewChat;

  /// Starts a blank chat with a selected runtime profile.
  final ValueChanged<String> onStartChatWithProfile;

  /// Opens a saved chat from quick access.
  final ValueChanged<String> onSelectHistoryChat;

  /// Opens a top-level app section.
  final ValueChanged<String> onOpenSection;

  /// Opens a specific settings section.
  final ValueChanged<String> onOpenSettingsSection;

  /// Opens the settings workspace.
  final VoidCallback onOpenSettings;

  /// Reopens the first-run setup shell.
  final VoidCallback onOpenSetup;

  /// Main workspace content.
  final Widget content;

  /// Builds the single app shell that owns navigation and panel placement.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final sidebarWidth = sidebarExpanded
        ? _AppSidebar.expandedWidth
        : _AppSidebar.compactWidth;
    return Row(
      children: <Widget>[
        _AppSidebarColumn(
          width: sidebarWidth,
          expanded: sidebarExpanded,
          selected: selectedSection,
          onSelected: onSelected,
          onToggleExpanded: onToggleSidebar,
        ),
        Expanded(
          child: Column(
            children: <Widget>[
              CommandBar(
                commandController: commandController,
                appController: controller,
                commandContext: commandContext,
                onSubmitScreenCommand: onSubmitScreenCommand,
                onSubmit: onSubmit,
                onNewChat: onNewChat,
                onStartChatWithProfile: onStartChatWithProfile,
                onSelectHistoryChat: onSelectHistoryChat,
                onOpenSection: onOpenSection,
                onOpenSettingsSection: onOpenSettingsSection,
                onOpenSettings: onOpenSettings,
                onOpenSetup: onOpenSetup,
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.page,
                    gradient: context.agentAwesomeWorkspaceGradient,
                  ),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
        border: Border(right: BorderSide(color: colors.border)),
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
          iconGlyph: '⌂',
        ),
        _SidebarItem(
          label: AppSections.chat,
          section: AppSections.chat,
          iconGlyph: '↗',
        ),
        _SidebarItem(
          label: AppSections.backlog,
          section: AppSections.backlog,
          iconGlyph: '▤',
          showsChevron: true,
        ),
      ],
    ),
    _SidebarGroup(
      title: 'KNOWLEDGE',
      items: <_SidebarItem>[
        _SidebarItem(
          label: AppSections.memory,
          section: AppSections.memory,
          iconGlyph: '◌',
          showsChevron: true,
        ),
        _SidebarItem(
          label: AppSections.files,
          section: AppSections.files,
          iconGlyph: '▷',
          showsChevron: true,
        ),
        _SidebarItem(
          label: AppSections.people,
          section: AppSections.people,
          iconGlyph: '□',
          showsChevron: true,
        ),
      ],
    ),
    _SidebarGroup(
      title: 'SYSTEM',
      items: <_SidebarItem>[
        _SidebarItem(
          label: AppSections.settings,
          section: AppSections.settings,
          iconGlyph: '↯',
          showsChevron: true,
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
    required this.iconGlyph,
    this.showsChevron = false,
  });

  /// Display text.
  final String label;

  /// App section emitted when the item is selected.
  final String section;

  /// Leading glyph copied from the documentation nav.
  final String iconGlyph;

  /// Whether the row shows a nested-section chevron.
  final bool showsChevron;
}

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
                label: item.label,
                iconGlyph: item.iconGlyph,
                selected: selected == item.section,
                onTap: () => onSelected(item.section),
                compact: compact,
                showsChevron: item.showsChevron,
              ),
            ),
        ],
      ),
    );
  }
}

/// _AgentAwesomeLogo renders the brand mark and wordmark.
class _AgentAwesomeLogo extends StatelessWidget {
  /// Creates a compact or expanded brand treatment.
  const _AgentAwesomeLogo({required this.compact});

  final bool compact;

  /// Builds the Agent Awesome mark and wordmark.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: compact ? 'Agent Awesome Personal Agent' : '',
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: <Widget>[
          Image.asset(
            'assets/images/agent-awesome-logo.png',
            height: 44,
            width: 44,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) {
              return const _LogoFallbackMark();
            },
          ),
          if (!compact) ...<Widget>[
            const SizedBox(width: 15),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'AGENT',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: 4.96,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'AWESOME',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: 4.96,
                      color: colors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// _LogoFallbackMark keeps the app usable if bundled assets fail to load.
class _LogoFallbackMark extends StatelessWidget {
  /// Creates a compact fallback mark.
  const _LogoFallbackMark();

  /// Builds a simple fallback mark for tests and asset failures.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final gradient = context.agentAwesomePrimaryGradient;
    return Container(
      height: 58,
      width: 58,
      decoration: BoxDecoration(
        color: gradient == null ? colors.green : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Text(
          'AA',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// _NavButton renders one selectable sidebar route.
class _NavButton extends StatelessWidget {
  /// Creates a navigation button for one app route.
  const _NavButton({
    required this.label,
    required this.iconGlyph,
    required this.selected,
    required this.onTap,
    required this.compact,
    required this.showsChevron,
  });

  final String label;
  final String iconGlyph;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final bool showsChevron;

  /// Builds one navigation item.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final selectedGradient = selected
        ? context.agentAwesomeSelectedGradient
        : null;
    final foreground = selected ? colors.ink : colors.muted;
    return Tooltip(
      message: compact ? label : '',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 38),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 10,
            vertical: compact ? 8 : 7,
          ),
          decoration: BoxDecoration(
            color: selectedGradient == null
                ? selected
                      ? colors.greenSoft
                      : Colors.transparent
                : null,
            gradient: selectedGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 22,
                child: Text(
                  iconGlyph,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
              if (!compact) ...<Widget>[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0,
                      height: 1.25,
                      color: foreground,
                    ),
                  ),
                ),
                if (showsChevron) const SizedBox(width: 8),
                if (showsChevron) ...<Widget>[
                  Text(
                    '›',
                    style: TextStyle(
                      color: colors.subtle,
                      fontSize: 19,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
