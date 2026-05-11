/// Chat composer input widget.
part of 'agent_awesome_shell.dart';

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.sending,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSubmit;

  /// Builds the sticky same-thread composer for the chat timeline.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(18),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.softShadow,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Icon(Icons.chat_bubble_outline, color: colors.muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('chat-thread-composer'),
                  controller: controller,
                  enabled: !sending,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  style: TextStyle(color: colors.ink),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Message Agent Awesome in this chat...',
                    hintStyle: TextStyle(color: colors.muted),
                  ),
                  onSubmitted: (_) {
                    if (!sending) {
                      onSubmit();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: colors.green,
                    foregroundColor: Colors.white,
                    fixedSize: const Size(42, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: sending ? null : onSubmit,
                  icon: Icon(
                    sending ? Icons.hourglass_top : Icons.arrow_upward,
                  ),
                  tooltip: 'Send message',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
