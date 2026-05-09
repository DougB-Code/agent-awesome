/// Defines the Agent Awesome visual system used by the Flutter workspace.
library;

import 'package:flutter/material.dart';

/// AgentAwesomeColors stores stable light-theme constants for legacy call sites.
class AgentAwesomeColors {
  /// Prevents construction because this is a static light palette.
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

/// AgentAwesomePalette exposes semantic theme colors to widgets.
@immutable
class AgentAwesomePalette extends ThemeExtension<AgentAwesomePalette> {
  /// Creates one complete color palette for the app chrome and content.
  const AgentAwesomePalette({
    required this.page,
    required this.surface,
    required this.panel,
    required this.panelStrong,
    required this.border,
    required this.borderStrong,
    required this.green,
    required this.greenSoft,
    required this.coral,
    required this.ink,
    required this.muted,
    required this.subtle,
    required this.chrome,
    required this.sidebar,
    required this.searchBorder,
    required this.kbdBackground,
    required this.heroEnd,
    required this.cardIconBackground,
    required this.cardIcon,
    required this.orbit,
    required this.layerFill,
    required this.layerBorder,
    required this.shadow,
    required this.softShadow,
    required this.warningSoft,
    required this.warningBorder,
    required this.warningText,
  });

  /// Documentation-inspired light palette used by the current Flutter UI.
  static const AgentAwesomePalette light = AgentAwesomePalette(
    page: AgentAwesomeColors.page,
    surface: AgentAwesomeColors.surface,
    panel: AgentAwesomeColors.panel,
    panelStrong: Color(0xffe8e8d2),
    border: AgentAwesomeColors.border,
    borderStrong: Color(0xffc8bba8),
    green: AgentAwesomeColors.green,
    greenSoft: AgentAwesomeColors.greenSoft,
    coral: AgentAwesomeColors.coral,
    ink: AgentAwesomeColors.ink,
    muted: AgentAwesomeColors.muted,
    subtle: AgentAwesomeColors.subtle,
    chrome: AgentAwesomeColors.chrome,
    sidebar: AgentAwesomeColors.sidebar,
    searchBorder: Color(0xff9ed1a1),
    kbdBackground: Color(0xfff0eee8),
    heroEnd: Color(0xfffff8ee),
    cardIconBackground: Color(0xffdfe9ff),
    cardIcon: Color(0xff1473ff),
    orbit: Color(0xffb7c4ae),
    layerFill: Color(0xffe6e7d8),
    layerBorder: Color(0xff93a98f),
    shadow: Color(0x12382718),
    softShadow: Color(0x04453421),
    warningSoft: Color(0xfffff7ef),
    warningBorder: AgentAwesomeColors.border,
    warningText: AgentAwesomeColors.green,
  );

  /// Documentation-inspired dark palette for the Flutter UI.
  static const AgentAwesomePalette dark = AgentAwesomePalette(
    page: Color(0xff070c12),
    surface: Color(0xff0d141d),
    panel: Color(0xff111a25),
    panelStrong: Color(0xff172232),
    border: Color(0xff263443),
    borderStrong: Color(0xff35475b),
    green: Color(0xff5bd777),
    greenSoft: Color(0xff193425),
    coral: Color(0xffa871ff),
    ink: Color(0xfff7f9ff),
    muted: Color(0xffc4cad7),
    subtle: Color(0xff8793a6),
    chrome: Color(0xff0d141d),
    sidebar: Color(0xff0a1119),
    searchBorder: Color(0xff2c5f9d),
    kbdBackground: Color(0xff162232),
    heroEnd: Color(0xff0b1017),
    cardIconBackground: Color(0xff182a43),
    cardIcon: Color(0xff4ea3ff),
    orbit: Color(0xff37564d),
    layerFill: Color(0xff172232),
    layerBorder: Color(0xff355b4d),
    shadow: Color(0x66000000),
    softShadow: Color(0x12a871ff),
    warningSoft: Color(0xff251d17),
    warningBorder: Color(0xff5b4231),
    warningText: Color(0xfff0ad37),
  );

  /// App page background.
  final Color page;

  /// Main card and control surface.
  final Color surface;

  /// Soft panel background.
  final Color panel;

  /// Stronger inset panel background.
  final Color panelStrong;

  /// Default border color.
  final Color border;

  /// Strong border color.
  final Color borderStrong;

  /// Primary positive and brand action color.
  final Color green;

  /// Selected or active soft background.
  final Color greenSoft;

  /// Primary command accent.
  final Color coral;

  /// Primary text color.
  final Color ink;

  /// Secondary text color.
  final Color muted;

  /// Subtle chrome text color.
  final Color subtle;

  /// Top-bar and brand chrome background.
  final Color chrome;

  /// Sidebar navigation background.
  final Color sidebar;

  /// Command/search field border.
  final Color searchBorder;

  /// Keyboard hint background.
  final Color kbdBackground;

  /// End color for the hero background gradient.
  final Color heroEnd;

  /// Path-card icon background.
  final Color cardIconBackground;

  /// Path-card icon foreground.
  final Color cardIcon;

  /// Diagram orbit guide color.
  final Color orbit;

  /// Diagram layer fill color.
  final Color layerFill;

  /// Diagram layer border color.
  final Color layerBorder;

  /// Standard decorative shadow color.
  final Color shadow;

  /// Softer control shadow color.
  final Color softShadow;

  /// Warning background.
  final Color warningSoft;

  /// Warning border.
  final Color warningBorder;

  /// Warning foreground.
  final Color warningText;

  @override
  AgentAwesomePalette copyWith({
    Color? page,
    Color? surface,
    Color? panel,
    Color? panelStrong,
    Color? border,
    Color? borderStrong,
    Color? green,
    Color? greenSoft,
    Color? coral,
    Color? ink,
    Color? muted,
    Color? subtle,
    Color? chrome,
    Color? sidebar,
    Color? searchBorder,
    Color? kbdBackground,
    Color? heroEnd,
    Color? cardIconBackground,
    Color? cardIcon,
    Color? orbit,
    Color? layerFill,
    Color? layerBorder,
    Color? shadow,
    Color? softShadow,
    Color? warningSoft,
    Color? warningBorder,
    Color? warningText,
  }) {
    return AgentAwesomePalette(
      page: page ?? this.page,
      surface: surface ?? this.surface,
      panel: panel ?? this.panel,
      panelStrong: panelStrong ?? this.panelStrong,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      green: green ?? this.green,
      greenSoft: greenSoft ?? this.greenSoft,
      coral: coral ?? this.coral,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      subtle: subtle ?? this.subtle,
      chrome: chrome ?? this.chrome,
      sidebar: sidebar ?? this.sidebar,
      searchBorder: searchBorder ?? this.searchBorder,
      kbdBackground: kbdBackground ?? this.kbdBackground,
      heroEnd: heroEnd ?? this.heroEnd,
      cardIconBackground: cardIconBackground ?? this.cardIconBackground,
      cardIcon: cardIcon ?? this.cardIcon,
      orbit: orbit ?? this.orbit,
      layerFill: layerFill ?? this.layerFill,
      layerBorder: layerBorder ?? this.layerBorder,
      shadow: shadow ?? this.shadow,
      softShadow: softShadow ?? this.softShadow,
      warningSoft: warningSoft ?? this.warningSoft,
      warningBorder: warningBorder ?? this.warningBorder,
      warningText: warningText ?? this.warningText,
    );
  }

  @override
  AgentAwesomePalette lerp(
    ThemeExtension<AgentAwesomePalette>? other,
    double t,
  ) {
    if (other is! AgentAwesomePalette) {
      return this;
    }
    return AgentAwesomePalette(
      page: Color.lerp(page, other.page, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelStrong: Color.lerp(panelStrong, other.panelStrong, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      green: Color.lerp(green, other.green, t)!,
      greenSoft: Color.lerp(greenSoft, other.greenSoft, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      chrome: Color.lerp(chrome, other.chrome, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      searchBorder: Color.lerp(searchBorder, other.searchBorder, t)!,
      kbdBackground: Color.lerp(kbdBackground, other.kbdBackground, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
      cardIconBackground: Color.lerp(
        cardIconBackground,
        other.cardIconBackground,
        t,
      )!,
      cardIcon: Color.lerp(cardIcon, other.cardIcon, t)!,
      orbit: Color.lerp(orbit, other.orbit, t)!,
      layerFill: Color.lerp(layerFill, other.layerFill, t)!,
      layerBorder: Color.lerp(layerBorder, other.layerBorder, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      softShadow: Color.lerp(softShadow, other.softShadow, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      warningBorder: Color.lerp(warningBorder, other.warningBorder, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
    );
  }
}

/// AgentAwesomeThemeLookup resolves app palette tokens from BuildContext.
extension AgentAwesomeThemeLookup on BuildContext {
  /// Active Agent Awesome semantic colors.
  AgentAwesomePalette get agentAwesomeColors {
    return Theme.of(this).extension<AgentAwesomePalette>() ??
        AgentAwesomePalette.light;
  }
}

/// AgentAwesomeThemeScope exposes app-level theme controls to descendants.
class AgentAwesomeThemeScope extends InheritedWidget {
  /// Creates a scope for reading and toggling the active app theme.
  const AgentAwesomeThemeScope({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
    required super.child,
  });

  /// Current app theme mode.
  final ThemeMode themeMode;

  /// Toggles between the light and dark themes.
  final VoidCallback onToggleTheme;

  /// Whether the current explicit theme mode is dark.
  bool get isDark => themeMode == ThemeMode.dark;

  /// Returns the nearest theme scope, if available.
  static AgentAwesomeThemeScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AgentAwesomeThemeScope>();
  }

  @override
  bool updateShouldNotify(covariant AgentAwesomeThemeScope oldWidget) {
    return themeMode != oldWidget.themeMode ||
        onToggleTheme != oldWidget.onToggleTheme;
  }
}

/// Builds the Material theme for Agent Awesome.
ThemeData buildAgentAwesomeTheme({Brightness brightness = Brightness.light}) {
  final colors = brightness == Brightness.dark
      ? AgentAwesomePalette.dark
      : AgentAwesomePalette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: colors.green,
    brightness: brightness,
    primary: colors.green,
    secondary: colors.coral,
    surface: colors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.page,
    canvasColor: colors.page,
    fontFamily: 'Inter',
    extensions: <ThemeExtension<dynamic>>[colors],
    dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
    iconTheme: IconThemeData(color: colors.ink),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.green,
      selectionColor: colors.greenSoft,
      selectionHandleColor: colors.green,
    ),
    textTheme: TextTheme(
      displayLarge: TextStyle(
        fontSize: 72,
        fontWeight: FontWeight.w900,
        height: 1.05,
        letterSpacing: 0,
        color: colors.ink,
      ),
      headlineLarge: TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.w900,
        height: 1.08,
        letterSpacing: 0,
        color: colors.ink,
      ),
      titleLarge: TextStyle(fontWeight: FontWeight.w700, color: colors.ink),
      bodyMedium: TextStyle(height: 1.5, color: colors.ink),
    ),
  );
}
