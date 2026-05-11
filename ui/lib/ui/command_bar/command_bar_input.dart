/// Global command input field and keyboard intents.
part of 'command_bar.dart';

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
