/// Memory correction capture and review widgets.
part of 'agent_awesome_shell.dart';

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
    if (!_matchesMemoryRecord(
      memory,
      widget.query,
      extra: _memoryFirewallSearchText(widget.controller, memory.firewall),
    )) {
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
                        firewallLabel: widget.controller.memoryFirewallLabel(
                          correction.firewall,
                        ),
                        firewallAudience: widget.controller
                            .memoryFirewallAudienceLabel(correction.firewall),
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
