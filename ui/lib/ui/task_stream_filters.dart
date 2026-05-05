/// Filters task stream projections by the same buckets used for stream axes.
library;

import '../domain/models.dart';
import 'task_stream_axes.dart';

/// TaskStreamFilterSelection stores active stream axis bucket filters.
class TaskStreamFilterSelection {
  /// Creates stream filter selections.
  const TaskStreamFilterSelection({
    this.filters = const <TaskStreamAxisDimension, String>{},
  });

  /// Selected bucket id by stream axis dimension.
  final Map<TaskStreamAxisDimension, String> filters;

  /// Whether any filter narrows the stream.
  bool get hasActiveFilters => activeCount > 0;

  /// Number of active filters.
  int get activeCount {
    return filters.values.where((value) => value.trim().isNotEmpty).length;
  }

  /// Returns the selected bucket id for a dimension.
  String valueFor(TaskStreamAxisDimension dimension) {
    return filters[dimension] ?? '';
  }

  /// Returns a copy with one dimension updated.
  TaskStreamFilterSelection withFilter(
    TaskStreamAxisDimension dimension,
    String value,
  ) {
    final next = Map<TaskStreamAxisDimension, String>.from(filters);
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      next.remove(dimension);
    } else {
      next[dimension] = trimmed;
    }
    return TaskStreamFilterSelection(filters: Map.unmodifiable(next));
  }

  /// Reports whether two filter selections carry the same values.
  @override
  bool operator ==(Object other) {
    if (other is! TaskStreamFilterSelection) {
      return false;
    }
    if (other.filters.length != filters.length) {
      return false;
    }
    return filters.entries.every((entry) {
      return other.filters[entry.key] == entry.value;
    });
  }

  /// Hashes the filter values.
  @override
  int get hashCode {
    final entries = filters.entries.toList()
      ..sort((left, right) => left.key.index.compareTo(right.key.index));
    return Object.hashAll(
      entries.map((entry) => Object.hash(entry.key, entry.value)),
    );
  }
}

/// TaskStreamFilterOption describes one selectable stream filter value.
class TaskStreamFilterOption {
  /// Creates a stream filter option with aggregate effort metadata.
  const TaskStreamFilterOption({
    required this.value,
    required this.label,
    required this.taskCount,
    required this.estimateMinutes,
  });

  /// Axis bucket id applied to the stream filter.
  final String value;

  /// Human-readable filter label.
  final String label;

  /// Number of cards covered by this option.
  final int taskCount;

  /// Total estimated minutes covered by this option.
  final int estimateMinutes;
}

/// TaskStreamFilterModel stores filter options and filtered stream output.
class TaskStreamFilterModel {
  /// Creates a stream filter result.
  const TaskStreamFilterModel({
    required this.filteredProjection,
    required this.optionsByDimension,
    required this.taskCount,
    required this.estimateMinutes,
  });

  /// Stream projection after active filters are applied.
  final TaskStreamProjection filteredProjection;

  /// Available bucket options keyed by stream axis dimension.
  final Map<TaskStreamAxisDimension, List<TaskStreamFilterOption>>
  optionsByDimension;

  /// Number of cards after filtering.
  final int taskCount;

  /// Total estimated minutes after filtering.
  final int estimateMinutes;

  /// Returns options for one dimension.
  List<TaskStreamFilterOption> optionsFor(TaskStreamAxisDimension dimension) {
    return optionsByDimension[dimension] ?? const <TaskStreamFilterOption>[];
  }
}

/// TaskStreamFilterProjector applies stream filters and derives options.
class TaskStreamFilterProjector {
  const TaskStreamFilterProjector._();

  /// Dimensions available in the stream filter dropdown.
  static const List<TaskStreamAxisDimension> dimensions =
      TaskStreamAxisProjector.filterDimensions;

  /// Builds filter options and a filtered projection.
  static TaskStreamFilterModel build(
    TaskStreamProjection projection, {
    required TaskStreamFilterSelection selection,
  }) {
    final entries = _TaskStreamFilterEntry.flatten(projection);
    final filteredEntries = entries.where((entry) {
      return _matchesSelection(entry, selection.filters);
    }).toList();
    return TaskStreamFilterModel(
      filteredProjection: _filteredProjection(projection, filteredEntries),
      optionsByDimension:
          <TaskStreamAxisDimension, List<TaskStreamFilterOption>>{
            for (final dimension in dimensions)
              dimension: _optionsForDimension(entries, selection, dimension),
          },
      taskCount: filteredEntries.length,
      estimateMinutes: _estimateMinutes(filteredEntries),
    );
  }

  /// Clears unavailable selections while preserving valid choices.
  static TaskStreamFilterSelection effectiveSelection(
    TaskStreamFilterSelection selection,
    TaskStreamFilterModel model,
  ) {
    var next = const TaskStreamFilterSelection();
    for (final entry in selection.filters.entries) {
      final selected = entry.value;
      final available = model.optionsFor(entry.key).any((option) {
        return option.value == selected;
      });
      if (available) {
        next = next.withFilter(entry.key, selected);
      }
    }
    return next;
  }

  /// Rebuilds the projection with only visible cards and links.
  static TaskStreamProjection _filteredProjection(
    TaskStreamProjection projection,
    List<_TaskStreamFilterEntry> entries,
  ) {
    final visibleCardsByTaskId = <String, TaskStreamCard>{
      for (final entry in entries) entry.card.taskId: entry.card,
    };
    return TaskStreamProjection(
      generatedAt: projection.generatedAt,
      lanes: <TaskStreamLane>[
        for (final lane in projection.lanes)
          TaskStreamLane(
            id: lane.id,
            title: lane.title,
            subtitle: lane.subtitle,
            cards: <TaskStreamCard>[
              for (final card in lane.cards)
                if (visibleCardsByTaskId.containsKey(card.taskId)) card,
            ],
          ),
      ],
      links: <TaskStreamLink>[
        for (final link in projection.links)
          if (visibleCardsByTaskId.containsKey(link.fromTaskId) &&
              visibleCardsByTaskId.containsKey(link.toTaskId))
            link,
      ],
    );
  }

  /// Builds options for one dimension while respecting other filters.
  static List<TaskStreamFilterOption> _optionsForDimension(
    List<_TaskStreamFilterEntry> entries,
    TaskStreamFilterSelection selection,
    TaskStreamAxisDimension dimension,
  ) {
    final scopedFilters = Map<TaskStreamAxisDimension, String>.from(
      selection.filters,
    )..remove(dimension);
    final grouped = <String, _TaskStreamFilterAggregate>{};
    for (final entry in entries) {
      if (!_matchesSelection(entry, scopedFilters)) {
        continue;
      }
      final bucket = entry.bucketFor(dimension);
      grouped
          .putIfAbsent(
            bucket.id,
            () => _TaskStreamFilterAggregate(
              value: bucket.id,
              label: bucket.title,
            ),
          )
          .add(entry.card);
    }
    final options = <TaskStreamFilterOption>[
      for (final aggregate in grouped.values) aggregate.option,
    ];
    if (TaskStreamAxisProjector.hasOrderedBuckets(dimension)) {
      options.sort((left, right) {
        return TaskStreamAxisProjector.bucketSortKey(
          left.value,
          dimension,
        ).compareTo(
          TaskStreamAxisProjector.bucketSortKey(right.value, dimension),
        );
      });
    } else {
      options.sort((left, right) => left.label.compareTo(right.label));
    }
    return List<TaskStreamFilterOption>.unmodifiable(options);
  }

  /// Returns total estimate minutes for entries.
  static int _estimateMinutes(List<_TaskStreamFilterEntry> entries) {
    return entries.fold<int>(
      0,
      (total, entry) => total + entry.card.estimateMinutes,
    );
  }
}

/// _TaskStreamFilterEntry stores a card with its source lane.
class _TaskStreamFilterEntry {
  /// Creates one stream filter entry.
  const _TaskStreamFilterEntry({required this.lane, required this.card});

  /// Source stream lane.
  final TaskStreamLane lane;

  /// Stream card being filtered.
  final TaskStreamCard card;

  /// Returns this card's bucket for a dimension.
  TaskStreamAxisBucket bucketFor(TaskStreamAxisDimension dimension) {
    return TaskStreamAxisProjector.bucketFor(
      lane: lane,
      card: card,
      dimension: dimension,
    );
  }

  /// Flattens stream lanes into filter entries.
  static List<_TaskStreamFilterEntry> flatten(TaskStreamProjection projection) {
    return <_TaskStreamFilterEntry>[
      for (final lane in projection.lanes)
        for (final card in lane.cards)
          _TaskStreamFilterEntry(lane: lane, card: card),
    ];
  }
}

/// _TaskStreamFilterAggregate accumulates option counts and effort.
class _TaskStreamFilterAggregate {
  /// Creates an aggregate around one bucket.
  _TaskStreamFilterAggregate({required this.value, required this.label});

  /// Bucket id.
  final String value;

  /// Display label.
  final String label;

  final Set<String> _taskIds = <String>{};
  int _estimateMinutes = 0;

  /// Adds one stream card to the aggregate.
  void add(TaskStreamCard card) {
    if (_taskIds.add(card.taskId)) {
      _estimateMinutes += card.estimateMinutes;
    }
  }

  /// Converts the aggregate into a selectable option.
  TaskStreamFilterOption get option {
    return TaskStreamFilterOption(
      value: value,
      label: label,
      taskCount: _taskIds.length,
      estimateMinutes: _estimateMinutes,
    );
  }
}

/// Returns whether an entry matches all selected filters.
bool _matchesSelection(
  _TaskStreamFilterEntry entry,
  Map<TaskStreamAxisDimension, String> filters,
) {
  for (final filter in filters.entries) {
    if (filter.value.trim().isEmpty) {
      continue;
    }
    if (entry.bucketFor(filter.key).id != filter.value) {
      return false;
    }
  }
  return true;
}
