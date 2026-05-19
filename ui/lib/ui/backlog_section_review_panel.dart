/// Backlog AI screen-change review widgets.
part of 'backlog_section.dart';

/// _BacklogReviewContent renders screen-command changes in the detail panel.
class _BacklogReviewContent extends StatelessWidget {
  /// Creates the backlog review detail content.
  const _BacklogReviewContent({required this.controller});

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Builds the current screen-command review list.
  @override
  Widget build(BuildContext context) {
    final run = controller.activeScreenCommandRun;
    if (run == null) {
      return const PanelEmptyBlock(label: 'No AI changes to review');
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ScreenRunSummaryBlock(controller: controller, run: run),
          const SizedBox(height: 12),
          if (run.changes.isEmpty)
            const PanelEmptyBlock(label: 'No changes match this view')
          else
            for (final change in run.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ScreenChangeReviewCard(
                  controller: controller,
                  change: change,
                ),
              ),
        ],
      ),
    );
  }
}

class _ScreenRunSummaryBlock extends StatelessWidget {
  const _ScreenRunSummaryBlock({required this.controller, required this.run});

  final AgentAwesomeAppController controller;
  final ScreenCommandRun run;

  /// Builds summary counts for one screen-command run.
  @override
  Widget build(BuildContext context) {
    final applied = run.changes
        .where((change) => change.status == ScreenChangeStatus.applied)
        .length;
    final review = run.changes
        .where((change) => change.status == ScreenChangeStatus.proposed)
        .length;
    final rejected = run.changes
        .where((change) => change.status == ScreenChangeStatus.rejected)
        .length;
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'AI found ${run.changes.length} changes',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          SelectableText(
            controller.screenCommandMessage,
            style: TextStyle(color: context.agentAwesomeColors.muted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _TaskBadge(label: 'Applied $applied'),
              _TaskBadge(label: 'Needs review $review'),
              _TaskBadge(label: 'Rejected $rejected'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScreenChangeReviewCard extends StatelessWidget {
  const _ScreenChangeReviewCard({
    required this.controller,
    required this.change,
  });

  final AgentAwesomeAppController controller;
  final ScreenChange change;

  /// Builds one reviewable AI change card.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final focused = controller.focusedScreenChangeId == change.id;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => controller.focusBacklogScreenChange(change.id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: focused ? colors.greenSoft : colors.surface,
          gradient: focused ? context.agentAwesomeSelectedGradient : null,
          border: Border.all(color: focused ? colors.green : colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  _screenChangeIcon(change),
                  size: 18,
                  color: _screenChangeColor(context, change),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    change.summary,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                _TaskBadge(label: _screenChangeStatusLabel(change)),
              ],
            ),
            if (change.reason.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(change.reason, style: TextStyle(color: colors.muted)),
            ],
            if (change.error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              SelectableText(
                change.error,
                style: const TextStyle(
                  color: AgentAwesomeColors.coral,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _ScreenChangeDiffList(change: change),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                PanelInlineIconButton(
                  icon: Icons.center_focus_strong,
                  tooltip: 'Focus change',
                  onPressed: () =>
                      controller.focusBacklogScreenChange(change.id),
                ),
                const Spacer(),
                if (change.status == ScreenChangeStatus.proposed &&
                    change.safety != ScreenChangeSafety.rejected) ...<Widget>[
                  PanelInlineIconButton(
                    icon: Icons.check,
                    tooltip: 'Apply change',
                    selected: true,
                    onPressed: controller.screenCommandBusy
                        ? null
                        : () => unawaited(
                            controller.applyScreenChangeFromUi(change.id),
                          ),
                  ),
                  const SizedBox(width: 8),
                  PanelInlineIconButton(
                    icon: Icons.close,
                    tooltip: 'Reject change',
                    onPressed: controller.screenCommandBusy
                        ? null
                        : () => unawaited(
                            controller.rejectScreenChangeFromUi(change.id),
                          ),
                  ),
                ],
                if (controller.screenChangeCanUndo(change))
                  PanelInlineIconButton(
                    icon: Icons.undo,
                    tooltip: 'Undo change',
                    onPressed: controller.screenCommandBusy
                        ? null
                        : () => unawaited(
                            controller.undoScreenChangeFromUi(change.id),
                          ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenChangeDiffList extends StatelessWidget {
  const _ScreenChangeDiffList({required this.change});

  final ScreenChange change;

  /// Builds before/after diff rows for one change.
  @override
  Widget build(BuildContext context) {
    final keys = <String>{
      ...change.beforeValues.keys,
      ...change.afterValues.keys,
    }.toList();
    if (keys.isEmpty) {
      final colors = context.agentAwesomeColors;
      return Text(
        _screenChangeOperationLabel(change.operation),
        style: TextStyle(color: colors.muted),
      );
    }
    final colors = context.agentAwesomeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final key in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 110,
                  child: Text(
                    _taskLabel(key.replaceAll('_', ' ')),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _screenValueLabel(change.beforeValues[key]),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 16),
                ),
                Expanded(
                  child: Text(
                    _screenValueLabel(change.afterValues[key]),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.green,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
