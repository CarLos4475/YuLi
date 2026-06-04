import 'package:flutter/material.dart';

// ─── Colors ──────────────────────────────────────────────────────────────────

// Light mode
const Color paperLight = Color(0xFFF5F2EC);
const Color inkBlack = Color(0xFF111111);
const Color inkGray = Color(0xFF888888);
const Color borderColor = Color(0xFF111111);

// Dark mode
const Color paperDark = Color(0xFF0D0D0D);
const Color paperDarkCard = Color(0xFF1A1A1A);
const Color inkLight = Color(0xFFF5F2EC);

// Accent colors by mode
const Color accentFight = Color(0xFFE02B2B);
const Color accentFlight = Color(0xFF2D4B8E);
const Color accentLab = Color(0xFF3D6B4F);
const Color accentJournal = Color(0xFFC17F3A);

// Curated folder/space palette. Brutalist rule: every colour must have BODY on
// the cream paper (#F5F2EC) and carry cream text — medium-to-dark, saturated, or
// muted/earthy (café, mocha…). No pastels or near-paper neutrals (they vanish).
// Organised by hue family, each a tonal ramp (light-but-valid → deep) so the
// picker shows them "classically": by category and by tone. The canonical mode
// accents (#E02B2B/#C17F3A/#3D6B4F/#2D4B8E) live in here so existing items light
// up as selected.

class FolderPaletteSection {
  final String label;
  final List<Color> colors;
  const FolderPaletteSection({required this.label, required this.colors});
}

const List<Color> _palRojos = [
  Color(0xFFEF4B4B), Color(0xFFE02B2B), Color(0xFFC92626),
  Color(0xFFA81F1F), Color(0xFF8E2D2D), Color(0xFF761818), Color(0xFF5C1414),
];
const List<Color> _palNaranjas = [
  Color(0xFFF07A2B), Color(0xFFE06A1E), Color(0xFFC85718),
  Color(0xFF9C4A24), Color(0xFF7E3A1C), Color(0xFF6B341A),
];
const List<Color> _palAmbar = [
  Color(0xFFE0A92B), Color(0xFFC9961F), Color(0xFFC17F3A),
  Color(0xFFA8761A), Color(0xFF8F6B3A), Color(0xFF6E5A22),
];
const List<Color> _palVerdes = [
  Color(0xFF5CA62E), Color(0xFF4B8E2D), Color(0xFF3E7A28), Color(0xFF2E8B57),
  Color(0xFF2F7A4C), Color(0xFF3D6B4F), Color(0xFF2F5E4F), Color(0xFF244A3A),
];
const List<Color> _palTeal = [
  Color(0xFF2E9E94), Color(0xFF21998C), Color(0xFF2E6F6D), Color(0xFF1F7A8C),
  Color(0xFF1C6B7A), Color(0xFF274D5E), Color(0xFF1E3E4A),
];
const List<Color> _palAzules = [
  Color(0xFF3A86E0), Color(0xFF2B7BE0), Color(0xFF2566C4), Color(0xFF2D4B8E),
  Color(0xFF25406F), Color(0xFF253A73), Color(0xFF1E2F5E), Color(0xFF182748),
];
const List<Color> _palMorados = [
  Color(0xFF6A4FC0), Color(0xFF4C3B8F), Color(0xFF6B2D8E), Color(0xFF5A2E8E),
  Color(0xFF5A2E73), Color(0xFF3A2E6B), Color(0xFF2E2552),
];
const List<Color> _palRosas = [
  Color(0xFFD14C92), Color(0xFFC2186F), Color(0xFFB5326E), Color(0xFFA0285E),
  Color(0xFF8E2D4B), Color(0xFF7A2540), Color(0xFF6B2038), Color(0xFF5A1A2E),
];
const List<Color> _palTierra = [
  Color(0xFFA0623A), Color(0xFF8E5A34), Color(0xFF6F4E37), Color(0xFF8B6F5C),
  Color(0xFF7C6F64), Color(0xFF6B7A2D), Color(0xFF7A7A4A), Color(0xFF5E6E66),
  Color(0xFFA35C5C), Color(0xFF6E5168),
];
const List<Color> _palNeutros = [
  Color(0xFF6F6A64), Color(0xFF55504B), Color(0xFF45403C),
  Color(0xFF2B2927), Color(0xFF1F1E1C), Color(0xFF1A1A1A),
];

const List<FolderPaletteSection> folderPaletteSections = [
  FolderPaletteSection(label: 'ROJOS', colors: _palRojos),
  FolderPaletteSection(label: 'NARANJAS', colors: _palNaranjas),
  FolderPaletteSection(label: 'ÁMBAR', colors: _palAmbar),
  FolderPaletteSection(label: 'VERDES', colors: _palVerdes),
  FolderPaletteSection(label: 'TEAL · CIAN', colors: _palTeal),
  FolderPaletteSection(label: 'AZULES', colors: _palAzules),
  FolderPaletteSection(label: 'MORADOS', colors: _palMorados),
  FolderPaletteSection(label: 'ROSAS · VINO', colors: _palRosas),
  FolderPaletteSection(label: 'TIERRA · MOCHA', colors: _palTierra),
  FolderPaletteSection(label: 'NEUTROS', colors: _palNeutros),
];

// Flat view (back-compat for code reading a single list).
const List<Color> folderPalette = [
  ..._palRojos, ..._palNaranjas, ..._palAmbar, ..._palVerdes, ..._palTeal,
  ..._palAzules, ..._palMorados, ..._palRosas, ..._palTierra, ..._palNeutros,
];

// ─── Borders & Spacing ───────────────────────────────────────────────────────

const double borderRadiusValue = 0.0; // zero everywhere, no exceptions
const double borderWidth = 2.0;
const double borderWidthHeavy = 4.0;
const Offset shadowOffset = Offset(3, 3);
const double shadowBlurRadius = 0.0; // solid shadow, never diffused

// ─── Typography ──────────────────────────────────────────────────────────────

// Display — Space Grotesk
const TextStyle displayXL = TextStyle(
  fontFamily: 'SpaceGrotesk',
  fontWeight: FontWeight.w800,
  fontSize: 48,
  letterSpacing: -1.0,
  height: 1.0,
);

const TextStyle displayL = TextStyle(
  fontFamily: 'SpaceGrotesk',
  fontWeight: FontWeight.w700,
  fontSize: 32,
  letterSpacing: -0.5,
  height: 1.1,
);

const TextStyle displayM = TextStyle(
  fontFamily: 'SpaceGrotesk',
  fontWeight: FontWeight.w700,
  fontSize: 24,
  letterSpacing: -0.3,
  height: 1.2,
);

// Body — Inter
const TextStyle bodyL = TextStyle(
  fontFamily: 'Inter',
  fontWeight: FontWeight.w400,
  fontSize: 18,
  height: 1.6,
);

const TextStyle bodyM = TextStyle(
  fontFamily: 'Inter',
  fontWeight: FontWeight.w400,
  fontSize: 16,
  height: 1.5,
);

const TextStyle bodyS = TextStyle(
  fontFamily: 'Inter',
  fontWeight: FontWeight.w400,
  fontSize: 13,
  height: 1.4,
);

const TextStyle labelBold = TextStyle(
  fontFamily: 'Inter',
  fontWeight: FontWeight.w700,
  fontSize: 14,
  height: 1.3,
  letterSpacing: 0.2,
);

const TextStyle mono = TextStyle(
  fontFamily: 'monospace',
  fontSize: 14,
  height: 1.4,
);

// Additional label sizes (not in original set, added for Calendar/Timeline)
const TextStyle labelS = TextStyle(
  fontFamily: 'Inter',
  fontWeight: FontWeight.w600,
  fontSize: 12,
  height: 1.3,
);

const TextStyle labelM = TextStyle(
  fontFamily: 'Inter',
  fontWeight: FontWeight.w600,
  fontSize: 14,
  height: 1.3,
);

const TextStyle labelXS = TextStyle(
  fontFamily: 'Inter',
  fontWeight: FontWeight.w500,
  fontSize: 10,
  height: 1.3,
);

const TextStyle labelXXS = TextStyle(
  fontFamily: 'Inter',
  fontWeight: FontWeight.w500,
  fontSize: 8,
  height: 1.2,
);

const TextStyle bodyXS = TextStyle(
  fontFamily: 'Inter',
  fontWeight: FontWeight.w400,
  fontSize: 11,
  height: 1.3,
);

// Semantic accent aliases
const Color accentError = accentFight;
const Color accentSuccess = accentLab;

// Shadow presets
const List<BoxShadow> shadowM = [
  BoxShadow(
    color: Color(0xFF111111),
    offset: Offset(3, 3),
    blurRadius: 0,
  ),
];

// ─── Theme Data ───────────────────────────────────────────────────────────────

ThemeData lightTheme() => ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: paperLight,
      colorScheme: const ColorScheme.light(
        surface: paperLight,
        primary: inkBlack,
        secondary: accentFight,
        onSurface: inkBlack,
      ),
      fontFamily: 'Inter',
      textTheme: _buildTextTheme(inkBlack),
      dividerColor: inkBlack,
      cardTheme: const CardThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        elevation: 0,
      ),
      inputDecorationTheme: _inputDecorationTheme(inkBlack, paperLight),
      appBarTheme: AppBarTheme(
        backgroundColor: paperLight,
        foregroundColor: inkBlack,
        elevation: 0,
        titleTextStyle: displayM.copyWith(color: inkBlack),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _BrutalistPushBuilder(),
          TargetPlatform.iOS: _BrutalistPushBuilder(),
          TargetPlatform.windows: _BrutalistPushBuilder(),
          TargetPlatform.macOS: _BrutalistPushBuilder(),
          TargetPlatform.linux: _BrutalistPushBuilder(),
        },
      ),
    );

ThemeData darkTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: paperDark,
      colorScheme: const ColorScheme.dark(
        surface: paperDark,
        primary: inkLight,
        secondary: accentFight,
        onSurface: inkLight,
      ),
      fontFamily: 'Inter',
      textTheme: _buildTextTheme(inkLight),
      dividerColor: inkLight,
      cardTheme: const CardThemeData(
        color: paperDarkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        elevation: 0,
      ),
      inputDecorationTheme: _inputDecorationTheme(inkLight, paperDark),
      appBarTheme: AppBarTheme(
        backgroundColor: paperDark,
        foregroundColor: inkLight,
        elevation: 0,
        titleTextStyle: displayM.copyWith(color: inkLight),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _BrutalistPushBuilder(),
          TargetPlatform.iOS: _BrutalistPushBuilder(),
          TargetPlatform.windows: _BrutalistPushBuilder(),
          TargetPlatform.macOS: _BrutalistPushBuilder(),
          TargetPlatform.linux: _BrutalistPushBuilder(),
        },
      ),
    );

TextTheme _buildTextTheme(Color baseColor) => TextTheme(
      displayLarge: displayXL.copyWith(color: baseColor),
      displayMedium: displayL.copyWith(color: baseColor),
      displaySmall: displayM.copyWith(color: baseColor),
      bodyLarge: bodyL.copyWith(color: baseColor),
      bodyMedium: bodyM.copyWith(color: baseColor),
      bodySmall: bodyS.copyWith(color: baseColor),
      labelLarge: labelBold.copyWith(color: baseColor),
    );

InputDecorationTheme _inputDecorationTheme(Color ink, Color paper) =>
    InputDecorationTheme(
      filled: true,
      fillColor: paper,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: ink, width: borderWidthHeavy),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: ink, width: borderWidthHeavy),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: ink, width: borderWidthHeavy),
      ),
    );

// ─── Helpers ──────────────────────────────────────────────────────────────────

Color paperColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? paperDark : paperLight;

Color inkColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? inkLight : inkBlack;

Color cardBackground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? paperDarkCard : paperLight;

/// Returns the given color desaturated for done/completed states.
Color desaturate(Color color, {double amount = 0.7}) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withSaturation((hsl.saturation * (1 - amount)).clamp(0.0, 1.0)).toColor();
}

/// Strips Spanish accents from a string to facilitate comparison.
String removeAccents(String str) {
  const withRound = 'áéíóúÁÉÍÓÚäëïöüÄËÏÖÜñÑ';
  const withoutRound = 'aeiouAEIOUaeiouAEIOUnN';
  var result = str;
  for (int i = 0; i < withRound.length; i++) {
    result = result.replaceAll(withRound[i], withoutRound[i]);
  }
  return result;
}

/// Brutalist page transition: new page slides from left, pushing old page to right.
class _BrutalistPushBuilder extends PageTransitionsBuilder {
  const _BrutalistPushBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(-1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.linear,
      )),
      child: child,
    );
  }
}
