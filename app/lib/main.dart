import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'services/app_preferences_store.dart';
import 'services/bridge_config_store.dart';
import 'services/local_notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    CodexMobileApp(
      configStore: SharedPrefsBridgeConfigStore(),
      preferencesStore: SharedPrefsAppPreferencesStore(),
      notificationService: LocalNotificationService(),
    ),
  );
}
