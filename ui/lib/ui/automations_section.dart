/// Renders root-level Automations operations and builder surfaces.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import 'theme.dart';
import '../domain/models_automation.dart';
import 'panels/panels.dart';

const String _automationPanelOperations = 'operations';
const String _automationPanelWorkflows = 'workflows';
const String _automationPanelTasks = 'tasks';
const String _automationOperationsAreaInbox = 'operations_inbox';
const String _automationOperationsAreaPublished = 'operations_published';
const String _automationOperationsAreaRuns = 'operations_runs';
const String _automationWorkflowAreaDrafts = 'workflow_drafts';
const String _automationWorkflowAreaTemplates = 'workflow_templates';
const String _automationWorkflowAreaActions = 'workflow_actions';
const String _automationTaskAreaDrafts = 'task_drafts';
const String _automationTaskAreaTemplates = 'task_templates';
const String _automationTaskAreaNodes = 'task_nodes';

const String _automationDetailOverview = 'overview';
const String _automationDetailBuilder = 'builder';
const String _automationDetailSteps = 'steps';
const String _automationDetailMap = 'map';
const String _automationDetailHistory = 'history';
const String _automationDetailSafety = 'safety';

const Set<String> _taskGraphActionNames = <String>{
  'mcp.call',
  'tool.call',
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
      filterHint: 'Filter runs and definitions...',
      detailModes: _detailModesForPanel(_automationPanelOperations),
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
  String _detailModeId = _automationDetailOverview;

  /// Triggers the first data load after the focused panel is attached.
  @override
  void initState() {
    super.initState();
    _taskGraphActionIntents = _TaskGraphActionIntentController();
    if (widget.panelId == _automationPanelTasks) {
      _detailModeId = _automationDetailBuilder;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.controller.automationDefinitions.isEmpty &&
          widget.controller.automationDrafts.isEmpty &&
          !widget.controller.automationsBusy) {
        unawaited(widget.controller.refreshAutomationsFromUi());
      }
    });
  }

  /// Releases command-panel intent controllers.
  @override
  void dispose() {
    _taskGraphActionIntents.dispose();
    super.dispose();
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
      onDetailModeSelected: (modeId) => setState(() => _detailModeId = modeId),
      detailBuilder: (modeId) => _AutomationDetailContent(
        controller: widget.controller,
        areaId: widget.panelId,
        modeId: modeId,
      ),
      areaDetailBuilder: (area, modeId) => _AutomationDetailContent(
        controller: widget.controller,
        areaId: area.id,
        modeId: modeId,
      ),
      areaTabbedDetailBuilder: (area, modeId, tabId) =>
          _AutomationDetailContent(
            controller: widget.controller,
            areaId: area.id,
            modeId: modeId,
            tabId: tabId,
          ),
      onAreaChanged: widget.onAreaChanged,
      areaActionsBuilder: (context, area) {
        if (area.id == _automationTaskAreaNodes) {
          return null;
        }
        return _AutomationPanelActions(
          controller: widget.controller,
          panelId: widget.panelId,
          areaId: area.id,
        );
      },
      detailModesBuilder: _detailModesForArea,
      detailActionsBuilder: (context, area, mode) {
        return _AutomationDetailActions(
          controller: widget.controller,
          panelId: widget.panelId,
          areaId: area.id,
        );
      },
      filterHint: widget.filterHint,
      split: widget.split,
    );
    if (widget.panelId != _automationPanelTasks) {
      return shell;
    }
    return _TaskGraphActionIntentScope(
      notifier: _taskGraphActionIntents,
      child: shell,
    );
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
          title: 'Published',
          icon: Icons.inventory_2_outlined,
          builder: (query) => _AutomationPublishedContent(
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
          title: 'Drafts',
          icon: Icons.edit_note_outlined,
          builder: (query) => _AutomationDraftsContent(
            controller: widget.controller,
            query: query,
            kind: 'state_machine',
            emptyLabel: 'No workflow drafts',
          ),
        ),
        SwitcherPanelArea(
          id: _automationWorkflowAreaTemplates,
          title: 'Templates',
          icon: Icons.library_books_outlined,
          builder: (query) => _AutomationTemplatesContent(
            controller: widget.controller,
            query: query,
            kind: 'state_machine',
          ),
        ),
        SwitcherPanelArea(
          id: _automationWorkflowAreaActions,
          title: 'Actions',
          icon: Icons.add_circle_outline,
          builder: (query) => _AutomationActionPaletteContent(
            controller: widget.controller,
            query: query,
            actionTypes: widget.controller.automationActionTypes,
          ),
        ),
      ];
    }
    if (widget.panelId == _automationPanelTasks) {
      return <SwitcherPanelArea>[
        SwitcherPanelArea(
          id: _automationTaskAreaDrafts,
          title: widget.title,
          icon: widget.icon,
          builder: (query) => _AutomationDraftsContent(
            controller: widget.controller,
            query: query,
            kind: 'task_graph',
            emptyLabel: 'No task graph drafts',
          ),
        ),
        SwitcherPanelArea(
          id: _automationTaskAreaTemplates,
          title: 'Templates',
          icon: Icons.library_books_outlined,
          builder: (query) => _AutomationTemplatesContent(
            controller: widget.controller,
            query: query,
            kind: 'task_graph',
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
    if (area.id == _automationWorkflowAreaTemplates ||
        area.id == _automationTaskAreaTemplates ||
        area.id == _automationWorkflowAreaActions) {
      return const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _automationDetailOverview,
          label: 'Overview',
          icon: Icons.info_outline,
        ),
      ];
    }
    return widget.detailModes;
  }
}

class _TaskGraphActionIntentController extends ChangeNotifier {
  String _actionName = '';
  int _revision = 0;

  String get actionName => _actionName;
  int get revision => _revision;

  /// Publishes one left-panel task action request to the active graph editor.
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

  /// Finds the current task action intent publisher for the Tasks screen.
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
  });

  final AgentAwesomeAppController controller;
  final String panelId;
  final String areaId;

  /// Builds common and section-specific Automations header actions.
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (panelId != _automationPanelTasks) ...<Widget>[
          PanelIconButton(
            icon: Icons.refresh,
            tooltip: 'Refresh automations',
            onPressed: controller.automationsBusy
                ? null
                : () => unawaited(controller.refreshAutomationsFromUi()),
          ),
          const SizedBox(width: 8),
        ],
        if (panelId == _automationPanelWorkflows &&
            areaId == _automationWorkflowAreaDrafts)
          PanelIconButton(
            icon: Icons.add,
            tooltip: 'New workflow draft',
            onPressed: controller.automationsBusy
                ? null
                : () => unawaited(
                    controller.createAutomationDraftFromUi(
                      kind: 'state_machine',
                      name: 'New Workflow',
                    ),
                  ),
          ),
        if (panelId == _automationPanelTasks &&
            areaId == _automationTaskAreaDrafts)
          PanelIconButton(
            icon: Icons.add,
            tooltip: 'New task graph',
            onPressed: controller.automationsBusy
                ? null
                : () => unawaited(
                    controller.createAutomationDraftFromUi(
                      kind: 'task_graph',
                      name: 'New Task Graph',
                    ),
                  ),
          ),
      ],
    );
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
    if (areaId == _automationWorkflowAreaTemplates ||
        areaId == _automationTaskAreaTemplates) {
      final template = _selectedAutomationTemplateForArea(controller, areaId);
      return PanelIconButton(
        icon: Icons.add,
        tooltip: 'Use selected template',
        onPressed: controller.automationsBusy || template == null
            ? null
            : () => unawaited(
                controller.instantiateAutomationTemplateFromUi(template),
              ),
      );
    }
    final kind = _automationDraftKindForArea(areaId);
    if (kind != null ||
        panelId == _automationPanelWorkflows ||
        panelId == _automationPanelTasks) {
      final effectiveKind =
          kind ??
          (panelId == _automationPanelTasks ? 'task_graph' : 'state_machine');
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
      return PanelIconButton(
        icon: Icons.play_arrow,
        tooltip: 'Start selected automation',
        onPressed: controller.automationsBusy || definition == null
            ? null
            : () => unawaited(
                controller.startAutomationDefinitionFromUi(definition),
              ),
      );
    }
    return const SizedBox.shrink();
  }
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
          id: _automationDetailHistory,
          label: 'History',
          icon: Icons.history,
        ),
        CommandPanelDetailMode(
          id: _automationDetailSafety,
          label: 'Safety',
          icon: Icons.verified_user_outlined,
        ),
      ];
    case _automationPanelWorkflows:
      return const <CommandPanelDetailMode>[
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

  /// Builds published automation definitions.
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
          const PanelEmptyBlock(label: 'No published automations')
        else
          for (final definition in definitions)
            _DefinitionTile(controller: controller, definition: definition),
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
    final runs = _filterRuns(controller.automationRuns, query);
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
      controller.automationDrafts.where((draft) => draft.kind == kind).toList(),
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

class _AutomationTemplatesContent extends StatelessWidget {
  const _AutomationTemplatesContent({
    required this.controller,
    required this.query,
    required this.kind,
  });

  final AgentAwesomeAppController controller;
  final String query;
  final String kind;

  /// Builds template source rows for one authoring section.
  @override
  Widget build(BuildContext context) {
    final templates = _filterTemplates(
      controller.automationTemplates.where((template) {
        return _templateMatchesKind(template, kind);
      }).toList(),
      query,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: templates.isEmpty
          ? const <Widget>[PanelEmptyBlock(label: 'No matching templates')]
          : <Widget>[
              for (final template in templates)
                _TemplateTile(controller: controller, template: template),
            ],
    );
  }
}

class _AutomationActionPaletteContent extends StatelessWidget {
  const _AutomationActionPaletteContent({
    required this.controller,
    required this.query,
    required this.actionTypes,
  });

  final AgentAwesomeAppController controller;
  final String query;
  final List<AutomationActionType> actionTypes;

  /// Builds a workflow action palette for selected draft editing.
  @override
  Widget build(BuildContext context) {
    final selectedDraft = _selectedAutomationDraftForKind(
      controller,
      'state_machine',
    );
    return _TaskGraphActionPalette(
      actionTypes: actionTypes,
      query: query,
      onAddAction: (actionName) {
        if (selectedDraft == null || controller.automationsBusy) {
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
      'task_graph',
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
    required this.areaId,
    required this.modeId,
    this.tabId = '',
  });

  final AgentAwesomeAppController controller;
  final String areaId;
  final String modeId;
  final String tabId;

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
    if (areaId == _automationWorkflowAreaTemplates ||
        areaId == _automationTaskAreaTemplates) {
      return _TemplateDetail(
        template: _selectedAutomationTemplateForArea(controller, areaId),
      );
    }
    final draftKind = _automationDraftKindForArea(areaId);
    if (draftKind != null) {
      return _DraftDetail(
        controller: controller,
        modeId: modeId,
        draft: _selectedAutomationDraftForKind(controller, draftKind),
      );
    }
    if (areaId == _automationPanelWorkflows ||
        areaId == _automationPanelTasks) {
      final kind = areaId == _automationPanelTasks
          ? 'task_graph'
          : 'state_machine';
      return _DraftDetail(
        controller: controller,
        modeId: modeId,
        draft: _selectedAutomationDraftForKind(controller, kind),
      );
    }
    return _OperationsDetail(controller: controller, modeId: modeId);
  }
}

class _TemplateDetail extends StatelessWidget {
  const _TemplateDetail({required this.template});

  final AutomationTemplate? template;

  /// Builds details for the selected automation template.
  @override
  Widget build(BuildContext context) {
    final selectedTemplate = template;
    if (selectedTemplate == null) {
      return const PanelEmptyBlock(label: 'No template selected');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        PanelSectionBlock(
          title: 'Template',
          child: _DetailRows(
            rows: <String>[
              selectedTemplate.name,
              selectedTemplate.id,
              selectedTemplate.category,
              selectedTemplate.description,
            ],
          ),
        ),
      ],
    );
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
      _ => _OperationsRunOverview(
        run: controller.selectedAutomationRun,
        runCount: controller.automationRuns.length,
      ),
    };
  }
}

const Set<String> _automationOperationsAreaIds = <String>{
  _automationOperationsAreaInbox,
  _automationOperationsAreaPublished,
  _automationOperationsAreaRuns,
};

class _DraftDetail extends StatelessWidget {
  const _DraftDetail({
    required this.controller,
    required this.modeId,
    required this.draft,
  });

  final AgentAwesomeAppController controller;
  final String modeId;
  final AutomationDraft? draft;

  @override
  Widget build(BuildContext context) {
    final selectedDraft = draft;
    if (selectedDraft == null) {
      return const PanelEmptyBlock(label: 'No draft selected');
    }
    if (selectedDraft.kind == 'task_graph') {
      return _TaskGraphDraftDetail(
        controller: controller,
        modeId: modeId,
        draft: selectedDraft,
      );
    }
    if (modeId == _automationDetailSteps) {
      return _DraftSteps(controller: controller, draft: selectedDraft);
    }
    if (modeId == _automationDetailMap) {
      return _StateMachineMapDetail(draft: selectedDraft);
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
          title: 'Draft',
          child: _DetailRows(
            rows: <String>[
              draft.name,
              draft.id,
              draft.kind,
              draft.status,
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
      view: modeId == _automationDetailOverview
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
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight - 46
            : 720.0;
        final designerHeight = availableHeight < 520 ? 520.0 : availableHeight;
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          child: SizedBox(
            height: designerHeight,
            child: _TaskGraphDesignerSurface(
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
              onDeleteConnection: (dependencyId, targetNodeId) =>
                  _removeDependency(
                    dependencyId,
                    targetNodeId,
                    selectedNodeId: targetNodeId,
                  ),
              onDeleteNode: _deleteSpecificNode,
              onMoveNodeInStage: _reorderNodeWithinStage,
              onMoveNodeStageBy: _moveNodeStageBy,
            ),
          ),
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
          title: 'Task Graph',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _AutomationTextField(controller: _nameController, label: 'Name'),
              const SizedBox(height: 10),
              _AutomationTextField(
                controller: _descriptionController,
                label: 'Description',
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              _AutomationTextField(
                controller: _taskGraphIdController,
                label: 'Graph id',
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
        tooltip: 'Add task node',
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
        tooltip: 'Delete task node',
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
      default:
        return PanelEmptyBlock(
          label:
              '${_fallbackActionLabel(_selectedAction)} is unsupported in task graphs',
        );
    }
  }

  void _loadDraft(AutomationDraft draft) {
    _nameController.text = draft.name;
    _descriptionController.text = draft.description;
    final body = _normalizedTaskGraphBody(draft);
    _taskGraphIdController.text = '${body['id'] ?? draft.id}';
    _nodes = _taskGraphNodes(body);
    _selectedNodeId = _nodes.isEmpty ? '' : _nodeId(_nodes.first);
    _loadSelectedNode();
    _lastSavedFingerprint = _draftFingerprint(
      name: draft.name,
      description: draft.description,
      body: body,
    );
    _message = '';
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
    _endpointController.text = '${args['endpoint'] ?? ''}';
    _toolController.text = '${args['name'] ?? args['tool'] ?? ''}';
    _domainIdController.text = '${args['domain_id'] ?? ''}';
    _argumentsController.text = _jsonText(_map(args['arguments']));
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
      body: <String, dynamic>{
        'kind': 'task_graph',
        'id': taskGraphId,
        'nodes': _nodes,
      },
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
          'endpoint': _endpointController.text.trim(),
          'tool': _toolController.text.trim(),
          'arguments': args,
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
      default:
        return _map(_selectedNode()?['with']);
    }
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
    ).map((action) => action.name).toList();
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
            description: 'Unsupported in task graphs',
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
  final names = known.keys.isEmpty
      ? const <String>[
          'tool.call',
          'mcp.call',
          'human.request',
          'delay.until',
          'workflow.run',
          'workflow.signal',
        ]
      : known.keys.toList();
  return <AutomationActionType>[
    for (final name in names)
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

/// Returns action types that may be newly created in task graphs.
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
    required super.controller,
    required super.label,
    super.maxLines = 1,
    super.keyboardType,
    super.monospace = false,
  });
}

class _AutomationDropdown extends StatelessWidget {
  const _AutomationDropdown({
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
    final colors = context.agentAwesomeColors;
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = actionTypes.where((action) {
      if (normalizedQuery.isEmpty) {
        return true;
      }
      return action.name.toLowerCase().contains(normalizedQuery) ||
          action.label.toLowerCase().contains(normalizedQuery) ||
          action.description.toLowerCase().contains(normalizedQuery);
    }).toList();
    return ColoredBox(
      color: colors.surface.withValues(alpha: 0.64),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: filtered.isEmpty
                  ? PanelEmptyState(query: query)
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final action = filtered[index];
                        return _TaskGraphActionPaletteTile(
                          action: action,
                          onAdd: () => onAddAction(action.name),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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
    final tile = PanelSurface(
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
              ],
            ),
          ),
        ],
      ),
    );
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

class _StateMachineMapDetail extends StatelessWidget {
  const _StateMachineMapDetail({required this.draft});

  final AutomationDraft draft;

  /// Builds a visual state map for a state-machine draft.
  @override
  Widget build(BuildContext context) {
    final body = _map(draft.body);
    final states = _list(body['states']).map(_map).toList();
    final initial = '${body['initial'] ?? ''}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        PanelSectionBlock(
          title: 'State Map',
          child: states.isEmpty
              ? const PanelEmptyBlock(label: 'No states')
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    for (final state in states)
                      _StateMapCard(state: state, initial: initial),
                  ],
                ),
        ),
      ],
    );
  }
}

class _StateMapCard extends StatelessWidget {
  const _StateMapCard({required this.state, required this.initial});

  final Map<String, dynamic> state;
  final String initial;

  /// Builds one visual state-machine state card.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final stateId = '${state['id'] ?? 'state'}';
    final actions = _list(state['on_entry']);
    final transitions = _list(state['transitions']);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 320),
      child: PanelSurface(
        padding: const EdgeInsets.all(14),
        style: PanelSurfaceStyle.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.radio_button_checked, size: 18, color: colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stateId,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                if (stateId == initial) const PanelBadge(label: 'initial'),
                PanelBadge(label: '${actions.length} entry actions'),
                PanelBadge(label: '${transitions.length} transitions'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftSteps extends StatelessWidget {
  const _DraftSteps({required this.controller, required this.draft});

  final AgentAwesomeAppController controller;
  final AutomationDraft draft;

  @override
  Widget build(BuildContext context) {
    final items = draft.kind == 'task_graph'
        ? _list(draft.body['nodes'])
        : _stateActions(draft.body);
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
        if (item != null) 'Run: ${item.runId}',
        if (item != null) 'Step: ${item.stepId}',
        if (item != null) 'Status: ${item.status}',
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

  /// Builds detail context for published automations.
  @override
  Widget build(BuildContext context) {
    final kinds = definitions.map((definition) => definition.kind).toSet();
    final definition = selectedDefinition;
    return _DetailList(
      title: 'Published',
      rows: <String>[
        'Published automations: ${definitions.length}',
        if (kinds.isNotEmpty) 'Kinds: ${kinds.join(', ')}',
        if (definition != null) 'Selected: ${definition.name}',
        if (definition != null) 'Definition id: ${definition.id}',
        if (definition != null) 'Hash: ${definition.hash}',
      ],
    );
  }
}

class _OperationsRunOverview extends StatelessWidget {
  const _OperationsRunOverview({required this.run, required this.runCount});

  final AutomationRun? run;
  final int runCount;

  /// Builds detail context for selected automation runs.
  @override
  Widget build(BuildContext context) {
    final selectedRun = run;
    return _DetailList(
      title: 'Runs',
      rows: <String>[
        'Recent runs: $runCount',
        if (selectedRun != null) 'Selected run: ${selectedRun.id}',
        if (selectedRun != null) 'Definition: ${selectedRun.definitionId}',
        if (selectedRun != null) 'Status: ${selectedRun.status}',
        if (selectedRun != null) 'State: ${selectedRun.state}',
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

class _PendingItemTile extends StatelessWidget {
  const _PendingItemTile({required this.controller, required this.item});

  final AgentAwesomeAppController controller;
  final AutomationPendingItem item;

  @override
  Widget build(BuildContext context) {
    return _AutomationTile(
      title: item.prompt,
      subtitle: '${item.runId} / ${item.stepId}',
      selected: controller.selectedAutomationPendingItem?.id == item.id,
      badges: <String>[item.status],
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
      subtitle: definition.id,
      selected: controller.selectedAutomationDefinition?.id == definition.id,
      badges: <String>[definition.kind],
      onTap: () => controller.selectAutomationDefinition(definition.id),
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
      title: run.definitionId,
      subtitle: '${run.id} / ${run.state}',
      selected: controller.selectedAutomationRun?.id == run.id,
      badges: <String>[run.status, run.kind],
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
      subtitle: draft.id,
      selected: selectedDraft?.id == draft.id,
      badges: <String>[
        draft.kind,
        draft.status,
        if (validation.valid) 'valid',
        if (validation.valid && !validation.publishable) 'blocked',
      ],
      onTap: () => controller.selectAutomationDraft(draft.id),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({required this.controller, required this.template});

  final AgentAwesomeAppController controller;
  final AutomationTemplate template;

  @override
  Widget build(BuildContext context) {
    return _AutomationTile(
      title: template.name,
      subtitle: template.description,
      badges: <String>[template.category, ...template.tags.take(2)],
      selected: controller.selectedAutomationTemplate?.id == template.id,
      onTap: () => controller.selectAutomationTemplate(template.id),
    );
  }
}

class _AutomationTile extends StatelessWidget {
  const _AutomationTile({
    required this.title,
    required this.subtitle,
    this.badges = const <String>[],
    this.selected = false,
    this.onTap,
  });

  final String title;
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
        definition.id.toLowerCase().contains(needle);
  }).toList();
}

List<AutomationDraft> _filterDrafts(
  List<AutomationDraft> drafts,
  String query,
) {
  final needle = query.toLowerCase();
  return drafts.where((draft) {
    return draft.name.toLowerCase().contains(needle) ||
        draft.id.toLowerCase().contains(needle);
  }).toList();
}

List<AutomationRun> _filterRuns(List<AutomationRun> runs, String query) {
  final needle = query.toLowerCase();
  return runs.where((run) {
    return run.id.toLowerCase().contains(needle) ||
        run.definitionId.toLowerCase().contains(needle);
  }).toList();
}

List<AutomationPendingItem> _filterPendingItems(
  List<AutomationPendingItem> items,
  String query,
) {
  final needle = query.toLowerCase();
  return items.where((item) {
    return item.prompt.toLowerCase().contains(needle) ||
        item.id.toLowerCase().contains(needle) ||
        item.runId.toLowerCase().contains(needle) ||
        item.stepId.toLowerCase().contains(needle) ||
        item.status.toLowerCase().contains(needle);
  }).toList();
}

List<AutomationTemplate> _filterTemplates(
  List<AutomationTemplate> templates,
  String query,
) {
  final needle = query.toLowerCase();
  return templates.where((template) {
    return template.name.toLowerCase().contains(needle) ||
        template.category.toLowerCase().contains(needle) ||
        template.tags.any((tag) => tag.toLowerCase().contains(needle));
  }).toList();
}

/// Reports whether a template belongs in a workflow or task authoring panel.
bool _templateMatchesKind(AutomationTemplate template, String kind) {
  final bodyKind = '${template.body['kind'] ?? ''}'.trim();
  if (bodyKind.isNotEmpty) {
    return bodyKind == kind;
  }
  final category = template.category.toLowerCase();
  if (kind == 'state_machine') {
    return category.contains('workflow') ||
        category.contains('approval') ||
        category.contains('state');
  }
  return category.contains('task_graph') ||
      category.contains('task-graph') ||
      category.contains('task graph') ||
      category.contains('task') ||
      category.contains('agent');
}

/// Returns the automation draft kind edited by a left command area.
String? _automationDraftKindForArea(String areaId) {
  if (areaId == _automationWorkflowAreaDrafts ||
      areaId == _automationWorkflowAreaActions) {
    return 'state_machine';
  }
  if (areaId == _automationTaskAreaDrafts ||
      areaId == _automationTaskAreaNodes) {
    return 'task_graph';
  }
  return null;
}

/// Returns the template kind represented by a template command area.
String? _automationTemplateKindForArea(String areaId) {
  if (areaId == _automationWorkflowAreaTemplates) {
    return 'state_machine';
  }
  if (areaId == _automationTaskAreaTemplates) {
    return 'task_graph';
  }
  return null;
}

/// Returns the selected template filtered to one template command area.
AutomationTemplate? _selectedAutomationTemplateForArea(
  AgentAwesomeAppController controller,
  String areaId,
) {
  final kind = _automationTemplateKindForArea(areaId);
  if (kind == null) {
    return controller.selectedAutomationTemplate;
  }
  final templates = controller.automationTemplates
      .where((template) => _templateMatchesKind(template, kind))
      .toList();
  if (templates.isEmpty) {
    return null;
  }
  for (final template in templates) {
    if (template.id == controller.selectedAutomationTemplateId) {
      return template;
    }
  }
  return templates.first;
}

/// Returns the selected draft for one builder kind.
AutomationDraft? _selectedAutomationDraftForKind(
  AgentAwesomeAppController controller,
  String kind,
) {
  final drafts = controller.automationDrafts
      .where((draft) => draft.kind == kind)
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
    'kind': 'task_graph',
    'id': '${body['id'] ?? draft.id}',
    'nodes': _taskGraphNodes(body),
  };
}

/// Returns detached task nodes from a draft body.
List<Map<String, dynamic>> _taskGraphNodes(Map<String, dynamic> body) {
  return _list(
    body['nodes'],
  ).map((node) => Map<String, dynamic>.from(_map(node))).toList();
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
      'endpoint': '',
      'tool': '',
      'arguments': <String, dynamic>{},
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
