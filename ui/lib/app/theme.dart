/// Defines the Aurora visual system used by the Flutter workspace.
library;

import 'package:flutter/material.dart';

/// AuroraColors stores the app palette.
class AuroraColors {
  /// Prevents construction because this is a static palette.
  const AuroraColors._();

  /// App page background.
  static const Color page = Color(0xfff3eee4);

  /// Main surface background.
  static const Color surface = Color(0xfffbf8f1);

  /// Soft panel background.
  static const Color panel = Color(0xfff0eadf);

  /// Border color.
  static const Color border = Color(0xffd8cfbf);

  /// Primary forest green.
  static const Color green = Color(0xff1f512b);

  /// Muted green used for selected backgrounds.
  static const Color greenSoft = Color(0xffe5e7cf);

  /// Coral command accent.
  static const Color coral = Color(0xffe45646);

  /// Primary text color.
  static const Color ink = Color(0xff12100d);

  /// Secondary text color.
  static const Color muted = Color(0xff786f63);
}

/// Builds the Material theme for Aurora.
ThemeData buildAuroraTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AuroraColors.green,
    brightness: Brightness.light,
    primary: AuroraColors.green,
    secondary: AuroraColors.coral,
    surface: AuroraColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AuroraColors.page,
    fontFamily: 'Manrope',
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 56,
        height: 1.05,
        color: AuroraColors.ink,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 48,
        height: 1.08,
        color: AuroraColors.ink,
      ),
      titleLarge: TextStyle(
        fontWeight: FontWeight.w700,
        color: AuroraColors.ink,
      ),
      bodyMedium: TextStyle(height: 1.5, color: AuroraColors.ink),
    ),
  );
}
