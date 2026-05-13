/// Chat context panel widgets and context row models.
part of 'agent_awesome_shell.dart';

class _ChatRuntimeNotice extends StatelessWidget {
  const _ChatRuntimeNotice({required this.icon, required this.label});

  final IconData icon;
  final String label;

  /// Builds a compact live runtime notice in the chat stream.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: Row(
        children: <Widget>[
          Icon(icon, color: colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMemoryContextTile extends StatelessWidget {
  const _ChatMemoryContextTile({required this.record});

  final MemoryRecord record;

  /// Builds one memory context tile for chat utilities.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            record.title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          if (record.summary.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              _chatContextDisplayText(record.summary),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.muted),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _MemoryBadge(label: record.kind),
              _MemoryBadge(label: record.sensitivity),
              if (record.sourceLabel.isNotEmpty)
                _MemoryBadge(label: _memorySourceLabel(record.sourceLabel)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatTaskContextTile extends StatelessWidget {
  const _ChatTaskContextTile({required this.task});

  final WorkspaceTask task;

  /// Builds one associated context tile for the chat context panel.
  @override
  Widget build(BuildContext context) {
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TaskLine(task: task),
          if (task.sourceLabel.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            _MemoryBadge(label: task.sourceLabel),
          ],
        ],
      ),
    );
  }
}

/// _ChatSourceContextTile renders one source file referenced by the chat.
class _ChatSourceContextTile extends StatelessWidget {
  const _ChatSourceContextTile({required this.source});

  final SourceItem source;

  /// Builds a compact source tile for the chat files panel.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.insert_drive_file_outlined, color: colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  source.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (source.detail.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    source.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// _ChatPersonContextTile renders one person or entity tied to chat context.
class _ChatPersonContextTile extends StatelessWidget {
  const _ChatPersonContextTile({required this.person});

  final _ChatPersonContext person;

  /// Builds a person overview row for the chat people panel.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.person_outline, color: colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  person.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    _MemoryBadge(label: '${person.memoryCount} memories'),
                    _MemoryBadge(label: '${person.taskCount} tasks'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// _ChatContextEmpty renders a specific empty state for chat overview modes.
class _ChatContextEmpty extends StatelessWidget {
  const _ChatContextEmpty({required this.label});

  final String label;

  /// Builds the centered empty-state message.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: TextStyle(color: context.agentAwesomeColors.muted),
      ),
    );
  }
}

/// _ChatRuntimeSummary stores one user-facing runtime fact.
class _ChatRuntimeSummary {
  const _ChatRuntimeSummary({
    required this.title,
    required this.detail,
    required this.state,
    required this.icon,
    this.message = '',
  });

  final String title;
  final String detail;
  final ConnectionStateKind state;
  final IconData icon;
  final String message;
}

/// _ChatRuntimeSummaryTile renders one simplified runtime status.
class _ChatRuntimeSummaryTile extends StatelessWidget {
  const _ChatRuntimeSummaryTile({required this.summary});

  final _ChatRuntimeSummary summary;

  /// Builds one runtime fact without exposing internal service URLs.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final color = switch (summary.state) {
      ConnectionStateKind.connected => colors.green,
      ConnectionStateKind.disconnected => colors.coral,
      ConnectionStateKind.unknown => colors.muted,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PanelSectionBlock(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(summary.icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    summary.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summary.detail,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted),
                  ),
                  if (summary.message.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(summary.message, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatConfirmationUtility extends StatelessWidget {
  const _ChatConfirmationUtility({
    required this.confirmation,
    required this.onAnswer,
  });

  final ConfirmationRequest confirmation;
  final ValueChanged<ConfirmationOption> onAnswer;

  /// Builds the pending approval utility for chat tool calls.
  @override
  Widget build(BuildContext context) {
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _MemoryPanelLabel('Pending approval'),
          const SizedBox(height: 8),
          Text(confirmation.hint),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final option in confirmation.options)
                OutlinedButton(
                  onPressed: () => onAnswer(option),
                  child: Text(option.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// _ChatPersonContext stores aggregate person context for one chat.
class _ChatPersonContext {
  const _ChatPersonContext({
    required this.name,
    required this.memoryCount,
    required this.taskCount,
  });

  final String name;
  final int memoryCount;
  final int taskCount;
}
