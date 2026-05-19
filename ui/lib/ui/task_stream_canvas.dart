/// Renders the colorful task stream task-fact projection.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import 'theme.dart';
import '../domain/date_formatting.dart';
import '../domain/models.dart';
import 'task_stream_axes.dart';

part 'task_stream_canvas_shell.dart';
part 'task_stream_focus.dart';
part 'task_stream_canvas_layout.dart';
part 'task_stream_canvas_painter.dart';
part 'task_stream_canvas_labels.dart';
part 'task_stream_focus_controls.dart';
part 'task_stream_cards.dart';
part 'task_stream_canvas_helpers.dart';
