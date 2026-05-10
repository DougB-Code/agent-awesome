/// Provides the global command bar and quick-access menu for Agent Awesome.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/date_formatting.dart';
import '../shell/app_sections.dart';
import 'command_context.dart';
import 'quick_access_menu.dart';

/// CommandBar renders the app-wide chat command field and shortcut actions.
class CommandBar extends StatefulWidget {
  /// Creates a command bar bound to the app shell and controller.
  const CommandBar({
    super.key,
    required this.commandController,
    required this.appController,
    required this.commandContext,
    required this.onSubmitScreenCommand,
    required this.onSubmit,
    required this.onNewChat,
    required this.onStartChatWithProfile,
    required this.onSelectHistoryChat,
    required this.onOpenSection,
    required this.onOpenSettingsSection,
    required this.onOpenSettings,
    required this.onOpenSetup,
  });

  /// Text controller for the global command input.
  final TextEditingController commandController;

  /// App state used to populate quick-access shortcuts.
  final AgentAwesomeAppController appController;

  /// Current screen context used by plain Enter commands.
  final CommandContext Function(String text, {String profilePath})
  commandContext;

  /// Sends the current command input to the active screen.
  final Future<void> Function(CommandContext context) onSubmitScreenCommand;

  /// Sends the current command input into a new chat.
  final Future<void> Function({String profilePath}) onSubmit;

  /// Starts a blank default-profile chat.
  final VoidCallback onNewChat;

  /// Starts a blank chat with a chosen runtime profile.
  final ValueChanged<String> onStartChatWithProfile;

  /// Opens an existing saved chat.
  final ValueChanged<String> onSelectHistoryChat;

  /// Opens a top-level workspace section.
  final ValueChanged<String> onOpenSection;

  /// Opens a specific settings section.
  final ValueChanged<String> onOpenSettingsSection;

  /// Opens the settings workspace.
  final VoidCallback onOpenSettings;

  /// Reopens the first-run setup shell.
  final VoidCallback onOpenSetup;

  @override
  State<CommandBar> createState() => _CommandBarState();
}

class _CommandBarState extends State<CommandBar> {
  static const double _height = 84;
  static const double _fieldHeight = 42;
  static const double _buttonSize = 42;
  static const double _quickAccessGap = 8;
  static const double _horizontalPadding = 24;

  final FocusNode _focusNode = FocusNode();
  final GlobalKey _fieldKey = GlobalKey();
  final LayerLink _fieldLink = LayerLink();
  OverlayEntry? _quickAccessEntry;
  bool _quickAccessRebuildScheduled = false;
  String _profilePathForNextChat = '';

  /// Cleans up quick-access overlay and text focus resources.
  @override
  void dispose() {
    _removeQuickAccess();
    _focusNode.dispose();
    super.dispose();
  }

  /// Refreshes quick-access content when controller state changes upstream.
  @override
  void didUpdateWidget(covariant CommandBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleQuickAccessRebuild();
  }

  /// Builds the global command bar.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: colors.chrome,
        gradient: context.agentAwesomeChromeGradient,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final actionCompact = constraints.maxWidth < 980;
          final roomy = constraints.maxWidth >= 1400;
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : _horizontalPadding,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: CompositedTransformTarget(
                    link: _fieldLink,
                    child: GestureDetector(
                      key: _fieldKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: _showQuickAccessIfIdle,
                      child: _CommandInputFrame(
                        height: _fieldHeight,
                        controller: widget.commandController,
                        focusNode: _focusNode,
                        onTap: _showQuickAccessIfIdle,
                        onChanged: _handleCommandTextChanged,
                        onSubmitCommand: () =>
                            unawaited(_handleScreenCommand()),
                        onSubmitNewChat: () =>
                            unawaited(_handleNewChatWithText()),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: compact ? 10 : 16),
                if (!compact && !widget.appController.hasConfiguredModel)
                  _SetupStatusButton(onTap: _handleOpenSetup),
                _CommandChromeButton(
                  icon: Icons.add,
                  label: actionCompact ? '' : 'New chat',
                  tooltip: 'New chat',
                  size: _buttonSize,
                  onTap: _handleNewChat,
                ),
                if (roomy) ...const <Widget>[SizedBox(width: 8), _ThemeBadge()],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Sends the global input as a command for the current screen.
  Future<void> _handleScreenCommand() async {
    _removeQuickAccess();
    final text = widget.commandController.text;
    if (text.trim().isEmpty) {
      _showQuickAccess();
      return;
    }
    widget.commandController.clear();
    final profilePath = _consumeProfilePathForNextChat();
    await widget.onSubmitScreenCommand(
      widget.commandContext(text, profilePath: profilePath),
    );
  }

  /// Starts a chat from the global input and closes transient navigation.
  Future<void> _handleNewChatWithText() async {
    _removeQuickAccess();
    final profilePath = _consumeProfilePathForNextChat();
    await widget.onSubmit(profilePath: profilePath);
  }

  /// Starts an empty chat from the global bar.
  void _handleNewChat() {
    _removeQuickAccess();
    final profilePath = _consumeProfilePathForNextChat();
    if (profilePath.isEmpty) {
      widget.onNewChat();
      return;
    }
    widget.onStartChatWithProfile(profilePath);
  }

  /// Opens the setup wizard from the app shell.
  void _handleOpenSetup() {
    _clearProfilePathForNextChat();
    _removeQuickAccess();
    widget.onOpenSetup();
  }

  /// Opens quick access while the command input is not carrying a message.
  void _showQuickAccessIfIdle() {
    if (widget.commandController.text.trim().isEmpty) {
      _showQuickAccess();
    }
  }

  /// Hides quick access once the user starts composing a new chat message.
  void _handleCommandTextChanged(String value) {
    if (value.trim().isEmpty) {
      _showQuickAccess();
    } else {
      _removeQuickAccess();
    }
  }

  /// Inserts the quick-access dropdown under the global command field.
  void _showQuickAccess() {
    if (_quickAccessEntry != null) {
      _scheduleQuickAccessRebuild();
      return;
    }
    _quickAccessEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: <Widget>[
            Positioned.fill(
              top: _height,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeQuickAccess,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _fieldLink,
              showWhenUnlinked: false,
              offset: const Offset(0, _fieldHeight + _quickAccessGap),
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  width: _quickAccessWidth(),
                  child: QuickAccessMenu(
                    groups: _quickAccessGroups(),
                    onViewSettings: () {
                      _clearProfilePathForNextChat();
                      _removeQuickAccess();
                      widget.onOpenSettings();
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_quickAccessEntry!);
  }

  /// Removes the quick-access dropdown if it is visible.
  void _removeQuickAccess() {
    _quickAccessEntry?.remove();
    _quickAccessEntry = null;
    _quickAccessRebuildScheduled = false;
  }

  /// Refreshes the quick-access overlay after the current frame is stable.
  void _scheduleQuickAccessRebuild() {
    final entry = _quickAccessEntry;
    if (entry == null || _quickAccessRebuildScheduled) {
      return;
    }
    _quickAccessRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _quickAccessRebuildScheduled = false;
      if (!mounted || _quickAccessEntry != entry) {
        return;
      }
      entry.markNeedsBuild();
    });
  }

  /// Returns the dropdown width from the command field to the bar's right edge.
  double _quickAccessWidth() {
    final renderObject = _fieldKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final fieldLeft = renderObject.localToGlobal(Offset.zero).dx;
      final availableWidth = screenWidth - fieldLeft - _horizontalPadding;
      return availableWidth
          .clamp(renderObject.size.width, screenWidth)
          .toDouble();
    }
    return 720;
  }

  /// Builds grouped quick-access actions from live app state.
  List<QuickAccessGroup> _quickAccessGroups() {
    return <QuickAccessGroup>[
      QuickAccessGroup(
        title: 'Profiles',
        icon: Icons.manage_accounts_outlined,
        emptyLabel: 'No profiles configured',
        actions: _profileActions(),
      ),
      QuickAccessGroup(
        title: 'Recent chats',
        icon: Icons.chat_bubble_outline,
        emptyLabel: 'No recent chats',
        actions: _chatActions(),
      ),
      QuickAccessGroup(
        title: 'Workspaces',
        icon: Icons.dashboard_customize_outlined,
        emptyLabel: '',
        actions: _workspaceActions(),
      ),
      QuickAccessGroup(
        title: 'Settings',
        icon: Icons.tune,
        emptyLabel: '',
        actions: _settingsActions(),
      ),
    ];
  }

  /// Builds new-chat actions for configured runtime profiles.
  List<QuickAccessAction> _profileActions() {
    final profiles = _profileEntries();
    return <QuickAccessAction>[
      for (final profile in profiles)
        QuickAccessAction(
          label: profile.label,
          detail: _profileDetail(profile),
          icon: profile.path == _profilePathForNextChat || profile.active
              ? Icons.check_circle_outline
              : Icons.person_outline,
          onTap: () => _selectProfileForNextChat(profile.path),
        ),
    ];
  }

  /// Selects a profile for the next top-bar chat without closing quick access.
  void _selectProfileForNextChat(String profilePath) {
    setState(() {
      _profilePathForNextChat = profilePath;
    });
    _scheduleQuickAccessRebuild();
    _focusCommandInput();
  }

  /// Focuses the global chat input after selecting a profile.
  void _focusCommandInput() {
    if (!mounted) {
      return;
    }
    FocusScope.of(context).requestFocus(_focusNode);
  }

  /// Returns and clears the selected profile for the next top-bar chat.
  String _consumeProfilePathForNextChat() {
    final profilePath = _profilePathForNextChat;
    _clearProfilePathForNextChat();
    return profilePath;
  }

  /// Clears a staged profile when the next action is not a new chat.
  void _clearProfilePathForNextChat() {
    if (_profilePathForNextChat.isNotEmpty && mounted) {
      setState(() {
        _profilePathForNextChat = '';
      });
    }
  }

  /// Returns profile choices, including the loaded profile when needed.
  List<RuntimeProfileFileEntry> _profileEntries() {
    if (widget.appController.availableProfiles.isNotEmpty) {
      return widget.appController.availableProfiles;
    }
    final profile = widget.appController.runtimeProfile;
    if (profile == null || widget.appController.runtimeProfilePath.isEmpty) {
      return const <RuntimeProfileFileEntry>[];
    }
    return <RuntimeProfileFileEntry>[
      RuntimeProfileFileEntry(
        path: widget.appController.runtimeProfilePath,
        id: profile.id,
        label: profile.label,
        active: true,
      ),
    ];
  }

  /// Labels profile rows with default and active state.
  String _profileDetail(RuntimeProfileFileEntry profile) {
    if (profile.path == _profilePathForNextChat) {
      return 'Selected for new chat';
    }
    if (profile.path == widget.appController.defaultChatProfilePath) {
      return 'Default profile';
    }
    if (profile.active) {
      return 'Active profile';
    }
    return profile.id;
  }

  /// Builds recent chat actions from the app history or active sessions.
  List<QuickAccessAction> _chatActions() {
    if (widget.appController.chatHistory.isNotEmpty) {
      return <QuickAccessAction>[
        for (final chat in widget.appController.chatHistory.take(4))
          QuickAccessAction(
            label: chat.title,
            detail:
                '${chat.profileLabel} • ${formatLocalMonthDayTime(chat.updatedAt)}',
            icon: chat.key == widget.appController.selectedChatKey
                ? Icons.check_circle_outline
                : Icons.chat_bubble_outline,
            onTap: () {
              _clearProfilePathForNextChat();
              _removeQuickAccess();
              widget.onSelectHistoryChat(chat.key);
            },
          ),
      ];
    }
    if (widget.appController.runtimeProfilePath.isEmpty) {
      return const <QuickAccessAction>[];
    }
    return <QuickAccessAction>[
      for (final session in widget.appController.sessions.take(4))
        QuickAccessAction(
          label: session.title,
          detail: formatLocalMonthDayTime(session.updatedAt),
          icon: session.id == widget.appController.selectedSessionId
              ? Icons.check_circle_outline
              : Icons.chat_bubble_outline,
          onTap: () {
            _clearProfilePathForNextChat();
            _removeQuickAccess();
            widget.onSelectHistoryChat(
              '${widget.appController.runtimeProfilePath}::${session.id}',
            );
          },
        ),
    ];
  }

  /// Builds quick workspace navigation actions.
  List<QuickAccessAction> _workspaceActions() {
    return <QuickAccessAction>[
      _workspaceAction(AppSections.chat, Icons.forum_outlined),
      _workspaceAction(AppSections.backlog, Icons.task_alt_outlined),
      _workspaceAction(AppSections.memory, Icons.chat_bubble_outline),
    ];
  }

  /// Builds one workspace navigation action.
  QuickAccessAction _workspaceAction(String section, IconData icon) {
    return QuickAccessAction(
      label: section,
      detail: '',
      icon: icon,
      onTap: () {
        _clearProfilePathForNextChat();
        _removeQuickAccess();
        widget.onOpenSection(section);
      },
    );
  }

  /// Builds app settings navigation actions.
  List<QuickAccessAction> _settingsActions() {
    return <QuickAccessAction>[
      _settingsAction('App', Icons.app_settings_alt_outlined),
      _settingsAction('Profiles', Icons.manage_accounts_outlined),
      _settingsAction('Models', Icons.memory_outlined),
      _settingsAction('Tools', Icons.extension_outlined),
    ];
  }

  /// Builds one settings navigation action.
  QuickAccessAction _settingsAction(String section, IconData icon) {
    return QuickAccessAction(
      label: section,
      detail: '',
      icon: icon,
      onTap: () {
        _clearProfilePathForNextChat();
        _removeQuickAccess();
        widget.onOpenSettingsSection(section);
      },
    );
  }
}

class _SetupStatusButton extends StatelessWidget {
  /// Creates the setup status action.
  const _SetupStatusButton({required this.onTap});

  /// Opens the setup wizard.
  final VoidCallback onTap;

  /// Builds a prominent setup status action for incomplete model setup.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: 'Finish setup',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 42,
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: colors.warningSoft,
            border: Border.all(color: colors.warningBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, color: colors.warningText, size: 18),
              const SizedBox(width: 7),
              Text(
                'Setup incomplete',
                style: TextStyle(
                  color: colors.warningText,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandInputFrame extends StatelessWidget {
  const _CommandInputFrame({
    required this.height,
    required this.controller,
    required this.focusNode,
    required this.onTap,
    required this.onChanged,
    required this.onSubmitCommand,
    required this.onSubmitNewChat,
  });

  final double height;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitCommand;
  final VoidCallback onSubmitNewChat;

  /// Builds the flat command input field.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      height: height,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeControlGradient,
        border: Border.all(color: colors.searchBorder),
        borderRadius: BorderRadius.circular(8),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.softShadow,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 260;
          return Row(
            children: <Widget>[
              Icon(Icons.search, color: colors.muted, size: compact ? 20 : 22),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: Shortcuts(
                  shortcuts: <ShortcutActivator, Intent>{
                    const SingleActivator(LogicalKeyboardKey.enter):
                        const _SubmitScreenCommandIntent(),
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                    ): const _SubmitNewChatIntent(),
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      shift: true,
                    ): const _SubmitNewChatIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _SubmitScreenCommandIntent:
                          CallbackAction<_SubmitScreenCommandIntent>(
                            onInvoke: (_) {
                              onSubmitCommand();
                              return null;
                            },
                          ),
                      _SubmitNewChatIntent:
                          CallbackAction<_SubmitNewChatIntent>(
                            onInvoke: (_) {
                              onSubmitNewChat();
                              return null;
                            },
                          ),
                    },
                    child: TextField(
                      key: const ValueKey<String>('global-command-input'),
                      controller: controller,
                      focusNode: focusNode,
                      style: TextStyle(
                        fontSize: compact ? 15 : 16,
                        letterSpacing: 0,
                        color: colors.ink,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText:
                            'Command current screen, Ctrl/Shift+Enter for chat...',
                        hintStyle: TextStyle(
                          color: colors.muted,
                          fontSize: compact ? 15 : 16,
                        ),
                      ),
                      onTap: onTap,
                      onChanged: onChanged,
                      onSubmitted: (_) => onSubmitCommand(),
                    ),
                  ),
                ),
              ),
              if (!compact) ...<Widget>[
                const SizedBox(width: 10),
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: colors.kbdBackground,
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Center(
                    child: Text(
                      'Enter',
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Intent for plain Enter in the global command field.
class _SubmitScreenCommandIntent extends Intent {
  /// Creates the screen command intent.
  const _SubmitScreenCommandIntent();
}

/// Intent for Ctrl+Enter or Shift+Enter in the global command field.
class _SubmitNewChatIntent extends Intent {
  /// Creates the new-chat intent.
  const _SubmitNewChatIntent();
}

/// _CommandChromeButton renders one screenshot-style top-bar action.
class _CommandChromeButton extends StatelessWidget {
  /// Creates a rounded top-bar button.
  const _CommandChromeButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.size,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final double size;
  final VoidCallback? onTap;

  /// Builds a rounded command-bar action button.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final compact = label.isEmpty;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: size,
          width: compact ? size : 118,
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
          decoration: BoxDecoration(
            color: colors.surface,
            gradient: context.agentAwesomeControlGradient,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Icon(
                icon,
                size: 19,
                color: onTap == null
                    ? colors.muted.withValues(alpha: 0.45)
                    : colors.ink,
              ),
              if (!compact) ...<Widget>[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
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

/// _ThemeBadge toggles between the light and dark themes.
class _ThemeBadge extends StatelessWidget {
  /// Creates a theme toggle badge.
  const _ThemeBadge();

  /// Builds the active theme indicator.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final themeScope = AgentAwesomeThemeScope.maybeOf(context);
    final dark =
        themeScope?.isDark ?? Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: dark ? 'Switch to light theme' : 'Switch to dark theme',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: themeScope?.onToggleTheme,
        child: Container(
          height: 42,
          width: 118,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            gradient: context.agentAwesomeControlGradient,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                color: colors.ink,
                size: 19,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  dark ? 'Dark' : 'Light',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
