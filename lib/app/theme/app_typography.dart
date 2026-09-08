/// THE CARGO / LEDGER TYPE SYSTEM
/// ---------------------------------------------------------------------
/// Two families, two jobs:
///
/// "Cargo" (Fraunces) is the display face — warm, characterful serif
/// used ONLY for the moments Sellora wants to feel human: onboarding
/// headlines, empty states, the seller's first "You're live" moment.
/// It never appears in dense UI chrome.
///
/// "Ledger" (Inter) is the body/UI face — the workhorse for buttons,
/// forms, prices, order tables and anything data-dense. It's legible
/// at small sizes across the buyer, seller and admin portals alike.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  static TextTheme get textTheme => TextTheme(
        // Cargo (display) — headlines & hero moments only.
        displayLarge: GoogleFonts.fraunces(
          fontSize: 40,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          height: 1.1,
          color: AppColors.ink,
        ),
        displayMedium: GoogleFonts.fraunces(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          height: 1.15,
          color: AppColors.ink,
        ),
        displaySmall: GoogleFonts.fraunces(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: AppColors.ink,
        ),

        // Ledger (body/UI) — everything else.
        headlineSmall: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.ink,
          height: 1.4,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.ink,
          height: 1.4,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.slate,
          height: 1.35,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.cloud,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.slate,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.slate,
        ),
      );

  /// Price treatment — used wherever money appears. Kept in one place so
  /// prices always look the same across buyer/seller/admin.
  static TextStyle price({double size = 18, Color? color}) => GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.ink,
        letterSpacing: -0.2,
      );

  /// Manifest tag / order-id treatment — a distinct tracked-out label
  /// used for SKUs and order codes. Deliberately not monospace.
  static TextStyle manifestCode({Color? color}) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: color ?? AppColors.slate,
      );
}
