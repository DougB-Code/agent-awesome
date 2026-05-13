/// Persists app-specific Agent Awesome settings that are not runtime profile concerns.
library;

import 'dart:convert';
import 'dart:io';

import '../domain/json_value.dart';
import 'runtime_profile.dart';

const List<String> _localMemoryPolicyActors = <String>[
  'agent',
  'agent_awesome_ui',
];

/// AgentAwesomeAppSettings stores UI-owned defaults and app model choices.
class AgentAwesomeAppSettings {
  /// Creates app settings for chat defaults and app-owned model work.
  const AgentAwesomeAppSettings({
    this.defaultChatProfilePath = '',
    this.summaryModelConfigPath = '',
    this.summaryModelRef = '',
    this.chatTitleSummariesEnabled = true,
    this.gettingStartedCompleted = false,
    this.memoryFirewalls = defaultMemoryFirewalls,
  });

  /// Runtime profile used by fast-path new chat creation.
  final String defaultChatProfilePath;

  /// Model config used by app-owned chat title summarization.
  final String summaryModelConfigPath;

  /// Provider:model reference used by app-owned chat title summarization.
  final String summaryModelRef;

  /// Whether the app should generate compact chat titles.
  final bool chatTitleSummariesEnabled;

  /// Whether the first-launch setup guide has been completed or hidden.
  final bool gettingStartedCompleted;

  /// User-visible memory firewalls available for capture and retrieval.
  final List<MemoryFirewall> memoryFirewalls;

  /// Returns configured firewalls or the safe defaults.
  List<MemoryFirewall> get effectiveMemoryFirewalls {
    return normalizeMemoryFirewalls(memoryFirewalls);
  }

  /// Returns a copy with selected settings changed.
  AgentAwesomeAppSettings copyWith({
    String? defaultChatProfilePath,
    String? summaryModelConfigPath,
    String? summaryModelRef,
    bool? chatTitleSummariesEnabled,
    bool? gettingStartedCompleted,
    List<MemoryFirewall>? memoryFirewalls,
  }) {
    return AgentAwesomeAppSettings(
      defaultChatProfilePath:
          defaultChatProfilePath ?? this.defaultChatProfilePath,
      summaryModelConfigPath:
          summaryModelConfigPath ?? this.summaryModelConfigPath,
      summaryModelRef: summaryModelRef ?? this.summaryModelRef,
      chatTitleSummariesEnabled:
          chatTitleSummariesEnabled ?? this.chatTitleSummariesEnabled,
      gettingStartedCompleted:
          gettingStartedCompleted ?? this.gettingStartedCompleted,
      memoryFirewalls: memoryFirewalls ?? this.memoryFirewalls,
    );
  }

  /// Encodes settings to stable JSON.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'default_chat_profile': defaultChatProfilePath,
      'summary_model_config': summaryModelConfigPath,
      'summary_model_ref': summaryModelRef,
      'chat_title_summaries_enabled': chatTitleSummariesEnabled,
      'getting_started_completed': gettingStartedCompleted,
      'memory_firewalls': <Map<String, dynamic>>[
        for (final firewall in effectiveMemoryFirewalls) firewall.toJson(),
      ],
    };
  }

  /// Parses settings from decoded JSON.
  factory AgentAwesomeAppSettings.fromJson(Map<String, dynamic> json) {
    return AgentAwesomeAppSettings(
      defaultChatProfilePath: stringValue(json['default_chat_profile']),
      summaryModelConfigPath: stringValue(json['summary_model_config']),
      summaryModelRef: stringValue(json['summary_model_ref']),
      chatTitleSummariesEnabled: boolValue(
        json['chat_title_summaries_enabled'],
        fallback: true,
      ),
      gettingStartedCompleted: boolValue(
        json['getting_started_completed'],
        fallback: false,
      ),
      memoryFirewalls: parseMemoryFirewalls(json['memory_firewalls']),
    );
  }
}

/// MemoryFirewall stores one user-configured memory sharing boundary.
class MemoryFirewall {
  /// Creates a configured memory firewall.
  const MemoryFirewall({
    required this.id,
    required this.label,
    this.shares = const <MemoryFirewallShare>[],
    this.writers = const <MemoryFirewallShare>[],
  });

  /// Stable firewall id stored with memory records and queries.
  final String id;

  /// Human-readable firewall label shown in app controls.
  final String label;

  /// Principals allowed to share this firewall.
  final List<MemoryFirewallShare> shares;

  /// Principals allowed to write into this firewall.
  final List<MemoryFirewallShare> writers;

  /// Human-readable people, teams, or organizations this firewall is shared with.
  List<String> get sharedWith {
    return shares.map((share) => share.label).toList(growable: false);
  }

  /// Human-readable people, teams, or organizations that can write here.
  List<String> get writableBy {
    return writers.map((writer) => writer.label).toList(growable: false);
  }

  /// Encodes this firewall to app settings JSON.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'shares': <Map<String, dynamic>>[
        for (final share in shares) share.toJson(),
      ],
      'writers': <Map<String, dynamic>>[
        for (final writer in writers) writer.toJson(),
      ],
    };
  }

  /// Parses one firewall from decoded settings JSON.
  factory MemoryFirewall.fromJson(Map<String, dynamic> json) {
    return MemoryFirewall(
      id: _normalizeFirewallId(stringValue(json['id'])),
      label: stringValue(json['label']),
      shares: parseMemoryFirewallShares(json['shares']),
      writers: parseMemoryFirewallShares(json['writers']),
    );
  }
}

/// MemoryFirewallShare stores one principal that may share a firewall.
class MemoryFirewallShare {
  /// Creates a structured firewall sharing principal.
  const MemoryFirewallShare({
    required this.kind,
    required this.id,
    required this.label,
  });

  /// Principal kind, such as person, team, company, project, or public.
  final String kind;

  /// Stable principal id.
  final String id;

  /// User-facing principal label.
  final String label;

  /// Encodes this share principal to app settings JSON.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'kind': kind, 'id': id, 'label': label};
  }

  /// Parses one share principal from decoded settings JSON.
  factory MemoryFirewallShare.fromJson(Map<String, dynamic> json) {
    return MemoryFirewallShare(
      kind: _normalizeFirewallShareKind(stringValue(json['kind'])),
      id: _normalizeFirewallId(stringValue(json['id'])),
      label: stringValue(json['label'], trim: true),
    );
  }
}

/// Default memory firewalls used before users customize sharing boundaries.
const List<MemoryFirewall> defaultMemoryFirewalls = <MemoryFirewall>[
  MemoryFirewall(
    id: 'session',
    label: 'Session',
    shares: <MemoryFirewallShare>[
      MemoryFirewallShare(
        kind: 'session',
        id: 'current-chat',
        label: 'Current chat',
      ),
    ],
  ),
  MemoryFirewall(
    id: 'user',
    label: 'User',
    shares: <MemoryFirewallShare>[
      MemoryFirewallShare(kind: 'user', id: 'owner', label: 'Only you'),
    ],
  ),
  MemoryFirewall(
    id: 'household',
    label: 'Household',
    shares: <MemoryFirewallShare>[
      MemoryFirewallShare(
        kind: 'household',
        id: 'members',
        label: 'Household members',
      ),
    ],
  ),
  MemoryFirewall(
    id: 'tenant',
    label: 'Tenant',
    shares: <MemoryFirewallShare>[
      MemoryFirewallShare(
        kind: 'company',
        id: 'tenant',
        label: 'Organization tenant',
      ),
    ],
  ),
  MemoryFirewall(
    id: 'project',
    label: 'Project',
    shares: <MemoryFirewallShare>[
      MemoryFirewallShare(
        kind: 'project',
        id: 'collaborators',
        label: 'Project collaborators',
      ),
    ],
  ),
  MemoryFirewall(
    id: 'global',
    label: 'Global',
    shares: <MemoryFirewallShare>[
      MemoryFirewallShare(
        kind: 'public',
        id: 'service-policy',
        label: 'Everyone allowed by service policy',
      ),
    ],
  ),
];

/// Parses memory firewalls from decoded app settings.
List<MemoryFirewall> parseMemoryFirewalls(Object? value) {
  if (value is! List) {
    return defaultMemoryFirewalls;
  }
  return normalizeMemoryFirewalls(
    value.whereType<Map<String, dynamic>>().map(MemoryFirewall.fromJson),
  );
}

/// Normalizes, deduplicates, and defaults configured memory firewalls.
List<MemoryFirewall> normalizeMemoryFirewalls(
  Iterable<MemoryFirewall> firewalls,
) {
  final seen = <String>{};
  final normalized = <MemoryFirewall>[];
  for (final firewall in firewalls) {
    final id = _normalizeFirewallId(firewall.id);
    if (id.isEmpty || seen.contains(id)) {
      continue;
    }
    seen.add(id);
    normalized.add(
      MemoryFirewall(
        id: id,
        label: firewall.label.trim().isEmpty
            ? _labelFromFirewallId(id)
            : firewall.label.trim(),
        shares: normalizeMemoryFirewallShares(firewall.shares),
        writers: normalizeMemoryFirewallShares(firewall.writers),
      ),
    );
  }
  return normalized.isEmpty
      ? defaultMemoryFirewalls
      : List<MemoryFirewall>.unmodifiable(normalized);
}

/// Converts display text into a stable memory firewall id.
String memoryFirewallIdFromLabel(String value) {
  return _normalizeFirewallId(value);
}

/// Returns whether a memory firewall id is safe for storage and tool calls.
bool isValidMemoryFirewallId(String value) {
  return _normalizeFirewallId(value) == value.trim();
}

/// Parses memory firewall share principals from decoded app settings.
List<MemoryFirewallShare> parseMemoryFirewallShares(Object? value) {
  final parsed = <MemoryFirewallShare>[
    for (final json in jsonObjectList(value))
      MemoryFirewallShare.fromJson(json),
  ];
  return normalizeMemoryFirewallShares(parsed);
}

/// Converts editable principal text to a structured firewall share.
MemoryFirewallShare memoryFirewallShareFromText(String value) {
  final trimmed = value.trim();
  final equals = trimmed.indexOf('=');
  final identity = equals < 0 ? trimmed : trimmed.substring(0, equals).trim();
  final rawLabel = equals < 0 ? '' : trimmed.substring(equals + 1).trim();
  final colon = identity.indexOf(':');
  final rawKind = colon < 0 ? 'principal' : identity.substring(0, colon);
  final rawId = colon < 0 ? identity : identity.substring(colon + 1);
  final normalizedId = _normalizeFirewallId(rawId);
  final fallbackLabel = colon < 0
      ? identity.trim()
      : _labelFromFirewallId(normalizedId);
  final label = rawLabel.isNotEmpty
      ? rawLabel
      : fallbackLabel.isEmpty
      ? _labelFromFirewallId(normalizedId)
      : fallbackLabel;
  return MemoryFirewallShare(
    kind: _normalizeFirewallShareKind(rawKind),
    id: _normalizeFirewallId(rawId.isEmpty ? label : rawId),
    label: label,
  );
}

/// Normalizes and deduplicates structured firewall share principals.
List<MemoryFirewallShare> normalizeMemoryFirewallShares(
  Iterable<MemoryFirewallShare> shares,
) {
  final seen = <String>{};
  final normalized = <MemoryFirewallShare>[];
  for (final share in shares) {
    final kind = _normalizeFirewallShareKind(share.kind);
    final id = _normalizeFirewallId(share.id);
    final label = share.label.trim().isEmpty
        ? _labelFromFirewallId(id)
        : share.label.trim();
    final key = '$kind:$id';
    if (kind.isEmpty || id.isEmpty || seen.contains(key)) {
      continue;
    }
    seen.add(key);
    normalized.add(MemoryFirewallShare(kind: kind, id: id, label: label));
  }
  return List<MemoryFirewallShare>.unmodifiable(normalized);
}

/// Encodes configured firewalls as the JSON policy consumed by memoryd.
Map<String, dynamic> memoryFirewallPolicyJson(
  Iterable<MemoryFirewall> firewalls, {
  Iterable<String> extraLocalActors = const <String>[],
}) {
  final localActors = _normalizedLocalMemoryPolicyActors(extraLocalActors);
  return <String, dynamic>{
    'default_allow': false,
    'firewalls': <Map<String, dynamic>>[
      for (final firewall in normalizeMemoryFirewalls(firewalls))
        <String, dynamic>{
          'firewall': firewall.id,
          'readers': _memoryFirewallPolicyReaders(
            firewall,
            localActors: localActors,
          ),
          'writers': _memoryFirewallPolicyWriters(
            firewall,
            localActors: localActors,
          ),
        },
    ],
  };
}

/// Returns actor principals allowed to read a configured memory firewall.
List<String> _memoryFirewallPolicyReaders(
  MemoryFirewall firewall, {
  required Set<String> localActors,
}) {
  return _memoryFirewallPolicyPrincipals(<MemoryFirewallShare>[
    ...firewall.shares,
    ...firewall.writers,
  ], localActors: localActors);
}

/// Returns actor principals allowed to write a configured memory firewall.
List<String> _memoryFirewallPolicyWriters(
  MemoryFirewall firewall, {
  required Set<String> localActors,
}) {
  return _memoryFirewallPolicyPrincipals(
    firewall.writers,
    localActors: localActors,
  );
}

/// Returns daemon actor strings for configured principals plus local operators.
List<String> _memoryFirewallPolicyPrincipals(
  Iterable<MemoryFirewallShare> principals, {
  required Set<String> localActors,
}) {
  final actors = <String>{...localActors};
  for (final share in principals) {
    if (share.kind == 'public') {
      actors.add('*');
    }
    actors.add(share.id);
    actors.add('${share.kind}:${share.id}');
    final label = share.label.trim().toLowerCase();
    if (label.isNotEmpty) {
      actors.add(label);
    }
  }
  actors.remove('');
  return List<String>.unmodifiable(actors);
}

/// Returns normalized actor principals trusted by the local app runtime.
Set<String> _normalizedLocalMemoryPolicyActors([
  Iterable<String> extraActors = const <String>[],
]) {
  return <String>{
    ..._localMemoryPolicyActors,
    for (final actor in extraActors)
      if (actor.trim().isNotEmpty) actor.trim(),
  };
}

/// Normalizes one memory firewall id to a safe lowercase identifier.
String _normalizeFirewallId(String value) {
  final normalized = value.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9_-]+'),
    '-',
  );
  final trimmed = normalized
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
  if (trimmed.isEmpty) {
    return '';
  }
  final prefixed = RegExp(r'^[a-z0-9]').hasMatch(trimmed)
      ? trimmed
      : 'firewall-$trimmed';
  return prefixed.length <= 64 ? prefixed : prefixed.substring(0, 64);
}

/// Normalizes a firewall share principal kind.
String _normalizeFirewallShareKind(String value) {
  final kind = _normalizeFirewallId(value);
  return kind.isEmpty ? 'principal' : kind;
}

/// Creates a readable label from a memory firewall id.
String _labelFromFirewallId(String id) {
  return id
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

/// AgentAwesomeAppSettingsStore reads and writes app-owned settings.
class AgentAwesomeAppSettingsStore {
  /// Creates a settings store in the standard app config directory.
  const AgentAwesomeAppSettingsStore();

  /// Loads settings, returning defaults when no file exists yet.
  Future<AgentAwesomeAppSettings> load() async {
    final file = File(appSettingsPath());
    if (!await file.exists()) {
      return const AgentAwesomeAppSettings();
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('App settings must be a JSON object');
    }
    return AgentAwesomeAppSettings.fromJson(decoded);
  }

  /// Saves settings to disk.
  Future<void> save(
    AgentAwesomeAppSettings settings, {
    Iterable<String> extraPolicyActors = const <String>[],
  }) async {
    final file = File(appSettingsPath());
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(settings.toJson())}\n');
    await saveMemoryFirewallPolicy(
      settings,
      extraPolicyActors: extraPolicyActors,
    );
  }

  /// Saves the memory daemon policy derived from app firewall settings.
  Future<void> saveMemoryFirewallPolicy(
    AgentAwesomeAppSettings settings, {
    Iterable<String> extraPolicyActors = const <String>[],
  }) async {
    final file = File(memoryFirewallPolicyPath());
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert(memoryFirewallPolicyJson(settings.effectiveMemoryFirewalls, extraLocalActors: extraPolicyActors))}\n',
    );
  }
}

/// Returns the app settings JSON path.
String appSettingsPath() {
  return '${agentAwesomeAppConfigDirectoryPath()}/app_settings.json';
}
