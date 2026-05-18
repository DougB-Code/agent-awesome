/// Memory search, filtering, status, and result-card widgets.
part of 'agent_awesome_shell.dart';

class _MemorySearchContent extends StatelessWidget {
  const _MemorySearchContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds memory search results and retrieval filters.
  @override
  Widget build(BuildContext context) {
    final records = controller.filteredMemoryRecords.where((record) {
      return _matchesMemoryRecord(
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
                  selected:
                      controller.selectedMemory != null &&
                      controller.memorySelectionKey(
                            controller.selectedMemory!,
                          ) ==
                          controller.memorySelectionKey(record),
                  firewallLabel: controller.memoryFirewallLabel(
                    record.firewall,
                  ),
                  firewallAudience: controller.memoryFirewallAudienceLabel(
                    record.firewall,
                  ),
                  onTap: () => unawaited(
                    controller.selectMemory(
                      controller.memorySelectionKey(record),
                    ),
                  ),
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

  /// Builds firewall, sensitivity, and service-search controls.
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
                child: PanelDropdownFormField<String>(
                  label: 'Firewall',
                  value: filters.firewall,
                  values: controller.memoryFirewallIds,
                  tooltip: 'Firewall',
                  labelFor: controller.memoryFirewallPickerLabel,
                  onChanged: (value) {
                    unawaited(
                      controller.applyMemoryFilters(
                        filters.copyWith(
                          firewall: value,
                          includeGlobal: value == 'global'
                              ? false
                              : filters.includeGlobal,
                        ),
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
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (controller.memoryFirewallIds.contains('global') &&
                  filters.firewall != 'global')
                FilterChip(
                  label: Text(
                    'Include ${controller.memoryFirewallLabel('global')}',
                  ),
                  selected: filters.includeGlobal,
                  showCheckmark: true,
                  backgroundColor: colors.surface,
                  selectedColor: colors.panelStrong,
                  checkmarkColor: colors.green,
                  side: BorderSide(
                    color: filters.includeGlobal
                        ? colors.borderStrong
                        : colors.border,
                  ),
                  labelStyle: TextStyle(
                    color: filters.includeGlobal ? colors.ink : colors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                  onSelected: (value) {
                    unawaited(
                      controller.applyMemoryFilters(
                        filters.copyWith(includeGlobal: value),
                      ),
                    );
                  },
                ),
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
    );
  }
}

class _RouteNoticePanel extends StatelessWidget {
  const _RouteNoticePanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

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
    required this.firewallLabel,
    required this.firewallAudience,
    required this.onTap,
  });

  final MemoryRecord record;
  final bool selected;
  final String firewallLabel;
  final String firewallAudience;
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
                                    _MemoryBadge(label: firewallLabel),
                                    if (firewallAudience.isNotEmpty)
                                      _MemoryBadge(
                                        label: 'Shared with $firewallAudience',
                                      ),
                                    _MemoryBadge(label: record.sensitivity),
                                    _MemoryBadge(
                                      label: _memoryLabel(record.trustLevel),
                                    ),
                                    if (record.domainId.isNotEmpty)
                                      _MemoryBadge(label: record.domainId),
                                    if (record.status != 'active')
                                      _MemoryBadge(label: record.status),
                                    for (final topic in record.topics.take(3))
                                      _MemoryBadge(label: _memoryLabel(topic)),
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
                              _memorySourceLabel(record.sourceLabel),
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
