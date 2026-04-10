import 'package:flutter/material.dart';

enum AppThemePreference { system, light, dark }

enum AppLanguagePreference { system, english, chinese }

class AppPreferences {
  AppPreferences({
    this.theme = AppThemePreference.system,
    this.language = AppLanguagePreference.system,
    this.notifyOnApprovalRequest = true,
    this.notifyOnTurnCompleted = true,
    this.notifyOnRealtimeError = true,
    Set<String> archivedThreadIds = const <String>{},
  }) : archivedThreadIds = Set.unmodifiable(
         _normalizeArchivedThreadIds(archivedThreadIds),
       );

  final AppThemePreference theme;
  final AppLanguagePreference language;
  final bool notifyOnApprovalRequest;
  final bool notifyOnTurnCompleted;
  final bool notifyOnRealtimeError;
  final Set<String> archivedThreadIds;

  ThemeMode get themeMode {
    return switch (theme) {
      AppThemePreference.light => ThemeMode.light,
      AppThemePreference.dark => ThemeMode.dark,
      AppThemePreference.system => ThemeMode.system,
    };
  }

  Locale? get locale {
    return switch (language) {
      AppLanguagePreference.english => const Locale('en'),
      AppLanguagePreference.chinese => const Locale('zh'),
      AppLanguagePreference.system => null,
    };
  }

  bool isThreadArchived(String threadId) {
    final normalized = _normalizeThreadId(threadId);
    return normalized != null && archivedThreadIds.contains(normalized);
  }

  AppPreferences copyWith({
    AppThemePreference? theme,
    AppLanguagePreference? language,
    bool? notifyOnApprovalRequest,
    bool? notifyOnTurnCompleted,
    bool? notifyOnRealtimeError,
    Set<String>? archivedThreadIds,
  }) {
    return AppPreferences(
      theme: theme ?? this.theme,
      language: language ?? this.language,
      notifyOnApprovalRequest:
          notifyOnApprovalRequest ?? this.notifyOnApprovalRequest,
      notifyOnTurnCompleted:
          notifyOnTurnCompleted ?? this.notifyOnTurnCompleted,
      notifyOnRealtimeError:
          notifyOnRealtimeError ?? this.notifyOnRealtimeError,
      archivedThreadIds: archivedThreadIds ?? this.archivedThreadIds,
    );
  }
}

Set<String> _normalizeArchivedThreadIds(Iterable<String> values) {
  final normalized = <String>{};
  for (final value in values) {
    final threadId = _normalizeThreadId(value);
    if (threadId != null) {
      normalized.add(threadId);
    }
  }
  return normalized;
}

String? _normalizeThreadId(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
