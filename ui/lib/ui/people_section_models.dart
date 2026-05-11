/// Private view models for the people workspace.
part of 'people_section.dart';

/// _ContactItem is the contact UI model derived from memory and tasks.
class _ContactItem {
  /// Creates a contact display item.
  const _ContactItem({
    required this.id,
    required this.name,
    required this.entityId,
    required this.summary,
    required this.statusLabel,
    required this.openTaskCount,
    required this.memoryRecords,
    required this.tasks,
    required this.commitments,
    required this.contexts,
    required this.scopeLabels,
    required this.topics,
    required this.primaryMemory,
    required this.primaryContext,
    required this.lastUpdatedAt,
  });

  /// Stable contact id.
  final String id;

  /// Display name.
  final String name;

  /// Best known canonical entity id.
  final String entityId;

  /// Short profile summary.
  final String summary;

  /// Current contact status label.
  final String statusLabel;

  /// Count of open tasks assigned to this contact.
  final int openTaskCount;

  /// Memory records mentioning this contact.
  final List<MemoryRecord> memoryRecords;

  /// Tasks owned by this contact.
  final List<WorkspaceTask> tasks;

  /// Commitments involving this contact.
  final List<TaskCommitment> commitments;

  /// Scoped context slices for this contact.
  final List<_ContactContext> contexts;

  /// Scope labels represented by this contact.
  final List<String> scopeLabels;

  /// Topic labels associated with this contact.
  final List<String> topics;

  /// Primary memory record used for entity-page actions.
  final MemoryRecord? primaryMemory;

  /// Primary context used for default note routing.
  final _ContactContext? primaryContext;

  /// Most recent timestamp across linked records.
  final DateTime? lastUpdatedAt;
}

/// _ContactContext stores one scoped contact slice.
class _ContactContext {
  /// Creates an immutable contact context slice.
  const _ContactContext({
    required this.id,
    required this.scope,
    required this.label,
    required this.summary,
    required this.sensitivityLabel,
    required this.sourceCount,
    required this.openTaskCount,
    required this.commitmentCount,
    required this.memoryRecords,
    required this.tasks,
    required this.commitments,
    required this.topics,
    required this.lastUpdatedAt,
  });

  /// Stable context id.
  final String id;

  /// Memory or inferred activity scope.
  final String scope;

  /// User-facing project, trip, domain, or topic label.
  final String label;

  /// Concise summary for this context.
  final String summary;

  /// Sensitivity summary for memory records in this context.
  final String sensitivityLabel;

  /// Source-backed memory count.
  final int sourceCount;

  /// Open task count.
  final int openTaskCount;

  /// Commitment count.
  final int commitmentCount;

  /// Memory records in this context.
  final List<MemoryRecord> memoryRecords;

  /// Tasks in this context.
  final List<WorkspaceTask> tasks;

  /// Commitments in this context.
  final List<TaskCommitment> commitments;

  /// Topic labels in this context.
  final List<String> topics;

  /// Most recent timestamp across context data.
  final DateTime? lastUpdatedAt;

  /// Combined display label used in compact badges.
  String get displayLabel {
    return '${_contactLabel(scope)} / $label';
  }
}

/// _ContactAggregate collects contact state before final sorting.
class _ContactAggregate {
  /// Creates a mutable contact aggregate.
  _ContactAggregate({required this.id, required this.name});

  /// Stable contact id.
  final String id;

  /// Display name.
  final String name;

  /// Entity ids linked by memory records.
  final Set<String> entityIds = <String>{};

  /// Memory records mentioning this contact.
  final List<MemoryRecord> memoryRecords = <MemoryRecord>[];

  /// Tasks owned by this contact.
  final List<WorkspaceTask> tasks = <WorkspaceTask>[];

  /// Commitments involving this contact.
  final List<TaskCommitment> commitments = <TaskCommitment>[];

  /// Topic labels gathered from records and work.
  final Set<String> topics = <String>{};
}

/// _ContactContextAggregate collects context state before sorting.
class _ContactContextAggregate {
  /// Creates a mutable contact context aggregate.
  _ContactContextAggregate({
    required this.id,
    required this.scope,
    required this.label,
  });

  /// Stable context id.
  final String id;

  /// Scope represented by this context.
  final String scope;

  /// Context display label.
  final String label;

  /// Memory records in this context.
  final List<MemoryRecord> memoryRecords = <MemoryRecord>[];

  /// Tasks in this context.
  final List<WorkspaceTask> tasks = <WorkspaceTask>[];

  /// Commitments in this context.
  final List<TaskCommitment> commitments = <TaskCommitment>[];

  /// Topics gathered for this context.
  final Set<String> topics = <String>{};

  /// Sensitivity values from source-backed records.
  final Set<String> sensitivities = <String>{};
}

/// _ContactFilter describes the filters shown in the contact library.
enum _ContactFilter {
  /// All contacts.
  all('All contacts', Icons.people_alt_outlined),

  /// Contacts with active tasks.
  active('Active', Icons.task_alt_outlined),

  /// Contacts with source-backed memory.
  sources('Sources', Icons.source_outlined),

  /// Contacts with first-class commitments.
  commitments('Commitments', Icons.handshake_outlined),

  /// Contacts with more than one scope/context slice.
  multiContext('Multi-context', Icons.account_tree_outlined),

  /// Contacts currently known only from work ownership.
  taskOwners('Task owners', Icons.assignment_ind_outlined);

  /// Creates a contact filter.
  const _ContactFilter(this.label, this.icon);

  /// Display label.
  final String label;

  /// Display icon.
  final IconData icon;
}
