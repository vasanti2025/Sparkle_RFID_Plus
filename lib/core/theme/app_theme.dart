import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.workSurface,
      colorScheme: const ColorScheme.light(
        primary: AppColors.charcoal,
        onPrimary: AppColors.white,
        secondary: AppColors.goldText,
        onSecondary: AppColors.white,
        surface: AppColors.workSurface,
        onSurface: AppColors.charcoal,
      ),
    );
    final inter = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.charcoal,
      displayColor: AppColors.charcoal,
    );
    return base.copyWith(
      textTheme: inter.copyWith(
        headlineMedium: inter.headlineMedium?.copyWith(
          fontSize: AppTypography.heading,
          fontWeight: FontWeight.w600,
          height: 1.12,
        ),
        bodyLarge: inter.bodyLarge?.copyWith(
          fontSize: AppTypography.body,
          height: 1.5,
        ),
        labelLarge: inter.labelLarge?.copyWith(
          fontSize: AppTypography.label,
          fontWeight: FontWeight.w600,
        ),
      ),
      primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
    );
  }
}
