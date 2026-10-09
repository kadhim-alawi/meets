import 'package:flutter/material.dart';

/// Design tokens. Warm "editorial" palette: paper, ink, a coral accent for
/// action, teal for good news, gold for discoveries.
@immutable
class MeetsColors extends ThemeExtension<MeetsColors> {
  const MeetsColors({
    required this.paper,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.teal,
    required this.gold,
    required this.danger,
  });

  final Color paper;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color line;
  final Color accent;
  final Color onAccent;
  final Color teal;
  final Color gold;
  final Color danger;

  static const light = MeetsColors(
    paper: Color(0xFFF4EFE6),
    surface: Color(0xFFFFFCF6),
    surfaceAlt: Color(0xFFEDE6D9),
    ink: Color(0xFF18160F),
    muted: Color(0xFF615A4F),
    faint: Color(0xFF948B7D),
    line: Color(0xFFDDD4C4),
    accent: Color(0xFFD9481F),
    onAccent: Color(0xFFFFF8F0),
    teal: Color(0xFF1C6B66),
    gold: Color(0xFFA77B0E),
    danger: Color(0xFFB3261E),
  );

  static const dark = MeetsColors(
    paper: Color(0xFF12110E),
    surface: Color(0xFF1B1915),
    surfaceAlt: Color(0xFF26231D),
    ink: Color(0xFFF2ECE1),
    muted: Color(0xFFB2A998),
    faint: Color(0xFF7D7567),
    line: Color(0xFF332F27),
    accent: Color(0xFFFF6B43),
    onAccent: Color(0xFF1A0E08),
    teal: Color(0xFF5DBDB3),
    gold: Color(0xFFE5BF4D),
    danger: Color(0xFFFF8A80),
  );

  @override
  MeetsColors copyWith() => this;

  @override
  MeetsColors lerp(ThemeExtension<MeetsColors>? other, double t) {
    if (other is! MeetsColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return MeetsColors(
      paper: l(paper, other.paper),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      line: l(line, other.line),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      teal: l(teal, other.teal),
      gold: l(gold, other.gold),
      danger: l(danger, other.danger),
    );
  }
}

extension MeetsThemeX on BuildContext {
  MeetsColors get c => Theme.of(this).extension<MeetsColors>()!;
  TextTheme get t => Theme.of(this).textTheme;
  double get width => MediaQuery.sizeOf(this).width;
  bool get isPhone => width < 720;
  bool get isWide => width >= 1120;
}

/// Font helpers. The sans and mono families are variable fonts, so weight is
/// set through the `wght` axis as well as [FontWeight].
class Fonts {
  static const serif = 'InstrumentSerif';
  static const sans = 'InstrumentSans';
  static const mono = 'JetBrainsMono';

  static TextStyle sansW(double size, FontWeight weight, {double height = 1.4, double? spacing, Color? color}) => TextStyle(
        fontFamily: sans,
        fontSize: size,
        fontWeight: weight,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        height: height,
        letterSpacing: spacing,
        color: color,
      );

  static TextStyle monoW(double size, {FontWeight weight = FontWeight.w500, double? spacing, Color? color}) => TextStyle(
        fontFamily: mono,
        fontSize: size,
        fontWeight: weight,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        letterSpacing: spacing,
        height: 1.3,
        color: color,
      );

  static TextStyle display(double size, {Color? color, bool italic = false, double height = 1.02}) => TextStyle(
        fontFamily: serif,
        fontSize: size,
        height: height,
        letterSpacing: -0.4,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: color,
      );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? MeetsColors.dark : MeetsColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.teal,
    onSecondary: c.surface,
    error: c.danger,
    onError: c.surface,
    surface: c.surface,
    onSurface: c.ink,
    surfaceContainerHighest: c.surfaceAlt,
    outline: c.line,
    outlineVariant: c.line,
  );
  final text = TextTheme(
    displayLarge: Fonts.display(72, color: c.ink),
    displayMedium: Fonts.display(54, color: c.ink),
    displaySmall: Fonts.display(40, color: c.ink, height: 1.08),
    headlineMedium: Fonts.display(32, color: c.ink, height: 1.1),
    headlineSmall: Fonts.display(26, color: c.ink, height: 1.15),
    titleLarge: Fonts.sansW(20, FontWeight.w600, color: c.ink, height: 1.25),
    titleMedium: Fonts.sansW(16, FontWeight.w600, color: c.ink, height: 1.3),
    titleSmall: Fonts.sansW(14, FontWeight.w600, color: c.ink, height: 1.3),
    bodyLarge: Fonts.sansW(17, FontWeight.w400, color: c.ink, height: 1.5),
    bodyMedium: Fonts.sansW(15, FontWeight.w400, color: c.ink, height: 1.5),
    bodySmall: Fonts.sansW(13, FontWeight.w400, color: c.muted, height: 1.45),
    labelLarge: Fonts.sansW(15, FontWeight.w600, color: c.ink, spacing: 0.1),
    labelMedium: Fonts.monoW(12, color: c.muted, spacing: 0.4),
    labelSmall: Fonts.monoW(11, color: c.muted, spacing: 0.6),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.paper,
    canvasColor: c.paper,
    fontFamily: Fonts.sans,
    textTheme: text,
    extensions: [c],
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    splashFactory: InkSparkle.splashFactory,
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(6)),
      textStyle: Fonts.sansW(12.5, FontWeight.w500, color: c.paper),
      waitDuration: const Duration(milliseconds: 350),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: Fonts.sansW(14, FontWeight.w500, color: c.paper),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      width: 420,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.paper,
      hintStyle: Fonts.sansW(15, FontWeight.w400, color: c.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ink, width: 1.4)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        textStyle: Fonts.sansW(15.5, FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.line),
        textStyle: Fonts.sansW(14.5, FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.ink, textStyle: Fonts.sansW(14.5, FontWeight.w600)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      side: BorderSide(color: c.line),
      labelStyle: Fonts.sansW(14, FontWeight.w500, color: c.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.line),
      radius: const Radius.circular(8),
    ),
  );
}
