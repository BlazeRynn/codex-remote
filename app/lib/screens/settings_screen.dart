import 'package:flutter/material.dart';

import '../app/app_strings.dart';
import '../models/app_preferences.dart';
import '../models/bridge_config.dart';
import '../services/app_preferences_controller.dart';
import '../services/bridge_config_store.dart';

class BridgeSettingsScreen extends StatefulWidget {
  const BridgeSettingsScreen({
    super.key,
    required this.initialConfig,
    required this.configStore,
    required this.preferencesController,
  });

  final BridgeConfig initialConfig;
  final BridgeConfigStore configStore;
  final AppPreferencesController preferencesController;

  @override
  State<BridgeSettingsScreen> createState() => _BridgeSettingsScreenState();
}

class _BridgeSettingsScreenState extends State<BridgeSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrlController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initialAppServerConfig = widget.initialConfig.baseUrl.trim().isEmpty
        ? BridgeConfig.localDefault(authToken: widget.initialConfig.authToken)
        : widget.initialConfig;
    _baseUrlController = TextEditingController(
      text: initialAppServerConfig.baseUrl,
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final config = BridgeConfig(
      baseUrl: _baseUrlController.text.trim(),
      authToken: '',
      eventsPath: BridgeConfig.defaultEventsPath,
    );

    setState(() {
      _saving = true;
    });

    await widget.configStore.save(config);
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(config);
  }

  Future<void> _resetToLocalAppServer() async {
    setState(() {
      _saving = true;
    });

    await widget.configStore.save(BridgeConfig.empty);
    final config = await widget.configStore.load();
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(config);
  }

  String? _validateBaseUrl(String? value) {
    final strings = context.strings;
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return strings.text('Base URL is required.', '必须填写基础 URL。');
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      final example =
          '${BridgeConfig.defaultMirrorBaseUrl()} '
          '(${strings.text('proxy mirror', 'proxy 镜像')}) / '
          '${BridgeConfig.defaultDirectBaseUrl()}';
      return strings.text(
        'Enter a full app-server URL such as $example.',
        '请输入完整的 app-server URL，例如 $example。',
      );
    }

    if (uri.scheme != 'http' &&
        uri.scheme != 'https' &&
        uri.scheme != 'ws' &&
        uri.scheme != 'wss') {
      return strings.text(
        'Only ws, wss, http, and https URLs are supported.',
        '仅支持 ws、wss、http 和 https URL。',
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final serverFieldsEnabled = !_saving;
    final themePreference = widget.preferencesController.themePreference;
    final languagePreference = widget.preferencesController.languagePreference;

    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Codex settings', 'Codex 设置'))),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                strings.text(
                  'Connect the app to your local Codex app-server. The local proxy mirror is preferred when available.',
                  '将应用连接到本地 Codex app-server。可用时优先使用本地 proxy mirror。',
                ),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('Appearance', '外观'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              SegmentedButton<AppThemePreference>(
                segments: [
                  ButtonSegment(
                    value: AppThemePreference.system,
                    label: Text(strings.text('System', '跟随系统')),
                    icon: const Icon(Icons.brightness_auto_outlined),
                  ),
                  ButtonSegment(
                    value: AppThemePreference.light,
                    label: Text(strings.text('Light', '明亮')),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: AppThemePreference.dark,
                    label: Text(strings.text('Dark', '暗黑')),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {themePreference},
                onSelectionChanged: _saving
                    ? null
                    : (selection) {
                        widget.preferencesController.setThemePreference(
                          selection.first,
                        );
                        setState(() {});
                      },
              ),
              const SizedBox(height: 18),
              Text(
                strings.text('Language', '语言'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              SegmentedButton<AppLanguagePreference>(
                segments: [
                  ButtonSegment(
                    value: AppLanguagePreference.system,
                    label: Text(strings.text('System', '跟随系统')),
                    icon: const Icon(Icons.translate_outlined),
                  ),
                  ButtonSegment(
                    value: AppLanguagePreference.english,
                    label: Text(strings.text('English', '英文')),
                    icon: const Icon(Icons.language_outlined),
                  ),
                  ButtonSegment(
                    value: AppLanguagePreference.chinese,
                    label: Text(strings.text('Chinese', '中文')),
                    icon: const Icon(Icons.language_outlined),
                  ),
                ],
                selected: {languagePreference},
                onSelectionChanged: _saving
                    ? null
                    : (selection) {
                        widget.preferencesController.setLanguagePreference(
                          selection.first,
                        );
                        setState(() {});
                      },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _baseUrlController,
                decoration: InputDecoration(
                  labelText: strings.text(
                    'Codex app-server URL',
                    'Codex app-server URL',
                  ),
                  hintText:
                      '${BridgeConfig.defaultMirrorBaseUrl()} / '
                      '${BridgeConfig.defaultDirectBaseUrl()}',
                ),
                keyboardType: TextInputType.url,
                validator: _validateBaseUrl,
                enabled: serverFieldsEnabled,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? strings.text('Saving...', '保存中...')
                      : strings.text('Save configuration', '保存配置'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _saving ? null : _resetToLocalAppServer,
                child: Text(
                  strings.text('Reset to local app-server', '重置为本地 app-server'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
