/// Defines the Agent Awesome visual system used by the Flutter workspace.
library;

import 'package:flutter/material.dart';

/// AgentAwesomeColors stores the app palette.
class AgentAwesomeColors {
  /// Prevents construction because this is a static palette.
  const AgentAwesomeColors._();

  /// App page background.
  static const Color page = Color(0xfff7f3eb);

  /// Main surface background.
  static const Color surface = Color(0xfffffcf7);

  /// Soft panel background.
  static const Color panel = Color(0xffeee8dc);

  /// Border color.
  static const Color border = Color(0xffd8cdbd);

  /// Primary forest green.
  static const Color green = Color(0xff244f31);

  /// Muted green used for selected backgrounds.
  static const Color greenSoft = Color(0xffe4e8cd);

  /// Coral command accent.
  static const Color coral = Color(0xffef5a4f);

  /// Primary text color.
  static const Color ink = Color(0xff15120f);

  /// Secondary text color.
  static const Color muted = Color(0xff786f63);

  /// Subtle secondary chrome text color.
  static const Color subtle = Color(0xff918779);

  /// Warm top-bar background.
  static const Color chrome = Color(0xfffffdf8);

  /// Sidebar navigation background.
  static const Color sidebar = Color(0xfff0eadf);
}

/// Builds the Material theme for Agent Awesome.
ThemeData buildAgentAwesomeTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AgentAwesomeColors.green,
    brightness: Brightness.light,
    primary: AgentAwesomeColors.green,
    secondary: AgentAwesomeColors.coral,
    surface: AgentAwesomeColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AgentAwesomeColors.page,
    fontFamily: 'Inter',
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 72,
        fontWeight: FontWeight.w900,
        height: 1.05,
        letterSpacing: 0,
        color: AgentAwesomeColors.ink,
      ),
      headlineLarge: TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.w900,
        height: 1.08,
        letterSpacing: 0,
        color: AgentAwesomeColors.ink,
      ),
      titleLarge: TextStyle(
        fontWeight: FontWeight.w700,
        color: AgentAwesomeColors.ink,
      ),
      bodyMedium: TextStyle(height: 1.5, color: AgentAwesomeColors.ink),
    ),
  );
}
