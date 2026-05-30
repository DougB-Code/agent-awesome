/// Defines the Agent Awesome visual system used by the Flutter workspace.
library;

import 'package:flutter/material.dart';

/// AgentAwesomeStrokeTokens defines shared border and divider thicknesses.
abstract final class AgentAwesomeStrokeTokens {
  /// Standard outline thickness for cards, fields, and panel frames.
  static const double borderWidth = 1.25;

  /// Standard divider thickness for command-shell section seams.
  static const double dividerWidth = 1.25;
}

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
    required this.field,
    required this.card,
    required this.cardBorder,
    required this.cardAccent,
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
    field: AgentAwesomeColors.surface,
    card: AgentAwesomeColors.surface,
    cardBorder: AgentAwesomeColors.border,
    cardAccent: AgentAwesomeColors.green,
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
    shadow: Color(0x00000000),
    softShadow: Color(0x00000000),
    warningSoft: Color(0xfffff7ef),
    warningBorder: AgentAwesomeColors.border,
    warningText: AgentAwesomeColors.green,
  );

  /// Restyled dark palette for the Flutter UI.
  static const AgentAwesomePalette dark = AgentAwesomePalette(
    page: Color(0xff040a12),
    surface: Color(0xff0c131f),
    panel: Color(0xff0c131f),
    panelStrong: Color(0xff162235),
    field: Color(0xff141b27),
    card: Color(0xff151b27),
    cardBorder: Color(0xff1c232f),
    cardAccent: Color(0xff24b6c7),
    border: Color(0xff1c232f),
    borderStrong: Color(0xff22b4dc),
    green: Color(0xff2fc4e7),
    greenSoft: Color(0xff102a40),
    coral: Color(0xffff5f7d),
    ink: Color(0xfff5f8ff),
    muted: Color(0xffc1cad8),
    subtle: Color(0xff8491a4),
    chrome: Color(0xff070e18),
    sidebar: Color(0xff091321),
    searchBorder: Color(0xff1c232f),
    kbdBackground: Color(0xff172131),
    heroEnd: Color(0xff08111b),
    cardIconBackground: Color(0xff102a3e),
    cardIcon: Color(0xff2fc4e7),
    orbit: Color(0xff41506b),
    layerFill: Color(0xff102236),
    layerBorder: Color(0xff325671),
    shadow: Color(0x00000000),
    softShadow: Color(0x00000000),
    warningSoft: Color(0xff251d0d),
    warningBorder: Color(0xff806122),
    warningText: Color(0xffffc453),
  );

  /// App page background.
  final Color page;

  /// Main card and control surface.
  final Color surface;

  /// Soft panel background.
  final Color panel;

  /// Stronger inset panel background.
  final Color panelStrong;

  /// Form field background.
  final Color field;

  /// Repeated selectable card background.
  final Color card;

  /// Repeated selectable card border.
  final Color cardBorder;

  /// Repeated selectable card active accent.
  final Color cardAccent;

  /// Default border color.
  final Color border;

  /// Strong border color.
  final Color borderStrong;

  /// Primary brand action color; light mode keeps the original forest green.
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

  /// No-op decorative shadow color; AA shared chrome stays flat.
  final Color shadow;

  /// No-op soft shadow color; AA shared chrome stays flat.
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
    Color? field,
    Color? card,
    Color? cardBorder,
    Color? cardAccent,
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
      field: field ?? this.field,
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      cardAccent: cardAccent ?? this.cardAccent,
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
      field: Color.lerp(field, other.field, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      cardAccent: Color.lerp(cardAccent, other.cardAccent, t)!,
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

  /// Whether the active Agent Awesome theme is dark.
  bool get agentAwesomeIsDark => Theme.of(this).brightness == Brightness.dark;

  /// Dark-mode page gradient matching the restyled canvas.
  LinearGradient? get agentAwesomeWorkspaceGradient {
    if (!agentAwesomeIsDark) {
      return null;
    }
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xff0b1624), Color(0xff040a12)],
    );
  }

  /// Dark-mode top chrome gradient for the global command bar.
  LinearGradient? get agentAwesomeChromeGradient {
    if (!agentAwesomeIsDark) {
      return null;
    }
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xff0b1421), Color(0xff070e18)],
    );
  }

  /// Dark-mode sidebar gradient matching the restyled rail.
  LinearGradient? get agentAwesomeSidebarGradient {
    if (!agentAwesomeIsDark) {
      return null;
    }
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xff0d1827), Color(0xff07111d)],
    );
  }

  /// Dark-mode panel gradient for primary bordered surfaces.
  LinearGradient? get agentAwesomeSurfaceGradient {
    return null;
  }

  /// Dark-mode card gradient for repeated work items.
  LinearGradient? get agentAwesomeCardGradient {
    if (!agentAwesomeIsDark) {
      return null;
    }
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xff121f31), Color(0xff0a1422)],
    );
  }

  /// Dark-mode control gradient for buttons, tabs, and filter triggers.
  LinearGradient? get agentAwesomeControlGradient {
    if (!agentAwesomeIsDark) {
      return null;
    }
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xff162233), Color(0xff0f1927)],
    );
  }

  /// Dark-mode selected gradient for active controls without a green wash.
  LinearGradient? get agentAwesomeSelectedGradient {
    if (!agentAwesomeIsDark) {
      return null;
    }
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xff14304a), Color(0xff0f1c2e)],
    );
  }

  /// Dark-mode selected gradient for active shell sidebar routes.
  LinearGradient? get agentAwesomeSidebarSelectedGradient {
    if (!agentAwesomeIsDark) {
      return null;
    }
    return const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xff15202d), Color(0xff111b27)],
    );
  }

  /// Dark-mode primary gradient for compact brand marks and main actions.
  LinearGradient? get agentAwesomePrimaryGradient {
    if (!agentAwesomeIsDark) {
      return null;
    }
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xff35d7ff), Color(0xff1687ad)],
    );
  }

  /// Semantic low-positive accent, cooler in dark mode than success green.
  Color get agentAwesomeLowAccent {
    if (agentAwesomeIsDark) {
      return const Color(0xff2ed884);
    }
    return agentAwesomeColors.green;
  }

  /// Semantic warning accent, matched to the restyled amber.
  Color get agentAwesomeWarningAccent {
    if (agentAwesomeIsDark) {
      return agentAwesomeColors.warningText;
    }
    return const Color(0xffa87312);
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
  final baseScheme = ColorScheme.fromSeed(
    seedColor: colors.green,
    brightness: brightness,
    primary: colors.green,
    secondary: colors.coral,
    surface: colors.surface,
  );
  final scheme = baseScheme.copyWith(
    primary: colors.green,
    onPrimary: colors.page,
    primaryContainer: colors.greenSoft,
    onPrimaryContainer: colors.ink,
    secondary: colors.cardIcon,
    onSecondary: colors.page,
    secondaryContainer: colors.cardIconBackground,
    onSecondaryContainer: colors.ink,
    error: colors.coral,
    onError: colors.page,
    surface: colors.surface,
    onSurface: colors.ink,
    surfaceContainerHighest: colors.panelStrong,
    outline: colors.border,
    outlineVariant: colors.borderStrong,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.page,
    canvasColor: colors.surface,
    fontFamily: 'Inter',
    extensions: <ThemeExtension<dynamic>>[colors],
    dividerTheme: DividerThemeData(
      color: colors.border,
      thickness: AgentAwesomeStrokeTokens.dividerWidth,
    ),
    iconTheme: IconThemeData(color: colors.ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.field,
      border: _agentAwesomeInputBorder(colors.border),
      enabledBorder: _agentAwesomeInputBorder(colors.border),
      disabledBorder: _agentAwesomeInputBorder(colors.border),
      focusedBorder: _agentAwesomeInputBorder(colors.searchBorder),
    ),
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

/// Builds the shared outline used by form fields and dropdown fields.
OutlineInputBorder _agentAwesomeInputBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(
      color: color,
      width: AgentAwesomeStrokeTokens.borderWidth,
    ),
  );
}
