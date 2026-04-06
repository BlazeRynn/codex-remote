import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

ThemeData applyAppTypography(ThemeData theme, {Locale? locale}) {
  final uiFamily = _uiFontFamily();
  final uiFallbacks = _uiFontFallbacks(locale);
  final textTheme = _applyUiTypography(
    theme.textTheme,
    family: uiFamily,
    fallbacks: uiFallbacks,
  );
  final primaryTextTheme = _applyUiTypography(
    theme.primaryTextTheme,
    family: uiFamily,
    fallbacks: uiFallbacks,
  );

  return theme.copyWith(
    textTheme: textTheme,
    primaryTextTheme: primaryTextTheme,
  );
}

TextStyle appCodeTextStyle(TextStyle? base, {Locale? locale}) {
  return (base ?? const TextStyle()).copyWith(
    fontFamily: _codeFontFamily(),
    fontFamilyFallback: _codeFontFallbacks(locale),
    height: base?.height ?? 1.5,
  );
}

TextTheme _applyUiTypography(
  TextTheme theme, {
  required String family,
  required List<String> fallbacks,
}) {
  return theme.copyWith(
    displayLarge: _withUiFamily(theme.displayLarge, family, fallbacks),
    displayMedium: _withUiFamily(theme.displayMedium, family, fallbacks),
    displaySmall: _withUiFamily(theme.displaySmall, family, fallbacks),
    headlineLarge: _withUiFamily(theme.headlineLarge, family, fallbacks),
    headlineMedium: _withUiFamily(theme.headlineMedium, family, fallbacks),
    headlineSmall: _withUiFamily(theme.headlineSmall, family, fallbacks),
    titleLarge: _withUiFamily(theme.titleLarge, family, fallbacks),
    titleMedium: _withUiFamily(theme.titleMedium, family, fallbacks),
    titleSmall: _withUiFamily(theme.titleSmall, family, fallbacks),
    bodyLarge: _withUiFamily(theme.bodyLarge, family, fallbacks),
    bodyMedium: _withUiFamily(theme.bodyMedium, family, fallbacks),
    bodySmall: _withUiFamily(theme.bodySmall, family, fallbacks),
    labelLarge: _withUiFamily(theme.labelLarge, family, fallbacks),
    labelMedium: _withUiFamily(theme.labelMedium, family, fallbacks),
    labelSmall: _withUiFamily(theme.labelSmall, family, fallbacks),
  );
}

TextStyle? _withUiFamily(
  TextStyle? style,
  String family,
  List<String> fallbacks,
) {
  if (style == null) {
    return null;
  }
  return style.copyWith(fontFamily: family, fontFamilyFallback: fallbacks);
}

String _uiFontFamily() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'Segoe UI',
    TargetPlatform.macOS => 'Helvetica Neue',
    TargetPlatform.iOS => 'Helvetica Neue',
    TargetPlatform.linux => 'Noto Sans',
    TargetPlatform.android => 'Roboto',
    TargetPlatform.fuchsia => 'Roboto',
  };
}

List<String> _uiFontFallbacks(Locale? locale) {
  final localeSpecific =
      locale?.languageCode.toLowerCase().startsWith('zh') == true
      ? const [
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'PingFang SC',
          'Hiragino Sans GB',
          'Noto Sans CJK SC',
          'Noto Sans SC',
          'Source Han Sans SC',
        ]
      : const [
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'PingFang SC',
          'Hiragino Sans GB',
          'Noto Sans CJK SC',
          'Noto Sans SC',
          'Source Han Sans SC',
        ];

  return [
    ...localeSpecific,
    switch (defaultTargetPlatform) {
      TargetPlatform.windows => 'Arial',
      TargetPlatform.macOS => 'Arial Unicode MS',
      TargetPlatform.iOS => 'Arial Unicode MS',
      TargetPlatform.linux => 'Ubuntu',
      TargetPlatform.android => 'Noto Sans',
      TargetPlatform.fuchsia => 'Noto Sans',
    },
  ];
}

String _codeFontFamily() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'Cascadia Code',
    TargetPlatform.macOS => 'SF Mono',
    TargetPlatform.iOS => 'SF Mono',
    TargetPlatform.linux => 'DejaVu Sans Mono',
    TargetPlatform.android => 'Roboto Mono',
    TargetPlatform.fuchsia => 'Roboto Mono',
  };
}

List<String> _codeFontFallbacks(Locale? locale) {
  final cjkFallbacks =
      locale?.languageCode.toLowerCase().startsWith('zh') == true
      ? const [
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'PingFang SC',
          'Noto Sans CJK SC',
          'Noto Sans SC',
        ]
      : const [
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'PingFang SC',
          'Noto Sans CJK SC',
          'Noto Sans SC',
        ];

  return [
    switch (defaultTargetPlatform) {
      TargetPlatform.windows => 'Consolas',
      TargetPlatform.macOS => 'Menlo',
      TargetPlatform.iOS => 'Menlo',
      TargetPlatform.linux => 'Liberation Mono',
      TargetPlatform.android => 'Droid Sans Mono',
      TargetPlatform.fuchsia => 'Courier New',
    },
    ...cjkFallbacks,
    'Courier New',
    'monospace',
  ];
}
