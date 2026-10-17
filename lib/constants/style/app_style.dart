import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData lightThemeFor(
    Color seedColor, {
    double fontScale = 1,
    double cardRadius = 20,
    double buttonRadius = 16,
    Color backgroundColor = const Color(0xFFF7F8FC),
  }) => _createTheme(
    seedColor,
    Brightness.light,
    fontScale: fontScale,
    cardRadius: cardRadius,
    buttonRadius: buttonRadius,
    backgroundColor: backgroundColor,
  );

  static ThemeData darkThemeFor(
    Color seedColor, {
    double fontScale = 1,
    double cardRadius = 20,
    double buttonRadius = 16,
    Color backgroundColor = const Color(0xFF111318),
  }) => _createTheme(
    seedColor,
    Brightness.dark,
    fontScale: fontScale,
    cardRadius: cardRadius,
    buttonRadius: buttonRadius,
    backgroundColor: backgroundColor,
  );

  static final ThemeData lightTheme = lightThemeFor(AppThemeColors.defaultSeed);

  static final ThemeData darkTheme = darkThemeFor(AppThemeColors.defaultSeed);

  static ThemeData _createTheme(
    Color seedColor,
    Brightness brightness, {
    required double fontScale,
    required double cardRadius,
    required double buttonRadius,
    required Color backgroundColor,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final baseTextTheme = Typography.material2021().black.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? backgroundColor
          : Color.lerp(backgroundColor, const Color(0xFF111318), 0.94),
      textTheme: _scaleTextTheme(baseTextTheme, fontScale),
      appBarTheme: AppBarTheme(
        backgroundColor: brightness == Brightness.light
            ? backgroundColor
            : Color.lerp(backgroundColor, const Color(0xFF111318), 0.94),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1B1D23),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1B1D23),
        indicatorColor: colorScheme.secondaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? const Color(0xFFF4F5F9)
            : const Color(0xFF252831),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: brightness == Brightness.light
            ? const Color(0xFFE8EAF0)
            : const Color(0xFF30333B),
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
    );
  }

  static TextTheme _scaleTextTheme(TextTheme theme, double scale) {
    TextStyle? scaleStyle(TextStyle? style) {
      final size = style?.fontSize;
      if (style == null || size == null) return style;
      return style.copyWith(fontSize: size * scale);
    }

    return theme.copyWith(
      displayLarge: scaleStyle(theme.displayLarge),
      displayMedium: scaleStyle(theme.displayMedium),
      displaySmall: scaleStyle(theme.displaySmall),
      headlineLarge: scaleStyle(theme.headlineLarge),
      headlineMedium: scaleStyle(theme.headlineMedium),
      headlineSmall: scaleStyle(theme.headlineSmall),
      titleLarge: scaleStyle(theme.titleLarge),
      titleMedium: scaleStyle(theme.titleMedium),
      titleSmall: scaleStyle(theme.titleSmall),
      bodyLarge: scaleStyle(theme.bodyLarge),
      bodyMedium: scaleStyle(theme.bodyMedium),
      bodySmall: scaleStyle(theme.bodySmall),
      labelLarge: scaleStyle(theme.labelLarge),
      labelMedium: scaleStyle(theme.labelMedium),
      labelSmall: scaleStyle(theme.labelSmall),
    );
  }
}

abstract final class AppThemeColors {
  static const Color defaultSeed = Color(0xFF5267D8);
}
