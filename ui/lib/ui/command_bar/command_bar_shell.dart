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
    required this.onToggleAssistantChat,
    required this.onSelectHistoryChat,
    required this.onOpenSection,
    required this.onOpenSettingsSection,
    required this.onOpenSettings,
    required this.onOpenSetup,
    this.assistantChatEnabled = true,
  });

  /// Text controller for the global command input.
  final TextEditingController commandController;

  /// App state used to populate quick-access shortcuts.
  final AgentAwesomeAppController appController;

  /// Current screen context used by plain Enter commands.
  final CommandContext Function(String text) commandContext;

  /// Sends the current command input to the active screen.
  final Future<void> Function(CommandContext context) onSubmitScreenCommand;

  /// Sends the current command input into a new chat.
  final Future<void> Function() onSubmit;

  /// Toggles the auxiliary AI chat panel.
  final VoidCallback onToggleAssistantChat;

  /// Whether the auxiliary AI chat pane can be opened for the current screen.
  final bool assistantChatEnabled;

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
  bool _agentSwitching = false;
  bool _memorySwitching = false;

  /// Starts listening to controller-driven chrome state.
  @override
  void initState() {
    super.initState();
    widget.appController.addListener(_handleAppControllerChanged);
  }

  /// Cleans up quick-access overlay and text focus resources.
  @override
  void dispose() {
    widget.appController.removeListener(_handleAppControllerChanged);
    _removeQuickAccess();
    _focusNode.dispose();
    super.dispose();
  }

  /// Refreshes quick-access content when controller state changes upstream.
  @override
  void didUpdateWidget(covariant CommandBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appController != widget.appController) {
      oldWidget.appController.removeListener(_handleAppControllerChanged);
      widget.appController.addListener(_handleAppControllerChanged);
    }
    _scheduleQuickAccessRebuild();
  }

  /// Refreshes top-bar state when app settings or chrome state change.
  void _handleAppControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
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
        border: Border(
          bottom: BorderSide(
            color: colors.border,
            width: AgentAwesomeStrokeTokens.dividerWidth,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final actionCompact = constraints.maxWidth < 980;
          final roomy = constraints.maxWidth >= 1400;
          final actionGap = compact ? 8.0 : 10.0;
          final actions = <Widget>[
            _CommandAgentPicker(
              agents: _agentEntries(),
              activePath: widget.appController.defaultAgentConfigPath,
              compact: actionCompact,
              switching: _agentSwitching,
              size: _buttonSize,
              onChanged: _agentSwitching
                  ? null
                  : (path) => unawaited(_handleActiveAgentChanged(path)),
              onManageAgents: _handleManageAgents,
              onOpen: _handleExternalControlOpened,
            ),
            _CommandMemoryPicker(
              domains: _memoryEntries(),
              activeId: widget.appController.selectedMemoryDomainId,
              compact: actionCompact,
              switching: _memorySwitching,
              size: _buttonSize,
              onChanged: _memorySwitching
                  ? null
                  : (domainId) =>
                        unawaited(_handleMemoryDomainChanged(domainId)),
              onManageMemory: _handleManageMemory,
              onOpen: _handleExternalControlOpened,
            ),
            _CommandWorkspaceViewPicker(
              activeView: widget.appController.activeWorkspaceView,
              compact: actionCompact,
              size: _buttonSize,
              onChanged: (view) => unawaited(_handleWorkspaceViewChanged(view)),
              onOpen: _handleExternalControlOpened,
            ),
            _CommandChromeButton(
              icon: widget.appController.watchWorkspaceChangesEnabled
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              label: '',
              tooltip: widget.appController.watchWorkspaceChangesEnabled
                  ? 'Watching AI changes'
                  : 'AI changes stay in background',
              size: _buttonSize,
              onTap: () => unawaited(_handleWatchWorkspaceChangesToggle()),
            ),
            if (!compact && !widget.appController.gettingStartedCompleted)
              _SetupStatusButton(onTap: _handleOpenSetup),
            if (roomy) const _ThemeBadge(),
            _CommandChromeButton(
              icon: Icons.help_outline,
              label: '',
              tooltip: 'Help',
              size: _buttonSize,
              onTap: _handleOpenHelp,
            ),
            _CommandChromeButton(
              icon: Icons.chat_bubble_outline,
              label: '',
              tooltip: widget.assistantChatEnabled
                  ? 'AI chat'
                  : 'AI chat is unavailable in this view',
              size: _buttonSize,
              onTap: widget.assistantChatEnabled
                  ? _handleAssistantChatToggle
                  : null,
            ),
          ];
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
                for (final action in actions) ...<Widget>[
                  SizedBox(width: actionGap),
                  action,
                ],
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
    await widget.onSubmitScreenCommand(widget.commandContext(text));
  }

  /// Starts a chat from the global input and closes transient navigation.
  Future<void> _handleNewChatWithText() async {
    _removeQuickAccess();
    await widget.onSubmit();
  }

  /// Toggles the global auxiliary AI chat pane.
  void _handleAssistantChatToggle() {
    _removeQuickAccess();
    widget.onToggleAssistantChat();
  }

  /// Toggles whether screen AI opens side panels while applying changes.
  Future<void> _handleWatchWorkspaceChangesToggle() async {
    _removeQuickAccess();
    await widget.appController.setWatchWorkspaceChangesEnabled(
      !widget.appController.watchWorkspaceChangesEnabled,
    );
  }

  /// Opens the setup wizard from the app shell.
  void _handleOpenSetup() {
    _removeQuickAccess();
    widget.onOpenSetup();
  }

  /// Opens contextual help without leaving the app shell.
  void _handleOpenHelp() {
    _removeQuickAccess();
    final contextSnapshot = widget.commandContext('');
    final help = commandHelpContent(contextSnapshot);
    final uri = commandHelpUri(
      contextSnapshot,
      widget.appController.config.workspaceRoot,
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.agentAwesomeColors;
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Row(
            children: <Widget>[
              Icon(help.icon, color: colors.green),
              const SizedBox(width: 10),
              Flexible(child: Text(help.title)),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(help.message),
          ),
          actions: <Widget>[
            TextButton.icon(
              onPressed: () {
                unawaited(Clipboard.setData(ClipboardData(text: '$uri')));
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Documentation link copied'),
                    duration: Duration(milliseconds: 1200),
                  ),
                );
              },
              icon: const Icon(Icons.link_outlined),
              label: const Text('Copy docs link'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  /// Closes command-input affordances when another top-bar control opens.
  void _handleExternalControlOpened() {
    _focusNode.unfocus();
    _removeQuickAccess();
  }

  /// Switches the active agent from the top-bar picker.
  Future<void> _handleActiveAgentChanged(String agentPath) async {
    if (agentPath.trim().isEmpty ||
        agentPath == widget.appController.defaultAgentConfigPath ||
        _agentSwitching) {
      return;
    }
    _removeQuickAccess();
    setState(() {
      _agentSwitching = true;
    });
    try {
      await widget.appController.selectActiveAgentConfig(agentPath);
    } finally {
      if (mounted) {
        setState(() {
          _agentSwitching = false;
        });
      }
    }
  }

  /// Switches the default memory domain from the top-bar picker.
  Future<void> _handleMemoryDomainChanged(String domainId) async {
    if (domainId.trim().isEmpty ||
        domainId == widget.appController.selectedMemoryDomainId ||
        _memorySwitching) {
      return;
    }
    _removeQuickAccess();
    setState(() {
      _memorySwitching = true;
    });
    try {
      await widget.appController.selectDefaultMemoryDomain(domainId);
    } finally {
      if (mounted) {
        setState(() {
          _memorySwitching = false;
        });
      }
    }
  }

  /// Switches the active workspace view from the top-bar picker.
  Future<void> _handleWorkspaceViewChanged(String view) async {
    _removeQuickAccess();
    await widget.appController.selectWorkspaceView(view);
  }

  /// Opens agent authoring from point-of-use controls.
  void _handleManageAgents() {
    _removeQuickAccess();
    widget.onOpenSection(AppSections.automationAgents);
  }

  /// Opens memory settings from point-of-use controls.
  void _handleManageMemory() {
    _removeQuickAccess();
    widget.onOpenSettingsSection('Memory');
  }

  /// Opens the full chat workspace from recent-chat quick access.
  void _handleOpenAllChats() {
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
        title: 'Agents',
        icon: Icons.psychology_outlined,
        emptyLabel: 'No agents configured',
        actions: _agentActions(),
        linkLabel: 'Manage',
        onLinkTap: _handleManageAgents,
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

  /// Builds quick actions for configured agents.
  List<QuickAccessAction> _agentActions() {
    final agents = _agentEntries();
    return <QuickAccessAction>[
      for (final agent in agents)
        QuickAccessAction(
          label: agent.label,
          detail: _agentDetail(agent),
          icon: agent.path == widget.appController.defaultAgentConfigPath
              ? Icons.check_circle_outline
              : Icons.psychology_outlined,
          onTap: () => unawaited(_handleActiveAgentChanged(agent.path)),
        ),
    ];
  }

  /// Returns agent choices, including the loaded agent path when needed.
  List<ConfigFileEntry> _agentEntries() {
    if (widget.appController.availableAgentConfigs.isNotEmpty) {
      return widget.appController.availableAgentConfigs;
    }
    final path = widget.appController.runtimeProfile?.harness.agentConfigPath;
    if (path == null || path.trim().isEmpty) {
      return const <ConfigFileEntry>[];
    }
    return <ConfigFileEntry>[
      ConfigFileEntry(path: path, kind: ConfigFileKind.agent, assigned: true),
    ];
  }

  /// Returns selectable memory domains from the active service topology.
  List<McpServerRuntime> _memoryEntries() {
    return widget.appController.runtimeProfile?.memoryDomains
            .where((domain) => domain.enabled)
            .toList() ??
        const <McpServerRuntime>[];
  }

  /// Labels agent rows with active state.
  String _agentDetail(ConfigFileEntry agent) {
    if (agent.path == widget.appController.defaultAgentConfigPath ||
        agent.assigned) {
      return 'Active agent';
    }
    return agent.fileLabel;
  }

  /// Builds recent chat actions from the app history or active sessions.
  List<QuickAccessAction> _chatActions() {
    if (widget.appController.chatHistory.isNotEmpty) {
      return <QuickAccessAction>[
        for (final chat in widget.appController.chatHistory.take(4))
          QuickAccessAction(
            label: chat.title,
            detail:
                '${chat.agentLabel} / ${formatLocalMonthDayTime(chat.updatedAt)}',
            icon: chat.key == widget.appController.selectedChatKey
                ? Icons.check_circle_outline
                : Icons.chat_bubble_outline,
            onTap: () {
              _removeQuickAccess();
              widget.onSelectHistoryChat(chat.key);
            },
          ),
      ];
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
            _removeQuickAccess();
            widget.onSelectHistoryChat(session.id);
          },
        ),
    ];
  }

  /// Builds app settings navigation actions.
  List<QuickAccessAction> _settingsActions() {
    return <QuickAccessAction>[
      _settingsAction('App', Icons.app_settings_alt_outlined),
      _settingsAction('Models', Icons.memory_outlined),
      _settingsAction('Memory', Icons.account_tree_outlined),
    ];
  }

  /// Builds one settings navigation action.
  QuickAccessAction _settingsAction(String section, IconData icon) {
    return QuickAccessAction(
      label: section,
      detail: '',
      icon: icon,
      onTap: () {
        _removeQuickAccess();
        widget.onOpenSettingsSection(section);
      },
    );
  }
}

const String _helpRepositoryBaseUrl =
    'https://github.com/DougB-Code/agent-awesome/blob/main';

/// Returns the documentation URI for the current command context.
Uri commandHelpUri(CommandContext context, String workspaceRoot) {
  final target = _commandHelpTarget(context);
  final root = workspaceRoot.trim();
  if (root.isEmpty) {
    return _commandHelpWebUri(target);
  }
  final htmlPath = '$root/build/site/agent-awesome/0.1/${target.htmlPage}';
  if (File(htmlPath).existsSync()) {
    return Uri.file(htmlPath);
  }
  return _commandHelpWebUri(target);
}

/// Returns the repository-backed documentation URI for unbuilt local docs.
Uri _commandHelpWebUri(_CommandHelpTarget target) {
  return Uri.parse('$_helpRepositoryBaseUrl/${target.sourcePath}');
}

/// Returns concise in-app help for a command-bar context.
CommandHelpContent commandHelpContent(CommandContext context) {
  final section = context.section.trim();
  if (section == AppSections.chat) {
    return const CommandHelpContent(
      title: 'Chat Help',
      message:
          'Start or continue a conversation, then use the right-side modes to inspect memory, tasks, files, people, and runtime details for the selected chat.',
      icon: Icons.forum_outlined,
    );
  }
  if (section == AppSections.automationLaunchpad ||
      section == AppSections.automationRunbooks) {
    return const CommandHelpContent(
      title: 'Launchpad Help',
      message:
          'Use Launchpad to prepare, review, and run guided automations from configured runbooks.',
      icon: Icons.rocket_launch_outlined,
    );
  }
  if (section == AppSections.settings ||
      section == AppSections.automationAgents ||
      section == AppSections.automationMcpServers ||
      section == AppSections.automationTools) {
    return const CommandHelpContent(
      title: 'Configuration Help',
      message:
          'Use Details for artifact metadata, then switch modes to edit runtime behavior, validations, credentials, and operational surfaces.',
      icon: Icons.tune,
    );
  }
  return const CommandHelpContent(
    title: 'Agent Awesome Help',
    message:
        'Use the sidebar to choose a workspace, the command bar to act on the current screen, and chat when you want Agent Awesome to work through a conversation.',
    icon: Icons.help_outline,
  );
}

/// CommandHelpContent stores one contextual in-app help payload.
class CommandHelpContent {
  /// Creates command-bar help content.
  const CommandHelpContent({
    required this.title,
    required this.message,
    required this.icon,
  });

  /// Dialog title.
  final String title;

  /// Brief contextual guidance.
  final String message;

  /// Dialog icon.
  final IconData icon;
}

/// Returns the section-specific docs page nearest to the current UI context.
_CommandHelpTarget _commandHelpTarget(CommandContext context) {
  final section = context.section.trim();
  if (section == AppSections.chat) {
    return const _CommandHelpTarget(
      htmlPage: 'user/local-chat.html',
      sourcePath: 'docs/modules/user/pages/local-chat.adoc',
    );
  }
  if (section == AppSections.settings ||
      section == AppSections.automationAgents ||
      section == AppSections.automationMcpServers ||
      section == AppSections.automationTools) {
    return const _CommandHelpTarget(
      htmlPage: 'user/desktop-ui.html',
      sourcePath: 'docs/modules/user/pages/desktop-ui.adoc',
    );
  }
  if (section == AppSections.automationLaunchpad ||
      section == AppSections.automationRunbooks) {
    return const _CommandHelpTarget(
      htmlPage: 'launchpad/local-run.html',
      sourcePath: 'docs/modules/launchpad/pages/local-run.adoc',
    );
  }
  return const _CommandHelpTarget(
    htmlPage: 'user/index.html',
    sourcePath: 'docs/modules/user/pages/index.adoc',
  );
}

/// _CommandHelpTarget stores paired built and source documentation paths.
class _CommandHelpTarget {
  /// Creates one local documentation target.
  const _CommandHelpTarget({required this.htmlPage, required this.sourcePath});

  /// Built Antora HTML path under `build/site/agent-awesome/0.1`.
  final String htmlPage;

  /// Source documentation path under the workspace root.
  final String sourcePath;
}
