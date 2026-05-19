/// Renders the focused Today attention queue with explanation-first details.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../ui/theme.dart';
import '../../domain/date_formatting.dart';
import '../../domain/executive_summary.dart';
import '../../domain/models.dart';
import 'widgets/executive_summary_explanation_drawer.dart';
import 'widgets/today_card.dart';
import 'widgets/today_lanes.dart';

part 'attention_screen_shell.dart';
part 'attention_screen_header.dart';
part 'attention_screen_list.dart';
part 'attention_screen_details.dart';
part 'attention_screen_models.dart';
part 'attention_screen_helpers.dart';
