/// Global command bar shell, submission, and quick-access state.
part of 'command_bar.dart';

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
  bool _profileSwitching = false;
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
                _CommandChromeButton(
                  icon: Icons.add,
                  label: actionCompact ? '' : 'New chat',
                  tooltip: 'New chat',
                  size: _buttonSize,
                  onTap: _handleNewChat,
                ),
                SizedBox(width: compact ? 8 : 10),
                _CommandProfilePicker(
                  profiles: _profileEntries(),
                  activePath: widget.appController.runtimeProfilePath,
                  defaultPath: widget.appController.defaultChatProfilePath,
                  compact: actionCompact,
                  switching: _profileSwitching,
                  size: _buttonSize,
                  onChanged: _profileSwitching
                      ? null
                      : (path) => unawaited(_handleActiveProfileChanged(path)),
                  onManageProfiles: _handleManageProfiles,
                  onOpen: _handleExternalControlOpened,
                ),
                SizedBox(width: compact ? 8 : 10),
                if (!compact && !widget.appController.hasConfiguredModel)
                  _SetupStatusButton(onTap: _handleOpenSetup),
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

  /// Closes command-input affordances when another top-bar control opens.
  void _handleExternalControlOpened() {
    _focusNode.unfocus();
    _removeQuickAccess();
  }

  /// Switches the active runtime profile from the top-bar picker.
  Future<void> _handleActiveProfileChanged(String profilePath) async {
    if (profilePath.trim().isEmpty ||
        profilePath == widget.appController.runtimeProfilePath ||
        _profileSwitching) {
      return;
    }
    _clearProfilePathForNextChat();
    _removeQuickAccess();
    setState(() {
      _profileSwitching = true;
    });
    try {
      await widget.appController.loadRuntimeProfileFromPath(profilePath);
    } finally {
      if (mounted) {
        setState(() {
          _profileSwitching = false;
        });
      }
    }
  }

  /// Opens profile settings from point-of-use profile controls.
  void _handleManageProfiles() {
    _clearProfilePathForNextChat();
    _removeQuickAccess();
    widget.onOpenSettingsSection('Profiles');
  }

  /// Opens the full chat workspace from recent-chat quick access.
  void _handleOpenAllChats() {
    _clearProfilePathForNextChat();
    _removeQuickAccess();
    widget.onOpenSection(AppSections.chat);
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
        linkLabel: 'Manage',
        onLinkTap: _handleManageProfiles,
      ),
      QuickAccessGroup(
        title: 'Recent chats',
        icon: Icons.chat_bubble_outline,
        emptyLabel: 'No recent chats',
        actions: _chatActions(),
        linkLabel: 'All Chats',
        onLinkTap: _handleOpenAllChats,
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
