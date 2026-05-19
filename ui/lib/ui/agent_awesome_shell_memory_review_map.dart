/// Memory review queue and relationship-map widgets.
part of 'agent_awesome_shell.dart';

class _MemoryReviewContent extends StatelessWidget {
  const _MemoryReviewContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds the cross-cutting memory review queue.
  @override
  Widget build(BuildContext context) {
    final records = controller.filteredMemoryRecords.where((record) {
      return _memoryReviewReasons(record).isNotEmpty &&
          _matchesMemoryRecord(
            record,
            query,
            extra: _memoryFirewallSearchText(controller, record.firewall),
          );
    }).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MemoryStatusStrip(controller: controller),
          const SizedBox(height: 14),
          if (records.isEmpty)
            const PanelEmptyBlock(label: 'No records need review')
          else
            for (final record in records)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PanelSectionBlock(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _MemoryRecordTile(
                        record: record,
                        selected:
                            controller.selectedMemory != null &&
                            controller.memorySelectionKey(
                                  controller.selectedMemory!,
                                ) ==
                                controller.memorySelectionKey(record),
                        firewallLabel: controller.memoryFirewallLabel(
                          record.firewall,
                        ),
                        firewallAudience: controller
                            .memoryFirewallAudienceLabel(record.firewall),
                        onTap: () => unawaited(
                          controller.selectMemory(
                            controller.memorySelectionKey(record),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final reason in _memoryReviewReasons(record))
                            _MemoryBadge(label: reason),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _MemoryMapContent extends StatelessWidget {
  const _MemoryMapContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds relationship and discovery-path context for the selected memory.
  @override
  Widget build(BuildContext context) {
    final memory = controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    final related = controller.workspace.memoryRecords
        .where((record) {
          return memory.relationships.any((rel) => rel.toId == record.id) ||
              record.relationships.any((rel) => rel.toId == memory.id);
        })
        .where((record) {
          return _matchesMemoryRecord(
            record,
            query,
            extra: _memoryFirewallSearchText(controller, record.firewall),
          );
        })
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Selected Memory'),
                const SizedBox(height: 10),
                Text(
                  memory.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _MemoryBadge(label: _memorySourceLabel(memory.sourceLabel)),
                    _MemoryBadge(
                      label: controller.memoryFirewallLabel(memory.firewall),
                    ),
                    if (controller
                        .memoryFirewallAudienceLabel(memory.firewall)
                        .isNotEmpty)
                      _MemoryBadge(
                        label:
                            'Shared with ${controller.memoryFirewallAudienceLabel(memory.firewall)}',
                      ),
                    _MemoryBadge(label: _memoryLabel(memory.kind)),
                    for (final topic in memory.topics)
                      _MemoryBadge(label: _memoryLabel(topic)),
                    for (final entity in memory.entityNames)
                      _MemoryBadge(label: entity),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Relationships'),
                const SizedBox(height: 10),
                if (memory.relationships.isEmpty)
                  Text(
                    'No relationship edges',
                    style: TextStyle(color: context.agentAwesomeColors.muted),
                  )
                else
                  for (final relationship in memory.relationships)
                    _MemoryRelationshipLine(relationship: relationship),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Related Records'),
                const SizedBox(height: 10),
                if (related.isEmpty)
                  Text(
                    'No related records in the current result set',
                    style: TextStyle(color: context.agentAwesomeColors.muted),
                  )
                else
                  for (final record in related)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemoryRecordTile(
                        record: record,
                        selected: false,
                        firewallLabel: controller.memoryFirewallLabel(
                          record.firewall,
                        ),
                        firewallAudience: controller
                            .memoryFirewallAudienceLabel(record.firewall),
                        onTap: () => unawaited(
                          controller.selectMemory(
                            controller.memorySelectionKey(record),
                          ),
                        ),
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
