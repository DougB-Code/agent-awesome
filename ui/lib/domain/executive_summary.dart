/// Defines the canonical Today executive summary projection for the UI.
library;

/// ExecutiveSummaryProjection stores the server-owned Today read model.
class ExecutiveSummaryProjection {
  /// Creates a complete executive summary projection.
  const ExecutiveSummaryProjection({
    this.schemaVersion = 'agent-awesome/executive-summary/v1',
    this.generatedAt,
    this.horizon = 'today',
    this.title = 'Today',
    this.subtitle = 'Here is what matters now.',
    this.narrativeSummary = '',
    this.metrics = const <SummaryMetric>[],
    this.attention = const AttentionProjection(),
    this.openLoops = const OpenLoopProjection(),
    this.commitments = const CommitmentProjection(),
    this.timeHorizon = const TimeHorizonProjection(),
    this.delegation = const DelegationProjection(),
    this.riskUnblocks = const RiskUnblockProjection(),
    this.coverage = const CoverageProjection(),
    this.quality = const ProjectionQualitySummary(),
    this.links = const <ProjectionLink>[],
  });

  /// Empty projection used before the memory service responds.
  const ExecutiveSummaryProjection.empty() : this();

  /// Projection schema version.
  final String schemaVersion;

  /// Projection generation time.
  final DateTime? generatedAt;

  /// Projection horizon.
  final String horizon;

  /// Page title.
  final String title;

  /// Page subtitle.
  final String subtitle;

  /// Text summary for non-visual channels.
  final String narrativeSummary;

  /// Top-level metrics.
  final List<SummaryMetric> metrics;

  /// Ranked attention rows.
  final AttentionProjection attention;

  /// Open-loop category summary.
  final OpenLoopProjection openLoops;

  /// Relationship and promise loops.
  final CommitmentProjection commitments;

  /// Time horizon buckets.
  final TimeHorizonProjection timeHorizon;

  /// Agent delegation buckets.
  final DelegationProjection delegation;

  /// Risk and unblock chains.
  final RiskUnblockProjection riskUnblocks;

  /// Source coverage summary.
  final CoverageProjection coverage;

  /// Projection quality summary.
  final ProjectionQualitySummary quality;

  /// Dedicated projection page links.
  final List<ProjectionLink> links;

  /// Returns this projection with selected fields replaced.
  ExecutiveSummaryProjection copyWith({
    String? schemaVersion,
    DateTime? generatedAt,
    String? horizon,
    String? title,
    String? subtitle,
    String? narrativeSummary,
    List<SummaryMetric>? metrics,
    AttentionProjection? attention,
    OpenLoopProjection? openLoops,
    CommitmentProjection? commitments,
    TimeHorizonProjection? timeHorizon,
    DelegationProjection? delegation,
    RiskUnblockProjection? riskUnblocks,
    CoverageProjection? coverage,
    ProjectionQualitySummary? quality,
    List<ProjectionLink>? links,
  }) {
    return ExecutiveSummaryProjection(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      generatedAt: generatedAt ?? this.generatedAt,
      horizon: horizon ?? this.horizon,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      narrativeSummary: narrativeSummary ?? this.narrativeSummary,
      metrics: metrics ?? this.metrics,
      attention: attention ?? this.attention,
      openLoops: openLoops ?? this.openLoops,
      commitments: commitments ?? this.commitments,
      timeHorizon: timeHorizon ?? this.timeHorizon,
      delegation: delegation ?? this.delegation,
      riskUnblocks: riskUnblocks ?? this.riskUnblocks,
      coverage: coverage ?? this.coverage,
      quality: quality ?? this.quality,
      links: links ?? this.links,
    );
  }
}

/// ProjectionLink stores a display label and reserved app route.
class ProjectionLink {
  /// Creates a projection link.
  const ProjectionLink({this.label = '', this.route = ''});

  /// Visible link label.
  final String label;

  /// Reserved app route.
  final String route;
}

/// SummaryMetric stores one top-line Today metric.
class SummaryMetric {
  /// Creates a summary metric.
  const SummaryMetric({
    required this.id,
    required this.label,
    required this.value,
    this.subtitle = '',
    this.severity = 'normal',
    this.link = const ProjectionLink(),
  });

  /// Stable metric id.
  final String id;

  /// Display label.
  final String label;

  /// Display value.
  final String value;

  /// Supporting text.
  final String subtitle;

  /// Semantic severity.
  final String severity;

  /// Detail route.
  final ProjectionLink link;
}

/// ExecutiveSummaryItem stores one explainable projected item.
class ExecutiveSummaryItem {
  /// Creates an executive summary item.
  const ExecutiveSummaryItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.reason,
    this.lane = '',
    this.subtitle = '',
    this.score = 0,
    this.confidence = 0,
    this.status = '',
    this.priority = '',
    this.taskId = '',
    this.person = '',
    this.project = '',
    this.dueAt,
    this.scheduledAt,
    this.followUpAt,
    this.estimateMinutes = 0,
    this.evidence = const <ExecutiveSummaryEvidence>[],
    this.primaryAction,
    this.actions = const <ExecutiveSummaryAction>[],
    this.links = const <ProjectionLink>[],
  });

  /// Stable item id.
  final String id;

  /// Item kind.
  final String kind;

  /// Attention lane.
  final String lane;

  /// Primary title.
  final String title;

  /// Supporting text.
  final String subtitle;

  /// Explanation reason.
  final String reason;

  /// Ranking score.
  final double score;

  /// Source confidence.
  final double confidence;

  /// Task status.
  final String status;

  /// Task priority.
  final String priority;

  /// Linked task id.
  final String taskId;

  /// Linked person label.
  final String person;

  /// Linked project label.
  final String project;

  /// Optional due timestamp.
  final DateTime? dueAt;

  /// Optional scheduled timestamp.
  final DateTime? scheduledAt;

  /// Optional follow-up timestamp.
  final DateTime? followUpAt;

  /// Estimated duration.
  final int estimateMinutes;

  /// Source handles returned by the memory projection API.
  final List<ExecutiveSummaryEvidence> evidence;

  /// Primary action hint.
  final ExecutiveSummaryAction? primaryAction;

  /// Additional action hints.
  final List<ExecutiveSummaryAction> actions;

  /// Detail links.
  final List<ProjectionLink> links;
}

/// ExecutiveSummaryEvidence names one source handle for an item.
class ExecutiveSummaryEvidence {
  /// Creates one source handle.
  const ExecutiveSummaryEvidence({
    required this.kind,
    required this.id,
    required this.label,
    this.relationship = '',
  });

  /// Source handle kind.
  final String kind;

  /// Source handle id.
  final String id;

  /// Display label.
  final String label;

  /// Relationship to the item.
  final String relationship;
}

/// ExecutiveSummaryAction stores one safe or approval-gated action hint.
class ExecutiveSummaryAction {
  /// Creates an executive summary action.
  const ExecutiveSummaryAction({
    required this.label,
    this.id = '',
    this.tool = '',
    this.safety = '',
    this.payload = const <String, dynamic>{},
  });

  /// Stable action id.
  final String id;

  /// Visible label.
  final String label;

  /// Optional tool name.
  final String tool;

  /// Safety classification.
  final String safety;

  /// Tool payload supplied by the projection.
  final Map<String, dynamic> payload;
}

/// AttentionProjection stores visible attention rows.
class AttentionProjection {
  /// Creates an attention projection.
  const AttentionProjection({
    this.items = const <ExecutiveSummaryItem>[],
    this.link = const ProjectionLink(),
  });

  /// Visible attention items.
  final List<ExecutiveSummaryItem> items;

  /// Section link.
  final ProjectionLink link;
}

/// OpenLoopProjection stores open-loop categories.
class OpenLoopProjection {
  /// Creates an open-loop projection.
  const OpenLoopProjection({
    this.categories = const <OpenLoopCategory>[],
    this.link = const ProjectionLink(),
  });

  /// Category counters.
  final List<OpenLoopCategory> categories;

  /// Section link.
  final ProjectionLink link;
}

/// OpenLoopCategory stores one open-loop category count.
class OpenLoopCategory {
  /// Creates one open-loop category.
  const OpenLoopCategory({
    required this.id,
    required this.label,
    required this.count,
    this.severity = '',
    this.topItems = const <ExecutiveSummaryItem>[],
    this.link = const ProjectionLink(),
  });

  /// Stable category id.
  final String id;

  /// Display label.
  final String label;

  /// Item count.
  final int count;

  /// Semantic severity.
  final String severity;

  /// Example items.
  final List<ExecutiveSummaryItem> topItems;

  /// Detail link.
  final ProjectionLink link;
}

/// CommitmentProjection stores visible commitment items.
class CommitmentProjection {
  /// Creates a commitment projection.
  const CommitmentProjection({
    this.items = const <ExecutiveSummaryItem>[],
    this.link = const ProjectionLink(),
  });

  /// Commitment rows.
  final List<ExecutiveSummaryItem> items;

  /// Section link.
  final ProjectionLink link;
}

/// TimeHorizonProjection stores fixed near-term buckets.
class TimeHorizonProjection {
  /// Creates a time horizon projection.
  const TimeHorizonProjection({
    this.buckets = const <TimeHorizonBucket>[],
    this.link = const ProjectionLink(),
  });

  /// Horizon buckets.
  final List<TimeHorizonBucket> buckets;

  /// Section link.
  final ProjectionLink link;
}

/// TimeHorizonBucket stores one horizon bucket.
class TimeHorizonBucket {
  /// Creates one horizon bucket.
  const TimeHorizonBucket({
    required this.id,
    required this.label,
    required this.count,
    this.summary = '',
    this.topItem = '',
    this.link = const ProjectionLink(),
  });

  /// Stable bucket id.
  final String id;

  /// Display label.
  final String label;

  /// Item count.
  final int count;

  /// Compact summary.
  final String summary;

  /// Top item title.
  final String topItem;

  /// Detail link.
  final ProjectionLink link;
}

/// DelegationProjection stores agent-status buckets.
class DelegationProjection {
  /// Creates a delegation projection.
  const DelegationProjection({
    this.buckets = const <DelegationBucket>[],
    this.link = const ProjectionLink(),
  });

  /// Delegation buckets.
  final List<DelegationBucket> buckets;

  /// Section link.
  final ProjectionLink link;
}

/// DelegationBucket stores one agent-status bucket.
class DelegationBucket {
  /// Creates one delegation bucket.
  const DelegationBucket({
    required this.id,
    required this.label,
    required this.count,
    this.items = const <ExecutiveSummaryItem>[],
    this.severity = '',
    this.link = const ProjectionLink(),
  });

  /// Stable bucket id.
  final String id;

  /// Display label.
  final String label;

  /// Total item count.
  final int count;

  /// Visible sample items.
  final List<ExecutiveSummaryItem> items;

  /// Semantic severity.
  final String severity;

  /// Detail link.
  final ProjectionLink link;
}

/// RiskUnblockProjection stores dependency chains.
class RiskUnblockProjection {
  /// Creates a risk and unblock projection.
  const RiskUnblockProjection({
    this.chains = const <RiskUnblockChain>[],
    this.link = const ProjectionLink(),
  });

  /// Visible chains.
  final List<RiskUnblockChain> chains;

  /// Section link.
  final ProjectionLink link;
}

/// RiskUnblockChain stores one blocker-to-outcome sequence.
class RiskUnblockChain {
  /// Creates one risk and unblock chain.
  const RiskUnblockChain({
    required this.id,
    this.nodes = const <RiskUnblockChainNode>[],
    this.suggestedAction,
  });

  /// Stable chain id.
  final String id;

  /// Chain nodes.
  final List<RiskUnblockChainNode> nodes;

  /// Suggested next action.
  final ExecutiveSummaryAction? suggestedAction;
}

/// RiskUnblockChainNode stores one chain node.
class RiskUnblockChainNode {
  /// Creates one chain node.
  const RiskUnblockChainNode({
    required this.title,
    this.taskId = '',
    this.subtitle = '',
  });

  /// Optional task id.
  final String taskId;

  /// Node title.
  final String title;

  /// Node subtitle.
  final String subtitle;
}

/// CoverageProjection stores source coverage and unknown integrations.
class CoverageProjection {
  /// Creates source coverage data.
  const CoverageProjection({
    this.good = const <String>[],
    this.partial = const <String>[],
    this.notConnected = const <String>[],
    this.promise = 'I only use information that is source-backed in memory.',
  });

  /// Well-covered domains.
  final List<String> good;

  /// Partially covered domains.
  final List<String> partial;

  /// Explicitly unknown integrations.
  final List<String> notConnected;

  /// Source-backed privacy promise.
  final String promise;
}

/// ProjectionQualitySummary stores trust and coverage details.
class ProjectionQualitySummary {
  /// Creates projection quality data.
  const ProjectionQualitySummary({
    this.label = 'Sparse',
    this.relationCoverage = 0,
    this.taskCount = 0,
    this.unknownDomains = const <String>[],
    this.limits = const <String>[],
  });

  /// Human quality label.
  final String label;

  /// Share of tasks with visible graph relations.
  final double relationCoverage;

  /// Number of tasks seen by the projection.
  final int taskCount;

  /// Domains known to be unavailable.
  final List<String> unknownDomains;

  /// Source and coverage limits.
  final List<String> limits;
}

/// ExecutiveSummaryItemExplanation explains one projected item.
class ExecutiveSummaryItemExplanation {
  /// Creates an item explanation.
  const ExecutiveSummaryItemExplanation({
    this.itemId = '',
    this.title = '',
    this.reason = '',
    this.evidence = const <ExecutiveSummaryEvidence>[],
    this.confidence = 0,
    this.limits = const <String>[],
  });

  /// Explained item id.
  final String itemId;

  /// Item title.
  final String title;

  /// Explanation reason.
  final String reason;

  /// Source handles.
  final List<ExecutiveSummaryEvidence> evidence;

  /// Explanation confidence.
  final double confidence;

  /// Known limits.
  final List<String> limits;
}

/// Parses a canonical executive summary projection response.
ExecutiveSummaryProjection parseExecutiveSummaryProjection(dynamic content) {
  final object = _mapValue(content);
  return ExecutiveSummaryProjection(
    schemaVersion: _stringValue(
      object['schema_version'],
      fallback: 'agent-awesome/executive-summary/v1',
    ),
    generatedAt: _dateTimeValue(object['generated_at']),
    horizon: _stringValue(object['horizon'], fallback: 'today'),
    title: _stringValue(object['title'], fallback: 'Today'),
    subtitle: _stringValue(
      object['subtitle'],
      fallback: 'Here is what matters now.',
    ),
    narrativeSummary: _stringValue(object['narrative_summary']),
    metrics: _parseMetrics(object['metrics']),
    attention: _parseAttention(object['attention']),
    openLoops: _parseOpenLoops(object['open_loops']),
    commitments: _parseCommitments(object['commitments']),
    timeHorizon: _parseTimeHorizon(object['time_horizon']),
    delegation: _parseDelegation(object['delegation']),
    riskUnblocks: _parseRiskUnblocks(object['risk_unblocks']),
    coverage: _parseCoverage(object['coverage']),
    quality: _parseQuality(object['quality']),
    links: _parseLinks(object['links']),
  );
}

/// Parses an item explanation response.
ExecutiveSummaryItemExplanation parseExecutiveSummaryItemExplanation(
  dynamic content,
) {
  final object = _mapValue(content);
  return ExecutiveSummaryItemExplanation(
    itemId: _stringValue(object['item_id']),
    title: _stringValue(object['title']),
    reason: _stringValue(object['reason']),
    evidence: _parseEvidence(object['evidence']),
    confidence: _doubleValue(object['confidence']),
    limits: _stringList(object['limits']),
  );
}

/// Parses metric card data.
List<SummaryMetric> _parseMetrics(dynamic content) {
  if (content is! List) {
    return const <SummaryMetric>[];
  }
  return content.whereType<Map<String, dynamic>>().map((metric) {
    return SummaryMetric(
      id: _stringValue(metric['id']),
      label: _stringValue(metric['label']),
      value: _stringValue(metric['value']),
      subtitle: _stringValue(metric['subtitle']),
      severity: _stringValue(metric['severity'], fallback: 'normal'),
      link: _parseLink(metric['link']),
    );
  }).toList();
}

/// Parses the attention section.
AttentionProjection _parseAttention(dynamic content) {
  final object = _mapValue(content);
  return AttentionProjection(
    items: _parseItems(object['items']),
    link: _parseLink(object['link']),
  );
}

/// Parses the open-loop radar section.
OpenLoopProjection _parseOpenLoops(dynamic content) {
  final object = _mapValue(content);
  return OpenLoopProjection(
    categories: _parseOpenLoopCategories(object['categories']),
    link: _parseLink(object['link']),
  );
}

/// Parses relationship and promise commitments.
CommitmentProjection _parseCommitments(dynamic content) {
  final object = _mapValue(content);
  return CommitmentProjection(
    items: _parseItems(object['items']),
    link: _parseLink(object['link']),
  );
}

/// Parses fixed time-horizon buckets.
TimeHorizonProjection _parseTimeHorizon(dynamic content) {
  final object = _mapValue(content);
  return TimeHorizonProjection(
    buckets: _parseTimeHorizonBuckets(object['buckets']),
    link: _parseLink(object['link']),
  );
}

/// Parses agent delegation buckets.
DelegationProjection _parseDelegation(dynamic content) {
  final object = _mapValue(content);
  return DelegationProjection(
    buckets: _parseDelegationBuckets(object['buckets']),
    link: _parseLink(object['link']),
  );
}

/// Parses risk and unblock chains.
RiskUnblockProjection _parseRiskUnblocks(dynamic content) {
  final object = _mapValue(content);
  return RiskUnblockProjection(
    chains: _parseRiskChains(object['chains']),
    link: _parseLink(object['link']),
  );
}

/// Parses source coverage details.
CoverageProjection _parseCoverage(dynamic content) {
  final object = _mapValue(content);
  return CoverageProjection(
    good: _stringList(object['good']),
    partial: _stringList(object['partial']),
    notConnected: _stringList(object['not_connected']),
    promise: _stringValue(
      object['promise'],
      fallback: 'I only use information that is source-backed in memory.',
    ),
  );
}

/// Parses projection quality metadata.
ProjectionQualitySummary _parseQuality(dynamic content) {
  final object = _mapValue(content);
  return ProjectionQualitySummary(
    label: _stringValue(object['label'], fallback: 'Sparse'),
    relationCoverage: _doubleValue(object['relation_coverage']),
    taskCount: _intValue(object['task_count']),
    unknownDomains: _stringList(object['unknown_domains']),
    limits: _stringList(object['limits']),
  );
}

/// Parses open-loop category counters.
List<OpenLoopCategory> _parseOpenLoopCategories(dynamic content) {
  if (content is! List) {
    return const <OpenLoopCategory>[];
  }
  return content.whereType<Map<String, dynamic>>().map((category) {
    return OpenLoopCategory(
      id: _stringValue(category['id']),
      label: _stringValue(category['label']),
      count: _intValue(category['count']),
      severity: _stringValue(category['severity']),
      topItems: _parseItems(category['top_items']),
      link: _parseLink(category['link']),
    );
  }).toList();
}

/// Parses time-horizon bucket counters.
List<TimeHorizonBucket> _parseTimeHorizonBuckets(dynamic content) {
  if (content is! List) {
    return const <TimeHorizonBucket>[];
  }
  return content.whereType<Map<String, dynamic>>().map((bucket) {
    return TimeHorizonBucket(
      id: _stringValue(bucket['id']),
      label: _stringValue(bucket['label']),
      count: _intValue(bucket['count']),
      summary: _stringValue(bucket['summary']),
      topItem: _stringValue(bucket['top_item']),
      link: _parseLink(bucket['link']),
    );
  }).toList();
}

/// Parses delegation bucket counters and samples.
List<DelegationBucket> _parseDelegationBuckets(dynamic content) {
  if (content is! List) {
    return const <DelegationBucket>[];
  }
  return content.whereType<Map<String, dynamic>>().map((bucket) {
    return DelegationBucket(
      id: _stringValue(bucket['id']),
      label: _stringValue(bucket['label']),
      count: _intValue(bucket['count']),
      items: _parseItems(bucket['items']),
      severity: _stringValue(bucket['severity']),
      link: _parseLink(bucket['link']),
    );
  }).toList();
}

/// Parses risk chains.
List<RiskUnblockChain> _parseRiskChains(dynamic content) {
  if (content is! List) {
    return const <RiskUnblockChain>[];
  }
  return content.whereType<Map<String, dynamic>>().map((chain) {
    return RiskUnblockChain(
      id: _stringValue(chain['id']),
      nodes: _parseRiskChainNodes(chain['nodes']),
      suggestedAction: _parseOptionalAction(chain['suggested_action']),
    );
  }).toList();
}

/// Parses risk chain nodes.
List<RiskUnblockChainNode> _parseRiskChainNodes(dynamic content) {
  if (content is! List) {
    return const <RiskUnblockChainNode>[];
  }
  return content.whereType<Map<String, dynamic>>().map((node) {
    return RiskUnblockChainNode(
      taskId: _stringValue(node['task_id']),
      title: _stringValue(node['title']),
      subtitle: _stringValue(node['subtitle']),
    );
  }).toList();
}

/// Parses generic executive summary items.
List<ExecutiveSummaryItem> _parseItems(dynamic content) {
  if (content is! List) {
    return const <ExecutiveSummaryItem>[];
  }
  return content.whereType<Map<String, dynamic>>().map((item) {
    return ExecutiveSummaryItem(
      id: _stringValue(item['id']),
      kind: _stringValue(item['kind'], fallback: 'item'),
      lane: _validLane(_stringValue(item['lane'])),
      title: _stringValue(item['title'], fallback: 'Untitled item'),
      subtitle: _stringValue(item['subtitle']),
      reason: _stringValue(item['reason']),
      score: _doubleValue(item['score']),
      confidence: _doubleValue(item['confidence']),
      status: _stringValue(item['status']),
      priority: _stringValue(item['priority']),
      taskId: _stringValue(item['task_id']),
      person: _stringValue(item['person']),
      project: _stringValue(item['project']),
      dueAt: _dateTimeValue(item['due_at']),
      scheduledAt: _dateTimeValue(item['scheduled_at']),
      followUpAt: _dateTimeValue(item['follow_up_at']),
      estimateMinutes: _intValue(item['estimate_minutes']),
      evidence: _parseEvidence(item['evidence']),
      primaryAction: _parseOptionalAction(item['primary_action']),
      actions: _parseActions(item['actions']),
      links: _parseLinks(item['links']),
    );
  }).toList();
}

/// Parses source handles.
List<ExecutiveSummaryEvidence> _parseEvidence(dynamic content) {
  if (content is! List) {
    return const <ExecutiveSummaryEvidence>[];
  }
  return content.whereType<Map<String, dynamic>>().map((source) {
    return ExecutiveSummaryEvidence(
      kind: _stringValue(source['kind']),
      id: _stringValue(source['id']),
      label: _stringValue(source['label']),
      relationship: _stringValue(source['relationship']),
    );
  }).toList();
}

/// Parses action hints.
List<ExecutiveSummaryAction> _parseActions(dynamic content) {
  if (content is! List) {
    return const <ExecutiveSummaryAction>[];
  }
  return content.whereType<Map<String, dynamic>>().map(_parseAction).toList();
}

/// Parses an optional action hint.
ExecutiveSummaryAction? _parseOptionalAction(dynamic content) {
  if (content is! Map<String, dynamic>) {
    return null;
  }
  return _parseAction(content);
}

/// Parses one action hint.
ExecutiveSummaryAction _parseAction(Map<String, dynamic> action) {
  return ExecutiveSummaryAction(
    id: _stringValue(action['id']),
    label: _stringValue(action['label']),
    tool: _stringValue(action['tool']),
    safety: _stringValue(action['safety']),
    payload: _mapValue(action['payload']),
  );
}

/// Parses route links.
List<ProjectionLink> _parseLinks(dynamic content) {
  if (content is! List) {
    return const <ProjectionLink>[];
  }
  return content.whereType<Map<String, dynamic>>().map(_parseLink).toList();
}

/// Parses one route link.
ProjectionLink _parseLink(dynamic content) {
  final object = _mapValue(content);
  return ProjectionLink(
    label: _stringValue(object['label']),
    route: _stringValue(object['route']),
  );
}

/// Normalizes unsupported lanes to the monitor lane.
String _validLane(String lane) {
  switch (lane) {
    case '':
    case 'protect':
    case 'decide':
    case 'do':
    case 'delegate':
    case 'follow_up':
    case 'monitor':
      return lane;
    default:
      return 'monitor';
  }
}

/// Returns a typed JSON object or an empty object.
Map<String, dynamic> _mapValue(dynamic value) {
  return value is Map<String, dynamic> ? value : <String, dynamic>{};
}

/// Returns a non-empty string or the supplied fallback.
String _stringValue(dynamic value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

/// Parses a list of non-empty strings.
List<String> _stringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map(_stringValue).where((item) => item.isNotEmpty).toList();
}

/// Parses an integer from flexible JSON.
int _intValue(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

/// Parses a floating-point number from flexible JSON.
double _doubleValue(dynamic value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

/// Parses an RFC3339 timestamp when present.
DateTime? _dateTimeValue(dynamic value) {
  final text = _stringValue(value);
  if (text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}
