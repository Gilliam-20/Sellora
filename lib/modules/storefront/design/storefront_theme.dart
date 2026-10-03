import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/color_utils.dart';
import '../../../core/widgets/product_card.dart';
import '../../../data/models/store_design.dart';

/// The storefront's look, built from a design's [ThemeSettings] on top of
/// the app theme: the seller's colors, fonts and button shape, plus a
/// [StoreStyle] extension for what Material's theme has no slot for
/// (corners, card treatment, photo shape, spacing). Only the storefront
/// itself is wrapped in it. Seller and admin screens stay Meridian.
class StorefrontTheme {
  StorefrontTheme._();

  static Color accent(ThemeSettings s) =>
      hexToColor(s.accentHex) ?? const Color(0xFF303F9F);
  static Color background(ThemeSettings s) =>
      hexToColor(s.backgroundHex) ?? const Color(0xFFFCFCFB);
  static Color surface(ThemeSettings s) =>
      hexToColor(s.surfaceHex) ?? background(s);
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
    final surface = StorefrontTheme.surface(s);
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
        surface: surface,
        onSurface: text,
      ),
      textTheme: textTheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: background,
        foregroundColor: text,
        centerTitle: s.centeredHeader,
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
      inputDecorationTheme:
          base.inputDecorationTheme.copyWith(fillColor: surface),
      chipTheme: base.chipTheme
          .copyWith(selectedColor: accent, backgroundColor: surface),
      extensions: [StoreStyle.from(s)],
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

/// A theme's layout style, for the renderer's own widgets.
class StoreStyle extends ThemeExtension<StoreStyle> {
  const StoreStyle({
    required this.largeRadius,
    required this.smallRadius,
    required this.surface,
    required this.onSurface,
    required this.cardStyle,
    required this.imageAspectRatio,
    required this.sectionGap,
    required this.uppercaseHeadings,
  });

  factory StoreStyle.from(ThemeSettings s) => StoreStyle(
        largeRadius: s.corners.large,
        smallRadius: s.corners.small,
        surface: StorefrontTheme.surface(s),
        onSurface: StorefrontTheme.text(s),
        cardStyle: s.cardStyle,
        imageAspectRatio: s.imageShape.aspectRatio,
        sectionGap: s.spacing.gap,
        uppercaseHeadings: s.uppercaseHeadings,
      );

  /// The surrounding storefront theme's style, or the default theme's
  /// outside one (a widget test, say).
  static StoreStyle of(BuildContext context) =>
      Theme.of(context).extension<StoreStyle>() ??
      StoreStyle.from(const ThemeSettings());

  final double largeRadius;
  final double smallRadius;
  final Color surface;
  final Color onSurface;
  final CardStyle cardStyle;
  final double imageAspectRatio;
  final double sectionGap;
  final bool uppercaseHeadings;

  /// A faint line in the text color, for outlined cards and dividers.
  Color get hairline => onSurface.withValues(alpha: 0.12);

  /// A box on the page in this style: [StoreStyle.surface], with the
  /// theme's outline or shadow.
  BoxDecoration panel({double? radius, Color? color}) => BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(radius ?? largeRadius),
        border: cardStyle == CardStyle.outlined
            ? Border.all(color: hairline)
            : null,
        boxShadow: cardStyle == CardStyle.raised
            ? const [
                BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 16,
                    offset: Offset(0, 6)),
              ]
            : null,
      );

  ProductCardStyle get productCard => ProductCardStyle(
        color: surface,
        foreground: onSurface,
        radius: largeRadius,
        border: cardStyle == CardStyle.outlined
            ? BorderSide(color: hairline)
            : BorderSide.none,
        elevation: cardStyle == CardStyle.raised ? 3 : 0,
        imageAspectRatio: imageAspectRatio,
      );

  /// A section title in this style.
  String heading(String text) => uppercaseHeadings ? text.toUpperCase() : text;
  TextStyle? headingStyle(TextStyle? base) => uppercaseHeadings
      ? base?.copyWith(
          letterSpacing: 1.6, fontSize: (base.fontSize ?? 24) * 0.8)
      : base;

  @override
  StoreStyle copyWith({
    double? largeRadius,
    double? smallRadius,
    Color? surface,
    Color? onSurface,
    CardStyle? cardStyle,
    double? imageAspectRatio,
    double? sectionGap,
    bool? uppercaseHeadings,
  }) =>
      StoreStyle(
        largeRadius: largeRadius ?? this.largeRadius,
        smallRadius: smallRadius ?? this.smallRadius,
        surface: surface ?? this.surface,
        onSurface: onSurface ?? this.onSurface,
        cardStyle: cardStyle ?? this.cardStyle,
        imageAspectRatio: imageAspectRatio ?? this.imageAspectRatio,
        sectionGap: sectionGap ?? this.sectionGap,
        uppercaseHeadings: uppercaseHeadings ?? this.uppercaseHeadings,
      );

  @override
  StoreStyle lerp(StoreStyle? other, double t) {
    if (other == null) return this;
    return StoreStyle(
      largeRadius: lerpDouble(largeRadius, other.largeRadius, t)!,
      smallRadius: lerpDouble(smallRadius, other.smallRadius, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      cardStyle: t < 0.5 ? cardStyle : other.cardStyle,
      imageAspectRatio:
          lerpDouble(imageAspectRatio, other.imageAspectRatio, t)!,
      sectionGap: lerpDouble(sectionGap, other.sectionGap, t)!,
      uppercaseHeadings: t < 0.5 ? uppercaseHeadings : other.uppercaseHeadings,
    );
  }
}
