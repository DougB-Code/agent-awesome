/// Provides the top-level Aurora app frame and sidebar navigation.
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
  final AuroraAppController controller;

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
    return Row(
      children: <Widget>[
        _AppSidebar(
          selected: selectedSection,
          expanded: sidebarExpanded,
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
              Expanded(child: content),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppSidebar extends StatelessWidget {
  const _AppSidebar({
    required this.selected,
    required this.expanded,
    required this.onSelected,
    required this.onToggleExpanded,
  });

  final String selected;
  final bool expanded;
  final ValueChanged<String> onSelected;
  final VoidCallback onToggleExpanded;

  static const List<({String label, IconData icon})> _items =
      <({String label, IconData icon})>[
        (label: 'Today', icon: Icons.auto_awesome),
        (label: 'Chat', icon: Icons.forum_outlined),
        (label: 'Workflows', icon: Icons.radio_button_unchecked),
        (label: AppSections.backlog, icon: Icons.task_alt_outlined),
        (label: 'Memory', icon: Icons.chat_bubble_outline),
        (label: 'Files', icon: Icons.folder_outlined),
        (label: 'Timeline', icon: Icons.view_timeline_outlined),
        (label: 'People', icon: Icons.people_outline),
        (label: 'Settings', icon: Icons.settings_outlined),
      ];

  /// Builds the left navigation rail.
  @override
  Widget build(BuildContext context) {
    final compact = !expanded;
    return Container(
      width: expanded ? 292 : 92,
      color: const Color(0xfff5f0e6),
      padding: EdgeInsets.fromLTRB(26, 26, expanded ? 24 : 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SidebarHeader(
            expanded: expanded,
            onToggleExpanded: onToggleExpanded,
          ),
          SizedBox(height: compact ? 24 : 32),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                for (final item in _items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _NavButton(
                      label: item.label,
                      icon: item.icon,
                      selected: selected == item.label,
                      onTap: () => onSelected(item.label),
                      compact: compact,
                    ),
                  ),
              ],
            ),
          ),
          if (expanded) ...const <Widget>[SizedBox(height: 16), _ProfileTile()],
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.expanded,
    required this.onToggleExpanded,
  });

  final bool expanded;
  final VoidCallback onToggleExpanded;

  /// Builds the top sidebar logo row and expansion control.
  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return Align(
        alignment: Alignment.topCenter,
        child: PanelCollapseButton(
          expanded: expanded,
          onPressed: onToggleExpanded,
          expandedTooltip: 'Collapse sidebar',
          collapsedTooltip: 'Expand sidebar',
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Expanded(child: _AuroraLogo(compact: false)),
        PanelCollapseButton(
          expanded: expanded,
          onPressed: onToggleExpanded,
          expandedTooltip: 'Collapse sidebar',
          collapsedTooltip: 'Expand sidebar',
        ),
      ],
    );
  }
}

class _AuroraLogo extends StatelessWidget {
  const _AuroraLogo({required this.compact});

  final bool compact;

  /// Builds the Aurora mark and wordmark.
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: compact ? 'Aurora Personal Agent' : '',
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: <Widget>[
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xfffffbf1),
              border: Border.all(color: const Color(0xffb8a879)),
            ),
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    height: 28,
                    width: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xff8c7a45),
                        width: 2,
                      ),
                    ),
                  ),
                  const Positioned(
                    right: -3,
                    top: 5,
                    child: _LogoDot(color: AuroraColors.coral),
                  ),
                  const Positioned(
                    left: -2,
                    bottom: 0,
                    child: _LogoDot(color: AuroraColors.green),
                  ),
                ],
              ),
            ),
          ),
          if (!compact) ...const <Widget>[
            SizedBox(width: 14),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'AURORA',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 5,
                    ),
                  ),
                  Text(
                    'PERSONAL AGENT',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: AuroraColors.muted,
                      letterSpacing: 2.4,
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

class _LogoDot extends StatelessWidget {
  const _LogoDot({required this.color});

  final Color color;

  /// Builds a small brand dot.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox.square(dimension: 10),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  /// Builds one navigation item.
  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AuroraColors.green : AuroraColors.muted;
    return Tooltip(
      message: compact ? label : '',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 20,
            vertical: compact ? 13 : 15,
          ),
          decoration: BoxDecoration(
            color: selected ? AuroraColors.greenSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 20, color: foreground),
              if (!compact) ...<Widget>[
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AuroraColors.ink
                          : const Color(0xff514b43),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile();

  /// Builds the user account tile.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfff0eadf),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Row(
        children: <Widget>[
          CircleAvatar(backgroundColor: Color(0xffd69b88)),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Doug', style: TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  'Local pilot',
                  style: TextStyle(color: AuroraColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AuroraColors.muted),
        ],
      ),
    );
  }
}
