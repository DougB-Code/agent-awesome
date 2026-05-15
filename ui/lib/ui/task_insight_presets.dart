/// Defines task insight presets shared by projection controls.
library;

import 'package:flutter/material.dart';

import '../domain/task_insight_query.dart';

/// TaskInsightPresetRegistry exposes stable one-click terrain insight presets.
class TaskInsightPresetRegistry {
  const TaskInsightPresetRegistry._();

  /// Terrain presets shown above projection overlays.
  static const List<TaskInsightPreset> terrainPresets = <TaskInsightPreset>[
    TaskInsightPreset(
      id: TaskInsightIds.all,
      label: 'All insights',
      question: 'Show all backlog items that match the current filters.',
      iconName: 'all',
    ),
    TaskInsightPreset(
      id: TaskInsightIds.todayActions,
      label: 'Execute',
      question: 'Which backlog items are ready for concrete execution?',
      iconName: 'actions',
    ),
    TaskInsightPreset(
      id: TaskInsightIds.todayDecisions,
      label: 'Decide',
      question: 'Which backlog items need human judgment or approval?',
      iconName: 'decisions',
    ),
    TaskInsightPreset(
      id: TaskInsightIds.todayRelationships,
      label: 'Follow-ups',
      question: 'Which people, promise, reply, or check-in loops are due?',
      iconName: 'followups',
    ),
    TaskInsightPreset(
      id: TaskInsightIds.agentHandoff,
      label: 'Agent can handle',
      question: 'What low-value must-do work can I safely hand off?',
      iconName: 'agent',
    ),
    TaskInsightPreset(
      id: TaskInsightIds.metadataGaps,
      label: 'Data quality',
      question: 'Which data gaps limit backlog insights?',
      iconName: 'quality',
    ),
  ];

  /// Returns the selected terrain preset, falling back to the all preset.
  static TaskInsightPreset selectedTerrainPreset(String presetId) {
    for (final preset in terrainPresets) {
      if (preset.id == presetId) {
        return preset;
      }
    }
    return terrainPresets.first;
  }

  /// Returns a Material icon for a preset icon name.
  static IconData iconFor(String iconName) {
    return switch (iconName) {
      'actions' => Icons.check_box_outlined,
      'decisions' => Icons.balance_outlined,
      'followups' => Icons.forum_outlined,
      'agent' => Icons.smart_toy_outlined,
      'calendar' => Icons.calendar_month_outlined,
      'unlock' => Icons.lock_open_outlined,
      'metadata' => Icons.manage_search_outlined,
      'quality' => Icons.fact_check_outlined,
      'risk' => Icons.report_problem_outlined,
      _ => Icons.all_inbox_outlined,
    };
  }
}
