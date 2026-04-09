import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bridge_config.dart';

typedef EndpointProbe = Future<bool> Function(String baseUrl);

abstract class BridgeConfigStore {
  Future<BridgeConfig> load();

  Future<void> save(BridgeConfig config);
}

class SharedPrefsBridgeConfigStore implements BridgeConfigStore {
  SharedPrefsBridgeConfigStore({EndpointProbe? endpointProbe})
    : _endpointProbe = endpointProbe ?? _defaultEndpointProbe;

  static const _baseUrlKey = 'bridge.base_url';
  static const _authTokenKey = 'bridge.auth_token';
  static const _eventsPathKey = 'bridge.events_path';
  final EndpointProbe _endpointProbe;

  @override
  Future<BridgeConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBaseUrl = prefs.getString(_baseUrlKey)?.trim() ?? '';
    final savedAuthToken = prefs.getString(_authTokenKey) ?? '';
    final savedEventsPath = prefs.getString(_eventsPathKey)?.trim() ?? '';

    final resolvedBaseUrl = await _resolveBaseUrl(savedBaseUrl);

    return BridgeConfig(
      baseUrl: resolvedBaseUrl,
      authToken: savedAuthToken,
      eventsPath: savedEventsPath.isEmpty
          ? BridgeConfig.defaultEventsPath
          : savedEventsPath,
    );
  }

  @override
  Future<void> save(BridgeConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, config.baseUrl.trim());
    await prefs.setString(_authTokenKey, config.authToken.trim());
    await prefs.setString(_eventsPathKey, config.eventsPath.trim());
  }

  Future<String> _resolveBaseUrl(String savedBaseUrl) async {
    if (BridgeConfig.isLegacyBridgeBaseUrl(savedBaseUrl)) {
      return await _preferredLocalBaseUrl();
    }

    if (savedBaseUrl.isEmpty) {
      return await _preferredLocalBaseUrl();
    }

    if (BridgeConfig.isLocalDirectBaseUrl(savedBaseUrl)) {
      final mirrorBaseUrl = BridgeConfig.defaultMirrorBaseUrl();
      if (await _endpointProbe(mirrorBaseUrl)) {
        return mirrorBaseUrl;
      }
    }

    return savedBaseUrl;
  }

  Future<String> _preferredLocalBaseUrl() async {
    final mirrorBaseUrl = BridgeConfig.defaultMirrorBaseUrl();
    if (await _endpointProbe(mirrorBaseUrl)) {
      return mirrorBaseUrl;
    }
    return BridgeConfig.defaultDirectBaseUrl();
  }

  static Future<bool> _defaultEndpointProbe(String baseUrl) async {
    try {
      final uri = Uri.parse(baseUrl);
      final port = uri.hasPort
          ? uri.port
          : switch (uri.scheme) {
              'wss' || 'https' => 443,
              _ => 80,
            };
      final socket = await Socket.connect(
        uri.host,
        port,
        timeout: const Duration(milliseconds: 300),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
