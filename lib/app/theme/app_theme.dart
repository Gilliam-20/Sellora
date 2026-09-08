import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_metrics.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.mist,
      primaryColor: AppColors.cargoNavy,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.cargoNavy,
        secondary: AppColors.manifestGold,
        tertiary: AppColors.horizonTeal,
        error: AppColors.danger,
        surface: AppColors.cloud,
      ),
      textTheme: AppTypography.textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.mist,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.ink),
        titleTextStyle: AppTypography.textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cloud,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.hairline),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.manifestGold,
          foregroundColor: AppColors.ink,
          disabledBackgroundColor: AppColors.slateLight,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          textStyle: AppTypography.textTheme.titleSmall,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.cargoNavy,
          side: const BorderSide(color: AppColors.cargoNavy, width: 1.4),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          textStyle: AppTypography.textTheme.titleSmall,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.cargoNavy,
          textStyle: AppTypography.textTheme.titleSmall,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cloud,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
        hintStyle: AppTypography.textTheme.bodyMedium
            ?.copyWith(color: AppColors.slateLight),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.stub + 8),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.stub + 8),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.stub + 8),
          borderSide: const BorderSide(color: AppColors.cargoNavy, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.stub + 8),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.mist,
        side: const BorderSide(color: AppColors.hairline),
        labelStyle: AppTypography.textTheme.labelMedium,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control)),
      ),
      dividerTheme: const DividerThemeData(
          color: AppColors.hairline, thickness: 1, space: 1),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.cargoNavy,
        selectedItemColor: AppColors.manifestGold,
        unselectedItemColor: AppColors.slateLight,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: AppTypography.textTheme.labelSmall
            ?.copyWith(color: AppColors.manifestGold),
        unselectedLabelStyle: AppTypography.textTheme.labelSmall,
        showUnselectedLabels: true,
        elevation: 0,
      ),
      splashFactory: InkRipple.splashFactory,
    );
  }
}
