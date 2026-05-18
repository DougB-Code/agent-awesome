/// Interactive task cards and continuation markers for the task stream canvas.
part of 'task_stream_canvas.dart';

/// _StreamTaskCard renders one interactive task node.
class _StreamTaskCard extends StatelessWidget {
  const _StreamTaskCard({
    required this.placement,
    required this.selected,
    required this.focused,
    required this.faded,
    required this.compact,
    required this.onTap,
  });

  final TaskStreamCardPlacement placement;
  final bool selected;
  final bool focused;
  final bool faded;
  final bool compact;
  final VoidCallback onTap;

  /// Builds one selectable task card over the painted stream.
  @override
  Widget build(BuildContext context) {
    final card = placement.card;
    final row = placement.row;
    final colors = context.agentAwesomeColors;
    final emphasized = selected || focused;
    final borderColor = emphasized ? colors.borderStrong : row.color;
    return Tooltip(
      message: card.explanation,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: faded ? 0.24 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: emphasized ? colors.panelStrong : colors.surface,
              gradient: context.agentAwesomeCardGradient,
              border: Border.all(color: borderColor, width: emphasized ? 2 : 1),
              borderRadius: BorderRadius.circular(8),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  blurRadius: emphasized ? 16 : 12,
                  offset: const Offset(0, 4),
                  color: row.color.withValues(alpha: emphasized ? 0.16 : 0.1),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                Icon(_cardIcon(card), color: row.color, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        card.title,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _cardSubtitle(card),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (card.priority == 'urgent') ...<Widget>[
                  const SizedBox(width: 6),
                  const _StreamUrgentDot(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// _StreamContinuationMarker renders a non-interactive future-work endpoint.
class _StreamContinuationMarker extends StatelessWidget {
  const _StreamContinuationMarker({required this.row});

  final TaskStreamRowLayout row;

  /// Builds the continuation endpoint at the end of one stream.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: row.color.withValues(alpha: 0.78),
        shape: BoxShape.circle,
      ),
      child: const SizedBox.square(dimension: 14),
    );
  }
}

/// _StreamUrgentDot renders the compact priority marker.
class _StreamUrgentDot extends StatelessWidget {
  const _StreamUrgentDot();

  /// Builds a small urgency indicator.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.agentAwesomeColors.coral,
        shape: BoxShape.circle,
      ),
      child: const SizedBox.square(dimension: 8),
    );
  }
}
