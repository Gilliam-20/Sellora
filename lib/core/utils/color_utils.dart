import 'package:flutter/material.dart';

/// Parses a `#RRGGBB`/`RRGGBB` hex string into a [Color]. Returns `null` for
/// null, empty, or malformed input rather than throwing — callers treat a
/// missing/invalid store color as "use the default theme color."
Color? hexToColor(String? hex) {
  if (hex == null) return null;
  final cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.length != 6) return null;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

/// Inverse of [hexToColor] — uppercase `#RRGGBB`, dropping alpha.
String colorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
