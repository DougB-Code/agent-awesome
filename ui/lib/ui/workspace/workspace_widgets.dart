/// Provides reusable workspace, task-plan, and chat timeline widgets.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../theme.dart';
import '../../domain/models.dart';
import '../panels/panels.dart';
import '../shell/app_sections.dart';

part 'workspace_home.dart';
part 'workspace_hero.dart';
part 'workspace_diagram.dart';
part 'workspace_path_grid.dart';
part 'workspace_execution_plan.dart';
part 'workspace_chat_row.dart';
part 'workspace_shared_labels.dart';
part 'workspace_message_text.dart';
