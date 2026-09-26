import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFFF57C00);

  static final ThemeData light = ThemeData(
    colorSchemeSeed: _seed,
    brightness: Brightness.light,
    useMaterial3: true,
  );

  static final ThemeData dark = ThemeData(
    colorSchemeSeed: _seed,
    brightness: Brightness.dark,
    useMaterial3: true,
  );
}
