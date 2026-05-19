/// Selected-memory overview, source, and relationship detail widgets.
part of 'agent_awesome_shell.dart';

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
    if (!_matchesMemoryRecord(
      memory,
      query,
      extra: _memoryFirewallSearchText(controller, memory.firewall),
    )) {
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
                          fontWeight: FontWeight.w800,
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
                    if (memory.domainId.isNotEmpty)
                      _MemoryBadge(
                        label: controller.memoryDomainLabel(memory.domainId),
                      ),
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
                  label: 'Domain',
                  value: controller.memoryDomainLabel(memory.domainId),
                ),
                _MemoryMetadataRow(
                  label: 'Source record id',
                  value: memory.evidenceId,
                ),
                _MemoryMetadataRow(
                  label: 'Source',
                  value: _memorySourceLabel(memory.sourceLabel),
                ),
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
                      _MemoryBadge(label: _memoryLabel(topic)),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: controller.memoryBusy
                          ? null
                          : () => unawaited(
                              controller.hydrateSelectedMemorySource(),
                            ),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Load Source'),
                    ),
                    if (controller.canExportMemoryRecord(memory))
                      FilledButton.icon(
                        onPressed: controller.memoryBusy
                            ? null
                            : () => unawaited(
                                _exportReviewedMemoryCopy(
                                  context,
                                  controller,
                                  memory,
                                ),
                              ),
                        icon: const Icon(Icons.move_up_outlined),
                        label: const Text('Export Reviewed Copy'),
                      ),
                  ],
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

/// Opens a reviewed export dialog and writes the approved copy.
Future<void> _exportReviewedMemoryCopy(
  BuildContext context,
  AgentAwesomeAppController controller,
  MemoryRecord memory,
) async {
  final draft = await _showMemoryExportDialog(context, controller, memory);
  if (draft == null) {
    return;
  }
  await controller.exportMemoryCopyFromUi(memory, draft);
}

/// Shows the declassification editor for one memory-domain export.
Future<MemoryExportDraft?> _showMemoryExportDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  MemoryRecord memory,
) async {
  final title = TextEditingController(text: memory.title);
  final content = TextEditingController(
    text: memory.rawContent.trim().isEmpty
        ? memory.summary
        : memory.rawContent.trim(),
  );
  var firewall = memory.firewall;
  var sensitivity = memory.sensitivity;
  try {
    return await showDialog<MemoryExportDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Export Reviewed Copy'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      PanelTextFormField(controller: title, label: 'Title'),
                      const SizedBox(height: 10),
                      PanelTextFormField(
                        controller: content,
                        label: 'Approved content',
                        maxLines: 10,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: PanelDropdownFormField<String>(
                              label: 'Firewall',
                              value: firewall,
                              values: controller.memoryFirewallIds,
                              tooltip: 'Firewall',
                              labelFor: controller.memoryFirewallPickerLabel,
                              onChanged: (value) {
                                setState(() => firewall = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PanelDropdownFormField<String>(
                              label: 'Sensitivity',
                              value: sensitivity,
                              values: _memorySensitivities,
                              tooltip: 'Sensitivity',
                              labelFor: _memoryLabel,
                              onChanged: (value) {
                                setState(() => sensitivity = value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      MemoryExportDraft(
                        title: title.text.trim(),
                        content: content.text.trim(),
                        firewall: firewall,
                        sensitivity: sensitivity,
                      ),
                    );
                  },
                  child: const Text('Approve Export'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    title.dispose();
    content.dispose();
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
