/// Defines the canonical Today executive summary projection for the UI.
library;

import 'json_value.dart';

/// ExecutiveSummaryProjection stores the server-owned Today read model.
class ExecutiveSummaryProjection {
  /// Creates a complete executive summary projection.
  const ExecutiveSummaryProjection({
    this.schemaVersion = 'agent-awesome/executive-summary/v1',
    this.generatedAt,
    this.firewall = const ProjectionFirewall(),
    this.horizon = 'today',
    this.title = 'Today',
    this.subtitle = 'Here is what matters now.',
    this.narrativeSummary = '',
    this.metrics = const <SummaryMetric>[],
    this.attention = const AttentionProjection(),
    this.openLoops = const OpenLoopProjection(),
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

  /// Memory firewall summarized by this projection.
  final ProjectionFirewall firewall;

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
    ProjectionFirewall? firewall,
    String? horizon,
    String? title,
    String? subtitle,
    String? narrativeSummary,
    List<SummaryMetric>? metrics,
    AttentionProjection? attention,
    OpenLoopProjection? openLoops,
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
      firewall: firewall ?? this.firewall,
      horizon: horizon ?? this.horizon,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      narrativeSummary: narrativeSummary ?? this.narrativeSummary,
      metrics: metrics ?? this.metrics,
      attention: attention ?? this.attention,
      openLoops: openLoops ?? this.openLoops,
      timeHorizon: timeHorizon ?? this.timeHorizon,
      delegation: delegation ?? this.delegation,
      riskUnblocks: riskUnblocks ?? this.riskUnblocks,
      coverage: coverage ?? this.coverage,
      quality: quality ?? this.quality,
      links: links ?? this.links,
    );
  }
}

/// ProjectionFirewall stores the memory firewall summarized by a projection.
class ProjectionFirewall {
  /// Creates projection firewall metadata.
  const ProjectionFirewall({
    this.kind = 'user',
    this.id = '',
    this.label = 'User',
  });

  /// Firewall kind or id.
  final String kind;

  /// Optional actor or owner id.
  final String id;

  /// User-facing firewall label.
  final String label;
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
  final object = jsonObject(content);
  return ExecutiveSummaryProjection(
    schemaVersion: stringValue(
      object['schema_version'],
      fallback: 'agent-awesome/executive-summary/v1',
    ),
    generatedAt: parseOptionalDateTime(object['generated_at']),
    firewall: _parseProjectionFirewall(object['firewall']),
    horizon: stringValue(object['horizon'], fallback: 'today'),
    title: stringValue(object['title'], fallback: 'Today'),
    subtitle: stringValue(
      object['subtitle'],
      fallback: 'Here is what matters now.',
    ),
    narrativeSummary: stringValue(object['narrative_summary']),
    metrics: _parseMetrics(object['metrics']),
    attention: _parseAttention(object['attention']),
    openLoops: _parseOpenLoops(object['open_loops']),
    timeHorizon: _parseTimeHorizon(object['time_horizon']),
    delegation: _parseDelegation(object['delegation']),
    riskUnblocks: _parseRiskUnblocks(object['risk_unblocks']),
    coverage: _parseCoverage(object['coverage']),
    quality: _parseQuality(object['quality']),
    links: _parseLinks(object['links']),
  );
}

/// Parses projection firewall metadata.
ProjectionFirewall _parseProjectionFirewall(dynamic content) {
  final object = jsonObject(content);
  return ProjectionFirewall(
    kind: stringValue(object['kind'], fallback: 'user'),
    id: stringValue(object['id']),
    label: stringValue(object['label'], fallback: 'User'),
  );
}

/// Parses an item explanation response.
ExecutiveSummaryItemExplanation parseExecutiveSummaryItemExplanation(
  dynamic content,
) {
  final object = jsonObject(content);
  return ExecutiveSummaryItemExplanation(
    itemId: stringValue(object['item_id']),
    title: stringValue(object['title']),
    reason: stringValue(object['reason']),
    evidence: _parseEvidence(object['evidence']),
    confidence: doubleValue(object['confidence']),
    limits: stringList(object['limits']),
  );
}

/// Parses metric card data.
List<SummaryMetric> _parseMetrics(dynamic content) {
  if (content is! List) {
    return const <SummaryMetric>[];
  }
  return content.whereType<Map<String, dynamic>>().map((metric) {
    return SummaryMetric(
      id: stringValue(metric['id']),
      label: stringValue(metric['label']),
      value: stringValue(metric['value']),
      subtitle: stringValue(metric['subtitle']),
      severity: stringValue(metric['severity'], fallback: 'normal'),
      link: _parseLink(metric['link']),
    );
  }).toList();
}

/// Parses the attention section.
AttentionProjection _parseAttention(dynamic content) {
  final object = jsonObject(content);
  return AttentionProjection(
    items: _parseItems(object['items']),
    link: _parseLink(object['link']),
  );
}

/// Parses the open-loop radar section.
OpenLoopProjection _parseOpenLoops(dynamic content) {
  final object = jsonObject(content);
  return OpenLoopProjection(
    categories: _parseOpenLoopCategories(object['categories']),
    link: _parseLink(object['link']),
  );
}

/// Parses fixed time-horizon buckets.
TimeHorizonProjection _parseTimeHorizon(dynamic content) {
  final object = jsonObject(content);
  return TimeHorizonProjection(
    buckets: _parseTimeHorizonBuckets(object['buckets']),
    link: _parseLink(object['link']),
  );
}

/// Parses agent delegation buckets.
DelegationProjection _parseDelegation(dynamic content) {
  final object = jsonObject(content);
  return DelegationProjection(
    buckets: _parseDelegationBuckets(object['buckets']),
    link: _parseLink(object['link']),
  );
}

/// Parses risk and unblock chains.
RiskUnblockProjection _parseRiskUnblocks(dynamic content) {
  final object = jsonObject(content);
  return RiskUnblockProjection(
    chains: _parseRiskChains(object['chains']),
    link: _parseLink(object['link']),
  );
}

/// Parses source coverage details.
CoverageProjection _parseCoverage(dynamic content) {
  final object = jsonObject(content);
  return CoverageProjection(
    good: stringList(object['good']),
    partial: stringList(object['partial']),
    notConnected: stringList(object['not_connected']),
    promise: stringValue(
      object['promise'],
      fallback: 'I only use information that is source-backed in memory.',
    ),
  );
}

/// Parses projection quality metadata.
ProjectionQualitySummary _parseQuality(dynamic content) {
  final object = jsonObject(content);
  return ProjectionQualitySummary(
    label: stringValue(object['label'], fallback: 'Sparse'),
    relationCoverage: doubleValue(object['relation_coverage']),
    taskCount: intValue(object['task_count']),
    unknownDomains: stringList(object['unknown_domains']),
    limits: stringList(object['limits']),
  );
}

/// Parses open-loop category counters.
List<OpenLoopCategory> _parseOpenLoopCategories(dynamic content) {
  if (content is! List) {
    return const <OpenLoopCategory>[];
  }
  return content.whereType<Map<String, dynamic>>().map((category) {
    return OpenLoopCategory(
      id: stringValue(category['id']),
      label: stringValue(category['label']),
      count: intValue(category['count']),
      severity: stringValue(category['severity']),
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
      id: stringValue(bucket['id']),
      label: stringValue(bucket['label']),
      count: intValue(bucket['count']),
      summary: stringValue(bucket['summary']),
      topItem: stringValue(bucket['top_item']),
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
      id: stringValue(bucket['id']),
      label: stringValue(bucket['label']),
      count: intValue(bucket['count']),
      items: _parseItems(bucket['items']),
      severity: stringValue(bucket['severity']),
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
      id: stringValue(chain['id']),
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
      taskId: stringValue(node['task_id']),
      title: stringValue(node['title']),
      subtitle: stringValue(node['subtitle']),
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
      id: stringValue(item['id']),
      kind: stringValue(item['kind'], fallback: 'item'),
      lane: _validLane(stringValue(item['lane'])),
      title: stringValue(item['title'], fallback: 'Untitled item'),
      subtitle: stringValue(item['subtitle']),
      reason: stringValue(item['reason']),
      score: doubleValue(item['score']),
      confidence: doubleValue(item['confidence']),
      status: stringValue(item['status']),
      priority: stringValue(item['priority']),
      taskId: stringValue(item['task_id']),
      person: stringValue(item['person']),
      project: stringValue(item['project']),
      dueAt: parseOptionalDateTime(item['due_at']),
      scheduledAt: parseOptionalDateTime(item['scheduled_at']),
      followUpAt: parseOptionalDateTime(item['follow_up_at']),
      estimateMinutes: intValue(item['estimate_minutes']),
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
      kind: stringValue(source['kind']),
      id: stringValue(source['id']),
      label: stringValue(source['label']),
      relationship: stringValue(source['relationship']),
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
    id: stringValue(action['id']),
    label: stringValue(action['label']),
    tool: stringValue(action['tool']),
    safety: stringValue(action['safety']),
    payload: jsonObject(action['payload']),
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
  final object = jsonObject(content);
  return ProjectionLink(
    label: stringValue(object['label']),
    route: stringValue(object['route']),
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
