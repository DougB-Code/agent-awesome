/// Workspace chat timeline row widget.
part of 'workspace_widgets.dart';

/// ChatRow renders one chat timeline entry.
class ChatRow extends StatelessWidget {
  /// Creates one chat timeline row.
  const ChatRow({super.key, required this.message});

  /// Message to display.
  final ChatMessage message;

  /// Builds one chat timeline row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    if (message.role == ChatRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 20),
          constraints: const BoxConstraints(maxWidth: 640),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(36),
          ),
          child: _MessageText(message: message),
        ),
      );
    }
    if (message.role == ChatRole.tool) {
      return Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.extension_outlined, color: colors.green),
            const SizedBox(width: 12),
            Expanded(child: _MessageText(message: message)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 25,
            backgroundColor: colors.green,
            child: Icon(Icons.auto_awesome, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(child: _MessageText(message: message)),
        ],
      ),
    );
  }
}
