/// Defines reusable axis projections for the task stream canvas.
library;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/models.dart';

/// TaskStreamAxisDimension identifies a task attribute that can become an axis.
enum TaskStreamAxisDimension {
  /// Source stream time lane such as Now, Next, Later, or Upcoming.
  time,

  /// Due-date window computed from the encoded due timestamp.
  due,

  /// Scheduled-date window computed from the encoded scheduled timestamp.
  scheduled,

  /// Attention or work mode used by insight projections.
  attention,

  /// Backend task lifecycle status.
  status,

  /// Backend task priority.
  priority,

  /// Suggested execution context.
  context,

  /// Owning project when supplied by the task stream backend.
  project,

  /// Global cross-cutting view when supplied by the task stream backend.
  view,

  /// Responsible person when supplied by the task stream backend.
  person,

  /// Estimated duration bucket.
  effort,

  /// Spend bucket from explicit monetary task data.
  spend,

  /// Blocker pressure bucket derived from relation and risk signals.
  blockers,
}

/// TaskStreamAxisBucket stores one projected axis bucket.
class TaskStreamAxisBucket {
  /// Creates a stream axis bucket.
  const TaskStreamAxisBucket({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  /// Stable bucket id.
  final String id;

  /// Display title.
  final String title;

  /// Secondary display text.
  final String subtitle;

  /// Visual color for rows, icons, and related affordances.
  final Color color;

  /// Icon that represents the bucket in row labels.
  final IconData icon;
}

/// TaskStreamAxisView stores a rebucketed stream projection for rendering.
class TaskStreamAxisView {
  /// Creates an axis-projected task stream view.
  const TaskStreamAxisView({
    required this.columnAxis,
    required this.rowAxis,
    required this.lanes,
    required this.rowBucketsByTaskId,
  });

  /// Dimension used for top timeline columns.
  final TaskStreamAxisDimension columnAxis;

  /// Dimension used for left stream rows.
  final TaskStreamAxisDimension rowAxis;

  /// Rebucketed task lanes for the column axis.
  final List<TaskStreamLane> lanes;

  /// Row bucket lookup keyed by task id.
  final Map<String, TaskStreamAxisBucket> rowBucketsByTaskId;
}

/// TaskStreamAxisProjector builds axis-specific stream views from one graph.
class TaskStreamAxisProjector {
  const TaskStreamAxisProjector._();

  /// Encoded task fact dimensions shown in the Stream view.
  static const List<TaskStreamAxisDimension> factDimensions =
      <TaskStreamAxisDimension>[
        TaskStreamAxisDimension.due,
        TaskStreamAxisDimension.scheduled,
        TaskStreamAxisDimension.priority,
        TaskStreamAxisDimension.context,
        TaskStreamAxisDimension.project,
        TaskStreamAxisDimension.view,
        TaskStreamAxisDimension.person,
        TaskStreamAxisDimension.effort,
        TaskStreamAxisDimension.spend,
      ];

  /// Encoded area dimensions used to overlay task facts on terrain projections.
  static const List<TaskStreamAxisDimension> terrainOverlayDimensions =
      <TaskStreamAxisDimension>[
        TaskStreamAxisDimension.project,
        TaskStreamAxisDimension.person,
        TaskStreamAxisDimension.view,
        TaskStreamAxisDimension.context,
        TaskStreamAxisDimension.priority,
        TaskStreamAxisDimension.due,
        TaskStreamAxisDimension.scheduled,
        TaskStreamAxisDimension.effort,
        TaskStreamAxisDimension.spend,
      ];

  /// Dimensions that are useful as top-level columns.
  static const List<TaskStreamAxisDimension> columnDimensions = factDimensions;

  /// Dimensions that are useful as left-side rows.
  static const List<TaskStreamAxisDimension> rowDimensions = factDimensions;

  /// Dimensions that are useful in the Stream filter menu.
  static const List<TaskStreamAxisDimension> filterDimensions = factDimensions;

  /// Returns whether a dimension is encoded task data in the Stream UI.
  static bool isFactDimension(TaskStreamAxisDimension dimension) {
    return factDimensions.contains(dimension);
  }

  /// Returns whether a dimension is intended as a Terrain area overlay.
  static bool isTerrainOverlayDimension(TaskStreamAxisDimension dimension) {
    return terrainOverlayDimensions.contains(dimension);
  }

  /// Returns a display label for an axis dimension.
  static String dimensionLabel(TaskStreamAxisDimension dimension) {
    switch (dimension) {
      case TaskStreamAxisDimension.time:
        return 'Time';
      case TaskStreamAxisDimension.due:
        return 'Due';
      case TaskStreamAxisDimension.scheduled:
        return 'Scheduled';
      case TaskStreamAxisDimension.attention:
        return 'Attention';
      case TaskStreamAxisDimension.status:
        return 'Status';
      case TaskStreamAxisDimension.priority:
        return 'Priority';
      case TaskStreamAxisDimension.context:
        return 'Context';
      case TaskStreamAxisDimension.project:
        return 'Project';
      case TaskStreamAxisDimension.view:
        return 'View';
      case TaskStreamAxisDimension.person:
        return 'Person';
      case TaskStreamAxisDimension.effort:
        return 'Effort';
      case TaskStreamAxisDimension.spend:
        return 'Spend';
      case TaskStreamAxisDimension.blockers:
        return 'Blockers';
    }
  }

  /// Returns a stable sort key for a bucket id on a dimension.
  static int bucketSortKey(String id, TaskStreamAxisDimension dimension) {
    return _bucketOrder(id, dimension);
  }

  /// Returns whether the dimension has a meaningful fixed bucket order.
  static bool hasOrderedBuckets(TaskStreamAxisDimension dimension) {
    return switch (dimension) {
      TaskStreamAxisDimension.due ||
      TaskStreamAxisDimension.scheduled ||
      TaskStreamAxisDimension.attention ||
      TaskStreamAxisDimension.status ||
      TaskStreamAxisDimension.priority ||
      TaskStreamAxisDimension.effort ||
      TaskStreamAxisDimension.spend ||
      TaskStreamAxisDimension.blockers => true,
      TaskStreamAxisDimension.time ||
      TaskStreamAxisDimension.context ||
      TaskStreamAxisDimension.project ||
      TaskStreamAxisDimension.view ||
      TaskStreamAxisDimension.person => false,
    };
  }

  /// Returns the icon used for a selectable axis dimension.
  static IconData dimensionIcon(TaskStreamAxisDimension dimension) {
    return switch (dimension) {
      TaskStreamAxisDimension.time => Icons.calendar_today_outlined,
      TaskStreamAxisDimension.due => Icons.event_available_outlined,
      TaskStreamAxisDimension.scheduled => Icons.event_note_outlined,
      TaskStreamAxisDimension.attention => Icons.auto_awesome_outlined,
      TaskStreamAxisDimension.status => Icons.task_alt_outlined,
      TaskStreamAxisDimension.priority => Icons.flag_outlined,
      TaskStreamAxisDimension.context => Icons.workspaces_outline,
      TaskStreamAxisDimension.project => Icons.folder_outlined,
      TaskStreamAxisDimension.view => Icons.layers_outlined,
      TaskStreamAxisDimension.person => Icons.person_outline,
      TaskStreamAxisDimension.effort => Icons.timer_outlined,
      TaskStreamAxisDimension.spend => Icons.price_change_outlined,
      TaskStreamAxisDimension.blockers => Icons.lock_outline,
    };
  }

  /// Returns the bucket assigned to one card for an axis dimension.
  static TaskStreamAxisBucket bucketFor({
    required TaskStreamLane lane,
    required TaskStreamCard card,
    required TaskStreamAxisDimension dimension,
  }) {
    return _bucketFor(_TaskStreamAxisEntry(lane: lane, card: card), dimension);
  }

  /// Projects backend stream lanes into the requested column and row axes.
  static TaskStreamAxisView project(
    TaskStreamProjection projection, {
    required TaskStreamAxisDimension columnAxis,
    required TaskStreamAxisDimension rowAxis,
  }) {
    final entries = _TaskStreamAxisEntry.flatten(projection.lanes);
    final rowBucketsByTaskId = <String, TaskStreamAxisBucket>{
      for (final entry in entries)
        entry.card.taskId: _bucketFor(entry, rowAxis),
    };
    final lanes = columnAxis == TaskStreamAxisDimension.time
        ? projection.lanes
        : _projectLanes(entries, columnAxis);
    return TaskStreamAxisView(
      columnAxis: columnAxis,
      rowAxis: rowAxis,
      lanes: lanes,
      rowBucketsByTaskId: rowBucketsByTaskId,
    );
  }

  /// Returns the default task-fact bucket for a card.
  static TaskStreamAxisBucket fallbackRowBucket(TaskStreamCard card) {
    return _dynamicBucket(
      value: card.project,
      fallback: 'No project',
      subtitle: card.context,
      icon: Icons.folder_outlined,
      paletteIndex: 1,
    );
  }

  /// Returns the bucket for one task stream entry on a dimension.
  static TaskStreamAxisBucket _bucketFor(
    _TaskStreamAxisEntry entry,
    TaskStreamAxisDimension dimension,
  ) {
    final card = entry.card;
    switch (dimension) {
      case TaskStreamAxisDimension.time:
        return TaskStreamAxisBucket(
          id: entry.lane.id,
          title: entry.lane.title,
          subtitle: entry.lane.subtitle,
          color: _paletteColor(entry.lane.id, 0),
          icon: Icons.calendar_today_outlined,
        );
      case TaskStreamAxisDimension.due:
        return _dateWindowBucket(
          value: card.dueAt,
          emptyId: 'no-due-date',
          emptyTitle: 'No due date',
          subtitleFallback: 'Due',
          icon: Icons.event_available_outlined,
        );
      case TaskStreamAxisDimension.scheduled:
        return _dateWindowBucket(
          value: card.scheduledAt,
          emptyId: 'not-scheduled',
          emptyTitle: 'Not scheduled',
          subtitleFallback: 'Schedule',
          icon: Icons.event_note_outlined,
        );
      case TaskStreamAxisDimension.attention:
        return _attentionBucket(card);
      case TaskStreamAxisDimension.status:
        return _statusBucket(card.status);
      case TaskStreamAxisDimension.priority:
        return _priorityBucket(card.priority);
      case TaskStreamAxisDimension.context:
        return _dynamicBucket(
          value: card.context,
          fallback: 'No context',
          subtitle: card.status,
          icon: Icons.workspaces_outline,
          paletteIndex: 0,
        );
      case TaskStreamAxisDimension.project:
        return _dynamicBucket(
          value: card.project,
          fallback: 'No project',
          subtitle: card.context,
          icon: Icons.folder_outlined,
          paletteIndex: 1,
        );
      case TaskStreamAxisDimension.view:
        return _dynamicBucket(
          value: card.domain,
          fallback: 'No view',
          subtitle: card.context,
          icon: Icons.layers_outlined,
          paletteIndex: 2,
        );
      case TaskStreamAxisDimension.person:
        return _dynamicBucket(
          value: card.owner,
          fallback: 'Unassigned',
          subtitle: card.context,
          icon: Icons.person_outline,
          paletteIndex: 3,
        );
      case TaskStreamAxisDimension.effort:
        return _effortBucket(card.estimateMinutes);
      case TaskStreamAxisDimension.spend:
        return _spendBucket(card);
      case TaskStreamAxisDimension.blockers:
        return _blockersBucket(card);
    }
  }

  /// Rebuilds lanes by grouping cards on a non-time column dimension.
  static List<TaskStreamLane> _projectLanes(
    List<_TaskStreamAxisEntry> entries,
    TaskStreamAxisDimension dimension,
  ) {
    final grouped = <String, _ProjectedLane>{};
    for (final entry in entries) {
      final bucket = _bucketFor(entry, dimension);
      grouped.putIfAbsent(
        bucket.id,
        () => _ProjectedLane(bucket: bucket, cards: <TaskStreamCard>[]),
      );
      grouped[bucket.id]!.cards.add(entry.card);
    }
    final ordered = grouped.values.toList();
    if (hasOrderedBuckets(dimension)) {
      ordered.sort((left, right) {
        return _bucketOrder(
          left.bucket.id,
          dimension,
        ).compareTo(_bucketOrder(right.bucket.id, dimension));
      });
    }
    return <TaskStreamLane>[
      for (final lane in ordered)
        TaskStreamLane(
          id: lane.bucket.id,
          title: lane.bucket.title,
          subtitle: lane.bucket.subtitle,
          cards: lane.cards,
        ),
    ];
  }

  /// Returns a stable sort key for known ordered dimensions.
  static int _bucketOrder(String id, TaskStreamAxisDimension dimension) {
    final order = switch (dimension) {
      TaskStreamAxisDimension.attention => const <String>[
        'focus',
        'deep-focus',
        'deep-work',
        'admin',
        'errands',
        'waiting',
        'personal',
      ],
      TaskStreamAxisDimension.status => const <String>[
        'open',
        'waiting',
        'blocked',
        'done',
        'canceled',
        'unknown-status',
      ],
      TaskStreamAxisDimension.priority => const <String>[
        'urgent',
        'high',
        'normal',
        'low',
        'unknown-priority',
      ],
      TaskStreamAxisDimension.effort => const <String>[
        'quick',
        'short',
        'medium',
        'deep',
        'unestimated',
      ],
      TaskStreamAxisDimension.spend => const <String>[
        'low-spend',
        'medium-spend',
        'high-spend',
        'no-spend-data',
      ],
      TaskStreamAxisDimension.due => const <String>[
        'overdue',
        'today',
        'tomorrow',
        'this-week',
        'next-week',
        'later',
        'no-due-date',
      ],
      TaskStreamAxisDimension.scheduled => const <String>[
        'overdue',
        'today',
        'tomorrow',
        'this-week',
        'next-week',
        'later',
        'not-scheduled',
      ],
      TaskStreamAxisDimension.blockers => const <String>[
        'clear',
        'watch',
        'blocked',
        'critical',
      ],
      _ => const <String>[],
    };
    final index = order.indexOf(id);
    return index < 0 ? order.length + id.hashCode.abs() : index;
  }
}

/// Converts backend identifiers into readable title-case labels.
String taskStreamDisplayLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

/// _TaskStreamAxisEntry keeps a card paired with its source time lane.
class _TaskStreamAxisEntry {
  const _TaskStreamAxisEntry({required this.lane, required this.card});

  /// Source time lane.
  final TaskStreamLane lane;

  /// Projected task card.
  final TaskStreamCard card;

  /// Flattens source lanes into card entries.
  static List<_TaskStreamAxisEntry> flatten(List<TaskStreamLane> lanes) {
    return <_TaskStreamAxisEntry>[
      for (final lane in lanes)
        for (final card in lane.cards)
          _TaskStreamAxisEntry(lane: lane, card: card),
    ];
  }
}

/// _ProjectedLane stores mutable lane assembly state.
class _ProjectedLane {
  _ProjectedLane({required this.bucket, required this.cards});

  /// Axis bucket represented by the lane.
  final TaskStreamAxisBucket bucket;

  /// Cards assigned to the lane.
  final List<TaskStreamCard> cards;
}

/// Returns the inferred attention bucket for a task card.
TaskStreamAxisBucket _attentionBucket(TaskStreamCard card) {
  final label = _attentionLabel(card);
  final normalized = label.toLowerCase();
  if (normalized.contains('focus')) {
    return TaskStreamAxisBucket(
      id: _slug(label, fallback: 'focus'),
      title: label,
      subtitle: 'Focus time',
      color: const Color(0xff5f94c9),
      icon: Icons.rocket_launch_outlined,
    );
  }
  if (normalized.contains('deep')) {
    return const TaskStreamAxisBucket(
      id: 'deep-work',
      title: 'Deep Work',
      subtitle: 'Focus time',
      color: Color(0xff5f94c9),
      icon: Icons.rocket_launch_outlined,
    );
  }
  if (normalized.contains('admin')) {
    return const TaskStreamAxisBucket(
      id: 'admin',
      title: 'Admin',
      subtitle: 'Operations',
      color: Color(0xff6f9b62),
      icon: Icons.settings_suggest_outlined,
    );
  }
  if (normalized.contains('errand') || normalized.contains('shopping')) {
    return const TaskStreamAxisBucket(
      id: 'errands',
      title: 'Errands',
      subtitle: 'Out & about',
      color: Color(0xffd7a246),
      icon: Icons.local_mall_outlined,
    );
  }
  if (normalized.contains('waiting') || normalized.contains('blocked')) {
    return const TaskStreamAxisBucket(
      id: 'waiting',
      title: 'Waiting',
      subtitle: 'External',
      color: Color(0xff9177c0),
      icon: Icons.hourglass_empty_outlined,
    );
  }
  if (normalized.contains('personal')) {
    return const TaskStreamAxisBucket(
      id: 'personal',
      title: 'Personal',
      subtitle: 'Life & growth',
      color: Color(0xffd8798c),
      icon: Icons.navigation_outlined,
    );
  }
  return _dynamicBucket(
    value: label,
    fallback: 'Personal',
    subtitle: card.status,
    icon: Icons.auto_awesome_outlined,
    paletteIndex: 4,
  );
}

/// Returns the attention label inferred from card metadata.
String _attentionLabel(TaskStreamCard card) {
  if (card.flowLane.trim().isNotEmpty) {
    return taskStreamDisplayLabel(card.flowLane);
  }
  if (card.context.trim().isNotEmpty) {
    return taskStreamDisplayLabel(card.context);
  }
  final normalizedStatus = _normalizedStatusId(card.status);
  if (normalizedStatus == 'waiting' || normalizedStatus == 'blocked') {
    return taskStreamDisplayLabel(normalizedStatus);
  }
  return card.readyNow ? 'Deep Work' : 'Personal';
}

/// Returns a status bucket for a backend lifecycle value.
TaskStreamAxisBucket _statusBucket(String status) {
  final normalized = _normalizedStatusId(status);
  return switch (normalized) {
    'open' => const TaskStreamAxisBucket(
      id: 'open',
      title: 'Open',
      subtitle: 'Active work',
      color: AgentAwesomeColors.green,
      icon: Icons.task_alt_outlined,
    ),
    'waiting' => const TaskStreamAxisBucket(
      id: 'waiting',
      title: 'Waiting',
      subtitle: 'External',
      color: Color(0xff9177c0),
      icon: Icons.hourglass_empty_outlined,
    ),
    'blocked' => const TaskStreamAxisBucket(
      id: 'blocked',
      title: 'Blocked',
      subtitle: 'Needs unblock',
      color: AgentAwesomeColors.coral,
      icon: Icons.lock_outline,
    ),
    'done' => const TaskStreamAxisBucket(
      id: 'done',
      title: 'Done',
      subtitle: 'Completed',
      color: Color(0xff6f9b62),
      icon: Icons.check_circle_outline,
    ),
    'canceled' => const TaskStreamAxisBucket(
      id: 'canceled',
      title: 'Canceled',
      subtitle: 'Inactive',
      color: AgentAwesomeColors.muted,
      icon: Icons.cancel_outlined,
    ),
    _ => const TaskStreamAxisBucket(
      id: 'unknown-status',
      title: 'Other status',
      subtitle: 'Unmapped lifecycle',
      color: AgentAwesomeColors.muted,
      icon: Icons.radio_button_unchecked,
    ),
  };
}

/// Normalizes backend lifecycle status labels into known status bucket ids.
String _normalizedStatusId(String status) {
  final normalized = _slug(status, fallback: 'unknown-status');
  return switch (normalized) {
    'open' ||
    'active' ||
    'todo' ||
    'to-do' ||
    'not-started' ||
    'in-progress' ||
    'started' => 'open',
    'waiting' || 'waiting-on' || 'snoozed' || 'deferred' => 'waiting',
    'blocked' || 'stuck' => 'blocked',
    'done' || 'complete' || 'completed' => 'done',
    'canceled' || 'cancelled' => 'canceled',
    _ => 'unknown-status',
  };
}

/// Returns a priority bucket for a backend priority value.
TaskStreamAxisBucket _priorityBucket(String priority) {
  final normalized = _slug(priority, fallback: 'unknown-priority');
  return switch (normalized) {
    'urgent' => const TaskStreamAxisBucket(
      id: 'urgent',
      title: 'Urgent',
      subtitle: 'Needs attention',
      color: AgentAwesomeColors.coral,
      icon: Icons.priority_high,
    ),
    'high' => const TaskStreamAxisBucket(
      id: 'high',
      title: 'High',
      subtitle: 'Important',
      color: Color(0xffd7a246),
      icon: Icons.keyboard_double_arrow_up,
    ),
    'normal' => const TaskStreamAxisBucket(
      id: 'normal',
      title: 'Normal',
      subtitle: 'Standard',
      color: AgentAwesomeColors.green,
      icon: Icons.remove,
    ),
    'low' => const TaskStreamAxisBucket(
      id: 'low',
      title: 'Low',
      subtitle: 'Flexible',
      color: AgentAwesomeColors.muted,
      icon: Icons.keyboard_arrow_down,
    ),
    _ => TaskStreamAxisBucket(
      id: normalized,
      title: taskStreamDisplayLabel(
        priority.isEmpty ? 'Unknown priority' : priority,
      ),
      subtitle: 'Priority',
      color: _paletteColor(normalized, 1),
      icon: Icons.flag_outlined,
    ),
  };
}

/// Returns a due or scheduled date-window bucket.
TaskStreamAxisBucket _dateWindowBucket({
  required DateTime? value,
  required String emptyId,
  required String emptyTitle,
  required String subtitleFallback,
  required IconData icon,
}) {
  if (value == null) {
    return TaskStreamAxisBucket(
      id: emptyId,
      title: emptyTitle,
      subtitle: subtitleFallback,
      color: AgentAwesomeColors.muted,
      icon: icon,
    );
  }
  final now = DateTime.now();
  final day = _startOfDay(value.toLocal());
  final today = _startOfDay(now.toLocal());
  final days = day.difference(today).inDays;
  if (days < 0) {
    return TaskStreamAxisBucket(
      id: 'overdue',
      title: 'Overdue',
      subtitle: _dateSubtitle(value),
      color: AgentAwesomeColors.coral,
      icon: icon,
    );
  }
  if (days == 0) {
    return TaskStreamAxisBucket(
      id: 'today',
      title: 'Today',
      subtitle: _dateSubtitle(value),
      color: Color(0xffd7a246),
      icon: icon,
    );
  }
  if (days == 1) {
    return TaskStreamAxisBucket(
      id: 'tomorrow',
      title: 'Tomorrow',
      subtitle: _dateSubtitle(value),
      color: Color(0xff7a9a91),
      icon: icon,
    );
  }
  if (days <= 7) {
    return TaskStreamAxisBucket(
      id: 'this-week',
      title: 'This week',
      subtitle: _dateSubtitle(value),
      color: Color(0xff6f9b62),
      icon: icon,
    );
  }
  if (days <= 14) {
    return TaskStreamAxisBucket(
      id: 'next-week',
      title: 'Next week',
      subtitle: _dateSubtitle(value),
      color: Color(0xff5f94c9),
      icon: icon,
    );
  }
  return TaskStreamAxisBucket(
    id: 'later',
    title: 'Later',
    subtitle: _dateSubtitle(value),
    color: Color(0xff9177c0),
    icon: icon,
  );
}

/// Returns the local day start for stable date bucket comparison.
DateTime _startOfDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

/// Formats a compact local date subtitle without external dependencies.
String _dateSubtitle(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)}';
}

/// Formats one two-digit date component.
String _twoDigits(int value) {
  return value.toString().padLeft(2, '0');
}

/// Returns a duration bucket for an estimate in minutes.
TaskStreamAxisBucket _effortBucket(int minutes) {
  if (minutes <= 0) {
    return const TaskStreamAxisBucket(
      id: 'unestimated',
      title: 'Unestimated',
      subtitle: 'No estimate',
      color: AgentAwesomeColors.muted,
      icon: Icons.help_outline,
    );
  }
  if (minutes <= 15) {
    return const TaskStreamAxisBucket(
      id: 'quick',
      title: 'Quick',
      subtitle: '<= 15m',
      color: Color(0xff6f9b62),
      icon: Icons.bolt_outlined,
    );
  }
  if (minutes <= 30) {
    return const TaskStreamAxisBucket(
      id: 'short',
      title: 'Short',
      subtitle: '<= 30m',
      color: Color(0xff7a9a91),
      icon: Icons.timer_outlined,
    );
  }
  if (minutes <= 60) {
    return const TaskStreamAxisBucket(
      id: 'medium',
      title: 'Medium',
      subtitle: '<= 60m',
      color: Color(0xffd7a246),
      icon: Icons.schedule_outlined,
    );
  }
  return const TaskStreamAxisBucket(
    id: 'deep',
    title: 'Deep',
    subtitle: '> 60m',
    color: Color(0xff5f94c9),
    icon: Icons.hourglass_top_outlined,
  );
}

/// Returns a spend bucket from explicit spend data.
TaskStreamAxisBucket _spendBucket(TaskStreamCard card) {
  final score = card.spendScore;
  final subtitle = card.spendLabel.trim().isEmpty ? 'Spend' : card.spendLabel;
  if (score <= 0) {
    if (card.spendLabel.trim().isNotEmpty) {
      return _dynamicBucket(
        value: card.spendLabel,
        fallback: 'Spend',
        subtitle: 'Spend',
        icon: Icons.attach_money,
        paletteIndex: 5,
      );
    }
    return const TaskStreamAxisBucket(
      id: 'no-spend-data',
      title: 'No spend data',
      subtitle: 'Not scored',
      color: AgentAwesomeColors.muted,
      icon: Icons.money_off_csred_outlined,
    );
  }
  if (score < 0.34) {
    return TaskStreamAxisBucket(
      id: 'low-spend',
      title: 'Low spend',
      subtitle: subtitle,
      color: const Color(0xff6f9b62),
      icon: Icons.savings_outlined,
    );
  }
  if (score < 0.67) {
    return TaskStreamAxisBucket(
      id: 'medium-spend',
      title: 'Medium spend',
      subtitle: subtitle,
      color: const Color(0xffd7a246),
      icon: Icons.paid_outlined,
    );
  }
  return TaskStreamAxisBucket(
    id: 'high-spend',
    title: 'High spend',
    subtitle: subtitle,
    color: AgentAwesomeColors.coral,
    icon: Icons.price_change_outlined,
  );
}

/// Returns a blocker bucket from blocker pressure.
TaskStreamAxisBucket _blockersBucket(TaskStreamCard card) {
  if (_normalizedStatusId(card.status) == 'blocked') {
    return const TaskStreamAxisBucket(
      id: 'critical',
      title: 'Critical',
      subtitle: 'Blocked',
      color: AgentAwesomeColors.coral,
      icon: Icons.report_problem_outlined,
    );
  }
  if (card.bottleneckScore >= 0.67) {
    return const TaskStreamAxisBucket(
      id: 'blocked',
      title: 'High friction',
      subtitle: 'Likely blocker',
      color: Color(0xff9177c0),
      icon: Icons.warning_amber_outlined,
    );
  }
  if (card.bottleneckScore >= 0.34 ||
      _normalizedStatusId(card.status) == 'waiting') {
    return const TaskStreamAxisBucket(
      id: 'watch',
      title: 'Watch',
      subtitle: 'Monitor',
      color: Color(0xffd7a246),
      icon: Icons.visibility_outlined,
    );
  }
  return const TaskStreamAxisBucket(
    id: 'clear',
    title: 'Clear',
    subtitle: 'No blocker',
    color: Color(0xff6f9b62),
    icon: Icons.check_circle_outline,
  );
}

/// Returns a bucket for user-supplied string metadata.
TaskStreamAxisBucket _dynamicBucket({
  required String value,
  required String fallback,
  required String subtitle,
  required IconData icon,
  required int paletteIndex,
}) {
  final title = taskStreamDisplayLabel(value.isEmpty ? fallback : value);
  final id = _slug(title, fallback: _slug(fallback, fallback: 'unknown'));
  return TaskStreamAxisBucket(
    id: id,
    title: title,
    subtitle: subtitle.isEmpty ? '' : taskStreamDisplayLabel(subtitle),
    color: _paletteColor(id, paletteIndex),
    icon: icon,
  );
}

/// Returns a stable slug for bucket identifiers.
String _slug(String value, {required String fallback}) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return normalized.isEmpty ? fallback : normalized;
}

/// Returns a stable color for dynamic bucket values.
Color _paletteColor(String value, int offset) {
  const palette = <Color>[
    Color(0xff5f94c9),
    Color(0xff6f9b62),
    Color(0xffd7a246),
    Color(0xff9177c0),
    Color(0xffd8798c),
    Color(0xff7a9a91),
    Color(0xffc1844f),
  ];
  var hash = offset;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}
