/// Parses loose app plugin manifest documents into domain models.
library;

import 'app_plugin.dart';

/// Parses a normalized YAML or JSON map into an app plugin manifest.
AppPluginManifest parseAppPluginManifest(
  Map<String, dynamic> map, {
  String packagePath = '',
}) {
  final rawEntrypoint = _stringMap(map['entrypoint']);
  final rawNavigation = _stringMap(map['navigation']);
  final panels = _mapList(map['panels'])
      .map(parseAppPluginPanel)
      .where((panel) => panel.id.isNotEmpty && panel.title.isNotEmpty)
      .toList(growable: false);
  final integrations = _mapList(map['integrations'])
      .map(parseAppPluginIntegration)
      .where((integration) => integration.id.isNotEmpty)
      .toList(growable: false);
  return AppPluginManifest(
    id: appPluginSafeToken(_stringValue(map['id'])),
    name: _stringValue(map['name']),
    description: _stringValue(map['description']),
    version: _stringValue(map['version']),
    icon: _stringValue(rawNavigation['icon'] ?? map['icon']),
    starlarkEntrypoint: _safeRelativePath(
      _stringValue(rawEntrypoint['starlark'] ?? map['starlark']),
    ),
    renderedFromStarlark: _boolValue(
      map['renderedFromStarlark'],
      fallback: false,
    ),
    panels: panels,
    integrations: integrations,
    packagePath: packagePath,
  );
}

/// Parses one plugin panel descriptor.
AppPluginPanel parseAppPluginPanel(Map<String, dynamic> map) {
  final actions = _mapList(map['actions'])
      .map(parseAppPluginAction)
      .where((action) => action.id.isNotEmpty)
      .toList(growable: false);
  final blocks = _mapList(map['blocks'])
      .map(parseAppPluginPanelBlock)
      .where((block) => block.title.isNotEmpty || block.text.isNotEmpty)
      .toList(growable: false);
  return AppPluginPanel(
    id: appPluginSafeToken(_stringValue(map['id'])),
    title: _stringValue(map['title'] ?? map['name']),
    description: _stringValue(map['description']),
    kind: appPluginPanelKindFrom(_stringValue(map['kind'])),
    icon: _stringValue(map['icon']),
    showInSidebar: _boolValue(map['showInSidebar'], fallback: true),
    quickAccess: _boolValue(map['quickAccess'], fallback: true),
    actions: actions,
    blocks: blocks,
  );
}

/// Parses one declarative panel block.
AppPluginPanelBlock parseAppPluginPanelBlock(Map<String, dynamic> map) {
  return AppPluginPanelBlock(
    title: _stringValue(map['title']),
    text: _stringValue(map['text']),
    icon: _stringValue(map['icon']),
    badges: _stringList(map['badges']),
  );
}

/// Parses one plugin action descriptor.
AppPluginAction parseAppPluginAction(Map<String, dynamic> map) {
  return AppPluginAction(
    id: appPluginSafeToken(_stringValue(map['id'])),
    title: _stringValue(map['title'] ?? map['name']),
    description: _stringValue(map['description']),
    kind: _stringValue(map['kind']),
    target: _stringValue(map['target']),
  );
}

/// Parses one external integration descriptor.
AppPluginIntegration parseAppPluginIntegration(Map<String, dynamic> map) {
  return AppPluginIntegration(
    id: appPluginSafeToken(_stringValue(map['id'])),
    title: _stringValue(map['title'] ?? map['name']),
    kind: _stringValue(map['kind']),
    credentialScope: _stringValue(map['credentialScope']),
    credential: parseAppPluginCredentialRequirement(
      _stringMap(map['credential']),
    ),
    capabilities: _stringList(map['capabilities']),
  );
}

/// Parses a typed credential requirement.
AppPluginCredentialRequirement parseAppPluginCredentialRequirement(
  Map<String, dynamic> map,
) {
  return AppPluginCredentialRequirement(
    kind: _stringValue(map['kind']),
    profileId: appPluginSafeToken(
      _stringValue(map['profileId'] ?? map['profile']),
    ),
    usernameRef: _stringValue(map['usernameRef']),
    passwordRef: _stringValue(map['passwordRef']),
    tokenRef: _stringValue(map['tokenRef']),
    oneTimeCodeSeedRef: _stringValue(map['oneTimeCodeSeedRef']),
    allowedDomains: _stringList(map['allowedDomains']),
  );
}

/// Returns map children from loose manifest input.
List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return <Map<String, dynamic>>[
    for (final item in value)
      if (item is Map)
        <String, dynamic>{
          for (final entry in item.entries) entry.key.toString(): entry.value,
        },
  ];
}

/// Returns a string-keyed map from loose manifest input.
Map<String, dynamic> _stringMap(dynamic value) {
  if (value is! Map) {
    return const <String, dynamic>{};
  }
  return <String, dynamic>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

/// Returns one trimmed string from loose manifest input.
String _stringValue(dynamic value) {
  return value?.toString().trim() ?? '';
}

/// Returns a string list from loose manifest input.
List<String> _stringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

/// Returns a bool from loose manifest input.
bool _boolValue(dynamic value, {required bool fallback}) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return switch (value.trim().toLowerCase()) {
      'true' || 'yes' || '1' => true,
      'false' || 'no' || '0' => false,
      _ => fallback,
    };
  }
  return fallback;
}

/// Keeps manifest-owned entrypoint paths inside the plugin package.
String _safeRelativePath(String value) {
  final normalized = value.replaceAll('\\', '/').trim();
  if (normalized.startsWith('/') ||
      normalized.contains('/../') ||
      normalized.startsWith('../') ||
      normalized == '..') {
    return '';
  }
  return normalized;
}
