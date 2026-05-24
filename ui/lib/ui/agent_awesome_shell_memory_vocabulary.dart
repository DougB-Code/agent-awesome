/// Memory controlled vocabularies and command-area builders.
part of 'agent_awesome_shell.dart';

const List<String> _memoryKinds = <String>[
  'conversation',
  'document',
  'tool_output',
  'artifact',
  'summary',
  'entity_page',
  'timeline',
  'profile_fact',
];

const List<String> _memoryTrustLevels = <String>[
  'source_original',
  'user_asserted',
  'model_extracted',
  'model_synthesized',
  'externally_verified',
];

const List<String> _memorySensitivities = <String>[
  'public',
  'internal',
  'private',
  'restricted',
];

const List<String> _memoryStatuses = <String>[
  'active',
  'superseded',
  'deprecated',
  'archived',
];

const String _memoryDetailsDetailId = 'details';
const String _memorySourceDetailId = 'source';
const String _memoryRelationsDetailId = 'relations';
const String _memoryMetadataDetailId = 'metadata';
const String _memoryCorrectionsDetailId = 'corrections';
const String _memoryPagesDetailId = 'pages';
const String _memoryMapDetailId = 'map';
const String _memorySafetyDetailId = 'safety';
const String _memoryCaptureDetailId = 'capture';

/// Builds the memory discovery areas used by the command subshell.
List<SwitcherPanelArea> _memoryCommandAreas(
  AgentAwesomeAppController controller,
) {
  return <SwitcherPanelArea>[
    SwitcherPanelArea(
      id: 'memory_records',
      title: 'Records',
      icon: Icons.manage_search,
      builder: (query) =>
          _MemorySearchContent(controller: controller, query: query),
    ),
    SwitcherPanelArea(
      id: 'memory_review',
      title: 'Review',
      icon: Icons.rule_folder_outlined,
      builder: (query) =>
          _MemoryReviewContent(controller: controller, query: query),
    ),
  ];
}

/// Returns the selected-memory detail modes for the memory subshell.
List<CommandPanelDetailMode> _memoryDetailModes() {
  return const <CommandPanelDetailMode>[
    CommandPanelDetailMode(
      id: _memoryDetailsDetailId,
      label: 'Details',
      icon: Icons.info_outline,
    ),
    CommandPanelDetailMode(
      id: _memorySourceDetailId,
      label: 'Source',
      icon: Icons.article_outlined,
    ),
    CommandPanelDetailMode(
      id: _memoryRelationsDetailId,
      label: 'Relations',
      icon: Icons.hub_outlined,
    ),
    CommandPanelDetailMode(
      id: _memoryMetadataDetailId,
      label: 'Metadata',
      icon: Icons.edit_note,
    ),
    CommandPanelDetailMode(
      id: _memoryCorrectionsDetailId,
      label: 'Corrections',
      icon: Icons.fact_check_outlined,
    ),
    CommandPanelDetailMode(
      id: _memoryPagesDetailId,
      label: 'Pages',
      icon: Icons.view_timeline_outlined,
    ),
    CommandPanelDetailMode(
      id: _memoryMapDetailId,
      label: 'Map',
      icon: Icons.account_tree_outlined,
    ),
    CommandPanelDetailMode(
      id: _memorySafetyDetailId,
      label: 'Safety',
      icon: Icons.policy_outlined,
    ),
    CommandPanelDetailMode(
      id: _memoryCaptureDetailId,
      label: 'Capture',
      icon: Icons.add_box_outlined,
    ),
  ];
}

/// _MemoryCommandSubShell renders memory in the official command subshell.
