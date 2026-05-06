/// Provides the global command bar and quick-access menu for Aurora.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
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
  });

  /// Text controller for the global command input.
  final TextEditingController commandController;

  /// App state used to populate quick-access shortcuts.
  final AuroraAppController appController;

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

  @override
  State<CommandBar> createState() => _CommandBarState();
}

class _CommandBarState extends State<CommandBar> {
  static const double _height = 62;
  static const double _buttonSize = 62;

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
    return Container(
      height: _height,
      decoration: const BoxDecoration(
        color: AuroraColors.surface,
        border: Border(bottom: BorderSide(color: AuroraColors.border)),
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
                  controller: widget.commandController,
                  focusNode: _focusNode,
                  onTap: _showQuickAccessIfIdle,
                  onChanged: _handleCommandTextChanged,
                  onSubmitCommand: () => unawaited(_handleScreenCommand()),
                  onSubmitNewChat: () => unawaited(_handleNewChatWithText()),
                ),
              ),
            ),
          ),
          _CommandIconButton(
            icon: Icons.add,
            tooltip: 'New chat',
            size: _buttonSize,
            onTap: _handleNewChat,
          ),
          _CommandIconButton(
            icon: Icons.tune,
            tooltip: 'Settings',
            size: _buttonSize,
            onTap: _handleOpenSettings,
          ),
        ],
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

  /// Opens settings from the global bar.
  void _handleOpenSettings() {
    _clearProfilePathForNextChat();
    _removeQuickAccess();
    widget.onOpenSettings();
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
              offset: const Offset(0, _height),
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

  /// Returns the dropdown width matched to the command field.
  double _quickAccessWidth() {
    final renderObject = _fieldKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size.width;
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
                '${chat.profileLabel} • ${_commandBarTimestamp(chat.updatedAt)}',
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
          detail: _commandBarTimestamp(session.updatedAt),
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
      _workspaceAction(AppSections.workflows, Icons.radio_button_unchecked),
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

class _CommandInputFrame extends StatelessWidget {
  const _CommandInputFrame({
    required this.controller,
    required this.focusNode,
    required this.onTap,
    required this.onChanged,
    required this.onSubmitCommand,
    required this.onSubmitNewChat,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitCommand;
  final VoidCallback onSubmitNewChat;

  /// Builds the flat command input field.
  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      padding: const EdgeInsets.only(left: 22, right: 8),
      decoration: BoxDecoration(
        color: const Color(0xfffffcf8),
        border: const Border(right: BorderSide(color: AuroraColors.border)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.search, color: AuroraColors.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Shortcuts(
              shortcuts: <ShortcutActivator, Intent>{
                const SingleActivator(LogicalKeyboardKey.enter):
                    const _SubmitScreenCommandIntent(),
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    const _SubmitNewChatIntent(),
                const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    const _SubmitNewChatIntent(),
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
                  _SubmitNewChatIntent: CallbackAction<_SubmitNewChatIntent>(
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
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText:
                        'Command current screen, Ctrl/Shift+Enter for chat...',
                  ),
                  onTap: onTap,
                  onChanged: onChanged,
                  onSubmitted: (_) => onSubmitCommand(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Enter',
            style: TextStyle(
              color: AuroraColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: AuroraColors.coral,
              foregroundColor: Colors.white,
              fixedSize: const Size(46, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: onSubmitCommand,
            icon: const Icon(Icons.arrow_upward),
            tooltip:
                'Run screen command. Ctrl+Enter or Shift+Enter starts a new chat.',
          ),
        ],
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

class _CommandIconButton extends StatelessWidget {
  const _CommandIconButton({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final double size;
  final VoidCallback onTap;

  /// Builds a flat command bar icon button.
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: size,
          width: size,
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AuroraColors.border)),
          ),
          child: Icon(icon, color: AuroraColors.muted),
        ),
      ),
    );
  }
}

/// Formats a chat timestamp for dense command bar rows.
String _commandBarTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}
