import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/color_utils.dart';
import '../../../data/models/store_design.dart';

/// The storefront's look, built from a design's [ThemeSettings] on top of
/// the app theme: the seller's colors, fonts and button shape. Only the
/// storefront itself is wrapped in it. Seller and admin screens stay
/// Meridian.
class StorefrontTheme {
  StorefrontTheme._();

  static Color accent(ThemeSettings s) =>
      hexToColor(s.accentHex) ?? const Color(0xFF303F9F);
  static Color background(ThemeSettings s) =>
      hexToColor(s.backgroundHex) ?? const Color(0xFFFCFCFB);
  static Color text(ThemeSettings s) =>
      hexToColor(s.textHex) ?? const Color(0xFF14161F);

  /// Black or white, whichever reads better on [color].
  static Color onColor(Color color) =>
      color.computeLuminance() > 0.45 ? const Color(0xFF14161F) : Colors.white;

  static OutlinedBorder buttonShape(ThemeSettings s) => switch (s.buttonShape) {
        ButtonShape.pill => const StadiumBorder(),
        ButtonShape.rounded => RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.stub + 4)),
        ButtonShape.square =>
          const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      };

  static ThemeData of(ThemeData base, ThemeSettings s) {
    final accent = StorefrontTheme.accent(s);
    final background = StorefrontTheme.background(s);
    final text = StorefrontTheme.text(s);
    final onAccent = onColor(accent);
    final shape = buttonShape(s);

    final body = _textTheme(s.bodyFont, base.textTheme);
    final heading = _textTheme(s.headingFont, base.textTheme);
    final textTheme = body
        .copyWith(
          displayLarge: heading.displayLarge,
          displayMedium: heading.displayMedium,
          displaySmall: heading.displaySmall,
          headlineLarge: heading.headlineLarge,
          headlineMedium: heading.headlineMedium,
          headlineSmall: heading.headlineSmall,
          titleLarge: heading.titleLarge,
        )
        .apply(bodyColor: text, displayColor: text);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      canvasColor: background,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        onPrimary: onAccent,
        secondary: accent,
        onSecondary: onAccent,
        surface: background,
        onSurface: text,
      ),
      textTheme: textTheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: background,
        foregroundColor: text,
        titleTextStyle: heading.titleLarge?.copyWith(color: text),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: shape,
          textStyle: body.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent),
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: text),
      ),
      chipTheme: base.chipTheme.copyWith(selectedColor: accent),
    );
  }

  /// [family] is always one of [StoreFont.all] (the model enforces it),
  /// but a font that fails to load must not take the storefront down.
  static TextTheme _textTheme(String family, TextTheme base) {
    try {
      return GoogleFonts.getTextTheme(family, base);
    } catch (_) {
      return base;
    }
  }
}
