/// Shared color, icon, and text helpers for task stream rendering.
part of 'task_stream_canvas.dart';

/// Returns a stable route color for one stream id.
Color _streamRouteColor(String streamId, Color fallback) {
  const palette = <Color>[
    Color(0xff5f94c9),
    Color(0xff6f9b62),
    Color(0xffd7a246),
    Color(0xff9177c0),
    Color(0xffd8798c),
    Color(0xff7a9a91),
    Color(0xffc1844f),
  ];
  var hash = 0;
  for (final unit in streamId.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  if (hash == 0) {
    return fallback;
  }
  return palette[hash % palette.length];
}

/// Returns the leading icon for a task card.
IconData _cardIcon(TaskStreamCard card) {
  final priority = card.priority.trim().toLowerCase();
  if (priority == 'urgent' || priority == 'high') {
    return Icons.flag_outlined;
  }
  if (card.dueAt != null) {
    return Icons.event_available_outlined;
  }
  return Icons.task_alt_outlined;
}

/// Returns compact metadata text for a task card.
String _cardSubtitle(TaskStreamCard card) {
  final parts = <String>[
    if (card.owner.isNotEmpty) taskStreamDisplayLabel(card.owner),
    if (card.estimateMinutes > 0) '${card.estimateMinutes}m',
    if (card.dueAt != null) 'Due ${formatLocalDate(card.dueAt!)}',
    if (card.dueAt == null && card.scheduledAt != null)
      'Scheduled ${formatLocalDate(card.scheduledAt!)}',
    if (card.spendLabel.isNotEmpty) card.spendLabel,
  ];
  if (parts.isEmpty) {
    return taskStreamDisplayLabel(card.priority);
  }
  return parts.join(' · ');
}
