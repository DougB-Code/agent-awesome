/// Implements the settings workspace panels for Agent Awesome configuration.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/app_settings.dart';
import '../../app/local_services.dart';
import '../../app/theme.dart';
import '../../domain/config_files.dart';
import '../../domain/credentials.dart';
import '../../domain/model_config.dart';
import '../../domain/runtime_profile.dart';
import '../../domain/tool_config.dart';
import '../panels/panels.dart';
import 'settings_form.dart';
import 'settings_logic.dart';

part 'settings_panel_shell.dart';
part 'settings_panel_app.dart';
part 'settings_panel_profiles.dart';
part 'settings_panel_models.dart';
part 'settings_panel_local_exec.dart';
part 'settings_panel_local_exec_dialog.dart';
part 'settings_panel_mcp_server_dialog.dart';
part 'settings_panel_mcp_servers.dart';
part 'settings_panel_tool_collection.dart';
part 'settings_panel_tool_editor.dart';
part 'settings_panel_tool_fields.dart';
part 'settings_panel_config_files.dart';
part 'settings_panel_server.dart';
part 'settings_panel_actions.dart';
part 'settings_panel_config_dropdowns.dart';
part 'settings_panel_credentials.dart';
part 'settings_panel_model_adapter.dart';
part 'settings_panel_model_provider_card.dart';
part 'settings_panel_model_rows.dart';
part 'settings_panel_text_fields.dart';
part 'settings_panel_text_file_editor.dart';
