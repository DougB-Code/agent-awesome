/// Defines reusable axis projections for the task stream canvas.
library;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/date_formatting.dart';
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

  /// Owning project when supplied by the task stream backend.
  project,

  /// Responsible person when supplied by the task stream backend.
  person,

  /// Estimated duration bucket.
  estimate,

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
        TaskStreamAxisDimension.project,
        TaskStreamAxisDimension.person,
        TaskStreamAxisDimension.estimate,
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
      case TaskStreamAxisDimension.project:
        return 'Project';
      case TaskStreamAxisDimension.person:
        return 'Person';
      case TaskStreamAxisDimension.estimate:
        return 'Estimate';
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
      TaskStreamAxisDimension.estimate ||
      TaskStreamAxisDimension.spend ||
      TaskStreamAxisDimension.blockers => true,
      TaskStreamAxisDimension.time ||
      TaskStreamAxisDimension.project ||
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
      TaskStreamAxisDimension.project => Icons.folder_outlined,
      TaskStreamAxisDimension.person => Icons.person_outline,
      TaskStreamAxisDimension.estimate => Icons.timer_outlined,
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
      subtitle: card.status,
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
      case TaskStreamAxisDimension.project:
        return _dynamicBucket(
          value: card.project,
          fallback: 'No project',
          subtitle: card.status,
          icon: Icons.folder_outlined,
          paletteIndex: 1,
        );
      case TaskStreamAxisDimension.person:
        return _dynamicBucket(
          value: card.owner,
          fallback: 'Unassigned',
          subtitle: card.status,
          icon: Icons.person_outline,
          paletteIndex: 3,
        );
      case TaskStreamAxisDimension.estimate:
        return _estimateBucket(card.estimateMinutes);
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
        'blocked',
        'waiting',
        'urgent',
        'due-soon',
        'ready',
        'general',
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
      TaskStreamAxisDimension.estimate => const <String>[
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
  final normalizedStatus = _normalizedStatusId(card.status);
  if (normalizedStatus == 'blocked') {
    return const TaskStreamAxisBucket(
      id: 'blocked',
      title: 'Blocked',
      subtitle: 'Needs unblock',
      color: AgentAwesomeColors.coral,
      icon: Icons.lock_outline,
    );
  }
  if (normalizedStatus == 'waiting') {
    return const TaskStreamAxisBucket(
      id: 'waiting',
      title: 'Waiting',
      subtitle: 'External',
      color: Color(0xff9177c0),
      icon: Icons.hourglass_empty_outlined,
    );
  }
  if (card.priority == 'urgent') {
    return const TaskStreamAxisBucket(
      id: 'urgent',
      title: 'Urgent',
      subtitle: 'Priority',
      color: AgentAwesomeColors.coral,
      icon: Icons.priority_high,
    );
  }
  if (_dueSoon(card.dueAt)) {
    return const TaskStreamAxisBucket(
      id: 'due-soon',
      title: 'Due soon',
      subtitle: 'Due date',
      color: Color(0xffd7a246),
      icon: Icons.event_available_outlined,
    );
  }
  if (card.readyNow) {
    return const TaskStreamAxisBucket(
      id: 'ready',
      title: 'Ready',
      subtitle: 'Open now',
      color: AgentAwesomeColors.green,
      icon: Icons.play_arrow_outlined,
    );
  }
  return const TaskStreamAxisBucket(
    id: 'general',
    title: 'General',
    subtitle: 'No immediate signal',
    color: AgentAwesomeColors.muted,
    icon: Icons.auto_awesome_outlined,
  );
}

/// Returns whether a due timestamp is overdue or within the next day.
bool _dueSoon(DateTime? dueAt) {
  if (dueAt == null) {
    return false;
  }
  final now = DateTime.now();
  final dueDay = _startOfDay(dueAt.toLocal());
  final today = _startOfDay(now.toLocal());
  return dueDay.difference(today).inDays <= 1;
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
      subtitle: formatLocalDate(value),
      color: AgentAwesomeColors.coral,
      icon: icon,
    );
  }
  if (days == 0) {
    return TaskStreamAxisBucket(
      id: 'today',
      title: 'Today',
      subtitle: formatLocalDate(value),
      color: Color(0xffd7a246),
      icon: icon,
    );
  }
  if (days == 1) {
    return TaskStreamAxisBucket(
      id: 'tomorrow',
      title: 'Tomorrow',
      subtitle: formatLocalDate(value),
      color: Color(0xff7a9a91),
      icon: icon,
    );
  }
  if (days <= 7) {
    return TaskStreamAxisBucket(
      id: 'this-week',
      title: 'This week',
      subtitle: formatLocalDate(value),
      color: Color(0xff6f9b62),
      icon: icon,
    );
  }
  if (days <= 14) {
    return TaskStreamAxisBucket(
      id: 'next-week',
      title: 'Next week',
      subtitle: formatLocalDate(value),
      color: Color(0xff5f94c9),
      icon: icon,
    );
  }
  return TaskStreamAxisBucket(
    id: 'later',
    title: 'Later',
    subtitle: formatLocalDate(value),
    color: Color(0xff9177c0),
    icon: icon,
  );
}

/// Returns the local day start for stable date bucket comparison.
DateTime _startOfDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

/// Returns a duration bucket for an estimate in minutes.
TaskStreamAxisBucket _estimateBucket(int minutes) {
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
