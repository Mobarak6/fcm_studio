import 'dart:io';

import 'package:fcm_studio/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    group('$name theme', () {
      test('uses Inter everywhere', () {
        final text = theme.textTheme;
        for (final style in [
          text.headlineSmall,
          text.titleMedium,
          text.titleSmall,
          text.bodyLarge,
          text.bodyMedium,
          text.labelLarge,
        ]) {
          expect(style?.fontFamily, AppTheme.fontFamily);
        }
      });

      test('has compact desktop text sizes', () {
        final text = theme.textTheme;
        expect(text.headlineSmall?.fontSize, 20);
        expect(text.titleMedium?.fontSize, 15);
        expect(text.titleSmall?.fontSize, 13);
        expect(text.titleSmall?.fontWeight, FontWeight.w600);
        expect(text.bodyLarge?.fontSize, 14);
        expect(text.bodyMedium?.fontSize, 13);
        expect(text.bodySmall?.fontSize, 12);
        expect(text.labelLarge?.fontSize, 13);
        expect(text.labelLarge?.fontWeight, FontWeight.w600);
      });

      test('takes its colors from the logo blue', () {
        expect(
          theme.colorScheme.primary,
          ColorScheme.fromSeed(
            seedColor: AppTheme.brandBlue,
            brightness: theme.brightness,
          ).primary,
        );
      });
    });
  }

  test('the bundled font and logo files exist', () {
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      expect(
        File('assets/fonts/Inter-$weight.ttf').existsSync(),
        isTrue,
        reason: weight,
      );
    }
    expect(File('assets/fonts/OFL.txt').existsSync(), isTrue);
    expect(File('assets/branding/mark.png').existsSync(), isTrue);
  });
}
