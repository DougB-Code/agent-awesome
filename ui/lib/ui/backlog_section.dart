/// Implements the first-class backlog workspace panels.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/theme.dart';
import '../domain/date_formatting.dart';
import '../domain/models.dart';
import '../domain/screen_command.dart';
import '../domain/task_insight_explanations.dart';
import '../domain/task_insight_query.dart';
import 'panels/panels.dart';
import 'task_concept_views.dart';
import 'task_insight_presets.dart';
import 'string_list_values.dart';
import 'task_wbs_formatting.dart';

part 'backlog_section_shell.dart';
part 'backlog_section_command_panel.dart';
part 'backlog_section_editor.dart';
part 'backlog_section_details.dart';
part 'backlog_section_memory_link_scaffold.dart';
part 'backlog_section_queue_content.dart';
part 'backlog_section_queue_filters.dart';
part 'backlog_section_queue_tile.dart';
part 'backlog_section_review_panel.dart';
part 'backlog_section_shell_modes.dart';
part 'backlog_section_controls.dart';
part 'backlog_section_dialogs.dart';
part 'backlog_section_commitment_dialog.dart';
part 'backlog_section_create_dialog.dart';
part 'backlog_section_filter_helpers.dart';
part 'backlog_section_formatting_helpers.dart';
part 'backlog_section_graph_helpers.dart';
part 'backlog_section_metadata_dialog.dart';
part 'backlog_section_query_helpers.dart';
part 'backlog_section_relation_dialog.dart';
part 'backlog_section_screen_change_helpers.dart';
part 'backlog_section_suggestion_helpers.dart';
part 'backlog_section_task_graph_details.dart';
part 'backlog_section_task_graph_row.dart';
part 'backlog_section_task_insight_details.dart';
part 'backlog_section_task_memory_links.dart';
part 'backlog_section_task_metadata_details.dart';
part 'backlog_section_task_relation_tiles.dart';
part 'backlog_section_task_suggestion_tiles.dart';
part 'backlog_section_wbs_dialog.dart';

const List<String> _taskStatuses = <String>[
  'open',
  'waiting',
  'blocked',
  'done',
  'canceled',
];

const List<String> _activeTaskStatuses = <String>['open', 'waiting', 'blocked'];

const List<String> _taskPriorities = <String>[
  'urgent',
  'high',
  'normal',
  'low',
];

const List<String> _taskRelationTypes = <String>[
  'related_to',
  'depends_on',
  'blocks',
  'part_of',
  'enables',
];
