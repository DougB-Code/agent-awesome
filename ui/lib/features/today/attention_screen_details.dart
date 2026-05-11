/// Selected attention item detail panel and metadata blocks.
part of 'attention_screen.dart';

/// _AttentionDetailsPanel renders the selected item's explanation details.
class _AttentionDetailsPanel extends StatelessWidget {
  /// Creates the right-side attention details panel.
  const _AttentionDetailsPanel({
    required this.item,
    required this.task,
    required this.onOpenBacklogTask,
    required this.onComplete,
  });

  /// Selected attention item.
  final ExecutiveSummaryItem? item;

  /// Backing workspace task, when loaded.
  final WorkspaceTask? task;

  /// Backlog open callback.
  final VoidCallback? onOpenBacklogTask;

  /// Completion callback.
  final VoidCallback? onComplete;

  /// Builds the details panel.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final selected = item;
    if (selected == null) {
      return Container(
        height: 320,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'No attention item selected',
          style: TextStyle(color: colors.muted),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'ATTENTION DETAILS',
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Icon(Icons.expand_less, color: colors.muted, size: 20),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _LanePill(lane: selected.lane),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      selected.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (_taskIdForItem(selected).isNotEmpty)
                      Text(
                        _taskIdForItem(selected),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _DetailBlock(
            title: 'Required attention',
            child: Text(
              _requiredAttention(selected),
              style: TextStyle(color: colors.ink, fontWeight: FontWeight.w700),
            ),
          ),
          _DetailBlock(
            title: 'Why this surfaced',
            child: Text(
              _reasonText(selected),
              style: TextStyle(color: colors.ink, height: 1.35),
            ),
          ),
          _DetailBlock(
            title: 'Suggested next action',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.greenSoft.withValues(alpha: 0.72),
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: <Widget>[
                  TodayIconBadge(
                    icon: todayLaneIcon(selected.lane),
                    severity: todayLaneSeverity(selected.lane),
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _primaryActionLabel(selected),
                          style: TextStyle(
                            color: colors.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (selected.estimateMinutes > 0)
                          Text(
                            _formatMinutes(selected.estimateMinutes),
                            style: TextStyle(color: colors.muted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _SourceBlock(item: selected),
          _ConfidenceBlock(confidence: selected.confidence),
          _TaskDetailsBlock(item: selected, task: task),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: <Widget>[
              if (_canCompleteItem(selected))
                FilledButton.icon(
                  onPressed: onComplete,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Mark done'),
                ),
              OutlinedButton.icon(
                onPressed: onOpenBacklogTask,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open in Backlog'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// _DetailBlock renders a titled block in the details panel.
class _DetailBlock extends StatelessWidget {
  /// Creates one detail block.
  const _DetailBlock({required this.title, required this.child});

  /// Block title.
  final String title;

  /// Block content.
  final Widget child;

  /// Builds the detail block.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(color: colors.ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// _SourceBlock renders source handles and derived attention factors.
class _SourceBlock extends StatelessWidget {
  /// Creates the source section.
  const _SourceBlock({required this.item});

  /// Selected attention item.
  final ExecutiveSummaryItem item;

  /// Builds source bullets.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final bullets = _sourceBullets(item);
    if (bullets.isEmpty) {
      return const SizedBox.shrink();
    }
    return _DetailBlock(
      title: 'Sources',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final bullet in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('• ', style: TextStyle(color: colors.ink)),
                  Expanded(
                    child: Text(
                      bullet,
                      style: TextStyle(color: colors.ink, height: 1.28),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// _ConfidenceBlock renders projection confidence as a compact meter.
class _ConfidenceBlock extends StatelessWidget {
  /// Creates a confidence meter block.
  const _ConfidenceBlock({required this.confidence});

  /// Normalized confidence value.
  final double confidence;

  /// Builds the confidence block.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final percent = _confidencePercent(confidence);
    final normalized = confidence <= 0 ? 0.01 : confidence.clamp(0, 1);
    return _DetailBlock(
      title: 'Confidence',
      child: Row(
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: normalized.toDouble(),
                minHeight: 6,
                color: colors.green,
                backgroundColor: colors.panel,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$percent%',
            style: TextStyle(color: colors.green, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

/// _TaskDetailsBlock renders task metadata available to explain the item.
class _TaskDetailsBlock extends StatelessWidget {
  /// Creates a task details block.
  const _TaskDetailsBlock({required this.item, required this.task});

  /// Selected attention item.
  final ExecutiveSummaryItem item;

  /// Backing workspace task, when loaded.
  final WorkspaceTask? task;

  /// Builds compact metadata rows.
  @override
  Widget build(BuildContext context) {
    final topics = task?.topics ?? const <String>[];
    return _DetailBlock(
      title: 'Task details',
      child: Column(
        children: <Widget>[
          _DetailRow(label: 'Status', value: _statusText(item, task)),
          _DetailRow(label: 'Priority', value: _priorityText(item, task)),
          _DetailRow(
            label: 'Due',
            value: formatOptionalLocalDate(
              item.dueAt ?? task?.dueAt,
              fallback: '-',
            ),
          ),
          _DetailRow(
            label: 'Scheduled',
            value: formatOptionalLocalDate(
              item.scheduledAt ?? task?.scheduledAt,
              fallback: '-',
            ),
          ),
          _DetailRow(
            label: 'Project',
            value: _fallbackText(item.project, task?.project ?? '-'),
          ),
          _DetailRow(
            label: 'Topics',
            value: topics.isEmpty ? '-' : topics.join(', '),
          ),
        ],
      ),
    );
  }
}

/// _DetailRow renders one label-value metadata row.
class _DetailRow extends StatelessWidget {
  /// Creates a metadata row.
  const _DetailRow({required this.label, required this.value});

  /// Row label.
  final String label;

  /// Row value.
  final String value;

  /// Builds the metadata row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                color: colors.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: colors.ink, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
