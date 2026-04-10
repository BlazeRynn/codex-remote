import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/app_preferences.dart';
import 'package:mobile/services/app_preferences_controller.dart';
import 'package:mobile/services/app_preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AppPreferences normalizes archived thread ids', () {
    final preferences = AppPreferences(
      archivedThreadIds: {' thread-1 ', '', 'thread-1', 'thread-2'},
    );

    expect(preferences.archivedThreadIds, {'thread-1', 'thread-2'});
    expect(preferences.isThreadArchived('thread-1'), isTrue);
    expect(preferences.isThreadArchived(' thread-2 '), isTrue);
    expect(preferences.isThreadArchived('thread-3'), isFalse);
  });

  test('AppPreferences enables all notification toggles by default', () {
    final preferences = AppPreferences();

    expect(preferences.notifyOnApprovalRequest, isTrue);
    expect(preferences.notifyOnTurnCompleted, isTrue);
    expect(preferences.notifyOnRealtimeError, isTrue);
  });

  test(
    'SharedPrefsAppPreferencesStore loads and saves archived thread ids',
    () async {
      SharedPreferences.setMockInitialValues({
        'app.theme': 'dark',
        'app.language': 'chinese',
        'app.notifyOnApprovalRequest': false,
        'app.notifyOnTurnCompleted': true,
        'app.notifyOnRealtimeError': false,
        'app.archivedThreadIds': ['thread-b', 'thread-a'],
      });
      final store = SharedPrefsAppPreferencesStore();

      final loaded = await store.load();

      expect(loaded.theme, AppThemePreference.dark);
      expect(loaded.language, AppLanguagePreference.chinese);
      expect(loaded.notifyOnApprovalRequest, isFalse);
      expect(loaded.notifyOnTurnCompleted, isTrue);
      expect(loaded.notifyOnRealtimeError, isFalse);
      expect(loaded.archivedThreadIds, {'thread-a', 'thread-b'});

      await store.save(
        AppPreferences(
          theme: AppThemePreference.light,
          language: AppLanguagePreference.english,
          notifyOnApprovalRequest: true,
          notifyOnTurnCompleted: false,
          notifyOnRealtimeError: true,
          archivedThreadIds: {'thread-2', 'thread-1'},
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app.theme'), 'light');
      expect(prefs.getString('app.language'), 'english');
      expect(prefs.getBool('app.notifyOnApprovalRequest'), isTrue);
      expect(prefs.getBool('app.notifyOnTurnCompleted'), isFalse);
      expect(prefs.getBool('app.notifyOnRealtimeError'), isTrue);
      expect(prefs.getStringList('app.archivedThreadIds'), [
        'thread-1',
        'thread-2',
      ]);
    },
  );

  test('AppPreferencesController archives and restores threads', () async {
    final store = _MemoryPreferencesStore();
    final controller = AppPreferencesController(store);

    await controller.load();
    await controller.archiveThread(' thread-1 ');

    expect(controller.isThreadArchived('thread-1'), isTrue);
    expect(store.savedPreferences.archivedThreadIds, {'thread-1'});

    await controller.toggleThreadArchived('thread-1');

    expect(controller.isThreadArchived('thread-1'), isFalse);
    expect(store.savedPreferences.archivedThreadIds, isEmpty);
  });

  test('AppPreferencesController updates notification toggles', () async {
    final store = _MemoryPreferencesStore();
    final controller = AppPreferencesController(store);

    await controller.load();
    await controller.setNotifyOnApprovalRequest(false);
    await controller.setNotifyOnTurnCompleted(false);
    await controller.setNotifyOnRealtimeError(false);

    expect(controller.notifyOnApprovalRequest, isFalse);
    expect(controller.notifyOnTurnCompleted, isFalse);
    expect(controller.notifyOnRealtimeError, isFalse);

    expect(store.savedPreferences.notifyOnApprovalRequest, isFalse);
    expect(store.savedPreferences.notifyOnTurnCompleted, isFalse);
    expect(store.savedPreferences.notifyOnRealtimeError, isFalse);
  });
}

class _MemoryPreferencesStore implements AppPreferencesStore {
  AppPreferences savedPreferences = AppPreferences();

  @override
  Future<AppPreferences> load() async {
    return savedPreferences;
  }

  @override
  Future<void> save(AppPreferences preferences) async {
    savedPreferences = preferences;
  }
}
