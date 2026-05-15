/// Defines display metadata for task terrain insight modes.
library;

import 'package:flutter/material.dart';

import '../domain/task_projection_adapters.dart';

/// TaskTerrainModeRegistry describes mode labels, questions, and icons.
class TaskTerrainModeRegistry {
  const TaskTerrainModeRegistry._();

  /// Ordered terrain modes.
  static const List<TaskTerrainInsightMode> modes = <TaskTerrainInsightMode>[
    TaskTerrainInsightMode.priorityFocus,
    TaskTerrainInsightMode.agentHandoff,
    TaskTerrainInsightMode.nextWeekHighValue,
    TaskTerrainInsightMode.unblockLeverage,
    TaskTerrainInsightMode.riskFocus,
  ];

  /// Returns a short label for one terrain mode.
  static String label(TaskTerrainInsightMode mode) {
    return switch (mode) {
      TaskTerrainInsightMode.priorityFocus => 'Priority focus',
      TaskTerrainInsightMode.agentHandoff => 'Agent handoff',
      TaskTerrainInsightMode.nextWeekHighValue => 'Next week value',
      TaskTerrainInsightMode.unblockLeverage => 'Unblock leverage',
      TaskTerrainInsightMode.riskFocus => 'Risk focus',
    };
  }

  /// Returns the user question answered by one terrain mode.
  static String question(TaskTerrainInsightMode mode) {
    return switch (mode) {
      TaskTerrainInsightMode.priorityFocus => 'What deserves attention?',
      TaskTerrainInsightMode.agentHandoff =>
        'What low-value must-do work can I safely hand off?',
      TaskTerrainInsightMode.nextWeekHighValue =>
        'What high-value work is coming up next week?',
      TaskTerrainInsightMode.unblockLeverage => 'What can I unblock quickly?',
      TaskTerrainInsightMode.riskFocus => 'What is most at risk?',
    };
  }

  /// Returns a compact mode icon.
  static IconData icon(TaskTerrainInsightMode mode) {
    return switch (mode) {
      TaskTerrainInsightMode.priorityFocus => Icons.center_focus_strong,
      TaskTerrainInsightMode.agentHandoff => Icons.smart_toy_outlined,
      TaskTerrainInsightMode.nextWeekHighValue => Icons.calendar_month_outlined,
      TaskTerrainInsightMode.unblockLeverage => Icons.lock_open_outlined,
      TaskTerrainInsightMode.riskFocus => Icons.report_problem_outlined,
    };
  }
}
