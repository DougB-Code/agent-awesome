/// Home workspace path grid and path card widgets.
part of 'workspace_widgets.dart';

/// _PathGrid renders the path cards under the hero.
class _PathGrid extends StatelessWidget {
  /// Creates the path grid.
  const _PathGrid({required this.onOpenSection});

  /// Opens a workspace section from a path card.
  final ValueChanged<String>? onOpenSection;

  /// Builds responsive path cards.
  @override
  Widget build(BuildContext context) {
    const paths = <_PathCardData>[
      _PathCardData(
        title: 'Daily Console',
        detail: 'Review status, live work, and assistant activity.',
        icon: Icons.dashboard_customize_outlined,
        section: AppSections.today,
      ),
      _PathCardData(
        title: 'Conversation Builder',
        detail: 'Start or continue a run with a configured profile.',
        icon: Icons.forum_outlined,
        section: AppSections.chat,
      ),
      _PathCardData(
        title: 'Task Stream',
        detail: 'Shape backlog work into queue, stream, and terrain views.',
        icon: Icons.task_alt_outlined,
        section: AppSections.backlog,
      ),
      _PathCardData(
        title: 'Memory Map',
        detail: 'Inspect context, entities, timelines, and remembered facts.',
        icon: Icons.hub_outlined,
        section: AppSections.memory,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 4
            : constraints.maxWidth >= 700
            ? 2
            : 1;
        final spacing = 20.0;
        final cardWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final path in paths)
              SizedBox(
                width: cardWidth,
                child: _PathCard(
                  data: path,
                  onTap: onOpenSection == null
                      ? null
                      : () => onOpenSection!(path.section),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// _PathCardData stores one home path card.
class _PathCardData {
  /// Creates path-card content.
  const _PathCardData({
    required this.title,
    required this.detail,
    required this.icon,
    required this.section,
  });

  /// Card title.
  final String title;

  /// Card supporting text.
  final String detail;

  /// Card icon.
  final IconData icon;

  /// Section opened from the card.
  final String section;
}

/// _PathCard renders one selectable home path.
class _PathCard extends StatelessWidget {
  /// Creates a path card.
  const _PathCard({required this.data, required this.onTap});

  /// Card content.
  final _PathCardData data;

  /// Selection callback.
  final VoidCallback? onTap;

  /// Builds one path card.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 158),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: colors.cardIconBackground,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(data.icon, color: colors.cardIcon, size: 24),
            ),
            const SizedBox(height: 18),
            Text(
              data.title,
              style: TextStyle(
                color: colors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data.detail,
              style: TextStyle(
                color: colors.muted,
                height: 1.45,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
