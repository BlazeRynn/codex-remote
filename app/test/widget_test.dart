import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/app/app.dart';
import 'package:mobile/models/app_preferences.dart';
import 'package:mobile/models/bridge_config.dart';
import 'package:mobile/services/app_preferences_store.dart';
import 'package:mobile/services/bridge_config_store.dart';

void main() {
  testWidgets('shows app-server setup prompt when config is empty', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      CodexMobileApp(
        configStore: _FakeBridgeConfigStore(BridgeConfig.empty),
        preferencesStore: _FakeAppPreferencesStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open Codex settings'), findsOneWidget);
    expect(find.text('Configure Codex'), findsWidgets);
  });
}

class _FakeBridgeConfigStore implements BridgeConfigStore {
  _FakeBridgeConfigStore(this._config);

  BridgeConfig _config;

  @override
  Future<BridgeConfig> load() async => _config;

  @override
  Future<void> save(BridgeConfig config) async {
    _config = config;
  }
}

class _FakeAppPreferencesStore implements AppPreferencesStore {
  AppPreferences _preferences = AppPreferences();

  @override
  Future<AppPreferences> load() async => _preferences;

  @override
  Future<void> save(AppPreferences preferences) async {
    _preferences = preferences;
  }
}
