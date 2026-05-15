/// Backlog memory-link scaffold widget.
part of 'backlog_section.dart';

class _TaskMemoryLinkScaffold extends StatelessWidget {
  const _TaskMemoryLinkScaffold({
    required this.selectedMemory,
    required this.links,
    required this.onLink,
  });

  final MemoryRecord? selectedMemory;
  final List<TaskMemoryLink> links;
  final VoidCallback? onLink;

  /// Builds reusable selected-memory and linked-memory sections.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: _TaskPanelLabel('Selected Memory')),
              Tooltip(
                message: 'Link selected memory',
                child: OutlinedButton.icon(
                  onPressed: onLink,
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Link'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _TaskSelectedMemoryBlock(memory: selectedMemory),
          const SizedBox(height: 12),
          _TaskMemoryLinksBlock(links: links),
        ],
      ),
    );
  }
}
