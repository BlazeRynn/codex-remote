import 'package:flutter/material.dart';

import '../models/app_preferences.dart';
import 'app_preferences_store.dart';

class AppPreferencesController extends ChangeNotifier {
  AppPreferencesController(this._store);

  final AppPreferencesStore _store;
  AppPreferences _preferences = AppPreferences();
  bool _loaded = false;

  AppPreferences get preferences => _preferences;
  ThemeMode get themeMode => _preferences.themeMode;
  Locale? get locale => _preferences.locale;
  AppThemePreference get themePreference => _preferences.theme;
  AppLanguagePreference get languagePreference => _preferences.language;
  Set<String> get archivedThreadIds => _preferences.archivedThreadIds;
  bool get loaded => _loaded;

  Future<void> load() async {
    _preferences = await _store.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemePreference(AppThemePreference value) async {
    if (value == _preferences.theme) {
      return;
    }
    _preferences = _preferences.copyWith(theme: value);
    notifyListeners();
    await _store.save(_preferences);
  }

  Future<void> setLanguagePreference(AppLanguagePreference value) async {
    if (value == _preferences.language) {
      return;
    }
    _preferences = _preferences.copyWith(language: value);
    notifyListeners();
    await _store.save(_preferences);
  }

  bool isThreadArchived(String threadId) {
    return _preferences.isThreadArchived(threadId);
  }

  Future<void> archiveThread(String threadId) async {
    await _setThreadArchived(threadId, archived: true);
  }

  Future<void> unarchiveThread(String threadId) async {
    await _setThreadArchived(threadId, archived: false);
  }

  Future<void> toggleThreadArchived(String threadId) async {
    await _setThreadArchived(threadId, archived: !isThreadArchived(threadId));
  }

  Future<void> _setThreadArchived(
    String threadId, {
    required bool archived,
  }) async {
    final normalized = threadId.trim();
    if (normalized.isEmpty) {
      return;
    }

    final nextArchivedThreadIds = Set<String>.from(
      _preferences.archivedThreadIds,
    );
    final changed = archived
        ? nextArchivedThreadIds.add(normalized)
        : nextArchivedThreadIds.remove(normalized);
    if (!changed) {
      return;
    }

    _preferences = _preferences.copyWith(
      archivedThreadIds: nextArchivedThreadIds,
    );
    notifyListeners();
    await _store.save(_preferences);
  }
}
