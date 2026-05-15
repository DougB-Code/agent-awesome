/// Terrain projection helpers for indexed task insights.
part of 'task_projection_adapters.dart';

List<String> _terrainTaskIds(
  TaskInsightIndex index,
  TaskTerrainInsightMode mode,
) {
  final ids = switch (mode) {
    TaskTerrainInsightMode.priorityFocus => _activeTaskIds(index),
    TaskTerrainInsightMode.agentHandoff =>
      index
          .tasksForInsight(TaskInsightIds.agentHandoff)
          .map((candidate) => candidate.taskId)
          .toList(),
    TaskTerrainInsightMode.nextWeekHighValue =>
      index
          .tasksForInsight(TaskInsightIds.nextWeekHighValue)
          .map((candidate) => candidate.taskId)
          .toList(),
    TaskTerrainInsightMode.unblockLeverage =>
      index
          .tasksForInsight(TaskInsightIds.quickUnblocks)
          .map((candidate) => candidate.taskId)
          .toList(),
    TaskTerrainInsightMode.riskFocus => <String>{
      ...index
          .tasksForInsight(TaskInsightIds.highRiskLowConfidence)
          .map((candidate) => candidate.taskId),
    }.toList(),
  };
  if (ids.isNotEmpty || mode == TaskTerrainInsightMode.priorityFocus) {
    return ids;
  }
  return _activeTaskIds(index);
}

/// Builds one terrain point for a mode.
PriorityTerrainPoint _terrainPoint(
  TaskInsightIndex index,
  String taskId,
  TaskTerrainInsightMode mode,
) {
  final scores =
      index.scoresFor(taskId) ??
      TaskInsightScoreProfile.fromTask(
        taskId: taskId,
        workspaceTask: index.workspaceTasksById[taskId],
        projectionTask: index.projectionTasksById[taskId],
      );
  final coordinates = _terrainCoordinates(scores, mode);
  return PriorityTerrainPoint(
    taskId: taskId,
    title: index.titleForTaskId(taskId),
    status: _statusFor(index, taskId),
    priority: _priorityFor(index, taskId),
    dueAt: _dueAtFor(index, taskId),
    urgencyScore: scores.pressure,
    valueScore: scores.reward,
    effortScore: scores.humanEffort,
    riskScore: scores.risk,
    rewardScore: scores.reward,
    timePressureScore: scores.timePressure,
    agentFitScore: scores.agentFit,
    humanEffortScore: scores.humanEffort,
    terrainZone: _terrainZoneForMode(index, taskId, scores, mode),
    x: coordinates.x,
    y: coordinates.y,
    elevation: _terrainElevation(scores, mode),
    recommendedNextStep: _indexNextBestAction(index, taskId),
    confidence: 0,
    explanation: _terrainExplanation(index, taskId, mode),
  );
}

/// Returns mode-specific terrain coordinates.
math.Point<double> _terrainCoordinates(
  TaskInsightScoreProfile scores,
  TaskTerrainInsightMode mode,
) {
  return switch (mode) {
    TaskTerrainInsightMode.priorityFocus => math.Point<double>(
      scores.reward,
      scores.pressure,
    ),
    TaskTerrainInsightMode.agentHandoff => math.Point<double>(
      scores.handoffReadiness,
      scores.obligation,
    ),
    TaskTerrainInsightMode.nextWeekHighValue => math.Point<double>(
      scores.reward,
      math.max(scores.consequence, scores.timePressure),
    ),
    TaskTerrainInsightMode.unblockLeverage => math.Point<double>(
      scores.unblockLeverage,
      scores.blockerEffort,
    ),
    TaskTerrainInsightMode.riskFocus => math.Point<double>(
      scores.timePressure,
      scores.risk,
    ),
  };
}

/// Returns the terrain zone id for a mode.
String _terrainZoneForMode(
  TaskInsightIndex index,
  String taskId,
  TaskInsightScoreProfile scores,
  TaskTerrainInsightMode mode,
) {
  return switch (mode) {
    TaskTerrainInsightMode.priorityFocus =>
      index.projectionTasksById[taskId]?.scores.terrainZone ?? '',
    TaskTerrainInsightMode.agentHandoff => _agentHandoffZone(
      scores,
      index.policy.safeAgentThreshold,
    ),
    TaskTerrainInsightMode.nextWeekHighValue => _nextWeekZone(scores),
    TaskTerrainInsightMode.unblockLeverage => _unblockZone(scores),
    TaskTerrainInsightMode.riskFocus => _riskFocusZone(scores),
  };
}

/// Returns the agent-handoff atlas zone for one task.
String _agentHandoffZone(
  TaskInsightScoreProfile scores,
  double safeAgentThreshold,
) {
  if (scores.humanJudgmentNeed >= 0.58 ||
      scores.agentSafety < safeAgentThreshold) {
    return 'human-judgment';
  }
  if (scores.handoffReadiness >= 0.58 && scores.agentSafety >= 0.58) {
    return 'ready-for-agent';
  }
  if (scores.agentFit >= 0.45 || scores.contextReadiness >= 0.45) {
    return 'agent-candidate';
  }
  return 'needs-review';
}

/// Returns the next-week value atlas zone for one task.
String _nextWeekZone(TaskInsightScoreProfile scores) {
  final consequence = math.max(scores.consequence, scores.timePressure);
  if (scores.reward >= 0.58 && scores.risk >= 0.58) {
    return 'rising-risk';
  }
  if (scores.reward >= 0.62 && consequence >= 0.50) {
    return 'high-value-next-week';
  }
  if (scores.reward >= 0.46 || consequence >= 0.44) {
    return 'prepare-early';
  }
  return 'next-week-backlog';
}

/// Returns the unblock leverage atlas zone for one task.
String _unblockZone(TaskInsightScoreProfile scores) {
  final ease = 1 - scores.blockerEffort.clamp(0, 1).toDouble();
  if (scores.unblockLeverage >= 0.58 && ease >= 0.50) {
    return 'quick-unblock';
  }
  if (scores.unblockLeverage >= 0.58) {
    return 'high-leverage-blocker';
  }
  if (ease >= 0.55) {
    return 'simple-blocker';
  }
  return 'costly-blocker';
}

/// Returns the risk atlas zone for one task.
String _riskFocusZone(TaskInsightScoreProfile scores) {
  final risk = scores.risk;
  if (risk >= 0.70 && scores.timePressure >= 0.70) {
    return 'urgent-risk';
  }
  if (risk >= 0.58) {
    return 'high-risk';
  }
  if (scores.timePressure >= 0.58) {
    return 'watch-risk';
  }
  return 'low-risk';
}

/// Returns mode-specific point elevation.
double _terrainElevation(
  TaskInsightScoreProfile scores,
  TaskTerrainInsightMode mode,
) {
  return switch (mode) {
    TaskTerrainInsightMode.priorityFocus => _clamp01(
      0.45 * scores.reward + 0.35 * scores.pressure + 0.20 * scores.risk,
    ),
    TaskTerrainInsightMode.agentHandoff => _clamp01(
      0.40 * scores.handoffReadiness +
          0.25 * scores.obligation +
          0.20 * scores.agentSafety +
          0.15 * scores.agentFit,
    ),
    TaskTerrainInsightMode.nextWeekHighValue => _clamp01(
      0.45 * scores.reward + 0.30 * scores.consequence + 0.10 * scores.pressure,
    ),
    TaskTerrainInsightMode.unblockLeverage => _clamp01(
      0.60 * scores.unblockLeverage + 0.25 * scores.downstreamValue,
    ),
    TaskTerrainInsightMode.riskFocus => _clamp01(scores.risk),
  };
}

/// Returns a mode-specific terrain explanation.
String _terrainExplanation(
  TaskInsightIndex index,
  String taskId,
  TaskTerrainInsightMode mode,
) {
  final insightId = switch (mode) {
    TaskTerrainInsightMode.agentHandoff => TaskInsightIds.agentHandoff,
    TaskTerrainInsightMode.nextWeekHighValue =>
      TaskInsightIds.nextWeekHighValue,
    TaskTerrainInsightMode.unblockLeverage => TaskInsightIds.quickUnblocks,
    TaskTerrainInsightMode.riskFocus => TaskInsightIds.highRiskLowConfidence,
    TaskTerrainInsightMode.priorityFocus => _primaryInsightId(index, taskId),
  };
  return index.explainTaskInsight(taskId, insightId);
}

/// Returns mode-specific terrain band labels.
List<PriorityTerrainBand> _terrainBandsForMode(TaskTerrainInsightMode mode) {
  return switch (mode) {
    TaskTerrainInsightMode.priorityFocus => const <PriorityTerrainBand>[
      PriorityTerrainBand(
        id: 'high-value-risk',
        title: 'High Value + Pressure',
        description: 'High impact work that is costly to miss.',
      ),
      PriorityTerrainBand(
        id: 'quick-win',
        title: 'Quick Wins',
        description: 'Useful low-effort work worth clearing.',
      ),
      PriorityTerrainBand(
        id: 'agent-opportunity',
        title: 'Agent Opportunity',
        description: 'High-reward work the agent can likely help complete.',
      ),
      PriorityTerrainBand(
        id: 'steady-progress',
        title: 'Steady Progress',
        description: 'Important work without immediate pressure.',
      ),
      PriorityTerrainBand(
        id: 'risk',
        title: 'Risk & Blockers',
        description: 'Blocked, waiting, or uncertain work.',
      ),
      PriorityTerrainBand(
        id: 'backlog',
        title: 'Backlog',
        description: 'Low-pressure work to keep bounded.',
      ),
    ],
    TaskTerrainInsightMode.agentHandoff => const <PriorityTerrainBand>[
      PriorityTerrainBand(
        id: 'agent-candidate',
        title: 'Candidate Later',
        description: 'Possible handoff after better context.',
      ),
      PriorityTerrainBand(
        id: 'ready-for-agent',
        title: 'Ready for Agent',
        description: 'Clear, safe work that can be delegated.',
      ),
      PriorityTerrainBand(
        id: 'needs-review',
        title: 'Needs Review',
        description: 'Could be delegated after scope or context review.',
      ),
      PriorityTerrainBand(
        id: 'human-judgment',
        title: 'Human Judgment',
        description: 'Risky, sensitive, or judgment-heavy work.',
      ),
    ],
    TaskTerrainInsightMode.nextWeekHighValue => const <PriorityTerrainBand>[
      PriorityTerrainBand(
        id: 'next-week-backlog',
        title: 'Lower Value',
        description: 'Keep bounded or defer.',
      ),
      PriorityTerrainBand(
        id: 'prepare-early',
        title: 'Prepare Early',
        description: 'Valuable work with room to schedule.',
      ),
      PriorityTerrainBand(
        id: 'rising-risk',
        title: 'Watch Risk',
        description: 'Valuable work that could slip.',
      ),
      PriorityTerrainBand(
        id: 'high-value-next-week',
        title: 'High Value',
        description: 'High-consequence work coming next week.',
      ),
    ],
    TaskTerrainInsightMode.unblockLeverage => const <PriorityTerrainBand>[
      PriorityTerrainBand(
        id: 'simple-blocker',
        title: 'Simple Blockers',
        description: 'Low effort with modest leverage.',
      ),
      PriorityTerrainBand(
        id: 'quick-unblock',
        title: 'Quick Unblocks',
        description: 'Low effort with downstream payoff.',
      ),
      PriorityTerrainBand(
        id: 'costly-blocker',
        title: 'Costly Blockers',
        description: 'High effort for limited leverage.',
      ),
      PriorityTerrainBand(
        id: 'high-leverage-blocker',
        title: 'High Leverage',
        description: 'Worth effort because it unlocks work.',
      ),
    ],
    TaskTerrainInsightMode.riskFocus => const <PriorityTerrainBand>[
      PriorityTerrainBand(
        id: 'low-risk',
        title: 'Low Risk',
        description: 'Lower due-date risk.',
      ),
      PriorityTerrainBand(
        id: 'watch-risk',
        title: 'Watch Risk',
        description: 'Timing pressure is rising.',
      ),
      PriorityTerrainBand(
        id: 'high-risk',
        title: 'High Risk',
        description: 'Due-date risk is high.',
      ),
      PriorityTerrainBand(
        id: 'urgent-risk',
        title: 'Urgent Risk',
        description: 'High risk with immediate timing pressure.',
      ),
    ],
  };
}
