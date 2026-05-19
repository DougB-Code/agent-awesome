/// Renders the first-run model setup flow for the Agent Awesome desktop app.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_controller.dart';
import '../theme.dart';
import '../../domain/local_models.dart';
import '../../domain/onboarding_model_setup.dart';
import '../../domain/system_capabilities.dart';

part 'getting_started_wizard_shell.dart';
part 'getting_started_wizard_frame.dart';
part 'getting_started_wizard_choice.dart';
part 'getting_started_wizard_api_key.dart';
part 'getting_started_wizard_local_model.dart';
part 'getting_started_wizard_controls.dart';
part 'getting_started_wizard_helpers.dart';
part 'getting_started_wizard_badges.dart';
