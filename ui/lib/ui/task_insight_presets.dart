/// Defines task insight presets shared by queue and projection controls.
library;

import 'package:flutter/material.dart';

import '../domain/task_insight_query.dart';

/// TaskInsightPresetRegistry exposes stable one-click task insight presets.
class TaskInsightPresetRegistry {
  const TaskInsightPresetRegistry._();

  /// Queue presets shown above operational filters.
  static const List<TaskInsightPreset> queuePresets = <TaskInsightPreset>[
    TaskInsightPreset(
      id: TaskInsightIds.all,
      label: 'All',
      question: 'Show all backlog items that match the current filters.',
      iconName: 'all',
    ),
    TaskInsightPreset(
      id: TaskInsightIds.agentHandoff,
      label: 'Agent handoff',
      question: 'What low-value must-do work can I safely hand off?',
      iconName: 'agent',
    ),
    TaskInsightPreset(
      id: TaskInsightIds.nextWeekHighValue,
      label: 'Next week high value',
      question: 'What high-value work is coming up next week?',
      iconName: 'calendar',
    ),
    TaskInsightPreset(
      id: TaskInsightIds.quickUnblocks,
      label: 'Quick unblocks',
      question: 'What can I unblock quickly?',
      iconName: 'unlock',
    ),
    TaskInsightPreset(
      id: TaskInsightIds.metadataGaps,
      label: 'Metadata gaps',
      question: 'What prevents better backlog insights?',
      iconName: 'metadata',
    ),
    TaskInsightPreset(
      id: TaskInsightIds.highRiskLowConfidence,
      label: 'Risk gaps',
      question: 'What looks risky but uncertain?',
      iconName: 'risk',
    ),
  ];

  /// Returns a Material icon for a preset icon name.
  static IconData iconFor(String iconName) {
    return switch (iconName) {
      'agent' => Icons.smart_toy_outlined,
      'calendar' => Icons.calendar_month_outlined,
      'unlock' => Icons.lock_open_outlined,
      'metadata' => Icons.manage_search_outlined,
      'risk' => Icons.report_problem_outlined,
      _ => Icons.all_inbox_outlined,
    };
  }
}
