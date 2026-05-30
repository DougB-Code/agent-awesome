/// Provides the global command bar and quick-access menu for Agent Awesome.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../domain/config_files.dart';
import '../theme.dart';
import '../../domain/date_formatting.dart';
import '../../domain/runtime_profile.dart';
import '../shell/app_sections.dart';
import 'command_context.dart';
import 'quick_access_menu.dart';

part 'command_bar_shell.dart';
part 'command_bar_setup_status.dart';
part 'command_bar_input.dart';
part 'command_bar_chrome_buttons.dart';
