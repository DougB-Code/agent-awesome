/// Renders root-level Automations launchpad and builder surfaces.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ClipOp;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../domain/automation_contracts.dart';
import '../domain/config_files.dart';
import '../domain/date_formatting.dart';
import '../domain/models_automation.dart';
import 'panels/panels.dart';
import 'settings/settings_panel.dart';
import 'settings/settings_logic.dart';
import 'theme.dart';

part 'automations_state_machine_builder.dart';

const String _automationPanelLaunchpad = 'launchpad';
const String _automationPanelRunbooks = 'runbooks';
const String _automationLaunchpadAreaInbox = 'launchpad_inbox';
const String _automationLaunchpadAreaPublished = 'launchpad_published';
const String _automationLaunchpadAreaSetups = 'launchpad_saved';
const String _automationLaunchpadAreaRuns = 'launchpad_runs';
const String _automationLaunchpadAreaTargets = 'launchpad_targets';
const String _automationLaunchpadAreaSchedules = 'launchpad_schedules';
const String _automationLaunchpadAreaArtifacts = 'launchpad_artifacts';
const String _automationRunbookAreaDrafts = 'runbook_drafts';
const String _automationRunbookAreaActions = 'runbook_actions';
const String _automationAgentsAreaFiles = 'agent_files';

const String _automationDetailDetails = 'details';
const String _automationDetailLaunchpad = 'launch_setups';
const String _automationDetailSchedules = 'schedules';
const String _automationDetailArtifacts = 'artifacts';
const String _automationDetailBuilder = 'builder';
const String _automationDetailInspect = 'inspect';
const String _automationDetailHistory = 'history';
const String _automationDetailTest = 'test';
const String _automationTargetDetailOverview = 'target_overview';
const String _automationTargetDetailCapabilities = 'target_capabilities';
const String _automationTargetDetailSecrets = 'target_secrets';
const String _automationTargetDetailLaunchpad = 'target_launchpad';
const String _automationTargetDetailLogs = 'target_logs';
const String _automationTargetDetailSettings = 'target_settings';
const String _automationTargetDetailUpdates = 'target_updates';
const String _stateMachineBodyKind = 'state_machine';
const String _launchSafetyOpenPROnly = 'open_pr_only';

const Map<String, String> _launchSafetyLabels = <String, String>{
  _launchSafetyOpenPROnly: 'Open PR only',
};

/// AutomationLaunchpadCommandPanel runs and observes published runbooks.
class AutomationLaunchpadCommandPanel extends StatelessWidget {
  /// Creates an launchpad panel bound to app state.
  const AutomationLaunchpadCommandPanel({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Reports active area changes to the root shell command context.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the launchpad command panel.
  @override
  Widget build(BuildContext context) {
    return _AutomationFocusedCommandPanel(
      controller: controller,
      panelId: _automationPanelLaunchpad,
      title: 'Launchpad',
      detailTitle: 'Launchpad',
      icon: Icons.monitor_heart_outlined,
      filterHint: 'Filter launchpad and runs...',
      detailModes: _detailModesForPanel(_automationPanelLaunchpad),
      split: const PanelSplit(left: 0.30, min: 0.22, max: 0.56),
      onAreaChanged: onAreaChanged,
    );
  }
}

/// AutomationRunbooksCommandPanel authors long-lived state-machine runbooks.
class AutomationRunbooksCommandPanel extends StatelessWidget {
  /// Creates a runbook authoring panel bound to app state.
  const AutomationRunbooksCommandPanel({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Reports active area changes to the root shell command context.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the runbook authoring command panel.
  @override
  Widget build(BuildContext context) {
    return _AutomationFocusedCommandPanel(
      controller: controller,
      panelId: _automationPanelRunbooks,
      title: 'Runbooks',
      detailTitle: 'Runbook',
      icon: Icons.route_outlined,
      filterHint: 'Filter runbooks...',
      detailModes: _detailModesForPanel(_automationPanelRunbooks),
      onAreaChanged: onAreaChanged,
    );
  }
}

/// AutomationAgentsCommandPanel authors reusable agent prompt files.
class AutomationAgentsCommandPanel extends StatefulWidget {
  /// Creates an agent authoring panel bound to app state.
  const AutomationAgentsCommandPanel({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Reports active area changes to the root shell command context.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  @override
  State<AutomationAgentsCommandPanel> createState() =>
      _AutomationAgentsCommandPanelState();
}

class _AutomationAgentsCommandPanelState
    extends State<AutomationAgentsCommandPanel> {
  String? _selectedAgentConfigPath;

  /// Builds the agent authoring command panel.
  @override
  Widget build(BuildContext context) {
    return CommandPanelSubShell(
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          id: _automationAgentsAreaFiles,
          title: 'Agents',
          icon: Icons.psychology_outlined,
          builder: (query) => _AutomationAgentFilesContent(
            controller: widget.controller,
            query: query,
            selectedPath: _selectedAgentConfigPathForArea(),
            onSelectedPathChanged: (path) {
              setState(() => _selectedAgentConfigPath = path);
            },
            onDuplicate: (entry) => unawaited(_duplicateAgentConfig(entry)),
            onDelete: (entry) => unawaited(_deleteAgentConfig(context, entry)),
          ),
        ),
      ],
      detailTitle: 'Agents',
      detailModes: const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _automationDetailDetails,
          label: 'Details',
          icon: Icons.info_outline,
        ),
      ],
      selectedDetailModeId: _automationDetailDetails,
      onDetailModeSelected: (_) {},
      detailBuilder: (_) => _AutomationAgentsDetailContent(
        controller: widget.controller,
        selectedPath: _selectedAgentConfigPathForArea(),
        onSelectedPathChanged: (path) {
          setState(() => _selectedAgentConfigPath = path);
        },
      ),
      areaDetailBuilder: (_, _) => _AutomationAgentsDetailContent(
        controller: widget.controller,
        selectedPath: _selectedAgentConfigPathForArea(),
        onSelectedPathChanged: (path) {
          setState(() => _selectedAgentConfigPath = path);
        },
      ),
      areaActionsBuilder: _buildAreaActions,
      detailActionsBuilder: _buildDetailActions,
      filterHint: 'Filter agents...',
      areaFilterHintBuilder: (_) => 'Filter agents...',
      split: const PanelSplit(left: 0.30, min: 0.18, max: 0.44),
      onAreaChanged: widget.onAreaChanged,
    );
  }

  /// Resolves the selected agent config path for the file list and editor.
  String? _selectedAgentConfigPathForArea() {
    final entries = widget.controller.availableAgentConfigs;
    if (entries.isEmpty) {
      return null;
    }
    final selectedPath = _selectedAgentConfigPath;
    if (selectedPath != null &&
        entries.any((entry) => entry.path == selectedPath)) {
      return selectedPath;
    }
    final assignedPath =
        widget.controller.runtimeProfile?.harness.agentConfigPath ?? '';
    if (assignedPath.isNotEmpty &&
        entries.any((entry) => entry.path == assignedPath)) {
      return assignedPath;
    }
    return entries.first.path;
  }

  /// Returns the selected agent config entry.
  ConfigFileEntry? _selectedAgentConfigEntry() {
    final selectedPath = _selectedAgentConfigPathForArea();
    if (selectedPath == null) {
      return null;
    }
    for (final entry in widget.controller.availableAgentConfigs) {
      if (entry.path == selectedPath) {
        return entry;
      }
    }
    return null;
  }

  /// Builds file catalog actions for agent configs.
  Widget _buildAreaActions(BuildContext context, SwitcherPanelArea area) {
    return PanelCreateButton(
      tooltip: 'Add agent config',
      onPressed: () => unawaited(_createAgentConfig()),
    );
  }

  /// Builds selected-agent actions for the detail header.
  Widget _buildDetailActions(
    BuildContext context,
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    final entry = _selectedAgentConfigEntry();
    return Wrap(
      spacing: 8,
      children: <Widget>[
        PanelIconButton(
          icon: Icons.content_copy,
          tooltip: 'Duplicate agent config',
          onPressed: entry == null
              ? null
              : () => unawaited(_duplicateAgentConfig(entry)),
        ),
        PanelIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete agent config',
          onPressed: entry == null
              ? null
              : () => unawaited(_deleteAgentConfig(context, entry)),
        ),
      ],
    );
  }

  /// Creates an agent config and selects it.
  Future<void> _createAgentConfig() async {
    try {
      final path = await widget.controller.createConfigFile(
        ConfigFileKind.agent,
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectedAgentConfigPath = path);
    } catch (_) {}
  }

  /// Duplicates the selected agent config and selects the duplicate.
  Future<void> _duplicateAgentConfig(ConfigFileEntry entry) async {
    try {
      final path = await widget.controller.duplicateConfigFile(entry);
      if (!mounted) {
        return;
      }
      setState(() => _selectedAgentConfigPath = path);
    } catch (_) {}
  }

  /// Deletes one selected agent config after confirmation.
  Future<void> _deleteAgentConfig(
    BuildContext context,
    ConfigFileEntry entry,
  ) async {
    final confirmed = await _confirmAutomationAgentDelete(
      context,
      label: entry.label,
    );
    if (!confirmed) {
      return;
    }
    try {
      await widget.controller.deleteConfigFile(entry);
      if (!mounted) {
        return;
      }
      setState(
        () => _selectedAgentConfigPath = _selectedAgentConfigPathForArea(),
      );
    } catch (_) {}
  }
}

class _AutomationAgentFilesContent extends StatelessWidget {
  const _AutomationAgentFilesContent({
    required this.controller,
    required this.query,
    required this.selectedPath,
    required this.onSelectedPathChanged,
    required this.onDuplicate,
    required this.onDelete,
  });

  final AgentAwesomeAppController controller;
  final String query;
  final String? selectedPath;
  final ValueChanged<String> onSelectedPathChanged;
  final ValueChanged<ConfigFileEntry> onDuplicate;
  final ValueChanged<ConfigFileEntry> onDelete;

  /// Builds the selectable agent file list.
  @override
  Widget build(BuildContext context) {
    final matches = controller.availableAgentConfigs.where((entry) {
      return SettingsQuery.matches(query, <String>[
        entry.label,
        entry.fileLabel,
        entry.path,
        if (entry.assigned) 'assigned',
      ]);
    }).toList();
    if (controller.availableAgentConfigs.isEmpty) {
      return const PanelEmptyBlock(label: 'No agent files configured');
    }
    if (matches.isEmpty) {
      return PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        for (final entry in matches)
          _AutomationAgentFileTile(
            entry: entry,
            selected: entry.path == selectedPath,
            onTap: () => onSelectedPathChanged(entry.path),
            onDuplicate: () => onDuplicate(entry),
            onDelete: () => onDelete(entry),
          ),
      ],
    );
  }
}

class _AutomationAgentFileTile extends StatelessWidget {
  const _AutomationAgentFileTile({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
  });

  final ConfigFileEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  /// Builds one agent file row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: PanelSurface(
          fillWidth: true,
          padding: const EdgeInsets.all(12),
          style: PanelSurfaceStyle.card,
          selected: selected,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.psychology_outlined,
                color: selected ? colors.green : colors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  PanelInlineIconButton(
                    icon: Icons.content_copy,
                    tooltip: 'Duplicate agent config',
                    onPressed: onDuplicate,
                  ),
                  const SizedBox(width: 6),
                  PanelInlineIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete agent config',
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutomationAgentsDetailContent extends StatelessWidget {
  const _AutomationAgentsDetailContent({
    required this.controller,
    required this.selectedPath,
    required this.onSelectedPathChanged,
  });

  final AgentAwesomeAppController controller;
  final String? selectedPath;
  final ValueChanged<String> onSelectedPathChanged;

  /// Builds the selected agent file editor.
  @override
  Widget build(BuildContext context) {
    return SettingsAgentConfigCollection(
      controller: controller,
      entries: controller.availableAgentConfigs,
      assignedPath: controller.runtimeProfile?.harness.agentConfigPath ?? '',
      selectedPath: selectedPath,
      onSelectedPathChanged: onSelectedPathChanged,
      modeId: 'agent-details',
      query: '',
    );
  }
}

/// Confirms a destructive agent file deletion.
Future<bool> _confirmAutomationAgentDelete(
  BuildContext context, {
  required String label,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Delete agent'),
        content: Text('Delete "$label"? This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

class _AutomationFocusedCommandPanel extends StatefulWidget {
  const _AutomationFocusedCommandPanel({
    required this.controller,
    required this.panelId,
    required this.title,
    required this.detailTitle,
    required this.icon,
    required this.filterHint,
    required this.detailModes,
    this.split = const PanelSplit(left: 0.64, min: 0.12, max: 0.9),
    this.onAreaChanged,
  });

  final AgentAwesomeAppController controller;
  final String panelId;
  final String title;
  final String detailTitle;
  final IconData icon;
  final String filterHint;
  final List<CommandPanelDetailMode> detailModes;
  final PanelSplit split;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  @override
  State<_AutomationFocusedCommandPanel> createState() =>
      _AutomationFocusedCommandPanelState();
}

class _AutomationFocusedCommandPanelState
    extends State<_AutomationFocusedCommandPanel> {
  late final _RunbookActionIntentController _runbookActionIntents;
  late final _StateMachineDraftEditController _stateMachineEditor;
  String _detailModeId = _automationDetailDetails;
  String _requestedAreaId = '';

  /// Triggers the first data load after the focused panel is attached.
  @override
  void initState() {
    super.initState();
    _runbookActionIntents = _RunbookActionIntentController();
    _stateMachineEditor = _StateMachineDraftEditController(
      controller: widget.controller,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasPanelData() && !widget.controller.automationsBusy) {
        final refresh = widget.panelId == _automationPanelRunbooks
            ? widget.controller.refreshAutomationAuthoringFromUi
            : widget.controller.refreshAutomationsFromUi;
        unawaited(refresh());
      }
    });
  }

  /// Releases command-panel intent controllers.
  @override
  void dispose() {
    _runbookActionIntents.dispose();
    _stateMachineEditor.dispose();
    super.dispose();
  }

  /// Reports whether the current panel already has its local collection data.
  bool _hasPanelData() {
    return switch (widget.panelId) {
      _automationPanelLaunchpad =>
        widget.controller.automationDefinitions.isNotEmpty ||
            widget.controller.automationRunSetups.isNotEmpty ||
            widget.controller.automationRuns.isNotEmpty ||
            widget.controller.automationCodebases.isNotEmpty ||
            widget.controller.automationRuntimeTargets.isNotEmpty ||
            widget.controller.automationInbox.isNotEmpty,
      _automationPanelRunbooks =>
        widget.controller.automationDrafts.any(
              (draft) => _isRunbookFileKind(draft.kind),
            ) ||
            widget.controller.automationCapabilities.isNotEmpty,
      _ => true,
    };
  }

  /// Builds one focused Automations command panel.
  @override
  Widget build(BuildContext context) {
    final modes = widget.detailModes;
    final areas = _commandAreas();
    final shell = CommandPanelSubShell(
      areas: areas,
      detailTitle: widget.detailTitle,
      detailModes: modes,
      detailTabsBuilder: (area, mode) =>
          _detailTabsForMode(widget.panelId, area.id, mode.id),
      selectedDetailModeId: _detailModeId,
      onDetailModeSelected: _selectDetailMode,
      detailBuilder: (modeId) => _AutomationDetailContent(
        controller: widget.controller,
        stateMachineEditor: _stateMachineEditor,
        areaId: widget.panelId,
        modeId: modeId,
        onDetailModeRequested: _selectDetailMode,
      ),
      areaDetailBuilder: (area, modeId) => _AutomationDetailContent(
        controller: widget.controller,
        stateMachineEditor: _stateMachineEditor,
        areaId: area.id,
        modeId: modeId,
        onDetailModeRequested: _selectDetailMode,
      ),
      areaTabbedDetailBuilder: (area, modeId, _) => _AutomationDetailContent(
        controller: widget.controller,
        stateMachineEditor: _stateMachineEditor,
        areaId: area.id,
        modeId: modeId,
        onDetailModeRequested: _selectDetailMode,
      ),
      onAreaChanged: _handleAreaChanged,
      areaActionsBuilder: (context, area) {
        if (widget.panelId != _automationPanelRunbooks &&
            widget.panelId != _automationPanelLaunchpad) {
          return null;
        }
        return _AutomationPanelActions(
          controller: widget.controller,
          panelId: widget.panelId,
          areaId: area.id,
          onCreateRunbook: _createRunbookDraft,
        );
      },
      detailModesBuilder: _detailModesForArea,
      companionAreaIdBuilder: _companionAreaForDetailMode,
      detailActionsBuilder: (context, area, mode) {
        return _AutomationDetailActions(
          controller: widget.controller,
          panelId: widget.panelId,
          areaId: area.id,
          modeId: mode.id,
        );
      },
      filterHint: widget.filterHint,
      areaFilterHintBuilder: _filterHintForArea,
      selectedAreaId: _requestedAreaId,
      split: _splitForArea(areas),
    );
    if (widget.panelId != _automationPanelRunbooks) {
      return shell;
    }
    return _RunbookActionIntentScope(
      notifier: _runbookActionIntents,
      child: shell,
    );
  }

  /// Creates a runbook draft and reveals it in the Runbooks collection.
  Future<void> _createRunbookDraft() async {
    setState(() => _requestedAreaId = _automationRunbookAreaDrafts);
    await widget.controller.createAutomationDraftFromUi(
      kind: automationRunbookKind,
      name: _nextRunbookDraftName(widget.controller.automationDrafts),
    );
    if (!mounted) {
      return;
    }
    setState(() => _requestedAreaId = _automationRunbookAreaDrafts);
  }

  /// Reports area changes and clears one-shot area requests after manual moves.
  void _handleAreaChanged(SwitcherPanelArea area) {
    if (_requestedAreaId.isNotEmpty && area.id != _requestedAreaId) {
      setState(() => _requestedAreaId = '');
    }
    if (widget.panelId == _automationPanelLaunchpad &&
        _detailModeId != _automationDetailDetails) {
      setState(() => _detailModeId = _automationDetailDetails);
    }
    widget.onAreaChanged?.call(area);
  }

  /// Selects a right-side Automations detail mode.
  void _selectDetailMode(String modeId) {
    final restoringCanvas =
        _detailModeId == _automationDetailInspect &&
        modeId == _automationDetailBuilder;
    if (_detailModeId == _automationDetailBuilder &&
        modeId == _automationDetailInspect) {
      _stateMachineEditor.captureCanvasOffset();
    }
    if (restoringCanvas) {
      _stateMachineEditor.prepareCanvasControllersForRestore();
    }
    setState(() => _detailModeId = modeId);
    if (restoringCanvas) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _stateMachineEditor.restoreCanvasOffset();
        }
      });
    }
  }

  /// Builds quick-access command areas for the current Automations screen.
  List<SwitcherPanelArea> _commandAreas() {
    if (widget.panelId == _automationPanelLaunchpad) {
      return <SwitcherPanelArea>[
        SwitcherPanelArea(
          id: _automationLaunchpadAreaPublished,
          title: 'Launchpad',
          icon: Icons.monitor_heart_outlined,
          builder: (query) => _AutomationLaunchpadContent(
            controller: widget.controller,
            query: query,
          ),
        ),
        SwitcherPanelArea(
          id: _automationLaunchpadAreaInbox,
          title: 'Inbox',
          icon: Icons.inbox_outlined,
          builder: (query) => _AutomationInboxContent(
            controller: widget.controller,
            query: query,
          ),
        ),
        SwitcherPanelArea(
          id: _automationLaunchpadAreaTargets,
          title: 'Computers',
          icon: Icons.devices_other_outlined,
          builder: (query) => _AutomationRuntimeTargetsContent(
            controller: widget.controller,
            query: query,
          ),
        ),
      ];
    }
    if (widget.panelId == _automationPanelRunbooks) {
      return <SwitcherPanelArea>[
        SwitcherPanelArea(
          id: _automationRunbookAreaDrafts,
          title: 'Runbooks',
          icon: Icons.route_outlined,
          builder: (query) => _AutomationDraftsContent(
            controller: widget.controller,
            query: query,
            kind: automationRunbookKind,
            emptyLabel: 'No runbook files',
          ),
        ),
        SwitcherPanelArea(
          id: _automationRunbookAreaActions,
          title: 'Actions',
          icon: Icons.extension_outlined,
          showInQuickAccess: false,
          builder: (query) => _AutomationRunbookStatePaletteContent(
            controller: widget.controller,
            query: query,
          ),
        ),
      ];
    }
    return <SwitcherPanelArea>[
      SwitcherPanelArea(
        id: widget.panelId,
        title: widget.title,
        icon: widget.icon,
        builder: (_) => const SizedBox.shrink(),
      ),
    ];
  }

  /// Returns area-specific right work modes where supporting areas need less UI.
  List<CommandPanelDetailMode> _detailModesForArea(SwitcherPanelArea area) {
    if (widget.panelId == _automationPanelLaunchpad) {
      return switch (area.id) {
        _automationLaunchpadAreaInbox => const <CommandPanelDetailMode>[
          CommandPanelDetailMode(
            id: _automationDetailDetails,
            label: 'Details',
            icon: Icons.info_outline,
          ),
        ],
        _automationLaunchpadAreaTargets => const <CommandPanelDetailMode>[
          CommandPanelDetailMode(
            id: _automationDetailDetails,
            label: 'Details',
            icon: Icons.info_outline,
          ),
          CommandPanelDetailMode(
            id: _automationTargetDetailOverview,
            label: 'Overview',
            icon: Icons.monitor_heart_outlined,
          ),
          CommandPanelDetailMode(
            id: _automationTargetDetailCapabilities,
            label: 'Capabilities',
            icon: Icons.hub_outlined,
          ),
          CommandPanelDetailMode(
            id: _automationTargetDetailSecrets,
            label: 'Secrets',
            icon: Icons.key_outlined,
          ),
          CommandPanelDetailMode(
            id: _automationTargetDetailLaunchpad,
            label: 'Launchpad',
            icon: Icons.playlist_play_outlined,
          ),
          CommandPanelDetailMode(
            id: _automationTargetDetailLogs,
            label: 'Logs',
            icon: Icons.article_outlined,
          ),
          CommandPanelDetailMode(
            id: _automationTargetDetailUpdates,
            label: 'Updates',
            icon: Icons.system_update_alt_outlined,
          ),
          CommandPanelDetailMode(
            id: _automationDetailTest,
            label: 'Test',
            icon: Icons.play_circle_outline,
          ),
        ],
        _ => widget.detailModes,
      };
    }
    return widget.detailModes;
  }

  /// Returns area-specific filter copy for the active command catalog.
  String _filterHintForArea(SwitcherPanelArea area) {
    return switch (area.id) {
      _automationLaunchpadAreaInbox => 'Filter inbox...',
      _automationLaunchpadAreaPublished => 'Filter launchpad...',
      _automationRunbookAreaDrafts => 'Filter runbooks...',
      _automationRunbookAreaActions => 'Filter actions...',
      _automationLaunchpadAreaTargets => 'Filter computers...',
      _ => widget.filterHint,
    };
  }

  /// Returns the left-pane companion area for right-side builder modes.
  String _companionAreaForDetailMode(String modeId) {
    if (modeId != _automationDetailBuilder) {
      return '';
    }
    return switch (widget.panelId) {
      _automationPanelRunbooks => _automationRunbookAreaActions,
      _ => '',
    };
  }

  /// Returns an area-aware split so builder palettes do not crowd the canvas.
  PanelSplit _splitForArea(List<SwitcherPanelArea> areas) {
    if (widget.panelId == _automationPanelRunbooks) {
      return const PanelSplit(left: 0.30, min: 0.16, max: 0.42);
    }
    return widget.split;
  }
}

class _RunbookActionIntentController extends ChangeNotifier {
  String _actionName = '';
  int _revision = 0;

  String get actionName => _actionName;
  int get revision => _revision;

  /// Publishes one left-panel action request to the active state editor.
  void addAction(String actionName) {
    final trimmed = actionName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _actionName = trimmed;
    _revision++;
    notifyListeners();
  }
}

class _RunbookActionIntentScope
    extends InheritedNotifier<_RunbookActionIntentController> {
  const _RunbookActionIntentScope({
    required super.notifier,
    required super.child,
  });

  /// Finds the current action intent publisher for state-machine screens.
  static _RunbookActionIntentController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_RunbookActionIntentScope>()
        ?.notifier;
  }
}

class _AutomationPanelActions extends StatelessWidget {
  const _AutomationPanelActions({
    required this.controller,
    required this.panelId,
    required this.areaId,
    required this.onCreateRunbook,
  });

  final AgentAwesomeAppController controller;
  final String panelId;
  final String areaId;
  final Future<void> Function() onCreateRunbook;

  /// Builds common and section-specific Automations header actions.
  @override
  Widget build(BuildContext context) {
    if (areaId == _automationRunbookAreaActions) {
      return const SizedBox.shrink();
    }
    if (panelId == _automationPanelLaunchpad &&
        areaId == _automationLaunchpadAreaPublished) {
      final definition = controller.selectedAutomationDefinition;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelCreateButton(
            key: const ValueKey<String>('automation-create-run-setup-button'),
            tooltip: 'New Launch',
            onPressed: controller.automationsBusy || definition == null
                ? null
                : () => unawaited(_createLaunch(context, definition)),
          ),
        ],
      );
    }
    if (panelId == _automationPanelLaunchpad &&
        areaId == _automationLaunchpadAreaTargets) {
      return _RemoteDockerRuntimeActions(controller: controller);
    }
    if (panelId == _automationPanelRunbooks ||
        areaId == _automationRunbookAreaDrafts) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelCreateButton(
            key: const ValueKey<String>('automation-new-runbook-draft-button'),
            tooltip: 'New runbook draft',
            onPressed: controller.automationsBusy
                ? null
                : () => unawaited(_createRunbook(context)),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  /// Runs runbook creation and surfaces failures from the async API call.
  Future<void> _createRunbook(BuildContext context) async {
    await onCreateRunbook();
    if (!context.mounted) {
      return;
    }
    _showAutomationErrorSnack(context, controller);
  }

  /// Runs Launch creation for the selected runbook definition.
  Future<void> _createLaunch(
    BuildContext context,
    AutomationDefinition definition,
  ) async {
    await _showCreateRunSetupDialog(context, controller, definition);
    if (!context.mounted) {
      return;
    }
    _showAutomationErrorSnack(context, controller);
  }
}

/// _RemoteDockerRuntimeActions exposes Docker runtime operations in Launchpad.
class _RemoteDockerRuntimeActions extends StatefulWidget {
  /// Creates Docker runtime action controls for the operational target area.
  const _RemoteDockerRuntimeActions({required this.controller});

  /// Shared app controller that owns runtime bundle operations.
  final AgentAwesomeAppController controller;

  @override
  State<_RemoteDockerRuntimeActions> createState() =>
      _RemoteDockerRuntimeActionsState();
}

class _RemoteDockerRuntimeActionsState
    extends State<_RemoteDockerRuntimeActions> {
  String _remoteDockerHost = '';

  /// Builds remote runtime operation controls for the Computers header.
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: <Widget>[
        PanelIconButton(
          icon: Icons.inventory_2_outlined,
          tooltip: 'Export remote Docker bundle',
          onPressed: () =>
              unawaited(_runDockerAction(context, _exportRemoteDockerBundle)),
        ),
        PanelIconButton(
          icon: Icons.build_outlined,
          tooltip: 'Build remote Docker image',
          onPressed: () =>
              unawaited(_runDockerAction(context, _buildRemoteDockerImage)),
        ),
        PanelIconButton(
          icon: Icons.play_arrow_outlined,
          tooltip: 'Start remote Docker runtime',
          onPressed: () =>
              unawaited(_runDockerAction(context, _startRemoteDockerRuntime)),
        ),
        PanelIconButton(
          icon: Icons.cloud_upload_outlined,
          tooltip: 'Deploy remote Docker runtime',
          onPressed: () =>
              unawaited(_runDockerAction(context, _deployRemoteDockerRuntime)),
        ),
      ],
    );
  }

  /// Runs one Docker operation and reports its status from the UI boundary.
  Future<void> _runDockerAction(
    BuildContext context,
    Future<bool> Function() action,
  ) async {
    try {
      final completed = await action();
      if (!context.mounted) {
        return;
      }
      if (!completed) {
        return;
      }
      final message = widget.controller.statusMessage.trim();
      if (message.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Remote Docker operation failed: $error'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// Exports the current runtime as a configured remote Docker bundle.
  Future<bool> _exportRemoteDockerBundle() async {
    await widget.controller.exportRemoteDockerBundle(
      localModelPath: await widget.controller.activeLocalModelArtifactPath(),
      localModelServerExecutablePath: await widget.controller
          .activeLocalLlamaServerExecutablePath(),
    );
    return true;
  }

  /// Exports the current runtime and builds its Docker image.
  Future<bool> _buildRemoteDockerImage() async {
    final bundle = await widget.controller.exportRemoteDockerBundle(
      localModelPath: await widget.controller.activeLocalModelArtifactPath(),
      localModelServerExecutablePath: await widget.controller
          .activeLocalLlamaServerExecutablePath(),
    );
    await widget.controller.buildRemoteDockerBundleImage(bundle);
    return true;
  }

  /// Exports the current runtime, builds the image, and starts it locally.
  Future<bool> _startRemoteDockerRuntime() async {
    final bundle = await widget.controller.exportRemoteDockerBundle(
      localModelPath: await widget.controller.activeLocalModelArtifactPath(),
      localModelServerExecutablePath: await widget.controller
          .activeLocalLlamaServerExecutablePath(),
    );
    await widget.controller.buildRemoteDockerBundleImage(bundle);
    await widget.controller.startRemoteDockerBundleContainer(
      bundle,
      gatewayToken: widget.controller.config.gatewayBearerToken,
    );
    return true;
  }

  /// Exports, builds, and deploys the current runtime to an SSH Docker host.
  Future<bool> _deployRemoteDockerRuntime() async {
    final host = await _promptRemoteDockerHost();
    if (host == null || host.trim().isEmpty) {
      return false;
    }
    setState(() => _remoteDockerHost = host.trim());
    final bundle = await widget.controller.exportRemoteDockerBundle(
      localModelPath: await widget.controller.activeLocalModelArtifactPath(),
      localModelServerExecutablePath: await widget.controller
          .activeLocalLlamaServerExecutablePath(),
    );
    await widget.controller.buildRemoteDockerBundleImage(bundle);
    await widget.controller.deployRemoteDockerBundle(
      bundle,
      remoteHost: host,
      gatewayToken: widget.controller.config.gatewayBearerToken,
    );
    return true;
  }

  /// Prompts for the SSH target used by generated remote deploy scripts.
  Future<String?> _promptRemoteDockerHost() async {
    final controller = TextEditingController(text: _remoteDockerHost);
    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Deploy runtime'),
            content: SizedBox(
              width: 420,
              child: PanelTextFormField(
                label: 'SSH host',
                controller: controller,
                onSubmitted: (_) =>
                    Navigator.of(dialogContext).pop(controller.text.trim()),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text.trim()),
                child: const Text('Deploy'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}

class _AutomationDetailActions extends StatelessWidget {
  const _AutomationDetailActions({
    required this.controller,
    required this.panelId,
    required this.areaId,
    required this.modeId,
  });

  final AgentAwesomeAppController controller;
  final String panelId;
  final String areaId;
  final String modeId;

  /// Builds selected-object controls for the Automations detail panel.
  @override
  Widget build(BuildContext context) {
    if (panelId == _automationPanelLaunchpad) {
      return _LaunchpadSelectedActions(
        controller: controller,
        areaId: areaId,
        modeId: modeId,
      );
    }
    final kind = _automationDraftKindForArea(areaId);
    if (kind != null || panelId == _automationPanelRunbooks) {
      final effectiveKind = kind ?? automationRunbookKind;
      final draft = _selectedAutomationDraftForKind(controller, effectiveKind);
      if (draft == null) {
        return const SizedBox.shrink();
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelIconButton(
            icon: Icons.rule_outlined,
            tooltip: 'Validate draft',
            onPressed: controller.automationsBusy
                ? null
                : () => unawaited(
                    controller.validateAutomationDraftFromUi(draft),
                  ),
          ),
          const SizedBox(width: 8),
          PanelIconButton(
            icon: Icons.publish_outlined,
            tooltip: 'Publish draft',
            onPressed: controller.automationsBusy
                ? null
                : () =>
                      unawaited(controller.publishAutomationDraftFromUi(draft)),
          ),
          const SizedBox(width: 8),
          PanelIconButton(
            icon: Icons.content_copy,
            tooltip: 'Duplicate runbook file',
            onPressed: controller.automationsBusy
                ? null
                : () => unawaited(
                    controller.duplicateAutomationDraftFromUi(draft),
                  ),
          ),
          const SizedBox(width: 8),
          PanelIconButton(
            key: const ValueKey<String>('automation-delete-runbook-button'),
            icon: Icons.delete_outline,
            tooltip: 'Delete runbook file',
            onPressed: controller.automationsBusy
                ? null
                : () => unawaited(
                    _showDeleteAutomationDraftDialog(
                      context,
                      controller,
                      draft,
                    ),
                  ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class _LaunchpadSelectedActions extends StatelessWidget {
  const _LaunchpadSelectedActions({
    required this.controller,
    required this.areaId,
    required this.modeId,
  });

  final AgentAwesomeAppController controller;
  final String areaId;
  final String modeId;

  /// Builds selected-object actions for the active Launchpad collection.
  @override
  Widget build(BuildContext context) {
    if (areaId == _automationLaunchpadAreaInbox &&
        modeId == _automationDetailDetails) {
      final item = controller.selectedAutomationPendingItem;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelIconButton(
            icon: Icons.check,
            tooltip: 'Approve selected automation item',
            onPressed: controller.automationsBusy || item == null
                ? null
                : () => unawaited(
                    controller.approveAutomationPendingItemFromUi(item),
                  ),
          ),
          const SizedBox(width: 8),
          PanelIconButton(
            icon: Icons.close,
            tooltip: 'Reject selected automation item',
            onPressed: controller.automationsBusy || item == null
                ? null
                : () => unawaited(
                    controller.rejectAutomationPendingItemFromUi(item),
                  ),
          ),
        ],
      );
    }
    if (areaId == _automationLaunchpadAreaPublished &&
        modeId == _automationDetailDetails) {
      final setup = controller.selectedAutomationRunSetup;
      return _LaunchSetupHeaderActions(controller: controller, setup: setup);
    }
    if (areaId == _automationLaunchpadAreaTargets &&
        modeId == _automationTargetDetailOverview) {
      final target = controller.selectedAutomationRuntimeTarget;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelIconButton(
            icon: Icons.content_copy,
            tooltip: 'Copy computer id',
            onPressed: target == null
                ? null
                : () => unawaited(
                    Clipboard.setData(ClipboardData(text: target.id)),
                  ),
          ),
          const SizedBox(width: 8),
          const PanelIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete computer',
            onPressed: null,
          ),
        ],
      );
    }
    if (areaId == _automationLaunchpadAreaPublished &&
        modeId == _automationDetailHistory) {
      final setup = controller.selectedAutomationRunSetup;
      return _LaunchSetupHeaderActions(controller: controller, setup: setup);
    }
    if (areaId == _automationLaunchpadAreaPublished &&
        modeId == _automationDetailLaunchpad) {
      final setup = _selectedLaunchSetupFrom(
        _launchSetupsForDefinition(
          controller.automationRunSetups,
          controller.selectedAutomationDefinition,
        ),
        controller.selectedAutomationRunSetup,
      );
      return _LaunchSetupHeaderActions(controller: controller, setup: setup);
    }
    return const SizedBox.shrink();
  }
}

class _LaunchSetupHeaderActions extends StatelessWidget {
  const _LaunchSetupHeaderActions({
    required this.controller,
    required this.setup,
  });

  final AgentAwesomeAppController controller;
  final AutomationRunSetup? setup;

  /// Builds selected Launch actions with copy/delete as the final pair.
  @override
  Widget build(BuildContext context) {
    final selected = setup;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PanelIconButton(
          key: const ValueKey<String>('automation-start-run-setup-button'),
          icon: Icons.play_arrow,
          tooltip: 'Run selected Launch',
          onPressed: controller.automationsBusy || selected == null
              ? null
              : () => unawaited(
                  _showStartAutomationRunSetupDialog(
                    context,
                    controller,
                    selected,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        PanelIconButton(
          icon: Icons.content_copy,
          tooltip: 'Copy Launch id',
          onPressed: selected == null
              ? null
              : () => unawaited(
                  Clipboard.setData(ClipboardData(text: selected.id)),
                ),
        ),
        const SizedBox(width: 8),
        PanelIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete Launch',
          onPressed: controller.automationsBusy || selected == null
              ? null
              : () => unawaited(
                  _showDeleteAutomationRunSetupDialog(
                    context,
                    controller,
                    selected,
                  ),
                ),
        ),
      ],
    );
  }
}

/// _showDeleteAutomationDraftDialog confirms destructive runbook deletion.
Future<void> _showDeleteAutomationDraftDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  AutomationDraft draft,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Delete runbook file'),
        content: Text('Delete "${draft.name}"? This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) {
    return;
  }
  await controller.deleteAutomationDraftFromUi(draft);
}

/// _showDeleteAutomationRunSetupDialog confirms Launch deletion.
Future<void> _showDeleteAutomationRunSetupDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  AutomationRunSetup setup,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Delete Launch'),
        content: Text('Delete "${setup.name}"? This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) {
    return;
  }
  await controller.deleteAutomationRunSetupFromUi(setup);
}

/// _showStartAutomationRunSetupDialog collects run-specific Launch input.
Future<void> _showStartAutomationRunSetupDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  AutomationRunSetup setup,
) async {
  final definition = _definitionForId(
    controller.automationDefinitions,
    setup.definitionId,
  );
  if (definition == null) {
    return;
  }
  final seedInput = <String, dynamic>{
    ..._runbookRunAuthoringDefaults(controller, definition),
    ...setup.input,
  };
  final runFields = _runbookRunSetupRunFields(definition.body);
  final input = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => _StartAutomationRunDialog(
      title: 'Run ${setup.name}',
      definition: definition,
      seedInput: seedInput,
      includeSeedInput: false,
      onlyMissingRequired: true,
      includedNames: runFields.isEmpty ? null : runFields,
    ),
  );
  if (input == null) {
    return;
  }
  await controller.startAutomationRunSetupFromUi(setup, input: input);
  if (!context.mounted) {
    return;
  }
  _showAutomationErrorSnack(context, controller);
}

/// Shows a bounded error after an attempted automation run start fails.
void _showAutomationErrorSnack(
  BuildContext context,
  AgentAwesomeAppController controller,
) {
  final message = controller.automationsMessage.trim();
  if (message.isEmpty || !context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}

/// _showCreateRunSetupDialog stores a saved Launch for later runs.
Future<void> _showCreateRunSetupDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  AutomationDefinition definition,
) async {
  final result = await showDialog<_RunSetupDialogResult>(
    context: context,
    builder: (context) => _CreateRunSetupDialog(
      definition: definition,
      seedInput: _runbookRunAuthoringDefaults(controller, definition),
      targets: controller.automationRuntimeTargets,
      selectedTargetId: controller.selectedAutomationRuntimeTarget?.id ?? '',
    ),
  );
  if (result == null) {
    return;
  }
  await controller.createAutomationRunSetupFromUi(
    definition: definition,
    name: result.name,
    description: result.description,
    runtimeTargetId: result.runtimeTargetId,
    input: result.input,
  );
}

/// _StartAutomationRunDialog renders generated runbook-run input controls.
class _StartAutomationRunDialog extends StatefulWidget {
  const _StartAutomationRunDialog({
    required this.title,
    required this.definition,
    required this.seedInput,
    required this.includeSeedInput,
    this.onlyMissingRequired = false,
    this.includedNames,
  });

  final String title;
  final AutomationDefinition definition;
  final Map<String, dynamic> seedInput;
  final bool includeSeedInput;
  final bool onlyMissingRequired;
  final Set<String>? includedNames;

  @override
  State<_StartAutomationRunDialog> createState() =>
      _StartAutomationRunDialogState();
}

/// _StartAutomationRunDialogState owns generated runbook-run field state.
class _StartAutomationRunDialogState extends State<_StartAutomationRunDialog> {
  late final List<_RunbookRunInputField> _fields;
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};
  final Map<String, bool> _booleanValues = <String, bool>{};
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fields = _runbookRunInputFields(
      widget.definition,
      seedInput: widget.seedInput,
      onlyMissingRequired: widget.onlyMissingRequired,
      includedNames: widget.includedNames,
    );
    for (final field in _fields) {
      if (field.type == 'boolean') {
        _booleanValues[field.name] = _initialBooleanValue(field.defaultValue);
      } else {
        _textControllers[field.name] = TextEditingController(
          text: _initialFieldText(field.defaultValue),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Builds the run input dialog.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final field in _fields) ...<Widget>[
                  _RunbookRunInputFieldControl(
                    field: field,
                    textController: _textControllers[field.name],
                    booleanValue: _booleanValues[field.name] ?? false,
                    onBooleanChanged: (value) =>
                        setState(() => _booleanValues[field.name] = value),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_error.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error,
                      style: TextStyle(color: colors.coral, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('automation-run-submit-button'),
          onPressed: _submit,
          child: const Text('Run'),
        ),
      ],
    );
  }

  /// Validates typed fields and returns a runbook input object to the caller.
  void _submit() {
    final input = widget.includeSeedInput
        ? _runbookRunSeedInput(widget.seedInput)
        : <String, dynamic>{};
    final error = _populateRunbookInputFromFields(
      fields: _fields,
      textControllers: _textControllers,
      booleanValues: _booleanValues,
      input: input,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(input);
  }
}

/// _RunSetupDialogResult carries one saved Launch created from the UI.
class _RunSetupDialogResult {
  const _RunSetupDialogResult({
    required this.name,
    required this.description,
    required this.runtimeTargetId,
    required this.input,
  });

  final String name;
  final String description;
  final String runtimeTargetId;
  final Map<String, dynamic> input;
}

/// _CreateRunSetupDialog renders a typed Launch form for one runbook file.
class _CreateRunSetupDialog extends StatefulWidget {
  const _CreateRunSetupDialog({
    required this.definition,
    required this.seedInput,
    required this.targets,
    required this.selectedTargetId,
  });

  final AutomationDefinition definition;
  final Map<String, dynamic> seedInput;
  final List<AutomationRuntimeTarget> targets;
  final String selectedTargetId;

  @override
  State<_CreateRunSetupDialog> createState() => _CreateRunSetupDialogState();
}

/// _CreateRunSetupDialogState owns Launch field controllers.
class _CreateRunSetupDialogState extends State<_CreateRunSetupDialog> {
  late final TextEditingController _nameController;
  late final List<_RunbookRunInputField> _fields;
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};
  final Map<String, bool> _booleanValues = <String, bool>{};
  String _targetId = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: '${widget.definition.name} Launch',
    );
    _targetId = _initialTargetId(widget.targets, widget.selectedTargetId);
    final setupFields = _runbookRunSetupSetupFields(widget.definition.body);
    _fields = setupFields.isEmpty
        ? const <_RunbookRunInputField>[]
        : _runbookRunInputFields(
            widget.definition,
            seedInput: widget.seedInput,
            includedNames: setupFields,
            excludedNames: _runbookRunSetupRunFields(widget.definition.body),
          );
    for (final field in _fields) {
      if (field.type == 'boolean') {
        _booleanValues[field.name] = _initialBooleanValue(field.defaultValue);
      } else {
        _textControllers[field.name] = TextEditingController(
          text: _initialFieldText(field.defaultValue),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Builds the saved Launch creation dialog.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return AlertDialog(
      title: Text('Create Launch'),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _AutomationTextField(
                  key: const ValueKey<String>('automation-run-setup-name'),
                  controller: _nameController,
                  label: 'Launch Name *',
                ),
                const SizedBox(height: 12),
                _AutomationDropdown(
                  key: const ValueKey<String>('automation-run-setup-target'),
                  label: 'Run on',
                  value: _targetId,
                  values: <String>[
                    for (final target in widget.targets) target.id,
                  ],
                  labels: <String, String>{
                    for (final target in widget.targets) target.id: target.name,
                  },
                  onChanged: (value) => setState(() => _targetId = value),
                ),
                const SizedBox(height: 12),
                for (final field in _fields) ...<Widget>[
                  _RunbookRunInputFieldControl(
                    field: field,
                    textController: _textControllers[field.name],
                    booleanValue: _booleanValues[field.name] ?? false,
                    onBooleanChanged: (value) =>
                        setState(() => _booleanValues[field.name] = value),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_error.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error,
                      style: TextStyle(color: colors.coral, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('automation-run-setup-submit-button'),
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }

  /// Validates and returns the saved Launch payload.
  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Launch Name is required.');
      return;
    }
    final input = <String, dynamic>{};
    final error = _populateRunbookInputFromFields(
      fields: _fields,
      textControllers: _textControllers,
      booleanValues: _booleanValues,
      input: input,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(
      _RunSetupDialogResult(
        name: name,
        description: widget.definition.name,
        runtimeTargetId: _targetId,
        input: input,
      ),
    );
  }
}

/// _RunbookRunInputFieldControl renders one runbook-run form field.
class _RunbookRunInputFieldControl extends StatelessWidget {
  const _RunbookRunInputFieldControl({
    required this.field,
    required this.textController,
    required this.booleanValue,
    required this.onBooleanChanged,
    this.onChanged,
  });

  final _RunbookRunInputField field;
  final TextEditingController? textController;
  final bool booleanValue;
  final ValueChanged<bool> onBooleanChanged;
  final VoidCallback? onChanged;

  /// Builds one typed runbook-run input control.
  @override
  Widget build(BuildContext context) {
    if (field.type == 'boolean') {
      final colors = context.agentAwesomeColors;
      return CheckboxListTile(
        key: ValueKey<String>('automation-run-input-${field.name}'),
        value: booleanValue,
        onChanged: (value) {
          onBooleanChanged(value ?? false);
          onChanged?.call();
        },
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: Text(field.label, style: TextStyle(color: colors.ink)),
      );
    }
    final controller = textController;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return _AutomationTextField(
      key: ValueKey<String>('automation-run-input-${field.name}'),
      controller: controller,
      label: field.requiredFromUser ? '${field.label} *' : field.label,
      minLines: field.maxLines > 1 ? 2 : null,
      maxLines: field.maxLines,
      keyboardType: _keyboardTypeForRunbookRunField(field),
      onChanged: (_) => onChanged?.call(),
    );
  }
}

/// _RunbookRunInputField describes one typed runbook-run input.
class _RunbookRunInputField {
  const _RunbookRunInputField({
    required this.name,
    required this.label,
    required this.type,
    required this.requiredFromUser,
    required this.defaultValue,
  });

  final String name;
  final String label;
  final String type;
  final bool requiredFromUser;
  final Object? defaultValue;

  /// Maximum visible editor lines for text-backed fields.
  int get maxLines {
    final lower = name.toLowerCase();
    if (lower.contains('request') ||
        lower.contains('body') ||
        lower.contains('message') ||
        lower.contains('description')) {
      return 4;
    }
    return 1;
  }
}

/// Returns runbook run fields declared by the definition body.
List<_RunbookRunInputField> _runbookRunInputFields(
  AutomationDefinition definition, {
  Map<String, dynamic> seedInput = const <String, dynamic>{},
  bool onlyMissingRequired = false,
  Set<String>? includedNames,
  Set<String> excludedNames = const <String>{},
}) {
  final schema = _runbookRunInputSchema(definition.body);
  final properties = _map(schema['properties']);
  if (properties.isEmpty) {
    return const <_RunbookRunInputField>[];
  }
  final defaults = _runbookRunDefaults(definition.body);
  final required = _list(schema['required']).map((item) => '$item').toSet();
  final orderedNames = <String>[
    for (final name in _list(schema['required']).map((item) => '$item'))
      if (properties.containsKey(name)) name,
    for (final name in properties.keys)
      if (!required.contains(name)) name,
  ];
  return <_RunbookRunInputField>[
    for (final name in orderedNames)
      if (_includeRunbookRunField(
        name,
        defaults: defaults,
        seedInput: seedInput,
        required: required,
        onlyMissingRequired: onlyMissingRequired,
        includedNames: includedNames,
        excludedNames: excludedNames,
      ))
        _RunbookRunInputField(
          name: name,
          label: _stateMachineDisplayName(name),
          type: _runbookRunInputType(_map(properties[name])),
          requiredFromUser: _runbookRunFieldRequiredFromUser(
            name,
            defaults: defaults,
            seedInput: seedInput,
            required: required,
          ),
          defaultValue: seedInput.containsKey(name)
              ? seedInput[name]
              : defaults[name],
        ),
  ];
}

/// Returns schema-backed Launch default fields with saved extras preserved.
List<_RunbookRunInputField> _launchInputFieldsForSetup(
  AutomationDefinition? definition,
  AutomationRunSetup setup,
) {
  final setupFields = definition == null
      ? const <String>{}
      : _runbookRunSetupSetupFields(definition.body);
  final runFields = definition == null
      ? const <String>{}
      : _runbookRunSetupRunFields(definition.body);
  final fields = definition == null || setupFields.isEmpty
      ? <_RunbookRunInputField>[]
      : _runbookRunInputFields(
          definition,
          seedInput: setup.input,
          includedNames: setupFields,
          excludedNames: runFields,
        );
  final seen = fields.map((field) => field.name).toSet();
  final extraNames =
      setup.input.keys
          .where((name) => !seen.contains(name))
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toList()
        ..sort();
  return <_RunbookRunInputField>[
    ...fields,
    for (final name in extraNames)
      _RunbookRunInputField(
        name: name,
        label: _stateMachineDisplayName(name),
        type: _runbookRunValueType(setup.input[name]),
        requiredFromUser: false,
        defaultValue: setup.input[name],
      ),
  ];
}

/// Infers a conservative field type for saved input without schema metadata.
String _runbookRunValueType(Object? value) {
  if (value is bool) {
    return 'boolean';
  }
  if (value is int) {
    return 'integer';
  }
  if (value is num) {
    return 'number';
  }
  return 'string';
}

/// Reports whether one input field belongs in the generated run form.
bool _includeRunbookRunField(
  String name, {
  required Map<String, dynamic> defaults,
  required Map<String, dynamic> seedInput,
  required Set<String> required,
  required bool onlyMissingRequired,
  required Set<String>? includedNames,
  required Set<String> excludedNames,
}) {
  if (excludedNames.contains(name)) {
    return false;
  }
  if (includedNames != null && !includedNames.contains(name)) {
    return false;
  }
  if (!onlyMissingRequired) {
    return true;
  }
  return _runbookRunFieldRequiredFromUser(
    name,
    defaults: defaults,
    seedInput: seedInput,
    required: required,
  );
}

/// Reports whether one runbook input field needs a user-provided value.
bool _runbookRunFieldRequiredFromUser(
  String name, {
  required Map<String, dynamic> defaults,
  required Map<String, dynamic> seedInput,
  required Set<String> required,
}) {
  if (!required.contains(name)) {
    return false;
  }
  if (defaults.containsKey(name)) {
    return false;
  }
  if (seedInput.containsKey(name) &&
      _isProvidedRunbookRunValue(seedInput[name])) {
    return false;
  }
  return true;
}

/// Finds the first object schema intended to validate runbook input.
Map<String, dynamic> _runbookRunInputSchema(Map<String, dynamic> body) {
  final direct = _map(body['input_schema']);
  if (direct.isNotEmpty) {
    return direct;
  }
  final authoring = _map(body['authoring']);
  final authoringSchema = _map(authoring['input_schema']);
  if (authoringSchema.isNotEmpty) {
    return authoringSchema;
  }
  for (final action in _runbookStateActions(_list(body['states']))) {
    final actionMap = _map(action);
    if ('${actionMap['uses'] ?? ''}' != 'data.assert') {
      continue;
    }
    final args = _map(actionMap['with']);
    if ('${args['mode'] ?? ''}' != 'schema') {
      continue;
    }
    final schema = _map(args['schema']);
    if ('${schema['type'] ?? ''}'.trim().toLowerCase() == 'object') {
      return schema;
    }
  }
  return const <String, dynamic>{};
}

/// Finds declarative input defaults used before runbook input validation.
Map<String, dynamic> _runbookRunDefaults(Map<String, dynamic> body) {
  for (final action in _runbookStateActions(_list(body['states']))) {
    final actionMap = _map(action);
    if ('${actionMap['uses'] ?? ''}' != 'data.defaults') {
      continue;
    }
    final args = _map(actionMap['with']);
    if (!'${args['input'] ?? ''}'.contains('runbook_input')) {
      continue;
    }
    return _map(args['defaults']);
  }
  return const <String, dynamic>{};
}

/// Returns UI-resolved runbook defaults that come from authoring metadata.
Map<String, dynamic> _runbookRunAuthoringDefaults(
  AgentAwesomeAppController controller,
  AutomationDefinition definition,
) {
  final authoring = _map(definition.body['authoring']);
  final defaults = _map(authoring['input_defaults']);
  return <String, dynamic>{
    for (final entry in defaults.entries)
      entry.key: _resolveRunbookRunAuthoringDefault(controller, entry.value),
  };
}

/// Resolves app-context tokens allowed in runbook authoring defaults.
Object _resolveRunbookRunAuthoringDefault(
  AgentAwesomeAppController controller,
  Object? value,
) {
  final text = '$value'.trim();
  return switch (text) {
    r'${app.workspace_root}' => controller.config.workspaceRoot,
    _ => value ?? '',
  };
}

/// Returns setup fields intended to be configured once for a runbook.
Set<String> _runbookRunSetupSetupFields(Map<String, dynamic> body) {
  final runSetup = _map(_map(body['authoring'])['run_setup']);
  return _list(runSetup['setup_fields']).map((item) => '$item').toSet();
}

/// Returns fields intended to be supplied each time a setup runs.
Set<String> _runbookRunSetupRunFields(Map<String, dynamic> body) {
  final runSetup = _map(_map(body['authoring'])['run_setup']);
  return _list(runSetup['run_fields']).map((item) => '$item').toSet();
}

/// Returns state entry actions from nested state-machine definitions.
List<dynamic> _runbookStateActions(List<dynamic> states) {
  final actions = <dynamic>[];
  for (final state in states.map(_map)) {
    actions.addAll(_list(state['on_entry']));
    actions.addAll(_runbookStateActions(_list(state['states'])));
  }
  return actions;
}

/// Converts a JSON-schema type into the supported form-control type.
String _runbookRunInputType(Map<String, dynamic> property) {
  final type = '${property['type'] ?? 'string'}'.trim().toLowerCase();
  return switch (type) {
    'boolean' => 'boolean',
    'integer' => 'integer',
    'number' => 'number',
    _ => 'string',
  };
}

/// Converts a user-entered field value to the payload type expected by runtime.
Object? _parsedRunbookRunValue(_RunbookRunInputField field, String raw) {
  return switch (field.type) {
    'integer' => int.tryParse(raw),
    'number' => double.tryParse(raw),
    _ => raw,
  };
}

/// Adds form-provided field values to a runbook input object.
String? _populateRunbookInputFromFields({
  required List<_RunbookRunInputField> fields,
  required Map<String, TextEditingController> textControllers,
  required Map<String, bool> booleanValues,
  required Map<String, dynamic> input,
}) {
  for (final field in fields) {
    if (field.type == 'boolean') {
      input[field.name] = booleanValues[field.name] ?? false;
      continue;
    }
    final raw = textControllers[field.name]?.text.trim() ?? '';
    if (raw.isEmpty) {
      if (field.requiredFromUser) {
        return '${field.label} is required.';
      }
      continue;
    }
    final parsed = _parsedRunbookRunValue(field, raw);
    if (parsed == null) {
      return '${field.label} must be ${field.type}.';
    }
    input[field.name] = parsed;
  }
  return null;
}

/// Returns seed input that can safely be sent with a runbook run request.
Map<String, dynamic> _runbookRunSeedInput(Map<String, dynamic> seedInput) {
  return <String, dynamic>{
    for (final entry in seedInput.entries)
      if (_isProvidedRunbookRunValue(entry.value)) entry.key: entry.value,
  };
}

/// Reports whether a value is meaningful form input rather than a blank token.
bool _isProvidedRunbookRunValue(Object? value) {
  if (value == null) {
    return false;
  }
  if (value is bool || value is num) {
    return true;
  }
  final text = '$value'.trim();
  if (text.isEmpty) {
    return false;
  }
  return !(text.startsWith(r'${') && text.endsWith('}'));
}

/// Returns a keyboard suited to one runbook field type.
TextInputType _keyboardTypeForRunbookRunField(_RunbookRunInputField field) {
  return switch (field.type) {
    'integer' => TextInputType.number,
    'number' => const TextInputType.numberWithOptions(decimal: true),
    _ => field.maxLines > 1 ? TextInputType.multiline : TextInputType.text,
  };
}

/// Returns a form-safe default string without showing expression syntax.
String _initialFieldText(Object? value) {
  if (value == null) {
    return '';
  }
  final text = '$value'.trim();
  if (text.startsWith(r'${') && text.endsWith('}')) {
    return '';
  }
  return text;
}

/// Returns a stable enough signature for JSON-like Launch payloads.
String _jsonSignature(Map<String, dynamic> value) {
  final keys = value.keys.toList()..sort();
  return jsonEncode(<String, dynamic>{for (final key in keys) key: value[key]});
}

/// Returns a boolean default value for runbook run fields.
bool _initialBooleanValue(Object? value) {
  if (value is bool) {
    return value;
  }
  return '${value ?? ''}'.trim().toLowerCase() == 'true';
}

List<CommandPanelDetailMode> _detailModesForPanel(String panelId) {
  switch (panelId) {
    case _automationPanelLaunchpad:
      return const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _automationDetailDetails,
          label: 'Details',
          icon: Icons.info_outline,
        ),
        CommandPanelDetailMode(
          id: _automationDetailLaunchpad,
          label: 'Overview',
          icon: Icons.dashboard_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailSchedules,
          label: 'Schedules',
          icon: Icons.event_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailArtifacts,
          label: 'Artifacts',
          icon: Icons.inventory_2_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailHistory,
          label: 'Runs',
          icon: Icons.history,
        ),
      ];
    case _automationPanelRunbooks:
      return const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _automationDetailDetails,
          label: 'Details',
          icon: Icons.info_outline,
        ),
        CommandPanelDetailMode(
          id: _automationDetailBuilder,
          label: 'Builder',
          icon: Icons.account_tree_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailInspect,
          label: 'State',
          icon: Icons.tune_outlined,
        ),
      ];
    default:
      return const <CommandPanelDetailMode>[];
  }
}

/// Returns second-level tabs available inside the selected right workspace.
List<ShellTab> _detailTabsForMode(
  String panelId,
  String areaId,
  String modeId,
) {
  return const <ShellTab>[];
}

/// Converts a Computer right-side mode into the target detail content id.
String _targetDetailModeForLaunchpadMode(String modeId) {
  return modeId == _automationDetailDetails
      ? _automationTargetDetailSettings
      : modeId;
}

class _AutomationInboxContent extends StatelessWidget {
  const _AutomationInboxContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds pending operator approval items.
  @override
  Widget build(BuildContext context) {
    final inbox = _filterPendingItems(controller.automationInbox, query);
    if (inbox.isEmpty) {
      return const PanelEmptyBody(label: 'No pending automation items');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        for (final item in inbox)
          _PendingItemTile(controller: controller, item: item),
      ],
    );
  }
}

class _AutomationLaunchpadContent extends StatelessWidget {
  const _AutomationLaunchpadContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds saved Launchpad as the Launchpad artifact catalog.
  @override
  Widget build(BuildContext context) {
    final setups = _filterRunSetups(controller.automationRunSetups, query);
    if (setups.isEmpty) {
      return const PanelEmptyBody(label: 'No launchpad');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        for (final setup in setups)
          _RunSetupTile(controller: controller, setup: setup),
      ],
    );
  }
}

class _AutomationRuntimeTargetsContent extends StatelessWidget {
  const _AutomationRuntimeTargetsContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds selectable Computer or Server targets for Launchpad.
  @override
  Widget build(BuildContext context) {
    final targets = _filterRuntimeTargets(
      controller.automationRuntimeTargets,
      query,
    );
    if (targets.isEmpty) {
      return const PanelEmptyBody(label: 'No computers');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        for (final target in targets)
          _RuntimeTargetTile(controller: controller, target: target),
      ],
    );
  }
}

class _AutomationDraftsContent extends StatelessWidget {
  const _AutomationDraftsContent({
    required this.controller,
    required this.query,
    required this.kind,
    required this.emptyLabel,
  });

  final AgentAwesomeAppController controller;
  final String query;
  final String kind;
  final String emptyLabel;

  /// Builds draft rows for one authoring section.
  @override
  Widget build(BuildContext context) {
    final drafts = _filterDrafts(
      controller.automationDrafts
          .where((draft) => _draftMatchesSectionKind(draft, kind))
          .toList(),
      query,
    );
    final selectedDraft = _selectedAutomationDraftForKind(controller, kind);
    final visibleDrafts = _draftsWithSelected(drafts, selectedDraft);
    if (visibleDrafts.isEmpty) {
      return PanelEmptyBody(label: emptyLabel);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        for (final draft in visibleDrafts)
          _DraftTile(
            controller: controller,
            draft: draft,
            selected: selectedDraft?.id == draft.id,
            onDuplicate: () =>
                unawaited(controller.duplicateAutomationDraftFromUi(draft)),
            onDelete: () => unawaited(
              _showDeleteAutomationDraftDialog(context, controller, draft),
            ),
          ),
      ],
    );
  }
}

class _AutomationRunbookStatePaletteContent extends StatelessWidget {
  const _AutomationRunbookStatePaletteContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds the shell-owned runbook builder node palette.
  @override
  Widget build(BuildContext context) {
    final selectedDraft = _selectedAutomationDraftForKind(
      controller,
      automationRunbookKind,
    );
    final actionIntents = _RunbookActionIntentScope.maybeOf(context);
    return _StateMachinePalette(
      actionTypes: _resolvedAutomationActionTypes(controller),
      query: query,
      onAddState: (actionName) {
        if (selectedDraft == null || controller.automationsBusy) {
          return;
        }
        controller.selectAutomationDraft(selectedDraft.id);
        if (actionIntents != null) {
          actionIntents.addAction(actionName);
        }
      },
    );
  }
}

class _AutomationDetailContent extends StatelessWidget {
  const _AutomationDetailContent({
    required this.controller,
    required this.stateMachineEditor,
    required this.areaId,
    required this.modeId,
    required this.onDetailModeRequested,
  });

  final AgentAwesomeAppController controller;
  final _StateMachineDraftEditController stateMachineEditor;
  final String areaId;
  final String modeId;
  final ValueChanged<String> onDetailModeRequested;

  @override
  Widget build(BuildContext context) {
    if (areaId == _automationPanelLaunchpad) {
      return _LaunchpadDetail(controller: controller, modeId: modeId);
    }
    if (_automationLaunchpadAreaIds.contains(areaId)) {
      return _LaunchpadDetail(
        controller: controller,
        areaId: areaId,
        modeId: modeId,
      );
    }
    final draftKind = _automationDraftKindForArea(areaId);
    if (draftKind != null) {
      return _DraftDetail(
        controller: controller,
        stateMachineEditor: stateMachineEditor,
        modeId: modeId,
        draft: _selectedAutomationDraftForKind(controller, draftKind),
        onDetailModeRequested: onDetailModeRequested,
      );
    }
    if (areaId == _automationPanelRunbooks) {
      return _DraftDetail(
        controller: controller,
        stateMachineEditor: stateMachineEditor,
        modeId: modeId,
        draft: _selectedAutomationDraftForKind(
          controller,
          automationRunbookKind,
        ),
        onDetailModeRequested: onDetailModeRequested,
      );
    }
    return _LaunchpadDetail(controller: controller, modeId: modeId);
  }
}

class _LaunchpadDetail extends StatelessWidget {
  const _LaunchpadDetail({
    required this.controller,
    required this.modeId,
    this.areaId = _automationLaunchpadAreaRuns,
  });

  final AgentAwesomeAppController controller;
  final String areaId;
  final String modeId;

  @override
  Widget build(BuildContext context) {
    if (areaId == _automationLaunchpadAreaTargets) {
      final targetMode = _targetDetailModeForLaunchpadMode(modeId);
      return _LaunchpadRuntimeTargetDetail(
        target: controller.selectedAutomationRuntimeTarget,
        health: controller.selectedAutomationTargetHealth,
        logs: controller.selectedAutomationTargetLogs,
        secrets: controller.selectedAutomationTargetSecrets,
        codebases: controller.automationCodebases,
        capabilities: controller.automationCapabilities,
        launchpad: controller.automationRunSetups,
        modeId: targetMode,
      );
    }
    final selectedSetup = _selectedLaunchSetupFrom(
      controller.automationRunSetups,
      controller.selectedAutomationRunSetup,
    );
    final selectedDefinition = areaId == _automationLaunchpadAreaPublished
        ? (selectedSetup == null
              ? null
              : _definitionForId(
                  controller.automationDefinitions,
                  selectedSetup.definitionId,
                ))
        : controller.selectedAutomationDefinition;
    final fileSetups = areaId == _automationLaunchpadAreaPublished
        ? controller.automationRunSetups
        : _launchSetupsForDefinition(
            controller.automationRunSetups,
            selectedDefinition,
          );
    final fileRuns = _launchRunsForDefinition(
      controller.automationRuns,
      selectedDefinition,
    );
    final selectedRun = _selectedAutomationRunFrom(
      fileRuns,
      controller.selectedAutomationRun,
    );
    if (areaId == _automationLaunchpadAreaPublished &&
        modeId == _automationDetailDetails) {
      return _LaunchpadRunSetupDetail(
        definitions: controller.automationDefinitions,
        definition: selectedDefinition,
        codebases: controller.automationCodebases,
        targets: controller.automationRuntimeTargets,
        runs: fileRuns,
        setups: fileSetups,
        selectedSetup: selectedSetup,
        modeId: _automationDetailDetails,
        onChanged: (setup) =>
            unawaited(controller.updateAutomationRunSetupFromUi(setup)),
      );
    }
    if (modeId == _automationDetailLaunchpad ||
        areaId == _automationLaunchpadAreaSetups) {
      return _LaunchpadRunSetupsWorkspace(
        controller: controller,
        definitions: controller.automationDefinitions,
        codebases: controller.automationCodebases,
        targets: controller.automationRuntimeTargets,
        setups: fileSetups,
        selectedSetup: selectedSetup,
      );
    }
    if (modeId == _automationDetailSchedules ||
        areaId == _automationLaunchpadAreaSchedules) {
      return _LaunchpadSchedulesWorkspace(
        controller: controller,
        definitions: controller.automationDefinitions,
        setups: fileSetups,
        selectedSetup: selectedSetup,
      );
    }
    if (modeId == _automationDetailArtifacts ||
        areaId == _automationLaunchpadAreaArtifacts) {
      final artifacts = _launchArtifactsForRuns(
        fileRuns,
        definitions: controller.automationDefinitions,
      );
      return _LaunchpadArtifactsWorkspace(
        controller: controller,
        artifacts: artifacts,
        selectedRun: selectedRun,
      );
    }
    if (modeId == _automationDetailHistory ||
        areaId == _automationLaunchpadAreaRuns) {
      return _LaunchpadRunsWorkspace(
        controller: controller,
        definitions: controller.automationDefinitions,
        launchpad: fileSetups,
        targets: controller.automationRuntimeTargets,
        runs: fileRuns,
        selectedRun: selectedRun,
        snapshot: controller.selectedAutomationLaunchRunSnapshot,
        events: controller.selectedAutomationEvents,
      );
    }
    return switch (areaId) {
      _automationLaunchpadAreaInbox => _LaunchpadInboxOverview(
        items: controller.automationInbox,
        selectedItem: controller.selectedAutomationPendingItem,
      ),
      _automationLaunchpadAreaPublished => _LaunchpadPublishedOverview(
        setups: controller.automationRunSetups,
        selectedSetup: selectedSetup,
        definitions: controller.automationDefinitions,
        codebases: controller.automationCodebases,
        targets: controller.automationRuntimeTargets,
      ),
      _automationLaunchpadAreaSetups => _LaunchpadRunSetupsOverview(
        definitions: controller.automationDefinitions,
        codebases: controller.automationCodebases,
        targets: controller.automationRuntimeTargets,
        setups: controller.automationRunSetups,
        selectedSetup: controller.selectedAutomationRunSetup,
      ),
      _automationLaunchpadAreaSchedules => _LaunchpadSchedulesOverview(
        definitions: controller.automationDefinitions,
        setups: controller.automationRunSetups,
        selectedSetup: controller.selectedAutomationRunSetup,
      ),
      _automationLaunchpadAreaArtifacts => _LaunchpadArtifactsOverview(
        artifacts: _launchArtifactsForRuns(
          controller.automationRuns,
          definitions: controller.automationDefinitions,
        ),
        selectedRun: controller.selectedAutomationRun,
      ),
      _ => _LaunchpadRunOverview(
        definitions: controller.automationDefinitions,
        launchpad: controller.automationRunSetups,
        targets: controller.automationRuntimeTargets,
        run: controller.selectedAutomationRun,
        snapshot: controller.selectedAutomationLaunchRunSnapshot,
        runCount: controller.automationRuns.length,
      ),
    };
  }
}

const Set<String> _automationLaunchpadAreaIds = <String>{
  _automationLaunchpadAreaInbox,
  _automationLaunchpadAreaPublished,
  _automationLaunchpadAreaSetups,
  _automationLaunchpadAreaTargets,
  _automationLaunchpadAreaSchedules,
  _automationLaunchpadAreaArtifacts,
  _automationLaunchpadAreaRuns,
};

class _DraftDetail extends StatelessWidget {
  const _DraftDetail({
    required this.controller,
    required this.stateMachineEditor,
    required this.modeId,
    required this.draft,
    required this.onDetailModeRequested,
  });

  final AgentAwesomeAppController controller;
  final _StateMachineDraftEditController stateMachineEditor;
  final String modeId;
  final AutomationDraft? draft;
  final ValueChanged<String> onDetailModeRequested;

  @override
  Widget build(BuildContext context) {
    final selectedDraft = draft;
    if (selectedDraft == null) {
      return const _CompactDetailEmptyBlock(label: 'No draft selected');
    }
    if (modeId == _automationDetailBuilder ||
        modeId == _automationDetailInspect) {
      return _StateMachineBuilderWorkspace(
        key: ValueKey<String>('${selectedDraft.id}:state-machine-workspace'),
        editor: stateMachineEditor,
        controller: controller,
        draft: selectedDraft,
        modeId: modeId,
        onDetailModeRequested: onDetailModeRequested,
      );
    }
    return _RunbookMetadataEditor(
      identity: selectedDraft.id,
      name: selectedDraft.name,
      description: _runbookDraftDescription(selectedDraft),
      status: _draftStatusLabel(selectedDraft.status),
      editable: !controller.automationsBusy,
      onSave: (name, description) => controller.saveAutomationDraftFromUi(
        _runbookDraftWithMetadata(
          selectedDraft,
          name: name,
          description: description,
        ),
      ),
    );
  }
}

/// Returns available runbook action types with built-in labels while loading.
List<AutomationActionType> _resolvedAutomationActionTypes(
  AgentAwesomeAppController controller,
) {
  final known = <String, AutomationActionType>{
    for (final action in controller.automationActionTypes)
      if (action.name.trim().isNotEmpty) action.name: action,
  };
  final capabilityByAction = <String, AutomationCapability>{
    for (final capability in controller.automationCapabilities)
      if (capability.kind == 'runbook_action' && capability.name.isNotEmpty)
        capability.name: capability,
  };
  final names = known.keys.isEmpty
      ? const <String>[
          'tool.call',
          'mcp.call',
          'command.execute',
          'data.assert',
          'data.defaults',
          'human.request',
          'delay.until',
          'runbook.run',
          'runbook.signal',
        ]
      : known.keys.toList();
  return <AutomationActionType>[
    for (final name in names)
      _resolvedActionType(name, known, capabilityByAction),
  ];
}

/// Applies capability availability to one authoring action type.
AutomationActionType _resolvedActionType(
  String name,
  Map<String, AutomationActionType> known,
  Map<String, AutomationCapability> capabilityByAction,
) {
  final base =
      known[name] ??
      AutomationActionType(
        name: name,
        label: _fallbackActionLabel(name),
        description: _fallbackActionDescription(name),
        risk: 'runbook',
        available: true,
      );
  final capability = capabilityByAction[name];
  if (capability == null) {
    return base;
  }
  return AutomationActionType(
    name: base.name,
    label: base.label,
    description: base.description,
    risk: base.risk,
    available:
        base.available &&
        capability.usableInRunbooks &&
        capability.availability.status == 'available',
    inputSchema: base.inputSchema,
    outputSchema: base.outputSchema,
    inputContracts: base.inputContracts,
    outputContracts: base.outputContracts,
  );
}

class _AutomationTextField extends PanelTextFormField {
  /// Creates a shared Automations text field.
  const _AutomationTextField({
    super.key,
    required super.controller,
    required super.label,
    super.minLines,
    super.maxLines = 1,
    super.keyboardType,
    super.monospace = false,
    super.onChanged,
    super.onSubmitted,
  });
}

class _AutomationDropdown extends StatelessWidget {
  /// Creates a shared Automations dropdown field.
  const _AutomationDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.labels = const <String, String>{},
  });

  /// Field label.
  final String label;

  /// Current selected value.
  final String value;

  /// Available selectable values.
  final List<String> values;

  /// User-facing labels keyed by value.
  final Map<String, String> labels;

  /// Emits selected value changes.
  final ValueChanged<String> onChanged;

  /// Builds one compact automation builder dropdown.
  @override
  Widget build(BuildContext context) {
    final options = values.isEmpty ? <String>[''] : values;
    final selected = options.contains(value) ? value : options.first;
    return PanelDropdownFormField<String>(
      label: label,
      value: selected,
      values: options,
      labelFor: (option) =>
          labels[option] ?? (option.isEmpty ? 'None' : option),
      onChanged: onChanged,
    );
  }
}

class _RunbookMetadataEditor extends StatefulWidget {
  /// Creates a debounced metadata editor for one runbook file.
  const _RunbookMetadataEditor({
    required this.identity,
    required this.name,
    required this.description,
    required this.status,
    required this.editable,
    required this.onSave,
  });

  /// Stable runbook or draft identity used for rehydration.
  final String identity;

  /// Current runbook display name.
  final String name;

  /// Current runbook description.
  final String description;

  /// User-facing runbook status.
  final String status;

  /// Whether the selected runbook has an editable backing draft.
  final bool editable;

  /// Persists changed runbook metadata.
  final Future<void> Function(String name, String description) onSave;

  @override
  State<_RunbookMetadataEditor> createState() => _RunbookMetadataEditorState();
}

class _RunbookMetadataEditorState extends State<_RunbookMetadataEditor> {
  static const Duration _saveDelay = Duration(milliseconds: 650);

  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final PanelSaveFeedbackController _feedback = PanelSaveFeedbackController();
  Timer? _debounce;
  String _savedName = '';
  String _savedDescription = '';
  bool _hydrating = false;

  /// Initializes field state and autosave listeners.
  @override
  void initState() {
    super.initState();
    _hydrate();
    _name.addListener(_scheduleSave);
    _description.addListener(_scheduleSave);
  }

  /// Rehydrates when the selected runbook changes.
  @override
  void didUpdateWidget(covariant _RunbookMetadataEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.name != widget.name ||
        oldWidget.description != widget.description) {
      _hydrate();
    }
  }

  /// Releases field and feedback resources.
  @override
  void dispose() {
    _flushSave();
    _debounce?.cancel();
    _feedback.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Builds editable runbook metadata fields.
  @override
  Widget build(BuildContext context) {
    return PanelFormView(
      children: <Widget>[
        PanelFormSection(
          title: 'Runbook',
          children: <Widget>[
            PanelSaveFeedback(
              controller: _feedback,
              child: Column(
                children: <Widget>[
                  _RunbookMetadataSummary(status: widget.status),
                  const SizedBox(height: 12),
                  PanelTextFormField(
                    key: const ValueKey<String>('runbook-metadata-name'),
                    label: 'Runbook Name',
                    controller: _name,
                    enabled: widget.editable,
                    onChanged: (_) => _scheduleSave(),
                  ),
                  const SizedBox(height: 12),
                  PanelTextFormField(
                    key: const ValueKey<String>('runbook-metadata-description'),
                    label: 'Description',
                    controller: _description,
                    enabled: widget.editable,
                    minLines: 3,
                    maxLines: 5,
                    onChanged: (_) => _scheduleSave(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Replaces controller text from widget values.
  void _hydrate() {
    _debounce?.cancel();
    _hydrating = true;
    _savedName = widget.name.trim();
    _savedDescription = widget.description.trim();
    _name.text = _savedName;
    _description.text = _savedDescription;
    _hydrating = false;
  }

  /// Schedules an autosave after a short edit pause.
  void _scheduleSave() {
    if (_hydrating || !widget.editable) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(_saveDelay, _flushSave);
  }

  /// Persists changed values when they differ from the last saved values.
  void _flushSave() {
    if (_hydrating || !widget.editable) {
      return;
    }
    _debounce?.cancel();
    final nextName = _name.text.trim();
    final nextDescription = _description.text.trim();
    if (nextName.isEmpty ||
        (nextName == _savedName && nextDescription == _savedDescription)) {
      return;
    }
    _savedName = nextName;
    _savedDescription = nextDescription;
    unawaited(_feedback.run(() => widget.onSave(nextName, nextDescription)));
  }
}

class _RunbookMetadataSummary extends StatelessWidget {
  /// Creates compact non-editable runbook metadata text.
  const _RunbookMetadataSummary({required this.status});

  /// Current runbook status.
  final String status;

  /// Builds compact status text inside the runbook section.
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (status.trim().isNotEmpty) PanelBadge(label: status),
      ],
    );
  }
}

class _LaunchpadInboxOverview extends StatelessWidget {
  const _LaunchpadInboxOverview({
    required this.items,
    required this.selectedItem,
  });

  final List<AutomationPendingItem> items;
  final AutomationPendingItem? selectedItem;

  /// Builds detail context for pending operator approvals.
  @override
  Widget build(BuildContext context) {
    final openItems = items.where((item) => item.status == 'open').length;
    final item = selectedItem;
    return _DetailList(
      title: 'Inbox',
      rows: <String>[
        'Pending items: ${items.length}',
        'Open approvals: $openItems',
        if (item != null) 'Selected: ${item.prompt}',
        if (item != null) 'Status: ${_draftStatusLabel(item.status)}',
        if (item != null && item.updatedAt.isNotEmpty)
          'Updated: ${item.updatedAt}',
      ],
    );
  }
}

class _LaunchpadPublishedOverview extends StatelessWidget {
  const _LaunchpadPublishedOverview({
    required this.setups,
    required this.selectedSetup,
    required this.definitions,
    required this.codebases,
    required this.targets,
  });

  final List<AutomationRunSetup> setups;
  final AutomationRunSetup? selectedSetup;
  final List<AutomationDefinition> definitions;
  final List<AutomationCodebase> codebases;
  final List<AutomationRuntimeTarget> targets;

  /// Builds detail context for saved Launchpad.
  @override
  Widget build(BuildContext context) {
    final setup = selectedSetup;
    return _DetailList(
      title: 'Launchpad',
      rows: <String>[
        'Launchpad: ${setups.length}',
        if (setup != null) 'Selected: ${setup.name}',
        if (setup != null)
          'Runbook: ${_definitionLabel(definitions, setup.definitionId)}',
        if (setup != null && setup.runtimeTargetId.isNotEmpty)
          'Run on: ${_targetLabel(targets, setup.runtimeTargetId)}',
        if (setup != null)
          ..._launchSafetyRows(setup, codebases: codebases, targets: targets),
        if (setup != null && setup.updatedAt.isNotEmpty)
          'Updated: ${setup.updatedAt}',
      ],
    );
  }
}

class _LaunchpadRunSetupDetail extends StatelessWidget {
  const _LaunchpadRunSetupDetail({
    required this.definitions,
    required this.definition,
    required this.codebases,
    required this.targets,
    required this.runs,
    required this.setups,
    required this.selectedSetup,
    required this.modeId,
    required this.onChanged,
  });

  final List<AutomationDefinition> definitions;
  final AutomationDefinition? definition;
  final List<AutomationCodebase> codebases;
  final List<AutomationRuntimeTarget> targets;
  final List<AutomationRun> runs;
  final List<AutomationRunSetup> setups;
  final AutomationRunSetup? selectedSetup;
  final String modeId;
  final ValueChanged<AutomationRunSetup> onChanged;

  /// Builds one saved Launch detail mode.
  @override
  Widget build(BuildContext context) {
    final setup = selectedSetup;
    if (setup == null) {
      return const _CompactDetailEmptyBlock(label: 'No launch selected');
    }
    return switch (modeId) {
      _automationDetailHistory => _DetailList(
        title: 'Runs',
        rows: _launchRunRows(setup, runs, definitions: definitions),
      ),
      _automationDetailDetails => _LaunchpadRunSetupEditor(
        setup: setup,
        definition: definition,
        definitions: definitions,
        targets: targets,
        onChanged: onChanged,
      ),
      _ => _LaunchpadRunSetupsOverview(
        definitions: definitions,
        codebases: codebases,
        targets: targets,
        setups: setups,
        selectedSetup: setup,
      ),
    };
  }
}

class _LaunchpadRunSetupEditor extends StatefulWidget {
  const _LaunchpadRunSetupEditor({
    required this.setup,
    required this.definition,
    required this.definitions,
    required this.targets,
    required this.onChanged,
  });

  final AutomationRunSetup setup;
  final AutomationDefinition? definition;
  final List<AutomationDefinition> definitions;
  final List<AutomationRuntimeTarget> targets;
  final ValueChanged<AutomationRunSetup> onChanged;

  @override
  State<_LaunchpadRunSetupEditor> createState() =>
      _LaunchpadRunSetupEditorState();
}

class _LaunchpadRunSetupEditorState extends State<_LaunchpadRunSetupEditor> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final Map<String, TextEditingController> _inputTextControllers =
      <String, TextEditingController>{};
  final Map<String, bool> _inputBooleanValues = <String, bool>{};
  List<_RunbookRunInputField> _inputFields = const <_RunbookRunInputField>[];
  Timer? _debounce;
  String _activeId = '';
  String _definitionId = '';
  String _targetId = '';
  String _inputError = '';
  bool _hydrating = false;

  @override
  void initState() {
    super.initState();
    _hydrate(widget.setup);
    _name.addListener(_scheduleSave);
    _description.addListener(_scheduleSave);
  }

  @override
  void didUpdateWidget(covariant _LaunchpadRunSetupEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.setup.id != widget.setup.id ||
        oldWidget.definition?.id != widget.definition?.id ||
        oldWidget.setup.name != widget.setup.name ||
        oldWidget.setup.description != widget.setup.description ||
        oldWidget.setup.runtimeTargetId != widget.setup.runtimeTargetId ||
        _jsonSignature(oldWidget.setup.input) !=
            _jsonSignature(widget.setup.input)) {
      _hydrate(widget.setup);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _description.dispose();
    for (final controller in _inputTextControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Builds the selected Launch typed setup editor.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelFormView(
      children: <Widget>[
        PanelFormSection(
          title: 'Launch',
          children: <Widget>[
            _AutomationTextField(
              key: const ValueKey<String>('automation-launch-edit-name'),
              controller: _name,
              label: 'Launch Name',
              onChanged: (_) => _scheduleSave(),
              onSubmitted: (_) => _flushSave(),
            ),
            const SizedBox(height: 12),
            _AutomationTextField(
              key: const ValueKey<String>('automation-launch-edit-description'),
              controller: _description,
              label: 'Description',
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => _scheduleSave(),
            ),
            const SizedBox(height: 12),
            _AutomationDropdown(
              key: const ValueKey<String>('automation-launch-edit-runbook'),
              label: 'Runbook',
              value: _definitionId,
              values: <String>[
                for (final definition in widget.definitions) definition.id,
              ],
              labels: <String, String>{
                for (final definition in widget.definitions)
                  definition.id: definition.name,
              },
              onChanged: (value) => setState(() {
                _definitionId = value;
                _scheduleSave();
              }),
            ),
          ],
        ),
        PanelFormSection(
          title: 'Runtime',
          children: <Widget>[
            _AutomationDropdown(
              key: const ValueKey<String>('automation-launch-edit-target'),
              label: 'Run on',
              value: _targetId,
              values: <String>[for (final target in widget.targets) target.id],
              labels: <String, String>{
                for (final target in widget.targets) target.id: target.name,
              },
              onChanged: (value) => setState(() {
                _targetId = value;
                _scheduleSave();
              }),
            ),
          ],
        ),
        if (_inputFields.isNotEmpty)
          PanelFormSection(
            title: 'Run Defaults',
            children: <Widget>[
              for (final field in _inputFields) ...<Widget>[
                _RunbookRunInputFieldControl(
                  field: field,
                  textController: _inputTextControllers[field.name],
                  booleanValue: _inputBooleanValues[field.name] ?? false,
                  onBooleanChanged: (value) => setState(() {
                    _inputBooleanValues[field.name] = value;
                    _scheduleSave();
                  }),
                  onChanged: _scheduleSave,
                ),
                const SizedBox(height: 12),
              ],
              if (_inputError.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _inputError,
                    style: TextStyle(color: colors.coral, fontSize: 12),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// Replaces editor state when the selected Launch changes.
  void _hydrate(AutomationRunSetup setup) {
    _debounce?.cancel();
    _hydrating = true;
    _activeId = setup.id;
    _definitionId = setup.definitionId;
    _name.text = setup.name;
    _description.text = setup.description;
    _targetId = setup.runtimeTargetId;
    _inputError = '';
    for (final controller in _inputTextControllers.values) {
      controller.dispose();
    }
    _inputTextControllers.clear();
    _inputBooleanValues.clear();
    _inputFields = _launchInputFieldsForSetup(widget.definition, setup);
    for (final field in _inputFields) {
      if (field.type == 'boolean') {
        _inputBooleanValues[field.name] = _initialBooleanValue(
          field.defaultValue,
        );
      } else {
        final controller = TextEditingController(
          text: _initialFieldText(field.defaultValue),
        );
        controller.addListener(_scheduleSave);
        _inputTextControllers[field.name] = controller;
      }
    }
    _hydrating = false;
  }

  /// Schedules bounded autosave after field edits.
  void _scheduleSave() {
    if (_hydrating || _activeId.isEmpty) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 650), _flushSave);
  }

  /// Persists the current Launch form values when the name is valid.
  void _flushSave() {
    if (_hydrating || _activeId.isEmpty) {
      return;
    }
    _debounce?.cancel();
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    final input = Map<String, dynamic>.from(widget.setup.input);
    if (_inputFields.isNotEmpty) {
      input.clear();
      final error = _populateRunbookInputFromFields(
        fields: _inputFields,
        textControllers: _inputTextControllers,
        booleanValues: _inputBooleanValues,
        input: input,
      );
      if (error != null) {
        setState(() => _inputError = error);
        return;
      }
    }
    if (_launchFormUnchanged(name, input)) {
      return;
    }
    if (_inputError.isNotEmpty) {
      setState(() => _inputError = '');
    }
    widget.onChanged(
      widget.setup.copyWith(
        definitionId: _definitionId,
        name: name,
        description: _description.text.trim(),
        runtimeTargetId: _targetId,
        input: input,
      ),
    );
  }

  /// Reports whether the current form fields still match the selected Launch.
  bool _launchFormUnchanged(String name, Map<String, dynamic> input) {
    return _definitionId == widget.setup.definitionId &&
        name == widget.setup.name.trim() &&
        _description.text.trim() == widget.setup.description.trim() &&
        _targetId == widget.setup.runtimeTargetId &&
        _jsonSignature(input) == _jsonSignature(widget.setup.input);
  }
}

class _LaunchpadRunSetupsOverview extends StatelessWidget {
  const _LaunchpadRunSetupsOverview({
    required this.definitions,
    required this.codebases,
    required this.targets,
    required this.setups,
    required this.selectedSetup,
  });

  final List<AutomationDefinition> definitions;
  final List<AutomationCodebase> codebases;
  final List<AutomationRuntimeTarget> targets;
  final List<AutomationRunSetup> setups;
  final AutomationRunSetup? selectedSetup;

  /// Builds detail context for saved Launchpad.
  @override
  Widget build(BuildContext context) {
    final setup = selectedSetup;
    return _DetailList(
      title: 'Launchpad',
      rows: <String>[
        'Launchpad: ${setups.length}',
        if (setup != null) 'Selected: ${setup.name}',
        if (setup != null)
          'Runbook file: ${_definitionLabel(definitions, setup.definitionId)}',
        if (setup != null && setup.runtimeTargetId.isNotEmpty)
          'Run on: ${_targetLabel(targets, setup.runtimeTargetId)}',
        if (setup != null)
          ..._launchSafetyRows(setup, codebases: codebases, targets: targets),
        if (setup != null && setup.updatedAt.isNotEmpty)
          'Updated: ${setup.updatedAt}',
      ],
    );
  }
}

class _LaunchpadRunSetupsWorkspace extends StatelessWidget {
  const _LaunchpadRunSetupsWorkspace({
    required this.controller,
    required this.definitions,
    required this.codebases,
    required this.targets,
    required this.setups,
    required this.selectedSetup,
  });

  final AgentAwesomeAppController controller;
  final List<AutomationDefinition> definitions;
  final List<AutomationCodebase> codebases;
  final List<AutomationRuntimeTarget> targets;
  final List<AutomationRunSetup> setups;
  final AutomationRunSetup? selectedSetup;

  /// Builds saved Launchpad as a right-side collection workspace.
  @override
  Widget build(BuildContext context) {
    final setup = selectedSetup;
    if (setups.isEmpty) {
      return const PanelEmptyBody(label: 'No launchpad');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        for (final item in setups)
          _RunSetupTile(controller: controller, setup: item),
        if (setup != null) ...<Widget>[
          const SizedBox(height: 12),
          PanelSectionBlock(
            title: 'Selected Launch',
            child: _DetailRows(
              rows: _launchSetupRows(
                setup,
                definitions: definitions,
                codebases: codebases,
                targets: targets,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LaunchpadSchedulesWorkspace extends StatelessWidget {
  const _LaunchpadSchedulesWorkspace({
    required this.controller,
    required this.definitions,
    required this.setups,
    required this.selectedSetup,
  });

  final AgentAwesomeAppController controller;
  final List<AutomationDefinition> definitions;
  final List<AutomationRunSetup> setups;
  final AutomationRunSetup? selectedSetup;

  /// Builds scheduled Launchpad as a right-side collection.
  @override
  Widget build(BuildContext context) {
    final scheduled = setups.where(_launchHasSchedule).toList();
    final selected = selectedSetup != null && _launchHasSchedule(selectedSetup!)
        ? selectedSetup
        : scheduled.isEmpty
        ? null
        : scheduled.first;
    if (scheduled.isEmpty) {
      return const PanelEmptyBody(label: 'No scheduled launchpad');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        for (final setup in scheduled)
          _ScheduleTile(controller: controller, setup: setup),
        if (selected != null) ...<Widget>[
          const SizedBox(height: 12),
          PanelSectionBlock(
            title: 'Selected Schedule',
            child: _DetailRows(
              rows: <String>[
                'Launch: ${selected.name}',
                'Runbook file: ${_definitionLabel(definitions, selected.definitionId)}',
                'Schedule: ${_launchScheduleLabel(selected.schedule)}',
                ..._launchScheduleRows(selected).skip(1),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LaunchpadArtifactsWorkspace extends StatelessWidget {
  const _LaunchpadArtifactsWorkspace({
    required this.controller,
    required this.artifacts,
    required this.selectedRun,
  });

  final AgentAwesomeAppController controller;
  final List<_LaunchArtifactItem> artifacts;
  final AutomationRun? selectedRun;

  /// Builds run artifacts as a right-side collection.
  @override
  Widget build(BuildContext context) {
    final selectedArtifacts = selectedRun == null
        ? artifacts
        : artifacts
              .where((artifact) => artifact.run.id == selectedRun!.id)
              .toList();
    final visible = selectedArtifacts.isEmpty ? artifacts : selectedArtifacts;
    if (visible.isEmpty) {
      return const PanelEmptyBody(label: 'No artifacts');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        for (final artifact in visible)
          _ArtifactTile(controller: controller, artifact: artifact),
      ],
    );
  }
}

class _LaunchpadRunsWorkspace extends StatelessWidget {
  const _LaunchpadRunsWorkspace({
    required this.controller,
    required this.definitions,
    required this.launchpad,
    required this.targets,
    required this.runs,
    required this.selectedRun,
    required this.snapshot,
    required this.events,
  });

  final AgentAwesomeAppController controller;
  final List<AutomationDefinition> definitions;
  final List<AutomationRunSetup> launchpad;
  final List<AutomationRuntimeTarget> targets;
  final List<AutomationRun> runs;
  final AutomationRun? selectedRun;
  final AutomationLaunchRunSnapshot? snapshot;
  final List<AutomationEvent> events;

  /// Builds automation run history as a right-side collection.
  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return const PanelEmptyBody(label: 'No recent automation runs');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        SettingsValidationScenarioTable(
          scenarios: <SettingsValidationScenario>[
            for (final run in runs)
              _runValidationScenario(
                run: run,
                definitions: definitions,
                launchpad: launchpad,
                targets: targets,
                snapshot: snapshot?.runId == run.id ? snapshot : null,
                events: selectedRun?.id == run.id
                    ? events
                    : const <AutomationEvent>[],
              ),
          ],
          selectedRunMode: 'mocked',
          runningMode: '',
          runningValidationIds: const <String>{},
          runningAll: false,
          liveAvailable: false,
          showControls: false,
          showModeColumn: false,
          showActions: false,
          primaryColumnLabel: 'Run',
          descriptionColumnLabel: 'Ran',
          statusColumnLabel: 'Status',
          emptyLabel: 'No recent automation runs',
          onScenarioExpanded: (scenario) {
            if (selectedRun?.id != scenario.id) {
              unawaited(controller.selectAutomationRun(scenario.id));
            }
          },
          onRunAll: (_) {},
          onRunScenario: (_) {},
          onDeleteScenario: (_) {},
          onAddValidation: null,
        ),
      ],
    );
  }
}

class _AutomationRunMetricsDetail extends StatelessWidget {
  const _AutomationRunMetricsDetail({
    required this.run,
    required this.definitions,
    required this.launchpad,
    required this.targets,
    required this.snapshot,
    required this.events,
  });

  final AutomationRun run;
  final List<AutomationDefinition> definitions;
  final List<AutomationRunSetup> launchpad;
  final List<AutomationRuntimeTarget> targets;
  final AutomationLaunchRunSnapshot? snapshot;
  final List<AutomationEvent> events;

  /// Builds expanded run metrics for an Launchpad run row.
  @override
  Widget build(BuildContext context) {
    final metricRows = _automationRunMetricRows(
      run: run,
      definitions: definitions,
      launchpad: launchpad,
      targets: targets,
      snapshot: snapshot,
    );
    final eventRows = _automationRunEventRows(events);
    final selectionColor = _runDetailSelectionColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelSectionBlock(
          title: 'Metrics',
          trailing: _CopyDetailRowsButton(
            tooltip: 'Copy metrics',
            rows: metricRows,
          ),
          child: _DetailRows(
            rows: metricRows,
            mergeRows: true,
            selectionColor: selectionColor,
          ),
        ),
        if (eventRows.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          PanelSectionBlock(
            title: 'Events',
            trailing: _CopyDetailRowsButton(
              tooltip: 'Copy events',
              rows: eventRows,
            ),
            child: _DetailRows(
              rows: eventRows,
              mergeRows: true,
              selectionColor: selectionColor,
            ),
          ),
        ],
      ],
    );
  }
}

class _LaunchpadSchedulesOverview extends StatelessWidget {
  const _LaunchpadSchedulesOverview({
    required this.definitions,
    required this.setups,
    required this.selectedSetup,
  });

  final List<AutomationDefinition> definitions;
  final List<AutomationRunSetup> setups;
  final AutomationRunSetup? selectedSetup;

  /// Builds detail context for scheduled Launchpad.
  @override
  Widget build(BuildContext context) {
    final scheduled = setups.where(_launchHasSchedule).toList();
    final selected = selectedSetup != null && _launchHasSchedule(selectedSetup!)
        ? selectedSetup
        : scheduled.isEmpty
        ? null
        : scheduled.first;
    return _DetailList(
      title: 'Schedules',
      rows: <String>[
        'Scheduled launchpad: ${scheduled.length}',
        if (selected != null) 'Launch: ${selected.name}',
        if (selected != null)
          'Runbook file: ${_definitionLabel(definitions, selected.definitionId)}',
        if (selected != null)
          'Schedule: ${_launchScheduleLabel(selected.schedule)}',
        if (selected != null) ..._launchScheduleRows(selected).skip(1),
      ],
    );
  }
}

class _LaunchpadArtifactsOverview extends StatelessWidget {
  const _LaunchpadArtifactsOverview({
    required this.artifacts,
    required this.selectedRun,
  });

  final List<_LaunchArtifactItem> artifacts;
  final AutomationRun? selectedRun;

  /// Builds detail context for Launch run artifacts.
  @override
  Widget build(BuildContext context) {
    final selectedArtifacts = selectedRun == null
        ? artifacts
        : artifacts
              .where((artifact) => artifact.run.id == selectedRun!.id)
              .toList();
    final visible = selectedArtifacts.isEmpty ? artifacts : selectedArtifacts;
    return _DetailList(
      title: 'Artifacts',
      rows: <String>[
        'Artifacts: ${artifacts.length}',
        for (final artifact in visible.take(8))
          '${artifact.title}: ${artifact.subtitle}',
      ],
    );
  }
}

class _LaunchpadRuntimeTargetDetail extends StatelessWidget {
  const _LaunchpadRuntimeTargetDetail({
    required this.target,
    required this.health,
    required this.logs,
    required this.secrets,
    required this.codebases,
    required this.capabilities,
    required this.launchpad,
    required this.modeId,
  });

  final AutomationRuntimeTarget? target;
  final AutomationTargetHealth? health;
  final List<AutomationTargetLogEntry> logs;
  final AutomationTargetSecretMetadata? secrets;
  final List<AutomationCodebase> codebases;
  final List<AutomationCapability> capabilities;
  final List<AutomationRunSetup> launchpad;
  final String modeId;

  /// Builds the selected Computer or Server inspector.
  @override
  Widget build(BuildContext context) {
    final selected = target;
    if (selected == null) {
      return const _CompactDetailEmptyBlock(label: 'No computer selected');
    }
    return switch (modeId) {
      _automationTargetDetailCapabilities => _targetDetailList(
        title: 'Capabilities',
        rows: _targetCapabilityRows(selected, capabilities),
      ),
      _automationTargetDetailSecrets => _targetDetailList(
        title: 'Secrets',
        rows: _targetSecretRows(selected, secrets),
      ),
      _automationTargetDetailLaunchpad => _targetDetailList(
        title: 'Launchpad',
        rows: _targetLaunchRows(selected, launchpad),
      ),
      _automationTargetDetailLogs => _TargetLogList(logs: logs),
      _automationTargetDetailSettings => _targetDetailList(
        title: 'Settings',
        rows: _targetSettingsRows(selected, codebases),
      ),
      _automationTargetDetailUpdates => _targetDetailList(
        title: 'Updates',
        rows: _targetUpdateRows(selected, health),
      ),
      _automationDetailTest => _targetDetailList(
        title: 'Health',
        rows: _targetHealthRows(selected, health),
      ),
      _ => _targetDetailList(
        title: 'Computer or Server',
        rows: _targetOverviewRows(selected, health, secrets),
      ),
    };
  }

  /// Builds a target detail section from display rows.
  Widget _targetDetailList({
    required String title,
    required List<String> rows,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        PanelSectionBlock(
          title: title,
          child: _DetailRows(rows: rows),
        ),
      ],
    );
  }
}

class _TargetLogList extends StatelessWidget {
  const _TargetLogList({required this.logs});

  final List<AutomationTargetLogEntry> logs;

  /// Builds display-safe target logs.
  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const _CompactDetailEmptyBlock(label: 'No logs recorded');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        for (final log in logs)
          _AutomationTile(
            title: _targetStatusLabel(log.level),
            subtitle: log.message,
            badges: <String>[if (log.createdAt.isNotEmpty) log.createdAt],
          ),
      ],
    );
  }
}

class _LaunchpadRunOverview extends StatelessWidget {
  const _LaunchpadRunOverview({
    required this.definitions,
    required this.launchpad,
    required this.targets,
    required this.run,
    required this.snapshot,
    required this.runCount,
  });

  final List<AutomationDefinition> definitions;
  final List<AutomationRunSetup> launchpad;
  final List<AutomationRuntimeTarget> targets;
  final AutomationRun? run;
  final AutomationLaunchRunSnapshot? snapshot;
  final int runCount;

  /// Builds detail context for selected automation runs.
  @override
  Widget build(BuildContext context) {
    final selectedRun = run;
    final selectedSnapshot = snapshot?.runId == selectedRun?.id
        ? snapshot
        : null;
    return _DetailList(
      title: 'Runs',
      rows: _launchRunOverviewRows(
        definitions: definitions,
        launchpad: launchpad,
        targets: targets,
        run: selectedRun,
        snapshot: selectedSnapshot,
        runCount: runCount,
      ),
    );
  }
}

/// Builds detail rows for one selected runbook run.
List<String> _launchRunOverviewRows({
  required List<AutomationDefinition> definitions,
  required List<AutomationRunSetup> launchpad,
  required List<AutomationRuntimeTarget> targets,
  required AutomationRun? run,
  required AutomationLaunchRunSnapshot? snapshot,
  required int runCount,
}) {
  return <String>[
    'Recent runs: $runCount',
    if (run != null) 'Runbook: ${_runDefinitionLabel(definitions, run)}',
    if (run != null) 'Status: ${_draftStatusLabel(run.status)}',
    if (run != null) 'State: ${run.state}',
    if (run != null && run.updatedAt.isNotEmpty)
      'Updated: ${formatStoredTimestampLocal(run.updatedAt)}',
    if (snapshot != null)
      'Launch: ${_launchLabel(launchpad, snapshot.launchId)}',
    if (snapshot != null &&
        _stringFromMap(snapshot.target, 'runtime_target_id').isNotEmpty)
      'Run on: ${_targetLabel(targets, _stringFromMap(snapshot.target, 'runtime_target_id'))}',
    if (snapshot != null && snapshot.launchVersion > 0)
      'Launch version: ${snapshot.launchVersion}',
    if (snapshot != null &&
        _stringFromMap(snapshot.policy, 'source_control').isNotEmpty)
      'Policy: ${_launchSourceControlPolicyLabel(_stringFromMap(snapshot.policy, 'source_control'))}',
    if (snapshot != null) 'Resolved inputs: ${snapshot.resolvedInput.length}',
    if (snapshot != null) 'Secret references: ${snapshot.secretRefs.length}',
  ];
}

/// Builds one reusable expandable table row for an automation run.
SettingsValidationScenario _runValidationScenario({
  required AutomationRun run,
  required List<AutomationDefinition> definitions,
  required List<AutomationRunSetup> launchpad,
  required List<AutomationRuntimeTarget> targets,
  required AutomationLaunchRunSnapshot? snapshot,
  required List<AutomationEvent> events,
}) {
  return SettingsValidationScenario(
    id: run.id,
    label: _runDefinitionLabel(definitions, run),
    description: _runWhenLabel(run),
    modeStates: const <String, SettingsValidationModeState>{},
    status: _runOutcomeStatus(run),
    details: _AutomationRunMetricsDetail(
      run: run,
      definitions: definitions,
      launchpad: launchpad,
      targets: targets,
      snapshot: snapshot,
      events: events,
    ),
  );
}

/// Returns collapsed-row timing copy for one run.
String _runWhenLabel(AutomationRun run) {
  final started = formatStoredTimestampLocal(run.createdAt);
  final updated = formatStoredTimestampLocal(run.updatedAt);
  if (started.isNotEmpty && updated.isNotEmpty && updated != started) {
    return 'Started $started, updated $updated';
  }
  if (started.isNotEmpty) {
    return 'Started $started';
  }
  if (updated.isNotEmpty) {
    return 'Updated $updated';
  }
  return 'Run ${run.id}';
}

/// Maps runbook run status to table status semantics.
String _runOutcomeStatus(AutomationRun run) {
  final status = run.status.trim().toLowerCase().replaceAll('-', '_');
  final state = run.state.trim().toLowerCase().replaceAll('-', '_');
  if (<String>{
        'completed',
        'complete',
        'done',
        'passed',
        'succeeded',
        'success',
      }.contains(status) ||
      <String>{
        'completed',
        'complete',
        'done',
        'succeeded',
        'success',
      }.contains(state)) {
    return 'succeeded';
  }
  if (<String>{
    'failed',
    'failure',
    'error',
    'cancelled',
    'canceled',
    'timed_out',
    'timeout',
  }.contains(status)) {
    return 'failed';
  }
  return run.status.trim().isEmpty ? 'not run' : run.status.trim();
}

/// Builds available metric rows for one runbook run.
List<String> _automationRunMetricRows({
  required AutomationRun run,
  required List<AutomationDefinition> definitions,
  required List<AutomationRunSetup> launchpad,
  required List<AutomationRuntimeTarget> targets,
  required AutomationLaunchRunSnapshot? snapshot,
}) {
  final artifacts = _launchArtifactsForRun(
    run,
    runbookLabel: _runDefinitionLabel(definitions, run),
  );
  final duration = _runDurationLabel(run);
  return <String>[
    'Run: ${run.id}',
    'Runbook: ${_runDefinitionLabel(definitions, run)}',
    'Status: ${_draftStatusLabel(run.status)}',
    if (run.state.trim().isNotEmpty) 'State: ${run.state}',
    if (run.createdAt.trim().isNotEmpty)
      'Started: ${formatStoredTimestampLocal(run.createdAt)}',
    if (run.updatedAt.trim().isNotEmpty)
      'Updated: ${formatStoredTimestampLocal(run.updatedAt)}',
    if (duration.isNotEmpty) 'Duration: $duration',
    'Input fields: ${run.input.length}',
    'Output fields: ${run.output.length}',
    if (run.output.isNotEmpty)
      'Output keys: ${_automationRunOutputKeys(run.output).join(', ')}',
    'Artifacts: ${artifacts.length}',
    if (snapshot != null)
      'Launch: ${_launchLabel(launchpad, snapshot.launchId)}',
    if (snapshot != null && snapshot.launchVersion > 0)
      'Launch version: ${snapshot.launchVersion}',
    if (snapshot != null &&
        _stringFromMap(snapshot.target, 'runtime_target_id').isNotEmpty)
      'Run on: ${_targetLabel(targets, _stringFromMap(snapshot.target, 'runtime_target_id'))}',
    if (snapshot != null) 'Resolved inputs: ${snapshot.resolvedInput.length}',
    if (snapshot != null) 'Secret references: ${snapshot.secretRefs.length}',
    if (snapshot != null &&
        _stringFromMap(snapshot.policy, 'source_control').isNotEmpty)
      'Policy: ${_launchSourceControlPolicyLabel(_stringFromMap(snapshot.policy, 'source_control'))}',
  ];
}

/// Returns event rows for an expanded run.
List<String> _automationRunEventRows(List<AutomationEvent> events) {
  return <String>[
    for (final event in events)
      '${formatStoredTimestampLocal(event.createdAt)} ${event.type}: ${event.message}',
  ];
}

/// Returns output keys ordered for compact display.
List<String> _automationRunOutputKeys(Map<String, dynamic> output) {
  final keys = output.keys.map((key) => key.trim()).where((key) {
    return key.isNotEmpty;
  }).toList();
  keys.sort();
  return keys;
}

/// Returns a compact elapsed time label when run timestamps can be parsed.
String _runDurationLabel(AutomationRun run) {
  final started = DateTime.tryParse(run.createdAt.trim());
  final updated = DateTime.tryParse(run.updatedAt.trim());
  if (started == null || updated == null || updated.isBefore(started)) {
    return '';
  }
  final duration = updated.difference(started);
  if (duration.inSeconds < 1) {
    return '<1s';
  }
  if (duration.inMinutes < 1) {
    return '${duration.inSeconds}s';
  }
  if (duration.inHours < 1) {
    return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
  }
  return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
}

class _DetailList extends StatelessWidget {
  const _DetailList({required this.title, required this.rows});

  final String title;
  final List<String> rows;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        PanelSectionBlock(
          title: title,
          child: _DetailRows(rows: rows),
        ),
      ],
    );
  }
}

/// _CompactDetailEmptyBlock keeps detail placeholders aligned with list bodies.
class _CompactDetailEmptyBlock extends StatelessWidget {
  /// Creates a compact empty state for a right-side detail body.
  const _CompactDetailEmptyBlock({required this.label});

  /// Empty-state text.
  final String label;

  /// Builds the empty state inside the standard detail list padding.
  @override
  Widget build(BuildContext context) {
    return PanelEmptyBody(
      icon: Icons.info_outline,
      label: label,
      message: 'Select or create an item in the left panel to continue.',
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
    );
  }
}

class _DetailRows extends StatelessWidget {
  const _DetailRows({
    required this.rows,
    this.mergeRows = false,
    this.selectionColor,
  });

  final List<String> rows;
  final bool mergeRows;
  final Color? selectionColor;

  /// Builds selectable detail text rows.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final visibleRows = rows.where((row) => row.trim().isNotEmpty).toList();
    if (mergeRows) {
      return SelectableText(
        visibleRows.join('\n'),
        selectionColor: selectionColor,
        style: TextStyle(color: colors.ink, height: 1.45),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final row in visibleRows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText(
              row,
              selectionColor: selectionColor,
              style: TextStyle(color: colors.ink),
            ),
          ),
      ],
    );
  }
}

class _CopyDetailRowsButton extends StatelessWidget {
  const _CopyDetailRowsButton({required this.tooltip, required this.rows});

  final String tooltip;
  final List<String> rows;

  /// Builds a compact copy action for one run detail card.
  @override
  Widget build(BuildContext context) {
    final text = rows.where((row) => row.trim().isNotEmpty).join('\n');
    return PanelInlineIconButton(
      icon: Icons.copy_outlined,
      tooltip: tooltip,
      onPressed: text.isEmpty
          ? null
          : () {
              unawaited(Clipboard.setData(ClipboardData(text: text)));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied'),
                  duration: Duration(milliseconds: 900),
                ),
              );
            },
    );
  }
}

/// Returns a visible text-selection color for dense run detail blocks.
Color _runDetailSelectionColor(BuildContext context) {
  if (context.agentAwesomeIsDark) {
    return const Color(0xff8c5cff).withValues(alpha: 0.62);
  }
  return context.agentAwesomeColors.coral.withValues(alpha: 0.28);
}

class _LaunchArtifactItem {
  const _LaunchArtifactItem({
    required this.run,
    required this.title,
    required this.subtitle,
    required this.runbookLabel,
  });

  /// Runbook run that produced the artifact.
  final AutomationRun run;

  /// User-facing artifact title.
  final String title;

  /// Display-safe artifact summary.
  final String subtitle;

  /// Runbook label used as compact metadata.
  final String runbookLabel;
}

class _PendingItemTile extends StatelessWidget {
  const _PendingItemTile({required this.controller, required this.item});

  final AgentAwesomeAppController controller;
  final AutomationPendingItem item;

  @override
  Widget build(BuildContext context) {
    return _AutomationTile(
      title: item.prompt,
      subtitle: 'Waiting for response',
      selected: controller.selectedAutomationPendingItem?.id == item.id,
      badges: <String>[_draftStatusLabel(item.status)],
      onTap: () => controller.selectAutomationPendingItem(item.id),
    );
  }
}

class _RunSetupTile extends StatelessWidget {
  const _RunSetupTile({required this.controller, required this.setup});

  final AgentAwesomeAppController controller;
  final AutomationRunSetup setup;

  @override
  Widget build(BuildContext context) {
    return _AutomationTile(
      title: setup.name,
      subtitle: _definitionLabel(
        controller.automationDefinitions,
        setup.definitionId,
      ),
      selected: controller.selectedAutomationRunSetup?.id == setup.id,
      badges: <String>[
        'launch',
        if (setup.runtimeTargetId.isNotEmpty)
          _targetLabel(
            controller.automationRuntimeTargets,
            setup.runtimeTargetId,
          ),
      ],
      onTap: () => controller.selectAutomationRunSetup(setup.id),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({required this.controller, required this.setup});

  final AgentAwesomeAppController controller;
  final AutomationRunSetup setup;

  /// Builds one selectable Launch schedule row.
  @override
  Widget build(BuildContext context) {
    return _AutomationTile(
      title: setup.name,
      subtitle: _launchScheduleLabel(setup.schedule),
      selected: controller.selectedAutomationRunSetup?.id == setup.id,
      badges: <String>[
        if (_launchScheduleEnabled(setup.schedule)) 'enabled' else 'paused',
      ],
      onTap: () => controller.selectAutomationRunSetup(setup.id),
    );
  }
}

class _ArtifactTile extends StatelessWidget {
  const _ArtifactTile({required this.controller, required this.artifact});

  final AgentAwesomeAppController controller;
  final _LaunchArtifactItem artifact;

  /// Builds one selectable run artifact row.
  @override
  Widget build(BuildContext context) {
    return _AutomationTile(
      title: artifact.title,
      subtitle: artifact.subtitle,
      selected: controller.selectedAutomationRun?.id == artifact.run.id,
      badges: <String>[artifact.runbookLabel],
      onTap: () => unawaited(controller.selectAutomationRun(artifact.run.id)),
    );
  }
}

class _RuntimeTargetTile extends StatelessWidget {
  const _RuntimeTargetTile({required this.controller, required this.target});

  final AgentAwesomeAppController controller;
  final AutomationRuntimeTarget target;

  /// Builds one selectable Computer or Server target card.
  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      if (target.hostname.isNotEmpty) target.hostname,
      if (target.os.isNotEmpty) target.os,
      if (target.lastSeenAt.isNotEmpty) 'Seen ${target.lastSeenAt}',
    ].join(' · ');
    return _AutomationTile(
      title: target.name,
      subtitle: subtitle.isEmpty ? _targetKindLabel(target.kind) : subtitle,
      selected: controller.selectedAutomationRuntimeTarget?.id == target.id,
      badges: <String>[
        _targetKindLabel(target.kind),
        _targetStatusLabel(target.status),
        if (target.currentRunCount > 0) 'Runs: ${target.currentRunCount}',
      ],
      actions: <Widget>[
        PanelInlineIconButton(
          icon: Icons.content_copy,
          tooltip: 'Copy computer id',
          onPressed: () =>
              unawaited(Clipboard.setData(ClipboardData(text: target.id))),
        ),
        const PanelInlineIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete computer',
          onPressed: null,
        ),
      ],
      onTap: () =>
          unawaited(controller.selectAutomationRuntimeTarget(target.id)),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.controller,
    required this.draft,
    required this.selected,
    required this.onDuplicate,
    required this.onDelete,
  });

  final AgentAwesomeAppController controller;
  final AutomationDraft draft;
  final bool selected;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final validation = parseAutomationValidationResult(draft.validation);
    return _AutomationTile(
      title: draft.name,
      subtitle: _draftTileSubtitle(draft),
      selected: selected,
      badges: <String>[
        _draftKindLabel(draft.kind),
        _draftStatusLabel(draft.status),
        if (validation.valid) 'valid',
        if (validation.valid && !validation.publishable) 'blocked',
      ],
      actions: <Widget>[
        PanelInlineIconButton(
          icon: Icons.content_copy,
          tooltip: 'Duplicate runbook file',
          onPressed: controller.automationsBusy ? null : onDuplicate,
        ),
        PanelInlineIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete runbook file',
          onPressed: controller.automationsBusy ? null : onDelete,
        ),
      ],
      onTap: () => controller.selectAutomationDraft(draft.id),
    );
  }
}

/// Returns product-facing supporting text for a runbook draft card.
String _draftTileSubtitle(AutomationDraft draft) {
  final description = draft.description.trim();
  if (description.isNotEmpty) {
    return description;
  }
  final body = _map(draft.body);
  final definitionName = '${body['name'] ?? ''}'.trim();
  if (definitionName.isNotEmpty && definitionName != draft.name) {
    return definitionName;
  }
  return '${_draftStatusLabel(draft.status)} ${_draftKindLabel(draft.kind)}';
}

/// Returns the best editable description for one runbook draft.
String _runbookDraftDescription(AutomationDraft draft) {
  final description = draft.description.trim();
  if (description.isNotEmpty) {
    return description;
  }
  return _stringFromMap(_map(draft.body), 'description');
}

/// Returns a draft copy with runbook metadata written into the body.
AutomationDraft _runbookDraftWithMetadata(
  AutomationDraft draft, {
  required String name,
  required String description,
}) {
  final body = Map<String, dynamic>.from(_map(draft.body));
  final trimmedName = name.trim();
  final trimmedDescription = description.trim();
  if (trimmedName.isNotEmpty &&
      (_isRunbookFileKind(draft.kind) || body.containsKey('name'))) {
    body['name'] = trimmedName;
  }
  body['description'] = trimmedDescription;
  return AutomationDraft(
    id: draft.id,
    kind: draft.kind,
    name: trimmedName.isEmpty ? draft.name : trimmedName,
    description: trimmedDescription,
    status: draft.status,
    body: body,
    validation: draft.validation,
    createdAt: draft.createdAt,
    updatedAt: draft.updatedAt,
  );
}

/// Returns the user-facing label for one automation draft kind.
String _draftKindLabel(String kind) {
  return switch (kind) {
    automationRunbookKind => 'runbook',
    _stateMachineBodyKind => 'runbook',
    _ => kind.trim().replaceAll('_', ' '),
  };
}

/// Returns the user-facing label for one automation draft status.
String _draftStatusLabel(String status) {
  final normalized = status.trim().replaceAll('_', ' ');
  return normalized.isEmpty ? 'draft' : normalized;
}

/// Returns the runbook name associated with one run when it is available.
String _runDefinitionLabel(
  List<AutomationDefinition> definitions,
  AutomationRun run,
) {
  return _definitionLabel(
    definitions,
    run.definitionId,
    fallback: 'Runbook run',
  );
}

/// Returns the runbook file name for one definition id.
String _definitionLabel(
  List<AutomationDefinition> definitions,
  String definitionId, {
  String fallback = 'Runbook file',
}) {
  final definition = _definitionForId(definitions, definitionId);
  return definition?.name ?? fallback;
}

/// Returns the codebase name for one catalog id.
String _codebaseLabel(
  List<AutomationCodebase> codebases,
  String codebaseId, {
  String fallback = 'Codebase',
}) {
  for (final codebase in codebases) {
    if (codebase.id == codebaseId) {
      return codebase.name;
    }
  }
  return fallback;
}

/// Returns the Launch name for one Launch id.
String _launchLabel(
  List<AutomationRunSetup> launchpad,
  String launchId, {
  String fallback = 'Launch',
}) {
  for (final launch in launchpad) {
    if (launch.id == launchId) {
      return launch.name;
    }
  }
  return fallback;
}

/// Returns the target name for one Computer or Server id.
String _targetLabel(
  List<AutomationRuntimeTarget> targets,
  String targetId, {
  String fallback = 'Computer or Server',
}) {
  for (final target in targets) {
    if (target.id == targetId) {
      return target.name;
    }
  }
  return fallback;
}

/// Returns the first usable target id for an Launch dialog.
String _initialTargetId(
  List<AutomationRuntimeTarget> targets,
  String selectedTargetId,
) {
  if (targets.any((target) => target.id == selectedTargetId)) {
    return selectedTargetId;
  }
  return targets.isEmpty ? '' : targets.first.id;
}

/// Returns the user-facing source-control policy label.
String _launchSourceControlPolicyLabel(String policy) {
  return _launchSafetyLabels[policy.trim()] ??
      (policy.trim().isEmpty
          ? 'not configured'
          : _stateMachineDisplayName(policy));
}

/// Finds one runbook file by id.
AutomationDefinition? _definitionForId(
  List<AutomationDefinition> definitions,
  String definitionId,
) {
  for (final definition in definitions) {
    if (definition.id == definitionId) {
      return definition;
    }
  }
  return null;
}

/// Returns the user-facing label for one target kind.
String _targetKindLabel(String kind) {
  return switch (kind.trim()) {
    'local' => 'This computer',
    'lan' => 'Nearby computer',
    'cloud' => 'Cloud server',
    'managed' => 'Managed server',
    _ =>
      kind.trim().isEmpty
          ? 'Computer or Server'
          : _stateMachineDisplayName(kind),
  };
}

/// Returns the user-facing label for one target status.
String _targetStatusLabel(String status) {
  return switch (status.trim()) {
    'healthy' => 'healthy',
    'offline' => 'offline',
    'needs_setup' => 'Needs Setup',
    'needs_review' => 'Needs Review',
    _ => status.trim().isEmpty ? 'unknown' : _stateMachineDisplayName(status),
  };
}

/// Converts dynamic values to compact display-safe text.
String _displayDynamicValue(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is bool || value is num) {
    return '$value';
  }
  if (value is String) {
    return value;
  }
  return jsonEncode(value);
}

/// Builds setup rows for one saved Launch.
List<String> _launchSetupRows(
  AutomationRunSetup setup, {
  required List<AutomationDefinition> definitions,
  required List<AutomationCodebase> codebases,
  required List<AutomationRuntimeTarget> targets,
}) {
  return <String>[
    'Launch: ${setup.name}',
    'Runbook file: ${_definitionLabel(definitions, setup.definitionId)}',
    if (setup.runtimeTargetId.isNotEmpty)
      'Run on: ${_targetLabel(targets, setup.runtimeTargetId)}',
    ..._launchSafetyRows(setup, codebases: codebases, targets: targets),
    if (setup.updatedAt.isNotEmpty) 'Updated: ${setup.updatedAt}',
  ];
}

/// Builds schedule rows for one Launch.
List<String> _launchScheduleRows(AutomationRunSetup setup) {
  final schedule = setup.schedule;
  if (!_launchHasSchedule(setup)) {
    return const <String>['Schedule: manual only'];
  }
  return <String>[
    'Schedule: ${_launchScheduleLabel(schedule)}',
    'Status: ${_launchScheduleEnabled(schedule) ? 'enabled' : 'paused'}',
    if (_stringFromMap(schedule, 'quiet_hours_start').isNotEmpty ||
        _stringFromMap(schedule, 'quiet_hours_end').isNotEmpty)
      'Quiet hours: ${_stringFromMap(schedule, 'quiet_hours_start')} - ${_stringFromMap(schedule, 'quiet_hours_end')}',
    if (_stringFromMap(schedule, 'stop_at').isNotEmpty)
      'Stop at: ${_stringFromMap(schedule, 'stop_at')}',
    if (_intFromMap(schedule, 'max_runs') > 0)
      'Max runs: ${_intFromMap(schedule, 'max_runs')}',
  ];
}

/// Builds policy rows for one Launch.
List<String> _launchSafetyRows(
  AutomationRunSetup setup, {
  required List<AutomationCodebase> codebases,
  required List<AutomationRuntimeTarget> targets,
}) {
  final policy = setup.policy;
  if (policy.isEmpty) {
    return const <String>[];
  }
  return <String>[
    if (_stringFromMap(policy, 'source_control').isNotEmpty)
      'Source control: ${_launchSourceControlPolicyLabel(_stringFromMap(policy, 'source_control'))}',
    if (_stringFromMap(policy, 'destructive_action').isNotEmpty)
      'Destructive actions: ${_launchDestructiveActionLabel(_stringFromMap(policy, 'destructive_action'))}',
    if (_stringListFromMap(policy, 'allowed_codebases').isNotEmpty)
      'Allowed codebases: ${_stringListFromMap(policy, 'allowed_codebases').map((codebaseId) => _codebaseLabel(codebases, codebaseId)).join(', ')}',
    if (_stringListFromMap(policy, 'allowed_targets').isNotEmpty)
      'Allowed targets: ${_stringListFromMap(policy, 'allowed_targets').map((targetId) => _targetLabel(targets, targetId)).join(', ')}',
    if (_intFromMap(policy, 'max_parallelism') > 0)
      'Max parallel runs: ${_intFromMap(policy, 'max_parallelism')}',
    if (_intFromMap(policy, 'retry_limit') > 0)
      'Retries: ${_intFromMap(policy, 'retry_limit')}',
  ];
}

/// Builds run rows for one Launch.
List<String> _launchRunRows(
  AutomationRunSetup setup,
  List<AutomationRun> runs, {
  required List<AutomationDefinition> definitions,
}) {
  final matching = runs
      .where((run) => run.definitionId == setup.definitionId)
      .toList();
  if (matching.isEmpty) {
    return const <String>['No runs for this Launch'];
  }
  return <String>[
    'Runs: ${matching.length}',
    for (final run in matching.take(8))
      '${_runDefinitionLabel(definitions, run)}: ${_draftStatusLabel(run.status)}${run.state.isEmpty ? '' : ' / ${run.state}'}',
  ];
}

/// Reports whether one Launch has a saved schedule.
bool _launchHasSchedule(AutomationRunSetup setup) {
  final schedule = setup.schedule;
  if (schedule.isEmpty) {
    return false;
  }
  return _launchScheduleEnabled(schedule) ||
      _stringFromMap(schedule, 'cron').isNotEmpty ||
      _stringFromMap(schedule, 'stop_at').isNotEmpty;
}

/// Reports whether one saved schedule is enabled.
bool _launchScheduleEnabled(Map<String, dynamic> schedule) {
  return schedule['enabled'] == true ||
      '${schedule['enabled'] ?? ''}'.trim().toLowerCase() == 'true';
}

/// Returns a product-facing schedule label.
String _launchScheduleLabel(Map<String, dynamic> schedule) {
  final cron = _stringFromMap(schedule, 'cron');
  if (cron.isEmpty) {
    return _launchScheduleEnabled(schedule) ? 'Enabled' : 'Manual only';
  }
  final parts = cron.split(RegExp(r'\s+'));
  if (parts.length == 5) {
    final minute = int.tryParse(parts[0]);
    final hour = int.tryParse(parts[1]);
    if (minute != null && hour != null) {
      final time =
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      if (parts[2] == '*' && parts[3] == '*' && parts[4] == '*') {
        return 'Daily at $time';
      }
      if (parts[2] == '*' && parts[3] == '*' && parts[4] != '*') {
        return 'Weekly at $time';
      }
    }
  }
  return 'Custom schedule';
}

/// Returns a product-facing destructive-action policy label.
String _launchDestructiveActionLabel(String value) {
  return switch (value.trim()) {
    'deny' => 'denied',
    'review' => 'Needs Review',
    'allow' => 'allowed',
    _ =>
      value.trim().isEmpty ? 'not configured' : _stateMachineDisplayName(value),
  };
}

/// Builds overview rows for one Computer or Server target.
List<String> _targetOverviewRows(
  AutomationRuntimeTarget target,
  AutomationTargetHealth? health,
  AutomationTargetSecretMetadata? secrets,
) {
  return <String>[
    'Selected: ${target.name}',
    'Kind: ${_targetKindLabel(target.kind)}',
    'Status: ${_targetStatusLabel(health?.status ?? target.status)}',
    'Capabilities: ${target.capabilities.length}',
    'Secret references: ${secrets?.count ?? target.secretRefCount}',
    'Active runs: ${health?.currentRunCount ?? target.currentRunCount}',
    if ((health?.hostname ?? target.hostname).isNotEmpty)
      'Computer: ${health?.hostname ?? target.hostname}',
    if ((health?.os ?? target.os).isNotEmpty)
      'System: ${health?.os ?? target.os}',
    if ((health?.version ?? target.version).isNotEmpty)
      'Version: ${health?.version ?? target.version}',
    if (target.lastSeenAt.isNotEmpty) 'Last seen: ${target.lastSeenAt}',
  ];
}

/// Builds health rows for one Computer or Server target.
List<String> _targetHealthRows(
  AutomationRuntimeTarget target,
  AutomationTargetHealth? health,
) {
  return <String>[
    'Status: ${_targetStatusLabel(health?.status ?? target.status)}',
    if ((health?.message ?? '').isNotEmpty) health!.message,
    'Active runs: ${health?.currentRunCount ?? target.currentRunCount}',
    if ((health?.hostname ?? target.hostname).isNotEmpty)
      'Computer: ${health?.hostname ?? target.hostname}',
    if ((health?.os ?? target.os).isNotEmpty)
      'System: ${health?.os ?? target.os}',
    if ((health?.version ?? target.version).isNotEmpty)
      'Version: ${health?.version ?? target.version}',
    if ((health?.checkedAt ?? '').isNotEmpty) 'Checked: ${health!.checkedAt}',
    if (target.lastSeenAt.isNotEmpty) 'Last seen: ${target.lastSeenAt}',
  ];
}

/// Builds capability rows for one Computer or Server target.
List<String> _targetCapabilityRows(
  AutomationRuntimeTarget target,
  List<AutomationCapability> capabilities,
) {
  final rows = <String>['Capabilities: ${target.capabilities.length}'];
  for (final capabilityId in target.capabilities.take(14)) {
    rows.add(_targetCapabilityLabel(capabilityId, capabilities));
  }
  if (target.capabilities.length > 14) {
    rows.add('More capabilities: ${target.capabilities.length - 14}');
  }
  return rows;
}

/// Builds secret reference rows for one Computer or Server target.
List<String> _targetSecretRows(
  AutomationRuntimeTarget target,
  AutomationTargetSecretMetadata? secrets,
) {
  return <String>[
    'Secret references: ${secrets?.count ?? target.secretRefCount}',
  ];
}

/// Builds launch routing rows for one Computer or Server target.
List<String> _targetLaunchRows(
  AutomationRuntimeTarget target,
  List<AutomationRunSetup> launchpad,
) {
  return <String>[
    'Saved Launchpad: ${launchpad.length}',
    'Active runs: ${target.currentRunCount}',
    if (target.allowedCodebaseIds.isNotEmpty)
      'Allowed codebases: ${target.allowedCodebaseIds.length}',
  ];
}

/// Builds editable-setting summary rows for one Computer or Server target.
List<String> _targetSettingsRows(
  AutomationRuntimeTarget target,
  List<AutomationCodebase> codebases,
) {
  return <String>[
    'Name: ${target.name}',
    'Kind: ${_targetKindLabel(target.kind)}',
    'Allowed codebases: ${_targetAllowedCodebaseLabels(target, codebases)}',
    'Secret references: ${target.secretRefCount}',
    if (target.updatedAt.isNotEmpty) 'Updated: ${target.updatedAt}',
  ];
}

/// Builds update metadata rows for one Computer or Server target.
List<String> _targetUpdateRows(
  AutomationRuntimeTarget target,
  AutomationTargetHealth? health,
) {
  return <String>[
    if ((health?.version ?? target.version).isNotEmpty)
      'Version: ${health?.version ?? target.version}',
    if ((health?.checkedAt ?? '').isNotEmpty) 'Checked: ${health!.checkedAt}',
    if (target.lastSeenAt.isNotEmpty) 'Last seen: ${target.lastSeenAt}',
    if (target.updatedAt.isNotEmpty) 'Updated: ${target.updatedAt}',
  ];
}

/// Returns display labels for codebases allowed on a target.
String _targetAllowedCodebaseLabels(
  AutomationRuntimeTarget target,
  List<AutomationCodebase> codebases,
) {
  if (target.allowedCodebaseIds.isEmpty) {
    return 'All configured codebases';
  }
  return target.allowedCodebaseIds
      .map((id) => _codebaseLabel(codebases, id))
      .join(', ');
}

/// Returns a display-safe capability label for a target inventory entry.
String _targetCapabilityLabel(
  String capabilityId,
  List<AutomationCapability> capabilities,
) {
  for (final capability in capabilities) {
    if (capability.id == capabilityId) {
      return capability.label.isEmpty ? capability.name : capability.label;
    }
  }
  final display = capabilityId.split(':').last.trim();
  return display.isEmpty
      ? 'Configured capability'
      : _stateMachineDisplayName(display);
}

class _AutomationTile extends StatelessWidget {
  const _AutomationTile({
    required this.title,
    required this.subtitle,
    this.badges = const <String>[],
    this.actions = const <Widget>[],
    this.selected = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final List<String> badges;
  final List<Widget> actions;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: PanelSurface(
          fillWidth: true,
          selected: selected,
          padding: const EdgeInsets.all(14),
          style: PanelSurfaceStyle.card,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, height: 1.35),
                      ),
                    ],
                    if (badges.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          for (final badge in badges.where(
                            (badge) => badge.isNotEmpty,
                          ))
                            PanelBadge(label: badge),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8),
                Wrap(spacing: 6, runSpacing: 6, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Returns saved Launchpad matching the left-pane text filter.
List<AutomationRunSetup> _filterRunSetups(
  List<AutomationRunSetup> setups,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return setups;
  }
  return setups.where((setup) {
    return setup.name.toLowerCase().contains(needle) ||
        setup.description.toLowerCase().contains(needle) ||
        setup.definitionId.toLowerCase().contains(needle) ||
        setup.codebaseId.toLowerCase().contains(needle) ||
        setup.runtimeTargetId.toLowerCase().contains(needle);
  }).toList();
}

/// Returns Launchpad scoped to the selected runbook file when one exists.
List<AutomationRunSetup> _launchSetupsForDefinition(
  List<AutomationRunSetup> setups,
  AutomationDefinition? definition,
) {
  if (definition == null) {
    return setups;
  }
  return setups.where((setup) => setup.definitionId == definition.id).toList();
}

/// Returns runs scoped to the selected runbook file when one exists.
List<AutomationRun> _launchRunsForDefinition(
  List<AutomationRun> runs,
  AutomationDefinition? definition,
) {
  if (definition == null) {
    return runs;
  }
  return runs.where((run) => run.definitionId == definition.id).toList();
}

/// Returns the selected Launch when it is in a visible scoped list.
AutomationRunSetup? _selectedLaunchSetupFrom(
  List<AutomationRunSetup> setups,
  AutomationRunSetup? selectedSetup,
) {
  if (selectedSetup != null) {
    for (final setup in setups) {
      if (setup.id == selectedSetup.id) {
        return setup;
      }
    }
  }
  return setups.isEmpty ? null : setups.first;
}

/// Returns the selected run when it is in a visible scoped list.
AutomationRun? _selectedAutomationRunFrom(
  List<AutomationRun> runs,
  AutomationRun? selectedRun,
) {
  if (selectedRun != null) {
    for (final run in runs) {
      if (run.id == selectedRun.id) {
        return run;
      }
    }
  }
  return runs.isEmpty ? null : runs.first;
}

List<AutomationDraft> _filterDrafts(
  List<AutomationDraft> drafts,
  String query,
) {
  final needle = query.toLowerCase();
  return drafts.where((draft) {
    final body = _map(draft.body);
    return draft.name.toLowerCase().contains(needle) ||
        draft.description.toLowerCase().contains(needle) ||
        '${body['name'] ?? ''}'.toLowerCase().contains(needle) ||
        _draftKindLabel(draft.kind).toLowerCase().contains(needle) ||
        _draftStatusLabel(draft.status).toLowerCase().contains(needle);
  }).toList();
}

/// Keeps the selected draft visible when a text filter would hide it.
List<AutomationDraft> _draftsWithSelected(
  List<AutomationDraft> drafts,
  AutomationDraft? selected,
) {
  if (selected == null || drafts.any((draft) => draft.id == selected.id)) {
    return drafts;
  }
  return <AutomationDraft>[selected, ...drafts];
}

/// Returns a non-colliding display name for a new runbook draft.
String _nextRunbookDraftName(List<AutomationDraft> drafts) {
  const base = 'New Runbook';
  final names = drafts.map((draft) => draft.name.trim()).toSet();
  if (!names.contains(base)) {
    return base;
  }
  var suffix = 2;
  while (names.contains('$base $suffix')) {
    suffix++;
  }
  return '$base $suffix';
}

List<AutomationRuntimeTarget> _filterRuntimeTargets(
  List<AutomationRuntimeTarget> targets,
  String query,
) {
  final needle = query.toLowerCase();
  return targets.where((target) {
    return target.name.toLowerCase().contains(needle) ||
        target.hostname.toLowerCase().contains(needle) ||
        target.os.toLowerCase().contains(needle) ||
        _targetKindLabel(target.kind).toLowerCase().contains(needle) ||
        _targetStatusLabel(target.status).toLowerCase().contains(needle);
  }).toList();
}

/// Returns one string field from a decoded map.
String _stringFromMap(Map<String, dynamic> values, String key) {
  final value = values[key];
  if (value == null) {
    return '';
  }
  return '$value'.trim();
}

/// Reads a display-safe string list from a JSON-like map.
List<String> _stringListFromMap(Map<String, dynamic> values, String key) {
  final value = values[key];
  if (value is List) {
    return <String>[
      for (final item in value)
        if ('$item'.trim().isNotEmpty) '$item'.trim(),
    ];
  }
  final single = '$value'.trim();
  return single.isEmpty ? const <String>[] : <String>[single];
}

/// Reads an integer from a JSON-like map.
int _intFromMap(Map<String, dynamic> values, String key) {
  final value = values[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('$value'.trim()) ?? 0;
}

/// Builds artifact rows from runbook run output.
List<_LaunchArtifactItem> _launchArtifactsForRuns(
  List<AutomationRun> runs, {
  required List<AutomationDefinition> definitions,
}) {
  final artifacts = <_LaunchArtifactItem>[];
  for (final run in runs) {
    final runbookLabel = _runDefinitionLabel(definitions, run);
    artifacts.addAll(_launchArtifactsForRun(run, runbookLabel: runbookLabel));
  }
  return artifacts;
}

/// Builds artifact rows from one runbook run output.
List<_LaunchArtifactItem> _launchArtifactsForRun(
  AutomationRun run, {
  required String runbookLabel,
}) {
  final output = run.output;
  final artifacts = <_LaunchArtifactItem>[];
  void addArtifact(String title, Object? value) {
    final text = _displayDynamicValue(value).trim();
    if (text.isEmpty) {
      return;
    }
    artifacts.add(
      _LaunchArtifactItem(
        run: run,
        title: title,
        subtitle: text,
        runbookLabel: runbookLabel,
      ),
    );
  }

  addArtifact('Pull request', output['pull_request_url'] ?? output['pr_url']);
  addArtifact('Branch', output['branch_url']);
  addArtifact('Commit', output['commit_url']);
  addArtifact('Report', output['report_url']);
  final artifactList = output['artifacts'];
  if (artifactList is List) {
    for (final item in artifactList) {
      if (item is Map) {
        final map = _map(item);
        addArtifact(
          _stateMachineDisplayName(
            '${map['type'] ?? map['name'] ?? 'artifact'}',
          ),
          map['url'] ?? map['path'] ?? map['name'],
        );
      } else {
        addArtifact('Artifact', item);
      }
    }
  }
  final files = output['files'];
  if (files is List) {
    for (final file in files) {
      addArtifact('File', file);
    }
  }
  return artifacts;
}

List<AutomationPendingItem> _filterPendingItems(
  List<AutomationPendingItem> items,
  String query,
) {
  final needle = query.toLowerCase();
  return items.where((item) {
    return item.prompt.toLowerCase().contains(needle) ||
        _draftStatusLabel(item.status).toLowerCase().contains(needle);
  }).toList();
}

/// Returns the automation draft kind edited by a left command area.
String? _automationDraftKindForArea(String areaId) {
  if (areaId == _automationRunbookAreaDrafts ||
      areaId == _automationRunbookAreaActions) {
    return automationRunbookKind;
  }
  return null;
}

/// Reports whether a draft belongs in the requested authoring section.
bool _draftMatchesSectionKind(AutomationDraft draft, String kind) {
  if (kind == automationRunbookKind) {
    return _isRunbookFileKind(draft.kind);
  }
  return draft.kind == kind;
}

/// Reports whether a draft kind is a runbook file in the Automations UI.
bool _isRunbookFileKind(String kind) {
  final normalized = kind.trim();
  return normalized == automationRunbookKind ||
      normalized == _stateMachineBodyKind;
}

/// Returns the selected draft for one builder kind.
AutomationDraft? _selectedAutomationDraftForKind(
  AgentAwesomeAppController controller,
  String kind,
) {
  final drafts = controller.automationDrafts
      .where((draft) => _draftMatchesSectionKind(draft, kind))
      .toList();
  if (drafts.isEmpty) {
    return null;
  }
  for (final draft in drafts) {
    if (draft.id == controller.selectedAutomationDraftId) {
      return draft;
    }
  }
  return drafts.first;
}

/// Returns the icon for one automation action type.
IconData _actionIcon(String actionName) {
  return switch (actionName) {
    'tool.call' => Icons.extension_outlined,
    'mcp.call' => Icons.extension_outlined,
    'command.execute' => Icons.terminal_outlined,
    'data.assert' => Icons.rule_outlined,
    'data.defaults' => Icons.tune_outlined,
    'human.request' => Icons.how_to_reg_outlined,
    'delay.until' => Icons.schedule_outlined,
    'runbook.run' => Icons.account_tree_outlined,
    'runbook.signal' => Icons.flag_outlined,
    _ => Icons.bolt_outlined,
  };
}

/// Returns the friendly label for a built-in action.
String _fallbackActionLabel(String actionName) {
  return switch (actionName) {
    'tool.call' => 'Run Tool',
    'mcp.call' => 'Call MCP Tool',
    'command.execute' => 'Run Command',
    'data.assert' => 'Assert Data',
    'data.defaults' => 'Apply Defaults',
    'human.request' => 'Prompt',
    'delay.until' => 'Delay',
    'runbook.run' => 'Run Runbook',
    'runbook.signal' => 'Signal',
    _ => actionName,
  };
}

/// Returns a short built-in action description for palette display.
String _fallbackActionDescription(String actionName) {
  return switch (actionName) {
    'tool.call' => 'Harness-exposed tool call',
    'mcp.call' => 'External MCP tool call',
    'command.execute' => 'Configured command template',
    'data.assert' => 'Deterministic data check',
    'data.defaults' => 'Declarative input defaults',
    'human.request' => 'Human approval or input',
    'delay.until' => 'Timed wait',
    'runbook.run' => 'Nested runbook run',
    'runbook.signal' => 'Runbook signal',
    _ => 'Runbook action',
  };
}

/// Returns the visual accent color for one runbook action type.
Color _actionColor(BuildContext context, String actionName) {
  final colors = context.agentAwesomeColors;
  return switch (actionName) {
    'tool.call' => colors.cardIcon,
    'mcp.call' => colors.cardIcon,
    'command.execute' => colors.cardIcon,
    'data.assert' => colors.green,
    'data.defaults' => colors.green,
    'human.request' => colors.green,
    'delay.until' => colors.muted,
    'runbook.run' => colors.orbit,
    'runbook.signal' => colors.warningText,
    _ => colors.green,
  };
}

/// Returns pretty JSON object text for editing.
String _jsonText(Map<String, dynamic> value) {
  if (value.isEmpty) {
    return '{}';
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return const <String, dynamic>{};
}

List<dynamic> _list(dynamic value) {
  if (value is List) {
    return value;
  }
  return const <dynamic>[];
}
