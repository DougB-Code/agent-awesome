/// Backlog memory-link scaffold widget.
part of 'backlog_section.dart';

class _TaskMemoryLinkScaffold extends StatelessWidget {
  const _TaskMemoryLinkScaffold({
    required this.selectedMemory,
    required this.links,
  });

  final MemoryRecord? selectedMemory;
  final List<TaskMemoryLink> links;

  /// Builds reusable selected-memory and linked-memory sections.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _TaskPanelLabel('Selected Memory'),
          const SizedBox(height: 10),
          _TaskSelectedMemoryBlock(memory: selectedMemory),
          const SizedBox(height: 12),
          _TaskMemoryLinksBlock(links: links),
        ],
      ),
    );
  }
}
