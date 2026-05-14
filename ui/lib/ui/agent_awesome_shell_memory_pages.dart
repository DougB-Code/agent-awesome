/// Memory entity page and timeline widgets.
part of 'agent_awesome_shell.dart';

class _MemoryPagesContent extends StatelessWidget {
  const _MemoryPagesContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds entity page and timeline controls for the selected memory.
  @override
  Widget build(BuildContext context) {
    final memory = controller.selectedMemory;
    final page = controller.selectedMemoryPage;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    if (!_matchesMemoryRecord(
          memory,
          query,
          extra: _memoryFirewallSearchText(controller, memory.firewall),
        ) &&
        !_matchesFuzzyQuery(
          '${page?.title ?? ''} ${page?.content ?? ''}',
          query,
        )) {
      return PanelEmptyState(query: query);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock.gradient(
            title: 'Page Tools',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: controller.memoryBusy
                      ? null
                      : () =>
                            unawaited(controller.loadEntityPageFromUi(memory)),
                  icon: const Icon(Icons.person_search_outlined),
                  label: const Text('Entity Page'),
                ),
                for (final topic in memory.topics.take(3))
                  OutlinedButton.icon(
                    onPressed: controller.memoryBusy
                        ? null
                        : () => unawaited(controller.loadTimelineFromUi(topic)),
                    icon: const Icon(Icons.timeline_outlined),
                    label: Text(_memoryLabel(topic)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (page == null)
            const PanelEmptyBlock(label: 'No compiled page loaded')
          else
            PanelSectionBlock.gradient(
              title: 'Compiled Page',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    page.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _MemoryBadge(label: page.kind),
                      _MemoryBadge(
                        label: controller.memoryFirewallLabel(page.firewall),
                      ),
                      if (controller
                          .memoryFirewallAudienceLabel(page.firewall)
                          .isNotEmpty)
                        _MemoryBadge(
                          label:
                              'Shared with ${controller.memoryFirewallAudienceLabel(page.firewall)}',
                        ),
                      _MemoryBadge(label: '${page.sourceIds.length} sources'),
                      if (page.stale) const _MemoryBadge(label: 'stale'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SelectableText(page.content),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
