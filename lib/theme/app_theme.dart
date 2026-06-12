import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF10A37F); // Emerald Green
  static const Color secondaryColor = Color(0xFF0D9488); // Teal Accent
  static const Color backgroundColor = Color(0xFF171717); // Deep Charcoal
  static const Color surfaceColor = Color(0xFF212121); // Dark Gray Surface
  static const Color textColor = Color(0xFFECECF1); // Clean Off-White
  static const Color mutedTextColor = Color(0xFFB4B4B4); // Muted Gray

  static ThemeData darkTheme = ThemeData.dark().copyWith(
    scaffoldBackgroundColor: backgroundColor,
    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: surfaceColor,
    ),
    textTheme: GoogleFonts.interTextTheme().copyWith(
      bodyLarge: GoogleFonts.inter(
        color: textColor,
        fontSize: 16,
        height: 1.6,
        letterSpacing: 0.1,
      ),
      bodyMedium: GoogleFonts.inter(
        color: mutedTextColor,
        fontSize: 14,
        height: 1.5,
      ),
      titleLarge: GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        color: textColor,
        fontSize: 20,
        letterSpacing: -0.2,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: textColor),
    ),
  );
}
