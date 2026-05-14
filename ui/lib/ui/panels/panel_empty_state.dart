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
