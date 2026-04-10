import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../screens/thread_list_screen.dart';
import '../services/app_preferences_controller.dart';
import '../services/app_preferences_store.dart';
import '../services/bridge_config_store.dart';
import '../services/local_notification_service.dart';
import 'app_strings.dart';
import 'theme.dart';

class CodexMobileApp extends StatefulWidget {
  const CodexMobileApp({
    super.key,
    required this.configStore,
    this.preferencesStore,
    this.notificationService,
  });

  final BridgeConfigStore configStore;
  final AppPreferencesStore? preferencesStore;
  final LocalNotificationService? notificationService;

  @override
  State<CodexMobileApp> createState() => _CodexMobileAppState();
}

class _CodexMobileAppState extends State<CodexMobileApp> {
  late final AppPreferencesController _preferencesController;
  late final LocalNotificationService _notificationService;
  late final _AppLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _preferencesController = AppPreferencesController(
      widget.preferencesStore ?? SharedPrefsAppPreferencesStore(),
    );
    _notificationService =
        widget.notificationService ?? LocalNotificationService();
    _lifecycleObserver = _AppLifecycleObserver(_notificationService);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _notificationService.setAppInForeground(_isAppInForeground());
    unawaited(_preferencesController.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _preferencesController.dispose();
    super.dispose();
  }

  bool _isAppInForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _preferencesController,
      builder: (context, _) {
        final themeLocale =
            _preferencesController.locale ??
            WidgetsBinding.instance.platformDispatcher.locale;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light, locale: themeLocale),
          darkTheme: buildAppTheme(Brightness.dark, locale: themeLocale),
          themeMode: _preferencesController.themeMode,
          scrollBehavior: switch (defaultTargetPlatform) {
            TargetPlatform.windows ||
            TargetPlatform.macOS ||
            TargetPlatform.linux => const _StableDesktopScrollBehavior(),
            _ => const MaterialScrollBehavior(),
          },
          locale: _preferencesController.locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          onGenerateTitle: (context) =>
              context.strings.text('Codex Control', 'Codex 鎺у埗鍙?'),
          home: ThreadListScreen(
            configStore: widget.configStore,
            preferencesController: _preferencesController,
            notificationService: _notificationService,
          ),
        );
      },
    );
  }
}

class _AppLifecycleObserver with WidgetsBindingObserver {
  _AppLifecycleObserver(this._notificationService);

  final LocalNotificationService _notificationService;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _notificationService.setAppInForeground(
      state == AppLifecycleState.resumed ||
          state == AppLifecycleState.inactive,
    );
  }
}

class _StableDesktopScrollBehavior extends MaterialScrollBehavior {
  const _StableDesktopScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
