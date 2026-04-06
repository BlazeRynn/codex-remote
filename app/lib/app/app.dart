import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../screens/thread_list_screen.dart';
import '../services/app_preferences_controller.dart';
import '../services/app_preferences_store.dart';
import '../services/bridge_config_store.dart';
import 'app_strings.dart';
import 'theme.dart';

class CodexMobileApp extends StatefulWidget {
  const CodexMobileApp({
    super.key,
    required this.configStore,
    this.preferencesStore,
  });

  final BridgeConfigStore configStore;
  final AppPreferencesStore? preferencesStore;

  @override
  State<CodexMobileApp> createState() => _CodexMobileAppState();
}

class _CodexMobileAppState extends State<CodexMobileApp> {
  late final AppPreferencesController _preferencesController;

  @override
  void initState() {
    super.initState();
    _preferencesController = AppPreferencesController(
      widget.preferencesStore ?? SharedPrefsAppPreferencesStore(),
    );
    unawaited(_preferencesController.load());
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
              context.strings.text('Codex Control', 'Codex 控制台'),
          home: ThreadListScreen(
            configStore: widget.configStore,
            preferencesController: _preferencesController,
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
