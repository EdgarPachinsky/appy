import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0xFF15151B);
  static const card = Color(0xFF1A1A21);
  static const cardHover = Color(0xFF1F1F27);
  static const tile = Color(0xFF111116);
  static const border = Color(0xFF282832);
  static const borderStrong = Color(0xFF363642);
  static const lavender = Color(0xFFDCD0F4);
  static const lavenderInk = Color(0xFF241E38);
  static const text = Color(0xFFEDEBF5);
  static const muted = Color(0xFF8C899C);
  static const faint = Color(0xFF5E5C6C);
  static const green = Color(0xFF6EE7A8);
  static const amber = Color(0xFFF5C46B);
  static const red = Color(0xFFF58A8A);
}

const monoFont = 'Menlo';

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.surface,
    dividerColor: AppColors.border,
    splashFactory: NoSplash.splashFactory,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.lavender,
      onPrimary: AppColors.lavenderInk,
      secondary: AppColors.lavender,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.red,
    ),
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.lavender,
      selectionColor: Color(0x55DCD0F4),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: AppColors.borderStrong,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.borderStrong),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(6),
    ),
  );
}
