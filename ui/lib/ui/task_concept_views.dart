/// Renders task graph projections inside the shared task command panel.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import 'theme.dart';
import '../domain/models.dart';
import '../domain/task_graph_query.dart';
import '../domain/task_wbs_tree.dart';
import 'panels/panels.dart';
import 'task_constellation_layout.dart';
import 'task_filter_menu.dart';
import 'task_stream_axes.dart';
import 'task_stream_canvas.dart';
import 'task_stream_filters.dart';
import 'task_wbs_formatting.dart';

part 'task_concept_wbs.dart';
part 'task_concept_stream.dart';
part 'task_concept_constellation.dart';
part 'task_concept_shared.dart';

/// TaskConceptKind identifies one task projection workspace.
enum TaskConceptKind {
  /// Relationship-first spatial task map.
  constellation,

  /// Encoded task-fact stream.
  stream,

  /// Work-breakdown structure table.
  wbs,
}

/// TaskConceptProjectionPanel renders one projection without command-panel chrome.
class TaskConceptProjectionPanel extends StatelessWidget {
  /// Creates a task projection panel.
  const TaskConceptProjectionPanel({
    super.key,
    required this.controller,
    required this.kind,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Projection view to render.
  final TaskConceptKind kind;

  /// Builds the selected projection surface.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeSurfaceGradient,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: _buildView(),
      ),
    );
  }

  /// Builds the projection matching the current kind.
  Widget _buildView() {
    switch (kind) {
      case TaskConceptKind.constellation:
        return _TaskConstellationView(controller: controller);
      case TaskConceptKind.stream:
        return _TaskStreamView(controller: controller);
      case TaskConceptKind.wbs:
        return _TaskWbsView(controller: controller);
    }
  }
}
