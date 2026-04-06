import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_preferences.dart';

abstract class AppPreferencesStore {
  Future<AppPreferences> load();

  Future<void> save(AppPreferences preferences);
}

class SharedPrefsAppPreferencesStore implements AppPreferencesStore {
  static const _themeKey = 'app.theme';
  static const _languageKey = 'app.language';
  static const _archivedThreadIdsKey = 'app.archivedThreadIds';

  @override
  Future<AppPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferences(
      theme: _parseTheme(prefs.getString(_themeKey)),
      language: _parseLanguage(prefs.getString(_languageKey)),
      archivedThreadIds: Set<String>.from(
        prefs.getStringList(_archivedThreadIdsKey) ?? const <String>[],
      ),
    );
  }

  @override
  Future<void> save(AppPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    final archivedThreadIds = preferences.archivedThreadIds.toList()
      ..sort((left, right) => left.compareTo(right));
    await prefs.setString(_themeKey, preferences.theme.name);
    await prefs.setString(_languageKey, preferences.language.name);
    await prefs.setStringList(_archivedThreadIdsKey, archivedThreadIds);
  }

  AppThemePreference _parseTheme(String? value) {
    return switch (value) {
      'light' => AppThemePreference.light,
      'dark' => AppThemePreference.dark,
      _ => AppThemePreference.system,
    };
  }

  AppLanguagePreference _parseLanguage(String? value) {
    return switch (value) {
      'english' => AppLanguagePreference.english,
      'chinese' => AppLanguagePreference.chinese,
      _ => AppLanguagePreference.system,
    };
  }
}
