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
    return PanelEmptyBody(
      icon: Icons.search_off_outlined,
      label: 'No results for "$query"',
      message: 'Try another search or adjust the current filters.',
    );
  }
}

/// PanelEmptyBody fills a pane body so no-content copy stays centered.
class PanelEmptyBody extends StatelessWidget {
  /// Creates a vertically centered empty state for a whole pane body.
  const PanelEmptyBody({
    super.key,
    required this.label,
    this.icon = Icons.inbox_outlined,
    this.message = '',
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 24),
  });

  /// Empty-state title or combined title and instruction text.
  final String label;

  /// Icon representing the empty state.
  final IconData icon;

  /// Optional instruction text.
  final String message;

  /// Padding between pane edges and centered content.
  final EdgeInsetsGeometry padding;

  /// Builds a body-filling empty-state wrapper when height is bounded.
  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: PanelEmptyBlock(icon: icon, label: label, message: message),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight && constraints.maxHeight.isFinite) {
          return SizedBox.expand(child: content);
        }
        return content;
      },
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
    return PanelEmptyBody(icon: icon, label: title, message: message);
  }
}
