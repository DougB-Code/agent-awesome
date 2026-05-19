/// Starts the Agent Awesome assistant workspace Flutter application.
library;

import 'package:flutter/material.dart';

import 'ui/agent_awesome_app.dart';
import 'app/app_config.dart';

/// Runs the configured Agent Awesome desktop application.
void main() {
  runApp(AgentAwesomeApp(config: AppConfig.fromEnvironment()));
}
