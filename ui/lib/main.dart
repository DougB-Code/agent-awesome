/// Starts the Aurora assistant workspace Flutter application.
library;

import 'package:flutter/material.dart';

import 'app/aurora_app.dart';
import 'app/app_config.dart';

/// Runs the configured Aurora desktop application.
void main() {
  runApp(AuroraApp(config: AppConfig.fromEnvironment()));
}
