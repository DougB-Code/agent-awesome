/// Renders root-level Automations operations and builder surfaces.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../domain/automation_contracts.dart';
import '../domain/models_automation.dart';
import 'panels/panels.dart';
import 'theme.dart';

part 'automations_state_machine_builder.dart';

const String _automationPanelOperations = 'operations';
const String _automationPanelWorkflows = 'workflows';
const String _automationPanelTasks = 'tasks';
const String _automationOperationsAreaInbox = 'operations_inbox';
const String _automationOperationsAreaPublished = 'operations_published';
const String _automationOperationsAreaSetups = 'operations_saved';
const String _automationOperationsAreaRuns = 'operations_runs';
const String _automationOperationsAreaCodebases = 'operations_codebases';
const String _automationOperationsAreaTargets = 'operations_targets';
const String _automationOperationsAreaSchedules = 'operations_schedules';
const String _automationOperationsAreaArtifacts = 'operations_artifacts';
const String _automationWorkflowAreaDrafts = 'workflow_drafts';
const String _automationWorkflowAreaActions = 'workflow_actions';
const String _automationWorkflowAreaCapabilities = 'workflow_capabilities';
const String _automationTaskAreaDrafts = 'task_drafts';
const String _automationTaskAreaNodes = 'task_nodes';

const String _automationDetailOverview = 'overview';
const String _automationDetailSetup = 'setup';
const String _automationDetailInputs = 'inputs';
const String _automationDetailTargets = 'targets';
const String _automationDetailSchedule = 'schedule';
const String _automationDetailBuilder = 'builder';
const String _automationDetailInspect = 'inspect';
const String _automationDetailSteps = 'steps';
const String _automationDetailMap = 'map';
const String _automationDetailHistory = 'history';
const String _automationDetailSafety = 'safety';
const String _automationDetailTest = 'test';
const String _automationTargetDetailCapabilities = 'target_capabilities';
const String _automationTargetDetailSecrets = 'target_secrets';
const String _automationTargetDetailOperations = 'target_operations';
const String _automationTargetDetailLogs = 'target_logs';
const String _automationTargetDetailSettings = 'target_settings';
const String _automationTargetDetailUpdates = 'target_updates';
const String _stateMachineBodyKind = 'state_machine';
const String _operationSafetyOpenPROnly = 'open_pr_only';

const List<String> _operationSourceControlTools = <String>[
  'sourcecontrol.prepare_worktree',
  'sourcecontrol.status',
  'sourcecontrol.commit',
  'sourcecontrol.push',
  'sourcecontrol.open_pull_request',
];

const Map<String, String> _operationSafetyLabels = <String, String>{
  _operationSafetyOpenPROnly: 'Open PR only',
};

const Set<String> _taskGraphActionNames = <String>{
  'mcp.call',
  'tool.call',
  'command.execute',
  'data.assert',
  'data.defaults',
  'workflow.run',
};

/// AutomationOperationsCommandPanel runs and observes published workflows.
class AutomationOperationsCommandPanel extends StatelessWidget {
  /// Creates an operations panel bound to app state.
  const AutomationOperationsCommandPanel({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Reports active area changes to the root shell command context.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the operations command panel.
  @override
  Widget build(BuildContext context) {
    return _AutomationFocusedCommandPanel(
      controller: controller,
      panelId: _automationPanelOperations,
      title: 'Operations',
      detailTitle: 'Operations',
      icon: Icons.monitor_heart_outlined,
      filterHint: 'Filter operations and runs...',
      detailModes: _detailModesForPanel(_automationPanelOperations),
      split: const PanelSplit(left: 0.30, min: 0.22, max: 0.56),
      onAreaChanged: onAreaChanged,
    );
  }
}

/// AutomationWorkflowsCommandPanel authors long-lived state-machine workflows.
class AutomationWorkflowsCommandPanel extends StatelessWidget {
  /// Creates a workflow authoring panel bound to app state.
  const AutomationWorkflowsCommandPanel({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Reports active area changes to the root shell command context.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the workflow authoring command panel.
  @override
  Widget build(BuildContext context) {
    return _AutomationFocusedCommandPanel(
      controller: controller,
      panelId: _automationPanelWorkflows,
      title: 'Workflows',
      detailTitle: 'Workflow',
      icon: Icons.route_outlined,
      filterHint: 'Filter workflows...',
      detailModes: _detailModesForPanel(_automationPanelWorkflows),
      onAreaChanged: onAreaChanged,
    );
  }
}

/// AutomationTasksCommandPanel authors bounded task-graph automations.
class AutomationTasksCommandPanel extends StatelessWidget {
  /// Creates a task-graph authoring panel bound to app state.
  const AutomationTasksCommandPanel({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Reports active area changes to the root shell command context.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the task-graph command panel.
  @override
  Widget build(BuildContext context) {
    return _AutomationFocusedCommandPanel(
      controller: controller,
      panelId: _automationPanelTasks,
      title: 'Tasks',
      detailTitle: 'Task Graph',
      icon: Icons.account_tree_outlined,
      filterHint: 'Filter tasks or nodes...',
      detailModes: _detailModesForPanel(_automationPanelTasks),
      split: const PanelSplit(left: 0.25, min: 0.12, max: 0.9),
      onAreaChanged: onAreaChanged,
    );
  }
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
  late final _TaskGraphActionIntentController _taskGraphActionIntents;
  late final _StateMachineDraftEditController _stateMachineEditor;
  String _detailModeId = _automationDetailOverview;
  String _requestedAreaId = '';

  /// Triggers the first data load after the focused panel is attached.
  @override
  void initState() {
    super.initState();
    _taskGraphActionIntents = _TaskGraphActionIntentController();
    _stateMachineEditor = _StateMachineDraftEditController(
      controller: widget.controller,
    );
    if (widget.panelId == _automationPanelWorkflows ||
        widget.panelId == _automationPanelTasks) {
      _detailModeId = _automationDetailBuilder;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasPanelData() && !widget.controller.automationsBusy) {
        unawaited(widget.controller.refreshAutomationsFromUi());
      }
    });
  }

  /// Releases command-panel intent controllers.
  @override
  void dispose() {
    _taskGraphActionIntents.dispose();
    _stateMachineEditor.dispose();
    super.dispose();
  }

  /// Reports whether the current panel already has its local collection data.
  bool _hasPanelData() {
    return switch (widget.panelId) {
      _automationPanelOperations =>
        widget.controller.automationDefinitions.isNotEmpty ||
            widget.controller.automationRunSetups.isNotEmpty ||
            widget.controller.automationRuns.isNotEmpty ||
            widget.controller.automationCodebases.isNotEmpty ||
            widget.controller.automationRuntimeTargets.isNotEmpty ||
            widget.controller.automationInbox.isNotEmpty,
      _automationPanelWorkflows =>
        widget.controller.automationDrafts.any(
              (draft) => _isWorkflowFileKind(draft.kind),
            ) ||
            widget.controller.automationCapabilities.isNotEmpty,
      _automationPanelTasks => widget.controller.automationDrafts.any(
        (draft) => draft.kind == automationTaskGraphKind,
      ),
      _ => true,
    };
  }

  /// Builds one focused Automations command panel.
  @override
  Widget build(BuildContext context) {
    final modes = widget.detailModes;
    final selectedMode = modes.any((mode) => mode.id == _detailModeId)
        ? _detailModeId
        : modes.first.id;
    final areas = _commandAreas();
    final shell = CommandPanelSubShell(
      areas: areas,
      detailTitle: widget.detailTitle,
      detailModes: modes,
      detailTabsBuilder: (area, mode) =>
          _detailTabsForMode(widget.panelId, mode.id),
      selectedDetailModeId: selectedMode,
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
      areaTabbedDetailBuilder: (area, modeId, tabId) =>
          _AutomationDetailContent(
            controller: widget.controller,
            stateMachineEditor: _stateMachineEditor,
            areaId: area.id,
            modeId: modeId,
            tabId: tabId,
            onDetailModeRequested: _selectDetailMode,
          ),
      onAreaChanged: _handleAreaChanged,
      areaActionsBuilder: (context, area) {
        if (widget.panelId != _automationPanelWorkflows &&
            widget.panelId != _automationPanelTasks) {
          return null;
        }
        return _AutomationPanelActions(
          controller: widget.controller,
          panelId: widget.panelId,
          areaId: area.id,
          onCreateWorkflow: _createWorkflowDraft,
          onCreateTaskGraph: _createTaskGraphDraft,
        );
      },
      detailModesBuilder: _detailModesForArea,
      companionAreaIdBuilder: _companionAreaForDetailMode,
      detailActionsBuilder: (context, area, mode) {
        return _AutomationDetailActions(
          controller: widget.controller,
          panelId: widget.panelId,
          areaId: area.id,
        );
      },
      filterHint: widget.filterHint,
      areaFilterHintBuilder: _filterHintForArea,
      selectedAreaId: _requestedAreaId,
      split: _splitForArea(areas),
    );
    if (widget.panelId != _automationPanelWorkflows &&
        widget.panelId != _automationPanelTasks) {
      return shell;
    }
    return _TaskGraphActionIntentScope(
      notifier: _taskGraphActionIntents,
      child: shell,
    );
  }

  /// Creates a workflow draft and reveals it in the Files collection.
  Future<void> _createWorkflowDraft() async {
    setState(() => _requestedAreaId = _automationWorkflowAreaDrafts);
    await widget.controller.createAutomationDraftFromUi(
      kind: automationWorkflowKind,
      name: 'New Workflow',
    );
    if (!mounted) {
      return;
    }
    setState(() => _requestedAreaId = _automationWorkflowAreaDrafts);
  }

  /// Creates a task graph draft and reveals it in the task draft collection.
  Future<void> _createTaskGraphDraft() async {
    setState(() => _requestedAreaId = _automationTaskAreaDrafts);
    await widget.controller.createAutomationDraftFromUi(
      kind: automationTaskGraphKind,
      name: 'New Task Graph',
    );
    if (!mounted) {
      return;
    }
    setState(() => _requestedAreaId = _automationTaskAreaDrafts);
  }

  /// Reports area changes and clears one-shot area requests after manual moves.
  void _handleAreaChanged(SwitcherPanelArea area) {
    if (_requestedAreaId.isNotEmpty && area.id != _requestedAreaId) {
      setState(() => _requestedAreaId = '');
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
    if (widget.panelId == _automationPanelOperations) {
      return <SwitcherPanelArea>[
        SwitcherPanelArea(
          id: _automationOperationsAreaInbox,
          title: 'Inbox',
          icon: Icons.inbox_outlined,
          builder: (query) => _AutomationInboxContent(
            controller: widget.controller,
            query: query,
          ),
        ),
        SwitcherPanelArea(
          id: _automationOperationsAreaPublished,
          title: 'Files',
          icon: Icons.folder_outlined,
          builder: (query) => _AutomationPublishedContent(
            controller: widget.controller,
            query: query,
          ),
        ),
        SwitcherPanelArea(
          id: _automationOperationsAreaSetups,
          title: 'Operations',
          icon: Icons.playlist_play_outlined,
          builder: (query) => _AutomationRunSetupsContent(
            controller: widget.controller,
            query: query,
          ),
        ),
        SwitcherPanelArea(
          id: _automationOperationsAreaCodebases,
          title: 'Codebases',
          icon: Icons.account_tree_outlined,
          builder: (query) => _AutomationCodebasesContent(
            controller: widget.controller,
            query: query,
          ),
        ),
        SwitcherPanelArea(
          id: _automationOperationsAreaTargets,
          title: 'Computers',
          icon: Icons.devices_other_outlined,
          builder: (query) => _AutomationRuntimeTargetsContent(
            controller: widget.controller,
            query: query,
          ),
        ),
        SwitcherPanelArea(
          id: _automationOperationsAreaSchedules,
          title: 'Schedules',
          icon: Icons.event_outlined,
          builder: (query) => _AutomationSchedulesContent(
            controller: widget.controller,
            query: query,
          ),
        ),
        SwitcherPanelArea(
          id: _automationOperationsAreaArtifacts,
          title: 'Artifacts',
          icon: Icons.inventory_2_outlined,
          builder: (query) => _AutomationArtifactsContent(
            controller: widget.controller,
            query: query,
          ),
        ),
        SwitcherPanelArea(
          id: _automationOperationsAreaRuns,
          title: 'Runs',
          icon: Icons.history_outlined,
          builder: (query) => _AutomationRunsContent(
            controller: widget.controller,
            query: query,
          ),
        ),
      ];
    }
    if (widget.panelId == _automationPanelWorkflows) {
      return <SwitcherPanelArea>[
        SwitcherPanelArea(
          id: _automationWorkflowAreaDrafts,
          title: 'Files',
          icon: Icons.folder_outlined,
          builder: (query) => _AutomationDraftsContent(
            controller: widget.controller,
            query: query,
            kind: automationWorkflowKind,
            emptyLabel: 'No workflow files',
          ),
        ),
        SwitcherPanelArea(
          id: _automationWorkflowAreaActions,
          title: 'Actions',
          icon: Icons.extension_outlined,
          builder: (query) => _AutomationWorkflowStatePaletteContent(
            controller: widget.controller,
            query: query,
          ),
        ),
        SwitcherPanelArea(
          id: _automationWorkflowAreaCapabilities,
          title: 'Capabilities',
          icon: Icons.science_outlined,
          builder: (query) => _AutomationCapabilitiesContent(
            controller: widget.controller,
            query: query,
          ),
        ),
      ];
    }
    if (widget.panelId == _automationPanelTasks) {
      return <SwitcherPanelArea>[
        SwitcherPanelArea(
          id: _automationTaskAreaDrafts,
          title: 'Files',
          icon: Icons.folder_outlined,
          builder: (query) => _AutomationDraftsContent(
            controller: widget.controller,
            query: query,
            kind: automationTaskGraphKind,
            emptyLabel: 'No task graph files',
          ),
        ),
        SwitcherPanelArea(
          id: _automationTaskAreaNodes,
          title: 'Nodes',
          icon: Icons.hub_outlined,
          builder: (query) => _AutomationTaskNodePaletteContent(
            controller: widget.controller,
            query: query,
          ),
        ),
      ];
    }
    if (widget.panelId != _automationPanelTasks) {
      return <SwitcherPanelArea>[
        SwitcherPanelArea(
          id: widget.panelId,
          title: widget.title,
          icon: widget.icon,
          builder: (_) => const SizedBox.shrink(),
        ),
      ];
    }
    return const <SwitcherPanelArea>[];
  }

  /// Returns area-specific right work modes where supporting areas need less UI.
  List<CommandPanelDetailMode> _detailModesForArea(SwitcherPanelArea area) {
    if (area.id == _automationWorkflowAreaCapabilities) {
      return const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _automationDetailOverview,
          label: 'Overview',
          icon: Icons.info_outline,
        ),
        CommandPanelDetailMode(
          id: _automationDetailSafety,
          label: 'Safety',
          icon: Icons.verified_user_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailTest,
          label: 'Test',
          icon: Icons.play_circle_outline,
        ),
      ];
    }
    if (area.id == _automationOperationsAreaTargets) {
      return const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _automationDetailOverview,
          label: 'Overview',
          icon: Icons.info_outline,
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
          id: _automationTargetDetailOperations,
          label: 'Operations',
          icon: Icons.playlist_play_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationTargetDetailLogs,
          label: 'Logs',
          icon: Icons.article_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationTargetDetailSettings,
          label: 'Settings',
          icon: Icons.tune_outlined,
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
      ];
    }
    return widget.detailModes;
  }

  /// Returns area-specific filter copy for the active command catalog.
  String _filterHintForArea(SwitcherPanelArea area) {
    return switch (area.id) {
      _automationWorkflowAreaDrafts ||
      _automationTaskAreaDrafts => 'Filter files...',
      _automationWorkflowAreaActions => 'Filter actions...',
      _automationWorkflowAreaCapabilities => 'Filter capabilities...',
      _automationOperationsAreaTargets => 'Filter computers...',
      _automationOperationsAreaSchedules => 'Filter schedules...',
      _automationOperationsAreaArtifacts => 'Filter artifacts...',
      _automationTaskAreaNodes => 'Filter nodes...',
      _ => widget.filterHint,
    };
  }

  /// Returns the left-pane companion area for right-side builder modes.
  String _companionAreaForDetailMode(String modeId) {
    if (modeId != _automationDetailBuilder) {
      return '';
    }
    return switch (widget.panelId) {
      _automationPanelWorkflows => _automationWorkflowAreaActions,
      _automationPanelTasks => _automationTaskAreaNodes,
      _ => '',
    };
  }

  /// Returns an area-aware split so builder palettes do not crowd the canvas.
  PanelSplit _splitForArea(List<SwitcherPanelArea> areas) {
    if (widget.panelId == _automationPanelWorkflows) {
      return const PanelSplit(left: 0.30, min: 0.16, max: 0.42);
    }
    if (widget.panelId == _automationPanelTasks) {
      return const PanelSplit(left: 0.24, min: 0.16, max: 0.42);
    }
    return widget.split;
  }
}

class _TaskGraphActionIntentController extends ChangeNotifier {
  String _actionName = '';
  int _revision = 0;

  String get actionName => _actionName;
  int get revision => _revision;

  /// Publishes one left-panel action request to the active graph editor.
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

class _TaskGraphActionIntentScope
    extends InheritedNotifier<_TaskGraphActionIntentController> {
  const _TaskGraphActionIntentScope({
    required super.notifier,
    required super.child,
  });

  /// Finds the current action intent publisher for graph-builder screens.
  static _TaskGraphActionIntentController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_TaskGraphActionIntentScope>()
        ?.notifier;
  }
}

class _AutomationPanelActions extends StatelessWidget {
  const _AutomationPanelActions({
    required this.controller,
    required this.panelId,
    required this.areaId,
    required this.onCreateWorkflow,
    required this.onCreateTaskGraph,
  });

  final AgentAwesomeAppController controller;
  final String panelId;
  final String areaId;
  final Future<void> Function() onCreateWorkflow;
  final Future<void> Function() onCreateTaskGraph;

  /// Builds common and section-specific Automations header actions.
  @override
  Widget build(BuildContext context) {
    if (areaId == _automationWorkflowAreaActions ||
        areaId == _automationWorkflowAreaCapabilities ||
        areaId == _automationTaskAreaNodes) {
      return const SizedBox.shrink();
    }
    if (panelId == _automationPanelWorkflows ||
        areaId == _automationWorkflowAreaDrafts) {
      return PanelCreateButton(
        key: const ValueKey<String>('automation-new-workflow-draft-button'),
        tooltip: 'New workflow draft',
        onPressed: controller.automationsBusy
            ? null
            : () => unawaited(onCreateWorkflow()),
      );
    }
    if (panelId == _automationPanelTasks ||
        areaId == _automationTaskAreaDrafts) {
      return PanelCreateButton(
        key: const ValueKey<String>('automation-new-task-graph-button'),
        tooltip: 'New task graph',
        onPressed: controller.automationsBusy
            ? null
            : () => unawaited(onCreateTaskGraph()),
      );
    }
    return const SizedBox.shrink();
  }
}

class _AutomationDetailActions extends StatelessWidget {
  const _AutomationDetailActions({
    required this.controller,
    required this.panelId,
    required this.areaId,
  });

  final AgentAwesomeAppController controller;
  final String panelId;
  final String areaId;

  /// Builds selected-object controls for the Automations detail panel.
  @override
  Widget build(BuildContext context) {
    if (panelId == _automationPanelOperations) {
      return _OperationsSelectedActions(controller: controller, areaId: areaId);
    }
    if (areaId == _automationWorkflowAreaCapabilities) {
      return const SizedBox.shrink();
    }
    final kind = _automationDraftKindForArea(areaId);
    if (kind != null ||
        panelId == _automationPanelWorkflows ||
        panelId == _automationPanelTasks) {
      final effectiveKind =
          kind ??
          (panelId == _automationPanelTasks
              ? automationTaskGraphKind
              : automationWorkflowKind);
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
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class _OperationsSelectedActions extends StatelessWidget {
  const _OperationsSelectedActions({
    required this.controller,
    required this.areaId,
  });

  final AgentAwesomeAppController controller;
  final String areaId;

  /// Builds selected-object actions for the active Operations collection.
  @override
  Widget build(BuildContext context) {
    if (areaId == _automationOperationsAreaInbox) {
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
    if (areaId == _automationOperationsAreaPublished) {
      final definition = controller.selectedAutomationDefinition;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelIconButton(
            key: const ValueKey<String>('automation-create-run-setup-button'),
            icon: Icons.tune_outlined,
            tooltip: 'Create Operation',
            onPressed: controller.automationsBusy || definition == null
                ? null
                : () => unawaited(
                    _showCreateRunSetupDialog(context, controller, definition),
                  ),
          ),
          const SizedBox(width: 8),
          PanelIconButton(
            key: const ValueKey<String>('automation-start-run-button'),
            icon: Icons.play_arrow,
            tooltip: 'Start selected automation',
            onPressed: controller.automationsBusy || definition == null
                ? null
                : () => unawaited(
                    _showStartAutomationRunDialog(
                      context,
                      controller,
                      definition,
                    ),
                  ),
          ),
        ],
      );
    }
    if (areaId == _automationOperationsAreaSetups) {
      final setup = controller.selectedAutomationRunSetup;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelIconButton(
            key: const ValueKey<String>('automation-preview-run-setup-button'),
            icon: Icons.science_outlined,
            tooltip: 'Test Run',
            onPressed: controller.automationsBusy || setup == null
                ? null
                : () => unawaited(
                    controller.previewAutomationRunSetupFromUi(setup),
                  ),
          ),
          const SizedBox(width: 8),
          PanelIconButton(
            key: const ValueKey<String>('automation-start-run-setup-button'),
            icon: Icons.play_arrow,
            tooltip: 'Run selected Operation',
            onPressed: controller.automationsBusy || setup == null
                ? null
                : () => unawaited(
                    _showStartAutomationRunSetupDialog(
                      context,
                      controller,
                      setup,
                    ),
                  ),
          ),
        ],
      );
    }
    if (areaId == _automationOperationsAreaCodebases) {
      return PanelIconButton(
        key: const ValueKey<String>('automation-create-codebase-button'),
        icon: Icons.add,
        tooltip: 'Create Codebase',
        onPressed: controller.automationsBusy
            ? null
            : () => unawaited(_showCreateCodebaseDialog(context, controller)),
      );
    }
    return const SizedBox.shrink();
  }
}

/// _showCreateCodebaseDialog collects typed fields for a new codebase.
Future<void> _showCreateCodebaseDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
) async {
  final codebase = await showDialog<AutomationCodebase>(
    context: context,
    builder: (context) => const _CreateCodebaseDialog(),
  );
  if (codebase == null) {
    return;
  }
  await controller.upsertAutomationCodebaseFromUi(codebase);
}

class _CreateCodebaseDialog extends StatefulWidget {
  /// Creates a typed codebase creation dialog.
  const _CreateCodebaseDialog();

  @override
  State<_CreateCodebaseDialog> createState() => _CreateCodebaseDialogState();
}

class _CreateCodebaseDialogState extends State<_CreateCodebaseDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _files = TextEditingController();
  final TextEditingController _aliases = TextEditingController();
  final TextEditingController _defaultRemote = TextEditingController(
    text: 'origin',
  );
  final TextEditingController _defaultBranch = TextEditingController(
    text: 'main',
  );
  final TextEditingController _provider = TextEditingController(text: 'local');
  final TextEditingController _providerRepository = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _files.dispose();
    _aliases.dispose();
    _defaultRemote.dispose();
    _defaultBranch.dispose();
    _provider.dispose();
    _providerRepository.dispose();
    super.dispose();
  }

  /// Builds the codebase creation dialog.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return AlertDialog(
      title: const Text('Create Codebase'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _AutomationTextField(
                key: const ValueKey<String>('automation-codebase-name'),
                controller: _name,
                label: 'Name *',
              ),
              const SizedBox(height: 12),
              _AutomationTextField(
                key: const ValueKey<String>('automation-codebase-files'),
                controller: _files,
                label: 'Files *',
              ),
              const SizedBox(height: 12),
              _AutomationTextField(controller: _aliases, label: 'Aliases'),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _AutomationTextField(
                      controller: _defaultRemote,
                      label: 'Default Remote',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AutomationTextField(
                      controller: _defaultBranch,
                      label: 'Default Branch',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _AutomationTextField(
                      controller: _provider,
                      label: 'Provider',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AutomationTextField(
                      controller: _providerRepository,
                      label: 'Repository',
                    ),
                  ),
                ],
              ),
              if (_error.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error,
                    style: TextStyle(color: colors.coral, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('automation-codebase-create-button'),
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }

  /// Validates typed input and returns a codebase payload.
  void _submit() {
    final name = _name.text.trim();
    final files = _files.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (files.isEmpty) {
      setState(() => _error = 'Files is required.');
      return;
    }
    Navigator.of(context).pop(
      AutomationCodebase(
        id: _stableCodebaseId(name),
        name: name,
        aliases: _splitCodebaseAliases(_aliases.text),
        repositoryPath: files,
        defaultRemote: _defaultRemote.text.trim(),
        defaultBranch: _defaultBranch.text.trim(),
        provider: _provider.text.trim(),
        providerRepository: _providerRepository.text.trim(),
      ),
    );
  }
}

/// _showStartAutomationRunDialog collects typed workflow inputs before a run starts.
Future<void> _showStartAutomationRunDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  AutomationDefinition definition,
) async {
  final seedInput = _workflowRunAuthoringDefaults(controller, definition);
  final input = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => _StartAutomationRunDialog(
      title: 'Run ${definition.name}',
      definition: definition,
      seedInput: seedInput,
      includeSeedInput: true,
      onlyMissingRequired: true,
    ),
  );
  if (input == null) {
    return;
  }
  await controller.startAutomationDefinitionFromUi(definition, input: input);
}

/// _showStartAutomationRunSetupDialog collects run-specific Operation input.
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
    ..._workflowRunAuthoringDefaults(controller, definition),
    ...setup.input,
  };
  final runFields = setup.definitionId == 'professional_coding_change'
      ? <String>{'change_request'}
      : _workflowRunSetupRunFields(definition.body);
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
}

/// _showCreateRunSetupDialog stores a saved Operation for later runs.
Future<void> _showCreateRunSetupDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  AutomationDefinition definition,
) async {
  final result = await showDialog<_RunSetupDialogResult>(
    context: context,
    builder: (context) => _CreateRunSetupDialog(
      definition: definition,
      seedInput: _workflowRunAuthoringDefaults(controller, definition),
      codebases: controller.automationCodebases,
      targets: controller.automationRuntimeTargets,
      selectedCodebaseId: controller.selectedAutomationCodebase?.id ?? '',
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
    codebaseId: result.codebaseId,
    runtimeTargetId: result.runtimeTargetId,
    input: result.input,
    policy: _operationPolicyFromDialogResult(result),
  );
}

/// _StartAutomationRunDialog renders generated workflow-run input controls.
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

/// _StartAutomationRunDialogState owns generated workflow-run field state.
class _StartAutomationRunDialogState extends State<_StartAutomationRunDialog> {
  late final List<_WorkflowRunInputField> _fields;
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};
  final Map<String, bool> _booleanValues = <String, bool>{};
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fields = _workflowRunInputFields(
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
                  _WorkflowRunInputFieldControl(
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

  /// Validates typed fields and returns a workflow input object to the caller.
  void _submit() {
    final input = widget.includeSeedInput
        ? _workflowRunSeedInput(widget.seedInput)
        : <String, dynamic>{};
    final error = _populateWorkflowInputFromFields(
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

/// _RunSetupDialogResult carries one saved Operation created from the UI.
class _RunSetupDialogResult {
  const _RunSetupDialogResult({
    required this.name,
    required this.description,
    required this.codebaseId,
    required this.runtimeTargetId,
    required this.sourceControlPolicy,
    required this.input,
  });

  final String name;
  final String description;
  final String codebaseId;
  final String runtimeTargetId;
  final String sourceControlPolicy;
  final Map<String, dynamic> input;
}

/// _CreateRunSetupDialog renders a typed Operation form for one workflow file.
class _CreateRunSetupDialog extends StatefulWidget {
  const _CreateRunSetupDialog({
    required this.definition,
    required this.seedInput,
    required this.codebases,
    required this.targets,
    required this.selectedCodebaseId,
    required this.selectedTargetId,
  });

  final AutomationDefinition definition;
  final Map<String, dynamic> seedInput;
  final List<AutomationCodebase> codebases;
  final List<AutomationRuntimeTarget> targets;
  final String selectedCodebaseId;
  final String selectedTargetId;

  @override
  State<_CreateRunSetupDialog> createState() => _CreateRunSetupDialogState();
}

/// _CreateRunSetupDialogState owns Operation field controllers.
class _CreateRunSetupDialogState extends State<_CreateRunSetupDialog> {
  late final TextEditingController _nameController;
  late final List<_WorkflowRunInputField> _fields;
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};
  final Map<String, bool> _booleanValues = <String, bool>{};
  String _codebaseId = '';
  String _targetId = '';
  String _sourceControlPolicy = _operationSafetyOpenPROnly;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: '${widget.definition.name} Operation',
    );
    _codebaseId = _initialCodebaseId(
      widget.codebases,
      widget.selectedCodebaseId,
    );
    _targetId = _initialTargetId(
      codebases: widget.codebases,
      targets: widget.targets,
      codebaseId: _codebaseId,
      selectedTargetId: widget.selectedTargetId,
    );
    final setupFields = _workflowRunSetupSetupFields(
      widget.definition.body,
    ).where((name) => !_isCodebaseBackedInputName(name)).toSet();
    _fields = _workflowRunInputFields(
      widget.definition,
      seedInput: widget.seedInput,
      includedNames: setupFields,
      excludedNames: _workflowRunSetupRunFields(widget.definition.body),
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

  /// Builds the saved Operation creation dialog.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final targetOptions = _targetOptionsForCodebase(
      widget.targets,
      _codebaseId,
    );
    return AlertDialog(
      title: Text('Create Operation'),
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
                  label: 'Operation Name *',
                ),
                const SizedBox(height: 12),
                _AutomationDropdown(
                  key: const ValueKey<String>('automation-run-setup-codebase'),
                  label: 'Codebase *',
                  value: _codebaseId,
                  values: <String>[
                    for (final codebase in widget.codebases) codebase.id,
                  ],
                  labels: <String, String>{
                    for (final codebase in widget.codebases)
                      codebase.id: codebase.name,
                  },
                  onChanged: (value) => setState(() {
                    _codebaseId = value;
                    _targetId = _initialTargetId(
                      codebases: widget.codebases,
                      targets: widget.targets,
                      codebaseId: _codebaseId,
                      selectedTargetId: _targetId,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                _AutomationDropdown(
                  key: const ValueKey<String>('automation-run-setup-target'),
                  label: 'Run on *',
                  value: _targetId,
                  values: <String>[
                    for (final target in targetOptions) target.id,
                  ],
                  labels: <String, String>{
                    for (final target in targetOptions) target.id: target.name,
                  },
                  onChanged: (value) => setState(() => _targetId = value),
                ),
                const SizedBox(height: 12),
                _AutomationDropdown(
                  key: const ValueKey<String>('automation-run-setup-safety'),
                  label: 'Safety',
                  value: _sourceControlPolicy,
                  values: const <String>[_operationSafetyOpenPROnly],
                  labels: _operationSafetyLabels,
                  onChanged: (value) =>
                      setState(() => _sourceControlPolicy = value),
                ),
                const SizedBox(height: 12),
                for (final field in _fields) ...<Widget>[
                  _WorkflowRunInputFieldControl(
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

  /// Validates and returns the saved Operation payload.
  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Operation Name is required.');
      return;
    }
    if (_operationNeedsCodebase(widget.definition) && _codebaseId.isEmpty) {
      setState(() => _error = 'Codebase is required.');
      return;
    }
    if (_operationNeedsTarget(widget.definition) && _targetId.isEmpty) {
      setState(() => _error = 'Run on is required.');
      return;
    }
    final input = <String, dynamic>{};
    final error = _populateWorkflowInputFromFields(
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
        codebaseId: _codebaseId,
        runtimeTargetId: _targetId,
        sourceControlPolicy: _sourceControlPolicy,
        input: input,
      ),
    );
  }
}

/// _WorkflowRunInputFieldControl renders one workflow-run form field.
class _WorkflowRunInputFieldControl extends StatelessWidget {
  const _WorkflowRunInputFieldControl({
    required this.field,
    required this.textController,
    required this.booleanValue,
    required this.onBooleanChanged,
  });

  final _WorkflowRunInputField field;
  final TextEditingController? textController;
  final bool booleanValue;
  final ValueChanged<bool> onBooleanChanged;

  /// Builds one typed workflow-run input control.
  @override
  Widget build(BuildContext context) {
    if (field.type == 'boolean') {
      final colors = context.agentAwesomeColors;
      return CheckboxListTile(
        key: ValueKey<String>('automation-run-input-${field.name}'),
        value: booleanValue,
        onChanged: (value) => onBooleanChanged(value ?? false),
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
      keyboardType: _keyboardTypeForWorkflowRunField(field),
    );
  }
}

/// _WorkflowRunInputField describes one typed workflow-run input.
class _WorkflowRunInputField {
  const _WorkflowRunInputField({
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

/// Returns workflow run fields declared by the definition body.
List<_WorkflowRunInputField> _workflowRunInputFields(
  AutomationDefinition definition, {
  Map<String, dynamic> seedInput = const <String, dynamic>{},
  bool onlyMissingRequired = false,
  Set<String>? includedNames,
  Set<String> excludedNames = const <String>{},
}) {
  final schema = _workflowRunInputSchema(definition.body);
  final properties = _map(schema['properties']);
  if (properties.isEmpty) {
    return const <_WorkflowRunInputField>[];
  }
  final defaults = _workflowRunDefaults(definition.body);
  final required = _list(schema['required']).map((item) => '$item').toSet();
  final orderedNames = <String>[
    for (final name in _list(schema['required']).map((item) => '$item'))
      if (properties.containsKey(name)) name,
    for (final name in properties.keys)
      if (!required.contains(name)) name,
  ];
  return <_WorkflowRunInputField>[
    for (final name in orderedNames)
      if (_includeWorkflowRunField(
        name,
        defaults: defaults,
        seedInput: seedInput,
        required: required,
        onlyMissingRequired: onlyMissingRequired,
        includedNames: includedNames,
        excludedNames: excludedNames,
      ))
        _WorkflowRunInputField(
          name: name,
          label: _stateMachineDisplayName(name),
          type: _workflowRunInputType(_map(properties[name])),
          requiredFromUser: _workflowRunFieldRequiredFromUser(
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

/// Reports whether one input field belongs in the generated run form.
bool _includeWorkflowRunField(
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
  return _workflowRunFieldRequiredFromUser(
    name,
    defaults: defaults,
    seedInput: seedInput,
    required: required,
  );
}

/// Reports whether one workflow input field needs a user-provided value.
bool _workflowRunFieldRequiredFromUser(
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
      _isProvidedWorkflowRunValue(seedInput[name])) {
    return false;
  }
  return true;
}

/// Finds the first object schema intended to validate workflow input.
Map<String, dynamic> _workflowRunInputSchema(Map<String, dynamic> body) {
  final direct = _map(body['input_schema']);
  if (direct.isNotEmpty) {
    return direct;
  }
  final authoring = _map(body['authoring']);
  final authoringSchema = _map(authoring['input_schema']);
  if (authoringSchema.isNotEmpty) {
    return authoringSchema;
  }
  for (final action in _workflowStateActions(_list(body['states']))) {
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

/// Finds declarative input defaults used before workflow input validation.
Map<String, dynamic> _workflowRunDefaults(Map<String, dynamic> body) {
  for (final action in _workflowStateActions(_list(body['states']))) {
    final actionMap = _map(action);
    if ('${actionMap['uses'] ?? ''}' != 'data.defaults') {
      continue;
    }
    final args = _map(actionMap['with']);
    if (!'${args['input'] ?? ''}'.contains('workflow_input')) {
      continue;
    }
    return _map(args['defaults']);
  }
  return const <String, dynamic>{};
}

/// Returns UI-resolved workflow defaults that come from authoring metadata.
Map<String, dynamic> _workflowRunAuthoringDefaults(
  AgentAwesomeAppController controller,
  AutomationDefinition definition,
) {
  final authoring = _map(definition.body['authoring']);
  final defaults = _map(authoring['input_defaults']);
  return <String, dynamic>{
    for (final entry in defaults.entries)
      entry.key: _resolveWorkflowRunAuthoringDefault(controller, entry.value),
  };
}

/// Resolves app-context tokens allowed in workflow authoring defaults.
Object _resolveWorkflowRunAuthoringDefault(
  AgentAwesomeAppController controller,
  Object? value,
) {
  final text = '$value'.trim();
  return switch (text) {
    r'${app.workspace_root}' => controller.config.workspaceRoot,
    _ => value ?? '',
  };
}

/// Returns setup fields intended to be configured once for a workflow.
Set<String> _workflowRunSetupSetupFields(Map<String, dynamic> body) {
  final runSetup = _map(_map(body['authoring'])['run_setup']);
  return _list(runSetup['setup_fields']).map((item) => '$item').toSet();
}

/// Returns fields intended to be supplied each time a setup runs.
Set<String> _workflowRunSetupRunFields(Map<String, dynamic> body) {
  final runSetup = _map(_map(body['authoring'])['run_setup']);
  return _list(runSetup['run_fields']).map((item) => '$item').toSet();
}

/// Returns state entry actions from nested state-machine definitions.
List<dynamic> _workflowStateActions(List<dynamic> states) {
  final actions = <dynamic>[];
  for (final state in states.map(_map)) {
    actions.addAll(_list(state['on_entry']));
    actions.addAll(_workflowStateActions(_list(state['states'])));
  }
  return actions;
}

/// Converts a JSON-schema type into the supported form-control type.
String _workflowRunInputType(Map<String, dynamic> property) {
  final type = '${property['type'] ?? 'string'}'.trim().toLowerCase();
  return switch (type) {
    'boolean' => 'boolean',
    'integer' => 'integer',
    'number' => 'number',
    _ => 'string',
  };
}

/// Converts a user-entered field value to the payload type expected by runtime.
Object? _parsedWorkflowRunValue(_WorkflowRunInputField field, String raw) {
  return switch (field.type) {
    'integer' => int.tryParse(raw),
    'number' => double.tryParse(raw),
    _ => raw,
  };
}

/// Adds form-provided field values to a workflow input object.
String? _populateWorkflowInputFromFields({
  required List<_WorkflowRunInputField> fields,
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
    final parsed = _parsedWorkflowRunValue(field, raw);
    if (parsed == null) {
      return '${field.label} must be ${field.type}.';
    }
    input[field.name] = parsed;
  }
  return null;
}

/// Returns seed input that can safely be sent with a workflow run request.
Map<String, dynamic> _workflowRunSeedInput(Map<String, dynamic> seedInput) {
  return <String, dynamic>{
    for (final entry in seedInput.entries)
      if (_isProvidedWorkflowRunValue(entry.value)) entry.key: entry.value,
  };
}

/// Reports whether a value is meaningful form input rather than a blank token.
bool _isProvidedWorkflowRunValue(Object? value) {
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

/// Returns a keyboard suited to one workflow field type.
TextInputType _keyboardTypeForWorkflowRunField(_WorkflowRunInputField field) {
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

/// Returns a boolean default value for workflow run fields.
bool _initialBooleanValue(Object? value) {
  if (value is bool) {
    return value;
  }
  return '${value ?? ''}'.trim().toLowerCase() == 'true';
}

List<CommandPanelDetailMode> _detailModesForPanel(String panelId) {
  switch (panelId) {
    case _automationPanelOperations:
      return const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _automationDetailOverview,
          label: 'Overview',
          icon: Icons.info_outline,
        ),
        CommandPanelDetailMode(
          id: _automationDetailSetup,
          label: 'Setup',
          icon: Icons.tune_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailInputs,
          label: 'Inputs',
          icon: Icons.input,
        ),
        CommandPanelDetailMode(
          id: _automationDetailTargets,
          label: 'Targets',
          icon: Icons.devices_other_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailSchedule,
          label: 'Schedule',
          icon: Icons.event_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailSafety,
          label: 'Safety',
          icon: Icons.verified_user_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailHistory,
          label: 'Runs',
          icon: Icons.history,
        ),
        CommandPanelDetailMode(
          id: _automationDetailTest,
          label: 'Test',
          icon: Icons.play_circle_outline,
        ),
      ];
    case _automationPanelWorkflows:
      return const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _automationDetailBuilder,
          label: 'Builder',
          icon: Icons.account_tree_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailInspect,
          label: 'Inspect',
          icon: Icons.tune_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailOverview,
          label: 'Overview',
          icon: Icons.info_outline,
        ),
        CommandPanelDetailMode(
          id: _automationDetailSteps,
          label: 'Steps',
          icon: Icons.account_tree_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailMap,
          label: 'Map',
          icon: Icons.hub_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailSafety,
          label: 'Safety',
          icon: Icons.verified_user_outlined,
        ),
      ];
    case _automationPanelTasks:
      return const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _automationDetailBuilder,
          label: 'Builder',
          icon: Icons.account_tree_outlined,
        ),
        CommandPanelDetailMode(
          id: _automationDetailOverview,
          label: 'Overview',
          icon: Icons.info_outline,
        ),
        CommandPanelDetailMode(
          id: _automationDetailSafety,
          label: 'Safety',
          icon: Icons.verified_user_outlined,
        ),
      ];
    default:
      return const <CommandPanelDetailMode>[];
  }
}

/// Returns second-level tabs available inside the selected right workspace.
List<ShellTab> _detailTabsForMode(String panelId, String modeId) {
  return const <ShellTab>[];
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (inbox.isEmpty)
          const PanelEmptyBlock(label: 'No pending automation items')
        else
          for (final item in inbox)
            _PendingItemTile(controller: controller, item: item),
      ],
    );
  }
}

class _AutomationPublishedContent extends StatelessWidget {
  const _AutomationPublishedContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds installed workflow files for Operations.
  @override
  Widget build(BuildContext context) {
    final definitions = _filterDefinitions(
      controller.automationDefinitions,
      query,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (definitions.isEmpty)
          const PanelEmptyBlock(label: 'No workflow files')
        else
          for (final definition in definitions)
            _DefinitionTile(controller: controller, definition: definition),
      ],
    );
  }
}

class _AutomationRunSetupsContent extends StatelessWidget {
  const _AutomationRunSetupsContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds saved Operations.
  @override
  Widget build(BuildContext context) {
    final setups = _filterRunSetups(
      controller.automationRunSetups,
      query,
      definitions: controller.automationDefinitions,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (setups.isEmpty)
          const PanelEmptyBlock(label: 'No operations')
        else
          for (final setup in setups)
            _RunSetupTile(controller: controller, setup: setup),
      ],
    );
  }
}

class _AutomationCodebasesContent extends StatelessWidget {
  const _AutomationCodebasesContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds selectable codebase records for Operations.
  @override
  Widget build(BuildContext context) {
    final codebases = _filterCodebases(controller.automationCodebases, query);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (codebases.isEmpty)
          const PanelEmptyBlock(label: 'No codebases')
        else
          for (final codebase in codebases)
            _CodebaseTile(controller: controller, codebase: codebase),
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

  /// Builds selectable Computer or Server targets for Operations.
  @override
  Widget build(BuildContext context) {
    final targets = _filterRuntimeTargets(
      controller.automationRuntimeTargets,
      query,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (targets.isEmpty)
          const PanelEmptyBlock(label: 'No computers')
        else
          for (final target in targets)
            _RuntimeTargetTile(controller: controller, target: target),
      ],
    );
  }
}

class _AutomationSchedulesContent extends StatelessWidget {
  const _AutomationSchedulesContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds selectable Operation schedules.
  @override
  Widget build(BuildContext context) {
    final setups = _filterScheduledOperations(
      controller.automationRunSetups,
      query,
      definitions: controller.automationDefinitions,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (setups.isEmpty)
          const PanelEmptyBlock(label: 'No scheduled operations')
        else
          for (final setup in setups)
            _ScheduleTile(controller: controller, setup: setup),
      ],
    );
  }
}

class _AutomationArtifactsContent extends StatelessWidget {
  const _AutomationArtifactsContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds selectable run artifacts from workflow output.
  @override
  Widget build(BuildContext context) {
    final artifacts = _filterOperationArtifacts(
      _operationArtifactsForRuns(
        controller.automationRuns,
        definitions: controller.automationDefinitions,
      ),
      query,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (artifacts.isEmpty)
          const PanelEmptyBlock(label: 'No artifacts')
        else
          for (final artifact in artifacts)
            _ArtifactTile(controller: controller, artifact: artifact),
      ],
    );
  }
}

class _AutomationRunsContent extends StatelessWidget {
  const _AutomationRunsContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds selectable automation run history.
  @override
  Widget build(BuildContext context) {
    final runs = _filterRuns(
      controller.automationRuns,
      query,
      definitions: controller.automationDefinitions,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (runs.isEmpty)
          const PanelEmptyBlock(label: 'No recent automation runs')
        else
          for (final run in runs) _RunTile(controller: controller, run: run),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: drafts.isEmpty
          ? <Widget>[PanelEmptyBlock(label: emptyLabel)]
          : <Widget>[
              for (final draft in drafts)
                _DraftTile(controller: controller, draft: draft),
            ],
    );
  }
}

class _AutomationWorkflowStatePaletteContent extends StatelessWidget {
  const _AutomationWorkflowStatePaletteContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds the shell-owned workflow builder node palette.
  @override
  Widget build(BuildContext context) {
    final selectedDraft = _selectedAutomationDraftForKind(
      controller,
      automationWorkflowKind,
    );
    final actionIntents = _TaskGraphActionIntentScope.maybeOf(context);
    final selectedBody = _map(selectedDraft?.body);
    if (_isWorkflowGraphDraft(selectedDraft, selectedBody) ||
        _stateMachineHasTaskStates(selectedBody)) {
      return _TaskGraphActionPalette(
        actionTypes: _resolvedTaskGraphActionTypes(controller),
        query: query,
        onAddAction: (actionName) {
          if (selectedDraft == null || controller.automationsBusy) {
            return;
          }
          controller.selectAutomationDraft(selectedDraft.id);
          actionIntents?.addAction(actionName);
        },
      );
    }
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

class _AutomationCapabilitiesContent extends StatelessWidget {
  const _AutomationCapabilitiesContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds selectable Capability Lab registry records.
  @override
  Widget build(BuildContext context) {
    final capabilities = _filterCapabilities(
      controller.automationCapabilities,
      query,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        if (capabilities.isEmpty)
          const PanelEmptyBlock(label: 'No capabilities')
        else
          for (final capability in capabilities)
            _CapabilityTile(controller: controller, capability: capability),
      ],
    );
  }
}

class _AutomationTaskNodePaletteContent extends StatelessWidget {
  const _AutomationTaskNodePaletteContent({
    required this.controller,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final String query;

  /// Builds the node-type quick access panel for task-graph authoring.
  @override
  Widget build(BuildContext context) {
    final selectedDraft = _selectedAutomationDraftForKind(
      controller,
      automationTaskGraphKind,
    );
    if (selectedDraft == null) {
      return Center(
        child: SelectableText(
          'Select a task graph',
          style: TextStyle(color: context.agentAwesomeColors.muted),
        ),
      );
    }
    final actionIntents = _TaskGraphActionIntentScope.maybeOf(context);
    return _TaskGraphActionPalette(
      actionTypes: _resolvedTaskGraphActionTypes(controller),
      query: query,
      onAddAction: (actionName) {
        if (actionIntents != null) {
          actionIntents.addAction(actionName);
          controller.selectAutomationDraft(selectedDraft.id);
          return;
        }
        if (controller.automationsBusy) {
          return;
        }
        controller.selectAutomationDraft(selectedDraft.id);
        unawaited(
          controller.addAutomationActionToSelectedDraftFromUi(actionName),
        );
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
    this.tabId = '',
  });

  final AgentAwesomeAppController controller;
  final _StateMachineDraftEditController stateMachineEditor;
  final String areaId;
  final String modeId;
  final String tabId;
  final ValueChanged<String> onDetailModeRequested;

  @override
  Widget build(BuildContext context) {
    if (areaId == _automationPanelOperations) {
      return _OperationsDetail(controller: controller, modeId: modeId);
    }
    if (_automationOperationsAreaIds.contains(areaId)) {
      return _OperationsDetail(
        controller: controller,
        areaId: areaId,
        modeId: modeId,
      );
    }
    if (areaId == _automationWorkflowAreaCapabilities) {
      return _CapabilityLabDetail(
        capability: controller.selectedAutomationCapability,
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
    if (areaId == _automationPanelWorkflows ||
        areaId == _automationPanelTasks) {
      final kind = areaId == _automationPanelTasks
          ? automationTaskGraphKind
          : automationWorkflowKind;
      return _DraftDetail(
        controller: controller,
        stateMachineEditor: stateMachineEditor,
        modeId: modeId,
        draft: _selectedAutomationDraftForKind(controller, kind),
        onDetailModeRequested: onDetailModeRequested,
      );
    }
    return _OperationsDetail(controller: controller, modeId: modeId);
  }
}

class _OperationsDetail extends StatelessWidget {
  const _OperationsDetail({
    required this.controller,
    required this.modeId,
    this.areaId = _automationOperationsAreaRuns,
  });

  final AgentAwesomeAppController controller;
  final String areaId;
  final String modeId;

  @override
  Widget build(BuildContext context) {
    if (areaId == _automationOperationsAreaTargets) {
      return _OperationsRuntimeTargetDetail(
        target: controller.selectedAutomationRuntimeTarget,
        health: controller.selectedAutomationTargetHealth,
        logs: controller.selectedAutomationTargetLogs,
        secrets: controller.selectedAutomationTargetSecrets,
        codebases: controller.automationCodebases,
        capabilities: controller.automationCapabilities,
        operations: controller.automationRunSetups,
        modeId: modeId,
      );
    }
    if (areaId == _automationOperationsAreaSetups) {
      return _OperationsRunSetupDetail(
        definitions: controller.automationDefinitions,
        codebases: controller.automationCodebases,
        targets: controller.automationRuntimeTargets,
        runs: controller.automationRuns,
        setups: controller.automationRunSetups,
        selectedSetup: controller.selectedAutomationRunSetup,
        preview: controller.selectedAutomationOperationPreview,
        modeId: modeId,
        onChanged: (setup) =>
            unawaited(controller.updateAutomationRunSetupFromUi(setup)),
      );
    }
    if (modeId == _automationDetailHistory) {
      return _EventList(events: controller.selectedAutomationEvents);
    }
    if (modeId == _automationDetailSafety) {
      return _SafetyDetail(actionTypes: controller.automationActionTypes);
    }
    return switch (areaId) {
      _automationOperationsAreaInbox => _OperationsInboxOverview(
        items: controller.automationInbox,
        selectedItem: controller.selectedAutomationPendingItem,
      ),
      _automationOperationsAreaPublished => _OperationsPublishedOverview(
        definitions: controller.automationDefinitions,
        selectedDefinition: controller.selectedAutomationDefinition,
      ),
      _automationOperationsAreaSetups => _OperationsRunSetupsOverview(
        definitions: controller.automationDefinitions,
        codebases: controller.automationCodebases,
        targets: controller.automationRuntimeTargets,
        setups: controller.automationRunSetups,
        selectedSetup: controller.selectedAutomationRunSetup,
      ),
      _automationOperationsAreaCodebases => _OperationsCodebaseEditor(
        codebase: controller.selectedAutomationCodebase,
        onChanged: (codebase) =>
            unawaited(controller.upsertAutomationCodebaseFromUi(codebase)),
      ),
      _automationOperationsAreaSchedules => _OperationsSchedulesOverview(
        definitions: controller.automationDefinitions,
        setups: controller.automationRunSetups,
        selectedSetup: controller.selectedAutomationRunSetup,
      ),
      _automationOperationsAreaArtifacts => _OperationsArtifactsOverview(
        artifacts: _operationArtifactsForRuns(
          controller.automationRuns,
          definitions: controller.automationDefinitions,
        ),
        selectedRun: controller.selectedAutomationRun,
      ),
      _ => _OperationsRunOverview(
        definitions: controller.automationDefinitions,
        operations: controller.automationRunSetups,
        targets: controller.automationRuntimeTargets,
        run: controller.selectedAutomationRun,
        snapshot: controller.selectedAutomationOperationRunSnapshot,
        runCount: controller.automationRuns.length,
      ),
    };
  }
}

class _CapabilityLabDetail extends StatelessWidget {
  const _CapabilityLabDetail({required this.capability, required this.modeId});

  final AutomationCapability? capability;
  final String modeId;

  /// Builds the selected capability inspector.
  @override
  Widget build(BuildContext context) {
    final selected = capability;
    if (selected == null) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: PanelEmptyBlock(label: 'No capability selected'),
      );
    }
    final rows = <String>[
      selected.label,
      _capabilityKindLabel(selected.kind),
      'Availability: ${_capabilityAvailabilityLabel(selected.availability.status)}',
      if (selected.usableInChat) 'Usable in chat',
      if (selected.usableInWorkflows) 'Usable in workflows',
      if (selected.description.isNotEmpty) selected.description,
      ...selected.availability.reasons.map((reason) => 'Reason: $reason'),
    ];
    final sections = switch (modeId) {
      _automationDetailSafety => <Widget>[
        PanelSectionBlock(
          title: 'Safety',
          child: _DetailRows(rows: _capabilitySafetyRows(selected)),
        ),
      ],
      _automationDetailTest => <Widget>[
        PanelSectionBlock(
          title: 'Checks',
          child: selected.testResults.isEmpty
              ? const PanelEmptyBlock(label: 'No checks recorded')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final result in selected.testResults)
                      _DetailRows(
                        rows: <String>[
                          '${_stateMachineDisplayName(result.type)}: ${_capabilityAvailabilityLabel(result.status)}',
                          if (result.message.isNotEmpty) result.message,
                          if (result.checkedAt.isNotEmpty) result.checkedAt,
                        ],
                      ),
                  ],
                ),
        ),
      ],
      _ => <Widget>[
        PanelSectionBlock(
          title: 'Capability',
          child: _DetailRows(rows: rows),
        ),
        const SizedBox(height: 12),
        PanelSectionBlock(
          title: 'Invocation',
          child: _DetailRows(rows: _capabilityInvocationRows(selected)),
        ),
      ],
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: sections,
    );
  }
}

const Set<String> _automationOperationsAreaIds = <String>{
  _automationOperationsAreaInbox,
  _automationOperationsAreaPublished,
  _automationOperationsAreaSetups,
  _automationOperationsAreaCodebases,
  _automationOperationsAreaTargets,
  _automationOperationsAreaSchedules,
  _automationOperationsAreaArtifacts,
  _automationOperationsAreaRuns,
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
      return const PanelEmptyBlock(label: 'No draft selected');
    }
    if (selectedDraft.kind == automationTaskGraphKind) {
      return _TaskGraphDraftDetail(
        controller: controller,
        modeId: modeId,
        draft: selectedDraft,
      );
    }
    final body = _map(selectedDraft.body);
    final hasTaskStates = _stateMachineHasTaskStates(body);
    final isWorkflowGraph = _isWorkflowGraphDraft(selectedDraft, body);
    if (modeId == _automationDetailBuilder ||
        modeId == _automationDetailInspect ||
        modeId == _automationDetailOverview) {
      if (isWorkflowGraph) {
        return _TaskGraphDraftDetail(
          controller: controller,
          modeId: modeId,
          draft: selectedDraft,
        );
      }
      if (!hasTaskStates && modeId == _automationDetailBuilder) {
        return _StateMachineBuilderWorkspace(
          key: ValueKey<String>('${selectedDraft.id}:state-machine-workspace'),
          editor: stateMachineEditor,
          controller: controller,
          draft: selectedDraft,
          modeId: modeId,
          onDetailModeRequested: onDetailModeRequested,
        );
      }
      if (!hasTaskStates && modeId == _automationDetailInspect) {
        return _StateMachineBuilderWorkspace(
          key: ValueKey<String>('${selectedDraft.id}:state-machine-workspace'),
          editor: stateMachineEditor,
          controller: controller,
          draft: selectedDraft,
          modeId: modeId,
          onDetailModeRequested: onDetailModeRequested,
        );
      }
      if (!hasTaskStates) {
        return _DraftOverview(controller: controller, draft: selectedDraft);
      }
      return _TaskGraphDraftEditor(
        key: ValueKey<String>('${selectedDraft.id}:$modeId'),
        controller: controller,
        draft: selectedDraft,
        view:
            modeId == _automationDetailOverview ||
                modeId == _automationDetailInspect
            ? _TaskGraphDraftEditorView.overview
            : _TaskGraphDraftEditorView.builder,
      );
    }
    if (modeId == _automationDetailSteps) {
      return _DraftSteps(controller: controller, draft: selectedDraft);
    }
    if (modeId == _automationDetailMap) {
      return _StateMachineBuilderDetail(
        editor: stateMachineEditor,
        controller: controller,
        draft: selectedDraft,
        onDetailModeRequested: onDetailModeRequested,
      );
    }
    if (modeId == _automationDetailSafety) {
      return _ValidationDetail(draft: selectedDraft);
    }
    return _DraftOverview(controller: controller, draft: selectedDraft);
  }
}

class _DraftOverview extends StatelessWidget {
  const _DraftOverview({required this.controller, required this.draft});

  final AgentAwesomeAppController controller;
  final AutomationDraft draft;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        PanelSectionBlock(
          title: _isWorkflowFileKind(draft.kind) ? 'Workflow' : 'Draft',
          child: _DetailRows(
            rows: <String>[
              draft.name,
              _draftKindLabel(draft.kind),
              _draftStatusLabel(draft.status),
              if (draft.description.isNotEmpty) draft.description,
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskGraphDraftDetail extends StatelessWidget {
  const _TaskGraphDraftDetail({
    required this.controller,
    required this.modeId,
    required this.draft,
  });

  final AgentAwesomeAppController controller;
  final String modeId;
  final AutomationDraft draft;

  /// Builds task-graph-specific detail views.
  @override
  Widget build(BuildContext context) {
    if (modeId == _automationDetailSafety) {
      return _ValidationDetail(draft: draft);
    }
    return _TaskGraphDraftEditor(
      key: ValueKey<String>('${draft.id}:$modeId'),
      controller: controller,
      draft: draft,
      view:
          modeId == _automationDetailOverview ||
              modeId == _automationDetailInspect
          ? _TaskGraphDraftEditorView.overview
          : _TaskGraphDraftEditorView.builder,
    );
  }
}

enum _TaskGraphDraftEditorView {
  /// Dedicated visual graph authoring surface.
  builder,

  /// Metadata and selected-step form surface.
  overview,
}

class _TaskGraphDraftEditor extends StatefulWidget {
  const _TaskGraphDraftEditor({
    super.key,
    required this.controller,
    required this.draft,
    required this.view,
  });

  final AgentAwesomeAppController controller;
  final AutomationDraft draft;
  final _TaskGraphDraftEditorView view;

  @override
  State<_TaskGraphDraftEditor> createState() => _TaskGraphDraftEditorState();
}

class _TaskGraphDraftEditorState extends State<_TaskGraphDraftEditor> {
  static const Duration _saveDelay = Duration(milliseconds: 500);

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _taskGraphIdController;
  late final TextEditingController _nodeIdController;
  late final TextEditingController _timeoutController;
  late final TextEditingController _retryController;
  late final TextEditingController _retryDelayController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _agentInputController;
  late final TextEditingController _serverIdController;
  late final TextEditingController _endpointController;
  late final TextEditingController _toolController;
  late final TextEditingController _domainIdController;
  late final TextEditingController _argumentsController;
  late final TextEditingController _commandController;
  late final TextEditingController _commandArgsController;
  late final TextEditingController _promptController;
  late final TextEditingController _durationController;
  late final TextEditingController _workflowController;
  late final TextEditingController _signalController;
  late final TextEditingController _payloadController;
  Timer? _saveTimer;
  List<Map<String, dynamic>> _nodes = <Map<String, dynamic>>[];
  Set<String> _dependsOn = <String>{};
  String _selectedNodeId = '';
  String _selectedAction = 'tool.call';
  String _message = '';
  String _lastSavedFingerprint = '';
  _TaskGraphActionIntentController? _taskGraphActionIntents;
  int _lastTaskGraphActionIntentRevision = 0;
  bool _loadingDraft = false;

  bool get _isWorkflowDraft => widget.draft.kind == automationWorkflowKind;

  String get _builderTitle => _isWorkflowDraft ? 'Workflow' : 'Task Graph';

  String get _builderIdLabel => _isWorkflowDraft ? 'Workflow id' : 'Graph id';

  String get _stepNodeTooltip =>
      _isWorkflowDraft ? 'Add workflow step' : 'Add task node';

  String get _deleteNodeTooltip =>
      _isWorkflowDraft ? 'Delete workflow step' : 'Delete task node';

  String get _unsupportedSurface =>
      _isWorkflowDraft ? 'workflows' : 'task graphs';

  /// Initializes task-graph editor controllers from the selected draft.
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _taskGraphIdController = TextEditingController();
    _nodeIdController = TextEditingController();
    _timeoutController = TextEditingController();
    _retryController = TextEditingController();
    _retryDelayController = TextEditingController();
    _instructionsController = TextEditingController();
    _agentInputController = TextEditingController();
    _serverIdController = TextEditingController();
    _endpointController = TextEditingController();
    _toolController = TextEditingController();
    _domainIdController = TextEditingController();
    _argumentsController = TextEditingController();
    _commandController = TextEditingController();
    _commandArgsController = TextEditingController();
    _promptController = TextEditingController();
    _durationController = TextEditingController();
    _workflowController = TextEditingController();
    _signalController = TextEditingController();
    _payloadController = TextEditingController();
    for (final controller in _controllers) {
      controller.addListener(_scheduleSave);
    }
    _loadDraft(widget.draft);
  }

  /// Reloads local fields when a different task-graph draft is selected.
  @override
  void didUpdateWidget(covariant _TaskGraphDraftEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.id != widget.draft.id) {
      _loadDraft(widget.draft);
    }
  }

  /// Subscribes to left-panel node creation requests for this task-graph editor.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextIntents = _TaskGraphActionIntentScope.maybeOf(context);
    if (nextIntents == _taskGraphActionIntents) {
      return;
    }
    _taskGraphActionIntents?.removeListener(_handleTaskGraphActionIntent);
    _taskGraphActionIntents = nextIntents;
    _lastTaskGraphActionIntentRevision = nextIntents?.revision ?? 0;
    _taskGraphActionIntents?.addListener(_handleTaskGraphActionIntent);
  }

  /// Releases task-graph editor controllers and pending saves.
  @override
  void dispose() {
    _saveTimer?.cancel();
    _taskGraphActionIntents?.removeListener(_handleTaskGraphActionIntent);
    for (final controller in _controllers) {
      controller.removeListener(_scheduleSave);
      controller.dispose();
    }
    super.dispose();
  }

  /// Adds the latest left-panel action request to the local task graph.
  void _handleTaskGraphActionIntent() {
    final intents = _taskGraphActionIntents;
    if (intents == null ||
        intents.revision == _lastTaskGraphActionIntentRevision) {
      return;
    }
    _lastTaskGraphActionIntentRevision = intents.revision;
    _addNode(intents.actionName, null);
  }

  List<TextEditingController> get _controllers => <TextEditingController>[
    _nameController,
    _descriptionController,
    _taskGraphIdController,
    _nodeIdController,
    _timeoutController,
    _retryController,
    _retryDelayController,
    _instructionsController,
    _agentInputController,
    _serverIdController,
    _endpointController,
    _toolController,
    _domainIdController,
    _argumentsController,
    _commandController,
    _commandArgsController,
    _promptController,
    _durationController,
    _workflowController,
    _signalController,
    _payloadController,
  ];

  /// Builds the task-graph editor surface.
  @override
  Widget build(BuildContext context) {
    if (widget.view == _TaskGraphDraftEditorView.builder) {
      return _buildGraphBuilder();
    }
    return _buildOverviewEditor(context);
  }

  /// Builds the dedicated visual task-graph builder.
  Widget _buildGraphBuilder() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final designer = _TaskGraphDesignerSurface(
          nodes: _nodes,
          actionTypes: _resolvedActionTypes(),
          selectedNodeId: _selectedNodeId,
          onSelect: _selectNode,
          onMoveToStage: _moveNodeToStage,
          onDropOnNode: _dropNodeOnNode,
          onAddActionToStage: _addNode,
          onAddActionAfterNode: _addNodeAfter,
          onChangeNodeAction: _changeNodeAction,
          onNudgeNode: _nudgeNodeByDrag,
          onToggleConnection: _toggleConnection,
          onDeleteConnection: (dependencyId, targetNodeId) => _removeDependency(
            dependencyId,
            targetNodeId,
            selectedNodeId: targetNodeId,
          ),
          onDeleteNode: _deleteSpecificNode,
          onMoveNodeInStage: _reorderNodeWithinStage,
          onMoveNodeStageBy: _moveNodeStageBy,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          child: constraints.hasBoundedHeight
              ? designer
              : SizedBox(height: 720, child: designer),
        );
      },
    );
  }

  /// Builds metadata and selected-step fields outside the graph surface.
  Widget _buildOverviewEditor(BuildContext context) {
    final selectedNode = _selectedNode();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        PanelSectionBlock.plain(
          title: _builderTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _AutomationTextField(
                controller: _nameController,
                label: _draftNameLabel(widget.draft),
              ),
              const SizedBox(height: 10),
              _AutomationTextField(
                controller: _descriptionController,
                label: 'Description',
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              _AutomationTextField(
                controller: _taskGraphIdController,
                label: _builderIdLabel,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSelectedStepPicker(),
        const SizedBox(height: 12),
        if (selectedNode == null)
          const PanelEmptyBlock(label: 'Select or add a step')
        else
          _buildNodeEditor(context),
      ],
    );
  }

  /// Builds the selected-step selector for the overview form panel.
  Widget _buildSelectedStepPicker() {
    return PanelSectionBlock.plain(
      title: 'Steps',
      trailing: PanelIconButton(
        icon: Icons.add,
        tooltip: _stepNodeTooltip,
        onPressed: widget.controller.automationsBusy ? null : _addNode,
      ),
      child: _nodes.isEmpty
          ? const PanelEmptyBlock(label: 'No steps')
          : _AutomationDropdown(
              label: 'Selected step',
              value: _selectedNodeId,
              values: _nodes.map(_nodeId).where((id) => id.isNotEmpty).toList(),
              onChanged: _selectNode,
            ),
    );
  }

  Widget _buildNodeEditor(BuildContext context) {
    return PanelSectionBlock.plain(
      title: 'Selected Step',
      trailing: PanelIconButton(
        icon: Icons.delete_outline,
        tooltip: _deleteNodeTooltip,
        onPressed: widget.controller.automationsBusy ? null : _deleteNode,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _AutomationTextField(controller: _nodeIdController, label: 'Step id'),
          const SizedBox(height: 10),
          _AutomationDropdown(
            label: 'Action',
            value: _selectedAction,
            values: _actionNames(),
            onChanged: (value) {
              setState(() {
                _selectedAction = value;
                _loadArgs(_defaultTaskGraphActionArgs(value));
                _scheduleSave();
              });
            },
          ),
          const SizedBox(height: 10),
          _TaskGraphDependencySelector(
            nodeIds: _nodes.map(_nodeId).where((id) => id.isNotEmpty).toList(),
            selectedNodeId: _selectedNodeId,
            dependsOn: _dependsOn,
            onChanged: (next) => setState(() {
              _dependsOn = next;
              _scheduleSave();
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _AutomationTextField(
                  controller: _timeoutController,
                  label: 'Timeout',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AutomationTextField(
                  controller: _retryController,
                  label: 'Retry attempts',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AutomationTextField(
                  controller: _retryDelayController,
                  label: 'Retry delay',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildActionFields(),
          if (_message.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _message,
              style: const TextStyle(color: AgentAwesomeColors.coral),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionFields() {
    switch (_selectedAction) {
      case 'tool.call':
        final toolNames = widget.controller.automationToolNames.toList()
          ..sort();
        final selectedTool = _toolController.text.trim();
        final toolValues = <String>{
          '',
          if (selectedTool.isNotEmpty) selectedTool,
          ...toolNames,
        }.toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (toolNames.isEmpty)
              _AutomationTextField(controller: _toolController, label: 'Tool')
            else
              _AutomationDropdown(
                label: 'Tool',
                value: selectedTool,
                values: toolValues,
                labels: const <String, String>{'': 'Select tool'},
                onChanged: (value) => setState(() {
                  _toolController.text = value;
                  _scheduleSave();
                }),
              ),
            const SizedBox(height: 10),
            _AutomationTextField(
              controller: _domainIdController,
              label: 'Domain id',
            ),
            const SizedBox(height: 10),
            _AutomationTextField(
              controller: _argumentsController,
              label: 'Arguments JSON',
              maxLines: 5,
              monospace: true,
            ),
          ],
        );
      case 'mcp.call':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _AutomationTextField(
              controller: _serverIdController,
              label: 'MCP server id',
            ),
            const SizedBox(height: 10),
            _AutomationTextField(
              controller: _endpointController,
              label: 'MCP endpoint',
            ),
            const SizedBox(height: 10),
            _AutomationTextField(controller: _toolController, label: 'Tool'),
            const SizedBox(height: 10),
            _AutomationTextField(
              controller: _argumentsController,
              label: 'Arguments JSON',
              maxLines: 5,
              monospace: true,
            ),
          ],
        );
      case 'command.execute':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _AutomationTextField(
              controller: _toolController,
              label: 'Template id',
            ),
            const SizedBox(height: 10),
            _AutomationTextField(
              controller: _domainIdController,
              label: 'Working directory',
            ),
            const SizedBox(height: 10),
            _AutomationTextField(
              controller: _argumentsController,
              label: 'Parameters JSON',
              maxLines: 5,
              monospace: true,
            ),
          ],
        );
      case 'workflow.run':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _AutomationTextField(
              controller: _workflowController,
              label: 'Workflow id',
            ),
            const SizedBox(height: 10),
            _AutomationTextField(
              controller: _payloadController,
              label: 'Input JSON',
              maxLines: 5,
              monospace: true,
            ),
          ],
        );
      case 'data.assert':
        return _AutomationTextField(
          controller: _argumentsController,
          label: 'Assertion JSON',
          maxLines: 5,
          monospace: true,
        );
      case 'data.defaults':
        return _AutomationTextField(
          controller: _argumentsController,
          label: 'Defaults JSON',
          maxLines: 5,
          monospace: true,
        );
      default:
        return PanelEmptyBlock(
          label:
              '${_fallbackActionLabel(_selectedAction)} is unsupported in $_unsupportedSurface',
        );
    }
  }

  void _loadDraft(AutomationDraft draft) {
    _loadingDraft = true;
    try {
      _nameController.text = draft.name;
      _descriptionController.text = draft.description;
      final body = _normalizedWorkflowBuilderBody(draft);
      _taskGraphIdController.text = '${body['id'] ?? draft.id}';
      _nodes = _workflowBuilderNodes(body);
      _selectedNodeId = _nodes.isEmpty ? '' : _nodeId(_nodes.first);
      _loadSelectedNode();
      _lastSavedFingerprint = _draftFingerprint(
        name: draft.name,
        description: draft.description,
        body: body,
      );
      _message = '';
    } finally {
      _loadingDraft = false;
      _saveTimer?.cancel();
      _saveTimer = null;
    }
  }

  void _selectNode(String nodeId) {
    setState(() {
      _selectedNodeId = nodeId;
      _loadSelectedNode();
    });
  }

  void _loadSelectedNode() {
    final node = _selectedNode();
    if (node == null) {
      _nodeIdController.text = '';
      _timeoutController.text = '';
      _retryController.text = '';
      _retryDelayController.text = '';
      _dependsOn = <String>{};
      _selectedAction = _actionNames().first;
      _loadArgs(const <String, dynamic>{});
      return;
    }
    _nodeIdController.text = _nodeId(node);
    _selectedAction = _nodeUses(node).isEmpty
        ? _actionNames().first
        : _nodeUses(node);
    if (!_actionNames().contains(_selectedAction)) {
      _selectedAction = _actionNames().first;
    }
    _dependsOn = _nodeDependsOn(node).toSet();
    _timeoutController.text = _nodeTimeout(node);
    _retryController.text = _nodeRetryAttempts(node);
    _retryDelayController.text = _nodeRetryDelay(node);
    _loadArgs(_map(node['with']));
  }

  void _loadArgs(Map<String, dynamic> args) {
    _instructionsController.text = '${args['instructions'] ?? ''}';
    _agentInputController.text = _jsonText(_map(args['input']));
    _serverIdController.text = '${args['server_id'] ?? ''}';
    _endpointController.text = '${args['endpoint'] ?? ''}';
    _toolController.text =
        '${args['name'] ?? args['tool'] ?? args['template_id'] ?? ''}';
    _domainIdController.text = '${args['domain_id'] ?? args['cwd'] ?? ''}';
    _argumentsController.text =
        _selectedAction == 'data.assert' || _selectedAction == 'data.defaults'
        ? _jsonText(args)
        : _selectedAction == 'command.execute'
        ? _jsonText(_map(args['parameters']))
        : _jsonText(_map(args['arguments']));
    _commandController.text = '${args['command'] ?? ''}';
    _commandArgsController.text = _linesText(_list(args['arguments']));
    _promptController.text = '${args['prompt'] ?? ''}';
    _durationController.text = '${args['duration'] ?? ''}';
    _workflowController.text = '${args['workflow'] ?? ''}';
    _signalController.text = '${args['signal'] ?? ''}';
    _payloadController.text = _jsonText(
      _map(args['payload']).isNotEmpty
          ? _map(args['payload'])
          : _map(args['input']),
    );
  }

  void _addNode([String actionName = 'tool.call', int? stageIndex]) {
    final dependencies = stageIndex == null
        ? const <String>[]
        : _dependenciesForStage(stageIndex);
    setState(() {
      final id = _nextTaskGraphNodeId(_nodes, actionName);
      _nodes.add(<String, dynamic>{
        'id': id,
        'uses': actionName,
        if (dependencies.isNotEmpty) 'depends_on': dependencies,
        'with': _defaultTaskGraphActionArgs(actionName),
      });
      _nodes = _flattenTaskGraphLevels(_taskGraphLevels(_nodes));
      _selectedNodeId = id;
      _loadSelectedNode();
      _scheduleSave();
    });
  }

  void _addNodeAfter(String actionName, String dependencyId) {
    setState(() {
      final id = _nextTaskGraphNodeId(_nodes, actionName);
      _nodes.add(<String, dynamic>{
        'id': id,
        'uses': actionName,
        'depends_on': <String>[dependencyId],
        'with': _defaultTaskGraphActionArgs(actionName),
      });
      _nodes = _flattenTaskGraphLevels(_taskGraphLevels(_nodes));
      _selectedNodeId = id;
      _loadSelectedNode();
      _scheduleSave();
    });
  }

  void _changeNodeAction(String nodeId, String actionName) {
    final index = _nodes.indexWhere((node) => _nodeId(node) == nodeId);
    if (index < 0) {
      return;
    }
    setState(() {
      final node = Map<String, dynamic>.from(_nodes[index]);
      node['uses'] = actionName;
      node['with'] = _defaultTaskGraphActionArgs(actionName);
      _nodes[index] = node;
      _selectedNodeId = nodeId;
      _loadSelectedNode();
      _scheduleSave();
    });
  }

  void _nudgeNodeByDrag(String nodeId, Offset delta) {
    if (delta.distance < 44) {
      return;
    }
    if (delta.dx.abs() > delta.dy.abs() && delta.dx.abs() > 92) {
      final levels = _taskGraphLevels(_nodes);
      final stage = _stageIndexForNode(levels, nodeId);
      if (stage < 0) {
        return;
      }
      final targetStage = delta.dx > 0 ? stage + 1 : stage - 1;
      _moveNodeToStage(nodeId, targetStage.clamp(0, levels.length));
      return;
    }
    if (delta.dy.abs() > 44) {
      _reorderNodeWithinStage(nodeId, delta.dy > 0 ? 1 : -1);
    }
  }

  void _deleteNode() {
    final removing = _selectedNodeId;
    _deleteSpecificNode(removing);
  }

  void _deleteSpecificNode(String removing) {
    if (removing.isEmpty) {
      return;
    }
    setState(() {
      _nodes = _nodes.where((node) => _nodeId(node) != removing).map((node) {
        final next = Map<String, dynamic>.from(node);
        next['depends_on'] = _nodeDependsOn(
          next,
        ).where((id) => id != removing).toList();
        return next;
      }).toList();
      _selectedNodeId = _nodes.isEmpty ? '' : _nodeId(_nodes.first);
      _loadSelectedNode();
      _scheduleSave();
    });
  }

  void _moveNodeStageBy(String nodeId, int delta) {
    final levels = _taskGraphLevels(_nodes);
    final stageIndex = _stageIndexForNode(levels, nodeId);
    if (stageIndex < 0) {
      return;
    }
    _moveNodeToStage(nodeId, (stageIndex + delta).clamp(0, levels.length));
  }

  void _moveNodeToStage(String nodeId, int stageIndex) {
    final moving = _nodes.firstWhere(
      (node) => _nodeId(node) == nodeId,
      orElse: () => const <String, dynamic>{},
    );
    if (moving.isEmpty) {
      return;
    }
    final dependencies = _dependenciesForStage(
      stageIndex,
      excludeNodeId: nodeId,
    );
    final moved = Map<String, dynamic>.from(moving);
    if (dependencies.isEmpty) {
      moved.remove('depends_on');
    } else {
      moved['depends_on'] = dependencies;
    }
    final nextNodes = <Map<String, dynamic>>[
      for (final node in _nodes)
        _nodeId(node) == nodeId ? moved : Map<String, dynamic>.from(node),
    ];
    setState(() {
      _nodes = _flattenTaskGraphLevels(_taskGraphLevels(nextNodes));
      _selectedNodeId = nodeId;
      _loadSelectedNode();
      _message = '';
      _scheduleSave();
    });
  }

  List<String> _dependenciesForStage(
    int stageIndex, {
    String excludeNodeId = '',
  }) {
    final levels = _taskGraphLevels(_nodes);
    final targetStage = stageIndex.clamp(0, levels.length);
    final previousStage = targetStage <= 0
        ? const <Map<String, dynamic>>[]
        : targetStage > levels.length - 1
        ? levels.last
        : levels[targetStage - 1];
    return previousStage.map(_nodeId).where((id) {
      return id.isNotEmpty &&
          id != excludeNodeId &&
          !_nodeDependsOnPath(_nodes, id, excludeNodeId);
    }).toList();
  }

  /// Handles a node drop onto another node.
  void _dropNodeOnNode(String draggedNodeId, String targetNodeId) {
    if (draggedNodeId == targetNodeId) {
      return;
    }
    final levels = _taskGraphLevels(_nodes);
    final draggedStage = _stageIndexForNode(levels, draggedNodeId);
    final targetStage = _stageIndexForNode(levels, targetNodeId);
    if (draggedStage == targetStage) {
      _reorderNodeBefore(draggedNodeId, targetNodeId);
      return;
    }
    _connectDependency(draggedNodeId, targetNodeId);
  }

  /// Reorders a node before another node in the same dependency stage.
  void _reorderNodeBefore(String draggedNodeId, String targetNodeId) {
    setState(() {
      final draggedIndex = _nodes.indexWhere(
        (node) => _nodeId(node) == draggedNodeId,
      );
      final targetIndex = _nodes.indexWhere(
        (node) => _nodeId(node) == targetNodeId,
      );
      if (draggedIndex < 0 || targetIndex < 0) {
        return;
      }
      final node = _nodes.removeAt(draggedIndex);
      final adjustedTargetIndex = draggedIndex < targetIndex
          ? targetIndex - 1
          : targetIndex;
      _nodes.insert(adjustedTargetIndex, node);
      _selectedNodeId = draggedNodeId;
      _loadSelectedNode();
      _scheduleSave();
    });
  }

  void _reorderNodeWithinStage(String nodeId, int direction) {
    final levels = _taskGraphLevels(_nodes);
    final stageIndex = _stageIndexForNode(levels, nodeId);
    if (stageIndex < 0) {
      return;
    }
    final levelIds = levels[stageIndex].map(_nodeId).toList();
    final currentIndex = levelIds.indexOf(nodeId);
    final targetIndex = currentIndex + direction;
    if (currentIndex < 0 || targetIndex < 0 || targetIndex >= levelIds.length) {
      return;
    }
    levelIds
      ..removeAt(currentIndex)
      ..insert(targetIndex, nodeId);
    final byId = <String, Map<String, dynamic>>{
      for (final node in _nodes) _nodeId(node): node,
    };
    setState(() {
      _nodes = <Map<String, dynamic>>[
        for (var index = 0; index < levels.length; index++)
          for (final id
              in index == stageIndex ? levelIds : levels[index].map(_nodeId))
            if (byId[id] != null) Map<String, dynamic>.from(byId[id]!),
      ];
      _selectedNodeId = nodeId;
      _loadSelectedNode();
      _message = '';
      _scheduleSave();
    });
  }

  /// Connects or disconnects a clicked node from the active connect-mode node.
  void _toggleConnection(String sourceNodeId, String clickedNodeId) {
    if (sourceNodeId == clickedNodeId) {
      return;
    }
    final source = _nodes.firstWhere(
      (node) => _nodeId(node) == sourceNodeId,
      orElse: () => const <String, dynamic>{},
    );
    final clicked = _nodes.firstWhere(
      (node) => _nodeId(node) == clickedNodeId,
      orElse: () => const <String, dynamic>{},
    );
    if (source.isEmpty || clicked.isEmpty) {
      return;
    }
    if (_nodeDependsOn(source).contains(clickedNodeId)) {
      _removeDependency(
        clickedNodeId,
        sourceNodeId,
        selectedNodeId: sourceNodeId,
      );
      return;
    }
    if (_nodeDependsOn(clicked).contains(sourceNodeId)) {
      _removeDependency(
        sourceNodeId,
        clickedNodeId,
        selectedNodeId: sourceNodeId,
      );
      return;
    }
    _connectDependency(
      sourceNodeId,
      clickedNodeId,
      selectedNodeId: sourceNodeId,
    );
  }

  /// Removes one dependency edge without deleting either connected node.
  void _removeDependency(
    String dependencyId,
    String targetNodeId, {
    required String selectedNodeId,
  }) {
    setState(() {
      _nodes = <Map<String, dynamic>>[
        for (final node in _nodes)
          if (_nodeId(node) == targetNodeId)
            _nodeWithoutDependency(node, dependencyId)
          else
            Map<String, dynamic>.from(node),
      ];
      _selectedNodeId = selectedNodeId;
      _loadSelectedNode();
      _message = '';
      _scheduleSave();
    });
  }

  /// Connects one node as an upstream dependency of another node.
  void _connectDependency(
    String dependencyId,
    String targetNodeId, {
    String? selectedNodeId,
  }) {
    if (_nodeDependsOnPath(_nodes, dependencyId, targetNodeId)) {
      setState(() => _message = 'That connection would create a cycle');
      return;
    }
    final targetIndex = _nodes.indexWhere(
      (node) => _nodeId(node) == targetNodeId,
    );
    if (targetIndex < 0) {
      return;
    }
    final nextTarget = Map<String, dynamic>.from(_nodes[targetIndex]);
    final dependencies = _nodeDependsOn(nextTarget).toSet()..add(dependencyId);
    nextTarget['depends_on'] = dependencies.toList();
    final nextNodes = <Map<String, dynamic>>[
      for (var index = 0; index < _nodes.length; index++)
        index == targetIndex
            ? nextTarget
            : Map<String, dynamic>.from(_nodes[index]),
    ];
    setState(() {
      _nodes = _flattenTaskGraphLevels(_taskGraphLevels(nextNodes));
      _selectedNodeId = selectedNodeId ?? targetNodeId;
      _loadSelectedNode();
      _message = '';
      _scheduleSave();
    });
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    if (widget.controller.automationsBusy) {
      _scheduleSave();
      return;
    }
    final draft = _currentDraft();
    if (draft == null) {
      return;
    }
    final fingerprint = _draftFingerprint(
      name: draft.name,
      description: draft.description,
      body: draft.body,
    );
    if (fingerprint == _lastSavedFingerprint) {
      return;
    }
    _lastSavedFingerprint = fingerprint;
    await widget.controller.saveAutomationDraftFromUi(draft);
  }

  AutomationDraft? _currentDraft() {
    final taskGraphId = _taskGraphIdController.text.trim().isEmpty
        ? widget.draft.id
        : _taskGraphIdController.text.trim();
    final node = _selectedNode();
    final nodeIndex = node == null
        ? -1
        : _nodes.indexWhere((item) => _nodeId(item) == _selectedNodeId);
    if (node != null && nodeIndex >= 0) {
      final updatedNode = _currentNode(node);
      if (updatedNode == null) {
        return null;
      }
      _nodes[nodeIndex] = updatedNode;
      _selectedNodeId = _nodeId(updatedNode);
    }
    return AutomationDraft(
      id: widget.draft.id,
      kind: widget.draft.kind,
      name: _nameController.text.trim().isEmpty
          ? widget.draft.id
          : _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      status: widget.draft.status,
      body: _currentDraftBody(taskGraphId),
      validation: widget.draft.validation,
      createdAt: widget.draft.createdAt,
      updatedAt: widget.draft.updatedAt,
    );
  }

  Map<String, dynamic>? _currentNode(Map<String, dynamic> fallback) {
    final id = _nodeIdController.text.trim();
    if (id.isEmpty) {
      setState(() => _message = 'Node id is required');
      return null;
    }
    final duplicate = _nodes.any(
      (node) => !identical(node, fallback) && _nodeId(node) == id,
    );
    if (duplicate) {
      setState(() => _message = 'Node id must be unique');
      return null;
    }
    final args = _currentArgs();
    if (args == null) {
      return null;
    }
    if (mounted && _message.isNotEmpty) {
      setState(() => _message = '');
    }
    return <String, dynamic>{
      'id': id,
      'uses': _selectedAction,
      if (_dependsOn.isNotEmpty) 'depends_on': _dependsOn.toList()..sort(),
      if (_timeoutController.text.trim().isNotEmpty)
        'timeout': _timeoutController.text.trim(),
      if (_retryController.text.trim().isNotEmpty)
        'retry': int.tryParse(_retryController.text.trim()) ?? 0,
      if (_retryDelayController.text.trim().isNotEmpty)
        'retry_delay': _retryDelayController.text.trim(),
      'with': args,
    };
  }

  Map<String, dynamic>? _currentArgs() {
    switch (_selectedAction) {
      case 'tool.call':
        final args = _parseJsonObject(
          _argumentsController.text,
          'Arguments JSON',
        );
        if (args == null) {
          return null;
        }
        return <String, dynamic>{
          'name': _toolController.text.trim(),
          if (_domainIdController.text.trim().isNotEmpty)
            'domain_id': _domainIdController.text.trim(),
          'arguments': args,
        };
      case 'mcp.call':
        final args = _parseJsonObject(
          _argumentsController.text,
          'Arguments JSON',
        );
        if (args == null) {
          return null;
        }
        return <String, dynamic>{
          if (_serverIdController.text.trim().isNotEmpty)
            'server_id': _serverIdController.text.trim(),
          if (_endpointController.text.trim().isNotEmpty)
            'endpoint': _endpointController.text.trim(),
          'tool': _toolController.text.trim(),
          'arguments': args,
        };
      case 'command.execute':
        final params = _parseJsonObject(
          _argumentsController.text,
          'Parameters JSON',
        );
        if (params == null) {
          return null;
        }
        return <String, dynamic>{
          'template_id': _toolController.text.trim(),
          if (_domainIdController.text.trim().isNotEmpty)
            'cwd': _domainIdController.text.trim(),
          'parameters': params,
        };
      case 'workflow.run':
        final input = _parseJsonObject(_payloadController.text, 'Input JSON');
        if (input == null) {
          return null;
        }
        return <String, dynamic>{
          'workflow': _workflowController.text.trim(),
          'input': input,
        };
      case 'data.assert':
        return _parseJsonObject(_argumentsController.text, 'Assertion JSON');
      case 'data.defaults':
        return _parseJsonObject(_argumentsController.text, 'Defaults JSON');
      default:
        return _map(_selectedNode()?['with']);
    }
  }

  Map<String, dynamic> _currentDraftBody(String taskGraphId) {
    if (_isWorkflowDraft) {
      final original = Map<String, dynamic>.from(_map(widget.draft.body));
      return _workflowBodyFromBuilderNodes(
        original: original,
        id: taskGraphId,
        name: _nameController.text.trim().isEmpty
            ? widget.draft.id
            : _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        nodes: _nodes,
      );
    }
    if (widget.draft.kind == automationTaskGraphKind) {
      return <String, dynamic>{
        'kind': automationTaskGraphKind,
        'id': taskGraphId,
        'nodes': _nodes,
      };
    }
    final original = Map<String, dynamic>.from(_map(widget.draft.body));
    final originalHadTaskStates = _stateMachineHasTaskStates(original);
    if (_nodes.isEmpty && !originalHadTaskStates) {
      return <String, dynamic>{
        ...original,
        'kind': _stateMachineBodyKind,
        'id': taskGraphId,
        'name': _nameController.text.trim().isEmpty
            ? widget.draft.id
            : _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
      };
    }
    final states = <Map<String, dynamic>>[
      for (final node in _nodes) _stateMachineTaskStateFromNode(node),
    ];
    final stateIds = states.map(_nodeId).where((id) => id.isNotEmpty).toSet();
    final body = <String, dynamic>{
      ...original,
      'kind': _stateMachineBodyKind,
      'id': taskGraphId,
      'name': _nameController.text.trim().isEmpty
          ? widget.draft.id
          : _nameController.text.trim(),
      'description': _descriptionController.text.trim(),
      'states': states,
    };
    body.remove('nodes');
    final initial = '${body['initial'] ?? ''}'.trim();
    if (initial.isNotEmpty && !stateIds.contains(initial)) {
      body.remove('initial');
    }
    return body;
  }

  Map<String, dynamic>? _parseJsonObject(String value, String label) {
    final text = value.trim();
    if (text.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, item) => MapEntry('$key', item));
      }
      setState(() => _message = '$label must be a JSON object');
      return null;
    } catch (_) {
      setState(() => _message = '$label is not valid JSON');
      return null;
    }
  }

  void _scheduleSave() {
    if (_loadingDraft) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(_save()));
  }

  String _draftFingerprint({
    required String name,
    required String description,
    required Map<String, dynamic> body,
  }) {
    return jsonEncode(<String, Object?>{
      'name': name.trim(),
      'description': description.trim(),
      'body': body,
    });
  }

  Map<String, dynamic>? _selectedNode() {
    for (final node in _nodes) {
      if (_nodeId(node) == _selectedNodeId) {
        return node;
      }
    }
    return null;
  }

  List<String> _actionNames() {
    final names = _resolvedTaskGraphActionTypes(
      widget.controller,
    ).where((action) => action.available).map((action) => action.name).toList();
    final selected = _selectedAction.trim();
    if (selected.isNotEmpty && !names.contains(selected)) {
      return <String>[...names, selected];
    }
    return names;
  }

  List<AutomationActionType> _resolvedActionTypes() {
    final actions = _resolvedTaskGraphActionTypes(widget.controller).toList();
    final actionNames = actions.map((action) => action.name).toSet();
    for (final node in _nodes) {
      final uses = _nodeUses(node);
      if (uses.isNotEmpty && !actionNames.contains(uses)) {
        actions.add(
          AutomationActionType(
            name: uses,
            label: _fallbackActionLabel(uses),
            description: 'Unsupported in $_unsupportedSurface',
            risk: 'unsupported',
            available: false,
          ),
        );
        actionNames.add(uses);
      }
    }
    return actions;
  }
}

/// Returns available workflow action types with built-in labels while loading.
List<AutomationActionType> _resolvedAutomationActionTypes(
  AgentAwesomeAppController controller,
) {
  final known = <String, AutomationActionType>{
    for (final action in controller.automationActionTypes)
      if (action.name.trim().isNotEmpty) action.name: action,
  };
  final capabilityByAction = <String, AutomationCapability>{
    for (final capability in controller.automationCapabilities)
      if (capability.kind == 'workflow_action' && capability.name.isNotEmpty)
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
          'workflow.run',
          'workflow.signal',
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
        risk: 'workflow',
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
        capability.usableInWorkflows &&
        capability.availability.status == 'available',
    inputSchema: base.inputSchema,
    outputSchema: base.outputSchema,
    inputContracts: base.inputContracts,
    outputContracts: base.outputContracts,
  );
}

/// Returns action types that may be newly created as task-state steps.
List<AutomationActionType> _resolvedTaskGraphActionTypes(
  AgentAwesomeAppController controller,
) {
  final known = <String, AutomationActionType>{
    for (final action in _resolvedAutomationActionTypes(controller))
      action.name: action,
  };
  return <AutomationActionType>[
    for (final name in _taskGraphActionNames)
      known[name] ??
          AutomationActionType(
            name: name,
            label: _fallbackActionLabel(name),
            description: _fallbackActionDescription(name),
            risk: 'workflow',
            available: true,
          ),
  ];
}

class _AutomationTextField extends PanelTextFormField {
  const _AutomationTextField({
    super.key,
    required super.controller,
    required super.label,
    super.minLines,
    super.maxLines = 1,
    super.keyboardType,
    super.monospace = false,
    super.onSubmitted,
  });
}

class _AutomationDropdown extends StatelessWidget {
  const _AutomationDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.labels = const <String, String>{},
  });

  final String label;
  final String value;
  final List<String> values;
  final Map<String, String> labels;
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

class _TaskGraphDependencySelector extends StatelessWidget {
  const _TaskGraphDependencySelector({
    required this.nodeIds,
    required this.selectedNodeId,
    required this.dependsOn,
    required this.onChanged,
  });

  final List<String> nodeIds;
  final String selectedNodeId;
  final Set<String> dependsOn;
  final ValueChanged<Set<String>> onChanged;

  /// Builds dependency checkboxes for task nodes.
  @override
  Widget build(BuildContext context) {
    final choices = nodeIds.where((id) => id != selectedNodeId).toList();
    if (choices.isEmpty) {
      return const PanelEmptyBlock(label: 'No dependency candidates');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final id in choices)
          PanelFilterChip(
            label: id,
            selected: dependsOn.contains(id),
            onSelected: (selected) {
              final next = <String>{...dependsOn};
              if (selected) {
                next.add(id);
              } else {
                next.remove(id);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _TaskGraphDesignerSurface extends StatefulWidget {
  const _TaskGraphDesignerSurface({
    required this.nodes,
    required this.actionTypes,
    required this.selectedNodeId,
    required this.onSelect,
    required this.onMoveToStage,
    required this.onDropOnNode,
    required this.onAddActionToStage,
    required this.onAddActionAfterNode,
    required this.onChangeNodeAction,
    required this.onNudgeNode,
    required this.onToggleConnection,
    required this.onDeleteConnection,
    required this.onDeleteNode,
    required this.onMoveNodeInStage,
    required this.onMoveNodeStageBy,
  });

  final List<Map<String, dynamic>> nodes;
  final List<AutomationActionType> actionTypes;
  final String selectedNodeId;
  final ValueChanged<String> onSelect;
  final void Function(String nodeId, int stageIndex) onMoveToStage;
  final void Function(String draggedNodeId, String targetNodeId) onDropOnNode;
  final void Function(String actionName, int? stageIndex) onAddActionToStage;
  final void Function(String actionName, String dependencyId)
  onAddActionAfterNode;
  final void Function(String nodeId, String actionName) onChangeNodeAction;
  final void Function(String nodeId, Offset delta) onNudgeNode;
  final void Function(String sourceNodeId, String clickedNodeId)
  onToggleConnection;
  final void Function(String dependencyId, String targetNodeId)
  onDeleteConnection;
  final ValueChanged<String> onDeleteNode;
  final void Function(String nodeId, int direction) onMoveNodeInStage;
  final void Function(String nodeId, int delta) onMoveNodeStageBy;

  @override
  State<_TaskGraphDesignerSurface> createState() =>
      _TaskGraphDesignerSurfaceState();
}

class _TaskGraphDesignerSurfaceState extends State<_TaskGraphDesignerSurface> {
  static const double _nodeWidth = 230;
  static const double _nodeCardHeight = 136;
  static const double _nodeHeight = 178;

  double _zoom = 1;
  String _connectionSourceId = '';
  _TaskGraphEdgeId? _selectedEdge;

  /// Builds the professional task-graph designer surface.
  @override
  Widget build(BuildContext context) {
    return PanelSurface(
      fillWidth: true,
      clipBehavior: Clip.hardEdge,
      style: PanelSurfaceStyle.card,
      child: _TaskGraphCanvasViewport(
        key: const ValueKey<String>('task-graph-canvas'),
        nodes: widget.nodes,
        actionTypes: widget.actionTypes,
        selectedNodeId: widget.selectedNodeId,
        connectionSourceId: _connectionSourceId,
        zoom: _zoom,
        nodeWidth: _nodeWidth,
        nodeHeight: _nodeHeight,
        nodeCardHeight: _nodeCardHeight,
        onSelect: _selectOrConnectNode,
        onMoveToStage: widget.onMoveToStage,
        onDropOnNode: widget.onDropOnNode,
        onAddActionToStage: widget.onAddActionToStage,
        onAddActionAfterNode: widget.onAddActionAfterNode,
        onChangeNodeAction: widget.onChangeNodeAction,
        onNudgeNode: widget.onNudgeNode,
        onStartConnection: _startConnection,
        onToggleConnection: _toggleConnection,
        selectedEdge: _selectedEdge,
        onSelectEdge: _selectEdge,
        onDeleteSelectedEdge: _deleteSelectedEdge,
        onDeleteNode: widget.onDeleteNode,
        onMoveNodeInStage: widget.onMoveNodeInStage,
        onMoveNodeStageBy: widget.onMoveNodeStageBy,
        onZoomChanged: (value) => setState(() => _zoom = value),
      ),
    );
  }

  void _selectOrConnectNode(String nodeId) {
    if (_connectionSourceId.isNotEmpty && _connectionSourceId != nodeId) {
      _toggleConnection(nodeId);
      return;
    }
    setState(() => _selectedEdge = null);
    widget.onSelect(nodeId);
  }

  void _startConnection(String nodeId) {
    setState(() {
      _connectionSourceId = _connectionSourceId == nodeId ? '' : nodeId;
      _selectedEdge = null;
    });
    widget.onSelect(nodeId);
  }

  void _toggleConnection(String nodeId) {
    final sourceId = _connectionSourceId;
    if (sourceId.isEmpty || sourceId == nodeId) {
      return;
    }
    setState(() => _selectedEdge = null);
    widget.onToggleConnection(sourceId, nodeId);
  }

  /// Selects a canvas edge and exits node connect mode.
  void _selectEdge(_TaskGraphEdgeId edge) {
    setState(() {
      _connectionSourceId = '';
      _selectedEdge = edge;
    });
  }

  /// Deletes the selected canvas edge from task dependencies.
  void _deleteSelectedEdge() {
    final edge = _selectedEdge;
    if (edge == null) {
      return;
    }
    setState(() => _selectedEdge = null);
    widget.onDeleteConnection(edge.dependencyId, edge.targetNodeId);
  }
}

class _TaskGraphActionPalette extends StatelessWidget {
  const _TaskGraphActionPalette({
    required this.actionTypes,
    required this.query,
    required this.onAddAction,
  });

  final List<AutomationActionType> actionTypes;
  final String query;
  final ValueChanged<String> onAddAction;

  /// Builds the draggable action palette for task node creation.
  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = actionTypes.where((action) {
      if (normalizedQuery.isEmpty) {
        return true;
      }
      return action.name.toLowerCase().contains(normalizedQuery) ||
          action.label.toLowerCase().contains(normalizedQuery) ||
          action.description.toLowerCase().contains(normalizedQuery);
    }).toList();
    if (filtered.isEmpty) {
      return KeyedSubtree(
        key: const ValueKey<String>('task-graph-action-palette'),
        child: PanelEmptyState(query: query),
      );
    }
    return ListView.separated(
      key: const ValueKey<String>('task-graph-action-palette'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      itemCount: filtered.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final action = filtered[index];
        return _TaskGraphActionPaletteTile(
          action: action,
          onAdd: () => onAddAction(action.name),
        );
      },
    );
  }
}

class _TaskGraphActionPaletteTile extends StatelessWidget {
  const _TaskGraphActionPaletteTile({
    required this.action,
    required this.onAdd,
  });

  final AutomationActionType action;
  final VoidCallback onAdd;

  /// Builds one draggable palette action tile.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final tile = Opacity(
      opacity: action.available ? 1 : 0.58,
      child: PanelSurface(
        fillWidth: true,
        padding: const EdgeInsets.all(10),
        style: PanelSurfaceStyle.card,
        child: Row(
          children: <Widget>[
            _TaskGraphNodeIcon(actionName: action.name, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    action.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                  if (!action.available) ...<Widget>[
                    const SizedBox(height: 8),
                    const PanelBadge(label: 'Needs Setup'),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!action.available) {
      return tile;
    }
    return Draggable<_TaskGraphActionDragData>(
      data: _TaskGraphActionDragData(action.name),
      feedback: SizedBox(
        width: 210,
        child: Material(color: Colors.transparent, child: tile),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: tile),
      child: InkWell(
        key: ValueKey<String>('task-graph-action-${action.name}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onAdd,
        child: tile,
      ),
    );
  }
}

class _TaskGraphCanvasViewport extends StatelessWidget {
  const _TaskGraphCanvasViewport({
    super.key,
    required this.nodes,
    required this.actionTypes,
    required this.selectedNodeId,
    required this.connectionSourceId,
    required this.zoom,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.nodeCardHeight,
    required this.onSelect,
    required this.onMoveToStage,
    required this.onDropOnNode,
    required this.onAddActionToStage,
    required this.onAddActionAfterNode,
    required this.onChangeNodeAction,
    required this.onNudgeNode,
    required this.onStartConnection,
    required this.onToggleConnection,
    required this.selectedEdge,
    required this.onSelectEdge,
    required this.onDeleteSelectedEdge,
    required this.onDeleteNode,
    required this.onMoveNodeInStage,
    required this.onMoveNodeStageBy,
    required this.onZoomChanged,
  });

  final List<Map<String, dynamic>> nodes;
  final List<AutomationActionType> actionTypes;
  final String selectedNodeId;
  final String connectionSourceId;
  final double zoom;
  final double nodeWidth;
  final double nodeHeight;
  final double nodeCardHeight;
  final ValueChanged<String> onSelect;
  final void Function(String nodeId, int stageIndex) onMoveToStage;
  final void Function(String draggedNodeId, String targetNodeId) onDropOnNode;
  final void Function(String actionName, int? stageIndex) onAddActionToStage;
  final void Function(String actionName, String dependencyId)
  onAddActionAfterNode;
  final void Function(String nodeId, String actionName) onChangeNodeAction;
  final void Function(String nodeId, Offset delta) onNudgeNode;
  final ValueChanged<String> onStartConnection;
  final ValueChanged<String> onToggleConnection;
  final _TaskGraphEdgeId? selectedEdge;
  final ValueChanged<_TaskGraphEdgeId> onSelectEdge;
  final VoidCallback onDeleteSelectedEdge;
  final ValueChanged<String> onDeleteNode;
  final void Function(String nodeId, int direction) onMoveNodeInStage;
  final void Function(String nodeId, int delta) onMoveNodeStageBy;
  final ValueChanged<double> onZoomChanged;

  /// Builds the scrollable dotted graph canvas and node layout.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final levels = _taskGraphLevels(nodes);
    final layout = _TaskGraphCanvasLayout.fromLevels(
      levels,
      nodeWidth: nodeWidth,
      nodeHeight: nodeHeight,
    );
    final downstreamDependencyIds = <String>{
      for (final node in nodes) ..._nodeDependsOn(node),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : layout.size.width;
        final viewportHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : layout.size.height;
        final contentSize = Size(
          layout.size.width > viewportWidth ? layout.size.width : viewportWidth,
          layout.size.height > viewportHeight
              ? layout.size.height
              : viewportHeight,
        );
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: DragTarget<Object>(
                onWillAcceptWithDetails: (details) =>
                    details.data is _TaskGraphActionDragData,
                onAcceptWithDetails: (details) {
                  final data = details.data;
                  if (data is _TaskGraphActionDragData) {
                    onAddActionToStage(data.actionName, null);
                  }
                },
                builder: (context, candidateData, rejectedData) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(
                        color: candidateData.isEmpty
                            ? colors.border
                            : colors.green,
                      ),
                    ),
                    child: ClipRect(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: Transform.scale(
                            scale: zoom,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: contentSize.width,
                              height: contentSize.height,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: <Widget>[
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _TaskGraphCanvasPainter(
                                        layout: layout,
                                        colors: colors,
                                        selectedEdge: selectedEdge,
                                      ),
                                    ),
                                  ),
                                  for (
                                    var index = 0;
                                    index < layout.stageRects.length;
                                    index++
                                  )
                                    Positioned.fromRect(
                                      rect: layout.stageRects[index],
                                      child: _TaskGraphStageDropColumn(
                                        key: ValueKey<String>(
                                          'task-graph-stage-drop-$index',
                                        ),
                                        stageIndex: index,
                                        onMoveToStage: onMoveToStage,
                                        onAddActionToStage: onAddActionToStage,
                                      ),
                                    ),
                                  Positioned.fromRect(
                                    rect: layout.appendStageRect,
                                    child: _TaskGraphStageDropColumn(
                                      key: ValueKey<String>(
                                        'task-graph-stage-drop-${layout.stageRects.length}',
                                      ),
                                      stageIndex: layout.stageRects.length,
                                      onMoveToStage: onMoveToStage,
                                      onAddActionToStage: onAddActionToStage,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: _TaskGraphEdgeInteractionLayer(
                                      layout: layout,
                                      selectedEdge: selectedEdge,
                                      onSelect: onSelectEdge,
                                      onDelete: onDeleteSelectedEdge,
                                    ),
                                  ),
                                  for (final placement in layout.placements)
                                    Positioned.fromRect(
                                      rect: placement.rect,
                                      child: _TaskGraphGraphNodeCard(
                                        key: ValueKey<String>(
                                          'task-graph-node-${_nodeId(placement.node)}',
                                        ),
                                        node: placement.node,
                                        actionTypes: actionTypes,
                                        cardHeight: nodeCardHeight,
                                        terminal: !downstreamDependencyIds
                                            .contains(_nodeId(placement.node)),
                                        selected:
                                            _nodeId(placement.node) ==
                                            selectedNodeId,
                                        connectionSourceId: connectionSourceId,
                                        connectedToConnectionSource:
                                            _nodesImmediatelyConnected(
                                              nodes,
                                              connectionSourceId,
                                              _nodeId(placement.node),
                                            ),
                                        onDropOnNode: onDropOnNode,
                                        onAddActionAfterNode:
                                            onAddActionAfterNode,
                                        onChangeNodeAction: onChangeNodeAction,
                                        onNudgeNode: onNudgeNode,
                                        onStartConnection: onStartConnection,
                                        onToggleConnection: onToggleConnection,
                                        onDeleteNode: onDeleteNode,
                                        onMoveNodeInStage: onMoveNodeInStage,
                                        onMoveNodeStageBy: onMoveNodeStageBy,
                                        onTap: () =>
                                            onSelect(_nodeId(placement.node)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 16,
              top: 14,
              child: _TaskGraphGraphMenu(
                zoom: zoom,
                onZoomChanged: onZoomChanged,
              ),
            ),
            Positioned(
              right: 16,
              bottom: 14,
              child: _TaskGraphMiniMap(layout: layout),
            ),
          ],
        );
      },
    );
  }
}

class _TaskGraphEdgeInteractionLayer extends StatelessWidget {
  const _TaskGraphEdgeInteractionLayer({
    required this.layout,
    required this.selectedEdge,
    required this.onSelect,
    required this.onDelete,
  });

  final _TaskGraphCanvasLayout layout;
  final _TaskGraphEdgeId? selectedEdge;
  final ValueChanged<_TaskGraphEdgeId> onSelect;
  final VoidCallback onDelete;

  /// Builds path-distance hit testing and controls for canvas edges.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final selectedPlacement = layout.edgeById(selectedEdge);
    final deletePoint = selectedPlacement?.midpoint;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) {
              final edge = layout.edgeAt(details.localPosition);
              if (edge != null) {
                onSelect(edge.id);
              }
            },
            child: const SizedBox.expand(),
          ),
        ),
        if (deletePoint != null && selectedPlacement != null)
          Positioned(
            left: deletePoint.dx - 16,
            top: deletePoint.dy - 16,
            child: Tooltip(
              message: 'Delete connection',
              child: Material(
                color: colors.panel,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: colors.coral),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  key: ValueKey<String>(
                    'task-graph-edge-delete-${selectedPlacement.id.dependencyId}-${selectedPlacement.id.targetNodeId}',
                  ),
                  borderRadius: BorderRadius.circular(8),
                  onTap: onDelete,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(
                      Icons.delete_outline,
                      color: colors.coral,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TaskGraphStageDropColumn extends StatelessWidget {
  const _TaskGraphStageDropColumn({
    super.key,
    required this.stageIndex,
    required this.onMoveToStage,
    required this.onAddActionToStage,
  });

  final int stageIndex;
  final void Function(String nodeId, int stageIndex) onMoveToStage;
  final void Function(String actionName, int? stageIndex) onAddActionToStage;

  /// Builds an invisible but active stage drop column over the canvas.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          details.data is String || details.data is _TaskGraphActionDragData,
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is String) {
          onMoveToStage(data, stageIndex);
        }
        if (data is _TaskGraphActionDragData) {
          onAddActionToStage(data.actionName, stageIndex);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final active = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: active
                ? colors.greenSoft.withValues(alpha: 0.34)
                : Colors.transparent,
            border: active ? Border.all(color: colors.green) : null,
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }
}

class _TaskGraphGraphMenu extends StatelessWidget {
  const _TaskGraphGraphMenu({required this.zoom, required this.onZoomChanged});

  final double zoom;
  final ValueChanged<double> onZoomChanged;

  /// Builds functional canvas zoom controls.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.95),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelInlineIconButton(
            icon: Icons.remove,
            tooltip: 'Zoom out',
            onPressed: () => onZoomChanged((zoom - 0.1).clamp(0.7, 1.4)),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '${(zoom * 100).round()}%',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.ink, fontWeight: FontWeight.w700),
            ),
          ),
          PanelInlineIconButton(
            icon: Icons.add,
            tooltip: 'Zoom in',
            onPressed: () => onZoomChanged((zoom + 0.1).clamp(0.7, 1.4)),
          ),
        ],
      ),
    );
  }
}

class _TaskGraphMiniMap extends StatelessWidget {
  const _TaskGraphMiniMap({required this.layout});

  final _TaskGraphCanvasLayout layout;

  /// Builds a compact map of the current graph topology.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 96,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.agentAwesomeColors.panel.withValues(alpha: 0.9),
          border: Border.all(color: context.agentAwesomeColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: CustomPaint(
          painter: _TaskGraphMiniMapPainter(
            layout: layout,
            colors: context.agentAwesomeColors,
          ),
        ),
      ),
    );
  }
}

class _TaskGraphGraphNodeCard extends StatelessWidget {
  const _TaskGraphGraphNodeCard({
    super.key,
    required this.node,
    required this.actionTypes,
    required this.cardHeight,
    required this.terminal,
    required this.selected,
    required this.connectionSourceId,
    required this.connectedToConnectionSource,
    required this.onDropOnNode,
    required this.onAddActionAfterNode,
    required this.onChangeNodeAction,
    required this.onNudgeNode,
    required this.onStartConnection,
    required this.onToggleConnection,
    required this.onDeleteNode,
    required this.onMoveNodeInStage,
    required this.onMoveNodeStageBy,
    required this.onTap,
  });

  final Map<String, dynamic> node;
  final List<AutomationActionType> actionTypes;
  final double cardHeight;
  final bool terminal;
  final bool selected;
  final String connectionSourceId;
  final bool connectedToConnectionSource;
  final void Function(String draggedNodeId, String targetNodeId) onDropOnNode;
  final void Function(String actionName, String dependencyId)
  onAddActionAfterNode;
  final void Function(String nodeId, String actionName) onChangeNodeAction;
  final void Function(String nodeId, Offset delta) onNudgeNode;
  final ValueChanged<String> onStartConnection;
  final ValueChanged<String> onToggleConnection;
  final ValueChanged<String> onDeleteNode;
  final void Function(String nodeId, int direction) onMoveNodeInStage;
  final void Function(String nodeId, int delta) onMoveNodeStageBy;
  final VoidCallback onTap;

  /// Builds one draggable task graph node.
  @override
  Widget build(BuildContext context) {
    final nodeId = _nodeId(node);
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        return (data is String && data != nodeId) ||
            data is _TaskGraphActionDragData;
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is String) {
          onDropOnNode(data, nodeId);
        }
        if (data is _TaskGraphActionDragData) {
          onAddActionAfterNode(data.actionName, nodeId);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final active = candidateData.isNotEmpty;
        final draggableChild = _TaskGraphGraphNodeSurface(
          node: node,
          selected: selected || active,
          connectedToConnectionSource: connectedToConnectionSource,
          actionTypes: actionTypes,
          cardHeight: cardHeight,
          terminal: terminal,
          connectionSourceId: connectionSourceId,
          onChangeAction: (actionName) =>
              onChangeNodeAction(nodeId, actionName),
          onStartConnection: () => onStartConnection(nodeId),
          onToggleConnection: () => onToggleConnection(nodeId),
          onDeleteNode: () => onDeleteNode(nodeId),
          onMoveUp: () => onMoveNodeInStage(nodeId, -1),
          onMoveDown: () => onMoveNodeInStage(nodeId, 1),
          onMoveLeft: () => onMoveNodeStageBy(nodeId, -1),
          onMoveRight: () => onMoveNodeStageBy(nodeId, 1),
          onTap: onTap,
        );
        return _TaskGraphNodeDragTracker(
          nodeId: nodeId,
          onNudgeNode: onNudgeNode,
          child: draggableChild,
        );
      },
    );
  }
}

class _TaskGraphNodeDragTracker extends StatefulWidget {
  const _TaskGraphNodeDragTracker({
    required this.nodeId,
    required this.onNudgeNode,
    required this.child,
  });

  final String nodeId;
  final void Function(String nodeId, Offset delta) onNudgeNode;
  final Widget child;

  @override
  State<_TaskGraphNodeDragTracker> createState() =>
      _TaskGraphNodeDragTrackerState();
}

class _TaskGraphNodeDragTrackerState extends State<_TaskGraphNodeDragTracker> {
  Offset _delta = Offset.zero;
  bool _emitted = false;

  /// Builds raw pointer tracking for node drag reorder gestures.
  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _reset(),
      onPointerMove: (event) => _delta += event.delta,
      onPointerUp: (_) => _emit(),
      onPointerCancel: (_) => _delta = Offset.zero,
      child: Draggable<String>(
        data: widget.nodeId,
        affinity: Axis.vertical,
        onDragStarted: _reset,
        onDragUpdate: (details) => _delta += details.delta,
        onDragEnd: (_) => _emit(),
        feedback: SizedBox(
          width: _TaskGraphDesignerSurfaceState._nodeWidth,
          height: _TaskGraphDesignerSurfaceState._nodeHeight,
          child: Material(color: Colors.transparent, child: widget.child),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: widget.child),
        child: widget.child,
      ),
    );
  }

  void _reset() {
    _delta = Offset.zero;
    _emitted = false;
  }

  void _emit() {
    if (_emitted) {
      return;
    }
    _emitted = true;
    widget.onNudgeNode(widget.nodeId, _delta);
  }
}

class _TaskGraphGraphNodeSurface extends StatelessWidget {
  const _TaskGraphGraphNodeSurface({
    required this.node,
    required this.selected,
    required this.connectedToConnectionSource,
    required this.actionTypes,
    required this.cardHeight,
    required this.terminal,
    required this.connectionSourceId,
    required this.onChangeAction,
    required this.onStartConnection,
    required this.onToggleConnection,
    required this.onDeleteNode,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onTap,
  });

  final Map<String, dynamic> node;
  final bool selected;
  final bool connectedToConnectionSource;
  final List<AutomationActionType> actionTypes;
  final double cardHeight;
  final bool terminal;
  final String connectionSourceId;
  final ValueChanged<String> onChangeAction;
  final VoidCallback onStartConnection;
  final VoidCallback onToggleConnection;
  final VoidCallback onDeleteNode;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback onTap;

  /// Builds the visual card used by draggable task nodes.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final dependencies = _nodeDependsOn(node);
    final nodeId = _nodeId(node);
    final connectingFromThis = connectionSourceId == nodeId;
    final connectionModeTarget =
        connectionSourceId.isNotEmpty && connectionSourceId != nodeId;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: connectionModeTarget ? onToggleConnection : onTap,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: cardHeight,
            child: PanelSurface(
              selected:
                  selected || connectingFromThis || connectedToConnectionSource,
              padding: const EdgeInsets.all(12),
              style: PanelSurfaceStyle.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _TaskGraphNodeIcon(actionName: _nodeUses(node), size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          nodeId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(Icons.check_circle, size: 14, color: colors.green),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _nodeUses(node),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                  const Spacer(),
                  Row(
                    children: <Widget>[
                      PanelBadge(
                        label: dependencies.isEmpty
                            ? 'entry'
                            : '${dependencies.length} in',
                      ),
                      const Spacer(),
                      if (terminal)
                        const PanelBadge(label: 'terminal')
                      else
                        Text(
                          'out',
                          style: TextStyle(color: colors.muted, fontSize: 11),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: cardHeight + 6,
            child: _TaskGraphNodeInlineToolbar(
              actionTypes: actionTypes,
              currentAction: _nodeUses(node),
              connectingFromThis: connectingFromThis,
              onChangeAction: onChangeAction,
              onStartConnection: onStartConnection,
              onDeleteNode: onDeleteNode,
              onMoveUp: onMoveUp,
              onMoveDown: onMoveDown,
              onMoveLeft: onMoveLeft,
              onMoveRight: onMoveRight,
            ),
          ),
          Positioned(
            left: -5,
            top: 50,
            child: _TaskGraphPort(
              color: connectedToConnectionSource
                  ? colors.green
                  : dependencies.isEmpty
                  ? colors.muted
                  : colors.green,
            ),
          ),
          Positioned(
            right: -5,
            top: 50,
            child: GestureDetector(
              onTap: onStartConnection,
              child: Tooltip(
                message: connectingFromThis ? 'Cancel connection' : 'Connect',
                child: _TaskGraphPort(
                  color: connectingFromThis ? colors.coral : colors.green,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskGraphNodeInlineToolbar extends StatelessWidget {
  const _TaskGraphNodeInlineToolbar({
    required this.actionTypes,
    required this.currentAction,
    required this.connectingFromThis,
    required this.onChangeAction,
    required this.onStartConnection,
    required this.onDeleteNode,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onMoveLeft,
    required this.onMoveRight,
  });

  final List<AutomationActionType> actionTypes;
  final String currentAction;
  final bool connectingFromThis;
  final ValueChanged<String> onChangeAction;
  final VoidCallback onStartConnection;
  final VoidCallback onDeleteNode;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;

  /// Builds point-of-use controls for the selected task node.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final actionLabels = <String, String>{
      for (final action in actionTypes) action.name: action.label,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.96),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 24,
              height: 24,
              child: PopupMenuButton<String>(
                tooltip: 'Change node action',
                padding: EdgeInsets.zero,
                icon: Icon(Icons.tune, size: 16, color: colors.muted),
                color: colors.surface,
                initialValue: currentAction,
                onSelected: onChangeAction,
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  for (final action in actionTypes)
                    if (action.available || action.name == currentAction)
                      PopupMenuItem<String>(
                        value: action.name,
                        child: Text(actionLabels[action.name] ?? action.name),
                      ),
                ],
              ),
            ),
            _TaskGraphNodeToolbarButton(
              icon: Icons.link,
              tooltip: connectingFromThis
                  ? 'Cancel connection'
                  : 'Connect from node',
              selected: connectingFromThis,
              onPressed: onStartConnection,
            ),
            _TaskGraphNodeToolbarButton(
              icon: Icons.arrow_upward,
              tooltip: 'Move up',
              onPressed: onMoveUp,
            ),
            _TaskGraphNodeToolbarButton(
              icon: Icons.arrow_downward,
              tooltip: 'Move down',
              onPressed: onMoveDown,
            ),
            _TaskGraphNodeToolbarButton(
              icon: Icons.arrow_back,
              tooltip: 'Move left',
              onPressed: onMoveLeft,
            ),
            _TaskGraphNodeToolbarButton(
              icon: Icons.arrow_forward,
              tooltip: 'Move right',
              onPressed: onMoveRight,
            ),
            _TaskGraphNodeToolbarButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete node',
              onPressed: onDeleteNode,
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskGraphNodeToolbarButton extends StatelessWidget {
  const _TaskGraphNodeToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  /// Builds one compact point-of-use node toolbar button.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: selected ? colors.greenSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 16,
            color: selected ? colors.green : colors.muted,
          ),
        ),
      ),
    );
  }
}

class _TaskGraphNodeIcon extends StatelessWidget {
  const _TaskGraphNodeIcon({required this.actionName, required this.size});

  final String actionName;
  final double size;

  /// Builds the colored node-type icon used by palette and graph cards.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _actionColor(context, actionName).withValues(alpha: 0.18),
        border: Border.all(
          color: _actionColor(context, actionName).withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _actionIcon(actionName),
        size: size * 0.55,
        color: _actionColor(context, actionName),
      ),
    );
  }
}

class _TaskGraphPort extends StatelessWidget {
  const _TaskGraphPort({required this.color});

  final Color color;

  /// Builds a graph connection port.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: context.agentAwesomeColors.surface, width: 2),
      ),
      child: const SizedBox(width: 12, height: 12),
    );
  }
}

class _TaskGraphActionDragData {
  const _TaskGraphActionDragData(this.actionName);

  final String actionName;
}

class _TaskGraphNodePlacement {
  const _TaskGraphNodePlacement({
    required this.node,
    required this.rect,
    required this.stageIndex,
  });

  final Map<String, dynamic> node;
  final Rect rect;
  final int stageIndex;
}

/// Identifies one directed dependency edge between two task nodes.
class _TaskGraphEdgeId {
  const _TaskGraphEdgeId({
    required this.dependencyId,
    required this.targetNodeId,
  });

  final String dependencyId;
  final String targetNodeId;

  @override
  bool operator ==(Object other) {
    return other is _TaskGraphEdgeId &&
        other.dependencyId == dependencyId &&
        other.targetNodeId == targetNodeId;
  }

  @override
  int get hashCode => Object.hash(dependencyId, targetNodeId);
}

/// Stores the geometry needed to paint and hit-test a task dependency edge.
class _TaskGraphEdgePlacement {
  const _TaskGraphEdgePlacement({
    required this.id,
    required this.from,
    required this.to,
  });

  final _TaskGraphEdgeId id;
  final Offset from;
  final Offset to;

  /// Returns the visual center point used for selected-edge controls.
  Offset get midpoint {
    final metrics = _taskGraphEdgePath(from, to).computeMetrics().toList();
    final metric = metrics.isEmpty ? null : metrics.first;
    return metric?.getTangentForOffset(metric.length / 2)?.position ??
        Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
  }

  /// Measures the shortest sampled distance from a canvas point to the edge.
  double distanceTo(Offset point) {
    final metrics = _taskGraphEdgePath(from, to).computeMetrics().toList();
    if (metrics.isEmpty) {
      return (point - midpoint).distance;
    }
    var nearest = double.infinity;
    for (final metric in metrics) {
      for (
        var distance = 0.0;
        distance <= metric.length;
        distance += _taskGraphEdgeHitSampleStep
      ) {
        final tangent = metric.getTangentForOffset(distance);
        if (tangent == null) {
          continue;
        }
        final nextDistance = (point - tangent.position).distance;
        if (nextDistance < nearest) {
          nearest = nextDistance;
        }
      }
      final tangent = metric.getTangentForOffset(metric.length);
      if (tangent != null) {
        final nextDistance = (point - tangent.position).distance;
        if (nextDistance < nearest) {
          nearest = nextDistance;
        }
      }
    }
    return nearest;
  }
}

class _TaskGraphCanvasLayout {
  const _TaskGraphCanvasLayout({
    required this.size,
    required this.placements,
    required this.stageRects,
    required this.appendStageRect,
  });

  final Size size;
  final List<_TaskGraphNodePlacement> placements;
  final List<Rect> stageRects;
  final Rect appendStageRect;

  Map<String, _TaskGraphNodePlacement> get byId =>
      <String, _TaskGraphNodePlacement>{
        for (final placement in placements) _nodeId(placement.node): placement,
      };

  List<_TaskGraphEdgePlacement> get edges {
    final placementsById = byId;
    return <_TaskGraphEdgePlacement>[
      for (final placement in placements)
        for (final dependencyId in _nodeDependsOn(placement.node))
          if (placementsById[dependencyId] != null)
            _TaskGraphEdgePlacement(
              id: _TaskGraphEdgeId(
                dependencyId: dependencyId,
                targetNodeId: _nodeId(placement.node),
              ),
              from: _taskGraphOutputPortCenter(
                placementsById[dependencyId]!.rect,
              ),
              to: _taskGraphInputPortCenter(placement.rect),
            ),
    ];
  }

  /// Returns the visible edge placement for an edge id.
  _TaskGraphEdgePlacement? edgeById(_TaskGraphEdgeId? edgeId) {
    if (edgeId == null) {
      return null;
    }
    for (final edge in edges) {
      if (edge.id == edgeId) {
        return edge;
      }
    }
    return null;
  }

  /// Returns the nearest edge when the point is close to an actual edge path.
  _TaskGraphEdgePlacement? edgeAt(Offset point) {
    _TaskGraphEdgePlacement? nearestEdge;
    var nearestDistance = _taskGraphEdgeHitRadius;
    for (final edge in edges) {
      final distance = edge.distanceTo(point);
      if (distance <= nearestDistance) {
        nearestDistance = distance;
        nearestEdge = edge;
      }
    }
    return nearestEdge;
  }

  /// Creates deterministic graph layout coordinates from task levels.
  static _TaskGraphCanvasLayout fromLevels(
    List<List<Map<String, dynamic>>> levels, {
    required double nodeWidth,
    required double nodeHeight,
  }) {
    const padding = 72.0;
    const columnGap = 128.0;
    const rowGap = 34.0;
    final stageCount = levels.isEmpty ? 1 : levels.length;
    final maxRows = levels.fold<int>(
      1,
      (value, level) => level.length > value ? level.length : value,
    );
    final graphHeight = maxRows * nodeHeight + (maxRows - 1) * rowGap;
    final width =
        padding * 2 +
        stageCount * nodeWidth +
        (stageCount - 1) * columnGap +
        180;
    final height = padding * 2 + graphHeight;
    final placements = <_TaskGraphNodePlacement>[];
    final stageRects = <Rect>[];
    for (var stageIndex = 0; stageIndex < levels.length; stageIndex++) {
      final level = levels[stageIndex];
      final x = padding + stageIndex * (nodeWidth + columnGap);
      final rowGaps = level.isEmpty ? 0 : level.length - 1;
      final levelHeight = level.length * nodeHeight + rowGaps * rowGap;
      final yStart = padding + (graphHeight - levelHeight) / 2;
      stageRects.add(Rect.fromLTWH(x - 28, 28, nodeWidth + 56, height - 56));
      for (var index = 0; index < level.length; index++) {
        placements.add(
          _TaskGraphNodePlacement(
            node: level[index],
            rect: Rect.fromLTWH(
              x,
              yStart + index * (nodeHeight + rowGap),
              nodeWidth,
              nodeHeight,
            ),
            stageIndex: stageIndex,
          ),
        );
      }
    }
    final appendLeft = padding + stageCount * (nodeWidth + columnGap) - 28;
    return _TaskGraphCanvasLayout(
      size: Size(width, height),
      placements: placements,
      stageRects: stageRects,
      appendStageRect: Rect.fromLTWH(
        appendLeft,
        28,
        nodeWidth + 56,
        height - 56,
      ),
    );
  }
}

class _TaskGraphCanvasPainter extends CustomPainter {
  const _TaskGraphCanvasPainter({
    required this.layout,
    required this.colors,
    required this.selectedEdge,
  });

  final _TaskGraphCanvasLayout layout;
  final AgentAwesomePalette colors;
  final _TaskGraphEdgeId? selectedEdge;

  /// Paints the dotted grid and curved dependency connectors.
  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    _paintEdges(canvas);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = colors.borderStrong.withValues(alpha: 0.34)
      ..style = PaintingStyle.fill;
    const spacing = 18.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }
  }

  void _paintEdges(Canvas canvas) {
    final edgePaint = Paint()
      ..color = colors.muted.withValues(alpha: 0.82)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final selectedEdgePaint = Paint()
      ..color = colors.green.withValues(alpha: 0.96)
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke;
    final activePaint = Paint()
      ..color = colors.green.withValues(alpha: 0.95)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    for (final edge in layout.edges) {
      canvas.drawPath(
        _taskGraphEdgePath(edge.from, edge.to),
        edge.id == selectedEdge ? selectedEdgePaint : edgePaint,
      );
      canvas.drawCircle(edge.to, 4, activePaint);
    }
  }

  /// Repaints when graph topology or colors change.
  @override
  bool shouldRepaint(covariant _TaskGraphCanvasPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.colors != colors ||
        oldDelegate.selectedEdge != selectedEdge;
  }
}

/// Builds the curved path for one task dependency edge.
Path _taskGraphEdgePath(Offset from, Offset to) {
  final bend = (to.dx - from.dx).abs() / 2;
  return Path()
    ..moveTo(from.dx, from.dy)
    ..cubicTo(from.dx + bend, from.dy, to.dx - bend, to.dy, to.dx, to.dy);
}

const double _taskGraphEdgeHitRadius = 6;
const double _taskGraphEdgeHitSampleStep = 4;

/// Returns the visible input port center for a node placement.
Offset _taskGraphInputPortCenter(Rect rect) {
  return Offset(rect.left, rect.top + 56);
}

/// Returns the visible output port center for a node placement.
Offset _taskGraphOutputPortCenter(Rect rect) {
  return Offset(rect.right, rect.top + 56);
}

class _TaskGraphMiniMapPainter extends CustomPainter {
  const _TaskGraphMiniMapPainter({required this.layout, required this.colors});

  final _TaskGraphCanvasLayout layout;
  final AgentAwesomePalette colors;

  /// Paints a compact overview of graph node positions.
  @override
  void paint(Canvas canvas, Size size) {
    if (layout.placements.isEmpty) {
      return;
    }
    final scale = (size.width / layout.size.width)
        .clamp(0.01, size.height / layout.size.height)
        .toDouble();
    final paint = Paint()..color = colors.green.withValues(alpha: 0.72);
    for (final placement in layout.placements) {
      final rect = Rect.fromLTWH(
        placement.rect.left * scale,
        placement.rect.top * scale,
        placement.rect.width * scale,
        placement.rect.height * scale,
      ).shift(const Offset(10, 10));
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );
    }
  }

  /// Repaints when layout or colors change.
  @override
  bool shouldRepaint(covariant _TaskGraphMiniMapPainter oldDelegate) {
    return oldDelegate.layout != layout || oldDelegate.colors != colors;
  }
}

class _DraftSteps extends StatelessWidget {
  const _DraftSteps({required this.controller, required this.draft});

  final AgentAwesomeAppController controller;
  final AutomationDraft draft;

  @override
  Widget build(BuildContext context) {
    final body = _map(draft.body);
    final items = _isWorkflowGraphDraft(draft, body)
        ? _workflowDefinitionNodes(body)
        : draft.kind == automationTaskGraphKind
        ? _taskGraphNodes(body)
        : _stateMachineHasTaskStates(body)
        ? _stateMachineTaskNodes(body)
        : _stateActions(body);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        const PanelSectionLabel('Steps'),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const PanelEmptyBlock(label: 'No steps')
        else
          for (final item in items)
            _AutomationTile(
              title: '${_map(item)['id'] ?? 'step'}',
              subtitle: '${_map(item)['uses'] ?? ''}',
              badges: <String>[
                if (_map(item)['depends_on'] != null) 'depends',
                '${_map(item)['uses'] ?? 'action'}',
              ],
            ),
      ],
    );
  }
}

class _ValidationDetail extends StatelessWidget {
  const _ValidationDetail({required this.draft});

  final AutomationDraft draft;

  @override
  Widget build(BuildContext context) {
    final validation = parseAutomationValidationResult(draft.validation);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        const PanelSectionLabel('Validation'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            PanelBadge(label: validation.valid ? 'valid' : 'invalid'),
            PanelBadge(
              label: validation.publishable ? 'publishable' : 'not publishable',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (validation.diagnostics.isEmpty)
          const PanelEmptyBlock(label: 'No diagnostics')
        else
          for (final diagnostic in validation.diagnostics)
            _AutomationTile(
              title: diagnostic.message,
              subtitle: diagnostic.path,
              badges: <String>[diagnostic.severity],
            ),
      ],
    );
  }
}

class _SafetyDetail extends StatelessWidget {
  const _SafetyDetail({required this.actionTypes});

  final List<AutomationActionType> actionTypes;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        const PanelSectionLabel('Action Risk'),
        const SizedBox(height: 12),
        for (final action in actionTypes)
          _AutomationTile(
            title: action.label,
            subtitle: action.description,
            badges: <String>[
              action.risk,
              action.available ? 'available' : 'draft-only',
            ],
          ),
      ],
    );
  }
}

class _OperationsInboxOverview extends StatelessWidget {
  const _OperationsInboxOverview({
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

class _OperationsPublishedOverview extends StatelessWidget {
  const _OperationsPublishedOverview({
    required this.definitions,
    required this.selectedDefinition,
  });

  final List<AutomationDefinition> definitions;
  final AutomationDefinition? selectedDefinition;

  /// Builds detail context for installed workflow files.
  @override
  Widget build(BuildContext context) {
    final kinds = definitions.map((definition) => definition.kind).toSet();
    final definition = selectedDefinition;
    return _DetailList(
      title: 'Files',
      rows: <String>[
        'Workflow files: ${definitions.length}',
        if (kinds.isNotEmpty)
          'File types: ${kinds.map(_draftKindLabel).join(', ')}',
        if (definition != null) 'Selected: ${definition.name}',
        if (definition != null) 'Type: ${_draftKindLabel(definition.kind)}',
        if (definition != null && definition.updatedAt.isNotEmpty)
          'Updated: ${definition.updatedAt}',
      ],
    );
  }
}

class _OperationsRunSetupDetail extends StatelessWidget {
  const _OperationsRunSetupDetail({
    required this.definitions,
    required this.codebases,
    required this.targets,
    required this.runs,
    required this.setups,
    required this.selectedSetup,
    required this.preview,
    required this.modeId,
    required this.onChanged,
  });

  final List<AutomationDefinition> definitions;
  final List<AutomationCodebase> codebases;
  final List<AutomationRuntimeTarget> targets;
  final List<AutomationRun> runs;
  final List<AutomationRunSetup> setups;
  final AutomationRunSetup? selectedSetup;
  final AutomationOperationPreview? preview;
  final String modeId;
  final ValueChanged<AutomationRunSetup> onChanged;

  /// Builds one saved Operation detail mode.
  @override
  Widget build(BuildContext context) {
    final setup = selectedSetup;
    if (modeId == _automationDetailTest) {
      return _OperationsRunSetupPreview(setup: setup, preview: preview);
    }
    if (setup == null) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: PanelEmptyBlock(label: 'No Operation selected'),
      );
    }
    return switch (modeId) {
      _automationDetailSetup => _OperationsRunSetupEditor(
        setup: setup,
        definitions: definitions,
        codebases: codebases,
        targets: targets,
        onChanged: onChanged,
      ),
      _automationDetailInputs => _DetailList(
        title: 'Inputs',
        rows: _operationInputRows(setup),
      ),
      _automationDetailTargets => _DetailList(
        title: 'Targets',
        rows: _operationTargetRows(
          setup,
          codebases: codebases,
          targets: targets,
        ),
      ),
      _automationDetailSchedule => _DetailList(
        title: 'Schedule',
        rows: _operationScheduleRows(setup),
      ),
      _automationDetailSafety => _DetailList(
        title: 'Safety',
        rows: _operationSafetyRows(
          setup,
          codebases: codebases,
          targets: targets,
        ),
      ),
      _automationDetailHistory => _DetailList(
        title: 'Runs',
        rows: _operationRunRows(setup, runs, definitions: definitions),
      ),
      _ => _OperationsRunSetupsOverview(
        definitions: definitions,
        codebases: codebases,
        targets: targets,
        setups: setups,
        selectedSetup: setup,
      ),
    };
  }
}

class _OperationsRunSetupEditor extends StatefulWidget {
  const _OperationsRunSetupEditor({
    required this.setup,
    required this.definitions,
    required this.codebases,
    required this.targets,
    required this.onChanged,
  });

  final AutomationRunSetup setup;
  final List<AutomationDefinition> definitions;
  final List<AutomationCodebase> codebases;
  final List<AutomationRuntimeTarget> targets;
  final ValueChanged<AutomationRunSetup> onChanged;

  @override
  State<_OperationsRunSetupEditor> createState() =>
      _OperationsRunSetupEditorState();
}

class _OperationsRunSetupEditorState extends State<_OperationsRunSetupEditor> {
  final TextEditingController _name = TextEditingController();
  Timer? _debounce;
  String _activeId = '';
  String _codebaseId = '';
  String _targetId = '';
  String _sourceControlPolicy = _operationSafetyOpenPROnly;
  bool _hydrating = false;

  @override
  void initState() {
    super.initState();
    _hydrate(widget.setup);
    _name.addListener(_scheduleSave);
  }

  @override
  void didUpdateWidget(covariant _OperationsRunSetupEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.setup.id != widget.setup.id) {
      _hydrate(widget.setup);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  /// Builds the selected Operation typed setup editor.
  @override
  Widget build(BuildContext context) {
    final targetOptions = _targetOptionsForCodebase(
      widget.targets,
      _codebaseId,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        _AutomationTextField(controller: _name, label: 'Operation Name'),
        const SizedBox(height: 12),
        _AutomationDropdown(
          key: const ValueKey<String>('automation-operation-edit-codebase'),
          label: 'Codebase',
          value: _codebaseId,
          values: <String>[
            for (final codebase in widget.codebases) codebase.id,
          ],
          labels: <String, String>{
            for (final codebase in widget.codebases) codebase.id: codebase.name,
          },
          onChanged: (value) => setState(() {
            _codebaseId = value;
            _targetId = _initialTargetId(
              codebases: widget.codebases,
              targets: widget.targets,
              codebaseId: _codebaseId,
              selectedTargetId: _targetId,
            );
            _scheduleSave();
          }),
        ),
        const SizedBox(height: 12),
        _AutomationDropdown(
          key: const ValueKey<String>('automation-operation-edit-target'),
          label: 'Run on',
          value: _targetId,
          values: <String>[for (final target in targetOptions) target.id],
          labels: <String, String>{
            for (final target in targetOptions) target.id: target.name,
          },
          onChanged: (value) => setState(() {
            _targetId = value;
            _scheduleSave();
          }),
        ),
        const SizedBox(height: 12),
        _AutomationDropdown(
          key: const ValueKey<String>('automation-operation-edit-safety'),
          label: 'Safety',
          value: _sourceControlPolicy,
          values: const <String>[_operationSafetyOpenPROnly],
          labels: _operationSafetyLabels,
          onChanged: (value) => setState(() {
            _sourceControlPolicy = value;
            _scheduleSave();
          }),
        ),
        const SizedBox(height: 16),
        PanelSectionBlock(
          title: 'Setup',
          child: _DetailRows(
            rows: _operationSetupRows(
              widget.setup,
              definitions: widget.definitions,
              codebases: widget.codebases,
              targets: widget.targets,
            ),
          ),
        ),
      ],
    );
  }

  /// Replaces editor state when the selected Operation changes.
  void _hydrate(AutomationRunSetup setup) {
    _debounce?.cancel();
    _hydrating = true;
    _activeId = setup.id;
    _name.text = setup.name;
    _codebaseId = setup.codebaseId;
    _targetId = setup.runtimeTargetId;
    _sourceControlPolicy =
        _stringFromMap(setup.policy, 'source_control').isEmpty
        ? _operationSafetyOpenPROnly
        : _stringFromMap(setup.policy, 'source_control');
    _hydrating = false;
  }

  /// Schedules bounded autosave after field edits.
  void _scheduleSave() {
    if (_hydrating || _activeId.isEmpty) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 650), () {
      final name = _name.text.trim();
      if (name.isEmpty) {
        return;
      }
      widget.onChanged(
        widget.setup.copyWith(
          name: name,
          codebaseId: _codebaseId,
          runtimeTargetId: _targetId,
          policy: _operationPolicyFromSelections(
            codebaseId: _codebaseId,
            runtimeTargetId: _targetId,
            sourceControlPolicy: _sourceControlPolicy,
          ),
        ),
      );
    });
  }
}

class _OperationsRunSetupsOverview extends StatelessWidget {
  const _OperationsRunSetupsOverview({
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

  /// Builds detail context for saved Operations.
  @override
  Widget build(BuildContext context) {
    final setup = selectedSetup;
    return _DetailList(
      title: 'Operations',
      rows: <String>[
        'Operations: ${setups.length}',
        if (setup != null) 'Selected: ${setup.name}',
        if (setup != null)
          'Workflow file: ${_definitionLabel(definitions, setup.definitionId)}',
        if (setup != null && setup.codebaseId.isNotEmpty)
          'Codebase: ${_codebaseLabel(codebases, setup.codebaseId)}',
        if (setup != null && setup.runtimeTargetId.isNotEmpty)
          'Run on: ${_targetLabel(targets, setup.runtimeTargetId)}',
        if (setup != null && setup.policy['source_control'] != null)
          'Safety: ${_operationSourceControlPolicyLabel('${setup.policy['source_control']}')}',
        if (setup != null && setup.updatedAt.isNotEmpty)
          'Updated: ${setup.updatedAt}',
      ],
    );
  }
}

class _OperationsRunSetupPreview extends StatelessWidget {
  const _OperationsRunSetupPreview({
    required this.setup,
    required this.preview,
  });

  final AutomationRunSetup? setup;
  final AutomationOperationPreview? preview;

  /// Builds dry-run resolution details for a saved Operation.
  @override
  Widget build(BuildContext context) {
    final selected = setup;
    if (selected == null) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: PanelEmptyBlock(label: 'No Operation selected'),
      );
    }
    final current = preview;
    if (current == null || current.operation.id != selected.id) {
      return _DetailList(
        title: 'Test Run',
        rows: <String>['Operation: ${selected.name}', 'Test Run: not started'],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        PanelSectionBlock(
          title: 'Test Run',
          child: _DetailRows(
            rows: <String>[
              'Operation: ${current.operation.name}',
              'Status: ${_operationPreviewStatusLabel(current.status)}',
              'Policy: ${_operationPolicyStatusLabel(current.policyDecision.status)}',
              for (final reason in current.policyDecision.reasons)
                'Policy reason: $reason',
              for (final field in current.missingSetup)
                'Needs Setup: ${_stateMachineDisplayName(field)}',
            ],
          ),
        ),
        const SizedBox(height: 12),
        PanelSectionBlock(
          title: 'Resolved Input',
          child: _DetailRows(rows: _operationPreviewInputRows(current)),
        ),
      ],
    );
  }
}

class _OperationsSchedulesOverview extends StatelessWidget {
  const _OperationsSchedulesOverview({
    required this.definitions,
    required this.setups,
    required this.selectedSetup,
  });

  final List<AutomationDefinition> definitions;
  final List<AutomationRunSetup> setups;
  final AutomationRunSetup? selectedSetup;

  /// Builds detail context for scheduled Operations.
  @override
  Widget build(BuildContext context) {
    final scheduled = setups.where(_operationHasSchedule).toList();
    final selected =
        selectedSetup != null && _operationHasSchedule(selectedSetup!)
        ? selectedSetup
        : scheduled.isEmpty
        ? null
        : scheduled.first;
    return _DetailList(
      title: 'Schedules',
      rows: <String>[
        'Scheduled operations: ${scheduled.length}',
        if (selected != null) 'Operation: ${selected.name}',
        if (selected != null)
          'Workflow file: ${_definitionLabel(definitions, selected.definitionId)}',
        if (selected != null)
          'Schedule: ${_operationScheduleLabel(selected.schedule)}',
        if (selected != null) ..._operationScheduleRows(selected).skip(1),
      ],
    );
  }
}

class _OperationsArtifactsOverview extends StatelessWidget {
  const _OperationsArtifactsOverview({
    required this.artifacts,
    required this.selectedRun,
  });

  final List<_OperationArtifactItem> artifacts;
  final AutomationRun? selectedRun;

  /// Builds detail context for Operation run artifacts.
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

class _OperationsCodebaseEditor extends StatefulWidget {
  const _OperationsCodebaseEditor({
    required this.codebase,
    required this.onChanged,
  });

  final AutomationCodebase? codebase;
  final ValueChanged<AutomationCodebase> onChanged;

  @override
  State<_OperationsCodebaseEditor> createState() =>
      _OperationsCodebaseEditorState();
}

class _OperationsCodebaseEditorState extends State<_OperationsCodebaseEditor> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _files = TextEditingController();
  final TextEditingController _aliases = TextEditingController();
  final TextEditingController _defaultRemote = TextEditingController();
  final TextEditingController _defaultBranch = TextEditingController();
  final TextEditingController _provider = TextEditingController();
  final TextEditingController _providerRepository = TextEditingController();
  final TextEditingController _goModule = TextEditingController();
  final TextEditingController _runtimeTarget = TextEditingController();
  final TextEditingController _agentProfile = TextEditingController();
  Timer? _debounce;
  String _activeId = '';
  bool _hydrating = false;

  @override
  void initState() {
    super.initState();
    _hydrate(widget.codebase);
    for (final controller in _controllers) {
      controller.addListener(_scheduleSave);
    }
  }

  @override
  void didUpdateWidget(covariant _OperationsCodebaseEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.codebase?.id != widget.codebase?.id) {
      _hydrate(widget.codebase);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<TextEditingController> get _controllers => <TextEditingController>[
    _name,
    _files,
    _aliases,
    _defaultRemote,
    _defaultBranch,
    _provider,
    _providerRepository,
    _goModule,
    _runtimeTarget,
    _agentProfile,
  ];

  /// Builds the selected codebase typed editor.
  @override
  Widget build(BuildContext context) {
    if (widget.codebase == null) {
      return const PanelEmptyBlock(label: 'No codebase selected');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        _AutomationTextField(controller: _name, label: 'Name'),
        const SizedBox(height: 12),
        _AutomationTextField(controller: _files, label: 'Files'),
        const SizedBox(height: 12),
        _AutomationTextField(controller: _aliases, label: 'Aliases'),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _AutomationTextField(
                controller: _defaultRemote,
                label: 'Default Remote',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AutomationTextField(
                controller: _defaultBranch,
                label: 'Default Branch',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _AutomationTextField(
                controller: _provider,
                label: 'Provider',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AutomationTextField(
                controller: _providerRepository,
                label: 'Repository',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _AutomationTextField(controller: _goModule, label: 'Go Module'),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _AutomationTextField(
                controller: _runtimeTarget,
                label: 'Runtime Target',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AutomationTextField(
                controller: _agentProfile,
                label: 'Agent Profile',
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Replaces editor controllers when selection changes.
  void _hydrate(AutomationCodebase? codebase) {
    _debounce?.cancel();
    _hydrating = true;
    _activeId = codebase?.id ?? '';
    _name.text = codebase?.name ?? '';
    _files.text = codebase?.repositoryPath ?? '';
    _aliases.text = (codebase?.aliases ?? const <String>[]).join(', ');
    _defaultRemote.text = codebase?.defaultRemote ?? '';
    _defaultBranch.text = codebase?.defaultBranch ?? '';
    _provider.text = codebase?.provider ?? '';
    _providerRepository.text = codebase?.providerRepository ?? '';
    _goModule.text = codebase?.goModulePath ?? '';
    _runtimeTarget.text = codebase?.runtimeTargetId ?? '';
    _agentProfile.text = codebase?.agentProfileId ?? '';
    _hydrating = false;
  }

  /// Schedules bounded autosave after field edits.
  void _scheduleSave() {
    if (_hydrating || _activeId.isEmpty) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 650), () {
      final name = _name.text.trim();
      final files = _files.text.trim();
      if (name.isEmpty || files.isEmpty) {
        return;
      }
      widget.onChanged(
        AutomationCodebase(
          id: _activeId,
          name: name,
          aliases: _splitCodebaseAliases(_aliases.text),
          repositoryPath: files,
          defaultRemote: _defaultRemote.text.trim(),
          defaultBranch: _defaultBranch.text.trim(),
          provider: _provider.text.trim(),
          providerRepository: _providerRepository.text.trim(),
          goModulePath: _goModule.text.trim(),
          runtimeTargetId: _runtimeTarget.text.trim(),
          agentProfileId: _agentProfile.text.trim(),
        ),
      );
    });
  }
}

class _OperationsRuntimeTargetDetail extends StatelessWidget {
  const _OperationsRuntimeTargetDetail({
    required this.target,
    required this.health,
    required this.logs,
    required this.secrets,
    required this.codebases,
    required this.capabilities,
    required this.operations,
    required this.modeId,
  });

  final AutomationRuntimeTarget? target;
  final AutomationTargetHealth? health;
  final List<AutomationTargetLogEntry> logs;
  final AutomationTargetSecretMetadata? secrets;
  final List<AutomationCodebase> codebases;
  final List<AutomationCapability> capabilities;
  final List<AutomationRunSetup> operations;
  final String modeId;

  /// Builds the selected Computer or Server inspector.
  @override
  Widget build(BuildContext context) {
    final selected = target;
    if (selected == null) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: PanelEmptyBlock(label: 'No computer selected'),
      );
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
      _automationTargetDetailOperations => _targetDetailList(
        title: 'Operations',
        rows: _targetOperationRows(selected, operations),
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
      return const Padding(
        padding: EdgeInsets.all(18),
        child: PanelEmptyBlock(label: 'No logs recorded'),
      );
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

class _OperationsRunOverview extends StatelessWidget {
  const _OperationsRunOverview({
    required this.definitions,
    required this.operations,
    required this.targets,
    required this.run,
    required this.snapshot,
    required this.runCount,
  });

  final List<AutomationDefinition> definitions;
  final List<AutomationRunSetup> operations;
  final List<AutomationRuntimeTarget> targets;
  final AutomationRun? run;
  final AutomationOperationRunSnapshot? snapshot;
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
      rows: <String>[
        'Recent runs: $runCount',
        if (selectedRun != null)
          'Workflow: ${_runDefinitionLabel(definitions, selectedRun)}',
        if (selectedRun != null)
          'Status: ${_draftStatusLabel(selectedRun.status)}',
        if (selectedRun != null) 'State: ${selectedRun.state}',
        if (selectedRun != null && selectedRun.updatedAt.isNotEmpty)
          'Updated: ${selectedRun.updatedAt}',
        if (selectedSnapshot != null)
          'Operation: ${_operationLabel(operations, selectedSnapshot.operationId)}',
        if (selectedSnapshot != null)
          'Run on: ${_targetLabel(targets, _stringFromMap(selectedSnapshot.target, 'runtime_target_id'))}',
        if (selectedSnapshot != null && selectedSnapshot.operationVersion > 0)
          'Operation version: ${selectedSnapshot.operationVersion}',
        if (selectedSnapshot != null)
          'Policy: ${_operationSourceControlPolicyLabel(_stringFromMap(selectedSnapshot.policy, 'source_control'))}',
        if (selectedSnapshot != null)
          'Resolved inputs: ${selectedSnapshot.resolvedInput.length}',
        if (selectedSnapshot != null)
          'Secret references: ${selectedSnapshot.secretRefs.length}',
      ],
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({required this.events});

  final List<AutomationEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: PanelEmptyBlock(label: 'No run history selected'),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        for (final event in events)
          _AutomationTile(
            title: event.type,
            subtitle: event.message,
            badges: <String>[event.createdAt],
          ),
      ],
    );
  }
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

class _DetailRows extends StatelessWidget {
  const _DetailRows({required this.rows});

  final List<String> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final row in rows.where((row) => row.trim().isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText(row, style: TextStyle(color: colors.ink)),
          ),
      ],
    );
  }
}

class _OperationArtifactItem {
  const _OperationArtifactItem({
    required this.run,
    required this.title,
    required this.subtitle,
    required this.workflowLabel,
  });

  /// Workflow run that produced the artifact.
  final AutomationRun run;

  /// User-facing artifact title.
  final String title;

  /// Display-safe artifact summary.
  final String subtitle;

  /// Workflow label used as compact metadata.
  final String workflowLabel;
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

class _DefinitionTile extends StatelessWidget {
  const _DefinitionTile({required this.controller, required this.definition});

  final AgentAwesomeAppController controller;
  final AutomationDefinition definition;

  @override
  Widget build(BuildContext context) {
    return _AutomationTile(
      title: definition.name,
      subtitle: '${_draftKindLabel(definition.kind)} file',
      selected: controller.selectedAutomationDefinition?.id == definition.id,
      badges: <String>[_draftKindLabel(definition.kind)],
      onTap: () => controller.selectAutomationDefinition(definition.id),
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
      subtitle: setup.codebaseId.isEmpty
          ? _definitionLabel(
              controller.automationDefinitions,
              setup.definitionId,
            )
          : _codebaseLabel(controller.automationCodebases, setup.codebaseId),
      selected: controller.selectedAutomationRunSetup?.id == setup.id,
      badges: <String>[
        'operation',
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

  /// Builds one selectable Operation schedule row.
  @override
  Widget build(BuildContext context) {
    return _AutomationTile(
      title: setup.name,
      subtitle: _operationScheduleLabel(setup.schedule),
      selected: controller.selectedAutomationRunSetup?.id == setup.id,
      badges: <String>[
        if (_operationScheduleEnabled(setup.schedule)) 'enabled' else 'paused',
      ],
      onTap: () => controller.selectAutomationRunSetup(setup.id),
    );
  }
}

class _ArtifactTile extends StatelessWidget {
  const _ArtifactTile({required this.controller, required this.artifact});

  final AgentAwesomeAppController controller;
  final _OperationArtifactItem artifact;

  /// Builds one selectable run artifact row.
  @override
  Widget build(BuildContext context) {
    return _AutomationTile(
      title: artifact.title,
      subtitle: artifact.subtitle,
      selected: controller.selectedAutomationRun?.id == artifact.run.id,
      badges: <String>[artifact.workflowLabel],
      onTap: () => unawaited(controller.selectAutomationRun(artifact.run.id)),
    );
  }
}

class _CodebaseTile extends StatelessWidget {
  const _CodebaseTile({required this.controller, required this.codebase});

  final AgentAwesomeAppController controller;
  final AutomationCodebase codebase;

  @override
  Widget build(BuildContext context) {
    return _AutomationTile(
      title: codebase.name,
      subtitle: codebase.repositoryPath.isEmpty
          ? codebase.providerRepository
          : codebase.repositoryPath,
      selected: controller.selectedAutomationCodebase?.id == codebase.id,
      badges: <String>[
        if (codebase.provider.isNotEmpty) codebase.provider else 'codebase',
      ],
      onTap: () => controller.selectAutomationCodebase(codebase.id),
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
      onTap: () =>
          unawaited(controller.selectAutomationRuntimeTarget(target.id)),
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({required this.controller, required this.capability});

  final AgentAwesomeAppController controller;
  final AutomationCapability capability;

  @override
  Widget build(BuildContext context) {
    return _AutomationTile(
      title: capability.label.isEmpty ? capability.name : capability.label,
      subtitle: capability.description.isEmpty
          ? _capabilityKindLabel(capability.kind)
          : capability.description,
      selected: controller.selectedAutomationCapability?.id == capability.id,
      badges: <String>[
        _capabilityKindLabel(capability.kind),
        _capabilityAvailabilityLabel(capability.availability.status),
        if (capability.usableInChat) 'chat',
        if (capability.usableInWorkflows) 'workflow',
      ],
      onTap: () => controller.selectAutomationCapability(capability.id),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.controller, required this.run});

  final AgentAwesomeAppController controller;
  final AutomationRun run;

  @override
  Widget build(BuildContext context) {
    return _AutomationTile(
      title: _runDefinitionLabel(controller.automationDefinitions, run),
      subtitle: _runSubtitle(run),
      selected: controller.selectedAutomationRun?.id == run.id,
      badges: <String>[
        _draftStatusLabel(run.status),
        _draftKindLabel(run.kind),
      ],
      onTap: () => unawaited(controller.selectAutomationRun(run.id)),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.controller, required this.draft});

  final AgentAwesomeAppController controller;
  final AutomationDraft draft;

  @override
  Widget build(BuildContext context) {
    final validation = parseAutomationValidationResult(draft.validation);
    final selectedDraft = _selectedAutomationDraftForKind(
      controller,
      draft.kind,
    );
    return _AutomationTile(
      title: draft.name,
      titleWidget: _EditableDraftTitle(
        key: ValueKey<String>('automation-draft-title-${draft.id}'),
        controller: controller,
        draft: draft,
      ),
      subtitle: _draftTileSubtitle(draft),
      selected: selectedDraft?.id == draft.id,
      badges: <String>[
        _draftKindLabel(draft.kind),
        _draftStatusLabel(draft.status),
        if (validation.valid) 'valid',
        if (validation.valid && !validation.publishable) 'blocked',
      ],
      onTap: () => controller.selectAutomationDraft(draft.id),
    );
  }
}

/// _EditableDraftTitle edits one workflow draft title from its card action.
class _EditableDraftTitle extends StatefulWidget {
  /// Creates an editable draft title with an explicit edit affordance.
  const _EditableDraftTitle({
    super.key,
    required this.controller,
    required this.draft,
  });

  /// App controller that owns draft selection and persistence.
  final AgentAwesomeAppController controller;

  /// Draft represented by this catalog title.
  final AutomationDraft draft;

  @override
  State<_EditableDraftTitle> createState() => _EditableDraftTitleState();
}

class _EditableDraftTitleState extends State<_EditableDraftTitle> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  bool _editing = false;
  bool _committing = false;

  /// Initializes the inline text controller.
  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.draft.name);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  /// Keeps the title synced when the backing draft refreshes.
  @override
  void didUpdateWidget(covariant _EditableDraftTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.draft.name != widget.draft.name) {
      _textController.text = widget.draft.name;
    }
  }

  /// Releases inline editing resources.
  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  /// Builds either the static title row or its inline editor.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final style = TextStyle(color: colors.ink, fontWeight: FontWeight.w800);
    if (!_editing) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              widget.draft.name,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: 8),
          PanelInlineIconButton(
            key: ValueKey<String>('automation-draft-rename-${widget.draft.id}'),
            icon: Icons.edit_outlined,
            tooltip: _renameDraftTooltip(widget.draft),
            onPressed: _startEditing,
          ),
        ],
      );
    }
    return Focus(
      onKeyEvent: _handleKey,
      child: TextField(
        key: const ValueKey<String>('automation-draft-title-editor'),
        controller: _textController,
        focusNode: _focusNode,
        autofocus: true,
        maxLines: 1,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _focusNode.unfocus(),
        style: style,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.borderStrong),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.green),
          ),
        ),
      ),
    );
  }

  /// Starts editing and selects the whole title.
  void _startEditing() {
    widget.controller.selectAutomationDraft(widget.draft.id);
    setState(() {
      _editing = true;
      _textController.text = widget.draft.name;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusNode.requestFocus();
      _textController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _textController.text.length,
      );
    });
  }

  /// Commits the title when focus leaves the inline editor.
  void _handleFocusChanged() {
    if (_editing && !_focusNode.hasFocus) {
      _commit();
    }
  }

  /// Handles keyboard commit and cancel behavior for inline editing.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Saves a changed draft title and exits edit mode.
  void _commit() {
    if (!_editing || _committing) {
      return;
    }
    final nextName = _textController.text.trim();
    if (nextName.isEmpty || nextName == widget.draft.name) {
      _cancel();
      return;
    }
    _committing = true;
    setState(() => _editing = false);
    unawaited(
      widget.controller
          .saveAutomationDraftFromUi(_renamedDraft(widget.draft, nextName))
          .whenComplete(() {
            if (mounted) {
              _committing = false;
            }
          }),
    );
  }

  /// Restores the previous title without saving.
  void _cancel() {
    if (!_editing) {
      return;
    }
    setState(() {
      _editing = false;
      _textController.text = widget.draft.name;
    });
    _focusNode.unfocus();
  }
}

/// Returns product-facing supporting text for a workflow draft card.
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

/// Returns the product-facing name field label for a draft kind.
String _draftNameLabel(AutomationDraft draft) {
  return _isWorkflowFileKind(draft.kind) ? 'Workflow name' : 'Task graph name';
}

/// Returns the tooltip for a draft file rename action.
String _renameDraftTooltip(AutomationDraft draft) {
  return _isWorkflowFileKind(draft.kind)
      ? 'Rename workflow file'
      : 'Rename task graph file';
}

/// Returns a copy of a draft with its display name updated.
AutomationDraft _renamedDraft(AutomationDraft draft, String name) {
  final body = Map<String, dynamic>.from(_map(draft.body));
  if (_isWorkflowFileKind(draft.kind) ||
      draft.kind == automationTaskGraphKind ||
      body.containsKey('name')) {
    body['name'] = name;
  }
  return AutomationDraft(
    id: draft.id,
    kind: draft.kind,
    name: name,
    description: draft.description,
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
    automationWorkflowKind => 'workflow',
    _stateMachineBodyKind => 'workflow',
    automationTaskGraphKind => 'task graph',
    _ => kind.trim().replaceAll('_', ' '),
  };
}

/// Returns the user-facing label for one automation draft status.
String _draftStatusLabel(String status) {
  final normalized = status.trim().replaceAll('_', ' ');
  return normalized.isEmpty ? 'draft' : normalized;
}

/// Returns the workflow name associated with one run when it is available.
String _runDefinitionLabel(
  List<AutomationDefinition> definitions,
  AutomationRun run,
) {
  return _definitionLabel(
    definitions,
    run.definitionId,
    fallback: 'Workflow run',
  );
}

/// Returns the workflow file name for one definition id.
String _definitionLabel(
  List<AutomationDefinition> definitions,
  String definitionId, {
  String fallback = 'Workflow file',
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

/// Returns the Operation name for one Operation id.
String _operationLabel(
  List<AutomationRunSetup> operations,
  String operationId, {
  String fallback = 'Operation',
}) {
  for (final operation in operations) {
    if (operation.id == operationId) {
      return operation.name;
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

/// Returns the first usable codebase id for an Operation dialog.
String _initialCodebaseId(
  List<AutomationCodebase> codebases,
  String selectedCodebaseId,
) {
  for (final codebase in codebases) {
    if (codebase.id == selectedCodebaseId) {
      return codebase.id;
    }
  }
  return codebases.isEmpty ? '' : codebases.first.id;
}

/// Returns the first usable target id for an Operation dialog.
String _initialTargetId({
  required List<AutomationCodebase> codebases,
  required List<AutomationRuntimeTarget> targets,
  required String codebaseId,
  required String selectedTargetId,
}) {
  final options = _targetOptionsForCodebase(targets, codebaseId);
  final codebase = _codebaseForId(codebases, codebaseId);
  if (codebase != null &&
      options.any((target) => target.id == codebase.runtimeTargetId)) {
    return codebase.runtimeTargetId;
  }
  if (options.any((target) => target.id == selectedTargetId)) {
    return selectedTargetId;
  }
  return options.isEmpty ? '' : options.first.id;
}

/// Returns targets eligible for the selected codebase.
List<AutomationRuntimeTarget> _targetOptionsForCodebase(
  List<AutomationRuntimeTarget> targets,
  String codebaseId,
) {
  if (codebaseId.trim().isEmpty) {
    return targets;
  }
  return <AutomationRuntimeTarget>[
    for (final target in targets)
      if (target.allowedCodebaseIds.isEmpty ||
          target.allowedCodebaseIds.contains(codebaseId))
        target,
  ];
}

/// Finds one codebase by catalog id.
AutomationCodebase? _codebaseForId(
  List<AutomationCodebase> codebases,
  String codebaseId,
) {
  for (final codebase in codebases) {
    if (codebase.id == codebaseId) {
      return codebase;
    }
  }
  return null;
}

/// Builds the source-control safety policy chosen in the Operation dialog.
Map<String, dynamic> _operationPolicyFromDialogResult(
  _RunSetupDialogResult result,
) {
  return _operationPolicyFromSelections(
    codebaseId: result.codebaseId,
    runtimeTargetId: result.runtimeTargetId,
    sourceControlPolicy: result.sourceControlPolicy,
  );
}

/// Builds a structured Operation safety policy from typed selections.
Map<String, dynamic> _operationPolicyFromSelections({
  required String codebaseId,
  required String runtimeTargetId,
  required String sourceControlPolicy,
}) {
  if (sourceControlPolicy != _operationSafetyOpenPROnly) {
    return const <String, dynamic>{};
  }
  return <String, dynamic>{
    'source_control': _operationSafetyOpenPROnly,
    'destructive_action': 'deny',
    'allowed_tools': _operationSourceControlTools,
    'allowed_mcp_servers': const <String>['sourcecontrol'],
    if (codebaseId.isNotEmpty) 'allowed_codebases': <String>[codebaseId],
    if (runtimeTargetId.isNotEmpty)
      'allowed_targets': <String>[runtimeTargetId],
  };
}

/// Reports whether one Operation should bind a codebase.
bool _operationNeedsCodebase(AutomationDefinition definition) {
  final setupFields = _workflowRunSetupSetupFields(definition.body);
  if (setupFields.any(_isCodebaseBackedInputName)) {
    return true;
  }
  final identity = '${definition.id} ${definition.name}'.toLowerCase();
  return identity.contains('coding') || identity.contains('codex');
}

/// Reports whether one Operation should bind a Computer or Server.
bool _operationNeedsTarget(AutomationDefinition definition) {
  return _operationNeedsCodebase(definition);
}

/// Reports whether a workflow input should come from a codebase record.
bool _isCodebaseBackedInputName(String name) {
  return const <String>{
    'repository_path',
    'repo_path',
    'default_remote',
    'remote',
    'default_branch',
    'base_branch',
    'provider_repository',
    'go_module_path',
  }.contains(name.trim());
}

/// Returns the user-facing source-control policy label.
String _operationSourceControlPolicyLabel(String policy) {
  return _operationSafetyLabels[policy.trim()] ??
      (policy.trim().isEmpty
          ? 'Open PR only'
          : _stateMachineDisplayName(policy));
}

/// Finds one workflow file by id.
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

/// Returns concise product-facing status for a workflow run.
String _runSubtitle(AutomationRun run) {
  final state = run.state.trim();
  if (state.isEmpty) {
    return _draftStatusLabel(run.status);
  }
  return state;
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

/// Returns the user-facing label for one Operation preview status.
String _operationPreviewStatusLabel(String status) {
  return switch (status.trim()) {
    'ready' => 'ready',
    'needs_input' => 'Needs Setup',
    'blocked' => 'blocked',
    _ => status.trim().isEmpty ? 'unknown' : _stateMachineDisplayName(status),
  };
}

/// Returns the user-facing label for one Operation policy status.
String _operationPolicyStatusLabel(String status) {
  return switch (status.trim()) {
    'allowed' => 'allowed',
    'blocked' => 'blocked',
    _ => status.trim().isEmpty ? 'unknown' : _stateMachineDisplayName(status),
  };
}

/// Builds display-safe resolved input rows for an Operation preview.
List<String> _operationPreviewInputRows(AutomationOperationPreview preview) {
  final keys = preview.resolvedInput.keys.toList()..sort();
  if (keys.isEmpty) {
    return const <String>['No resolved inputs'];
  }
  return <String>[
    for (final key in keys)
      '${_stateMachineDisplayName(key)}: ${_displayPreviewValue(preview.resolvedInput[key])}',
  ];
}

/// Converts preview values to compact display-safe text.
String _displayPreviewValue(Object? value) {
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

/// Builds setup rows for one saved Operation.
List<String> _operationSetupRows(
  AutomationRunSetup setup, {
  required List<AutomationDefinition> definitions,
  required List<AutomationCodebase> codebases,
  required List<AutomationRuntimeTarget> targets,
}) {
  return <String>[
    'Operation: ${setup.name}',
    'Workflow file: ${_definitionLabel(definitions, setup.definitionId)}',
    if (setup.codebaseId.isNotEmpty)
      'Codebase: ${_codebaseLabel(codebases, setup.codebaseId)}',
    if (setup.runtimeTargetId.isNotEmpty)
      'Run on: ${_targetLabel(targets, setup.runtimeTargetId)}',
    if (setup.policy['source_control'] != null)
      'Safety: ${_operationSourceControlPolicyLabel('${setup.policy['source_control']}')}',
    if (setup.updatedAt.isNotEmpty) 'Updated: ${setup.updatedAt}',
  ];
}

/// Builds saved input rows for one Operation.
List<String> _operationInputRows(AutomationRunSetup setup) {
  final keys = setup.input.keys.toList()..sort();
  if (keys.isEmpty) {
    return const <String>['No saved default inputs'];
  }
  return <String>[
    for (final key in keys)
      '${_stateMachineDisplayName(key)}: ${_displayPreviewValue(setup.input[key])}',
  ];
}

/// Builds target binding rows for one Operation.
List<String> _operationTargetRows(
  AutomationRunSetup setup, {
  required List<AutomationCodebase> codebases,
  required List<AutomationRuntimeTarget> targets,
}) {
  return <String>[
    if (setup.runtimeTargetId.isEmpty) 'Run on: not selected',
    if (setup.runtimeTargetId.isNotEmpty)
      'Run on: ${_targetLabel(targets, setup.runtimeTargetId)}',
    if (setup.codebaseId.isNotEmpty)
      'Allowed codebase: ${_codebaseLabel(codebases, setup.codebaseId)}',
    if (_stringListFromMap(setup.policy, 'allowed_targets').isNotEmpty)
      'Allowed targets: ${_stringListFromMap(setup.policy, 'allowed_targets').map((targetId) => _targetLabel(targets, targetId)).join(', ')}',
  ];
}

/// Builds schedule rows for one Operation.
List<String> _operationScheduleRows(AutomationRunSetup setup) {
  final schedule = setup.schedule;
  if (!_operationHasSchedule(setup)) {
    return const <String>['Schedule: manual only'];
  }
  return <String>[
    'Schedule: ${_operationScheduleLabel(schedule)}',
    'Status: ${_operationScheduleEnabled(schedule) ? 'enabled' : 'paused'}',
    if (_stringFromMap(schedule, 'quiet_hours_start').isNotEmpty ||
        _stringFromMap(schedule, 'quiet_hours_end').isNotEmpty)
      'Quiet hours: ${_stringFromMap(schedule, 'quiet_hours_start')} - ${_stringFromMap(schedule, 'quiet_hours_end')}',
    if (_stringFromMap(schedule, 'stop_at').isNotEmpty)
      'Stop at: ${_stringFromMap(schedule, 'stop_at')}',
    if (_intFromMap(schedule, 'max_runs') > 0)
      'Max runs: ${_intFromMap(schedule, 'max_runs')}',
  ];
}

/// Builds policy rows for one Operation.
List<String> _operationSafetyRows(
  AutomationRunSetup setup, {
  required List<AutomationCodebase> codebases,
  required List<AutomationRuntimeTarget> targets,
}) {
  final policy = setup.policy;
  if (policy.isEmpty) {
    return const <String>['Safety: default Operation policy'];
  }
  return <String>[
    if (_stringFromMap(policy, 'source_control').isNotEmpty)
      'Source control: ${_operationSourceControlPolicyLabel(_stringFromMap(policy, 'source_control'))}',
    if (_stringFromMap(policy, 'destructive_action').isNotEmpty)
      'Destructive actions: ${_operationDestructiveActionLabel(_stringFromMap(policy, 'destructive_action'))}',
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

/// Builds run rows for one Operation.
List<String> _operationRunRows(
  AutomationRunSetup setup,
  List<AutomationRun> runs, {
  required List<AutomationDefinition> definitions,
}) {
  final matching = runs
      .where((run) => run.definitionId == setup.definitionId)
      .toList();
  if (matching.isEmpty) {
    return const <String>['No runs for this Operation'];
  }
  return <String>[
    'Runs: ${matching.length}',
    for (final run in matching.take(8))
      '${_runDefinitionLabel(definitions, run)}: ${_draftStatusLabel(run.status)}${run.state.isEmpty ? '' : ' / ${run.state}'}',
  ];
}

/// Reports whether one Operation has a saved schedule.
bool _operationHasSchedule(AutomationRunSetup setup) {
  final schedule = setup.schedule;
  if (schedule.isEmpty) {
    return false;
  }
  return _operationScheduleEnabled(schedule) ||
      _stringFromMap(schedule, 'cron').isNotEmpty ||
      _stringFromMap(schedule, 'stop_at').isNotEmpty;
}

/// Reports whether one saved schedule is enabled.
bool _operationScheduleEnabled(Map<String, dynamic> schedule) {
  return schedule['enabled'] == true ||
      '${schedule['enabled'] ?? ''}'.trim().toLowerCase() == 'true';
}

/// Returns a product-facing schedule label.
String _operationScheduleLabel(Map<String, dynamic> schedule) {
  final cron = _stringFromMap(schedule, 'cron');
  if (cron.isEmpty) {
    return _operationScheduleEnabled(schedule) ? 'Enabled' : 'Manual only';
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
String _operationDestructiveActionLabel(String value) {
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

/// Builds operation routing rows for one Computer or Server target.
List<String> _targetOperationRows(
  AutomationRuntimeTarget target,
  List<AutomationRunSetup> operations,
) {
  return <String>[
    'Saved Operations: ${operations.length}',
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
    this.titleWidget,
    this.badges = const <String>[],
    this.selected = false,
    this.onTap,
  });

  final String title;
  final Widget? titleWidget;
  final String subtitle;
  final List<String> badges;
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
                    titleWidget ??
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
            ],
          ),
        ),
      ),
    );
  }
}

List<AutomationDefinition> _filterDefinitions(
  List<AutomationDefinition> definitions,
  String query,
) {
  final needle = query.toLowerCase();
  return definitions.where((definition) {
    return definition.name.toLowerCase().contains(needle) ||
        _draftKindLabel(definition.kind).toLowerCase().contains(needle);
  }).toList();
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

List<AutomationRunSetup> _filterRunSetups(
  List<AutomationRunSetup> setups,
  String query, {
  List<AutomationDefinition> definitions = const <AutomationDefinition>[],
}) {
  final needle = query.toLowerCase();
  return setups.where((setup) {
    return setup.name.toLowerCase().contains(needle) ||
        setup.description.toLowerCase().contains(needle) ||
        _definitionLabel(
          definitions,
          setup.definitionId,
        ).toLowerCase().contains(needle);
  }).toList();
}

/// Filters Operations that have a saved schedule.
List<AutomationRunSetup> _filterScheduledOperations(
  List<AutomationRunSetup> setups,
  String query, {
  List<AutomationDefinition> definitions = const <AutomationDefinition>[],
}) {
  return _filterRunSetups(
    setups.where(_operationHasSchedule).toList(),
    query,
    definitions: definitions,
  );
}

List<AutomationCodebase> _filterCodebases(
  List<AutomationCodebase> codebases,
  String query,
) {
  final needle = query.toLowerCase();
  return codebases.where((codebase) {
    return codebase.name.toLowerCase().contains(needle) ||
        codebase.repositoryPath.toLowerCase().contains(needle) ||
        codebase.providerRepository.toLowerCase().contains(needle) ||
        codebase.aliases.any((alias) => alias.toLowerCase().contains(needle));
  }).toList();
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

List<AutomationCapability> _filterCapabilities(
  List<AutomationCapability> capabilities,
  String query,
) {
  final needle = query.toLowerCase();
  return capabilities.where((capability) {
    return capability.id.toLowerCase().contains(needle) ||
        capability.name.toLowerCase().contains(needle) ||
        capability.label.toLowerCase().contains(needle) ||
        capability.description.toLowerCase().contains(needle) ||
        _capabilityKindLabel(capability.kind).toLowerCase().contains(needle) ||
        _capabilityAvailabilityLabel(
          capability.availability.status,
        ).toLowerCase().contains(needle);
  }).toList();
}

String _capabilityKindLabel(String kind) {
  return switch (kind.trim()) {
    'mcp_server' => 'MCP server',
    'mcp_tool' => 'MCP tool',
    'agent_profile' => 'agent profile',
    'workflow_action' => 'workflow action',
    'node_preset' => 'node preset',
    'node_scenario' => 'scenario',
    'command' => 'command',
    _ => kind.trim().replaceAll('_', ' '),
  };
}

String _capabilityAvailabilityLabel(String status) {
  return switch (status.trim()) {
    'available' => 'available',
    'unavailable' => 'Needs Setup',
    'needs_check' => 'Needs Review',
    _ => status.trim().isEmpty ? 'unknown' : status.trim().replaceAll('_', ' '),
  };
}

List<String> _capabilityInvocationRows(AutomationCapability capability) {
  final invocation = capability.invocation;
  return <String>[
    if (_stringFromMap(invocation, 'direct_tool_name').isNotEmpty)
      'Direct: ${_stringFromMap(invocation, 'direct_tool_name')}',
    if (_stringFromMap(invocation, 'workflow_action').isNotEmpty)
      'Workflow action: ${_stringFromMap(invocation, 'workflow_action')}',
    if (_stringFromMap(invocation, 'command_template').isNotEmpty)
      'Command: ${_stringFromMap(invocation, 'command_template')}',
    if (_stringFromMap(invocation, 'mcp_server').isNotEmpty)
      'MCP server: ${_stringFromMap(invocation, 'mcp_server')}',
    if (_stringFromMap(invocation, 'mcp_tool').isNotEmpty)
      'MCP tool: ${_stringFromMap(invocation, 'mcp_tool')}',
    if (_stringFromMap(invocation, 'agent_profile_id').isNotEmpty)
      'Agent profile: ${_stringFromMap(invocation, 'agent_profile_id')}',
    if (_stringFromMap(invocation, 'node_preset_id').isNotEmpty)
      'Preset: ${_stringFromMap(invocation, 'node_preset_id')}',
    if (_stringFromMap(invocation, 'node_scenario_id').isNotEmpty)
      'Scenario: ${_stringFromMap(invocation, 'node_scenario_id')}',
  ];
}

List<String> _capabilitySafetyRows(AutomationCapability capability) {
  final riskLevel = _stringFromMap(capability.risk, 'level');
  final confirmationRequired =
      capability.contract['confirmation_required'] == true ||
      capability.risk['requires_confirmation'] == true;
  return <String>[
    if (riskLevel.isNotEmpty) 'Risk: $riskLevel',
    confirmationRequired
        ? 'Confirmation: required'
        : 'Confirmation: not required',
  ];
}

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

List<String> _splitCodebaseAliases(String value) {
  return value
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}

String _stableCodebaseId(String name) {
  final buffer = StringBuffer();
  var lastWasSeparator = false;
  for (final unit in name.trim().toLowerCase().codeUnits) {
    final isLetter = unit >= 97 && unit <= 122;
    final isDigit = unit >= 48 && unit <= 57;
    if (isLetter || isDigit) {
      buffer.writeCharCode(unit);
      lastWasSeparator = false;
      continue;
    }
    if (!lastWasSeparator && buffer.isNotEmpty) {
      buffer.write('_');
      lastWasSeparator = true;
    }
  }
  final id = buffer.toString().replaceFirst(RegExp(r'_+$'), '');
  return id.isEmpty ? 'codebase' : id;
}

List<AutomationRun> _filterRuns(
  List<AutomationRun> runs,
  String query, {
  List<AutomationDefinition> definitions = const <AutomationDefinition>[],
}) {
  final needle = query.toLowerCase();
  return runs.where((run) {
    return _runDefinitionLabel(
          definitions,
          run,
        ).toLowerCase().contains(needle) ||
        _draftKindLabel(run.kind).toLowerCase().contains(needle) ||
        _draftStatusLabel(run.status).toLowerCase().contains(needle) ||
        run.state.toLowerCase().contains(needle);
  }).toList();
}

/// Builds artifact rows from workflow run output.
List<_OperationArtifactItem> _operationArtifactsForRuns(
  List<AutomationRun> runs, {
  required List<AutomationDefinition> definitions,
}) {
  final artifacts = <_OperationArtifactItem>[];
  for (final run in runs) {
    final workflowLabel = _runDefinitionLabel(definitions, run);
    artifacts.addAll(
      _operationArtifactsForRun(run, workflowLabel: workflowLabel),
    );
  }
  return artifacts;
}

/// Builds artifact rows from one workflow run output.
List<_OperationArtifactItem> _operationArtifactsForRun(
  AutomationRun run, {
  required String workflowLabel,
}) {
  final output = run.output;
  final artifacts = <_OperationArtifactItem>[];
  void addArtifact(String title, Object? value) {
    final text = _displayPreviewValue(value).trim();
    if (text.isEmpty) {
      return;
    }
    artifacts.add(
      _OperationArtifactItem(
        run: run,
        title: title,
        subtitle: text,
        workflowLabel: workflowLabel,
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

/// Filters artifact rows by user-facing labels.
List<_OperationArtifactItem> _filterOperationArtifacts(
  List<_OperationArtifactItem> artifacts,
  String query,
) {
  final needle = query.toLowerCase();
  return artifacts.where((artifact) {
    return artifact.title.toLowerCase().contains(needle) ||
        artifact.subtitle.toLowerCase().contains(needle) ||
        artifact.workflowLabel.toLowerCase().contains(needle);
  }).toList();
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
  if (areaId == _automationWorkflowAreaDrafts ||
      areaId == _automationWorkflowAreaActions) {
    return automationWorkflowKind;
  }
  if (areaId == _automationTaskAreaDrafts ||
      areaId == _automationTaskAreaNodes) {
    return automationTaskGraphKind;
  }
  return null;
}

/// Reports whether a draft belongs in the requested authoring section.
bool _draftMatchesSectionKind(AutomationDraft draft, String kind) {
  if (kind == automationWorkflowKind) {
    return _isWorkflowFileKind(draft.kind);
  }
  return draft.kind == kind;
}

/// Reports whether a draft kind is a workflow file in the Automations UI.
bool _isWorkflowFileKind(String kind) {
  final normalized = kind.trim();
  return normalized == automationWorkflowKind ||
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

/// Returns a canonical task-graph body for an editable draft.
Map<String, dynamic> _normalizedTaskGraphBody(AutomationDraft draft) {
  final body = _map(draft.body);
  return <String, dynamic>{
    'kind': automationTaskGraphKind,
    'id': '${body['id'] ?? draft.id}',
    'nodes': _taskGraphNodes(body),
  };
}

/// Returns the builder-editable body shape for workflow and task drafts.
Map<String, dynamic> _normalizedWorkflowBuilderBody(AutomationDraft draft) {
  final body = _map(draft.body);
  final bodyKind = '${body['kind'] ?? ''}'.trim();
  if (draft.kind == automationWorkflowKind &&
      bodyKind == automationWorkflowKind) {
    return <String, dynamic>{
      'kind': automationWorkflowKind,
      'id': '${body['id'] ?? draft.id}',
      'nodes': _workflowDefinitionNodes(body),
    };
  }
  if (draft.kind == automationTaskGraphKind) {
    return _normalizedTaskGraphBody(draft);
  }
  return <String, dynamic>{
    'kind': _stateMachineBodyKind,
    'id': '${body['id'] ?? draft.id}',
    'states': _stateMachineTaskNodes(body),
  };
}

/// Returns graph-builder nodes from the current authoring body.
List<Map<String, dynamic>> _workflowBuilderNodes(Map<String, dynamic> body) {
  final kind = '${body['kind'] ?? ''}'.trim();
  if (kind == automationWorkflowKind) {
    return _workflowDefinitionNodes(body);
  }
  if (kind == _stateMachineBodyKind) {
    return _stateMachineTaskNodes(body);
  }
  return _taskGraphNodes(body);
}

/// Reports whether a draft body uses the current workflow graph contract.
bool _isWorkflowGraphDraft(AutomationDraft? draft, Map<String, dynamic> body) {
  return draft?.kind == automationWorkflowKind &&
      '${body['kind'] ?? ''}'.trim() == automationWorkflowKind;
}

/// Returns graph-builder nodes decorated with dependencies from workflow edges.
List<Map<String, dynamic>> _workflowDefinitionNodes(Map<String, dynamic> body) {
  final dependenciesByNode = <String, Set<String>>{};
  for (final edge in _list(body['edges']).map(_map)) {
    final from = '${_map(edge['from'])['node'] ?? ''}'.trim();
    final to = '${_map(edge['to'])['node'] ?? ''}'.trim();
    if (from.isEmpty || to.isEmpty) {
      continue;
    }
    dependenciesByNode.putIfAbsent(to, () => <String>{}).add(from);
  }
  return _taskGraphNodes(body).map((node) {
    final next = Map<String, dynamic>.from(node)..remove('depends_on');
    final dependencies = List<String>.of(
      dependenciesByNode[_nodeId(node)] ?? const <String>{},
    )..sort();
    if (dependencies.isNotEmpty) {
      next['depends_on'] = dependencies;
    }
    return next;
  }).toList();
}

/// Builds a canonical workflow definition body from graph-builder nodes.
Map<String, dynamic> _workflowBodyFromBuilderNodes({
  required Map<String, dynamic> original,
  required String id,
  required String name,
  required String description,
  required List<Map<String, dynamic>> nodes,
}) {
  final body = <String, dynamic>{
    ...original,
    'apiVersion': '${original['apiVersion'] ?? automationWorkflowApiVersion}',
    'kind': automationWorkflowKind,
    'id': id,
    'name': name,
    'description': description,
    'nodes': _workflowNodesForSave(nodes),
    'edges': _workflowEdgesForSave(nodes),
  };
  body
    ..remove('states')
    ..remove('initial');
  return body;
}

/// Returns workflow-schema nodes by removing UI-only dependency data.
List<Map<String, dynamic>> _workflowNodesForSave(
  List<Map<String, dynamic>> nodes,
) {
  return <Map<String, dynamic>>[
    for (final node in nodes)
      Map<String, dynamic>.from(node)
        ..remove('depends_on')
        ..remove('transitions')
        ..remove('on_entry'),
  ];
}

/// Converts UI dependency lists into workflow-schema edge records.
List<Map<String, dynamic>> _workflowEdgesForSave(
  List<Map<String, dynamic>> nodes,
) {
  final edges = <Map<String, dynamic>>[];
  for (final node in nodes) {
    final target = _nodeId(node);
    if (target.isEmpty) {
      continue;
    }
    for (final dependency in _nodeDependsOn(node)) {
      edges.add(<String, dynamic>{
        'from': <String, dynamic>{'node': dependency},
        'to': <String, dynamic>{'node': target},
      });
    }
  }
  return edges;
}

/// Returns detached task nodes from a draft body.
List<Map<String, dynamic>> _taskGraphNodes(Map<String, dynamic> body) {
  return _list(
    body['nodes'],
  ).map((node) => Map<String, dynamic>.from(_map(node))).toList();
}

/// Reports whether a state-machine body already uses durable task states.
bool _stateMachineHasTaskStates(Map<String, dynamic> body) {
  return _list(body['states']).map(_map).any(_stateLooksLikeTaskNode);
}

/// Returns task-state entries that the visual workflow builder can edit.
List<Map<String, dynamic>> _stateMachineTaskNodes(Map<String, dynamic> body) {
  final nodes = <Map<String, dynamic>>[];
  for (final state in _list(body['states']).map(_map)) {
    if (!_stateLooksLikeTaskNode(state)) {
      continue;
    }
    final node = Map<String, dynamic>.from(state);
    node['type'] = 'task';
    node.remove('on_entry');
    node.remove('transitions');
    nodes.add(node);
  }
  return nodes;
}

/// Reports whether a state definition belongs to the task-state model.
bool _stateLooksLikeTaskNode(Map<String, dynamic> state) {
  return '${state['type'] ?? ''}'.trim() == 'task' ||
      '${state['uses'] ?? ''}'.trim().isNotEmpty ||
      _list(state['depends_on']).isNotEmpty ||
      '${state['timeout'] ?? ''}'.trim().isNotEmpty ||
      '${state['retry'] ?? ''}'.trim().isNotEmpty ||
      '${state['retry_delay'] ?? ''}'.trim().isNotEmpty;
}

/// Converts one graph-builder node into a durable state-machine task state.
Map<String, dynamic> _stateMachineTaskStateFromNode(Map<String, dynamic> node) {
  final state = Map<String, dynamic>.from(node);
  state['type'] = 'task';
  state.remove('on_entry');
  state.remove('transitions');
  final dependencies = _nodeDependsOn(state);
  if (dependencies.isEmpty) {
    state.remove('depends_on');
  } else {
    state['depends_on'] = dependencies;
  }
  return state;
}

/// Groups task nodes into dependency stages for visual graph rendering.
List<List<Map<String, dynamic>>> _taskGraphLevels(
  List<Map<String, dynamic>> nodes,
) {
  final byId = <String, Map<String, dynamic>>{
    for (final node in nodes)
      if (_nodeId(node).isNotEmpty) _nodeId(node): node,
  };
  final orderedIds = nodes.map(_nodeId).where((id) => id.isNotEmpty).toList();
  final remaining = byId.keys.toSet();
  final levels = <List<Map<String, dynamic>>>[];
  while (remaining.isNotEmpty) {
    final readyIds = orderedIds.where((id) {
      if (!remaining.contains(id)) {
        return false;
      }
      final dependencies = _nodeDependsOn(byId[id] ?? const {});
      return dependencies.every(
        (dependency) => !remaining.contains(dependency),
      );
    }).toList();
    final currentIds = readyIds.isEmpty
        ? orderedIds.where(remaining.contains).toList()
        : readyIds;
    levels.add(
      currentIds
          .map((id) => byId[id])
          .whereType<Map<String, dynamic>>()
          .toList(),
    );
    remaining.removeAll(currentIds);
  }
  return levels;
}

/// Flattens task levels back into ordered node data.
List<Map<String, dynamic>> _flattenTaskGraphLevels(
  List<List<Map<String, dynamic>>> levels,
) {
  return <Map<String, dynamic>>[
    for (final level in levels)
      for (final node in level) Map<String, dynamic>.from(node),
  ];
}

/// Returns the visual stage index for a node id.
int _stageIndexForNode(List<List<Map<String, dynamic>>> levels, String nodeId) {
  for (var stageIndex = 0; stageIndex < levels.length; stageIndex++) {
    if (levels[stageIndex].any((node) => _nodeId(node) == nodeId)) {
      return stageIndex;
    }
  }
  return -1;
}

/// Reports whether a node already depends on another node through any path.
bool _nodeDependsOnPath(
  List<Map<String, dynamic>> nodes,
  String startNodeId,
  String targetNodeId,
) {
  final byId = <String, Map<String, dynamic>>{
    for (final node in nodes)
      if (_nodeId(node).isNotEmpty) _nodeId(node): node,
  };
  final visited = <String>{};
  bool visit(String nodeId) {
    if (!visited.add(nodeId)) {
      return false;
    }
    final node = byId[nodeId];
    if (node == null) {
      return false;
    }
    for (final dependency in _nodeDependsOn(node)) {
      if (dependency == targetNodeId || visit(dependency)) {
        return true;
      }
    }
    return false;
  }

  return visit(startNodeId);
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
    'workflow.run' => Icons.account_tree_outlined,
    'workflow.signal' => Icons.flag_outlined,
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
    'workflow.run' => 'Run Workflow',
    'workflow.signal' => 'Signal',
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
    'workflow.run' => 'Nested workflow run',
    'workflow.signal' => 'Workflow signal',
    _ => 'Workflow action',
  };
}

/// Returns the visual accent color for a task action type.
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
    'workflow.run' => colors.orbit,
    'workflow.signal' => colors.warningText,
    _ => colors.green,
  };
}

/// Returns a task node id.
String _nodeId(Map<String, dynamic> node) {
  return '${node['id'] ?? ''}'.trim();
}

/// Returns a task node action type.
String _nodeUses(Map<String, dynamic> node) {
  return '${node['uses'] ?? ''}'.trim();
}

/// Returns dependency ids for one task node.
List<String> _nodeDependsOn(Map<String, dynamic> node) {
  return _list(
    node['depends_on'],
  ).map((item) => '$item'.trim()).where((item) => item.isNotEmpty).toList();
}

/// Reports whether two task nodes share an immediate dependency edge.
bool _nodesImmediatelyConnected(
  List<Map<String, dynamic>> nodes,
  String firstNodeId,
  String secondNodeId,
) {
  if (firstNodeId.isEmpty ||
      secondNodeId.isEmpty ||
      firstNodeId == secondNodeId) {
    return false;
  }
  final first = _nodeById(nodes, firstNodeId);
  final second = _nodeById(nodes, secondNodeId);
  return _nodeDependsOn(first).contains(secondNodeId) ||
      _nodeDependsOn(second).contains(firstNodeId);
}

/// Returns one task node by id, or an empty map when absent.
Map<String, dynamic> _nodeById(
  List<Map<String, dynamic>> nodes,
  String nodeId,
) {
  for (final node in nodes) {
    if (_nodeId(node) == nodeId) {
      return node;
    }
  }
  return const <String, dynamic>{};
}

/// Returns a copy of a node with one dependency removed.
Map<String, dynamic> _nodeWithoutDependency(
  Map<String, dynamic> node,
  String dependencyId,
) {
  final next = Map<String, dynamic>.from(node);
  final dependencies = _nodeDependsOn(
    next,
  ).where((id) => id != dependencyId).toList();
  if (dependencies.isEmpty) {
    next.remove('depends_on');
  } else {
    next['depends_on'] = dependencies;
  }
  return next;
}

/// Returns a node timeout value.
String _nodeTimeout(Map<String, dynamic> node) {
  return '${node['timeout'] ?? ''}'.trim();
}

/// Returns configured retry attempts for one node.
String _nodeRetryAttempts(Map<String, dynamic> node) {
  final retry = '${node['retry'] ?? ''}'.trim();
  if (retry.isNotEmpty) {
    return retry;
  }
  final retries = _map(node['retries']);
  return '${retries['attempts'] ?? ''}'.trim();
}

/// Returns configured retry delay for one node.
String _nodeRetryDelay(Map<String, dynamic> node) {
  final delay = '${node['retry_delay'] ?? ''}'.trim();
  if (delay.isNotEmpty) {
    return delay;
  }
  final retries = _map(node['retries']);
  return '${retries['delay'] ?? ''}'.trim();
}

/// Returns pretty JSON object text for editing.
String _jsonText(Map<String, dynamic> value) {
  if (value.isEmpty) {
    return '{}';
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}

/// Returns newline text for list values.
String _linesText(List<dynamic> value) {
  return value.map((item) => '$item').join('\n');
}

/// Builds a unique node id for a task action name.
String _nextTaskGraphNodeId(
  List<Map<String, dynamic>> nodes,
  String actionName,
) {
  final base = actionName.replaceAll('.', '_').replaceAll('-', '_');
  final existing = nodes.map(_nodeId).toSet();
  var index = nodes.length + 1;
  var id = '${base}_$index';
  while (existing.contains(id)) {
    index++;
    id = '${base}_$index';
  }
  return id;
}

/// Provides valid starting arguments for one task action type.
Map<String, dynamic> _defaultTaskGraphActionArgs(String actionName) {
  return switch (actionName) {
    'tool.call' => <String, dynamic>{
      'name': '',
      'domain_id': '',
      'arguments': <String, dynamic>{},
    },
    'mcp.call' => <String, dynamic>{
      'server_id': '',
      'endpoint': '',
      'tool': '',
      'arguments': <String, dynamic>{},
    },
    'command.execute' => <String, dynamic>{
      'template_id': '',
      'cwd': '',
      'parameters': <String, dynamic>{},
    },
    'data.assert' => <String, dynamic>{'checks': <dynamic>[]},
    'data.defaults' => <String, dynamic>{
      'input': <String, dynamic>{},
      'defaults': <String, dynamic>{},
    },
    'workflow.run' => <String, dynamic>{
      'workflow': '',
      'input': <String, dynamic>{},
    },
    _ => <String, dynamic>{},
  };
}

List<dynamic> _stateActions(Map<String, dynamic> body) {
  final states = _list(body['states']);
  final actions = <dynamic>[];
  for (final state in states) {
    actions.addAll(_list(_map(state)['on_entry']));
  }
  return actions;
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
