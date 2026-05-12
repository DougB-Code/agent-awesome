/// Memory capture form and duplicate-hint widgets.
part of 'agent_awesome_shell.dart';

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
  String _firewall = 'user';
  String _trust = 'source_original';
  String _sensitivity = 'private';

  /// Initializes live duplicate hint refresh.
  @override
  void initState() {
    super.initState();
    _firewall = widget.controller.defaultMemoryFirewallId;
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
          return probe.trim().isNotEmpty &&
              _matchesMemoryRecord(
                record,
                probe,
                extra: _memoryFirewallSearchText(
                  widget.controller,
                  record.firewall,
                ),
              );
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
                        value: _firewall,
                        values: widget.controller.memoryFirewallIds,
                        tooltip: 'Firewall',
                        labelForValue:
                            widget.controller.memoryFirewallPickerLabel,
                        onChanged: (value) => setState(() => _firewall = value),
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
                        firewallLabel: widget.controller.memoryFirewallLabel(
                          record.firewall,
                        ),
                        firewallAudience: widget.controller
                            .memoryFirewallAudienceLabel(record.firewall),
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
      firewall: _coerceDropdownValue(
        widget.controller.memoryFirewallIds,
        _firewall,
        widget.controller.defaultMemoryFirewallId,
      ),
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
