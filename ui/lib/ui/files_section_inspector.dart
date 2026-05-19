/// Selected-file inspector panels and metadata rows.
part of 'files_section.dart';

/// _FileInspectorContent renders details for the selected file.
class _FileInspectorContent extends StatelessWidget {
  /// Creates selected file inspector content.
  const _FileInspectorContent({
    required this.controller,
    required this.file,
    required this.modeId,
    required this.onSendToChat,
  });

  /// Shared app controller used for configured firewall labels.
  final AgentAwesomeAppController controller;

  /// Selected file.
  final _AgentFileItem? file;

  /// Active inspector mode.
  final String modeId;

  /// Sends the selected file to the current chat.
  final VoidCallback? onSendToChat;

  /// Builds the detail mode body.
  @override
  Widget build(BuildContext context) {
    final selected = file;
    if (selected == null) {
      return const PanelEmptyBlock(
        label:
            'No files indexed yet. Files are PDFs, spreadsheets, images, and source documents, not chat messages.',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: switch (modeId) {
        _fileSourceModeId => _FileSourceDetails(file: selected),
        _fileAccessModeId => _FileAccessDetails(
          controller: controller,
          file: selected,
        ),
        _ => _FilePrimaryDetails(file: selected, onSendToChat: onSendToChat),
      },
    );
  }
}

/// _FilePrimaryDetails renders the main selected-file summary.
class _FilePrimaryDetails extends StatelessWidget {
  /// Creates primary file details.
  const _FilePrimaryDetails({required this.file, required this.onSendToChat});

  /// Selected file.
  final _AgentFileItem file;

  /// Sends this file to chat.
  final VoidCallback? onSendToChat;

  /// Builds the selected-file overview.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accent = _fileKindAccent(context, file.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InspectorHeader(file: file),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onSendToChat,
          icon: const Icon(Icons.send_outlined, size: 16),
          label: const Text('Send to chat'),
        ),
        const SizedBox(height: 12),
        _InspectorBlock(
          label: 'Summary',
          child: SelectableText(
            file.summary,
            style: TextStyle(color: colors.muted, fontSize: 15, height: 1.35),
          ),
        ),
        const SizedBox(height: 12),
        _InspectorBlock(
          label: 'File',
          child: Column(
            children: <Widget>[
              _InspectorRow(label: 'Type', value: file.kind.label),
              _InspectorRow(label: 'Media', value: file.mediaLabel),
              _InspectorRow(label: 'Path', value: file.pathLabel),
              _InspectorRow(label: 'Checksum', value: file.checksumLabel),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InspectorBlock(
          label: 'Topics',
          child: file.topics.isEmpty
              ? Text('No topics', style: TextStyle(color: colors.muted))
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final topic in file.topics)
                      _FileTypeBadge(label: topic, color: accent),
                  ],
                ),
        ),
      ],
    );
  }
}

/// _FileSourceDetails renders provenance for the selected file.
class _FileSourceDetails extends StatelessWidget {
  /// Creates source details.
  const _FileSourceDetails({required this.file});

  /// Selected file.
  final _AgentFileItem file;

  /// Builds file source metadata.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InspectorHeader(file: file),
        const SizedBox(height: 18),
        _InspectorBlock(
          label: 'Source',
          child: Column(
            children: <Widget>[
              _InspectorRow(label: 'System', value: file.sourceSystem),
              _InspectorRow(label: 'Source id', value: file.sourceId),
              _InspectorRow(label: 'File record id', value: file.evidenceId),
              _InspectorRow(label: 'Memory id', value: file.memoryId),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InspectorBlock(
          label: 'File path',
          child: SelectableText(file.pathLabel),
        ),
      ],
    );
  }
}

/// _FileAccessDetails renders access metadata for the selected file.
class _FileAccessDetails extends StatelessWidget {
  /// Creates access details.
  const _FileAccessDetails({required this.controller, required this.file});

  /// Shared app controller used for configured firewall labels.
  final AgentAwesomeAppController controller;

  /// Selected file.
  final _AgentFileItem file;

  /// Builds firewall and lifecycle metadata.
  @override
  Widget build(BuildContext context) {
    final audience = controller.memoryFirewallAudienceLabel(file.firewall);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InspectorHeader(file: file),
        const SizedBox(height: 18),
        _InspectorBlock(
          label: 'Access',
          child: Column(
            children: <Widget>[
              _InspectorRow(
                label: 'Firewall',
                value: controller.memoryFirewallLabel(file.firewall),
              ),
              if (audience.isNotEmpty)
                _InspectorRow(label: 'Shared with', value: audience),
              _InspectorRow(label: 'Sensitivity', value: file.sensitivity),
              _InspectorRow(label: 'Trust', value: file.trustLevel),
              _InspectorRow(label: 'Status', value: file.status),
            ],
          ),
        ),
      ],
    );
  }
}

/// _InspectorHeader renders the selected-file heading.
class _InspectorHeader extends StatelessWidget {
  /// Creates the inspector header.
  const _InspectorHeader({required this.file});

  /// Selected file.
  final _AgentFileItem file;

  /// Builds the selected-file heading row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accent = _fileKindAccent(context, file.kind);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FileIconBox(icon: file.kind.icon, color: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SelectableText(
                file.title,
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                file.kind.label,
                style: TextStyle(color: colors.muted, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// _InspectorBlock renders a titled detail group.
class _InspectorBlock extends StatelessWidget {
  /// Creates an inspector block.
  const _InspectorBlock({required this.label, required this.child});

  /// Group label.
  final String label;

  /// Group content.
  final Widget child;

  /// Builds one bordered inspector group.
  @override
  Widget build(BuildContext context) {
    return PanelSectionBlock.gradient(
      title: label,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[child],
      ),
    );
  }
}

/// _InspectorRow renders one selected-file metadata row.
class _InspectorRow extends StatelessWidget {
  /// Creates an inspector metadata row.
  const _InspectorRow({required this.label, required this.value});

  /// Row label.
  final String label;

  /// Row value.
  final String value;

  /// Builds a label/value row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final display = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                color: colors.subtle,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              display,
              style: TextStyle(
                color: colors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
