/// Empty-state panel widgets.
part of 'panels.dart';

class PanelEmptyState extends StatelessWidget {
  /// Creates a panel empty state for a search query.
  const PanelEmptyState({super.key, required this.query});

  /// Filter query that produced no results.
  final String query;

  /// Builds a compact empty state for filtered command panel content.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Center(
      child: Text(
        'No results for "$query"',
        style: TextStyle(color: colors.muted),
      ),
    );
  }
}

/// PanelGuidedEmptyBlock renders a shared visual no-data state.
class PanelGuidedEmptyBlock extends StatelessWidget {
  /// Creates a guided empty state with optional supporting copy.
  const PanelGuidedEmptyBlock({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
  });

  /// Empty-state icon.
  final IconData icon;

  /// Main empty-state title.
  final String title;

  /// Optional supporting empty-state message.
  final String message;

  /// Builds one quiet guided empty-state block.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final messageText = message.trim();
    return PanelSectionBlock(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: colors.muted, size: 34),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (messageText.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  messageText,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.muted, height: 1.35),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
