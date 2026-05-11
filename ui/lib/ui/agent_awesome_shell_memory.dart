/// Memory command surface widgets for the Agent Awesome shell.
part of 'agent_awesome_shell.dart';

class _MemoryCommandSubShell extends StatefulWidget {
  const _MemoryCommandSubShell({required this.controller, this.onAreaChanged});

  final AgentAwesomeAppController controller;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  @override
  State<_MemoryCommandSubShell> createState() => _MemoryCommandSubShellState();
}

class _MemoryCommandSubShellState extends State<_MemoryCommandSubShell> {
  String _detailModeId = _memoryOverviewDetailId;

  /// Builds memory discovery and inspection inside the shared subshell.
  @override
  Widget build(BuildContext context) {
    return CommandPanelSubShell(
      areas: _memoryCommandAreas(widget.controller),
      detailTitle: 'Memory Inspector',
      detailModes: _memoryDetailModes(),
      selectedDetailModeId: _detailModeId,
      onDetailModeSelected: _selectDetailMode,
      detailBuilder: _buildDetailContent,
      onAreaChanged: widget.onAreaChanged,
      filterHint: 'Filter...',
      split: const PanelSplit(left: 0.58, min: 0.44, max: 0.82),
    );
  }

  /// Selects the right-side memory detail mode.
  void _selectDetailMode(String modeId) {
    setState(() => _detailModeId = modeId);
  }

  /// Builds one selected-memory detail mode.
  Widget _buildDetailContent(String modeId) {
    return switch (modeId) {
      _memorySourceDetailId => _MemorySourceContent(
        controller: widget.controller,
        query: '',
      ),
      _memoryRelationsDetailId => _MemoryRelationsContent(
        controller: widget.controller,
        query: '',
      ),
      _memoryMetadataDetailId => _MemoryMetadataContent(
        controller: widget.controller,
        query: '',
      ),
      _memoryCorrectionsDetailId => _MemoryCorrectionsContent(
        controller: widget.controller,
        query: '',
      ),
      _memoryPagesDetailId => _MemoryPagesContent(
        controller: widget.controller,
        query: '',
      ),
      _ => _MemoryOverviewContent(controller: widget.controller, query: ''),
    };
  }
}

class _MemorySearchContent extends StatelessWidget {
  const _MemorySearchContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds memory search results and retrieval filters.
  @override
  Widget build(BuildContext context) {
    final records = controller.filteredMemoryRecords.where((record) {
      return _matchesMemoryRecord(record, query);
    }).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MemoryFilterBar(controller: controller, query: query),
          const SizedBox(height: 14),
          _MemoryStatusStrip(controller: controller),
          if (controller.memoryBusy || _memoryMessageIsError(controller))
            const SizedBox(height: 14),
          if (records.isEmpty)
            PanelEmptyBlock(label: 'No memory records')
          else
            for (final record in records)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MemoryRecordTile(
                  record: record,
                  selected: controller.selectedMemory?.id == record.id,
                  onTap: () => unawaited(controller.selectMemory(record.id)),
                ),
              ),
        ],
      ),
    );
  }
}

class _MemoryFilterBar extends StatelessWidget {
  const _MemoryFilterBar({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds scope, sensitivity, and service-search controls.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final filters = controller.memoryFilters;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _MemoryDropdown(
                  value: filters.scope,
                  values: _memoryScopes,
                  tooltip: 'Scope',
                  onChanged: (value) {
                    unawaited(
                      controller.applyMemoryFilters(
                        filters.copyWith(scope: value),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Search service',
                child: IconButton.outlined(
                  onPressed: () {
                    unawaited(
                      controller.applyMemoryFilters(
                        filters.copyWith(text: query.trim()),
                      ),
                    );
                  },
                  icon: const Icon(Icons.travel_explore),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Refresh',
                child: IconButton.outlined(
                  onPressed: () =>
                      unawaited(controller.applyMemoryFilters(filters)),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final sensitivity in _memorySensitivities)
                Builder(
                  builder: (context) {
                    final selected = filters.allowedSensitivities.contains(
                      sensitivity,
                    );
                    return FilterChip(
                      label: Text(_memoryLabel(sensitivity)),
                      selected: selected,
                      showCheckmark: true,
                      backgroundColor: colors.surface,
                      selectedColor: colors.panelStrong,
                      checkmarkColor: colors.green,
                      side: BorderSide(
                        color: selected ? colors.borderStrong : colors.border,
                      ),
                      labelStyle: TextStyle(
                        color: selected ? colors.ink : colors.muted,
                        fontWeight: FontWeight.w800,
                      ),
                      onSelected: (_) {
                        unawaited(
                          controller.applyMemoryFilters(
                            filters.copyWith(
                              allowedSensitivities: toggleStringValue(
                                filters.allowedSensitivities,
                                sensitivity,
                                allowEmpty: false,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
          if (filters.text.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            _MemoryActiveFilter(
              label: 'Search: ${filters.text}',
              onClear: () {
                unawaited(
                  controller.applyMemoryFilters(filters.copyWith(text: '')),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _MemoryStatusStrip extends StatelessWidget {
  const _MemoryStatusStrip({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds a compact memory operation status strip.
  @override
  Widget build(BuildContext context) {
    if (controller.memoryBusy) {
      return const _RouteNoticePanel(
        icon: Icons.sync,
        title: 'Loading memory',
        message: 'Agent Awesome is reading memory, people, and timeline data.',
      );
    }
    if (!_memoryMessageIsError(controller)) {
      return const SizedBox.shrink();
    }
    return _RouteNoticePanel(
      icon: Icons.error_outline,
      title: 'Memory service unavailable',
      message: controller.memoryMessage,
      action: OutlinedButton.icon(
        onPressed: () => unawaited(controller.refreshMemoryFromUi()),
        icon: const Icon(Icons.refresh),
        label: const Text('Try again'),
      ),
    );
  }
}

class _RouteNoticePanel extends StatelessWidget {
  const _RouteNoticePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  /// Builds a prominent route-level status or error panel.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: colors.greenSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: colors.green),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  message,
                  style: TextStyle(color: colors.muted, height: 1.4),
                ),
                if (action != null) ...<Widget>[
                  const SizedBox(height: 14),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryUnavailableRoute extends StatelessWidget {
  const _MemoryUnavailableRoute({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds the full-page error state for memory-backed routes.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Memory service unavailable',
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 28),
          _RouteNoticePanel(
            icon: Icons.error_outline,
            title: 'Connection failed',
            message: controller.memoryMessage,
            action: OutlinedButton.icon(
              onPressed: () => unawaited(controller.refreshMemoryFromUi()),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryRecordTile extends StatelessWidget {
  const _MemoryRecordTile({
    required this.record,
    required this.selected,
    required this.onTap,
  });

  final MemoryRecord record;
  final bool selected;
  final VoidCallback onTap;

  /// Builds one selectable memory search result.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accentColor = _memoryRecordAccentColor(context, record);
    final borderColor = selected ? colors.borderStrong : colors.border;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          gradient: context.agentAwesomeCardGradient,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(width: 4, color: accentColor),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _MemoryKindBadge(record: record),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  record.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.ink,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                if (record.summary.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 8),
                                  Text(
                                    record.summary,
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
                                    _MemoryBadge(label: record.scope),
                                    _MemoryBadge(label: record.sensitivity),
                                    _MemoryBadge(
                                      label: _memoryLabel(record.trustLevel),
                                    ),
                                    if (record.status != 'active')
                                      _MemoryBadge(label: record.status),
                                    for (final topic in record.topics.take(3))
                                      _MemoryBadge(label: topic),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: colors.border),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.link_outlined,
                            size: 15,
                            color: colors.muted,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              record.sourceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryKindBadge extends StatelessWidget {
  const _MemoryKindBadge({required this.record});

  final MemoryRecord record;

  /// Builds the compact record-kind badge for memory cards.
  @override
  Widget build(BuildContext context) {
    final accent = _memoryRecordAccentColor(context, record);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_memoryRecordIcon(record), size: 16, color: accent),
          const SizedBox(width: 5),
          Text(
            _memoryLabel(record.kind),
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Returns the accent color used by a memory card.
Color _memoryRecordAccentColor(BuildContext context, MemoryRecord record) {
  final colors = context.agentAwesomeColors;
  if (record.status != 'active') {
    return colors.coral;
  }
  if (record.sensitivity == 'restricted') {
    return colors.coral;
  }
  if (record.sensitivity == 'private') {
    return context.agentAwesomeWarningAccent;
  }
  if (record.trustLevel == 'low') {
    return context.agentAwesomeWarningAccent;
  }
  return context.agentAwesomeLowAccent;
}

/// Returns the icon that represents one memory record kind.
IconData _memoryRecordIcon(MemoryRecord record) {
  if (record.kind == 'profile_fact') {
    return Icons.person_outline;
  }
  if (record.kind == 'source_original') {
    return Icons.article_outlined;
  }
  if (record.kind == 'relationship') {
    return Icons.hub_outlined;
  }
  if (record.kind == 'task') {
    return Icons.task_alt_outlined;
  }
  return Icons.chat_bubble_outline;
}

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

class _MemoryCaptureContent extends StatefulWidget {
  const _MemoryCaptureContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  @override
  State<_MemoryCaptureContent> createState() => _MemoryCaptureContentState();
}

class _MemoryCaptureContentState extends State<_MemoryCaptureContent> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  final TextEditingController _sourceSystem = TextEditingController(
    text: 'agent_awesome_ui',
  );
  final TextEditingController _sourceId = TextEditingController();
  final TextEditingController _subjects = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  final TextEditingController _entities = TextEditingController();
  String _kind = 'document';
  String _scope = 'user';
  String _trust = 'source_original';
  String _sensitivity = 'private';

  /// Initializes live duplicate hint refresh.
  @override
  void initState() {
    super.initState();
    _title.addListener(_refreshDuplicateHints);
    _content.addListener(_refreshDuplicateHints);
  }

  /// Cleans up capture form controllers.
  @override
  void dispose() {
    _title.removeListener(_refreshDuplicateHints);
    _content.removeListener(_refreshDuplicateHints);
    _title.dispose();
    _content.dispose();
    _sourceSystem.dispose();
    _sourceId.dispose();
    _subjects.dispose();
    _topics.dispose();
    _entities.dispose();
    super.dispose();
  }

  /// Builds the careful memory accession form.
  @override
  Widget build(BuildContext context) {
    final duplicates = widget.controller.filteredMemoryRecords
        .where((record) {
          final probe = '${_title.text} ${_content.text} ${widget.query}';
          return probe.trim().isNotEmpty && _matchesMemoryRecord(record, probe);
        })
        .take(4)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              children: <Widget>[
                _MemoryTextField(controller: _title, label: 'Title'),
                const SizedBox(height: 10),
                _MemoryTextField(
                  controller: _content,
                  label: 'Source content',
                  maxLines: 8,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _MemoryTextField(
                        controller: _sourceSystem,
                        label: 'Source system',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MemoryTextField(
                        controller: _sourceId,
                        label: 'Source id',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _MemoryDropdown(
                        value: _kind,
                        values: _memoryKinds,
                        tooltip: 'Kind',
                        onChanged: (value) => setState(() => _kind = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MemoryDropdown(
                        value: _scope,
                        values: _memoryScopes,
                        tooltip: 'Scope',
                        onChanged: (value) => setState(() => _scope = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _MemoryDropdown(
                        value: _trust,
                        values: _memoryTrustLevels,
                        tooltip: 'Trust',
                        onChanged: (value) => setState(() => _trust = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MemoryDropdown(
                        value: _sensitivity,
                        values: _memorySensitivities,
                        tooltip: 'Sensitivity',
                        onChanged: (value) =>
                            setState(() => _sensitivity = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _MemoryTextField(controller: _subjects, label: 'Subjects'),
                const SizedBox(height: 10),
                _MemoryTextField(controller: _topics, label: 'Topics'),
                const SizedBox(height: 10),
                _MemoryTextField(controller: _entities, label: 'Entities'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Nearby Records'),
                const SizedBox(height: 10),
                if (duplicates.isEmpty)
                  Text(
                    'No nearby records',
                    style: TextStyle(color: context.agentAwesomeColors.muted),
                  )
                else
                  for (final record in duplicates)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemoryRecordTile(
                        record: record,
                        selected: false,
                        onTap: () => unawaited(
                          widget.controller.selectMemory(record.id),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: widget.controller.memoryBusy ? null : _save,
            icon: const Icon(Icons.library_add_check_outlined),
            label: const Text('Save Reviewed Memory'),
          ),
        ],
      ),
    );
  }

  /// Confirms and saves the drafted source-backed memory.
  Future<void> _save() async {
    final draft = MemoryCaptureDraft(
      content: _content.text.trim(),
      title: _title.text.trim(),
      kind: _kind,
      scope: _scope,
      trustLevel: _trust,
      sensitivity: _sensitivity,
      sourceSystem: _sourceSystem.text.trim(),
      sourceId: _sourceId.text.trim(),
      subjects: splitCommaSeparatedValues(_subjects.text),
      topics: splitCommaSeparatedValues(_topics.text),
      entityNames: splitCommaSeparatedValues(_entities.text),
    );
    if (draft.content.isEmpty) {
      return;
    }
    final approved = await _confirmWrite(
      context,
      'Save "${draft.title.isEmpty ? 'Untitled memory' : draft.title}"?',
    );
    if (!approved || !mounted) {
      return;
    }
    await widget.controller.saveMemoryCandidateFromUi(draft);
    if (!mounted) {
      return;
    }
    _content.clear();
    _title.clear();
    _sourceId.clear();
  }

  /// Refreshes nearby-record hints while accession fields change.
  void _refreshDuplicateHints() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _MemoryOverviewContent extends StatelessWidget {
  const _MemoryOverviewContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds selected memory metadata and stewardship posture.
  @override
  Widget build(BuildContext context) {
    final memory = controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    if (!_matchesMemoryRecord(memory, query)) {
      return PanelEmptyState(query: query);
    }
    final contradictionCount = memory.relationships
        .where((relationship) => relationship.type == 'contradicts')
        .length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        memory.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    if (contradictionCount > 0)
                      _MemoryBadge(label: '$contradictionCount conflicts'),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  memory.summary,
                  style: TextStyle(color: context.agentAwesomeColors.muted),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _MemoryBadge(label: _memoryLabel(memory.kind)),
                    _MemoryBadge(label: memory.scope),
                    _MemoryBadge(label: memory.sensitivity),
                    _MemoryBadge(label: _memoryLabel(memory.trustLevel)),
                    _MemoryBadge(label: memory.status),
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
                _MemoryPanelLabel('Memory'),
                const SizedBox(height: 10),
                _MemoryMetadataRow(label: 'Memory id', value: memory.id),
                _MemoryMetadataRow(
                  label: 'Source record id',
                  value: memory.evidenceId,
                ),
                _MemoryMetadataRow(label: 'Source', value: memory.sourceLabel),
                _MemoryMetadataRow(
                  label: 'Created',
                  value: formatOptionalLocalDateTime(memory.createdAt),
                ),
                _MemoryMetadataRow(
                  label: 'Updated',
                  value: formatOptionalLocalDateTime(memory.updatedAt),
                ),
                _MemoryMetadataRow(
                  label: 'Event',
                  value: formatOptionalLocalDateTime(memory.eventTime),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Access Paths'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final subject in memory.subjects)
                      _MemoryBadge(label: subject),
                    for (final topic in memory.topics)
                      _MemoryBadge(label: topic),
                    for (final entity in memory.entityNames)
                      _MemoryBadge(label: entity),
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

class _MemorySourceContent extends StatelessWidget {
  const _MemorySourceContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds immutable raw source preview for the selected memory.
  @override
  Widget build(BuildContext context) {
    final memory = controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    if (!_matchesFuzzyQuery(
      '${memory.rawContent} ${memory.rawPath} ${memory.rawChecksum}',
      query,
    )) {
      return PanelEmptyState(query: query);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Source'),
                const SizedBox(height: 10),
                _MemoryMetadataRow(
                  label: 'Source record id',
                  value: memory.evidenceId,
                ),
                _MemoryMetadataRow(label: 'Path', value: memory.rawPath),
                _MemoryMetadataRow(
                  label: 'Checksum',
                  value: memory.rawChecksum,
                ),
                _MemoryMetadataRow(
                  label: 'Media type',
                  value: memory.rawMediaType,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: controller.memoryBusy
                      ? null
                      : () =>
                            unawaited(controller.hydrateSelectedMemorySource()),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Load Source'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(minHeight: 260),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.agentAwesomeColors.surface,
              gradient: context.agentAwesomeCardGradient,
              border: Border.all(color: context.agentAwesomeColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              memory.rawContent.isEmpty
                  ? 'Source not loaded'
                  : memory.rawContent,
              style: TextStyle(
                color: context.agentAwesomeColors.ink,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryRelationsContent extends StatelessWidget {
  const _MemoryRelationsContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds relationship review for the selected memory.
  @override
  Widget build(BuildContext context) {
    final memory = controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    final relationships = memory.relationships.where((relationship) {
      return _matchesFuzzyQuery(
        '${relationship.type} ${relationship.toId} ${relationship.sourceId}',
        query,
      );
    }).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Outgoing Edges'),
                const SizedBox(height: 10),
                if (relationships.isEmpty)
                  Text(
                    'No matching relationship edges',
                    style: TextStyle(color: context.agentAwesomeColors.muted),
                  )
                else
                  for (final relationship in relationships)
                    _MemoryRelationshipLine(relationship: relationship),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Incoming Edges'),
                const SizedBox(height: 10),
                for (final record in controller.workspace.memoryRecords)
                  for (final relationship in record.relationships.where(
                    (rel) => rel.toId == memory.id,
                  ))
                    _MemoryRelationshipLine(relationship: relationship),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryMetadataContent extends StatefulWidget {
  const _MemoryMetadataContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  @override
  State<_MemoryMetadataContent> createState() => _MemoryMetadataContentState();
}

class _MemoryMetadataContentState extends State<_MemoryMetadataContent> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _summary = TextEditingController();
  final TextEditingController _subjects = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  final TextEditingController _entities = TextEditingController();
  String _recordId = '';
  String _kind = 'document';
  String _sensitivity = 'private';
  String _status = 'active';

  /// Initializes form state.
  @override
  void initState() {
    super.initState();
    _syncFromSelected();
  }

  /// Keeps form state aligned when the selected memory changes.
  @override
  void didUpdateWidget(covariant _MemoryMetadataContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.selectedMemory?.id !=
        widget.controller.selectedMemory?.id) {
      _syncFromSelected();
    }
  }

  /// Cleans up metadata editing form controllers.
  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _subjects.dispose();
    _topics.dispose();
    _entities.dispose();
    super.dispose();
  }

  /// Builds explicit metadata repair controls.
  @override
  Widget build(BuildContext context) {
    final memory = widget.controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    if (!_matchesMemoryRecord(memory, widget.query)) {
      return PanelEmptyState(query: widget.query);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              children: <Widget>[
                _MemoryTextField(controller: _title, label: 'Title'),
                const SizedBox(height: 10),
                _MemoryTextField(
                  controller: _summary,
                  label: 'Summary',
                  maxLines: 4,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _MemoryDropdown(
                        value: _kind,
                        values: _memoryKinds,
                        tooltip: 'Kind',
                        onChanged: (value) => setState(() => _kind = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MemoryDropdown(
                        value: _sensitivity,
                        values: _memorySensitivities,
                        tooltip: 'Sensitivity',
                        onChanged: (value) =>
                            setState(() => _sensitivity = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _MemoryDropdown(
                  value: _status,
                  values: _memoryStatuses,
                  tooltip: 'Status',
                  onChanged: (value) => setState(() => _status = value),
                ),
                const SizedBox(height: 10),
                _MemoryTextField(controller: _subjects, label: 'Subjects'),
                const SizedBox(height: 10),
                _MemoryTextField(controller: _topics, label: 'Topics'),
                const SizedBox(height: 10),
                _MemoryTextField(controller: _entities, label: 'Entities'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: widget.controller.memoryBusy ? null : _repair,
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('Repair Memory Metadata'),
          ),
        ],
      ),
    );
  }

  /// Copies selected memory metadata into the repair form.
  void _syncFromSelected() {
    final memory = widget.controller.selectedMemory;
    if (memory == null || memory.id == _recordId) {
      return;
    }
    _recordId = memory.id;
    _title.text = memory.title;
    _summary.text = memory.summary;
    _subjects.text = memory.subjects.join(', ');
    _topics.text = memory.topics.join(', ');
    _entities.text = memory.entityNames.join(', ');
    _kind = _coerceDropdownValue(_memoryKinds, memory.kind, 'document');
    _sensitivity = _coerceDropdownValue(
      _memorySensitivities,
      memory.sensitivity,
      'private',
    );
    _status = _coerceDropdownValue(_memoryStatuses, memory.status, 'active');
  }

  /// Confirms and submits memory metadata repairs.
  Future<void> _repair() async {
    final memory = widget.controller.selectedMemory;
    if (memory == null) {
      return;
    }
    final approved = await _confirmWrite(
      context,
      'Repair memory metadata for "${memory.title}"?',
    );
    if (!approved || !mounted) {
      return;
    }
    await widget.controller.repairMemoryFromUi(
      MemoryRepairDraft(
        memoryId: memory.id,
        title: _title.text.trim(),
        summary: _summary.text.trim(),
        kind: _kind,
        sensitivity: _sensitivity,
        status: _status,
        subjects: splitCommaSeparatedValues(_subjects.text),
        topics: splitCommaSeparatedValues(_topics.text),
        entityNames: splitCommaSeparatedValues(_entities.text),
      ),
    );
  }
}

class _MemoryCorrectionsContent extends StatefulWidget {
  const _MemoryCorrectionsContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  @override
  State<_MemoryCorrectionsContent> createState() =>
      _MemoryCorrectionsContentState();
}

class _MemoryCorrectionsContentState extends State<_MemoryCorrectionsContent> {
  final TextEditingController _correction = TextEditingController();

  /// Cleans up correction form state.
  @override
  void dispose() {
    _correction.dispose();
    super.dispose();
  }

  /// Builds correction capture controls.
  @override
  Widget build(BuildContext context) {
    final memory = widget.controller.selectedMemory;
    if (memory == null) {
      return const _MemorySelectionEmpty();
    }
    if (!_matchesMemoryRecord(memory, widget.query)) {
      return PanelEmptyState(query: widget.query);
    }
    final corrections = widget.controller.workspace.memoryRecords.where((
      record,
    ) {
      return record.sourceSystem == 'memory_correction' &&
          record.sourceId == memory.id;
    }).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('New Correction'),
                const SizedBox(height: 10),
                _MemoryTextField(
                  controller: _correction,
                  label: 'Correction text',
                  maxLines: 6,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: widget.controller.memoryBusy ? null : _submit,
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('Submit Correction'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _MemoryPanelLabel('Existing Corrections'),
                const SizedBox(height: 10),
                if (corrections.isEmpty)
                  Text(
                    'No corrections in current results',
                    style: TextStyle(color: context.agentAwesomeColors.muted),
                  )
                else
                  for (final correction in corrections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemoryRecordTile(
                        record: correction,
                        selected: false,
                        onTap: () => unawaited(
                          widget.controller.selectMemory(correction.id),
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

  /// Confirms and submits a source-backed correction.
  Future<void> _submit() async {
    final memory = widget.controller.selectedMemory;
    final text = _correction.text.trim();
    if (memory == null || text.isEmpty) {
      return;
    }
    final approved = await _confirmWrite(
      context,
      'Submit correction for "${memory.title}"?',
    );
    if (!approved || !mounted) {
      return;
    }
    await widget.controller.submitMemoryCorrectionFromUi(text);
    if (mounted) {
      _correction.clear();
    }
  }
}

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
    if (!_matchesMemoryRecord(memory, query) &&
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
          PanelSectionBlock(
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
                    label: Text(topic),
                  ),
                if (page != null)
                  OutlinedButton.icon(
                    onPressed: controller.memoryBusy
                        ? null
                        : () => unawaited(
                            controller.refreshSelectedMemoryPageFromUi(),
                          ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Page'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (page == null)
            const PanelEmptyBlock(label: 'No compiled page loaded')
          else
            PanelSectionBlock(
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
                      _MemoryBadge(label: page.scope),
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
