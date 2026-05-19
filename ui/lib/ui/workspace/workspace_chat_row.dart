/// Workspace chat timeline row widget.
part of 'workspace_widgets.dart';

/// ChatRow renders one chat timeline entry.
class ChatRow extends StatelessWidget {
  /// Creates one chat timeline row.
  const ChatRow({super.key, required this.message, this.compact = false});

  /// Message to display.
  final ChatMessage message;

  /// Whether the row is rendering inside a narrow side chat panel.
  final bool compact;

  /// Builds one chat timeline row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    if (message.role == ChatRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: EdgeInsets.only(bottom: compact ? 16 : 20),
          constraints: BoxConstraints(maxWidth: compact ? 360 : 640),
          padding: EdgeInsets.all(compact ? 18 : 24),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(compact ? 24 : 36),
          ),
          child: _MessageText(message: message, compact: compact),
        ),
      );
    }
    if (message.role == ChatRole.tool) {
      return Container(
        margin: EdgeInsets.only(bottom: compact ? 14 : 18),
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(compact ? 14 : 18),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.extension_outlined, color: colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: _MessageText(message: message, compact: compact),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 16 : 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: compact ? 20 : 25,
            backgroundColor: colors.green,
            child: Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: compact ? 20 : 24,
            ),
          ),
          SizedBox(width: compact ? 12 : 16),
          Expanded(
            child: _MessageText(message: message, compact: compact),
          ),
        ],
      ),
    );
  }
}
