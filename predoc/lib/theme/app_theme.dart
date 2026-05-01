import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────
// APP COLORS — Day 12 Design System
// primary:  soft purple  (#7C3AED)
// good:     #4CAF50
// moderate: #FFC107
// risk:     #F44336
// bg:       #FAFAFA
// ─────────────────────────────────────────────────────────────

class AppColors {
  // Primary purple palette
  static const Color primary      = Color(0xFF7C3AED);
  static const Color primaryDark  = Color(0xFF5B21B6);
  static const Color primaryLight = Color(0xFFEDE9FE);
  static const Color primaryMid   = Color(0xFFA78BFA);

  // Day 12: Semantic status colours
  static const Color good         = Color(0xFF4CAF50);  // green
  static const Color moderate     = Color(0xFFFFC107);  // amber
  static const Color risk         = Color(0xFFF44336);  // red

  // Background — Day 12: #FAFAFA
  static const Color background     = Color(0xFFFAFAFA);
  static const Color backgroundCard = Color(0xFFFFFFFF);

  // Accent (kept for live-monitoring banner)
  static const Color accent      = Color(0xFFFBBF24);
  static const Color accentGreen = Color(0xFF4CAF50);   // aligned to `good`
  static const Color accentRed   = Color(0xFFF44336);   // aligned to `risk`

  // Text
  static const Color textDark  = Color(0xFF1E1B4B);
  static const Color textMid   = Color(0xFF4C1D95);
  static const Color textLight = Color(0xFF8B5CF6);
  static const Color textMuted = Color(0xFF9CA3AF);

  // Utility
  static const Color divider = Color(0xFFE9D5FF);
  static const Color shadow  = Color(0x1A7C3AED);

  // Day 12: spacing / radius helpers exposed as constants
  static const double radiusCard   = 16.0;
  static const double paddingH     = 20.0;
  static const double paddingV     = 16.0;
  static const double sectionGap   = 24.0;
}

class AppTheme {
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        surface: AppColors.background,
      ),
      scaffoldBackgroundColor: AppColors.background,
      textTheme: GoogleFonts.nunitoTextTheme().copyWith(
        displayLarge: GoogleFonts.nunito(
          fontSize: 36,
          fontWeight: FontWeight.w900,
          color: AppColors.textDark,
        ),
        displayMedium: GoogleFonts.nunito(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: AppColors.textDark,
        ),
        headlineLarge: GoogleFonts.nunito(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppColors.textDark,
        ),
        headlineMedium: GoogleFonts.nunito(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ),
        titleLarge: GoogleFonts.nunito(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ),
        bodyLarge: GoogleFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
        bodyMedium: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
        ),
        labelLarge: GoogleFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          textStyle: GoogleFonts.nunito(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
          elevation: 2,
          shadowColor: AppColors.shadow,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SHARED DECORATION HELPERS (Day 12)
// ─────────────────────────────────────────────────────────────

BoxDecoration appCardDecoration({
  Color? color,
  double? radius,
  Border? border,
}) =>
    BoxDecoration(
      color: color ?? AppColors.backgroundCard,
      borderRadius: BorderRadius.circular(radius ?? AppColors.radiusCard),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
      border: border,
    );
