/// Backlog compact graph row widget.
part of 'backlog_section.dart';

class _TaskGraphRow extends StatelessWidget {
  const _TaskGraphRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badges,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> badges;
  final List<Widget> actions;

  /// Builds a compact graph metadata row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ],
                if (badges.where((badge) => badge.isNotEmpty).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final badge in badges)
                          if (badge.isNotEmpty) _TaskBadge(label: badge),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          for (final action in actions) action,
        ],
      ),
    );
  }
}
