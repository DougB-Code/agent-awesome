/// Renders manifest-backed app plugin panels inside the shared command shell.
library;

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../domain/app_plugin.dart';
import 'panels/panels.dart';
import 'theme.dart';

const String _pluginDetailsModeId = 'details';
const String _pluginActionsModeId = 'actions';
const String _pluginIntegrationsModeId = 'integrations';
const String _pluginScriptModeId = 'script';

/// AppPluginCommandPanel hosts one installed app plugin in the app shell.
class AppPluginCommandPanel extends StatefulWidget {
  /// Creates a plugin command panel for one dynamic app route.
  const AppPluginCommandPanel({
    super.key,
    required this.controller,
    required this.route,
    this.onAreaChanged,
  });

  /// Shared app controller that owns installed app plugin manifests.
  final AgentAwesomeAppController controller;

  /// Decoded dynamic route selected from the app shell.
  final AppPluginRoute route;

  /// Reports the active command area to the shell.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  @override
  State<AppPluginCommandPanel> createState() => _AppPluginCommandPanelState();
}

class _AppPluginCommandPanelState extends State<AppPluginCommandPanel> {
  String _detailModeId = _pluginDetailsModeId;

  /// Builds the plugin shell for the selected manifest.
  @override
  Widget build(BuildContext context) {
    final plugin = _selectedPlugin();
    if (plugin == null) {
      return const PanelEmptyBody(
        icon: Icons.apps_outlined,
        label: 'App plugin unavailable',
        message: 'Install or enable the app plugin package to open this app.',
      );
    }
    final panels = plugin.panels;
    final selected = _selectedPanel(plugin);
    return CommandPanelSubShell(
      areas: <SwitcherPanelArea>[
        for (final panel in panels)
          SwitcherPanelArea(
            id: panel.id,
            title: panel.title,
            icon: _pluginIconFor(panel.icon, panel.kind),
            showInQuickAccess: panel.quickAccess,
            builder: (query) => _PluginPanelOverview(
              plugin: plugin,
              panel: panel,
              query: query,
            ),
          ),
      ],
      selectedAreaId: selected?.id ?? '',
      detailTitle: plugin.name,
      detailModes: _detailModes(plugin),
      selectedDetailModeId: _detailModeId,
      onDetailModeSelected: _selectDetailMode,
      detailBuilder: (modeId) =>
          _PluginDetailPane(plugin: plugin, panel: selected, modeId: modeId),
      onAreaChanged: widget.onAreaChanged,
      filterHint: 'Filter panels...',
      emptyLabel: 'No app plugin panels configured',
      split: const PanelSplit(left: 0.32, min: 0.22, max: 0.64),
    );
  }

  /// Selects the active plugin detail mode.
  void _selectDetailMode(String modeId) {
    setState(() => _detailModeId = modeId);
  }

  /// Returns the selected installed plugin.
  AppPluginManifest? _selectedPlugin() {
    for (final plugin in widget.controller.appPlugins) {
      if (plugin.id == widget.route.pluginId) {
        return plugin;
      }
    }
    return null;
  }

  /// Returns the panel selected by the route, or the plugin default panel.
  AppPluginPanel? _selectedPanel(AppPluginManifest plugin) {
    for (final panel in plugin.panels) {
      if (panel.id == widget.route.panelId) {
        return panel;
      }
    }
    return plugin.defaultPanel;
  }

  /// Builds available right-pane modes for one plugin.
  List<CommandPanelDetailMode> _detailModes(AppPluginManifest plugin) {
    return <CommandPanelDetailMode>[
      const CommandPanelDetailMode(
        id: _pluginDetailsModeId,
        label: 'Details',
        icon: Icons.info_outline,
      ),
      const CommandPanelDetailMode(
        id: _pluginActionsModeId,
        label: 'Actions',
        icon: Icons.bolt_outlined,
      ),
      const CommandPanelDetailMode(
        id: _pluginIntegrationsModeId,
        label: 'Integrations',
        icon: Icons.extension_outlined,
      ),
      if (plugin.starlarkEntrypoint.isNotEmpty)
        const CommandPanelDetailMode(
          id: _pluginScriptModeId,
          label: 'Script',
          icon: Icons.code_outlined,
        ),
    ];
  }
}

/// _PluginPanelOverview renders the selected plugin panel contract.
class _PluginPanelOverview extends StatelessWidget {
  /// Creates a plugin panel overview.
  const _PluginPanelOverview({
    required this.plugin,
    required this.panel,
    required this.query,
  });

  /// Owning plugin manifest.
  final AppPluginManifest plugin;

  /// Panel being inspected.
  final AppPluginPanel panel;

  /// Current command-pane filter.
  final String query;

  /// Builds the selected panel overview.
  @override
  Widget build(BuildContext context) {
    if (!_matchesQuery(plugin, panel, query)) {
      return PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _PluginSummaryHeader(plugin: plugin, panel: panel),
        const SizedBox(height: 16),
        PanelSectionBlock.plain(
          title: 'Surface',
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              PanelBadge(label: appPluginPanelKindLabel(panel.kind)),
              if (plugin.version.trim().isNotEmpty)
                PanelBadge(label: plugin.version.trim()),
              if (plugin.starlarkEntrypoint.isNotEmpty)
                const PanelBadge(label: 'Starlark'),
            ],
          ),
        ),
        if (panel.actions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          PanelSectionBlock.plain(
            title: 'Commands',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final action in panel.actions)
                  _PluginActionRow(action: action),
              ],
            ),
          ),
        ],
        for (final block in panel.blocks) ...<Widget>[
          const SizedBox(height: 18),
          _PluginPanelBlockView(block: block),
        ],
      ],
    );
  }
}

/// _PluginDetailPane renders plugin metadata, actions, and integrations.
class _PluginDetailPane extends StatelessWidget {
  /// Creates a plugin detail pane.
  const _PluginDetailPane({
    required this.plugin,
    required this.panel,
    required this.modeId,
  });

  /// Owning plugin manifest.
  final AppPluginManifest plugin;

  /// Active plugin panel.
  final AppPluginPanel? panel;

  /// Selected right-pane detail mode.
  final String modeId;

  /// Builds the selected detail pane mode.
  @override
  Widget build(BuildContext context) {
    return switch (modeId) {
      _pluginActionsModeId => _PluginActionsDetail(panel: panel),
      _pluginIntegrationsModeId => _PluginIntegrationsDetail(plugin: plugin),
      _pluginScriptModeId => _PluginScriptDetail(plugin: plugin),
      _ => _PluginDetailsDetail(plugin: plugin, panel: panel),
    };
  }
}

/// _PluginDetailsDetail renders selected app metadata.
class _PluginDetailsDetail extends StatelessWidget {
  /// Creates a details pane for one plugin panel.
  const _PluginDetailsDetail({required this.plugin, required this.panel});

  /// Owning plugin manifest.
  final AppPluginManifest plugin;

  /// Active plugin panel.
  final AppPluginPanel? panel;

  /// Builds plugin details.
  @override
  Widget build(BuildContext context) {
    final selected = panel;
    if (selected == null) {
      return const PanelEmptyBody(label: 'No plugin panel selected');
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        _PluginSummaryHeader(plugin: plugin, panel: selected),
        const SizedBox(height: 18),
        PanelSectionBlock.plain(
          title: 'Capabilities',
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              PanelBadge(label: appPluginPanelKindLabel(selected.kind)),
              if (plugin.supportsBoardTools)
                const PanelBadge(label: 'Board tools'),
              if (plugin.integrations.isNotEmpty)
                PanelBadge(label: '${plugin.integrations.length} integrations'),
              if (selected.actions.isNotEmpty)
                PanelBadge(label: '${selected.actions.length} actions'),
            ],
          ),
        ),
      ],
    );
  }
}

/// _PluginActionsDetail renders declared panel actions.
class _PluginActionsDetail extends StatelessWidget {
  /// Creates an action detail pane.
  const _PluginActionsDetail({required this.panel});

  /// Active plugin panel.
  final AppPluginPanel? panel;

  /// Builds declared plugin action rows.
  @override
  Widget build(BuildContext context) {
    final selected = panel;
    if (selected == null || selected.actions.isEmpty) {
      return const PanelEmptyBody(
        icon: Icons.bolt_outlined,
        label: 'No panel actions',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        for (final action in selected.actions) _PluginActionRow(action: action),
      ],
    );
  }
}

/// _PluginIntegrationsDetail renders plugin integration requirements.
class _PluginIntegrationsDetail extends StatelessWidget {
  /// Creates an integration detail pane.
  const _PluginIntegrationsDetail({required this.plugin});

  /// Owning plugin manifest.
  final AppPluginManifest plugin;

  /// Builds integration rows.
  @override
  Widget build(BuildContext context) {
    if (plugin.integrations.isEmpty) {
      return const PanelEmptyBody(
        icon: Icons.extension_outlined,
        label: 'No integrations declared',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        for (final integration in plugin.integrations)
          _PluginIntegrationRow(integration: integration),
      ],
    );
  }
}

/// _PluginScriptDetail renders the Starlark-backed plugin status.
class _PluginScriptDetail extends StatelessWidget {
  /// Creates a script detail pane.
  const _PluginScriptDetail({required this.plugin});

  /// Owning plugin manifest.
  final AppPluginManifest plugin;

  /// Builds script metadata without exposing raw script content.
  @override
  Widget build(BuildContext context) {
    if (plugin.starlarkEntrypoint.isEmpty) {
      return const PanelEmptyBody(
        icon: Icons.code_outlined,
        label: 'No Starlark entrypoint',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        PanelSectionBlock.plain(
          title: 'Runtime',
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: const <Widget>[
              PanelBadge(label: 'Starlark'),
              PanelBadge(label: 'Package entrypoint'),
            ],
          ),
        ),
      ],
    );
  }
}

/// _PluginSummaryHeader renders a title and description for a plugin panel.
class _PluginSummaryHeader extends StatelessWidget {
  /// Creates the summary header.
  const _PluginSummaryHeader({required this.plugin, required this.panel});

  /// Owning plugin manifest.
  final AppPluginManifest plugin;

  /// Active plugin panel.
  final AppPluginPanel panel;

  /// Builds a compact inspector header.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final description = panel.description.trim().isNotEmpty
        ? panel.description.trim()
        : plugin.description.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          _pluginIconFor(panel.icon, panel.kind),
          color: colors.green,
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                panel.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// _PluginActionRow renders one plugin action contract.
class _PluginActionRow extends StatelessWidget {
  /// Creates an action row.
  const _PluginActionRow({required this.action});

  /// Plugin action descriptor.
  final AppPluginAction action;

  /// Builds a compact action row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.bolt_outlined, size: 18, color: colors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  action.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (action.description.trim().isNotEmpty)
                  Text(
                    action.description.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (action.kind.trim().isNotEmpty) ...<Widget>[
            const SizedBox(width: 8),
            PanelBadge(label: action.kind.trim()),
          ],
        ],
      ),
    );
  }
}

/// _PluginIntegrationRow renders one external integration declaration.
class _PluginIntegrationRow extends StatelessWidget {
  /// Creates an integration row.
  const _PluginIntegrationRow({required this.integration});

  /// Plugin integration descriptor.
  final AppPluginIntegration integration;

  /// Builds a compact integration row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.extension_outlined, size: 18, color: colors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  integration.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (_integrationBadges(integration).isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _integrationBadges(integration),
                  ),
                ],
              ],
            ),
          ),
          if (integration.kind.trim().isNotEmpty) ...<Widget>[
            const SizedBox(width: 8),
            PanelBadge(label: integration.kind.trim()),
          ],
        ],
      ),
    );
  }
}

/// _PluginPanelBlockView renders one declarative plugin-owned content block.
class _PluginPanelBlockView extends StatelessWidget {
  /// Creates a plugin panel block view.
  const _PluginPanelBlockView({required this.block});

  /// Declarative block to render.
  final AppPluginPanelBlock block;

  /// Builds a pane-native plugin content block.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock.plain(
      title: block.title,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(_blockIcon(block.icon), size: 18, color: colors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (block.text.trim().isNotEmpty)
                  Text(
                    block.text.trim(),
                    style: TextStyle(
                      color: colors.ink,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                if (block.badges.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final badge in block.badges)
                        PanelBadge(label: badge),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Builds metadata badges for one plugin integration.
List<Widget> _integrationBadges(AppPluginIntegration integration) {
  return <Widget>[
    for (final capability in integration.capabilities)
      PanelBadge(label: capability),
    if (integration.credential.kind.trim().isNotEmpty)
      PanelBadge(label: integration.credential.kind.trim()),
    if (integration.credential.allowedDomains.isNotEmpty)
      PanelBadge(
        label: '${integration.credential.allowedDomains.length} domains',
      ),
  ];
}

/// Reports whether a plugin panel matches the current filter query.
bool _matchesQuery(
  AppPluginManifest plugin,
  AppPluginPanel panel,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }
  return <String>[
    plugin.name,
    plugin.description,
    panel.title,
    panel.description,
    appPluginPanelKindLabel(panel.kind),
  ].any((value) => value.toLowerCase().contains(normalized));
}

/// Maps plugin panel icon names and kinds to Material symbols.
IconData _pluginIconFor(String name, AppPluginPanelKind kind) {
  final normalized = name.trim().toLowerCase();
  if (normalized.isNotEmpty) {
    return switch (normalized) {
      'board' || 'kanban' || 'columns' => Icons.view_kanban_outlined,
      'calendar' || 'schedule' => Icons.calendar_month_outlined,
      'dashboard' => Icons.dashboard_outlined,
      'form' => Icons.dynamic_form_outlined,
      'list' || 'collection' => Icons.list_alt_outlined,
      'tool' => Icons.handyman_outlined,
      'integration' => Icons.extension_outlined,
      _ => Icons.apps_outlined,
    };
  }
  return switch (kind) {
    AppPluginPanelKind.board => Icons.view_kanban_outlined,
    AppPluginPanelKind.calendar => Icons.calendar_month_outlined,
    AppPluginPanelKind.collection => Icons.list_alt_outlined,
    AppPluginPanelKind.dashboard => Icons.dashboard_outlined,
    AppPluginPanelKind.form => Icons.dynamic_form_outlined,
    AppPluginPanelKind.custom => Icons.apps_outlined,
  };
}

/// Maps plugin block icon names to Material symbols.
IconData _blockIcon(String name) {
  return switch (name.trim().toLowerCase()) {
    'calendar' || 'schedule' => Icons.calendar_month_outlined,
    'board' || 'kanban' => Icons.view_kanban_outlined,
    'login' || 'credential' => Icons.lock_outline,
    'sync' => Icons.sync_outlined,
    'warning' => Icons.warning_amber_outlined,
    _ => Icons.notes_outlined,
  };
}
