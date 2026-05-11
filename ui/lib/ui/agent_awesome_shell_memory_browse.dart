/// Memory browse, review, facet, and relationship-map widgets.
part of 'agent_awesome_shell.dart';

class _MemoryBrowseContent extends StatelessWidget {
  const _MemoryBrowseContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds facet-based discovery paths into memory.
  @override
  Widget build(BuildContext context) {
    final records = controller.filteredMemoryRecords;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MemoryFacetGroup(
            title: 'Kinds',
            values: _counts(records.map((record) => record.kind)),
            query: query,
            onSelected: (value) =>
                _applySingleFacet(controller, kinds: <String>[value]),
          ),
          _MemoryFacetGroup(
            title: 'Topics',
            values: _counts(records.expand((record) => record.topics)),
            query: query,
            onSelected: (value) =>
                _applySingleFacet(controller, topics: <String>[value]),
          ),
          _MemoryFacetGroup(
            title: 'Entities',
            values: _counts(records.expand((record) => record.entityNames)),
            query: query,
            onSelected: (value) => _selectFirstEntity(controller, value),
          ),
          _MemoryFacetGroup(
            title: 'Sensitivity',
            values: _counts(records.map((record) => record.sensitivity)),
            query: query,
            onSelected: (value) => _applySingleFacet(
              controller,
              allowedSensitivities: <String>[value],
            ),
          ),
          _MemoryFacetGroup(
            title: 'Trust',
            values: _counts(records.map((record) => record.trustLevel)),
            query: query,
            onSelected: (value) {
              unawaited(
                controller.applyMemoryFilters(
                  controller.memoryFilters.copyWith(localTrustLevel: value),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MemoryReviewContent extends StatelessWidget {
  const _MemoryReviewContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds the cross-cutting memory review queue.
  @override
  Widget build(BuildContext context) {
    final records = controller.filteredMemoryRecords.where((record) {
      return _memoryReviewReasons(record).isNotEmpty &&
          _matchesMemoryRecord(record, query);
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
                        selected: controller.selectedMemory?.id == record.id,
                        onTap: () =>
                            unawaited(controller.selectMemory(record.id)),
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

class _MemoryFacetGroup extends StatelessWidget {
  const _MemoryFacetGroup({
    required this.title,
    required this.values,
    required this.query,
    required this.onSelected,
  });

  final String title;
  final Map<String, int> values;
  final String query;
  final ValueChanged<String> onSelected;

  /// Builds one group of browse facets.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final entries = values.entries.where((entry) {
      return _matchesFuzzyQuery('${entry.key} $title', query);
    }).toList();
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MemoryPanelLabel(title),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final entry in entries)
                ActionChip(
                  avatar: CircleAvatar(
                    backgroundColor: colors.greenSoft,
                    child: Text(
                      '${entry.value}',
                      style: TextStyle(color: colors.green, fontSize: 11),
                    ),
                  ),
                  label: Text(_memoryLabel(entry.key)),
                  labelStyle: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: colors.surface,
                  side: BorderSide(color: colors.border),
                  onPressed: () => onSelected(entry.key),
                ),
            ],
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
          return _matchesMemoryRecord(record, query);
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
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _MemoryBadge(label: memory.sourceLabel),
                    _MemoryBadge(label: memory.scope),
                    _MemoryBadge(label: _memoryLabel(memory.kind)),
                    for (final topic in memory.topics)
                      _MemoryBadge(label: topic),
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
                        onTap: () =>
                            unawaited(controller.selectMemory(record.id)),
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
