/// Shared validation scenario table widgets for settings command panels.
part of 'settings_panel.dart';

const List<String> _settingsValidationRunModes = <String>[
  'mocked',
  'live',
  'all',
];

/// SettingsValidationRunRequest describes one requested validation run.
class SettingsValidationRunRequest {
  /// Creates a validation run request for one or more scenario ids.
  const SettingsValidationRunRequest({
    required this.mode,
    required this.validationIds,
    this.allowEmpty = false,
  });

  /// Requested lane: mocked, live, or all.
  final String mode;

  /// Validation ids that should be sent to the runner.
  final List<String> validationIds;

  /// Whether an empty id list should run the package-level validation gate.
  final bool allowEmpty;
}

/// SettingsValidationModeState stores status for one scenario lane.
class SettingsValidationModeState {
  /// Creates a mode lane result for a scenario row.
  const SettingsValidationModeState({
    required this.mode,
    required this.validationIds,
    required this.status,
    this.configured = true,
  });

  /// Lane name, such as mocked or live.
  final String mode;

  /// Configured validation ids that belong to this lane.
  final List<String> validationIds;

  /// Latest runner status for this lane.
  final String status;

  /// Whether this lane is configured for the scenario.
  final bool configured;
}

/// SettingsValidationScenario stores one reusable validation table row.
class SettingsValidationScenario {
  /// Creates a table row for one portable validation scenario.
  const SettingsValidationScenario({
    required this.id,
    required this.label,
    required this.description,
    required this.modeStates,
    required this.status,
    required this.details,
  });

  /// Stable row id.
  final String id;

  /// Human-readable scenario label.
  final String label;

  /// Human-readable purpose or invocation surface.
  final String description;

  /// Mode lane states keyed by mode.
  final Map<String, SettingsValidationModeState> modeStates;

  /// Latest display status for the scenario.
  final String status;

  /// Optional expanded evidence widget.
  final Widget? details;

  /// Returns every configured validation id for this scenario.
  List<String> get allValidationIds {
    return <String>[
      for (final state in modeStates.values) ...state.validationIds,
    ];
  }

  /// Returns configured ids that can run for a requested mode.
  List<String> validationIdsForMode(String mode) {
    final normalized = _settingsValidationModeValue(mode);
    if (normalized == 'all') {
      return allValidationIds;
    }
    return modeStates[normalized]?.validationIds ?? const <String>[];
  }

  /// Reports whether the requested run mode has at least one configured id.
  bool canRunMode(String mode) {
    return validationIdsForMode(mode).isNotEmpty;
  }
}

/// SettingsValidationScenarioTable renders reusable scenario validation rows.
class SettingsValidationScenarioTable extends StatefulWidget {
  /// Creates a reusable validation scenario table.
  const SettingsValidationScenarioTable({
    super.key,
    required this.scenarios,
    required this.selectedRunMode,
    required this.runningMode,
    required this.runningValidationIds,
    required this.runningAll,
    required this.onRunAll,
    required this.onRunScenario,
    required this.onDeleteScenario,
    required this.onAddValidation,
    this.liveAvailable = true,
    this.extraActions = const <Widget>[],
    this.emptyLabel = 'No validations configured',
    this.showControls = true,
    this.showModeColumn = true,
    this.showActions = true,
    this.primaryColumnLabel = 'Validation',
    this.descriptionColumnLabel = 'Description',
    this.modeColumnLabel = 'Mode',
    this.statusColumnLabel = 'Status',
    this.actionsColumnLabel = 'Actions',
    this.onScenarioExpanded,
  });

  /// Rows to render in the scenario table.
  final List<SettingsValidationScenario> scenarios;

  /// Last selected run lane.
  final String selectedRunMode;

  /// Lane currently running, when any.
  final String runningMode;

  /// Validation ids currently running.
  final Set<String> runningValidationIds;

  /// Whether the run-all action is currently active.
  final bool runningAll;

  /// Runs every visible scenario in the selected lane.
  final ValueChanged<SettingsValidationRunRequest> onRunAll;

  /// Runs one visible scenario in the selected lane.
  final ValueChanged<SettingsValidationRunRequest> onRunScenario;

  /// Deletes one scenario and its configured lanes.
  final ValueChanged<SettingsValidationScenario> onDeleteScenario;

  /// Adds default validations for the active verification target.
  final VoidCallback? onAddValidation;

  /// Whether live validations are available for the selected target.
  final bool liveAvailable;

  /// Additional compact actions shown with the scenario controls.
  final List<Widget> extraActions;

  /// Empty-state label for tables without scenarios.
  final String emptyLabel;

  /// Whether table-level run and add controls should be shown.
  final bool showControls;

  /// Whether the per-lane mode column should be shown.
  final bool showModeColumn;

  /// Whether per-row run and delete actions should be shown.
  final bool showActions;

  /// Header label for the primary row identity column.
  final String primaryColumnLabel;

  /// Header label for the row description column.
  final String descriptionColumnLabel;

  /// Header label for the mode column.
  final String modeColumnLabel;

  /// Header label for the status column.
  final String statusColumnLabel;

  /// Header label for the action column.
  final String actionsColumnLabel;

  /// Optional callback when a row is expanded.
  final ValueChanged<SettingsValidationScenario>? onScenarioExpanded;

  /// Creates mutable expansion state for scenario evidence.
  @override
  State<SettingsValidationScenarioTable> createState() =>
      _SettingsValidationScenarioTableState();
}

class _SettingsValidationScenarioTableState
    extends State<SettingsValidationScenarioTable> {
  final Set<String> _expanded = <String>{};

  /// Builds the table and scenario controls.
  @override
  Widget build(BuildContext context) {
    final anyRunning =
        widget.runningAll || widget.runningValidationIds.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.showControls) ...<Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SettingsValidationRunModeButton(
                label: widget.runningAll ? 'Running' : 'Run all',
                selectedMode: widget.selectedRunMode,
                enabledModes: _enabledModesFor(widget.scenarios),
                loading: widget.runningAll,
                onRun: anyRunning ? null : _runAll,
              ),
              OutlinedButton.icon(
                onPressed: anyRunning ? null : widget.onAddValidation,
                icon: const Icon(Icons.add),
                label: const Text('Add validation'),
              ),
              ...widget.extraActions,
              if (anyRunning)
                PanelBadge(
                  label:
                      'Running ${_settingsValidationModeLabel(widget.runningMode)}',
                ),
            ],
          ),
          const SizedBox(height: SettingsFormMetrics.sectionGap),
        ],
        if (widget.scenarios.isEmpty)
          PanelEmptyBlock(label: widget.emptyLabel)
        else
          _buildTable(context),
      ],
    );
  }

  /// Builds the scenario table body.
  Widget _buildTable(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SettingsValidationScenarioHeader(
          primaryColumnLabel: widget.primaryColumnLabel,
          descriptionColumnLabel: widget.descriptionColumnLabel,
          modeColumnLabel: widget.modeColumnLabel,
          statusColumnLabel: widget.statusColumnLabel,
          actionsColumnLabel: widget.actionsColumnLabel,
          showModeColumn: widget.showModeColumn,
          showActions: widget.showActions,
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < widget.scenarios.length; index++)
          Padding(
            padding: EdgeInsets.only(
              bottom: index == widget.scenarios.length - 1 ? 0 : 6,
            ),
            child: _SettingsValidationScenarioRow(
              scenario: widget.scenarios[index],
              expanded: _expanded.contains(widget.scenarios[index].id),
              selectedRunMode: widget.selectedRunMode,
              runningMode: widget.runningMode,
              runningIds: widget.runningValidationIds,
              liveAvailable: widget.liveAvailable,
              showModeColumn: widget.showModeColumn,
              showActions: widget.showActions,
              onToggleExpanded: () => _toggleExpanded(widget.scenarios[index]),
              onRun: (request) {
                widget.onRunScenario(request);
                if (!_expanded.contains(widget.scenarios[index].id)) {
                  setState(() => _expanded.add(widget.scenarios[index].id));
                }
              },
              onDelete: () => widget.onDeleteScenario(widget.scenarios[index]),
            ),
          ),
      ],
    );
  }

  /// Runs every visible scenario for the currently selected mode.
  void _runAll(String mode) {
    final ids = <String>[
      for (final scenario in widget.scenarios)
        ...scenario.validationIdsForMode(mode),
    ];
    widget.onRunAll(
      SettingsValidationRunRequest(
        mode: mode,
        validationIds: ids,
        allowEmpty: true,
      ),
    );
  }

  /// Expands or collapses one scenario row.
  void _toggleExpanded(SettingsValidationScenario scenario) {
    setState(() {
      if (!_expanded.remove(scenario.id)) {
        _expanded.add(scenario.id);
        widget.onScenarioExpanded?.call(scenario);
      }
    });
  }

  /// Returns run modes that have at least one configured visible scenario.
  Set<String> _enabledModesFor(List<SettingsValidationScenario> scenarios) {
    if (scenarios.isEmpty) {
      return const <String>{'mocked'};
    }
    final hasMocked = scenarios.any(
      (scenario) => scenario.canRunMode('mocked'),
    );
    final hasLive =
        widget.liveAvailable &&
        scenarios.any((scenario) => scenario.canRunMode('live'));
    return <String>{
      if (hasMocked) 'mocked',
      if (hasLive) 'live',
      if (hasMocked && hasLive) 'all',
    };
  }
}

/// SettingsValidationRunModeButton renders a split run/dropdown control.
class SettingsValidationRunModeButton extends StatelessWidget {
  /// Creates a split validation run control.
  const SettingsValidationRunModeButton({
    super.key,
    required this.label,
    required this.selectedMode,
    required this.enabledModes,
    required this.onRun,
    this.loading = false,
  });

  /// Text shown on the primary run segment.
  final String label;

  /// Last selected validation lane.
  final String selectedMode;

  /// Modes that have configured validation ids.
  final Set<String> enabledModes;

  /// Called when the user selects and runs a lane.
  final ValueChanged<String>? onRun;

  /// Whether the current action should display a spinner.
  final bool loading;

  /// Builds the split run control.
  @override
  Widget build(BuildContext context) {
    final reportColors = _SettingsValidationReportPalette.of(context);
    final mode = _effectiveValidationRunMode(selectedMode, enabledModes);
    final enabled = onRun != null && enabledModes.contains(mode);
    final primary = label.trim().isNotEmpty;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: primary ? reportColors.primaryAction : reportColors.action,
        border: Border.all(
          color: primary
              ? reportColors.primaryActionBorder
              : reportColors.actionBorder,
        ),
        borderRadius: BorderRadius.circular(PanelStyleTokens.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          InkWell(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(PanelStyleTokens.radius),
            ),
            onTap: enabled ? () => onRun?.call(mode) : null,
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 0, 12, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (loading)
                      SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: primary
                              ? reportColors.primaryActionText
                              : reportColors.actionText,
                        ),
                      )
                    else
                      Icon(
                        Icons.play_arrow,
                        size: 17,
                        color: primary
                            ? reportColors.primaryActionText
                            : reportColors.actionText,
                      ),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: TextStyle(
                        color: primary
                            ? reportColors.primaryActionText
                            : reportColors.actionText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 24,
            color: primary
                ? reportColors.primaryActionDivider
                : reportColors.actionBorder,
          ),
          PopupMenuButton<String>(
            tooltip: 'Choose validation mode',
            enabled: onRun != null,
            color: reportColors.menu,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                PanelStyleTokens.compactRadius,
              ),
            ),
            onSelected: (value) => onRun?.call(value),
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              for (final value in _settingsValidationRunModes)
                PopupMenuItem<String>(
                  value: value,
                  enabled: enabledModes.contains(value),
                  child: Text(
                    _settingsValidationModeLabel(value),
                    style: TextStyle(
                      color: enabledModes.contains(value)
                          ? reportColors.text
                          : reportColors.textMuted.withValues(alpha: 0.48),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
            child: Opacity(
              opacity: onRun != null ? 1 : 0.45,
              child: SizedBox(
                width: 34,
                child: Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: primary
                      ? reportColors.primaryActionText
                      : reportColors.actionText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsValidationScenarioHeader extends StatelessWidget {
  const _SettingsValidationScenarioHeader({
    required this.primaryColumnLabel,
    required this.descriptionColumnLabel,
    required this.modeColumnLabel,
    required this.statusColumnLabel,
    required this.actionsColumnLabel,
    required this.showModeColumn,
    required this.showActions,
  });

  final String primaryColumnLabel;

  final String descriptionColumnLabel;

  final String modeColumnLabel;

  final String statusColumnLabel;

  final String actionsColumnLabel;

  final bool showModeColumn;

  final bool showActions;

  /// Builds table column headers for scenario rows.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final style = TextStyle(
      color: colors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w800,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          _SettingsValidationCell(
            flex: 2,
            child: Text(primaryColumnLabel, style: style),
          ),
          _SettingsValidationCell(
            flex: 3,
            child: Text(descriptionColumnLabel, style: style),
          ),
          if (showModeColumn)
            _SettingsValidationCell(
              flex: 2,
              child: Text(modeColumnLabel, style: style),
            ),
          _SettingsValidationCell(
            flex: 2,
            child: Text(statusColumnLabel, style: style),
          ),
          if (showActions)
            SizedBox(
              width: 124,
              child: Text(
                actionsColumnLabel,
                style: style,
                textAlign: TextAlign.right,
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsValidationScenarioRow extends StatelessWidget {
  const _SettingsValidationScenarioRow({
    required this.scenario,
    required this.expanded,
    required this.selectedRunMode,
    required this.runningMode,
    required this.runningIds,
    required this.liveAvailable,
    required this.showModeColumn,
    required this.showActions,
    required this.onToggleExpanded,
    required this.onRun,
    required this.onDelete,
  });

  final SettingsValidationScenario scenario;
  final bool expanded;
  final String selectedRunMode;
  final String runningMode;
  final Set<String> runningIds;
  final bool liveAvailable;
  final bool showModeColumn;
  final bool showActions;
  final VoidCallback onToggleExpanded;
  final ValueChanged<SettingsValidationRunRequest> onRun;
  final VoidCallback onDelete;

  /// Builds one scenario row and its optional expanded details.
  @override
  Widget build(BuildContext context) {
    final reportColors = _SettingsValidationReportPalette.of(context);
    final running = scenario.allValidationIds.any(runningIds.contains);
    final canExpand = scenario.details != null;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: expanded ? reportColors.rowExpanded : reportColors.row,
        border: Border.all(
          color: expanded
              ? reportColors.rowBorderActive
              : reportColors.rowBorder,
        ),
        borderRadius: BorderRadius.circular(PanelStyleTokens.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: scenario.details == null ? null : onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: <Widget>[
                  _SettingsValidationCell(
                    flex: 2,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_down
                              : canExpand
                              ? Icons.chevron_right
                              : Icons.circle,
                          size: 19,
                          color: canExpand
                              ? reportColors.textMuted
                              : Colors.transparent,
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          _scenarioSuccessIcon(scenario),
                          size: 13,
                          color: _scenarioSuccessColor(context, scenario),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            scenario.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _SettingsValidationCell(
                    flex: 3,
                    child: Text(
                      scenario.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: reportColors.textMuted),
                    ),
                  ),
                  if (showModeColumn)
                    _SettingsValidationCell(
                      flex: 2,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          for (final mode in const <String>['mocked', 'live'])
                            _SettingsValidationModePill(
                              state:
                                  scenario.modeStates[mode] ??
                                  SettingsValidationModeState(
                                    mode: mode,
                                    validationIds: const <String>[],
                                    status: '',
                                    configured: false,
                                  ),
                              running:
                                  running &&
                                  _settingsValidationModeValue(runningMode) ==
                                      mode,
                            ),
                        ],
                      ),
                    ),
                  _SettingsValidationCell(
                    flex: 2,
                    child: _SettingsValidationStatusPill(
                      status: running ? 'running' : scenario.status,
                    ),
                  ),
                  if (showActions)
                    SizedBox(
                      width: 124,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          SettingsValidationRunModeButton(
                            label: '',
                            selectedMode: selectedRunMode,
                            enabledModes: _enabledModesForScenario(scenario),
                            loading: running,
                            onRun: running ? null : _runScenario,
                          ),
                          const SizedBox(width: 6),
                          PanelInlineIconButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Delete validation',
                            onPressed: onDelete,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (expanded && scenario.details != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: scenario.details!,
            ),
        ],
      ),
    );
  }

  /// Runs this scenario with the selected mode if it is configured.
  void _runScenario(String mode) {
    final ids = scenario.validationIdsForMode(mode);
    if (ids.isEmpty) {
      return;
    }
    onRun(SettingsValidationRunRequest(mode: mode, validationIds: ids));
  }

  /// Returns modes that are available for this row.
  Set<String> _enabledModesForScenario(SettingsValidationScenario scenario) {
    final hasMocked = scenario.canRunMode('mocked');
    final hasLive = liveAvailable && scenario.canRunMode('live');
    return <String>{
      if (hasMocked) 'mocked',
      if (hasLive) 'live',
      if (hasMocked && hasLive) 'all',
    };
  }
}

/// Returns the selected run mode, or the first runnable fallback.
String _effectiveValidationRunMode(String selectedMode, Set<String> modes) {
  final requested = _settingsValidationModeValue(selectedMode);
  if (modes.contains(requested)) {
    return requested;
  }
  for (final mode in const <String>['mocked', 'live', 'all']) {
    if (modes.contains(mode)) {
      return mode;
    }
  }
  return requested;
}

class _SettingsValidationCell extends StatelessWidget {
  const _SettingsValidationCell({required this.flex, required this.child});

  final int flex;
  final Widget child;

  /// Builds one flexible table cell with consistent spacing.
  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(padding: const EdgeInsets.only(right: 12), child: child),
    );
  }
}

class _SettingsValidationModePill extends StatelessWidget {
  const _SettingsValidationModePill({
    required this.state,
    required this.running,
  });

  final SettingsValidationModeState state;
  final bool running;

  /// Builds one mocked/live mode status pill.
  @override
  Widget build(BuildContext context) {
    final reportColors = _SettingsValidationReportPalette.of(context);
    final success = _validationStatusIsSuccess(state.status);
    final failure = _validationStatusIsFailure(state.status);
    final color = running
        ? reportColors.modeText
        : success
        ? reportColors.statusSuccessText
        : failure
        ? reportColors.statusFailureText
        : state.configured
        ? reportColors.modeText
        : reportColors.textSubtle;
    final fill = state.configured
        ? reportColors.modeFill
        : reportColors.modeFill.withValues(alpha: 0.36);
    final border = state.configured
        ? reportColors.modeBorder
        : reportColors.modeBorder.withValues(alpha: 0.44);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(
          color: border,
          width: AgentAwesomeStrokeTokens.borderWidth,
        ),
        borderRadius: BorderRadius.circular(PanelStyleTokens.compactRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (running)
            SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(
              success
                  ? Icons.check_circle_outline
                  : failure
                  ? Icons.cancel_outlined
                  : state.configured
                  ? Icons.radio_button_unchecked
                  : Icons.remove_circle_outline,
              size: 13,
              color: color,
            ),
          const SizedBox(width: 5),
          Text(
            _settingsValidationModeLabel(state.mode),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsValidationStatusPill extends StatelessWidget {
  const _SettingsValidationStatusPill({required this.status});

  final String status;

  /// Builds the aggregate row status pill.
  @override
  Widget build(BuildContext context) {
    final reportColors = _SettingsValidationReportPalette.of(context);
    final value = status.trim().isEmpty ? 'not run' : status.trim();
    final success = _validationStatusIsSuccess(value);
    final partial = _validationStatusIsPartial(value);
    final failure = _validationStatusIsFailure(value);
    final color = success
        ? reportColors.statusSuccessText
        : partial
        ? reportColors.statusPartialText
        : failure
        ? reportColors.statusFailureText
        : reportColors.textMuted;
    final fill = success
        ? reportColors.statusSuccessFill
        : partial
        ? reportColors.statusPartialFill
        : failure
        ? reportColors.statusFailureFill
        : reportColors.pillFill;
    final border = success
        ? reportColors.statusSuccessBorder
        : partial
        ? reportColors.statusPartialBorder
        : failure
        ? reportColors.statusFailureBorder
        : reportColors.pillBorder;
    final label = _validationStatusLabel(value);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(
            color: border,
            width: AgentAwesomeStrokeTokens.borderWidth,
          ),
          borderRadius: BorderRadius.circular(PanelStyleTokens.compactRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              success
                  ? Icons.check_circle_outline
                  : partial
                  ? Icons.check_circle_outline
                  : failure
                  ? Icons.cancel_outlined
                  : Icons.radio_button_unchecked,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Returns the normalized validation mode used by UI controls.
String _settingsValidationModeValue(String mode) {
  final value = mode.trim().toLowerCase();
  if (value == 'live' || value == 'all') {
    return value;
  }
  return 'mocked';
}

/// Returns the user-facing label for a validation mode.
String _settingsValidationModeLabel(String mode) {
  return switch (_settingsValidationModeValue(mode)) {
    'live' => 'Live',
    'all' => 'All',
    _ => 'Mocked',
  };
}

/// Reports whether a validation status should be treated as successful.
bool _validationStatusIsSuccess(String status) {
  final value = status.trim().toLowerCase();
  return value == 'passed' || value == 'succeeded' || value == 'success';
}

/// Reports whether a validation status is an incomplete success.
bool _validationStatusIsPartial(String status) {
  final value = status.trim().toLowerCase().replaceAll('-', '_');
  return value == 'partial_success';
}

/// Reports whether a validation status should be treated as failed.
bool _validationStatusIsFailure(String status) {
  final value = status.trim().toLowerCase();
  return value == 'failed' ||
      value == 'error' ||
      value == 'unsupported' ||
      value == 'timed out' ||
      value == 'timeout';
}

/// Returns polished user-facing status copy.
String _validationStatusLabel(String status) {
  final value = status.trim().toLowerCase().replaceAll('-', '_');
  return switch (value) {
    'partial_success' => 'Partial Success',
    'success' || 'passed' || 'succeeded' => 'Success',
    'not_run' || 'not run' || '' => 'not run',
    _ => status,
  };
}

/// Returns the leading row icon for aggregate scenario state.
IconData _scenarioSuccessIcon(SettingsValidationScenario scenario) {
  if (_validationStatusIsSuccess(scenario.status) ||
      _validationStatusIsPartial(scenario.status)) {
    return Icons.circle;
  }
  if (_validationStatusIsFailure(scenario.status)) {
    return Icons.cancel;
  }
  return Icons.radio_button_unchecked;
}

/// Returns the leading row color for aggregate scenario state.
Color _scenarioSuccessColor(
  BuildContext context,
  SettingsValidationScenario scenario,
) {
  final reportColors = _SettingsValidationReportPalette.of(context);
  if (_validationStatusIsSuccess(scenario.status) ||
      _validationStatusIsPartial(scenario.status)) {
    return reportColors.dotSuccess;
  }
  if (_validationStatusIsFailure(scenario.status)) {
    return reportColors.statusFailureText;
  }
  return reportColors.textMuted;
}

class _SettingsValidationReportPalette {
  const _SettingsValidationReportPalette({
    required this.row,
    required this.rowExpanded,
    required this.rowBorder,
    required this.rowBorderActive,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.dotSuccess,
    required this.action,
    required this.actionBorder,
    required this.actionText,
    required this.primaryAction,
    required this.primaryActionBorder,
    required this.primaryActionDivider,
    required this.primaryActionText,
    required this.menu,
    required this.modeFill,
    required this.modeBorder,
    required this.modeText,
    required this.pillFill,
    required this.pillBorder,
    required this.statusSuccessFill,
    required this.statusSuccessBorder,
    required this.statusSuccessText,
    required this.statusPartialFill,
    required this.statusPartialBorder,
    required this.statusPartialText,
    required this.statusFailureFill,
    required this.statusFailureBorder,
    required this.statusFailureText,
  });

  final Color row;
  final Color rowExpanded;
  final Color rowBorder;
  final Color rowBorderActive;
  final Color text;
  final Color textMuted;
  final Color textSubtle;
  final Color dotSuccess;
  final Color action;
  final Color actionBorder;
  final Color actionText;
  final Color primaryAction;
  final Color primaryActionBorder;
  final Color primaryActionDivider;
  final Color primaryActionText;
  final Color menu;
  final Color modeFill;
  final Color modeBorder;
  final Color modeText;
  final Color pillFill;
  final Color pillBorder;
  final Color statusSuccessFill;
  final Color statusSuccessBorder;
  final Color statusSuccessText;
  final Color statusPartialFill;
  final Color statusPartialBorder;
  final Color statusPartialText;
  final Color statusFailureFill;
  final Color statusFailureBorder;
  final Color statusFailureText;

  /// Returns the blue validation-report palette used by scenario tables.
  static _SettingsValidationReportPalette of(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!dark) {
      return _SettingsValidationReportPalette(
        row: colors.surface,
        rowExpanded: colors.greenSoft,
        rowBorder: colors.border,
        rowBorderActive: colors.borderStrong,
        text: colors.ink,
        textMuted: colors.muted,
        textSubtle: colors.subtle,
        dotSuccess: colors.green,
        action: colors.panel,
        actionBorder: colors.borderStrong,
        actionText: colors.green,
        primaryAction: colors.greenSoft,
        primaryActionBorder: colors.borderStrong,
        primaryActionDivider: colors.borderStrong,
        primaryActionText: colors.green,
        menu: colors.panelStrong,
        modeFill: colors.panel,
        modeBorder: colors.border,
        modeText: colors.green,
        pillFill: colors.panel,
        pillBorder: colors.border,
        statusSuccessFill: colors.greenSoft,
        statusSuccessBorder: colors.green.withValues(alpha: 0.5),
        statusSuccessText: colors.green,
        statusPartialFill: colors.warningSoft,
        statusPartialBorder: colors.warningBorder,
        statusPartialText: colors.warningText,
        statusFailureFill: colors.coral.withValues(alpha: 0.13),
        statusFailureBorder: colors.coral.withValues(alpha: 0.45),
        statusFailureText: colors.coral,
      );
    }
    return const _SettingsValidationReportPalette(
      row: Color(0xff08121f),
      rowExpanded: Color(0xff0f1a31),
      rowBorder: Color(0xff1f344f),
      rowBorderActive: Color(0xff4e82c7),
      text: Color(0xfff3f7ff),
      textMuted: Color(0xffaebbd0),
      textSubtle: Color(0xff74849b),
      dotSuccess: Color(0xff6fe08a),
      action: Color(0xff101b31),
      actionBorder: Color(0xff3f5f88),
      actionText: Color(0xffb4d5ff),
      primaryAction: Color(0xff8cc5ff),
      primaryActionBorder: Color(0xffa7d3ff),
      primaryActionDivider: Color(0xff5f9bd6),
      primaryActionText: Color(0xff061224),
      menu: Color(0xff202329),
      modeFill: Color(0xff0f1d34),
      modeBorder: Color(0xff284368),
      modeText: Color(0xffaad0ff),
      pillFill: Color(0xff0e1a2d),
      pillBorder: Color(0xff284368),
      statusSuccessFill: Color(0xff103121),
      statusSuccessBorder: Color(0xff2f7d4d),
      statusSuccessText: Color(0xff78e08f),
      statusPartialFill: Color(0xff2a1d08),
      statusPartialBorder: Color(0xff9a640d),
      statusPartialText: Color(0xffffb238),
      statusFailureFill: Color(0xff281832),
      statusFailureBorder: Color(0xff6d4baa),
      statusFailureText: Color(0xffb78dff),
    );
  }
}
