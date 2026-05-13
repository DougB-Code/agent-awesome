/// Memory metadata repair widgets.
part of 'agent_awesome_shell.dart';

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
    final oldMemory = oldWidget.controller.selectedMemory;
    final currentMemory = widget.controller.selectedMemory;
    final oldKey = oldMemory == null
        ? ''
        : oldWidget.controller.memorySelectionKey(oldMemory);
    final currentKey = currentMemory == null
        ? ''
        : widget.controller.memorySelectionKey(currentMemory);
    if (oldKey != currentKey) {
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
    if (!_matchesMemoryRecord(
      memory,
      widget.query,
      extra: _memoryFirewallSearchText(widget.controller, memory.firewall),
    )) {
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
