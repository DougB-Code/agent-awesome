/// Shared memory badges, fields, rows, and confirmation helpers.
part of 'agent_awesome_shell.dart';

class _MemoryPanelLabel extends StatelessWidget {
  const _MemoryPanelLabel(this.label);

  final String label;

  /// Builds an uppercase memory panel label.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Text(
      label.toUpperCase(),
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.subtle,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.4,
      ),
    );
  }
}

class _MemoryBadge extends StatelessWidget {
  const _MemoryBadge({required this.label});

  final String label;

  /// Builds a dense metadata badge.
  @override
  Widget build(BuildContext context) {
    return PanelBadge(label: _memoryLabel(label));
  }
}

class _MemoryActiveFilter extends StatelessWidget {
  const _MemoryActiveFilter({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  /// Builds a removable active filter chip.
  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label, overflow: TextOverflow.ellipsis),
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close, size: 16),
    );
  }
}

class _MemoryMetadataRow extends StatelessWidget {
  const _MemoryMetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds one key/value metadata row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: colors.subtle,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '-' : value,
              style: TextStyle(color: colors.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryRelationshipLine extends StatelessWidget {
  const _MemoryRelationshipLine({required this.relationship});

  final MemoryRelationship relationship;

  /// Builds one relationship review row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final isConflict = relationship.type == 'contradicts';
    final accent = isConflict ? colors.coral : context.agentAwesomeLowAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isConflict ? colors.warningSoft : colors.surface,
        gradient: isConflict ? null : context.agentAwesomeCardGradient,
        border: Border.all(color: isConflict ? colors.coral : colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isConflict ? Icons.warning_amber : Icons.link,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _memoryLabel(relationship.type),
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _MemoryBadge(label: _memoryLabel(relationship.trustLevel)),
            ],
          ),
          const SizedBox(height: 8),
          _MemoryMetadataRow(label: 'From', value: relationship.fromId),
          _MemoryMetadataRow(label: 'To', value: relationship.toId),
          _MemoryMetadataRow(label: 'Source', value: relationship.sourceId),
        ],
      ),
    );
  }
}

class _MemorySelectionEmpty extends StatelessWidget {
  const _MemorySelectionEmpty();

  /// Builds the no-selection state for the stewardship panel.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Select a memory',
        style: TextStyle(color: context.agentAwesomeColors.muted),
      ),
    );
  }
}

/// Returns whether a memory record matches a command filter query.
bool _matchesMemoryRecord(
  MemoryRecord record,
  String query, {
  String extra = '',
}) {
  return _matchesFuzzyQuery(
    '${record.title} ${record.summary} ${record.kind} ${record.firewall} '
    '${record.trustLevel} ${record.sensitivity} ${record.status} '
    '${record.sourceLabel} ${record.subjects.join(' ')} '
    '${record.topics.join(' ')} ${record.entityNames.join(' ')} $extra',
    query,
  );
}

/// Returns user-facing firewall text for record filtering.
String _memoryFirewallSearchText(
  AgentAwesomeAppController controller,
  String firewallId,
) {
  return '${controller.memoryFirewallLabel(firewallId)} '
      '${controller.memoryFirewallAudienceLabel(firewallId)}';
}

/// Reports whether the memory route status is an actionable error.
bool _memoryMessageIsError(AgentAwesomeAppController controller) {
  final message = controller.memoryMessage.trim().toLowerCase();
  if (message.isEmpty) {
    return false;
  }
  if (message.startsWith('no memory records') ||
      message.startsWith('loaded ') ||
      message == 'source content loaded' ||
      message.startsWith('searching memory')) {
    return false;
  }
  return message.contains('exception') ||
      message.contains('http 4') ||
      message.contains('http 5') ||
      message.contains('failed') ||
      message.contains('unauthorized') ||
      message.contains('not loaded');
}

/// Returns cross-cutting stewardship reasons for a record.
List<String> _memoryReviewReasons(MemoryRecord record) {
  final reasons = <String>[];
  if (record.sensitivity == 'restricted') {
    reasons.add('restricted');
  }
  if (record.status != 'active') {
    reasons.add(record.status);
  }
  if (record.trustLevel == 'model_extracted' ||
      record.trustLevel == 'model_synthesized') {
    reasons.add(record.trustLevel);
  }
  if (record.topics.isEmpty) {
    reasons.add('missing topics');
  }
  if (record.entityIds.isEmpty && record.entityNames.isEmpty) {
    reasons.add('missing entities');
  }
  if (record.relationships.any((rel) => rel.type == 'contradicts')) {
    reasons.add('contradiction');
  }
  return reasons;
}

/// Coerces a dropdown value to a valid controlled value.
String _coerceDropdownValue(
  List<String> values,
  String value,
  String defaultValue,
) {
  return values.contains(value) ? value : defaultValue;
}

/// Converts controlled vocabulary to readable labels.
String _memoryLabel(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }
  if (normalized == 'adk_chat' ||
      normalized == 'agent_awesome_chat' ||
      normalized == 'chat_session' ||
      normalized == 'google_adk_session' ||
      normalized.startsWith('google_adk_session:') ||
      normalized.startsWith('agent_awesome_chat:')) {
    return 'Chat';
  }
  return value
      .trim()
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

/// Converts internal source identifiers to user-facing labels.
String _memorySourceLabel(String value) {
  final trimmed = value.trim();
  final normalized = trimmed.toLowerCase();
  if (normalized == 'google_adk_session' ||
      normalized == 'agent_awesome_chat' ||
      normalized == 'chat_session') {
    return 'Chat';
  }
  for (final prefix in <String>[
    'google_adk_session:',
    'agent_awesome_chat:',
    'chat_session:',
  ]) {
    if (normalized.startsWith(prefix)) {
      final suffix = trimmed.substring(prefix.length).trim();
      return suffix.isEmpty ? 'Chat' : 'Chat: $suffix';
    }
  }
  return trimmed;
}

Future<bool> _confirmWrite(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Confirm Write'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
