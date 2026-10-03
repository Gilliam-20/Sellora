import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/models/store_design.dart';
import '../../storefront/design/storefront_theme.dart';

/// A theme's thumbnail (TODO §19): a miniature storefront drawn from its
/// [ThemeSettings] (header, hero, a row of product cards), so it always
/// shows what applying the theme does, with no image files to keep in
/// step.
class ThemeThumbnail extends StatelessWidget {
  const ThemeThumbnail({super.key, required this.settings, this.label = 'Aa'});
  final ThemeSettings settings;

  /// Stands in for the store name in the header.
  final String label;

  static const _width = 240.0;
  static const _height = 150.0;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final accent = StorefrontTheme.accent(s);
    final onAccent = StorefrontTheme.onColor(accent);
    final text = StorefrontTheme.text(s);
    final style = StoreStyle.from(s);
    // Everything is drawn at 240×150 and scaled, so radii and gaps are
    // a third of the real ones.
    final large = style.largeRadius / 3;
    final gap = style.sectionGap / 4;
    final button = switch (s.buttonShape) {
      ButtonShape.pill => BorderRadius.circular(20),
      ButtonShape.rounded => BorderRadius.circular(3),
      ButtonShape.square => BorderRadius.zero,
    };

    Widget bar(double width, Color color, [double height = 4]) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        );

    Widget card() => Expanded(
          child: Container(
            decoration: style.panel(radius: large),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: style.imageAspectRatio,
                  child: ColoredBox(color: text.withValues(alpha: 0.12)),
                ),
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(30, text.withValues(alpha: 0.5), 3),
                      const SizedBox(height: 2),
                      bar(16, text, 3),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        child: Container(
          width: _width,
          height: _height,
          color: StorefrontTheme.background(s),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 22,
                child: Align(
                  alignment: s.centeredHeader
                      ? Alignment.center
                      : Alignment.centerLeft,
                  child: Text(label,
                      maxLines: 1,
                      style: _font(s.headingFont,
                          TextStyle(fontSize: 11, color: text, height: 1))),
                ),
              ),
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                    color: accent, borderRadius: BorderRadius.circular(large)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.uppercaseHeadings ? 'NEW SEASON' : 'New season',
                        style: _font(
                            s.headingFont,
                            TextStyle(
                                fontSize: 10,
                                color: onAccent,
                                height: 1,
                                letterSpacing: s.uppercaseHeadings ? 1 : 0))),
                    const SizedBox(height: 5),
                    Container(
                      width: 34,
                      height: 9,
                      decoration:
                          BoxDecoration(color: onAccent, borderRadius: button),
                    ),
                  ],
                ),
              ),
              SizedBox(height: gap),
              // Tall (portrait) cards run off the bottom, as on a page.
              Expanded(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    maxHeight: double.infinity,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        card(),
                        const SizedBox(width: 5),
                        card(),
                        const SizedBox(width: 5),
                        card(),
                        const SizedBox(width: 5),
                        card(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The theme's font when it loads; the app's otherwise.
  static TextStyle _font(String family, TextStyle base) {
    try {
      return GoogleFonts.getFont(family, textStyle: base);
    } catch (_) {
      return base;
    }
  }
}
