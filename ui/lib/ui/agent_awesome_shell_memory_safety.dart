/// Memory safety audit widgets.
part of 'agent_awesome_shell.dart';

class _MemorySafetyContent extends StatelessWidget {
  const _MemorySafetyContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds the memory-domain safety event trail.
  @override
  Widget build(BuildContext context) {
    final events = controller.memorySafetyEvents.where((event) {
      return _matchesFuzzyQuery(
        _memorySafetySearchText(controller, event),
        query,
      );
    }).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MemoryStatusStrip(controller: controller),
          if (controller.memoryBusy || _memoryMessageIsError(controller))
            const SizedBox(height: 14),
          if (events.isEmpty)
            const PanelEmptyBlock(label: 'No memory safety events')
          else ...<Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: controller.clearMemorySafetyEvents,
                icon: const Icon(Icons.clear_all_outlined),
                label: const Text('Clear'),
              ),
            ),
            const SizedBox(height: 8),
            for (final event in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MemorySafetyEventTile(
                  controller: controller,
                  event: event,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MemorySafetyEventTile extends StatelessWidget {
  const _MemorySafetyEventTile({required this.controller, required this.event});

  final AgentAwesomeAppController controller;
  final MemorySafetyEvent event;

  /// Builds one memory safety event review tile.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final source = controller.memoryDomainLabel(event.sourceDomain);
    final target = controller.memoryDomainLabel(event.targetDomain);
    final route = source.isEmpty && target.isEmpty
        ? ''
        : '${source.isEmpty ? event.sourceDomain : source} -> ${target.isEmpty ? event.targetDomain : target}';
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(_memorySafetyIcon(event), color: colors.green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  event.title,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(event.detail, style: TextStyle(color: colors.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _MemoryBadge(label: event.severity),
              _MemoryBadge(label: _memoryLabel(event.kind)),
              if (event.approved) const _MemoryBadge(label: 'Approved'),
              if (route.trim().isNotEmpty) PanelBadge(label: route),
              if (event.sourceMemoryId.isNotEmpty)
                PanelBadge(label: event.sourceMemoryId),
              PanelBadge(label: formatOptionalLocalDateTime(event.createdAt)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Returns a compact icon for one memory safety event.
IconData _memorySafetyIcon(MemorySafetyEvent event) {
  if (event.severity == 'error') {
    return Icons.error_outline;
  }
  if (event.kind.startsWith('blocked')) {
    return Icons.block_outlined;
  }
  if (event.approved) {
    return Icons.verified_user_outlined;
  }
  return Icons.policy_outlined;
}

/// Builds searchable text for one memory safety event.
String _memorySafetySearchText(
  AgentAwesomeAppController controller,
  MemorySafetyEvent event,
) {
  return <String>[
    event.kind,
    event.severity,
    event.title,
    event.detail,
    event.sourceDomain,
    event.targetDomain,
    controller.memoryDomainLabel(event.sourceDomain),
    controller.memoryDomainLabel(event.targetDomain),
    event.sourceMemoryId,
  ].join(' ');
}
