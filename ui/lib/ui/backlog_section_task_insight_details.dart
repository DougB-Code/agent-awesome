/// Backlog selected-task insight explanation widget.
part of 'backlog_section.dart';

/// _TaskInsightDetailsBlock explains selected-task insight membership.
class _TaskInsightDetailsBlock extends StatelessWidget {
  const _TaskInsightDetailsBlock({
    required this.controller,
    required this.task,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  /// Builds insight summary, unblock plan, handoff, and metadata gaps.
  @override
  Widget build(BuildContext context) {
    final index = controller.taskInsightIndex;
    final taskId = task.id;
    final scores = index.scoresFor(taskId);
    final candidates = index.candidatesForTask(taskId);
    final plan = index.unblockPlanFor(taskId);
    final gaps = index.metadataGapsFor(taskId);
    final handoff = index.candidateForTask(taskId, TaskInsightIds.agentHandoff);
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _TaskPanelLabel('Insights'),
          const SizedBox(height: 10),
          Text(
            TaskInsightExplanations.whyThisMatters(
              task: task,
              scores: scores,
              candidates: candidates,
            ),
            style: TextStyle(
              color: context.agentAwesomeColors.ink,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              if (scores != null) ...<Widget>[
                _TaskBadge(label: 'Reward ${_formatTaskScore(scores.reward)}'),
                _TaskBadge(
                  label: 'Pressure ${_formatTaskScore(scores.pressure)}',
                ),
                _TaskBadge(label: 'Risk ${_formatTaskScore(scores.risk)}'),
                _TaskBadge(
                  label: 'Confidence ${_formatTaskScore(scores.confidence)}',
                ),
              ],
              for (final candidate in candidates.take(3))
                _TaskBadge(label: _insightCandidateLabel(candidate)),
            ],
          ),
          if (plan.hasExplicitBlocker ||
              task.status == 'blocked' ||
              task.status == 'waiting') ...<Widget>[
            const Divider(height: 22),
            _TaskGraphRow(
              icon: Icons.lock_open_outlined,
              title: 'Unblock plan',
              subtitle: plan.explanation,
              badges: <String>[
                if (plan.primaryBlockerId.isNotEmpty)
                  'Blocked by ${index.titleForTaskId(plan.primaryBlockerId)}',
                if (plan.downstreamTaskIds.isNotEmpty)
                  'Unlocks ${plan.downstreamTaskIds.length}',
                _formatTaskScore(plan.confidence),
              ],
              actions: const <Widget>[],
            ),
            _TaskMetadataRow(
              label: 'Next action',
              value: plan.smallestNextAction,
            ),
            if (plan.agentAssistOptions.isNotEmpty)
              _TaskMetadataRow(
                label: 'Agent can help',
                value: plan.agentAssistOptions.take(2).join(' '),
              ),
          ],
          if (handoff != null) ...<Widget>[
            const Divider(height: 22),
            _TaskGraphRow(
              icon: Icons.smart_toy_outlined,
              title: 'Agent handoff readiness',
              subtitle: handoff.explanation,
              badges: <String>[
                handoff.severity == 'warning' ? 'Needs review' : 'Ready',
                if (scores != null) 'Fit ${_formatTaskScore(scores.agentFit)}',
                if (scores != null)
                  'Safety ${_formatTaskScore(scores.agentSafety)}',
              ],
              actions: const <Widget>[],
            ),
          ],
          if (gaps.isNotEmpty) ...<Widget>[
            const Divider(height: 22),
            for (final gap in gaps.take(3))
              _TaskGraphRow(
                icon: Icons.manage_search_outlined,
                title: 'Missing ${gap.field.replaceAll('_', ' ')}',
                subtitle: gap.message.isEmpty
                    ? gap.proposedAction
                    : gap.message,
                badges: <String>[
                  _taskLabel(gap.severity),
                  for (final insight in gap.blocksInsights.take(2))
                    _taskLabel(insight),
                ],
                actions: const <Widget>[],
              ),
          ],
        ],
      ),
    );
  }

  /// Returns a compact badge label for one insight candidate.
  String _insightCandidateLabel(TaskInsightCandidate candidate) {
    final label = switch (candidate.insightId) {
      TaskInsightIds.todayActions => 'Execute',
      TaskInsightIds.todayDecisions => 'Decide',
      TaskInsightIds.todayRelationships => 'Follow-up',
      TaskInsightIds.agentHandoff => 'Agent handoff',
      TaskInsightIds.nextWeekHighValue => 'Next week value',
      TaskInsightIds.quickUnblocks => 'Quick unblock',
      TaskInsightIds.metadataGaps => 'Metadata gap',
      TaskInsightIds.highRiskLowConfidence => 'Risk gap',
      _ => 'Insight',
    };
    return '$label ${_formatTaskScore(candidate.score)}';
  }
}
