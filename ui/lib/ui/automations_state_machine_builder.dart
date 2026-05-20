/// Visual builder for process-style state-machine workflow drafts.
part of 'automations_section.dart';

/// _StateMachineDraftEditController owns editable process-state graph state.
class _StateMachineDraftEditController extends ChangeNotifier {
  /// Creates a shared editor for process-state workflow drafts.
  _StateMachineDraftEditController({required this.controller}) {
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _attachCanvasScrollListeners();
  }

  /// Shared app controller used to persist draft edits.
  final AgentAwesomeAppController controller;

  static const Duration _saveDelay = Duration(milliseconds: 500);

  Timer? _saveTimer;
  AutomationDraft? _draft;
  String _draftFingerprint = '';
  List<Map<String, dynamic>> _states = <Map<String, dynamic>>[];
  Map<String, Offset> _positions = <String, Offset>{};
  Set<String> _collapsedPhaseIds = <String>{};
  String _initialStateId = '';
  String _selectedStateId = '';
  String _connectionSourceId = '';
  double _zoom = 1;
  Offset _canvasOffset = Offset.zero;
  ScrollController _horizontalCanvasController = ScrollController();
  ScrollController _verticalCanvasController = ScrollController();
  bool _suppressCanvasOffsetUpdates = false;
  bool _openInspectorModifierPressed = false;

  /// Editable states in the selected process workflow.
  List<Map<String, dynamic>> get states => _states;

  /// Persisted canvas positions keyed by state id.
  Map<String, Offset> get positions => _positions;

  /// Composite phase ids currently collapsed on the canvas.
  Set<String> get collapsedPhaseIds => _collapsedPhaseIds;

  /// Initial state id for the selected workflow.
  String get initialStateId => _initialStateId;

  /// Currently selected state id.
  String get selectedStateId => _selectedStateId;

  /// State id currently used as a transition source.
  String get connectionSourceId => _connectionSourceId;

  /// Canvas zoom factor.
  double get zoom => _zoom;

  /// Last known canvas viewport x/y offset.
  Offset get canvasOffset => _canvasOffset;

  /// Horizontal controller used to preserve the canvas x position.
  ScrollController get horizontalCanvasController =>
      _horizontalCanvasController;

  /// Vertical controller used to preserve the canvas y position.
  ScrollController get verticalCanvasController => _verticalCanvasController;

  /// Reports whether Ctrl-click should open the selected-node inspector.
  bool get openInspectorModifierPressed =>
      _openInspectorModifierPressed ||
      HardwareKeyboard.instance.isControlPressed;

  /// Attaches this editor to the selected workflow draft.
  void attachDraft(AutomationDraft draft) {
    final fingerprint = _fingerprintForDraft(draft);
    if (_draftFingerprint == fingerprint) {
      return;
    }
    _draft = draft;
    _draftFingerprint = fingerprint;
    _canvasOffset =
        _stateMachineCanvasOffsetsByDraft[draft.id] ?? _canvasOffset;
    _loadDraft(draft);
    notifyListeners();
  }

  /// Releases pending persistence timers.
  @override
  void dispose() {
    _saveTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _detachCanvasScrollListeners();
    _horizontalCanvasController.dispose();
    _verticalCanvasController.dispose();
    super.dispose();
  }

  /// Updates the canvas zoom factor without mutating workflow data.
  void setZoom(double value) {
    if (_zoom == value) {
      return;
    }
    _zoom = value;
    notifyListeners();
  }

  /// Selects a state or completes the active connection gesture.
  void selectOrConnectState(String stateId) {
    if (_connectionSourceId.isNotEmpty && _connectionSourceId != stateId) {
      toggleTransition(_connectionSourceId, stateId);
      return;
    }
    if (_selectedStateId == stateId) {
      return;
    }
    _selectedStateId = stateId;
    notifyListeners();
  }

  /// Selects one state without applying the connection gesture.
  void selectState(String stateId) {
    if (stateId.isEmpty || _selectedStateId == stateId) {
      return;
    }
    _selectedStateId = stateId;
    notifyListeners();
  }

  /// Toggles transition-connection mode from one source state.
  void startConnection(String stateId) {
    _connectionSourceId = _connectionSourceId == stateId ? '' : stateId;
    _selectedStateId = stateId;
    notifyListeners();
  }

  /// Cancels an active transition connection gesture.
  void cancelConnection() {
    if (_connectionSourceId.isEmpty) {
      return;
    }
    _connectionSourceId = '';
    notifyListeners();
  }

  /// Adds a new process state from a palette action.
  void addStateFromPalette(String actionName) {
    _mutateStates(() {
      final state = _newProcessState(_states, actionName);
      _states.add(state);
      _selectedStateId = _stateId(state);
      if (_initialStateId.isEmpty) {
        _initialStateId = _selectedStateId;
      }
      _positions[_selectedStateId] = _nextStateMachinePosition(_positions);
    });
  }

  /// Adds a new process state as a child of an existing composite phase.
  void addStateToPhase(String parentStateId, String actionName) {
    if (parentStateId.isEmpty) {
      addStateFromPalette(actionName);
      return;
    }
    _mutateStates(() {
      final parentIndex = _states.indexWhere(
        (state) => _stateId(state) == parentStateId,
      );
      if (parentIndex < 0) {
        return;
      }
      final state = _newProcessState(_states, actionName);
      state['parent'] = parentStateId;
      final stateId = _stateId(state);
      final parent = Map<String, dynamic>.from(_states[parentIndex]);
      if ('${parent['initial'] ?? ''}'.trim().isEmpty) {
        parent['initial'] = stateId;
        _states[parentIndex] = parent;
      }
      _states.add(state);
      _selectedStateId = stateId;
      final parentPosition = _stateMachinePositionForState(
        parentStateId,
        _states,
        _positions,
        _initialStateId,
      );
      _positions[stateId] = parentPosition + const Offset(32, 128);
      _collapsedPhaseIds.remove(parentStateId);
    });
  }

  /// Collapses or expands one composite phase on the canvas.
  void togglePhaseCollapsed(String stateId) {
    if (stateId.isEmpty) {
      return;
    }
    _mutateStates(() {
      if (_collapsedPhaseIds.contains(stateId)) {
        _collapsedPhaseIds.remove(stateId);
      } else {
        _collapsedPhaseIds.add(stateId);
      }
    });
  }

  /// Adds a palette action as an entry action on an existing state.
  void addEntryActionToState(String stateId, String actionName) {
    if (actionName == _terminalStatePaletteAction) {
      return;
    }
    final index = _states.indexWhere((state) => _stateId(state) == stateId);
    if (index < 0) {
      return;
    }
    _mutateStates(() {
      final state = Map<String, dynamic>.from(_states[index]);
      final actions = _stateEntryActions(state).map(_map).toList();
      actions.add(_newEntryAction(actions, actionName));
      state['on_entry'] = actions;
      _states[index] = state;
      _selectedStateId = stateId;
    });
  }

  /// Adds or removes a transition between two process states.
  void toggleTransition(String sourceStateId, String targetStateId) {
    final index = _states.indexWhere(
      (state) => _stateId(state) == sourceStateId,
    );
    if (index < 0 || sourceStateId == targetStateId) {
      return;
    }
    _mutateStates(() {
      final state = Map<String, dynamic>.from(_states[index]);
      final transitions = _stateTransitions(state).map(_map).toList();
      final existingIndex = transitions.indexWhere(
        (transition) => _transitionTarget(transition) == targetStateId,
      );
      if (existingIndex >= 0) {
        transitions.removeAt(existingIndex);
      } else {
        transitions.add(<String, dynamic>{
          'trigger': _nextTransitionTrigger(transitions),
          'to': targetStateId,
        });
      }
      if (transitions.isEmpty) {
        state.remove('transitions');
      } else {
        state['transitions'] = transitions;
      }
      _states[index] = state;
      _selectedStateId = sourceStateId;
      _connectionSourceId = '';
    });
  }

  /// Marks one process state as the workflow's initial state.
  void setInitialState(String stateId) {
    if (stateId.isEmpty) {
      return;
    }
    _mutateStates(() {
      final parentId = _stateMachineParentOf(_states, stateId);
      if (parentId.isEmpty) {
        _initialStateId = stateId;
      } else {
        _states = _states.map((state) {
          final next = Map<String, dynamic>.from(state);
          if (_stateId(next) == parentId) {
            next['initial'] = stateId;
          }
          return next;
        }).toList();
      }
      _selectedStateId = stateId;
    });
  }

  /// Deletes one process state and removes transitions pointing at it.
  void deleteState(String stateId) {
    if (stateId.isEmpty) {
      return;
    }
    _mutateStates(() {
      final deleted = _stateMachineDescendantIds(_states, stateId)
        ..add(stateId);
      _states = _states
          .where((state) => !deleted.contains(_stateId(state)))
          .map((state) {
            final next = Map<String, dynamic>.from(state);
            final initial = '${next['initial'] ?? ''}'.trim();
            if (deleted.contains(initial)) {
              final replacement = _stateMachineFirstChildId(
                _states,
                _stateId(next),
                excludedIds: deleted,
              );
              if (replacement.isEmpty) {
                next.remove('initial');
              } else {
                next['initial'] = replacement;
              }
            }
            final transitions = _stateTransitions(next)
                .map(_map)
                .where(
                  (transition) =>
                      !deleted.contains(_transitionTarget(transition)),
                )
                .toList();
            if (transitions.isEmpty) {
              next.remove('transitions');
            } else {
              next['transitions'] = transitions;
            }
            return next;
          })
          .toList();
      if (deleted.contains(_initialStateId)) {
        _initialStateId = _stateMachineFirstRootId(_states);
      }
      _selectedStateId = _states.isEmpty ? '' : _stateId(_states.first);
      if (deleted.contains(_connectionSourceId)) {
        _connectionSourceId = '';
      }
      for (final id in deleted) {
        _positions.remove(id);
        _collapsedPhaseIds.remove(id);
      }
    });
  }

  /// Moves one state node by a canvas drag delta.
  void moveStateBy(String stateId, Offset delta) {
    if (delta.distance < 1) {
      return;
    }
    final current = _stateMachinePositionForState(
      stateId,
      _states,
      _positions,
      _initialStateId,
    );
    _mutateStates(() {
      _positions[stateId] = Offset(
        (current.dx + delta.dx).clamp(24.0, 10000.0).toDouble(),
        (current.dy + delta.dy).clamp(24.0, 10000.0).toDouble(),
      );
      _selectedStateId = stateId;
    });
  }

  /// Renames a state and rewires transitions that target it.
  void renameState(String oldStateId, String nextStateId) {
    final nextId = nextStateId.trim();
    if (oldStateId.isEmpty ||
        nextId.isEmpty ||
        oldStateId == nextId ||
        _states.any((state) => _stateId(state) == nextId)) {
      return;
    }
    _mutateStates(() {
      _states = _states.map((state) {
        final next = Map<String, dynamic>.from(state);
        if (_stateId(next) == oldStateId) {
          next['id'] = nextId;
        }
        if ('${next['parent'] ?? ''}'.trim() == oldStateId) {
          next['parent'] = nextId;
        }
        if ('${next['initial'] ?? ''}'.trim() == oldStateId) {
          next['initial'] = nextId;
        }
        final transitions = _stateTransitions(next).map(_map).map((transition) {
          final updated = Map<String, dynamic>.from(transition);
          if (_transitionTarget(updated) == oldStateId) {
            updated['to'] = nextId;
          }
          return updated;
        }).toList();
        if (transitions.isNotEmpty) {
          next['transitions'] = transitions;
        }
        return next;
      }).toList();
      if (_initialStateId == oldStateId) {
        _initialStateId = nextId;
      }
      if (_selectedStateId == oldStateId) {
        _selectedStateId = nextId;
      }
      if (_connectionSourceId == oldStateId) {
        _connectionSourceId = nextId;
      }
      if (_collapsedPhaseIds.remove(oldStateId)) {
        _collapsedPhaseIds.add(nextId);
      }
      final position = _positions.remove(oldStateId);
      if (position != null) {
        _positions[nextId] = position;
      }
    });
  }

  /// Updates one entry action on a process state.
  void updateEntryAction(
    String stateId,
    int actionIndex,
    Map<String, dynamic> action,
  ) {
    final stateIndex = _states.indexWhere(
      (state) => _stateId(state) == stateId,
    );
    if (stateIndex < 0 || actionIndex < 0) {
      return;
    }
    _mutateStates(() {
      final state = Map<String, dynamic>.from(_states[stateIndex]);
      final actions = _stateEntryActions(
        state,
      ).map((action) => Map<String, dynamic>.from(_map(action))).toList();
      if (actionIndex >= actions.length) {
        return;
      }
      actions[actionIndex] = action;
      state['on_entry'] = actions;
      _states[stateIndex] = state;
    });
  }

  /// Updates one transition on a process state.
  void updateTransition(
    String stateId,
    int transitionIndex,
    Map<String, dynamic> transition,
  ) {
    final stateIndex = _states.indexWhere(
      (state) => _stateId(state) == stateId,
    );
    if (stateIndex < 0 || transitionIndex < 0) {
      return;
    }
    _mutateStates(() {
      final state = Map<String, dynamic>.from(_states[stateIndex]);
      final transitions = _stateTransitions(state)
          .map((transition) => Map<String, dynamic>.from(_map(transition)))
          .toList();
      if (transitionIndex >= transitions.length) {
        return;
      }
      transitions[transitionIndex] = transition;
      state['transitions'] = transitions;
      _states[stateIndex] = state;
    });
  }

  /// Returns the currently selected state, if any.
  Map<String, dynamic>? selectedState() {
    for (final state in _states) {
      if (_stateId(state) == _selectedStateId) {
        return state;
      }
    }
    return _states.isEmpty ? null : _states.first;
  }

  /// Persists pending graph edits immediately.
  Future<void> flushSave() async {
    await _saveDraft();
  }

  /// Tracks Ctrl key state for canvas pointer shortcuts.
  void trackOpenInspectorModifier(KeyEvent event) {
    if (!_isControlKey(event.logicalKey)) {
      return;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _openInspectorModifierPressed = true;
    } else if (event is KeyUpEvent) {
      _openInspectorModifierPressed = false;
    }
  }

  /// Clears the tracked Ctrl-click shortcut state after mode changes.
  void clearOpenInspectorModifier() {
    _openInspectorModifierPressed = false;
  }

  /// Observes global hardware-key modifier changes for Ctrl-click behavior.
  bool _handleHardwareKey(KeyEvent event) {
    trackOpenInspectorModifier(event);
    return false;
  }

  /// Captures the latest controller offsets before leaving the canvas.
  void captureCanvasOffset() {
    final x = _horizontalCanvasController.hasClients
        ? _horizontalCanvasController.offset
        : _canvasOffset.dx;
    final y = _verticalCanvasController.hasClients
        ? _verticalCanvasController.offset
        : _canvasOffset.dy;
    rememberCanvasOffset(Offset(x, y));
    _suppressCanvasOffsetUpdates = true;
  }

  /// Stores the latest visible canvas x/y position.
  void rememberCanvasOffset(Offset offset) {
    _canvasOffset = offset;
    final draftId = _draft?.id ?? '';
    if (draftId.isNotEmpty) {
      _stateMachineCanvasOffsetsByDraft[draftId] = offset;
    }
  }

  /// Recreates detached canvas controllers at the stored x/y offset.
  void prepareCanvasControllersForRestore() {
    if (_horizontalCanvasController.hasClients ||
        _verticalCanvasController.hasClients) {
      _suppressCanvasOffsetUpdates = false;
      return;
    }
    _detachCanvasScrollListeners();
    _horizontalCanvasController.dispose();
    _verticalCanvasController.dispose();
    _horizontalCanvasController = ScrollController(
      initialScrollOffset: _canvasOffset.dx,
    );
    _verticalCanvasController = ScrollController(
      initialScrollOffset: _canvasOffset.dy,
    );
    _suppressCanvasOffsetUpdates = false;
    _attachCanvasScrollListeners();
  }

  /// Jumps attached canvas controllers back to the stored x/y offset.
  void restoreCanvasOffset() {
    _restoreCanvasController(_horizontalCanvasController, _canvasOffset.dx);
    _restoreCanvasController(_verticalCanvasController, _canvasOffset.dy);
  }

  /// Attaches x/y tracking to the live canvas scroll controllers.
  void _attachCanvasScrollListeners() {
    _horizontalCanvasController.addListener(_rememberCanvasControllerOffset);
    _verticalCanvasController.addListener(_rememberCanvasControllerOffset);
  }

  /// Detaches x/y tracking before replacing canvas scroll controllers.
  void _detachCanvasScrollListeners() {
    _horizontalCanvasController.removeListener(_rememberCanvasControllerOffset);
    _verticalCanvasController.removeListener(_rememberCanvasControllerOffset);
  }

  /// Tracks user-visible canvas scroll movement while the canvas is mounted.
  void _rememberCanvasControllerOffset() {
    if (_suppressCanvasOffsetUpdates ||
        !_horizontalCanvasController.hasClients ||
        !_verticalCanvasController.hasClients) {
      return;
    }
    rememberCanvasOffset(
      Offset(
        _horizontalCanvasController.offset,
        _verticalCanvasController.offset,
      ),
    );
  }

  /// Restores one attached scroll controller without animation.
  void _restoreCanvasController(ScrollController controller, double offset) {
    if (!controller.hasClients) {
      return;
    }
    final position = controller.position;
    final target = offset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((position.pixels - target).abs() < 0.5) {
      return;
    }
    controller.jumpTo(target);
  }

  /// Copies the selected draft body into local builder state.
  void _loadDraft(AutomationDraft draft) {
    final body = _map(draft.body);
    final states = _stateMachineFlattenedStatesFromBody(body);
    final initial = '${body['initial'] ?? ''}'.trim();
    _states = states;
    _initialStateId = initial;
    if (_selectedStateId.isEmpty ||
        !_states.any((state) => _stateId(state) == _selectedStateId)) {
      _selectedStateId = initial.isNotEmpty
          ? initial
          : _states.isEmpty
          ? ''
          : _stateId(_states.first);
    }
    _connectionSourceId = '';
    _positions = _stateMachinePositionsFromAuthoring(body);
    _collapsedPhaseIds = _stateMachineCollapsedPhasesFromAuthoring(body);
  }

  /// Applies a local graph mutation and schedules persistence.
  void _mutateStates(VoidCallback mutate) {
    mutate();
    notifyListeners();
    _scheduleSave();
  }

  /// Debounces draft persistence for canvas edit gestures.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(_saveDraft()));
  }

  /// Persists the current process-state graph to the workflow draft.
  Future<void> _saveDraft() async {
    _saveTimer?.cancel();
    if (controller.automationsBusy) {
      _scheduleSave();
      return;
    }
    final current = _currentDraft();
    if (current == null) {
      return;
    }
    _draft = current;
    await controller.saveAutomationDraftFromUi(current);
  }

  /// Builds the draft payload represented by the local graph.
  AutomationDraft? _currentDraft() {
    final source = _draft;
    if (source == null) {
      return null;
    }
    final body = Map<String, dynamic>.from(_map(source.body));
    body
      ..['kind'] = 'state_machine'
      ..['id'] = '${body['id'] ?? source.id}'
      ..['name'] = source.name
      ..['description'] = source.description
      ..['states'] = <Map<String, dynamic>>[
        for (final state in _stateMachineNestedStates(_states))
          Map<String, dynamic>.from(state),
      ];
    if (_initialStateId.isEmpty) {
      body.remove('initial');
    } else {
      body['initial'] = _initialStateId;
    }
    body['authoring'] = _stateMachineAuthoringWithPositions(
      _map(body['authoring']),
      _positions,
      _collapsedPhaseIds,
    );
    return AutomationDraft(
      id: source.id,
      kind: source.kind,
      name: source.name,
      description: source.description,
      status: source.status,
      body: body,
      validation: source.validation,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
    );
  }

  /// Creates a stable draft fingerprint for reload decisions.
  String _fingerprintForDraft(AutomationDraft draft) {
    return jsonEncode(<String, Object?>{
      'id': draft.id,
      'updated_at': draft.updatedAt,
      'body': draft.body,
    });
  }
}

/// Stores per-draft canvas viewport offsets for the active UI session.
final Map<String, Offset> _stateMachineCanvasOffsetsByDraft =
    <String, Offset>{};

/// _StateMachineBuilderWorkspace keeps canvas and inspector mode state alive.
class _StateMachineBuilderWorkspace extends StatelessWidget {
  /// Creates a process-state authoring workspace for Builder and Inspect modes.
  const _StateMachineBuilderWorkspace({
    super.key,
    required this.editor,
    required this.controller,
    required this.draft,
    required this.modeId,
    required this.onDetailModeRequested,
  });

  /// Shared process-state editor.
  final _StateMachineDraftEditController editor;

  /// Shared app controller used by builder and inspector children.
  final AgentAwesomeAppController controller;

  /// Workflow draft being edited.
  final AutomationDraft draft;

  /// Active right-pane mode id.
  final String modeId;

  /// Requests a right-side detail mode change.
  final ValueChanged<String> onDetailModeRequested;

  /// Builds one visible mode while keeping its sibling mounted.
  @override
  Widget build(BuildContext context) {
    final inspecting = modeId == _automationDetailInspect;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleModeKey,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              ignoring: inspecting,
              child: Opacity(
                opacity: inspecting ? 0 : 1,
                child: _StateMachineBuilderDetail(
                  editor: editor,
                  controller: controller,
                  draft: draft,
                  onDetailModeRequested: onDetailModeRequested,
                ),
              ),
            ),
          ),
          if (inspecting)
            Positioned.fill(
              child: _StateMachineInspectorDetail(
                editor: editor,
                controller: controller,
                draft: draft,
                onDetailModeRequested: onDetailModeRequested,
              ),
            ),
        ],
      ),
    );
  }

  /// Handles workspace-level keyboard transitions between canvas and inspector.
  KeyEventResult _handleModeKey(FocusNode node, KeyEvent event) {
    editor.trackOpenInspectorModifier(event);
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        modeId == _automationDetailInspect) {
      editor.clearOpenInspectorModifier();
      editor.prepareCanvasControllersForRestore();
      onDetailModeRequested(_automationDetailBuilder);
      return KeyEventResult.handled;
    }
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        modeId == _automationDetailBuilder &&
        editor.selectedStateId.isNotEmpty) {
      editor.captureCanvasOffset();
      editor.clearOpenInspectorModifier();
      onDetailModeRequested(_automationDetailInspect);
      return KeyEventResult.handled;
    }
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        modeId == _automationDetailInspect) {
      unawaited(editor.flushSave());
      editor.clearOpenInspectorModifier();
      editor.prepareCanvasControllersForRestore();
      onDetailModeRequested(_automationDetailBuilder);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// _StateMachineBuilderDetail renders the canvas-only workflow builder.
class _StateMachineBuilderDetail extends StatefulWidget {
  /// Creates a state-machine builder bound to one automation draft.
  const _StateMachineBuilderDetail({
    required this.editor,
    required this.controller,
    required this.draft,
    required this.onDetailModeRequested,
  });

  /// Shared process-state editor.
  final _StateMachineDraftEditController editor;

  /// Shared app controller used to resolve action metadata.
  final AgentAwesomeAppController controller;

  /// Workflow draft being edited.
  final AutomationDraft draft;

  /// Requests a right-side detail mode change from inside the builder.
  final ValueChanged<String> onDetailModeRequested;

  /// Creates builder state for palette intent subscriptions.
  @override
  State<_StateMachineBuilderDetail> createState() =>
      _StateMachineBuilderDetailState();
}

/// _StateMachineBuilderDetailState connects shell intents to the canvas.
class _StateMachineBuilderDetailState
    extends State<_StateMachineBuilderDetail> {
  _TaskGraphActionIntentController? _actionIntents;
  int _lastActionIntentRevision = 0;

  /// Loads editable process-state data from the selected workflow draft.
  @override
  void initState() {
    super.initState();
    widget.editor.attachDraft(widget.draft);
  }

  /// Reloads state-machine data when the selected workflow draft changes.
  @override
  void didUpdateWidget(covariant _StateMachineBuilderDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.editor.attachDraft(widget.draft);
  }

  /// Releases palette intent subscriptions.
  @override
  void dispose() {
    _actionIntents?.removeListener(_handleActionIntent);
    super.dispose();
  }

  /// Subscribes to the shell-owned workflow action palette.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextIntents = _TaskGraphActionIntentScope.maybeOf(context);
    if (nextIntents == _actionIntents) {
      return;
    }
    _actionIntents?.removeListener(_handleActionIntent);
    _actionIntents = nextIntents;
    _lastActionIntentRevision = nextIntents?.revision ?? 0;
    _actionIntents?.addListener(_handleActionIntent);
  }

  /// Builds the visual state-machine builder.
  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleCanvasKey,
      child: AnimatedBuilder(
        animation: widget.editor,
        builder: (context, _) {
          return _StateMachineCanvasViewport(
            key: const ValueKey<String>('state-machine-canvas'),
            states: widget.editor.states,
            positions: widget.editor.positions,
            collapsedPhaseIds: widget.editor.collapsedPhaseIds,
            initialStateId: widget.editor.initialStateId,
            selectedStateId: widget.editor.selectedStateId,
            connectionSourceId: widget.editor.connectionSourceId,
            canvasOffset: widget.editor.canvasOffset,
            horizontalScrollController:
                widget.editor.horizontalCanvasController,
            verticalScrollController: widget.editor.verticalCanvasController,
            zoom: widget.editor.zoom,
            onCanvasOffsetChanged: widget.editor.rememberCanvasOffset,
            onZoomChanged: widget.editor.setZoom,
            onSelectState: widget.editor.selectOrConnectState,
            onStartConnection: widget.editor.startConnection,
            onSetInitial: widget.editor.setInitialState,
            onDeleteState: widget.editor.deleteState,
            onAddState: widget.editor.addStateFromPalette,
            onAddStateToPhase: widget.editor.addStateToPhase,
            onAddEntryAction: widget.editor.addEntryActionToState,
            onTogglePhaseCollapsed: widget.editor.togglePhaseCollapsed,
            onMoveStateBy: widget.editor.moveStateBy,
            isOpenInspectorModifierPressed: () =>
                widget.editor.openInspectorModifierPressed,
            onOpenInspector: _openInspector,
          );
        },
      ),
    );
  }

  /// Adds a state from the shell-owned node palette.
  void _handleActionIntent() {
    final intents = _actionIntents;
    if (intents == null || intents.revision == _lastActionIntentRevision) {
      return;
    }
    _lastActionIntentRevision = intents.revision;
    widget.editor.addStateFromPalette(intents.actionName);
  }

  /// Opens the selected-state inspector right mode.
  void _openInspector(String stateId) {
    if (stateId.isEmpty) {
      return;
    }
    widget.editor.captureCanvasOffset();
    widget.editor.selectState(stateId);
    widget.editor.clearOpenInspectorModifier();
    widget.onDetailModeRequested(_automationDetailInspect);
  }

  /// Opens the inspector for the current canvas selection.
  void _openSelectedInspector() {
    _openInspector(widget.editor.selectedStateId);
  }

  /// Handles canvas-level keyboard navigation.
  KeyEventResult _handleCanvasKey(FocusNode node, KeyEvent event) {
    widget.editor.trackOpenInspectorModifier(event);
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _openSelectedInspector();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.editor.cancelConnection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// _StateMachineInspectorDetail renders selected-state editing as a mode.
class _StateMachineInspectorDetail extends StatefulWidget {
  /// Creates a full-width selected-state inspector for one workflow draft.
  const _StateMachineInspectorDetail({
    required this.editor,
    required this.controller,
    required this.draft,
    required this.onDetailModeRequested,
  });

  /// Shared process-state editor.
  final _StateMachineDraftEditController editor;

  /// Shared app controller used to resolve action metadata.
  final AgentAwesomeAppController controller;

  /// Workflow draft being edited.
  final AutomationDraft draft;

  /// Requests a right-side detail mode change from inside the inspector.
  final ValueChanged<String> onDetailModeRequested;

  /// Creates inspector mode state.
  @override
  State<_StateMachineInspectorDetail> createState() =>
      _StateMachineInspectorDetailState();
}

/// _StateMachineInspectorDetailState wires keyboard flow for inspection.
class _StateMachineInspectorDetailState
    extends State<_StateMachineInspectorDetail> {
  /// Attaches the shared editor to the selected draft.
  @override
  void initState() {
    super.initState();
    widget.editor.attachDraft(widget.draft);
  }

  /// Reloads editor state when the selected draft changes.
  @override
  void didUpdateWidget(covariant _StateMachineInspectorDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.editor.attachDraft(widget.draft);
  }

  /// Builds the selected-state inspector mode.
  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleInspectorKey,
      child: AnimatedBuilder(
        animation: widget.editor,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            child: SizedBox.expand(
              child: _StateMachineInspector(
                state: widget.editor.selectedState(),
                stateIds: widget.editor.states
                    .map(_stateId)
                    .where((id) => id.isNotEmpty)
                    .toList(),
                actionNames: _resolvedAutomationActionTypes(
                  widget.controller,
                ).map((action) => action.name).toList(),
                initialStateId: widget.editor.initialStateId,
                connectionSourceId: widget.editor.connectionSourceId,
                onSetInitial: widget.editor.setInitialState,
                onStartConnection: widget.editor.startConnection,
                onDeleteState: widget.editor.deleteState,
                onRenameState: widget.editor.renameState,
                onUpdateEntryAction: widget.editor.updateEntryAction,
                onUpdateTransition: widget.editor.updateTransition,
                onSubmitEdit: _submitAndReturn,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Saves the current edit buffer and returns to the canvas.
  void _submitAndReturn() {
    unawaited(widget.editor.flushSave());
    _returnToBuilder();
  }

  /// Returns to the canvas without forcing a pending save.
  void _returnToBuilder() {
    widget.editor.clearOpenInspectorModifier();
    widget.editor.prepareCanvasControllersForRestore();
    widget.onDetailModeRequested(_automationDetailBuilder);
  }

  /// Handles inspector-level keyboard navigation.
  KeyEventResult _handleInspectorKey(FocusNode node, KeyEvent event) {
    widget.editor.trackOpenInspectorModifier(event);
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _returnToBuilder();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submitAndReturn();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// _StateMachinePalette lists draggable state and action templates.
class _StateMachinePalette extends StatelessWidget {
  /// Creates a process-state palette from available action types.
  const _StateMachinePalette({
    required this.actionTypes,
    required this.query,
    required this.onAddState,
  });

  /// Workflow actions available for entry-action states.
  final List<AutomationActionType> actionTypes;

  /// Left-pane filter query.
  final String query;

  /// Adds a new state from a selected palette action.
  final ValueChanged<String> onAddState;

  /// Builds the draggable process-state node palette.
  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final items =
        <_StateMachinePaletteItem>[
          const _StateMachinePaletteItem(
            actionName: _inputStatePaletteAction,
            label: 'Input',
            description: 'Run input contract',
            icon: Icons.input_outlined,
          ),
          for (final action in actionTypes)
            _StateMachinePaletteItem(
              actionName: action.name,
              label: action.label,
              description: action.description,
              icon: _actionIcon(action.name),
            ),
          const _StateMachinePaletteItem(
            actionName: _terminalStatePaletteAction,
            label: 'Terminal',
            description: 'Done or abandoned state',
            icon: Icons.stop_circle_outlined,
          ),
        ].where((item) {
          if (normalizedQuery.isEmpty) {
            return true;
          }
          return item.label.toLowerCase().contains(normalizedQuery) ||
              item.description.toLowerCase().contains(normalizedQuery) ||
              item.actionName.toLowerCase().contains(normalizedQuery);
        }).toList();
    if (items.isEmpty) {
      return KeyedSubtree(
        key: const ValueKey<String>('state-machine-palette'),
        child: PanelEmptyState(query: query),
      );
    }
    return ListView.separated(
      key: const ValueKey<String>('state-machine-palette'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return _StateMachinePaletteTile(
          item: item,
          onAdd: () => onAddState(item.actionName),
        );
      },
    );
  }
}

/// _StateMachinePaletteTile renders one draggable palette item.
class _StateMachinePaletteTile extends StatelessWidget {
  /// Creates one palette tile with tap and drag behavior.
  const _StateMachinePaletteTile({required this.item, required this.onAdd});

  /// Palette item metadata.
  final _StateMachinePaletteItem item;

  /// Adds this item to the workflow graph.
  final VoidCallback onAdd;

  /// Builds one draggable palette item for process-state creation.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final tile = PanelSurface(
      style: PanelSurfaceStyle.card,
      padding: const EdgeInsets.all(10),
      child: Row(
        children: <Widget>[
          _StateMachineNodeIcon(
            icon: item.icon,
            color: _stateMachinePaletteColor(context, item.actionName),
            size: 32,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
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
    return Draggable<_StateMachinePaletteDragData>(
      data: _StateMachinePaletteDragData(item.actionName),
      feedback: SizedBox(
        width: 210,
        child: Material(color: Colors.transparent, child: tile),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: tile),
      child: InkWell(
        key: ValueKey<String>('state-machine-palette-${item.actionName}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onAdd,
        child: tile,
      ),
    );
  }
}

/// _StateMachineCanvasViewport lays out the scrollable state graph.
class _StateMachineCanvasViewport extends StatefulWidget {
  /// Creates the interactive process-state canvas viewport.
  const _StateMachineCanvasViewport({
    super.key,
    required this.states,
    required this.positions,
    required this.collapsedPhaseIds,
    required this.initialStateId,
    required this.selectedStateId,
    required this.connectionSourceId,
    required this.canvasOffset,
    required this.horizontalScrollController,
    required this.verticalScrollController,
    required this.zoom,
    required this.onCanvasOffsetChanged,
    required this.onZoomChanged,
    required this.onSelectState,
    required this.onStartConnection,
    required this.onSetInitial,
    required this.onDeleteState,
    required this.onAddState,
    required this.onAddStateToPhase,
    required this.onAddEntryAction,
    required this.onTogglePhaseCollapsed,
    required this.onMoveStateBy,
    required this.isOpenInspectorModifierPressed,
    required this.onOpenInspector,
  });

  final List<Map<String, dynamic>> states;
  final Map<String, Offset> positions;
  final Set<String> collapsedPhaseIds;
  final String initialStateId;
  final String selectedStateId;
  final String connectionSourceId;
  final Offset canvasOffset;
  final ScrollController horizontalScrollController;
  final ScrollController verticalScrollController;
  final double zoom;
  final ValueChanged<Offset> onCanvasOffsetChanged;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<String> onSelectState;
  final ValueChanged<String> onStartConnection;
  final ValueChanged<String> onSetInitial;
  final ValueChanged<String> onDeleteState;
  final ValueChanged<String> onAddState;
  final void Function(String parentStateId, String actionName)
  onAddStateToPhase;
  final void Function(String stateId, String actionName) onAddEntryAction;
  final ValueChanged<String> onTogglePhaseCollapsed;
  final void Function(String stateId, Offset delta) onMoveStateBy;
  final bool Function() isOpenInspectorModifierPressed;
  final ValueChanged<String> onOpenInspector;

  /// Builds the scrollable process-state graph canvas.
  @override
  State<_StateMachineCanvasViewport> createState() =>
      _StateMachineCanvasViewportState();
}

/// _StateMachineCanvasViewportState preserves the graph viewport position.
class _StateMachineCanvasViewportState
    extends State<_StateMachineCanvasViewport> {
  final Map<String, Offset> _dragPreviewOffsets = <String, Offset>{};
  _StateMachineEdgeViewMode _edgeViewMode = _StateMachineEdgeViewMode.success;

  /// Restores the last known x/y canvas position after the viewport attaches.
  @override
  void initState() {
    super.initState();
    _restoreCanvasOffset();
  }

  /// Restores the x/y position when a different scroll controller is attached.
  @override
  void didUpdateWidget(covariant _StateMachineCanvasViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.horizontalScrollController !=
            widget.horizontalScrollController ||
        oldWidget.verticalScrollController != widget.verticalScrollController) {
      _restoreCanvasOffset();
    }
  }

  /// Captures the current x/y position before the canvas unmounts.
  @override
  void dispose() {
    _captureCanvasOffset();
    super.dispose();
  }

  /// Builds the scrollable process-state graph canvas.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final layout = _StateMachineCanvasLayout.fromStates(
      widget.states,
      initialStateId: widget.initialStateId,
      positions: _effectivePositions(),
      collapsedPhaseIds: widget.collapsedPhaseIds,
      edgeViewMode: _edgeViewMode,
      selectedStateId: widget.selectedStateId,
    );
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
              child: DragTarget<_StateMachinePaletteDragData>(
                onWillAcceptWithDetails: (details) => true,
                onAcceptWithDetails: (details) {
                  widget.onAddState(details.data.actionName);
                },
                builder: (context, candidateData, rejectedData) {
                  return DecoratedBox(
                    decoration: BoxDecoration(color: colors.surface),
                    child: widget.states.isEmpty
                        ? const Center(
                            child: PanelEmptyBlock(label: 'No states'),
                          )
                        : ClipRect(
                            child: SingleChildScrollView(
                              key: const PageStorageKey<String>(
                                'state-machine-canvas-horizontal-scroll',
                              ),
                              controller: widget.horizontalScrollController,
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                key: const PageStorageKey<String>(
                                  'state-machine-canvas-vertical-scroll',
                                ),
                                controller: widget.verticalScrollController,
                                child: Transform.scale(
                                  scale: widget.zoom,
                                  alignment: Alignment.topLeft,
                                  child: SizedBox(
                                    width: contentSize.width,
                                    height: contentSize.height,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: <Widget>[
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: _StateMachineCanvasPainter(
                                              layout: layout,
                                              colors: colors,
                                              selectedStateId:
                                                  widget.selectedStateId,
                                            ),
                                          ),
                                        ),
                                        for (final phase in layout.phases)
                                          Positioned.fromRect(
                                            rect: phase.rect,
                                            child:
                                                DragTarget<
                                                  _StateMachinePaletteDragData
                                                >(
                                                  key: ValueKey<String>(
                                                    'state-machine-phase-drop-${phase.stateId}',
                                                  ),
                                                  onWillAcceptWithDetails:
                                                      (details) =>
                                                          details
                                                              .data
                                                              .actionName !=
                                                          _terminalStatePaletteAction,
                                                  onAcceptWithDetails:
                                                      (details) {
                                                        widget
                                                            .onAddStateToPhase(
                                                              phase.stateId,
                                                              details
                                                                  .data
                                                                  .actionName,
                                                            );
                                                      },
                                                  builder:
                                                      (
                                                        context,
                                                        candidateData,
                                                        rejectedData,
                                                      ) =>
                                                          const SizedBox.expand(),
                                                ),
                                          ),
                                        for (final placement
                                            in layout.placements)
                                          Positioned.fromRect(
                                            rect: placement.rect,
                                            child: _StateMachineCanvasNodeCard(
                                              key: ValueKey<String>(
                                                'state-machine-node-${_stateId(placement.state)}',
                                              ),
                                              state: placement.state,
                                              childCount: placement.childCount,
                                              collapsed: widget
                                                  .collapsedPhaseIds
                                                  .contains(
                                                    _stateId(placement.state),
                                                  ),
                                              initial:
                                                  _stateId(placement.state) ==
                                                      widget.initialStateId ||
                                                  _stateMachineIsPhaseInitial(
                                                    widget.states,
                                                    _stateId(placement.state),
                                                  ),
                                              selected:
                                                  _stateId(placement.state) ==
                                                  widget.selectedStateId,
                                              connectingFromThis:
                                                  _stateId(placement.state) ==
                                                  widget.connectionSourceId,
                                              connectionTarget:
                                                  widget
                                                      .connectionSourceId
                                                      .isNotEmpty &&
                                                  _stateId(placement.state) !=
                                                      widget.connectionSourceId,
                                              onTap: () => widget.onSelectState(
                                                _stateId(placement.state),
                                              ),
                                              onStartConnection: () =>
                                                  widget.onStartConnection(
                                                    _stateId(placement.state),
                                                  ),
                                              onSetInitial: () =>
                                                  widget.onSetInitial(
                                                    _stateId(placement.state),
                                                  ),
                                              onDeleteState: () =>
                                                  widget.onDeleteState(
                                                    _stateId(placement.state),
                                                  ),
                                              onAddStateToPhase:
                                                  widget.onAddStateToPhase,
                                              onAddEntryAction:
                                                  widget.onAddEntryAction,
                                              onTogglePhaseCollapsed: () =>
                                                  widget.onTogglePhaseCollapsed(
                                                    _stateId(placement.state),
                                                  ),
                                              onPreviewMoveBy:
                                                  _previewStateMoveBy,
                                              onMoveStateBy: _commitStateMoveBy,
                                              onCancelMove: _cancelStateMove,
                                              isOpenInspectorModifierPressed: widget
                                                  .isOpenInspectorModifierPressed,
                                              onOpenInspector:
                                                  widget.onOpenInspector,
                                            ),
                                          ),
                                        for (final badge in layout.exitBadges)
                                          Positioned.fromRect(
                                            rect: badge.rect,
                                            child: _StateMachineExitBadge(
                                              badge: badge,
                                              onPressed: () =>
                                                  _focusBadgeTarget(
                                                    badge,
                                                    layout,
                                                    Size(
                                                      viewportWidth,
                                                      viewportHeight,
                                                    ),
                                                  ),
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
              child: _StateMachineCanvasControls(
                zoom: widget.zoom,
                edgeViewMode: _edgeViewMode,
                onZoomChanged: widget.onZoomChanged,
                onEdgeViewModeChanged: (mode) {
                  setState(() => _edgeViewMode = mode);
                },
              ),
            ),
            if (widget.states.isNotEmpty)
              Positioned(
                right: 16,
                bottom: 14,
                child: _StateMachineMiniMap(layout: layout),
              ),
          ],
        );
      },
    );
  }

  /// Schedules a post-layout scroll restoration.
  void _restoreCanvasOffset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _jumpToStoredOffset(
        widget.horizontalScrollController,
        widget.canvasOffset.dx != 0
            ? widget.canvasOffset.dx
            : widget.horizontalScrollController.initialScrollOffset,
      );
      _jumpToStoredOffset(
        widget.verticalScrollController,
        widget.canvasOffset.dy != 0
            ? widget.canvasOffset.dy
            : widget.verticalScrollController.initialScrollOffset,
      );
    });
  }

  /// Stores the current scroll-controller x/y offset.
  void _captureCanvasOffset() {
    final x = widget.horizontalScrollController.hasClients
        ? widget.horizontalScrollController.offset
        : widget.canvasOffset.dx;
    final y = widget.verticalScrollController.hasClients
        ? widget.verticalScrollController.offset
        : widget.canvasOffset.dy;
    widget.onCanvasOffsetChanged(Offset(x, y));
  }

  /// Restores one axis while staying inside the attached scroll extent.
  void _jumpToStoredOffset(ScrollController controller, double target) {
    if (!controller.hasClients) {
      return;
    }
    final position = controller.position;
    final bounded = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((position.pixels - bounded).abs() < 0.5) {
      return;
    }
    controller.jumpTo(bounded);
  }

  /// Returns committed positions plus any active drag preview position.
  Map<String, Offset> _effectivePositions() {
    if (_dragPreviewOffsets.isEmpty) {
      return widget.positions;
    }
    final positions = Map<String, Offset>.from(widget.positions);
    for (final entry in _dragPreviewOffsets.entries) {
      final base = _stateMachinePositionForState(
        entry.key,
        widget.states,
        widget.positions,
        widget.initialStateId,
      );
      positions[entry.key] = Offset(
        (base.dx + entry.value.dx).clamp(24.0, 10000.0).toDouble(),
        (base.dy + entry.value.dy).clamp(24.0, 10000.0).toDouble(),
      );
    }
    return positions;
  }

  /// Previews a node move in the shared canvas layout without saving it.
  void _previewStateMoveBy(String stateId, Offset delta) {
    if (!mounted) {
      return;
    }
    setState(() {
      if (delta.distance < 0.5) {
        _dragPreviewOffsets.remove(stateId);
      } else {
        _dragPreviewOffsets[stateId] = delta;
      }
    });
  }

  /// Persists the final node move and clears the transient preview.
  void _commitStateMoveBy(String stateId, Offset delta) {
    if (mounted) {
      setState(() => _dragPreviewOffsets.remove(stateId));
    }
    widget.onMoveStateBy(stateId, delta);
  }

  /// Cancels a transient node move preview.
  void _cancelStateMove(String stateId) {
    if (!mounted || !_dragPreviewOffsets.containsKey(stateId)) {
      return;
    }
    setState(() => _dragPreviewOffsets.remove(stateId));
  }

  /// Selects and scrolls toward the visible target represented by an exit badge.
  void _focusBadgeTarget(
    _StateMachineExitBadgePlacement badge,
    _StateMachineCanvasLayout layout,
    Size viewportSize,
  ) {
    final targetId = badge.visibleTargetStateId.isNotEmpty
        ? badge.visibleTargetStateId
        : badge.targetStateId;
    final placement = layout.byId[targetId];
    if (placement == null) {
      return;
    }
    widget.onSelectState(targetId);
    _centerPlacement(placement.rect, viewportSize);
  }

  /// Centers one visible canvas placement inside the current viewport.
  void _centerPlacement(Rect rect, Size viewportSize) {
    _centerScrollController(
      widget.horizontalScrollController,
      rect.center.dx * widget.zoom - viewportSize.width / 2,
    );
    _centerScrollController(
      widget.verticalScrollController,
      rect.center.dy * widget.zoom - viewportSize.height / 2,
    );
  }

  /// Moves one scroll controller toward a bounded target offset.
  void _centerScrollController(ScrollController controller, double target) {
    if (!controller.hasClients) {
      return;
    }
    final position = controller.position;
    final bounded = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    controller.animateTo(
      bounded,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }
}

/// _StateMachineCanvasControls renders canvas zoom and edge-visibility modes.
class _StateMachineCanvasControls extends StatelessWidget {
  /// Creates the shared state-machine canvas control strip.
  const _StateMachineCanvasControls({
    required this.zoom,
    required this.edgeViewMode,
    required this.onZoomChanged,
    required this.onEdgeViewModeChanged,
  });

  /// Current zoom factor.
  final double zoom;

  /// Active edge visibility mode.
  final _StateMachineEdgeViewMode edgeViewMode;

  /// Handles zoom changes.
  final ValueChanged<double> onZoomChanged;

  /// Handles edge mode changes.
  final ValueChanged<_StateMachineEdgeViewMode> onEdgeViewModeChanged;

  /// Builds functional canvas controls.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TaskGraphGraphMenu(zoom: zoom, onZoomChanged: onZoomChanged),
        const SizedBox(width: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.panel.withValues(alpha: 0.95),
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final mode in _StateMachineEdgeViewMode.values)
                _StateMachineEdgeModeButton(
                  mode: mode,
                  selected: mode == edgeViewMode,
                  onPressed: () => onEdgeViewModeChanged(mode),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// _StateMachineEdgeModeButton renders one compact edge-view segment.
class _StateMachineEdgeModeButton extends StatelessWidget {
  /// Creates one selectable edge-mode segment.
  const _StateMachineEdgeModeButton({
    required this.mode,
    required this.selected,
    required this.onPressed,
  });

  /// Segment mode.
  final _StateMachineEdgeViewMode mode;

  /// Whether this segment is active.
  final bool selected;

  /// Handles segment selection.
  final VoidCallback onPressed;

  /// Builds a compact text segment.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: mode.tooltip,
      child: InkWell(
        key: ValueKey<String>('state-machine-edge-mode-${mode.id}'),
        onTap: onPressed,
        child: Container(
          height: 32,
          constraints: const BoxConstraints(minWidth: 58),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? colors.greenSoft : Colors.transparent,
            border: Border(
              right: BorderSide(
                color: mode == _StateMachineEdgeViewMode.values.last
                    ? Colors.transparent
                    : colors.border,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            mode.label,
            style: TextStyle(
              color: selected ? colors.ink : colors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// _StateMachineExitBadge renders one clickable aggregated transition exit.
class _StateMachineExitBadge extends StatelessWidget {
  /// Creates a clickable off-path exit badge.
  const _StateMachineExitBadge({required this.badge, required this.onPressed});

  /// Badge placement and transition summary.
  final _StateMachineExitBadgePlacement badge;

  /// Selects and scrolls to the badge target.
  final VoidCallback onPressed;

  /// Builds an action badge adjacent to its source node or phase.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final detail = badge.count > 1
        ? 'Go to ${badge.visibleTargetStateId} (${badge.count} exits)'
        : 'Go to ${badge.visibleTargetStateId}';
    return Tooltip(
      message: detail,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('state-machine-exit-badge-${badge.id}'),
          borderRadius: BorderRadius.circular(PanelStyleTokens.compactRadius),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: colors.panel.withValues(alpha: 0.96),
              border: Border.all(color: colors.coral.withValues(alpha: 0.74)),
              borderRadius: BorderRadius.circular(
                PanelStyleTokens.compactRadius,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: colors.surface.withValues(alpha: 0.42),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.call_made, size: 13, color: colors.coral),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    badge.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// _StateMachineCanvasNodeCard renders one state node on the canvas.
class _StateMachineCanvasNodeCard extends StatelessWidget {
  /// Creates one selectable state-machine canvas node.
  const _StateMachineCanvasNodeCard({
    super.key,
    required this.state,
    required this.childCount,
    required this.collapsed,
    required this.initial,
    required this.selected,
    required this.connectingFromThis,
    required this.connectionTarget,
    required this.onTap,
    required this.onStartConnection,
    required this.onSetInitial,
    required this.onDeleteState,
    required this.onAddStateToPhase,
    required this.onAddEntryAction,
    required this.onTogglePhaseCollapsed,
    required this.onPreviewMoveBy,
    required this.onMoveStateBy,
    required this.onCancelMove,
    required this.isOpenInspectorModifierPressed,
    required this.onOpenInspector,
  });

  final Map<String, dynamic> state;
  final int childCount;
  final bool collapsed;
  final bool initial;
  final bool selected;
  final bool connectingFromThis;
  final bool connectionTarget;
  final VoidCallback onTap;
  final VoidCallback onStartConnection;
  final VoidCallback onSetInitial;
  final VoidCallback onDeleteState;
  final void Function(String parentStateId, String actionName)
  onAddStateToPhase;
  final void Function(String stateId, String actionName) onAddEntryAction;
  final VoidCallback onTogglePhaseCollapsed;
  final void Function(String stateId, Offset delta) onPreviewMoveBy;
  final void Function(String stateId, Offset delta) onMoveStateBy;
  final ValueChanged<String> onCancelMove;
  final bool Function() isOpenInspectorModifierPressed;
  final ValueChanged<String> onOpenInspector;

  /// Builds one selectable process-state node on the workflow canvas.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final stateId = _stateId(state);
    final actions = _stateEntryActions(state);
    final transitions = _stateTransitions(state);
    final primaryAction = actions.isEmpty
        ? _terminalStatePaletteAction
        : '${_map(actions.first)['uses'] ?? ''}';
    var controlPressedOnTapDown = false;
    var handledTapDown = false;
    return DragTarget<_StateMachinePaletteDragData>(
      onWillAcceptWithDetails: (details) =>
          details.data.actionName != _terminalStatePaletteAction,
      onAcceptWithDetails: (details) {
        if (childCount > 0) {
          onAddStateToPhase(stateId, details.data.actionName);
        } else {
          onAddEntryAction(stateId, details.data.actionName);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final active = candidateData.isNotEmpty;
        return _StateMachineNodeDragTracker(
          stateId: stateId,
          onPointerDown: () {
            controlPressedOnTapDown = isOpenInspectorModifierPressed();
            if (controlPressedOnTapDown) {
              onOpenInspector(stateId);
            } else {
              onTap();
            }
            handledTapDown = true;
          },
          onPreviewMoveBy: onPreviewMoveBy,
          onMoveStateBy: onMoveStateBy,
          onCancelMove: onCancelMove,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: _stateMachineNodeCardHeight,
                child: InkWell(
                  onTapDown: (_) {
                    controlPressedOnTapDown = isOpenInspectorModifierPressed();
                  },
                  onTap: () {
                    if (handledTapDown) {
                      handledTapDown = false;
                      return;
                    }
                    _handleTap(stateId, controlPressedOnTapDown);
                  },
                  onDoubleTap: () => onOpenInspector(stateId),
                  child: PanelSurface(
                    selected:
                        selected ||
                        active ||
                        connectingFromThis ||
                        connectionTarget,
                    style: PanelSurfaceStyle.card,
                    borderRadius: BorderRadius.zero,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            _StateMachineNodeIcon(
                              icon: _stateMachineNodeIcon(primaryAction),
                              color: _stateMachinePaletteColor(
                                context,
                                primaryAction,
                              ),
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                stateId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (initial)
                              Icon(Icons.flag, size: 15, color: colors.green),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          actions.isEmpty
                              ? 'terminal'
                              : '${_map(actions.first)['id'] ?? 'entry'} · ${_map(actions.first)['uses'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                        const Spacer(),
                        SizedBox(
                          height: 26,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: <Widget>[
                                if (initial) ...const <Widget>[
                                  PanelBadge(label: 'initial'),
                                  SizedBox(width: 6),
                                ],
                                PanelBadge(label: '${actions.length} actions'),
                                const SizedBox(width: 6),
                                PanelBadge(
                                  label: childCount > 0
                                      ? '$childCount states'
                                      : '${transitions.length} exits',
                                ),
                                if (childCount > 0) ...<Widget>[
                                  const SizedBox(width: 6),
                                  PanelBadge(
                                    label: collapsed ? 'collapsed' : 'phase',
                                  ),
                                ],
                                for (final transition in transitions.take(
                                  2,
                                )) ...<Widget>[
                                  const SizedBox(width: 6),
                                  PanelBadge(
                                    label:
                                        '${_transitionTrigger(_map(transition))} -> ${_transitionTarget(_map(transition))}',
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (childCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: PanelInlineIconButton(
                    icon: collapsed ? Icons.unfold_more : Icons.unfold_less,
                    tooltip: collapsed ? 'Expand phase' : 'Collapse phase',
                    onPressed: onTogglePhaseCollapsed,
                  ),
                ),
              if (selected)
                Positioned(
                  left: 8,
                  top: _stateMachineNodeCardHeight + 6,
                  child: KeyedSubtree(
                    key: ValueKey<String>(
                      'state-machine-node-toolbar-$stateId',
                    ),
                    child: _StateMachineNodeToolbar(
                      connectingFromThis: connectingFromThis,
                      onStartConnection: onStartConnection,
                      onSetInitial: onSetInitial,
                      onDeleteState: onDeleteState,
                      onOpenInspector: () => onOpenInspector(stateId),
                    ),
                  ),
                ),
              Positioned(
                left: -5,
                top: 58,
                child: _TaskGraphPort(
                  color: connectionTarget ? colors.green : colors.muted,
                ),
              ),
              Positioned(
                right: -5,
                top: 58,
                child: GestureDetector(
                  onTap: onStartConnection,
                  child: Tooltip(
                    message: connectingFromThis
                        ? 'Cancel connection'
                        : 'Connect from state',
                    child: _TaskGraphPort(
                      color: connectingFromThis ? colors.coral : colors.green,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Handles normal selection and Ctrl-click inspector opening.
  void _handleTap(String stateId, bool controlPressedOnTapDown) {
    if (controlPressedOnTapDown || isOpenInspectorModifierPressed()) {
      onOpenInspector(stateId);
      return;
    }
    onTap();
  }
}

class _StateMachineNodeDragTracker extends StatefulWidget {
  const _StateMachineNodeDragTracker({
    required this.stateId,
    required this.onPointerDown,
    required this.onPreviewMoveBy,
    required this.onMoveStateBy,
    required this.onCancelMove,
    required this.child,
  });

  final String stateId;
  final VoidCallback onPointerDown;
  final void Function(String stateId, Offset delta) onPreviewMoveBy;
  final void Function(String stateId, Offset delta) onMoveStateBy;
  final ValueChanged<String> onCancelMove;
  final Widget child;

  /// Creates pointer tracking for moving existing state-machine nodes.
  @override
  State<_StateMachineNodeDragTracker> createState() =>
      _StateMachineNodeDragTrackerState();
}

class _StateMachineNodeDragTrackerState
    extends State<_StateMachineNodeDragTracker> {
  Offset _delta = Offset.zero;
  bool _emitted = false;
  int? _activePointer;

  /// Builds a draggable wrapper around one state-machine node.
  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _start,
      onPointerMove: _preview,
      onPointerUp: _commit,
      onPointerCancel: _cancel,
      child: RepaintBoundary(child: widget.child),
    );
  }

  /// Starts tracking one pointer for responsive node movement.
  void _start(PointerDownEvent event) {
    if (_activePointer != null) {
      return;
    }
    _activePointer = event.pointer;
    _delta = Offset.zero;
    _emitted = false;
    widget.onPointerDown();
  }

  /// Updates the local transform immediately without persisting each pixel.
  void _preview(PointerMoveEvent event) {
    if (_activePointer != event.pointer || _emitted) {
      return;
    }
    _delta += event.delta;
    if (_delta.distance < 2) {
      return;
    }
    widget.onPreviewMoveBy(widget.stateId, _delta);
  }

  /// Commits the final position once the drag gesture finishes.
  void _commit(PointerUpEvent event) {
    if (_activePointer != event.pointer) {
      return;
    }
    if (_emitted) {
      return;
    }
    _emitted = true;
    final delta = _delta;
    if (delta.distance >= 2) {
      widget.onMoveStateBy(widget.stateId, delta);
    }
    _activePointer = null;
    _delta = Offset.zero;
  }

  /// Drops uncommitted preview movement when the drag is canceled.
  void _cancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) {
      return;
    }
    if (_delta.distance >= 2) {
      widget.onCancelMove(widget.stateId);
    }
    _activePointer = null;
    _delta = Offset.zero;
    _emitted = false;
  }
}

/// _StateMachineNodeToolbar provides selected-node graph controls.
class _StateMachineNodeToolbar extends StatelessWidget {
  /// Creates compact controls for one selected state.
  const _StateMachineNodeToolbar({
    required this.connectingFromThis,
    required this.onStartConnection,
    required this.onSetInitial,
    required this.onDeleteState,
    required this.onOpenInspector,
  });

  final bool connectingFromThis;
  final VoidCallback onStartConnection;
  final VoidCallback onSetInitial;
  final VoidCallback onDeleteState;
  final VoidCallback onOpenInspector;

  /// Builds compact controls for the selected process-state node.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
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
            _TaskGraphNodeToolbarButton(
              icon: Icons.tune_outlined,
              tooltip: 'Inspect state',
              onPressed: onOpenInspector,
            ),
            _TaskGraphNodeToolbarButton(
              icon: Icons.link,
              tooltip: connectingFromThis
                  ? 'Cancel connection'
                  : 'Connect from state',
              selected: connectingFromThis,
              onPressed: onStartConnection,
            ),
            _TaskGraphNodeToolbarButton(
              icon: Icons.flag_outlined,
              tooltip: 'Set initial state',
              onPressed: onSetInitial,
            ),
            _TaskGraphNodeToolbarButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete state',
              onPressed: onDeleteState,
            ),
          ],
        ),
      ),
    );
  }
}

/// _StateMachineInspector shows the selected state's editable context.
class _StateMachineInspector extends StatefulWidget {
  /// Creates an inspector for the selected state.
  const _StateMachineInspector({
    required this.state,
    required this.stateIds,
    required this.actionNames,
    required this.initialStateId,
    required this.connectionSourceId,
    required this.onSetInitial,
    required this.onStartConnection,
    required this.onDeleteState,
    required this.onRenameState,
    required this.onUpdateEntryAction,
    required this.onUpdateTransition,
    required this.onSubmitEdit,
  });

  final Map<String, dynamic>? state;
  final List<String> stateIds;
  final List<String> actionNames;
  final String initialStateId;
  final String connectionSourceId;
  final ValueChanged<String> onSetInitial;
  final ValueChanged<String> onStartConnection;
  final ValueChanged<String> onDeleteState;
  final void Function(String oldStateId, String nextStateId) onRenameState;
  final void Function(
    String stateId,
    int actionIndex,
    Map<String, dynamic> action,
  )
  onUpdateEntryAction;
  final void Function(
    String stateId,
    int transitionIndex,
    Map<String, dynamic> transition,
  )
  onUpdateTransition;
  final VoidCallback onSubmitEdit;

  /// Creates mutable form state for selected-state editing.
  @override
  State<_StateMachineInspector> createState() => _StateMachineInspectorState();
}

class _StateMachineInspectorState extends State<_StateMachineInspector> {
  late final TextEditingController _stateIdController;
  final List<TextEditingController> _actionIdControllers =
      <TextEditingController>[];
  final List<TextEditingController> _actionWithControllers =
      <TextEditingController>[];
  final List<TextEditingController> _transitionTriggerControllers =
      <TextEditingController>[];
  bool _loadingControllers = false;

  /// Initializes selected-state form controllers.
  @override
  void initState() {
    super.initState();
    _stateIdController = TextEditingController();
    _loadControllers();
  }

  /// Reloads form controllers when selected-state shape changes.
  @override
  void didUpdateWidget(covariant _StateMachineInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stateChanged =
        _stateId(widget.state ?? const <String, dynamic>{}) !=
        _stateId(oldWidget.state ?? const <String, dynamic>{});
    final actionsChanged =
        _stateEntryActions(widget.state ?? const <String, dynamic>{}).length !=
        _stateEntryActions(oldWidget.state ?? const <String, dynamic>{}).length;
    final transitionsChanged =
        _stateTransitions(widget.state ?? const <String, dynamic>{}).length !=
        _stateTransitions(oldWidget.state ?? const <String, dynamic>{}).length;
    if (stateChanged || actionsChanged || transitionsChanged) {
      _loadControllers();
    }
  }

  /// Disposes all text controllers owned by the inspector.
  @override
  void dispose() {
    _stateIdController.dispose();
    for (final controller in _rowControllers()) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Builds editable selected-state fields and actions.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final selected = widget.state;
    if (selected == null) {
      return const PanelSurface(
        key: ValueKey<String>('state-machine-inspector'),
        style: PanelSurfaceStyle.card,
        padding: EdgeInsets.all(12),
        child: PanelEmptyBlock(label: 'No state selected'),
      );
    }
    final stateId = _stateId(selected);
    final actions = _stateEntryActions(selected);
    final transitions = _stateTransitions(selected);
    return PanelSurface(
      key: const ValueKey<String>('state-machine-inspector'),
      style: PanelSurfaceStyle.card,
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: <Widget>[
          Row(
            children: <Widget>[
              _StateMachineNodeIcon(
                icon: _stateMachineNodeIcon(
                  actions.isEmpty
                      ? _terminalStatePaletteAction
                      : '${_map(actions.first)['uses'] ?? ''}',
                ),
                color: _stateMachinePaletteColor(
                  context,
                  actions.isEmpty
                      ? _terminalStatePaletteAction
                      : '${_map(actions.first)['uses'] ?? ''}',
                ),
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stateId,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AutomationTextField(
            key: const ValueKey<String>('state-machine-state-id-field'),
            controller: _stateIdController,
            label: 'State id',
            onSubmitted: (_) => widget.onSubmitEdit(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              if (stateId == widget.initialStateId)
                const PanelBadge(label: 'initial'),
              PanelBadge(label: '${actions.length} entry actions'),
              PanelBadge(label: '${transitions.length} transitions'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              PanelInlineIconButton(
                icon: Icons.link,
                tooltip: widget.connectionSourceId == stateId
                    ? 'Cancel connection'
                    : 'Connect from state',
                selected: widget.connectionSourceId == stateId,
                onPressed: () => widget.onStartConnection(stateId),
              ),
              const SizedBox(width: 8),
              PanelInlineIconButton(
                icon: Icons.flag_outlined,
                tooltip: 'Set initial state',
                onPressed: () => widget.onSetInitial(stateId),
              ),
              const SizedBox(width: 8),
              PanelInlineIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete state',
                onPressed: () => widget.onDeleteState(stateId),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const PanelSectionLabel('Entry Actions'),
          const SizedBox(height: 8),
          if (actions.isEmpty)
            const PanelEmptyBlock(label: 'No entry actions')
          else
            for (var index = 0; index < actions.length; index++)
              _StateMachineEntryActionEditor(
                action: _map(actions[index]),
                actionNames: _actionNamesFor(_map(actions[index])),
                idController: _actionIdControllers[index],
                withController: _actionWithControllers[index],
                onUsesChanged: (uses) => _emitAction(index, uses: uses),
                onSubmitEdit: widget.onSubmitEdit,
              ),
          const SizedBox(height: 16),
          const PanelSectionLabel('Transitions'),
          const SizedBox(height: 8),
          if (transitions.isEmpty)
            const PanelEmptyBlock(label: 'Terminal state')
          else
            for (var index = 0; index < transitions.length; index++)
              _StateMachineTransitionEditor(
                transition: _map(transitions[index]),
                stateIds: widget.stateIds,
                triggerController: _transitionTriggerControllers[index],
                onTargetChanged: (target) =>
                    _emitTransition(index, target: target),
                onSubmitEdit: widget.onSubmitEdit,
              ),
        ],
      ),
    );
  }

  List<TextEditingController> _rowControllers() {
    return <TextEditingController>[
      ..._actionIdControllers,
      ..._actionWithControllers,
      ..._transitionTriggerControllers,
    ];
  }

  void _loadControllers() {
    _loadingControllers = true;
    for (final controller in _rowControllers()) {
      controller.dispose();
    }
    _actionIdControllers.clear();
    _actionWithControllers.clear();
    _transitionTriggerControllers.clear();
    _stateIdController
      ..removeListener(_emitStateId)
      ..text = _stateId(widget.state ?? const <String, dynamic>{});
    _stateIdController.addListener(_emitStateId);
    final actions = _stateEntryActions(
      widget.state ?? const <String, dynamic>{},
    );
    for (var index = 0; index < actions.length; index++) {
      final action = _map(actions[index]);
      _actionIdControllers.add(
        TextEditingController(text: '${action['id'] ?? ''}')
          ..addListener(() => _emitAction(index)),
      );
      _actionWithControllers.add(
        TextEditingController(text: _jsonText(_map(action['with'])))
          ..addListener(() => _emitAction(index)),
      );
    }
    final transitions = _stateTransitions(
      widget.state ?? const <String, dynamic>{},
    );
    for (var index = 0; index < transitions.length; index++) {
      final transition = _map(transitions[index]);
      _transitionTriggerControllers.add(
        TextEditingController(text: _transitionTrigger(transition))
          ..addListener(() => _emitTransition(index)),
      );
    }
    _loadingControllers = false;
  }

  void _emitStateId() {
    if (_loadingControllers) {
      return;
    }
    widget.onRenameState(
      _stateId(widget.state ?? const <String, dynamic>{}),
      _stateIdController.text,
    );
  }

  void _emitAction(int index, {String? uses}) {
    if (_loadingControllers ||
        widget.state == null ||
        index >= _actionIdControllers.length ||
        index >= _actionWithControllers.length) {
      return;
    }
    final current = _map(_stateEntryActions(widget.state!)[index]);
    final parsedWith = _tryParseJsonObject(_actionWithControllers[index].text);
    if (parsedWith == null) {
      return;
    }
    widget.onUpdateEntryAction(
      _stateId(widget.state ?? const <String, dynamic>{}),
      index,
      <String, dynamic>{
        'id': _actionIdControllers[index].text.trim(),
        'uses': uses ?? '${current['uses'] ?? ''}',
        'with': parsedWith,
      },
    );
  }

  void _emitTransition(int index, {String? target}) {
    if (_loadingControllers ||
        widget.state == null ||
        index >= _transitionTriggerControllers.length) {
      return;
    }
    final current = _map(_stateTransitions(widget.state!)[index]);
    widget.onUpdateTransition(
      _stateId(widget.state ?? const <String, dynamic>{}),
      index,
      <String, dynamic>{
        'trigger': _transitionTriggerControllers[index].text.trim(),
        'to': target ?? _transitionTarget(current),
        if ('${current['guard'] ?? ''}'.trim().isNotEmpty)
          'guard': '${current['guard']}',
      },
    );
  }

  List<String> _actionNamesFor(Map<String, dynamic> action) {
    final uses = '${action['uses'] ?? ''}'.trim();
    return <String>{if (uses.isNotEmpty) uses, ...widget.actionNames}.toList();
  }
}

/// _StateMachineEntryActionEditor edits one state entry action.
class _StateMachineEntryActionEditor extends StatelessWidget {
  /// Creates an entry-action editor row.
  const _StateMachineEntryActionEditor({
    required this.action,
    required this.actionNames,
    required this.idController,
    required this.withController,
    required this.onUsesChanged,
    required this.onSubmitEdit,
  });

  final Map<String, dynamic> action;
  final List<String> actionNames;
  final TextEditingController idController;
  final TextEditingController withController;
  final ValueChanged<String> onUsesChanged;
  final VoidCallback onSubmitEdit;

  /// Builds editable fields for an entry action.
  @override
  Widget build(BuildContext context) {
    final uses = '${action['uses'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PanelSurface(
        style: PanelSurfaceStyle.card,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _AutomationTextField(
              controller: idController,
              label: 'Action id',
              onSubmitted: (_) => onSubmitEdit(),
            ),
            const SizedBox(height: 8),
            _AutomationDropdown(
              label: 'Action',
              value: uses,
              values: actionNames,
              onChanged: onUsesChanged,
            ),
            const SizedBox(height: 8),
            _AutomationTextField(
              controller: withController,
              label: 'Arguments JSON',
              maxLines: 4,
              monospace: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// _StateMachineTransitionEditor edits one state transition.
class _StateMachineTransitionEditor extends StatelessWidget {
  /// Creates a transition editor row.
  const _StateMachineTransitionEditor({
    required this.transition,
    required this.stateIds,
    required this.triggerController,
    required this.onTargetChanged,
    required this.onSubmitEdit,
  });

  final Map<String, dynamic> transition;
  final List<String> stateIds;
  final TextEditingController triggerController;
  final ValueChanged<String> onTargetChanged;
  final VoidCallback onSubmitEdit;

  /// Builds editable fields for a transition trigger and target.
  @override
  Widget build(BuildContext context) {
    final target = _transitionTarget(transition);
    final values = <String>{
      if (target.isNotEmpty) target,
      ...stateIds,
    }.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PanelSurface(
        style: PanelSurfaceStyle.card,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _AutomationTextField(
              controller: triggerController,
              label: 'Trigger',
              onSubmitted: (_) => onSubmitEdit(),
            ),
            const SizedBox(height: 8),
            _AutomationDropdown(
              label: 'Target',
              value: target,
              values: values,
              onChanged: onTargetChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// _StateMachineNodeIcon renders a colored icon tile.
class _StateMachineNodeIcon extends StatelessWidget {
  /// Creates an icon tile for state-machine palette and nodes.
  const _StateMachineNodeIcon({
    required this.icon,
    required this.color,
    required this.size,
  });

  final IconData icon;
  final Color color;
  final double size;

  /// Builds the colored icon tile used by state-machine nodes and palette.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}

/// _StateMachineMiniMap renders a compact process-state overview.
class _StateMachineMiniMap extends StatelessWidget {
  /// Creates a minimap for the current canvas layout.
  const _StateMachineMiniMap({required this.layout});

  final _StateMachineCanvasLayout layout;

  /// Builds a compact overview of the process-state canvas.
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
          painter: _StateMachineMiniMapPainter(
            layout: layout,
            colors: context.agentAwesomeColors,
          ),
        ),
      ),
    );
  }
}

/// _StateMachinePaletteItem stores one process-state palette entry.
class _StateMachinePaletteItem {
  /// Creates immutable palette metadata.
  const _StateMachinePaletteItem({
    required this.actionName,
    required this.label,
    required this.description,
    required this.icon,
  });

  final String actionName;
  final String label;
  final String description;
  final IconData icon;
}

/// _StateMachinePaletteDragData carries a dragged palette action.
class _StateMachinePaletteDragData {
  /// Creates drag metadata for one palette action.
  const _StateMachinePaletteDragData(this.actionName);

  final String actionName;
}

/// _StateMachineNodePlacement stores one laid-out state node.
class _StateMachineNodePlacement {
  /// Creates a state-node placement.
  const _StateMachineNodePlacement({
    required this.state,
    required this.rect,
    required this.childCount,
  });

  final Map<String, dynamic> state;
  final Rect rect;
  final int childCount;
}

/// _StateMachineEdgePlacement stores one rendered transition edge.
class _StateMachineEdgePlacement {
  /// Creates a transition-edge placement.
  const _StateMachineEdgePlacement({
    required this.fromStateId,
    required this.toStateId,
    required this.trigger,
    required this.from,
    required this.to,
    required this.backEdge,
  });

  final String fromStateId;
  final String toStateId;
  final String trigger;
  final Offset from;
  final Offset to;
  final bool backEdge;
}

/// _StateMachineExitBadgePlacement stores one aggregated off-path exit badge.
class _StateMachineExitBadgePlacement {
  /// Creates an aggregated clickable exit badge placement.
  const _StateMachineExitBadgePlacement({
    required this.id,
    required this.sourceStateId,
    required this.targetStateId,
    required this.visibleTargetStateId,
    required this.trigger,
    required this.label,
    required this.rect,
    required this.from,
    required this.to,
    required this.count,
    required this.sourceStateIds,
  });

  /// Stable badge id used for keys and hover identity.
  final String id;

  /// Visible state or phase that owns the badge.
  final String sourceStateId;

  /// Authored transition target id.
  final String targetStateId;

  /// Visible target id when the authored target is inside a collapsed phase.
  final String visibleTargetStateId;

  /// Trigger represented by this badge.
  final String trigger;

  /// Compact badge label.
  final String label;

  /// Badge geometry in canvas coordinates.
  final Rect rect;

  /// Connector start point.
  final Offset from;

  /// Connector endpoint at the badge.
  final Offset to;

  /// Number of authored transitions represented by this badge.
  final int count;

  /// Authored source ids represented by this badge.
  final Set<String> sourceStateIds;
}

/// _StateMachinePhasePlacement stores one rendered composite phase group.
class _StateMachinePhasePlacement {
  /// Creates a composite phase canvas placement.
  const _StateMachinePhasePlacement({
    required this.stateId,
    required this.rect,
  });

  final String stateId;
  final Rect rect;
}

/// _StateMachineCanvasLayout stores process-state canvas geometry.
class _StateMachineCanvasLayout {
  /// Creates an immutable state-machine canvas layout.
  const _StateMachineCanvasLayout({
    required this.size,
    required this.placements,
    required this.edges,
    required this.exitBadges,
    required this.phases,
  });

  final Size size;
  final List<_StateMachineNodePlacement> placements;
  final List<_StateMachineEdgePlacement> edges;
  final List<_StateMachineExitBadgePlacement> exitBadges;
  final List<_StateMachinePhasePlacement> phases;

  /// Returns state placements keyed by state id.
  Map<String, _StateMachineNodePlacement> get byId =>
      <String, _StateMachineNodePlacement>{
        for (final placement in placements)
          _stateId(placement.state): placement,
      };

  /// Creates deterministic process-state graph layout coordinates.
  static _StateMachineCanvasLayout fromStates(
    List<Map<String, dynamic>> states, {
    required String initialStateId,
    required Map<String, Offset> positions,
    Set<String> collapsedPhaseIds = const <String>{},
    _StateMachineEdgeViewMode edgeViewMode = _StateMachineEdgeViewMode.success,
    String selectedStateId = '',
  }) {
    final childIdsByParent = _stateMachineChildIdsByParent(states);
    final visibleStates = _stateMachineVisibleStates(states, collapsedPhaseIds);
    const padding = 84.0;
    const nodeWidth = _stateMachineNodeWidth;
    const nodeHeight = _stateMachineNodeHeight;
    final autoPositions = _stateMachineSugiyamaPositions(
      visibleStates,
      initialStateId,
    );
    final resolvedPositions = _stateMachineResolvedReadablePositions(
      visibleStates,
      savedPositions: positions,
      autoPositions: autoPositions,
    );
    final placements = <_StateMachineNodePlacement>[];
    for (var index = 0; index < visibleStates.length; index++) {
      final state = visibleStates[index];
      final stateId = _stateId(state);
      final fallback = Offset(
        padding + index * (_stateMachineLayoutNodeWidth + 72),
        padding,
      );
      final position =
          resolvedPositions[stateId] ?? autoPositions[stateId] ?? fallback;
      placements.add(
        _StateMachineNodePlacement(
          state: state,
          rect: Rect.fromLTWH(position.dx, position.dy, nodeWidth, nodeHeight),
          childCount: childIdsByParent[stateId]?.length ?? 0,
        ),
      );
    }
    var maxRight = padding * 2;
    var maxBottom = padding * 2;
    for (final placement in placements) {
      maxRight = math.max(maxRight, placement.rect.right + padding);
      maxBottom = math.max(maxBottom, placement.rect.bottom + padding);
    }
    final layout = _StateMachineCanvasLayout(
      size: Size(maxRight, maxBottom),
      placements: placements,
      edges: const <_StateMachineEdgePlacement>[],
      exitBadges: const <_StateMachineExitBadgePlacement>[],
      phases: const <_StateMachinePhasePlacement>[],
    );
    final byId = layout.byId;
    final phases = _stateMachinePhasePlacements(
      states: states,
      visibleIds: placements
          .map((placement) => _stateId(placement.state))
          .toSet(),
      childIdsByParent: childIdsByParent,
      byId: byId,
      collapsedPhaseIds: collapsedPhaseIds,
    );
    final phaseById = <String, _StateMachinePhasePlacement>{
      for (final phase in phases) phase.stateId: phase,
    };
    final edges = <_StateMachineEdgePlacement>[];
    final exitBadgeGroups = <String, _StateMachineExitBadgeGroup>{};
    final visibleIds = placements
        .map((placement) => _stateId(placement.state))
        .toSet();
    final parents = _stateMachineParentById(states);
    final edgeKeys = <String>{};
    for (final state in states) {
      final sourceId = _stateId(state);
      final visibleSourceId = _stateMachineVisibleAncestor(
        sourceId,
        visibleIds,
        parents,
      );
      if (visibleSourceId.isEmpty) {
        continue;
      }
      for (final transition in _stateTransitions(state).map(_map)) {
        final trigger = _transitionTrigger(transition);
        final targetId = _transitionTarget(transition);
        final visibleTargetId = _stateMachineVisibleAncestor(
          targetId,
          visibleIds,
          parents,
        );
        if (visibleTargetId.isEmpty || visibleSourceId == visibleTargetId) {
          continue;
        }
        final transitionView = _StateMachineTransitionView(
          sourceStateId: sourceId,
          visibleSourceStateId: visibleSourceId,
          targetStateId: targetId,
          visibleTargetStateId: visibleTargetId,
          trigger: trigger,
        );
        if (_stateMachineTransitionUsesExitBadge(
          transitionView,
          edgeViewMode,
          selectedStateId,
        )) {
          final badgeSourceId = _stateMachineExitBadgeSourceId(
            transitionView,
            visibleIds: visibleIds,
            parents: parents,
            childIdsByParent: childIdsByParent,
          );
          final key =
              '$badgeSourceId|$visibleTargetId|${transitionView.trigger}';
          exitBadgeGroups
              .putIfAbsent(
                key,
                () => _StateMachineExitBadgeGroup(
                  sourceStateId: badgeSourceId,
                  targetStateId: targetId,
                  visibleTargetStateId: visibleTargetId,
                  trigger: transitionView.trigger,
                ),
              )
              .sourceStateIds
              .add(sourceId);
          continue;
        }
        if (!_stateMachineTransitionShowsEdge(
          transitionView,
          edgeViewMode,
          selectedStateId,
        )) {
          continue;
        }
        final edgeKey =
            '$visibleSourceId|$visibleTargetId|${transitionView.trigger}';
        if (!edgeKeys.add(edgeKey)) {
          continue;
        }
        final source = byId[visibleSourceId];
        final target = byId[visibleTargetId];
        if (source == null || target == null) {
          continue;
        }
        edges.add(
          _StateMachineEdgePlacement(
            fromStateId: visibleSourceId,
            toStateId: visibleTargetId,
            trigger: transitionView.trigger,
            from: _stateMachineOutputPortCenter(source.rect),
            to: _stateMachineInputPortCenter(target.rect),
            backEdge: target.rect.left <= source.rect.left,
          ),
        );
      }
    }
    final exitBadges = _stateMachineExitBadgePlacements(
      groups: exitBadgeGroups.values.toList(),
      byId: byId,
      phaseById: phaseById,
    );
    for (final phase in phases) {
      maxRight = math.max(maxRight, phase.rect.right + padding);
      maxBottom = math.max(maxBottom, phase.rect.bottom + padding);
    }
    for (final badge in exitBadges) {
      maxRight = math.max(maxRight, badge.rect.right + padding);
      maxBottom = math.max(maxBottom, badge.rect.bottom + padding);
    }
    return _StateMachineCanvasLayout(
      size: Size(maxRight, maxBottom),
      placements: placements,
      edges: edges,
      exitBadges: exitBadges,
      phases: phases,
    );
  }
}

/// _StateMachineCanvasPainter paints process-state graph edges and grid.
class _StateMachineCanvasPainter extends CustomPainter {
  /// Creates a painter for a computed state-machine layout.
  const _StateMachineCanvasPainter({
    required this.layout,
    required this.colors,
    required this.selectedStateId,
  });

  final _StateMachineCanvasLayout layout;
  final AgentAwesomePalette colors;
  final String selectedStateId;

  /// Paints the state-machine grid, transitions, labels, and arrows.
  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    _paintPhaseGroups(canvas);
    _paintEdges(canvas);
    _paintExitBadgeConnectors(canvas);
  }

  /// Paints the dotted builder grid behind nodes and edges.
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

  /// Paints composite phase containers behind state nodes and edges.
  void _paintPhaseGroups(Canvas canvas) {
    for (final phase in layout.phases) {
      final rect = phase.rect;
      final fillPaint = Paint()
        ..color = colors.panel.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = colors.green.withValues(alpha: 0.46)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas
        ..drawRRect(rrect, fillPaint)
        ..drawRRect(rrect, borderPaint);
      _paintPhaseLabel(canvas, phase);
    }
  }

  /// Paints a compact phase label inside a composite container.
  void _paintPhaseLabel(Canvas canvas, _StateMachinePhasePlacement phase) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: phase.stateId,
        style: TextStyle(
          color: colors.ink,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(80, phase.rect.width - 24));
    final labelRect = Rect.fromLTWH(
      phase.rect.left + 12,
      phase.rect.top + 10,
      textPainter.width + 16,
      textPainter.height + 8,
    );
    final fillPaint = Paint()..color = colors.panel.withValues(alpha: 0.92);
    final borderPaint = Paint()
      ..color = colors.border
      ..style = PaintingStyle.stroke;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
        fillPaint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
        borderPaint,
      );
    textPainter.paint(canvas, Offset(labelRect.left + 8, labelRect.top + 4));
  }

  /// Paints all transition edge paths on the process-state canvas.
  void _paintEdges(Canvas canvas) {
    final edgePaint = Paint()
      ..color = colors.muted.withValues(alpha: 0.82)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final edge in layout.edges) {
      final path = _stateMachineEdgePath(edge.from, edge.to, edge.backEdge);
      canvas.drawPath(path, edgePaint);
      _paintArrow(canvas, path, edgePaint.color);
      if (edge.fromStateId == selectedStateId ||
          edge.toStateId == selectedStateId) {
        _paintEdgeLabel(canvas, path, edge.trigger);
      }
    }
  }

  /// Paints short connectors from a state or phase to aggregated exit badges.
  void _paintExitBadgeConnectors(Canvas canvas) {
    final badgePaint = Paint()
      ..color = colors.coral.withValues(alpha: 0.78)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    for (final badge in layout.exitBadges) {
      final path = Path()
        ..moveTo(badge.from.dx, badge.from.dy)
        ..cubicTo(
          badge.from.dx + 24,
          badge.from.dy,
          badge.to.dx - 18,
          badge.to.dy,
          badge.to.dx,
          badge.to.dy,
        );
      canvas.drawPath(path, badgePaint);
      _paintArrow(canvas, path, badgePaint.color);
    }
  }

  /// Paints a transition arrowhead at the end of an edge path.
  void _paintArrow(Canvas canvas, Path path, Color color) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) {
      return;
    }
    final metric = metrics.first;
    final tangent = metric.getTangentForOffset(metric.length);
    if (tangent == null) {
      return;
    }
    final angle = tangent.angle;
    final tip = tangent.position;
    const length = 9.0;
    const spread = math.pi / 7;
    final left = Offset(
      tip.dx - length * math.cos(angle - spread),
      tip.dy - length * math.sin(angle - spread),
    );
    final right = Offset(
      tip.dx - length * math.cos(angle + spread),
      tip.dy - length * math.sin(angle + spread),
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas
      ..drawLine(tip, left, paint)
      ..drawLine(tip, right, paint);
  }

  /// Paints the transition trigger label near the middle of an edge.
  void _paintEdgeLabel(Canvas canvas, Path path, String label) {
    if (label.isEmpty) {
      return;
    }
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) {
      return;
    }
    final metric = metrics.first;
    final tangent = metric.getTangentForOffset(metric.length / 2);
    if (tangent == null) {
      return;
    }
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: colors.ink,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 120);
    final rect = Rect.fromCenter(
      center: tangent.position,
      width: textPainter.width + 14,
      height: textPainter.height + 8,
    );
    final fillPaint = Paint()..color = colors.panel.withValues(alpha: 0.94);
    final borderPaint = Paint()
      ..color = colors.border
      ..style = PaintingStyle.stroke;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        fillPaint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        borderPaint,
      );
    textPainter.paint(canvas, Offset(rect.left + 7, rect.top + 4));
  }

  /// Repaints when graph topology or theme colors change.
  @override
  bool shouldRepaint(covariant _StateMachineCanvasPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.colors != colors ||
        oldDelegate.selectedStateId != selectedStateId;
  }
}

/// _StateMachineMiniMapPainter paints the compact graph overview.
class _StateMachineMiniMapPainter extends CustomPainter {
  /// Creates a minimap painter for a computed layout.
  const _StateMachineMiniMapPainter({
    required this.layout,
    required this.colors,
  });

  final _StateMachineCanvasLayout layout;
  final AgentAwesomePalette colors;

  /// Paints a compact overview of process-state placements.
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
  bool shouldRepaint(covariant _StateMachineMiniMapPainter oldDelegate) {
    return oldDelegate.layout != layout || oldDelegate.colors != colors;
  }
}

const String _inputStatePaletteAction = '__input_state__';
const String _terminalStatePaletteAction = '__terminal_state__';
const double _stateMachineNodeWidth = 246;
const double _stateMachineNodeHeight = 178;
const double _stateMachineNodeCardHeight = 138;
const double _stateMachineExitBadgeWidth = 148;
const double _stateMachineExitBadgeHeight = 28;
const double _stateMachineExitBadgeXGap = 14;
const double _stateMachineExitBadgeTopOffset = 86;
const double _stateMachineExitBadgeStackGap = 8;
const double _stateMachineLayoutNodeWidth =
    _stateMachineNodeWidth + _stateMachineExitBadgeWidth + 84;
const double _stateMachineLayoutNodeHeight = _stateMachineNodeHeight + 48;
const double _stateMachineLaneGap = _stateMachineNodeHeight + 54;
const double _stateMachineMinimumNodeGap = 96;
const double _stateMachineMinimumBadgeGap = 56;
const double _stateMachineNodeClearance = 18;
const double _stateMachineBadgeClearance = 8;

/// _StateMachineEdgeViewMode selects which transition family the canvas emphasizes.
enum _StateMachineEdgeViewMode {
  /// Show success-like forward flow and aggregate failure exits.
  success('success', 'Success', 'Show success flow with compact exit badges'),

  /// Show failure-like exits as compact local badges.
  failures('failures', 'Failures', 'Show failure and recovery exits'),

  /// Show manual and custom signal transitions.
  decisions('decisions', 'Decisions', 'Show manual and custom signal exits'),

  /// Show every transition as a literal edge.
  all('all', 'All', 'Show the full transition graph'),

  /// Show only transitions touching the selected state.
  selected('selected', 'Selected', 'Show transitions touching selection');

  /// Creates one edge view mode.
  const _StateMachineEdgeViewMode(this.id, this.label, this.tooltip);

  /// Stable mode id for widget keys.
  final String id;

  /// Compact visible mode label.
  final String label;

  /// Tooltip text.
  final String tooltip;
}

/// _StateMachineTransitionKind classifies trigger labels for display only.
enum _StateMachineTransitionKind {
  /// Success-like transitions.
  success,

  /// Failure, rejection, or repair-style transitions.
  failure,

  /// Manual or custom signal transitions.
  decision,
}

/// _StateMachineLayoutLane groups states into stable workflow swimlanes.
enum _StateMachineLayoutLane {
  /// Main forward workflow path.
  primary,

  /// Recovery, repair, and retry states.
  repair,

  /// Human, operator, blocked, or approval states.
  operator,

  /// Done, abandoned, cancelled, or otherwise terminal states.
  terminal,
}

/// Reports whether a key event belongs to a Control modifier key.
bool _isControlKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight;
}

/// Returns a process-state id.
String _stateId(Map<String, dynamic> state) {
  return '${state['id'] ?? ''}'.trim();
}

/// Returns the parent id for one flattened process-state definition.
String _stateParentId(Map<String, dynamic> state) {
  return '${state['parent'] ?? ''}'.trim();
}

/// Returns flattened process states from a nested state-machine body.
List<Map<String, dynamic>> _stateMachineFlattenedStatesFromBody(
  Map<String, dynamic> body,
) {
  final states = <Map<String, dynamic>>[];
  _appendFlattenedStateMachineStates(states, _list(body['states']), '');
  return states;
}

/// Appends nested process states with implicit parent ids made explicit.
void _appendFlattenedStateMachineStates(
  List<Map<String, dynamic>> output,
  List<dynamic> states,
  String parentId,
) {
  for (final item in states) {
    final state = Map<String, dynamic>.from(_map(item));
    final children = _list(state.remove('states'));
    if (parentId.isNotEmpty && '${state['parent'] ?? ''}'.trim().isEmpty) {
      state['parent'] = parentId;
    }
    output.add(state);
    _appendFlattenedStateMachineStates(output, children, _stateId(state));
  }
}

/// Rebuilds nested process states from the editor's flattened state list.
List<Map<String, dynamic>> _stateMachineNestedStates(
  List<Map<String, dynamic>> states,
) {
  final childrenByParent = <String, List<Map<String, dynamic>>>{};
  for (final state in states) {
    final parent = _stateParentId(state);
    childrenByParent
        .putIfAbsent(parent, () => <Map<String, dynamic>>[])
        .add(Map<String, dynamic>.from(state));
  }
  List<Map<String, dynamic>> build(String parentId) {
    return <Map<String, dynamic>>[
      for (final state
          in childrenByParent[parentId] ?? const <Map<String, dynamic>>[])
        _stateMachineNestedState(state, build(_stateId(state))),
    ];
  }

  return build('');
}

/// Builds one nested state and strips editor-only parent metadata from children.
Map<String, dynamic> _stateMachineNestedState(
  Map<String, dynamic> state,
  List<Map<String, dynamic>> children,
) {
  final next = Map<String, dynamic>.from(state)..remove('parent');
  if (children.isEmpty) {
    next.remove('states');
  } else {
    next['states'] = children;
  }
  return next;
}

/// Returns child ids grouped by parent state id.
Map<String, List<String>> _stateMachineChildIdsByParent(
  List<Map<String, dynamic>> states,
) {
  final children = <String, List<String>>{};
  for (final state in states) {
    final parent = _stateParentId(state);
    if (parent.isEmpty) {
      continue;
    }
    children.putIfAbsent(parent, () => <String>[]).add(_stateId(state));
  }
  return children;
}

/// Returns parent ids keyed by state id.
Map<String, String> _stateMachineParentById(List<Map<String, dynamic>> states) {
  return <String, String>{
    for (final state in states)
      if (_stateId(state).isNotEmpty) _stateId(state): _stateParentId(state),
  };
}

/// Returns the direct parent id for one state id.
String _stateMachineParentOf(
  List<Map<String, dynamic>> states,
  String stateId,
) {
  for (final state in states) {
    if (_stateId(state) == stateId) {
      return _stateParentId(state);
    }
  }
  return '';
}

/// Reports whether one state is the initial child of its containing phase.
bool _stateMachineIsPhaseInitial(
  List<Map<String, dynamic>> states,
  String stateId,
) {
  final parentId = _stateMachineParentOf(states, stateId);
  if (parentId.isEmpty) {
    return false;
  }
  for (final state in states) {
    if (_stateId(state) == parentId) {
      return '${state['initial'] ?? ''}'.trim() == stateId;
    }
  }
  return false;
}

/// Returns the first direct child id that remains after optional exclusions.
String _stateMachineFirstChildId(
  List<Map<String, dynamic>> states,
  String parentId, {
  Set<String> excludedIds = const <String>{},
}) {
  for (final state in states) {
    final stateId = _stateId(state);
    if (_stateParentId(state) == parentId && !excludedIds.contains(stateId)) {
      return stateId;
    }
  }
  return '';
}

/// Returns the first root state id that remains in author order.
String _stateMachineFirstRootId(List<Map<String, dynamic>> states) {
  for (final state in states) {
    final stateId = _stateId(state);
    if (_stateParentId(state).isEmpty && stateId.isNotEmpty) {
      return stateId;
    }
  }
  return '';
}

/// _StateMachineTransitionView stores resolved visibility data for one transition.
class _StateMachineTransitionView {
  /// Creates one resolved transition view model.
  const _StateMachineTransitionView({
    required this.sourceStateId,
    required this.visibleSourceStateId,
    required this.targetStateId,
    required this.visibleTargetStateId,
    required this.trigger,
  });

  /// Authored source state id.
  final String sourceStateId;

  /// Source id visible in the current collapsed canvas.
  final String visibleSourceStateId;

  /// Authored target state id.
  final String targetStateId;

  /// Target id visible in the current collapsed canvas.
  final String visibleTargetStateId;

  /// Transition trigger.
  final String trigger;
}

/// _StateMachineLayoutEdge stores the graph projection used for auto layout.
class _StateMachineLayoutEdge {
  /// Creates one projected directed edge for Sugiyama layout stages.
  const _StateMachineLayoutEdge({
    required this.sourceStateId,
    required this.targetStateId,
    required this.kind,
    required this.order,
    this.structural = false,
  });

  /// Visible source state id.
  final String sourceStateId;

  /// Visible target state id.
  final String targetStateId;

  /// Display transition kind used for semantic ranking.
  final _StateMachineTransitionKind kind;

  /// Stable source order from authored YAML.
  final int order;

  /// Whether this edge represents hierarchy/initial structure.
  final bool structural;

  /// Stable edge identity.
  String get key => '$sourceStateId->$targetStateId';
}

/// _StateMachineExitBadgeGroup aggregates equivalent hidden exits.
class _StateMachineExitBadgeGroup {
  /// Creates one mutable badge grouping bucket.
  _StateMachineExitBadgeGroup({
    required this.sourceStateId,
    required this.targetStateId,
    required this.visibleTargetStateId,
    required this.trigger,
  });

  /// Visible source or phase that owns the badge.
  final String sourceStateId;

  /// Authored transition target.
  final String targetStateId;

  /// Visible transition target.
  final String visibleTargetStateId;

  /// Shared trigger for this group.
  final String trigger;

  /// Authored source states represented by this group.
  final Set<String> sourceStateIds = <String>{};
}

/// Returns expanded composite phase group placements.
List<_StateMachinePhasePlacement> _stateMachinePhasePlacements({
  required List<Map<String, dynamic>> states,
  required Set<String> visibleIds,
  required Map<String, List<String>> childIdsByParent,
  required Map<String, _StateMachineNodePlacement> byId,
  required Set<String> collapsedPhaseIds,
}) {
  final phases = <_StateMachinePhasePlacement>[];
  for (final state in states) {
    final stateId = _stateId(state);
    if (!visibleIds.contains(stateId) ||
        collapsedPhaseIds.contains(stateId) ||
        (childIdsByParent[stateId] ?? const <String>[]).isEmpty) {
      continue;
    }
    final descendantIds = _stateMachineDescendantIds(
      states,
      stateId,
    ).where(visibleIds.contains).toList();
    if (descendantIds.isEmpty) {
      continue;
    }
    final rects = <Rect>[
      if (byId[stateId] != null) byId[stateId]!.rect,
      for (final id in descendantIds)
        if (byId[id] != null) byId[id]!.rect,
    ];
    if (rects.length < 2) {
      continue;
    }
    var bounds = rects.first;
    for (final rect in rects.skip(1)) {
      bounds = bounds.expandToInclude(rect);
    }
    phases.add(
      _StateMachinePhasePlacement(stateId: stateId, rect: bounds.inflate(28)),
    );
  }
  phases.sort(
    (a, b) => b.rect.size.longestSide.compareTo(a.rect.size.longestSide),
  );
  return phases;
}

/// Returns clickable badge placements for aggregated off-path exits.
List<_StateMachineExitBadgePlacement> _stateMachineExitBadgePlacements({
  required List<_StateMachineExitBadgeGroup> groups,
  required Map<String, _StateMachineNodePlacement> byId,
  required Map<String, _StateMachinePhasePlacement> phaseById,
}) {
  final sortedGroups =
      groups.where((group) => byId[group.sourceStateId] != null).toList()
        ..sort((a, b) {
          final aRect =
              phaseById[a.sourceStateId]?.rect ?? byId[a.sourceStateId]!.rect;
          final bRect =
              phaseById[b.sourceStateId]?.rect ?? byId[b.sourceStateId]!.rect;
          final yCompare = aRect.top.compareTo(bRect.top);
          if (yCompare != 0) {
            return yCompare;
          }
          final xCompare = aRect.left.compareTo(bRect.left);
          if (xCompare != 0) {
            return xCompare;
          }
          return a.trigger.compareTo(b.trigger);
        });
  final indexBySource = <String, int>{};
  final placements = <_StateMachineExitBadgePlacement>[];
  for (final group in sortedGroups) {
    final sourceRect =
        phaseById[group.sourceStateId]?.rect ?? byId[group.sourceStateId]!.rect;
    final index = indexBySource[group.sourceStateId] ?? 0;
    indexBySource[group.sourceStateId] = index + 1;
    final rect = _stateMachineExitBadgeRect(sourceRect, index);
    final count = group.sourceStateIds.length;
    final label = count > 1
        ? '${group.trigger} x$count -> ${group.visibleTargetStateId}'
        : '${group.trigger} -> ${group.visibleTargetStateId}';
    placements.add(
      _StateMachineExitBadgePlacement(
        id: '${_safeCanvasKey(group.sourceStateId)}-${_safeCanvasKey(group.trigger)}-${_safeCanvasKey(group.visibleTargetStateId)}',
        sourceStateId: group.sourceStateId,
        targetStateId: group.targetStateId,
        visibleTargetStateId: group.visibleTargetStateId,
        trigger: group.trigger,
        label: label,
        rect: rect,
        from: Offset(sourceRect.right, rect.center.dy),
        to: Offset(rect.left, rect.center.dy),
        count: count,
        sourceStateIds: Set<String>.unmodifiable(group.sourceStateIds),
      ),
    );
  }
  return placements;
}

/// Returns a widget-key-safe fragment for canvas overlay ids.
String _safeCanvasKey(String value) {
  final safe = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  return safe.isEmpty ? 'empty' : safe;
}

/// Returns every descendant id for one state.
Set<String> _stateMachineDescendantIds(
  List<Map<String, dynamic>> states,
  String stateId,
) {
  final children = _stateMachineChildIdsByParent(states);
  final descendants = <String>{};
  void visit(String id) {
    for (final child in children[id] ?? const <String>[]) {
      if (descendants.add(child)) {
        visit(child);
      }
    }
  }

  visit(stateId);
  return descendants;
}

/// Returns states visible after collapsed phases hide their descendants.
List<Map<String, dynamic>> _stateMachineVisibleStates(
  List<Map<String, dynamic>> states,
  Set<String> collapsedPhaseIds,
) {
  if (collapsedPhaseIds.isEmpty) {
    return states;
  }
  final parents = _stateMachineParentById(states);
  return <Map<String, dynamic>>[
    for (final state in states)
      if (!_stateMachineHasCollapsedAncestor(
        _stateId(state),
        parents,
        collapsedPhaseIds,
      ))
        state,
  ];
}

/// Reports whether any ancestor of stateId is collapsed.
bool _stateMachineHasCollapsedAncestor(
  String stateId,
  Map<String, String> parents,
  Set<String> collapsedPhaseIds,
) {
  var parent = parents[stateId] ?? '';
  while (parent.isNotEmpty) {
    if (collapsedPhaseIds.contains(parent)) {
      return true;
    }
    parent = parents[parent] ?? '';
  }
  return false;
}

/// Returns the nearest visible ancestor for a state id.
String _stateMachineVisibleAncestor(
  String stateId,
  Set<String> visibleIds,
  Map<String, String> parents,
) {
  var current = stateId;
  while (current.isNotEmpty) {
    if (visibleIds.contains(current)) {
      return current;
    }
    current = parents[current] ?? '';
  }
  return '';
}

/// Returns entry actions for one process-state definition.
List<dynamic> _stateEntryActions(Map<String, dynamic> state) {
  return _list(state['on_entry']);
}

/// Returns transition definitions for one process-state definition.
List<dynamic> _stateTransitions(Map<String, dynamic> state) {
  return _list(state['transitions']);
}

/// Returns a transition trigger label.
String _transitionTrigger(Map<String, dynamic> transition) {
  return '${transition['trigger'] ?? 'signal'}'.trim();
}

/// Returns a transition target state id.
String _transitionTarget(Map<String, dynamic> transition) {
  return '${transition['to'] ?? ''}'.trim();
}

/// Returns whether one transition should be drawn as a literal edge.
bool _stateMachineTransitionShowsEdge(
  _StateMachineTransitionView transition,
  _StateMachineEdgeViewMode mode,
  String selectedStateId,
) {
  return switch (mode) {
    _StateMachineEdgeViewMode.success =>
      _stateMachineTransitionKind(transition.trigger) ==
          _StateMachineTransitionKind.success,
    _StateMachineEdgeViewMode.failures => false,
    _StateMachineEdgeViewMode.decisions => _stateMachineIsDecisionTrigger(
      transition.trigger,
    ),
    _StateMachineEdgeViewMode.all => true,
    _StateMachineEdgeViewMode.selected =>
      selectedStateId.isNotEmpty &&
          (transition.sourceStateId == selectedStateId ||
              transition.targetStateId == selectedStateId ||
              transition.visibleSourceStateId == selectedStateId ||
              transition.visibleTargetStateId == selectedStateId),
  };
}

/// Returns whether one transition should become a compact local exit badge.
bool _stateMachineTransitionUsesExitBadge(
  _StateMachineTransitionView transition,
  _StateMachineEdgeViewMode mode,
  String selectedStateId,
) {
  final kind = _stateMachineTransitionKind(transition.trigger);
  return switch (mode) {
    _StateMachineEdgeViewMode.success =>
      kind == _StateMachineTransitionKind.failure,
    _StateMachineEdgeViewMode.failures =>
      kind == _StateMachineTransitionKind.failure,
    _StateMachineEdgeViewMode.decisions => false,
    _StateMachineEdgeViewMode.all => false,
    _StateMachineEdgeViewMode.selected =>
      selectedStateId.isNotEmpty &&
          kind == _StateMachineTransitionKind.failure &&
          (transition.sourceStateId == selectedStateId ||
              transition.visibleSourceStateId == selectedStateId),
  };
}

/// Classifies trigger labels for display filtering only.
_StateMachineTransitionKind _stateMachineTransitionKind(String trigger) {
  final normalized = trigger.trim().toLowerCase();
  if (_stateMachineSuccessTriggers.contains(normalized)) {
    return _StateMachineTransitionKind.success;
  }
  if (_stateMachineFailureTriggers.contains(normalized)) {
    return _StateMachineTransitionKind.failure;
  }
  return _StateMachineTransitionKind.decision;
}

const Set<String> _stateMachineSuccessTriggers = <String>{
  'succeeded',
  'success',
  'approved',
  'approve',
  'completed',
  'complete',
  'passed',
  'pass',
};

const Set<String> _stateMachineFailureTriggers = <String>{
  'failed',
  'failure',
  'rejected',
  'reject',
  'blocked',
  'abandoned',
  'canceled',
  'cancelled',
  'timeout',
  'errored',
  'error',
};

/// Reports whether a trigger is a manual or custom signal in display terms.
bool _stateMachineIsDecisionTrigger(String trigger) {
  return trigger.trim().isNotEmpty &&
      _stateMachineTransitionKind(trigger) ==
          _StateMachineTransitionKind.decision;
}

/// Returns the visible source that should own an aggregated exit badge.
String _stateMachineExitBadgeSourceId(
  _StateMachineTransitionView transition, {
  required Set<String> visibleIds,
  required Map<String, String> parents,
  required Map<String, List<String>> childIdsByParent,
}) {
  var current = transition.sourceStateId;
  while (current.isNotEmpty) {
    final parent = parents[current] ?? '';
    if (parent.isEmpty || !visibleIds.contains(parent)) {
      break;
    }
    if ((childIdsByParent[parent] ?? const <String>[]).isNotEmpty &&
        !_stateMachineIsDescendantOf(
          transition.targetStateId,
          parent,
          parents,
        )) {
      return parent;
    }
    current = parent;
  }
  return transition.visibleSourceStateId;
}

/// Reports whether one state is nested below a possible ancestor.
bool _stateMachineIsDescendantOf(
  String stateId,
  String possibleAncestorId,
  Map<String, String> parents,
) {
  var parent = parents[stateId] ?? '';
  while (parent.isNotEmpty) {
    if (parent == possibleAncestorId) {
      return true;
    }
    parent = parents[parent] ?? '';
  }
  return false;
}

/// Returns saved positions that can be honored without damaging readability.
Map<String, Offset> _stateMachineResolvedReadablePositions(
  List<Map<String, dynamic>> states, {
  required Map<String, Offset> savedPositions,
  required Map<String, Offset> autoPositions,
}) {
  if (savedPositions.isEmpty) {
    return const <String, Offset>{};
  }
  final ids = states.map(_stateId).where((id) => id.isNotEmpty).toSet();
  final completeSavedLayout = ids.every((id) => savedPositions[id] != null);
  if (completeSavedLayout) {
    return _stateMachinePositionsAreReadable(
          states,
          positions: savedPositions,
          autoPositions: autoPositions,
        )
        ? savedPositions
        : const <String, Offset>{};
  }
  final resolved = <String, Offset>{};
  for (final entry in savedPositions.entries) {
    if (!ids.contains(entry.key)) {
      continue;
    }
    final candidate = <String, Offset>{
      ...autoPositions,
      ...resolved,
      entry.key: entry.value,
    };
    if (_stateMachinePositionsAreReadable(
      states,
      positions: candidate,
      autoPositions: autoPositions,
    )) {
      resolved[entry.key] = entry.value;
    }
  }
  return resolved;
}

/// Reports whether positions leave enough room for nodes and exit badges.
bool _stateMachinePositionsAreReadable(
  List<Map<String, dynamic>> states, {
  required Map<String, Offset> positions,
  required Map<String, Offset> autoPositions,
}) {
  if (positions.isEmpty) {
    return false;
  }
  final ids = states.map(_stateId).where((id) => id.isNotEmpty).toList();
  if (ids.any((id) => positions[id] == null)) {
    return false;
  }
  for (var index = 0; index < ids.length; index++) {
    final leftId = ids[index];
    final leftRect = _stateMachineReadableNodeRect(positions[leftId]!);
    for (final rightId in ids.skip(index + 1)) {
      final rightRect = _stateMachineReadableNodeRect(positions[rightId]!);
      if (leftRect.overlaps(rightRect)) {
        return false;
      }
      if (_stateMachineHorizontalBandIntersects(leftRect, rightRect)) {
        final gap = (leftRect.left < rightRect.left)
            ? rightRect.left - leftRect.right
            : leftRect.left - rightRect.right;
        if (gap < _stateMachineMinimumNodeGap) {
          return false;
        }
      }
    }
  }
  final badgeIndexBySource = <String, int>{};
  for (final state in states) {
    final sourceId = _stateId(state);
    final sourcePosition = positions[sourceId];
    if (sourcePosition == null) {
      continue;
    }
    final sourceRect = _stateMachineReadableNodeRect(sourcePosition);
    for (final transition in _stateTransitions(state).map(_map)) {
      if (_stateMachineTransitionKind(_transitionTrigger(transition)) !=
          _StateMachineTransitionKind.failure) {
        continue;
      }
      final badgeIndex = badgeIndexBySource[sourceId] ?? 0;
      badgeIndexBySource[sourceId] = badgeIndex + 1;
      final badgeRect = _stateMachineReadableExitBadgeRect(
        sourceRect,
        badgeIndex,
      );
      for (final targetId in ids) {
        if (targetId == sourceId) {
          continue;
        }
        final targetPosition = positions[targetId];
        if (targetPosition == null) {
          continue;
        }
        final targetRect = _stateMachineReadableNodeRect(targetPosition);
        if (badgeRect.overlaps(targetRect)) {
          return false;
        }
        if (_stateMachineHorizontalBandIntersects(badgeRect, targetRect) &&
            targetRect.left > sourceRect.right &&
            targetRect.left - badgeRect.right < _stateMachineMinimumBadgeGap) {
          return false;
        }
      }
    }
  }
  return _stateMachineSavedPositionsRoughlyMatchLayoutDirection(
    states,
    positions: positions,
    autoPositions: autoPositions,
  );
}

/// Returns whether saved positions preserve the Sugiyama left-to-right flow.
bool _stateMachineSavedPositionsRoughlyMatchLayoutDirection(
  List<Map<String, dynamic>> states, {
  required Map<String, Offset> positions,
  required Map<String, Offset> autoPositions,
}) {
  if (autoPositions.isEmpty) {
    return true;
  }
  for (final state in states) {
    final sourceId = _stateId(state);
    final sourceSaved = positions[sourceId];
    final sourceAuto = autoPositions[sourceId];
    if (sourceSaved == null || sourceAuto == null) {
      continue;
    }
    for (final transition in _stateTransitions(state).map(_map)) {
      if (_stateMachineTransitionKind(_transitionTrigger(transition)) !=
          _StateMachineTransitionKind.success) {
        continue;
      }
      final targetId = _transitionTarget(transition);
      final targetSaved = positions[targetId];
      final targetAuto = autoPositions[targetId];
      if (targetSaved == null || targetAuto == null) {
        continue;
      }
      final autoForward = targetAuto.dx > sourceAuto.dx;
      final savedForward =
          targetSaved.dx - sourceSaved.dx > _stateMachineMinimumNodeGap;
      if (autoForward && !savedForward) {
        return false;
      }
    }
  }
  return true;
}

/// Returns a node rectangle inflated to include nearby toolbar and breathing room.
Rect _stateMachineReadableNodeRect(Offset position) {
  return Rect.fromLTWH(
    position.dx,
    position.dy,
    _stateMachineNodeWidth,
    _stateMachineNodeHeight,
  ).inflate(_stateMachineNodeClearance);
}

/// Returns the first exit-badge rectangle adjacent to a source node.
Rect _stateMachineReadableExitBadgeRect(Rect sourceRect, int index) {
  return _stateMachineExitBadgeRect(
    sourceRect,
    index,
  ).inflate(_stateMachineBadgeClearance);
}

/// Returns the visual exit-badge rectangle beside a state or phase.
Rect _stateMachineExitBadgeRect(Rect sourceRect, int index) {
  return Rect.fromLTWH(
    sourceRect.right + _stateMachineExitBadgeXGap,
    sourceRect.top +
        _stateMachineExitBadgeTopOffset +
        index * (_stateMachineExitBadgeHeight + _stateMachineExitBadgeStackGap),
    _stateMachineExitBadgeWidth,
    _stateMachineExitBadgeHeight,
  );
}

/// Reports whether two rectangles occupy the same horizontal flow band.
bool _stateMachineHorizontalBandIntersects(Rect a, Rect b) {
  return a.top < b.bottom && b.top < a.bottom;
}

/// Computes automatic positions with a domain-aware Sugiyama layout pipeline.
Map<String, Offset> _stateMachineSugiyamaPositions(
  List<Map<String, dynamic>> states,
  String initialStateId,
) {
  if (states.isEmpty) {
    return const <String, Offset>{};
  }
  final stateById = <String, Map<String, dynamic>>{
    for (final state in states)
      if (_stateId(state).isNotEmpty) _stateId(state): state,
  };
  if (stateById.isEmpty) {
    return const <String, Offset>{};
  }
  final ids = stateById.keys.toList();
  final edges = _stateMachineLayoutEdges(states, stateById.keys.toSet());
  final lanes = _stateMachineLayoutLanesForStates(stateById, edges);
  final initialId = stateById.containsKey(initialStateId)
      ? initialStateId
      : ids.first;
  final backEdgeKeys = _stateMachineLayoutBackEdgeKeys(
    initialId,
    ids,
    edges,
    lanes,
  );
  final ranks = _stateMachineLayoutRanks(
    initialId,
    ids,
    edges,
    lanes,
    backEdgeKeys,
  );
  final layerOrders = _stateMachineLayerOrders(ids, edges, ranks, lanes);
  return <String, Offset>{
    for (final id in ids)
      id: _stateMachineLayeredCoordinate(id, ranks, lanes, layerOrders),
  };
}

/// Projects visible states into directed edges for Sugiyama layout stages.
List<_StateMachineLayoutEdge> _stateMachineLayoutEdges(
  List<Map<String, dynamic>> states,
  Set<String> visibleIds,
) {
  final edges = <_StateMachineLayoutEdge>[];
  final seen = <String>{};
  var order = 0;
  void addEdge(
    String sourceId,
    String targetId,
    _StateMachineTransitionKind kind, {
    bool structural = false,
  }) {
    if (!visibleIds.contains(sourceId) ||
        !visibleIds.contains(targetId) ||
        sourceId == targetId) {
      return;
    }
    final key = '$sourceId->$targetId';
    if (!seen.add(key)) {
      return;
    }
    edges.add(
      _StateMachineLayoutEdge(
        sourceStateId: sourceId,
        targetStateId: targetId,
        kind: kind,
        order: order++,
        structural: structural,
      ),
    );
  }

  for (final state in states) {
    final sourceId = _stateId(state);
    final initialChild = '${state['initial'] ?? ''}'.trim();
    if (initialChild.isNotEmpty) {
      addEdge(
        sourceId,
        initialChild,
        _StateMachineTransitionKind.success,
        structural: true,
      );
    }
    for (final transition in _stateTransitions(state).map(_map)) {
      addEdge(
        sourceId,
        _transitionTarget(transition),
        _stateMachineTransitionKind(_transitionTrigger(transition)),
      );
    }
  }
  return edges;
}

/// Finds edges that should be treated as cycle-breaking back edges.
Set<String> _stateMachineLayoutBackEdgeKeys(
  String initialId,
  List<String> ids,
  List<_StateMachineLayoutEdge> edges,
  Map<String, _StateMachineLayoutLane> lanes,
) {
  final bySource = _stateMachineSortedOutgoingEdges(edges);
  final visited = <String>{};
  final visiting = <String>{};
  final backEdges = <String>{};

  void visit(String id) {
    if (visiting.contains(id)) {
      return;
    }
    visiting.add(id);
    for (final edge in bySource[id] ?? const <_StateMachineLayoutEdge>[]) {
      final targetId = edge.targetStateId;
      if (visiting.contains(targetId)) {
        backEdges.add(edge.key);
        continue;
      }
      if (!visited.contains(targetId)) {
        visit(targetId);
        continue;
      }
      if (_stateMachineLayoutReturnsToPrimaryLane(edge, lanes)) {
        backEdges.add(edge.key);
      }
    }
    visiting.remove(id);
    visited.add(id);
  }

  visit(initialId);
  for (final id in ids) {
    if (!visited.contains(id)) {
      visit(id);
    }
  }
  return backEdges;
}

/// Returns outgoing layout edges in stable semantic traversal order.
Map<String, List<_StateMachineLayoutEdge>> _stateMachineSortedOutgoingEdges(
  List<_StateMachineLayoutEdge> edges,
) {
  final bySource = <String, List<_StateMachineLayoutEdge>>{};
  for (final edge in edges) {
    bySource
        .putIfAbsent(edge.sourceStateId, () => <_StateMachineLayoutEdge>[])
        .add(edge);
  }
  for (final sourceEdges in bySource.values) {
    sourceEdges.sort((a, b) {
      final classCompare = _stateMachineLayoutEdgePriority(
        a,
      ).compareTo(_stateMachineLayoutEdgePriority(b));
      if (classCompare != 0) {
        return classCompare;
      }
      return a.order.compareTo(b.order);
    });
  }
  return bySource;
}

/// Assigns left-to-right ranks after cycle-removal.
Map<String, int> _stateMachineLayoutRanks(
  String initialId,
  List<String> ids,
  List<_StateMachineLayoutEdge> edges,
  Map<String, _StateMachineLayoutLane> lanes,
  Set<String> backEdgeKeys,
) {
  final ranks = <String, int>{initialId: 0};
  final forwardEdges = edges
      .where((edge) => !backEdgeKeys.contains(edge.key))
      .toList();
  for (var pass = 0; pass < ids.length; pass++) {
    var changed = false;
    for (final edge in forwardEdges) {
      if (!edge.structural &&
          edge.kind != _StateMachineTransitionKind.success) {
        continue;
      }
      final sourceRank = ranks[edge.sourceStateId] ?? 0;
      final targetRank = ranks[edge.targetStateId];
      final nextRank = sourceRank + 1;
      if (targetRank == null || targetRank < nextRank) {
        ranks[edge.targetStateId] = nextRank;
        changed = true;
      }
    }
    if (!changed) {
      break;
    }
  }
  for (final edge in forwardEdges) {
    if (edge.structural || edge.kind == _StateMachineTransitionKind.success) {
      continue;
    }
    final sourceRank = ranks[edge.sourceStateId] ?? 0;
    final nextRank = sourceRank + 1;
    final targetRank = ranks[edge.targetStateId];
    final targetLane =
        lanes[edge.targetStateId] ?? _StateMachineLayoutLane.primary;
    if (targetLane == _StateMachineLayoutLane.repair) {
      if (targetRank == null || targetRank > nextRank) {
        ranks[edge.targetStateId] = nextRank;
      }
      continue;
    }
    if (targetRank == null || targetRank < nextRank) {
      ranks[edge.targetStateId] = nextRank;
    }
  }
  for (final id in ids) {
    ranks.putIfAbsent(id, () => id == initialId ? 0 : 1);
  }
  final maxForwardRank = ranks.values.fold<int>(0, math.max);
  for (final id in ids) {
    if (lanes[id] == _StateMachineLayoutLane.terminal && id != initialId) {
      ranks[id] = math.max(ranks[id] ?? 0, maxForwardRank);
    }
  }
  return ranks;
}

/// Orders nodes inside each layer with barycenter-style sweeps.
Map<String, int> _stateMachineLayerOrders(
  List<String> ids,
  List<_StateMachineLayoutEdge> edges,
  Map<String, int> ranks,
  Map<String, _StateMachineLayoutLane> lanes,
) {
  final byRank = <int, List<String>>{};
  for (final id in ids) {
    byRank.putIfAbsent(ranks[id] ?? 0, () => <String>[]).add(id);
  }
  final order = <String, int>{};
  for (final entry in byRank.entries) {
    entry.value.sort(
      (a, b) =>
          _stateMachineLaneIndex(
            lanes[a] ?? _StateMachineLayoutLane.primary,
          ).compareTo(
            _stateMachineLaneIndex(lanes[b] ?? _StateMachineLayoutLane.primary),
          ),
    );
    for (var index = 0; index < entry.value.length; index++) {
      order[entry.value[index]] = index;
    }
  }
  final incoming = <String, List<String>>{};
  final outgoing = <String, List<String>>{};
  for (final edge in edges) {
    outgoing
        .putIfAbsent(edge.sourceStateId, () => <String>[])
        .add(edge.targetStateId);
    incoming
        .putIfAbsent(edge.targetStateId, () => <String>[])
        .add(edge.sourceStateId);
  }
  final rankKeys = byRank.keys.toList()..sort();
  for (var sweep = 0; sweep < 4; sweep++) {
    for (final rank in rankKeys.skip(1)) {
      _stateMachineSortLayerByNeighborBarycenter(
        byRank[rank] ?? const <String>[],
        incoming,
        order,
        lanes,
      );
    }
    for (final rank in rankKeys.reversed.skip(1)) {
      _stateMachineSortLayerByNeighborBarycenter(
        byRank[rank] ?? const <String>[],
        outgoing,
        order,
        lanes,
      );
    }
  }
  for (final entry in byRank.entries) {
    for (var index = 0; index < entry.value.length; index++) {
      order[entry.value[index]] = index;
    }
  }
  return order;
}

/// Sorts one layer near the average order of connected neighbor nodes.
void _stateMachineSortLayerByNeighborBarycenter(
  List<String> layer,
  Map<String, List<String>> neighbors,
  Map<String, int> order,
  Map<String, _StateMachineLayoutLane> lanes,
) {
  if (layer.length < 2) {
    return;
  }
  layer.sort((a, b) {
    final laneCompare =
        _stateMachineLaneIndex(
          lanes[a] ?? _StateMachineLayoutLane.primary,
        ).compareTo(
          _stateMachineLaneIndex(lanes[b] ?? _StateMachineLayoutLane.primary),
        );
    if (laneCompare != 0) {
      return laneCompare;
    }
    final aBarycenter = _stateMachineNeighborBarycenter(a, neighbors, order);
    final bBarycenter = _stateMachineNeighborBarycenter(b, neighbors, order);
    final barycenterCompare = aBarycenter.compareTo(bBarycenter);
    if (barycenterCompare != 0) {
      return barycenterCompare;
    }
    return (order[a] ?? 0).compareTo(order[b] ?? 0);
  });
  for (var index = 0; index < layer.length; index++) {
    order[layer[index]] = index;
  }
}

/// Returns the average neighbor order used by crossing minimization.
double _stateMachineNeighborBarycenter(
  String id,
  Map<String, List<String>> neighbors,
  Map<String, int> order,
) {
  final neighborIds = neighbors[id] ?? const <String>[];
  if (neighborIds.isEmpty) {
    return (order[id] ?? 0).toDouble();
  }
  final total = neighborIds.fold<double>(
    0,
    (value, neighborId) => value + (order[neighborId] ?? order[id] ?? 0),
  );
  return total / neighborIds.length;
}

/// Converts a ranked node into a bounded canvas coordinate.
Offset _stateMachineLayeredCoordinate(
  String id,
  Map<String, int> ranks,
  Map<String, _StateMachineLayoutLane> lanes,
  Map<String, int> layerOrders,
) {
  const padding = 84.0;
  final lane = lanes[id] ?? _StateMachineLayoutLane.primary;
  final rank = ranks[id] ?? 0;
  final order = layerOrders[id] ?? 0;
  final laneSlot = layerOrders.entries.where((entry) {
    return entry.key != id &&
        (ranks[entry.key] ?? 0) == rank &&
        (lanes[entry.key] ?? _StateMachineLayoutLane.primary) == lane &&
        entry.value < order;
  }).length;
  return Offset(
    padding + rank * _stateMachineLayoutNodeWidth,
    padding +
        _stateMachineLaneIndex(lane) * _stateMachineLaneGap +
        laneSlot * _stateMachineLayoutNodeHeight,
  );
}

/// Returns semantic swimlanes from state structure and transition classes.
Map<String, _StateMachineLayoutLane> _stateMachineLayoutLanesForStates(
  Map<String, Map<String, dynamic>> stateById,
  List<_StateMachineLayoutEdge> edges,
) {
  final failureTargets = <String>{
    for (final edge in edges)
      if (!edge.structural && edge.kind == _StateMachineTransitionKind.failure)
        edge.targetStateId,
  };
  return <String, _StateMachineLayoutLane>{
    for (final entry in stateById.entries)
      entry.key: _stateMachineLayoutLaneForState(
        entry.value,
        incomingFailure: failureTargets.contains(entry.key),
      ),
  };
}

/// Returns a semantic swimlane for one state.
_StateMachineLayoutLane _stateMachineLayoutLaneForState(
  Map<String, dynamic> state, {
  required bool incomingFailure,
}) {
  if (_stateMachineIsTerminalState(state)) {
    return _StateMachineLayoutLane.terminal;
  }
  if (_stateMachineUsesHumanRequest(state)) {
    return _StateMachineLayoutLane.operator;
  }
  if (incomingFailure) {
    return _StateMachineLayoutLane.repair;
  }
  return _StateMachineLayoutLane.primary;
}

/// Reports whether one state has no entry behavior, exits, or children.
bool _stateMachineIsTerminalState(Map<String, dynamic> state) {
  return '${state['initial'] ?? ''}'.trim().isEmpty &&
      _stateEntryActions(state).isEmpty &&
      _stateTransitions(state).isEmpty &&
      _list(state['states']).isEmpty;
}

/// Reports whether one state waits for human input through the generic action.
bool _stateMachineUsesHumanRequest(Map<String, dynamic> state) {
  return _stateEntryActions(state)
      .map(_map)
      .any((action) => '${action['uses'] ?? ''}'.trim() == 'human.request');
}

/// Returns a stable top-to-bottom lane index.
int _stateMachineLaneIndex(_StateMachineLayoutLane lane) {
  return switch (lane) {
    _StateMachineLayoutLane.primary => 0,
    _StateMachineLayoutLane.repair => 1,
    _StateMachineLayoutLane.operator => 2,
    _StateMachineLayoutLane.terminal => 3,
  };
}

/// Reports whether one projected edge returns from a side lane to the main path.
bool _stateMachineLayoutReturnsToPrimaryLane(
  _StateMachineLayoutEdge edge,
  Map<String, _StateMachineLayoutLane> lanes,
) {
  final sourceLane =
      lanes[edge.sourceStateId] ?? _StateMachineLayoutLane.primary;
  final targetLane =
      lanes[edge.targetStateId] ?? _StateMachineLayoutLane.primary;
  return sourceLane != _StateMachineLayoutLane.primary &&
      targetLane == _StateMachineLayoutLane.primary;
}

/// Returns semantic priority for traversal and crossing minimization.
int _stateMachineLayoutEdgePriority(_StateMachineLayoutEdge edge) {
  if (edge.structural) {
    return 0;
  }
  return switch (edge.kind) {
    _StateMachineTransitionKind.success => 1,
    _StateMachineTransitionKind.decision => 2,
    _StateMachineTransitionKind.failure => 3,
  };
}

/// Creates a new process-state from one palette action.
Map<String, dynamic> _newProcessState(
  List<Map<String, dynamic>> states,
  String actionName,
) {
  final id = _nextStateId(states, _stateBaseNameForAction(actionName));
  if (actionName == _terminalStatePaletteAction) {
    return <String, dynamic>{'id': id};
  }
  if (actionName == _inputStatePaletteAction) {
    return <String, dynamic>{
      'id': id,
      'on_entry': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'assert_input',
          'uses': 'data.assert',
          'with': <String, dynamic>{
            'mode': 'schema',
            'path': 'workflow_input',
            'schema': <String, dynamic>{'type': 'object'},
          },
        },
      ],
    };
  }
  return <String, dynamic>{
    'id': id,
    'on_entry': <Map<String, dynamic>>[_newEntryAction(const [], actionName)],
  };
}

/// Creates a new entry action for a process state.
Map<String, dynamic> _newEntryAction(
  List<Map<String, dynamic>> existingActions,
  String actionName,
) {
  final id = _nextEntryActionId(existingActions, actionName);
  return <String, dynamic>{
    'id': id,
    'uses': actionName,
    'with': _defaultStateMachineActionArgs(actionName),
  };
}

/// Returns valid starter arguments for one process-state action.
Map<String, dynamic> _defaultStateMachineActionArgs(String actionName) {
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
    'data.assert' => <String, dynamic>{'checks': <dynamic>[]},
    'human.request' => <String, dynamic>{
      'prompt': '',
      'payload': <String, dynamic>{},
    },
    'delay.until' => <String, dynamic>{'duration': ''},
    'workflow.run' => <String, dynamic>{
      'workflow': '',
      'input': <String, dynamic>{},
    },
    'workflow.signal' => <String, dynamic>{
      'run_id': '',
      'signal': '',
      'payload': <String, dynamic>{},
    },
    _ => <String, dynamic>{},
  };
}

/// Parses a JSON object without surfacing partial-edit errors.
Map<String, dynamic>? _tryParseJsonObject(String value) {
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
  } catch (_) {
    return null;
  }
  return null;
}

/// Returns the next transition trigger for a source state.
String _nextTransitionTrigger(List<Map<String, dynamic>> transitions) {
  final existing = transitions.map(_transitionTrigger).toSet();
  if (!existing.contains('succeeded')) {
    return 'succeeded';
  }
  if (!existing.contains('failed')) {
    return 'failed';
  }
  var index = transitions.length + 1;
  var trigger = 'signal_$index';
  while (existing.contains(trigger)) {
    index++;
    trigger = 'signal_$index';
  }
  return trigger;
}

/// Reads saved builder positions from definition authoring metadata.
Map<String, Offset> _stateMachinePositionsFromAuthoring(
  Map<String, dynamic> body,
) {
  final positions = _map(_map(_map(body['authoring'])['builder'])['positions']);
  return <String, Offset>{
    for (final entry in positions.entries)
      if (_positionFromValue(entry.value) != null)
        entry.key: _positionFromValue(entry.value)!,
  };
}

/// Writes builder positions into definition authoring metadata.
Map<String, dynamic> _stateMachineAuthoringWithPositions(
  Map<String, dynamic> authoring,
  Map<String, Offset> positions,
  Set<String> collapsedPhaseIds,
) {
  final next = Map<String, dynamic>.from(authoring);
  final builder = Map<String, dynamic>.from(_map(next['builder']));
  builder['positions'] = <String, Map<String, double>>{
    for (final entry in positions.entries)
      entry.key: <String, double>{'x': entry.value.dx, 'y': entry.value.dy},
  };
  builder['collapsed_phases'] = collapsedPhaseIds.toList()..sort();
  next['builder'] = builder;
  return next;
}

/// Reads collapsed composite phase ids from definition authoring metadata.
Set<String> _stateMachineCollapsedPhasesFromAuthoring(
  Map<String, dynamic> body,
) {
  final values = _list(
    _map(_map(body['authoring'])['builder'])['collapsed_phases'],
  );
  return values
      .map((value) => '$value'.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
}

/// Returns a saved builder position from JSON-compatible metadata.
Offset? _positionFromValue(dynamic value) {
  final map = _map(value);
  final x = map['x'];
  final y = map['y'];
  if (x is num && y is num) {
    return Offset(x.toDouble(), y.toDouble());
  }
  return null;
}

/// Returns the visual position for a state, falling back to auto layout.
Offset _stateMachinePositionForState(
  String stateId,
  List<Map<String, dynamic>> states,
  Map<String, Offset> positions,
  String initialStateId,
) {
  final saved = positions[stateId];
  if (saved != null) {
    return saved;
  }
  final layout = _StateMachineCanvasLayout.fromStates(
    states,
    initialStateId: initialStateId,
    positions: positions,
  );
  final placement = layout.byId[stateId];
  return placement?.rect.topLeft ?? const Offset(84, 84);
}

/// Returns a reasonable canvas position for a newly added state.
Offset _nextStateMachinePosition(Map<String, Offset> positions) {
  if (positions.isEmpty) {
    return const Offset(84, 84);
  }
  final maxX = positions.values.fold<double>(
    84,
    (value, offset) => offset.dx > value ? offset.dx : value,
  );
  final countAtRight = positions.values
      .where((offset) => offset.dx == maxX)
      .length;
  return Offset(maxX + 160, 84 + countAtRight * 112);
}

/// Builds a stable process-state id from an action name.
String _nextStateId(List<Map<String, dynamic>> states, String baseName) {
  final existing = states.map(_stateId).toSet();
  var index = states.length + 1;
  var id = baseName;
  if (existing.contains(id)) {
    id = '${baseName}_$index';
  }
  while (existing.contains(id)) {
    index++;
    id = '${baseName}_$index';
  }
  return id;
}

/// Builds a stable entry-action id from an action name.
String _nextEntryActionId(
  List<Map<String, dynamic>> actions,
  String actionName,
) {
  final existing = actions.map((action) => '${action['id'] ?? ''}').toSet();
  final base = _stateBaseNameForAction(actionName);
  var index = actions.length + 1;
  var id = base;
  if (existing.contains(id)) {
    id = '${base}_$index';
  }
  while (existing.contains(id)) {
    index++;
    id = '${base}_$index';
  }
  return id;
}

/// Returns a readable id base for one process-state palette item.
String _stateBaseNameForAction(String actionName) {
  return switch (actionName) {
    _inputStatePaletteAction => 'intake_contract',
    _terminalStatePaletteAction => 'done',
    'tool.call' => 'run_tool',
    'mcp.call' => 'call_mcp_tool',
    'data.assert' => 'assert_data',
    'human.request' => 'operator_decision',
    'delay.until' => 'wait',
    'workflow.run' => 'run_workflow',
    'workflow.signal' => 'send_signal',
    _ =>
      actionName.replaceAll('.', '_').replaceAll('-', '_').replaceAll(' ', '_'),
  };
}

/// Returns a process-state node icon for a palette action.
IconData _stateMachineNodeIcon(String actionName) {
  return switch (actionName) {
    _inputStatePaletteAction => Icons.input_outlined,
    _terminalStatePaletteAction => Icons.stop_circle_outlined,
    _ => _actionIcon(actionName),
  };
}

/// Returns a process-state palette and node accent color.
Color _stateMachinePaletteColor(BuildContext context, String actionName) {
  final colors = context.agentAwesomeColors;
  return switch (actionName) {
    _inputStatePaletteAction => colors.cardIcon,
    _terminalStatePaletteAction => colors.coral,
    _ => _actionColor(context, actionName),
  };
}

/// Builds an orthogonal path for one process-state transition edge.
Path _stateMachineEdgePath(Offset from, Offset to, bool backEdge) {
  if (backEdge) {
    final laneY = math.max(from.dy, to.dy) + 72;
    return Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(from.dx + 38, from.dy)
      ..lineTo(from.dx + 38, laneY)
      ..lineTo(to.dx - 38, laneY)
      ..lineTo(to.dx - 38, to.dy)
      ..lineTo(to.dx, to.dy);
  }
  final midX = from.dx + math.max(42.0, (to.dx - from.dx) / 2);
  return Path()
    ..moveTo(from.dx, from.dy)
    ..lineTo(midX, from.dy)
    ..lineTo(midX, to.dy)
    ..lineTo(to.dx, to.dy);
}

/// Returns the visible input port center for a process-state placement.
Offset _stateMachineInputPortCenter(Rect rect) {
  return Offset(rect.left, rect.top + 62);
}

/// Returns the visible output port center for a process-state placement.
Offset _stateMachineOutputPortCenter(Rect rect) {
  return Offset(rect.right, rect.top + 62);
}
