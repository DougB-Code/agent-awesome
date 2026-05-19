/// Sticky row and column labels for the task stream canvas.
part of 'task_stream_canvas.dart';

/// _StreamRowLabel renders the sticky label for one stream row.
class _StreamRowLabel extends StatelessWidget {
  const _StreamRowLabel({required this.row});

  final TaskStreamRowLayout row;

  /// Builds the label and icon for one stream row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final tooltip = row.subtitle.isEmpty
        ? row.title
        : '${row.title}\n${row.subtitle}';
    return Tooltip(
      message: tooltip,
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: row.color.withValues(alpha: 0.14),
            child: Icon(row.icon, size: 17, color: row.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (row.subtitle.isNotEmpty)
                  Text(
                    row.subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// _StreamColumnHeader renders one sticky timeline heading.
class _StreamColumnHeader extends StatelessWidget {
  const _StreamColumnHeader({required this.column});

  final TaskStreamColumnLayout column;

  /// Builds a timeline column heading.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          column.title.toUpperCase(),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.subtle,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
        if (column.subtitle.isNotEmpty)
          Text(
            column.subtitle,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
      ],
    );
  }
}
