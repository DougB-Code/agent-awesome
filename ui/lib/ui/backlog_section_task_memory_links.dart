/// Backlog selected-task memory-link panel widgets.
part of 'backlog_section.dart';

/// _TaskMemoryLinkPanel links selected memory to a backlog item.
class _TaskMemoryLinkPanel extends StatelessWidget {
  const _TaskMemoryLinkPanel({
    required this.controller,
    required this.task,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;
  final String query;

  /// Builds the context memory-linking panel.
  @override
  Widget build(BuildContext context) {
    final selectedMemory = controller.selectedMemory;
    return _TaskMemoryLinkScaffold(
      selectedMemory: selectedMemory,
      links: _filteredLinks(task.memoryLinks, query),
      onLink: controller.tasksBusy || selectedMemory == null
          ? null
          : () => unawaited(controller.linkSelectedMemoryToTaskFromUi(task.id)),
    );
  }
}

class _TaskSelectedMemoryBlock extends StatelessWidget {
  const _TaskSelectedMemoryBlock({required this.memory});

  final MemoryRecord? memory;

  /// Builds a compact preview of the memory selected elsewhere in the app.
  @override
  Widget build(BuildContext context) {
    final record = memory;
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: record == null
          ? Text('No memory selected', style: TextStyle(color: colors.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 17,
                      color: colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        record.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (record.kind.isNotEmpty) _TaskBadge(label: record.kind),
                  ],
                ),
                if (record.summary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    record.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ],
              ],
            ),
    );
  }
}

class _TaskMemoryLinksBlock extends StatelessWidget {
  const _TaskMemoryLinksBlock({required this.links});

  final List<TaskMemoryLink> links;

  /// Builds memory link rows for context objects.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (links.isEmpty)
            Text('No linked memory', style: TextStyle(color: colors.muted))
          else
            for (final link in links)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            link.note.isEmpty ? link.relationship : link.note,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            link.memoryId.isEmpty
                                ? link.memoryEvidenceId
                                : link.memoryId,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    _TaskBadge(label: link.relationship),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
