import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/app.dart';
import 'services/app_preferences_store.dart';
import 'services/bridge_config_store.dart';
import 'services/local_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    await WakelockPlus.enable();
  }
  runApp(
    CodexMobileApp(
      configStore: SharedPrefsBridgeConfigStore(),
      preferencesStore: SharedPrefsAppPreferencesStore(),
      notificationService: LocalNotificationService(),
    ),
  );
}
