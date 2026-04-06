import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_typography.dart';

ThemeData buildDesktopWorkspaceTheme(ThemeData base, {Locale? locale}) {
  final isDark = base.brightness == Brightness.dark;
  final colorScheme = isDark
      ? const ColorScheme.dark(
          primary: Color(0xFF75BEFF),
          onPrimary: Color(0xFF07121F),
          secondary: Color(0xFF4EC9B0),
          onSecondary: Color(0xFF041411),
          tertiary: Color(0xFF89D185),
          onTertiary: Color(0xFF091408),
          error: Color(0xFFFF7B72),
          onError: Color(0xFF2A0E0A),
          surface: Color(0xFF181B20),
          onSurface: Color(0xFFE6EDF3),
        )
      : const ColorScheme.light(
          primary: Color(0xFF0D5CAB),
          onPrimary: Colors.white,
          secondary: Color(0xFF0F766E),
          onSecondary: Colors.white,
          tertiary: Color(0xFF557A46),
          onTertiary: Colors.white,
          error: Color(0xFFBA1A1A),
          onError: Colors.white,
          surface: Color(0xFFF5F7FB),
          onSurface: Color(0xFF18212B),
        );

  final textTheme = base.textTheme.apply(
    bodyColor: colorScheme.onSurface,
    displayColor: colorScheme.onSurface,
  );

  return applyAppTypography(
    base.copyWith(
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF111317)
          : const Color(0xFFF0F3F8),
      canvasColor: isDark ? const Color(0xFF111317) : const Color(0xFFF0F3F8),
      cardColor: isDark ? const Color(0xFF181B20) : const Color(0xFFF5F7FB),
      dividerColor: isDark ? const Color(0xFF2A2F3A) : const Color(0xFFD7DFEA),
      textTheme: textTheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: isDark
            ? const Color(0xFF111317)
            : const Color(0xFFF0F3F8),
        foregroundColor: colorScheme.onSurface,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: isDark ? const Color(0xFF181B20) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF2A2F3A) : const Color(0xFFD7DFEA),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF2A2F3A) : const Color(0xFFD7DFEA),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary),
        ),
        labelStyle: TextStyle(
          color: isDark ? const Color(0xFFAAB5C3) : const Color(0xFF607080),
        ),
        hintStyle: TextStyle(
          color: isDark ? const Color(0xFF7D8590) : const Color(0xFF7A8897),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primary.withValues(alpha: 0.18);
            }
            return isDark ? const Color(0xFF181B20) : Colors.white;
          }),
          foregroundColor: WidgetStatePropertyAll(colorScheme.onSurface),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: isDark ? const Color(0xFF2A2F3A) : const Color(0xFFD7DFEA),
            ),
          ),
        ),
      ),
    ),
    locale: locale,
  );
}

bool useDesktopWorkspaceShell(BuildContext context) {
  return switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      } &&
      MediaQuery.sizeOf(context).width >= 1180;
}

Color panelBackgroundColor(ThemeData theme) {
  if (theme.brightness == Brightness.dark) {
    return const Color(0xFF181B20);
  }
  return theme.colorScheme.surface;
}

Color mutedPanelBackgroundColor(ThemeData theme) {
  if (theme.brightness == Brightness.dark) {
    return const Color(0xFF13161B);
  }
  return theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.46);
}

Color borderColor(ThemeData theme) {
  if (theme.brightness == Brightness.dark) {
    return theme.dividerColor;
  }
  return Colors.black.withValues(alpha: 0.05);
}

Color selectionFillColor(ThemeData theme) {
  if (theme.brightness == Brightness.dark) {
    return theme.colorScheme.primary.withValues(alpha: 0.14);
  }
  return theme.colorScheme.primary.withValues(alpha: 0.10);
}

Color secondaryTextColor(ThemeData theme) {
  if (theme.brightness == Brightness.dark) {
    return const Color(0xFFAAB5C3);
  }
  return Colors.black.withValues(alpha: 0.62);
}

double panelRadius(ThemeData theme) {
  return theme.brightness == Brightness.dark ? 18 : 28;
}
