import 'package:flutter/material.dart';

import 'app_typography.dart';

ThemeData buildAppTheme(Brightness brightness, {Locale? locale}) {
  const seed = Color(0xFF0F766E);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
  );

  if (brightness == Brightness.dark) {
    final colorScheme = base.colorScheme.copyWith(
      surface: const Color(0xFF171A1F),
      surfaceContainerHighest: const Color(0xFF242933),
      onSurface: const Color(0xFFE7EDF5),
    );

    return applyAppTypography(
      base.copyWith(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF101217),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Color(0xFF171A1F),
        ),
        cardColor: const Color(0xFF171A1F),
        dividerColor: const Color(0xFF2A303A),
      ),
      locale: locale,
    );
  }

  final colorScheme = base.colorScheme.copyWith(
    surface: const Color(0xFFF5F4EE),
    surfaceContainerHighest: const Color(0xFFE6E5DB),
  );

  return applyAppTypography(
    base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF3F1E8),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    ),
    locale: locale,
  );
}
