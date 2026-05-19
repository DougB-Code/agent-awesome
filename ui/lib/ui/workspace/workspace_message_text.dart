/// Workspace chat message text and copy controls.
part of 'workspace_widgets.dart';

class _MessageText extends StatelessWidget {
  const _MessageText({required this.message, this.compact = false});

  final ChatMessage message;
  final bool compact;

  /// Builds message author and text.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: message.author,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: colors.ink,
                            ),
                          ),
                          TextSpan(
                            text: '  $time',
                            style: TextStyle(color: colors.muted),
                          ),
                          if (message.modelRef.trim().isNotEmpty)
                            TextSpan(
                              text: '  ${message.modelRef}',
                              style: TextStyle(color: colors.muted),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _CopyMessageButton(text: message.text),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          message.text,
          style: TextStyle(
            color: colors.ink,
            fontSize: compact ? 15 : 16,
            height: compact ? 1.45 : 1.55,
          ),
        ),
      ],
    );
  }
}

class _CopyMessageButton extends StatelessWidget {
  const _CopyMessageButton({required this.text});

  final String text;

  /// Builds a compact control for copying one chat message.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: 'Copy message',
      child: IconButton(
        onPressed: () {
          unawaited(Clipboard.setData(ClipboardData(text: text)));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied'),
              duration: Duration(milliseconds: 900),
            ),
          );
        },
        icon: const Icon(Icons.copy_outlined),
        color: colors.muted,
        iconSize: 15,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        visualDensity: VisualDensity.compact,
        splashRadius: 16,
      ),
    );
  }
}
