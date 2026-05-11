/// Renders contact management surfaces for people-backed memory and work.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/theme.dart';
import '../domain/date_formatting.dart';
import '../domain/models.dart';
import 'panels/panels.dart';

part 'people_section_shell.dart';
part 'people_section_library.dart';
part 'people_section_inspector.dart';
part 'people_section_activity_tiles.dart';
part 'people_section_capture.dart';
part 'people_section_models.dart';
part 'people_section_aggregation.dart';
part 'people_section_filters.dart';
part 'people_section_helpers.dart';

const String _contactProfileModeId = 'profile';
const String _contactContextsModeId = 'contexts';
const String _contactActivityModeId = 'activity';
const String _contactSourcesModeId = 'sources';
const String _contactPageModeId = 'page';
