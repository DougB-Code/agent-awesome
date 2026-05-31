/// Defines manifest data for Agent Awesome app plugins.
library;

/// Directory name for installed AA app plugin packages.
const aaAppPluginPackageDirectoryName = 'app-plugins';

/// Canonical manifest filename inside one AA app plugin package.
const aaAppPluginManifestFilename = 'app.yaml';

/// AppPluginManifest stores one installed app plugin's shell surface contract.
class AppPluginManifest {
  /// Creates a manifest for one app plugin package.
  const AppPluginManifest({
    required this.id,
    required this.name,
    this.description = '',
    this.version = '',
    this.icon = '',
    this.starlarkEntrypoint = '',
    this.renderedFromStarlark = false,
    this.panels = const <AppPluginPanel>[],
    this.integrations = const <AppPluginIntegration>[],
    this.packagePath = '',
  });

  /// Stable plugin id.
  final String id;

  /// Human-readable app name.
  final String name;

  /// Short app purpose.
  final String description;

  /// Package version label.
  final String version;

  /// Optional named icon for shell navigation.
  final String icon;

  /// Relative Starlark entrypoint used by the plugin package.
  final String starlarkEntrypoint;

  /// Whether this manifest was rendered by executing the Starlark entrypoint.
  final bool renderedFromStarlark;

  /// App panels exposed by this plugin.
  final List<AppPluginPanel> panels;

  /// External capabilities required or exposed by this plugin.
  final List<AppPluginIntegration> integrations;

  /// Local package directory that owns the manifest.
  final String packagePath;

  /// Route id for the plugin's default panel.
  String get defaultRoute {
    final panel = defaultPanel;
    if (panel == null) {
      return '';
    }
    return appPluginRoute(id, panel.id);
  }

  /// First panel that should appear in top-level navigation.
  AppPluginPanel? get defaultPanel {
    for (final panel in panels) {
      if (panel.showInSidebar) {
        return panel;
      }
    }
    return panels.isEmpty ? null : panels.first;
  }

  /// Reports whether this plugin can expose a board-style work tool.
  bool get supportsBoardTools {
    return panels.any((panel) => panel.kind == AppPluginPanelKind.board);
  }

  /// Reports whether this manifest is complete enough to load.
  bool get isUsable {
    return id.isNotEmpty && name.trim().isNotEmpty && panels.isNotEmpty;
  }
}

/// AppPluginPanel stores one plugin-owned app surface.
class AppPluginPanel {
  /// Creates one plugin panel descriptor.
  const AppPluginPanel({
    required this.id,
    required this.title,
    this.description = '',
    this.kind = AppPluginPanelKind.custom,
    this.icon = '',
    this.showInSidebar = true,
    this.quickAccess = true,
    this.actions = const <AppPluginAction>[],
    this.blocks = const <AppPluginPanelBlock>[],
  });

  /// Stable panel id inside the plugin package.
  final String id;

  /// Human-readable panel title.
  final String title;

  /// Short panel purpose.
  final String description;

  /// Generic panel behavior class.
  final AppPluginPanelKind kind;

  /// Optional named icon.
  final String icon;

  /// Whether this panel receives a top-level shell navigation entry.
  final bool showInSidebar;

  /// Whether this panel is shown in the plugin command-pane quick access row.
  final bool quickAccess;

  /// Actions the plugin declares for this panel.
  final List<AppPluginAction> actions;

  /// Declarative content blocks rendered in this panel.
  final List<AppPluginPanelBlock> blocks;
}

/// AppPluginPanelBlock stores declarative plugin-owned panel content.
class AppPluginPanelBlock {
  /// Creates one declarative panel block.
  const AppPluginPanelBlock({
    this.title = '',
    this.text = '',
    this.icon = '',
    this.badges = const <String>[],
  });

  /// Optional section title.
  final String title;

  /// Body copy rendered by the plugin panel.
  final String text;

  /// Optional named icon.
  final String icon;

  /// Metadata badges for this block.
  final List<String> badges;
}

/// AppPluginPanelKind identifies a generic app plugin surface.
enum AppPluginPanelKind {
  /// Custom panel rendered by plugin logic.
  custom,

  /// Board-style surface for kanban or similar lane tools.
  board,

  /// Calendar or schedule surface.
  calendar,

  /// Collection catalog or list surface.
  collection,

  /// Dashboard surface.
  dashboard,

  /// Typed data-entry form surface.
  form,
}

/// AppPluginAction stores one plugin-declared command.
class AppPluginAction {
  /// Creates one plugin action descriptor.
  const AppPluginAction({
    required this.id,
    required this.title,
    this.description = '',
    this.kind = '',
    this.target = '',
  });

  /// Stable action id inside the panel.
  final String id;

  /// Human-readable action label.
  final String title;

  /// Short action purpose.
  final String description;

  /// Generic action boundary such as command, MCP, HTTP, or workflow.
  final String kind;

  /// Boundary-specific target reference.
  final String target;
}

/// AppPluginIntegration describes one external plugin capability.
class AppPluginIntegration {
  /// Creates one external integration descriptor.
  const AppPluginIntegration({
    required this.id,
    required this.title,
    this.kind = '',
    this.credentialScope = '',
    this.credential = const AppPluginCredentialRequirement(),
    this.capabilities = const <String>[],
  });

  /// Stable integration id.
  final String id;

  /// Human-readable integration label.
  final String title;

  /// Integration kind such as calendar, command, MCP, HTTP, or workflow.
  final String kind;

  /// Credential scope requested through the credential boundary.
  final String credentialScope;

  /// Typed credential contract requested by this integration.
  final AppPluginCredentialRequirement credential;

  /// Capability labels advertised by the integration.
  final List<String> capabilities;
}

/// AppPluginCredentialRequirement stores typed secret refs for integrations.
class AppPluginCredentialRequirement {
  /// Creates a credential requirement for one plugin integration.
  const AppPluginCredentialRequirement({
    this.kind = '',
    this.profileId = '',
    this.usernameRef = '',
    this.passwordRef = '',
    this.tokenRef = '',
    this.oneTimeCodeSeedRef = '',
    this.allowedDomains = const <String>[],
  });

  /// Credential kind such as website-login, apple-calendar, oauth, or token.
  final String kind;

  /// Stable credential profile id.
  final String profileId;

  /// Keyring/env reference for a username-style value.
  final String usernameRef;

  /// Keyring/env reference for a password-style value.
  final String passwordRef;

  /// Keyring/env reference for token-style auth.
  final String tokenRef;

  /// Keyring/env reference for optional one-time-code seed material.
  final String oneTimeCodeSeedRef;

  /// Domains browser automations may authenticate against with this profile.
  final List<String> allowedDomains;

  /// Whether this requirement describes a browser login profile.
  bool get isWebsiteLogin {
    return kind.trim().toLowerCase() == 'website-login';
  }

  /// Whether this requirement describes an Apple Calendar credential profile.
  bool get isAppleCalendar {
    return kind.trim().toLowerCase() == 'apple-calendar';
  }
}

/// AppPluginRoute stores decoded dynamic app plugin route ids.
class AppPluginRoute {
  /// Creates a decoded plugin route.
  const AppPluginRoute({required this.pluginId, required this.panelId});

  /// Stable plugin id.
  final String pluginId;

  /// Stable panel id.
  final String panelId;
}

/// Builds a top-level app section id for one plugin panel.
String appPluginRoute(String pluginId, String panelId) {
  return 'app-plugin:${appPluginSafeToken(pluginId)}:${appPluginSafeToken(panelId)}';
}

/// Decodes one dynamic app plugin route, returning null for normal sections.
AppPluginRoute? parseAppPluginRoute(String section) {
  final parts = section.split(':');
  if (parts.length != 3 || parts.first != 'app-plugin') {
    return null;
  }
  final pluginId = appPluginSafeToken(parts[1]);
  final panelId = appPluginSafeToken(parts[2]);
  if (pluginId.isEmpty || panelId.isEmpty) {
    return null;
  }
  return AppPluginRoute(pluginId: pluginId, panelId: panelId);
}

/// Parses a panel kind from manifest text.
AppPluginPanelKind appPluginPanelKindFrom(String value) {
  return switch (value.trim().toLowerCase()) {
    'board' || 'kanban' => AppPluginPanelKind.board,
    'calendar' || 'schedule' => AppPluginPanelKind.calendar,
    'collection' || 'list' => AppPluginPanelKind.collection,
    'dashboard' => AppPluginPanelKind.dashboard,
    'form' => AppPluginPanelKind.form,
    _ => AppPluginPanelKind.custom,
  };
}

/// Converts one panel kind to a stable label.
String appPluginPanelKindLabel(AppPluginPanelKind kind) {
  return switch (kind) {
    AppPluginPanelKind.custom => 'Custom',
    AppPluginPanelKind.board => 'Board',
    AppPluginPanelKind.calendar => 'Calendar',
    AppPluginPanelKind.collection => 'Collection',
    AppPluginPanelKind.dashboard => 'Dashboard',
    AppPluginPanelKind.form => 'Form',
  };
}

/// Sanitizes ids used in app routes and manifest keys.
String appPluginSafeToken(String value) {
  final lower = value.trim().toLowerCase();
  final buffer = StringBuffer();
  var lastWasDash = false;
  for (final codeUnit in lower.codeUnits) {
    final isAlphaNumeric =
        (codeUnit >= 97 && codeUnit <= 122) ||
        (codeUnit >= 48 && codeUnit <= 57);
    if (isAlphaNumeric) {
      buffer.writeCharCode(codeUnit);
      lastWasDash = false;
      continue;
    }
    if (!lastWasDash) {
      buffer.write('-');
      lastWasDash = true;
    }
  }
  return buffer.toString().replaceAll(RegExp(r'^-+|-+$'), '');
}
