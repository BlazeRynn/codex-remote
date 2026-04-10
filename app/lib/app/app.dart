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

  @override
  void initState() {
    super.initState();
    _preferencesController = AppPreferencesController(
      widget.preferencesStore ?? SharedPrefsAppPreferencesStore(),
    );
    _notificationService =
        widget.notificationService ?? LocalNotificationService();
    unawaited(_preferencesController.load());
    unawaited(_notificationService.initialize());
  }

  @override
  void dispose() {
    _preferencesController.dispose();
    super.dispose();
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
