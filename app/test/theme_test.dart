import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/app/theme.dart';
import 'package:mobile/app/workspace_theme.dart';

void main() {
  test('light app theme uses the refreshed bright palette', () {
    final theme = buildAppTheme(Brightness.light);

    expect(theme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
    expect(theme.colorScheme.primary, const Color(0xFF2563EB));
    expect(theme.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(theme.colorScheme.surfaceContainerHighest, const Color(0xFFEEF4FA));
    expect(theme.dividerColor, const Color(0xFFD9E2EC));
    expect(theme.inputDecorationTheme.fillColor, const Color(0xFFFDFEFF));
  });

  test(
    'desktop workspace light theme keeps panel hierarchy and readable borders',
    () {
      final theme = buildDesktopWorkspaceTheme(buildAppTheme(Brightness.light));

      expect(theme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
      expect(panelBackgroundColor(theme), const Color(0xFFFFFFFF));
      expect(
        mutedPanelBackgroundColor(theme),
        const Color(0xFFEEF4FA).withValues(alpha: 0.78),
      );
      expect(borderColor(theme), const Color(0xFFD9E2EC));
      expect(secondaryTextColor(theme), const Color(0xFF5B6B7F));
      expect(panelRadius(theme), 24);
    },
  );
}
