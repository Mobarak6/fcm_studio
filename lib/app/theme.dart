import 'package:flutter/material.dart';

/// FCM Studio's look: the logo's colors, the Inter font, and text sizes
/// tuned for a desktop tool rather than a phone.
abstract final class AppTheme {
  /// The logo's blue (the bell's clapper and the signal waves).
  static const brandBlue = Color(0xFF1F8AFD);

  /// Bundled in assets/fonts (SIL Open Font License, assets/fonts/OFL.txt).
  static const fontFamily = 'Inter';

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandBlue,
        brightness: brightness,
      ),
      fontFamily: fontFamily,
    );
    return base.copyWith(
      textTheme: _compact(base.textTheme),
      primaryTextTheme: _compact(base.primaryTextTheme),
    );
  }

  /// Material's sizes are made for phones; a desktop tool reads better a
  /// step smaller, with semibold titles. Inter needs no extra tracking.
  static TextTheme _compact(TextTheme t) {
    TextStyle? style(
      TextStyle? s,
      double size,
      FontWeight weight, {
      double height = 1.4,
    }) => s?.copyWith(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: 0,
    );

    return t.copyWith(
      displayLarge: style(t.displayLarge, 48, FontWeight.w600, height: 1.15),
      displayMedium: style(t.displayMedium, 40, FontWeight.w600, height: 1.15),
      displaySmall: style(t.displaySmall, 32, FontWeight.w600, height: 1.2),
      headlineLarge: style(t.headlineLarge, 28, FontWeight.w600, height: 1.25),
      headlineMedium: style(t.headlineMedium, 24, FontWeight.w600, height: 1.3),
      headlineSmall: style(t.headlineSmall, 20, FontWeight.w600, height: 1.3),
      titleLarge: style(t.titleLarge, 18, FontWeight.w600, height: 1.35),
      titleMedium: style(t.titleMedium, 15, FontWeight.w600),
      titleSmall: style(t.titleSmall, 13, FontWeight.w600),
      bodyLarge: style(t.bodyLarge, 14, FontWeight.w400),
      bodyMedium: style(t.bodyMedium, 13, FontWeight.w400),
      bodySmall: style(t.bodySmall, 12, FontWeight.w400, height: 1.35),
      labelLarge: style(t.labelLarge, 13, FontWeight.w600),
      labelMedium: style(t.labelMedium, 12, FontWeight.w500),
      labelSmall: style(t.labelSmall, 11, FontWeight.w500),
    );
  }
}
