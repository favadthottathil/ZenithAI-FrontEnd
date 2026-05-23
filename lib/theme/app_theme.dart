import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF6366F1); // Indigo
  static const Color secondaryColor = Color(0xFF8B5CF6); // Violet
  static const Color backgroundColor = Color(0xFF0F172A); // Slate 900
  static const Color surfaceColor = Color(0xFF1E293B); // Slate 800
  static const Color textColor = Color(0xFFF8FAFC); // Slate 50
  static const Color mutedTextColor = Color(0xFF94A3B8); // Slate 400

  static ThemeData darkTheme = ThemeData.dark().copyWith(
    scaffoldBackgroundColor: backgroundColor,
    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: surfaceColor,
    ),
    textTheme: GoogleFonts.interTextTheme().copyWith(
      bodyLarge: GoogleFonts.inter(color: textColor),
      bodyMedium: GoogleFonts.inter(color: textColor),
      titleLarge: GoogleFonts.inter(fontWeight: FontWeight.bold, color: textColor),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
  );
}
