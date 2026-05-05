/// Defines selected-task unblock diagnosis data.
library;

import 'models.dart';

/// TaskUnblockPlan explains how a selected task can become unstuck.
class TaskUnblockPlan {
  /// Creates a selected-task unblock plan.
  const TaskUnblockPlan({
    required this.taskId,
    this.status = '',
    this.primaryBlockerId = '',
    this.blockerType = '',
    this.blockerOwner = '',
    this.blockingRelations = const <TaskProjectionEdge>[],
    this.downstreamTaskIds = const <String>[],
    this.smallestNextAction = '',
    this.agentAssistOptions = const <String>[],
    this.missingContext = const <String>[],
    this.evidenceIds = const <String>[],
    this.confidence = 0,
    this.explanation = '',
  });

  /// Canonical task id receiving the diagnosis.
  final String taskId;

  /// Current task status.
  final String status;

  /// Primary canonical blocker task id.
  final String primaryBlockerId;

  /// Blocker relation type.
  final String blockerType;

  /// Person or waiting entity responsible for the blocker.
  final String blockerOwner;

  /// Relations that make this task blocked or waiting.
  final List<TaskProjectionEdge> blockingRelations;

  /// Canonical downstream task ids affected by resolving the blocker.
  final List<String> downstreamTaskIds;

  /// Smallest concrete next action.
  final String smallestNextAction;

  /// Safe agent-assist options.
  final List<String> agentAssistOptions;

  /// Missing context that limits unblock confidence.
  final List<String> missingContext;

  /// Evidence ids supporting the plan.
  final List<String> evidenceIds;

  /// Plan confidence from 0 to 1.
  final double confidence;

  /// Human-readable plan explanation.
  final String explanation;

  /// Returns whether this plan contains an explicit graph blocker.
  bool get hasExplicitBlocker {
    return primaryBlockerId.isNotEmpty || blockingRelations.isNotEmpty;
  }
}
