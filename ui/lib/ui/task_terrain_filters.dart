/// Builds task terrain filters from encoded task-fact overlay buckets.
library;

import '../domain/models.dart';
import 'task_stream_axes.dart';

/// TaskTerrainFilterOption stores one selectable terrain filter value.
class TaskTerrainFilterOption {
  /// Creates one terrain filter option.
  const TaskTerrainFilterOption({
    required this.id,
    required this.title,
    this.subtitle = '',
  });

  /// Stable option id.
  final String id;

  /// Display label.
  final String title;

  /// Optional secondary label.
  final String subtitle;
}

/// TaskTerrainFilterSelection stores the currently active terrain filters.
class TaskTerrainFilterSelection {
  /// Creates an immutable terrain filter selection.
  const TaskTerrainFilterSelection({
    this.areaFilters = const <TaskStreamAxisDimension, String>{},
  });

  /// Selected task-area bucket ids keyed by encoded fact dimension.
  final Map<TaskStreamAxisDimension, String> areaFilters;

  /// Returns true when at least one filter narrows the terrain.
  bool get hasActiveFilters {
    return areaFilters.values.any(_isNarrowingValue);
  }

  /// Returns the selected value for one area dimension.
  String valueForAreaDimension(TaskStreamAxisDimension dimension) {
    return areaFilters[dimension] ?? TaskTerrainFilterProjector.allOptionId;
  }

  /// Returns a copy with one area filter changed.
  TaskTerrainFilterSelection withAreaFilter(
    TaskStreamAxisDimension dimension,
    String value,
  ) {
    final next = Map<TaskStreamAxisDimension, String>.from(areaFilters);
    if (value == TaskTerrainFilterProjector.allOptionId) {
      next.remove(dimension);
    } else {
      next[dimension] = value;
    }
    return TaskTerrainFilterSelection(
      areaFilters: Map<TaskStreamAxisDimension, String>.unmodifiable(next),
    );
  }

  /// Returns true when a value represents a narrowed filter.
  static bool _isNarrowingValue(String value) {
    return value.isNotEmpty && value != TaskTerrainFilterProjector.allOptionId;
  }
}

/// TaskTerrainFilterModel stores available filters and per-task bucket lookups.
class TaskTerrainFilterModel {
  /// Creates the derived terrain filter model.
  const TaskTerrainFilterModel({
    required this.areaOptionsByDimension,
    required this.areaBucketsByTaskId,
  });

  /// Area options keyed by encoded task-fact dimension.
  final Map<TaskStreamAxisDimension, List<TaskTerrainFilterOption>>
  areaOptionsByDimension;

  /// Area bucket ids keyed by task id, then encoded task-fact dimension.
  final Map<String, Map<TaskStreamAxisDimension, String>> areaBucketsByTaskId;

  /// Returns a terrain projection narrowed by the selected filters.
  PriorityTerrainProjection apply(
    PriorityTerrainProjection projection,
    TaskTerrainFilterSelection selection,
  ) {
    if (!selection.hasActiveFilters) {
      return projection;
    }
    return PriorityTerrainProjection(
      generatedAt: projection.generatedAt,
      bands: projection.bands,
      points: <PriorityTerrainPoint>[
        for (final point in projection.points)
          if (_matches(point, selection)) point,
      ],
    );
  }

  /// Returns true when one point satisfies the current selection.
  bool _matches(
    PriorityTerrainPoint point,
    TaskTerrainFilterSelection selection,
  ) {
    final areaBuckets = areaBucketsByTaskId[point.taskId];
    for (final entry in selection.areaFilters.entries) {
      if (entry.value == TaskTerrainFilterProjector.allOptionId) {
        continue;
      }
      if (areaBuckets == null || areaBuckets[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}

/// TaskTerrainFilterProjector derives terrain filter choices from projections.
class TaskTerrainFilterProjector {
  const TaskTerrainFilterProjector._();

  /// Shared id for the non-filtering option.
  static const String allOptionId = '__all__';

  /// Encoded task-fact dimensions used as terrain area overlays.
  static const List<TaskStreamAxisDimension> overlayDimensions =
      TaskStreamAxisProjector.terrainOverlayDimensions;

  /// Builds a filter model from encoded area categories and terrain points.
  static TaskTerrainFilterModel build({
    required TaskStreamProjection streamProjection,
    required PriorityTerrainProjection terrainProjection,
  }) {
    final terrainTaskIds = <String>{
      for (final point in terrainProjection.points) point.taskId,
    };
    final areaBucketsByTaskId =
        <String, Map<TaskStreamAxisDimension, String>>{};
    final areaOptionsByDimension =
        <TaskStreamAxisDimension, List<TaskTerrainFilterOption>>{};
    for (final dimension in overlayDimensions) {
      final axisView = TaskStreamAxisProjector.project(
        streamProjection,
        columnAxis: TaskStreamAxisDimension.due,
        rowAxis: dimension,
      );
      final bucketsById = <String, TaskTerrainFilterOption>{};
      for (final entry in axisView.rowBucketsByTaskId.entries) {
        if (!terrainTaskIds.contains(entry.key)) {
          continue;
        }
        final bucket = entry.value;
        areaBucketsByTaskId.putIfAbsent(
          entry.key,
          () => <TaskStreamAxisDimension, String>{},
        )[dimension] = bucket.id;
        bucketsById[bucket.id] = TaskTerrainFilterOption(
          id: bucket.id,
          title: bucket.title,
          subtitle: bucket.subtitle,
        );
      }
      if (bucketsById.isNotEmpty) {
        final options = bucketsById.values.toList()
          ..sort((left, right) {
            if (!TaskStreamAxisProjector.hasOrderedBuckets(dimension)) {
              return left.title.compareTo(right.title);
            }
            final leftKey = TaskStreamAxisProjector.bucketSortKey(
              left.id,
              dimension,
            );
            final rightKey = TaskStreamAxisProjector.bucketSortKey(
              right.id,
              dimension,
            );
            if (leftKey != rightKey) {
              return leftKey.compareTo(rightKey);
            }
            return left.title.compareTo(right.title);
          });
        areaOptionsByDimension[dimension] = <TaskTerrainFilterOption>[
          _allOption(TaskStreamAxisProjector.dimensionLabel(dimension)),
          ...options,
        ];
      }
    }

    return TaskTerrainFilterModel(
      areaOptionsByDimension:
          Map<
            TaskStreamAxisDimension,
            List<TaskTerrainFilterOption>
          >.unmodifiable(areaOptionsByDimension),
      areaBucketsByTaskId:
          Map<String, Map<TaskStreamAxisDimension, String>>.unmodifiable(
            <String, Map<TaskStreamAxisDimension, String>>{
              for (final entry in areaBucketsByTaskId.entries)
                entry.key: Map<TaskStreamAxisDimension, String>.unmodifiable(
                  entry.value,
                ),
            },
          ),
    );
  }

  /// Returns whether a selector can narrow a mixed terrain set.
  static bool hasNarrowingOptions(List<TaskTerrainFilterOption> options) {
    return options.where((option) => option.id != allOptionId).length > 1;
  }

  /// Builds the all option for one selector.
  static TaskTerrainFilterOption _allOption(String label) {
    return TaskTerrainFilterOption(id: allOptionId, title: 'All $label');
  }
}
