/// Route shell and controller actions for the Today attention screen.
part of 'attention_screen.dart';

/// TodayAttentionScreen explains why projected tasks need attention now.
class TodayAttentionScreen extends StatefulWidget {
  /// Creates a Today-owned attention detail surface.
  const TodayAttentionScreen({
    super.key,
    required this.controller,
    this.route = '/attention',
    this.onOpenToday,
    this.onOpenBacklogTask,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Reserved Today projection route that scoped this screen.
  final String route;

  /// Returns to the main Today dashboard.
  final VoidCallback? onOpenToday;

  /// Opens the backing task in the Backlog inspector.
  final ValueChanged<String>? onOpenBacklogTask;

  @override
  State<TodayAttentionScreen> createState() => _TodayAttentionScreenState();
}

/// _TodayAttentionScreenState stores local filters for the attention surface.
class _TodayAttentionScreenState extends State<TodayAttentionScreen> {
  _AttentionFilter _filter = _AttentionFilter.all;
  String _selectedItemId = '';

  /// Seeds local selection from the initial route.
  @override
  void initState() {
    super.initState();
    _selectedItemId = _attentionScopeForRoute(widget.route).itemId;
  }

  /// Keeps local selection aligned when the shell opens a new attention route.
  @override
  void didUpdateWidget(covariant TodayAttentionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route == widget.route) {
      return;
    }
    final scope = _attentionScopeForRoute(widget.route);
    setState(() {
      _filter = _AttentionFilter.all;
      _selectedItemId = scope.itemId;
    });
  }

  /// Builds the attention queue and details panel.
  @override
  Widget build(BuildContext context) {
    final projection = widget.controller.todayState.projection;
    final scope = _attentionScopeForRoute(widget.route);
    final scopedItems = _itemsForScope(projection.attention.items, scope);
    final filteredItems = _itemsForFilter(scopedItems, _filter);
    final selected = _selectedItem(filteredItems, scopedItems, _selectedItemId);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _AttentionHeader(
            title: _titleForScope(scope, scopedItems.length),
            subtitle: _subtitleForScope(scope),
            busy: widget.controller.todayState.busy,
            updatedAt: projection.generatedAt,
            onBack: widget.onOpenToday,
            onRefresh: () => unawaited(widget.controller.refreshTodayFromUi()),
            onExplain: selected == null
                ? null
                : () => unawaited(_showExplanation(selected)),
          ),
          const SizedBox(height: 18),
          _AttentionFilterBar(
            items: scopedItems,
            selected: _filter,
            onSelected: (filter) {
              setState(() {
                _filter = filter;
              });
            },
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1080;
              final list = _AttentionList(
                items: filteredItems,
                selected: selected,
                onSelected: (item) {
                  setState(() {
                    _selectedItemId = item.id;
                  });
                },
                onOpenBacklogTask: _openBacklogTask,
                onComplete: _completeItem,
              );
              final details = _AttentionDetailsPanel(
                item: selected,
                task: selected == null ? null : _workspaceTaskForItem(selected),
                onOpenBacklogTask: selected == null
                    ? null
                    : () => _openBacklogTask(selected),
                onComplete: selected == null
                    ? null
                    : () => _completeItem(selected),
              );
              if (!wide) {
                return Column(
                  children: <Widget>[list, const SizedBox(height: 14), details],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 7, child: list),
                  const SizedBox(width: 18),
                  SizedBox(width: 390, child: details),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Opens the existing item explanation drawer for one attention item.
  Future<void> _showExplanation(ExecutiveSummaryItem item) async {
    await widget.controller.explainTodayItem(item.id);
    if (!mounted) {
      return;
    }
    final explanation = widget.controller.todayState.explanation;
    if (explanation.itemId != item.id && explanation.reason.isEmpty) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.agentAwesomeColors.surface,
      builder: (context) {
        return ExecutiveSummaryExplanationDrawer(explanation: explanation);
      },
    );
    widget.controller.clearTodayExplanation();
  }

  /// Opens the backing task in the Backlog inspector when one is linked.
  void _openBacklogTask(ExecutiveSummaryItem item) {
    final taskId = _taskIdForItem(item);
    if (taskId.isEmpty) {
      return;
    }
    widget.onOpenBacklogTask?.call(taskId);
  }

  /// Completes the linked task through the existing task controller API.
  void _completeItem(ExecutiveSummaryItem item) {
    final taskId = _taskIdForItem(item);
    if (taskId.isEmpty) {
      return;
    }
    unawaited(widget.controller.completeTaskFromUi(taskId));
  }

  /// Returns the workspace task linked to an attention item, if loaded.
  WorkspaceTask? _workspaceTaskForItem(ExecutiveSummaryItem item) {
    final taskId = _taskIdForItem(item);
    if (taskId.isEmpty) {
      return null;
    }
    for (final task in widget.controller.workspace.tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }
}
