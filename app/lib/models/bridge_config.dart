import 'dart:io';

enum BridgeDataSourceMode { bridge, demo }

class BridgeConfig {
  const BridgeConfig({
    required this.baseUrl,
    required this.authToken,
    this.eventsPath = '/events',
    this.mode = BridgeDataSourceMode.bridge,
  });

  static const empty = BridgeConfig(baseUrl: '', authToken: '');
  static const defaultEventsPath = '/events';
  static const defaultDesktopDirectBaseUrl = 'ws://127.0.0.1:8766';
  static const defaultAndroidEmulatorDirectBaseUrl = 'ws://10.0.2.2:8766';
  static const defaultDesktopMirrorBaseUrl = 'ws://127.0.0.1:8767';
  static const defaultAndroidEmulatorMirrorBaseUrl = 'ws://10.0.2.2:8767';
  static const legacyDesktopBridgeBaseUrl = 'http://127.0.0.1:8788';
  static const legacyAndroidBridgeBaseUrl = 'http://10.0.2.2:8788';
  static const legacyMockDesktopBridgeBaseUrl = 'http://127.0.0.1:8787';
  static const legacyMockAndroidBridgeBaseUrl = 'http://10.0.2.2:8787';

  final String baseUrl;
  final String authToken;
  final String eventsPath;
  final BridgeDataSourceMode mode;

  static String defaultBridgeBaseUrl() {
    return defaultDirectBaseUrl();
  }

  static String defaultDirectBaseUrl() {
    return Platform.isAndroid
        ? defaultAndroidEmulatorDirectBaseUrl
        : defaultDesktopDirectBaseUrl;
  }

  static String defaultMirrorBaseUrl() {
    return Platform.isAndroid
        ? defaultAndroidEmulatorMirrorBaseUrl
        : defaultDesktopMirrorBaseUrl;
  }

  static bool isLegacyBridgeBaseUrl(String value) {
    final normalized = _normalizeBaseUrl(value);
    return normalized == _normalizeBaseUrl(legacyDesktopBridgeBaseUrl) ||
        normalized == _normalizeBaseUrl(legacyAndroidBridgeBaseUrl) ||
        normalized == _normalizeBaseUrl(legacyMockDesktopBridgeBaseUrl) ||
        normalized == _normalizeBaseUrl(legacyMockAndroidBridgeBaseUrl);
  }

  static bool isLocalDirectBaseUrl(String value) {
    final normalized = _normalizeBaseUrl(value);
    return normalized == _normalizeBaseUrl(defaultDesktopDirectBaseUrl) ||
        normalized == _normalizeBaseUrl(defaultAndroidEmulatorDirectBaseUrl);
  }

  static BridgeConfig localDefault({
    String authToken = '',
    String eventsPath = defaultEventsPath,
  }) {
    return BridgeConfig(
      baseUrl: defaultBridgeBaseUrl(),
      authToken: authToken,
      eventsPath: eventsPath,
    );
  }

  bool get usesDemoData => mode == BridgeDataSourceMode.demo;

  bool get isConfigured => usesDemoData || baseUrl.trim().isNotEmpty;

  Map<String, String> get headers {
    final token = authToken.trim();
    if (token.isEmpty) {
      return const {};
    }

    return {'Authorization': 'Bearer $token'};
  }

  BridgeConfig copyWith({
    String? baseUrl,
    String? authToken,
    String? eventsPath,
    BridgeDataSourceMode? mode,
  }) {
    return BridgeConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      authToken: authToken ?? this.authToken,
      eventsPath: eventsPath ?? this.eventsPath,
      mode: mode ?? this.mode,
    );
  }

  Uri resolveHttpUri(String path) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    final rpcUri = resolveRpcUri();
    final httpScheme = switch (rpcUri.scheme) {
      'wss' => 'https',
      'ws' => 'http',
      _ => rpcUri.scheme,
    };
    return rpcUri.replace(
      scheme: httpScheme,
      path: rpcUri.resolve(normalized).path,
      queryParameters: rpcUri.resolve(normalized).queryParameters,
    );
  }

  Uri resolveRpcUri() {
    final uri = Uri.parse(baseUrl);
    final scheme = switch (uri.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      'ws' || 'wss' => uri.scheme,
      _ => uri.scheme,
    };
    return uri.replace(scheme: scheme);
  }

  Uri resolveEventsUri({String? threadId}) {
    final uri = resolveRpcUri();
    final queryParameters = Map<String, String>.from(uri.queryParameters);
    if (threadId != null && threadId.isNotEmpty) {
      queryParameters['threadId'] = threadId;
    }

    return uri.replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }

  Map<String, String> toJson() {
    return {
      'baseUrl': baseUrl,
      'authToken': authToken,
      'eventsPath': eventsPath,
      'mode': mode.name,
    };
  }

  factory BridgeConfig.fromJson(Map<String, Object?> json) {
    return BridgeConfig(
      baseUrl: (json['baseUrl'] as String?) ?? '',
      authToken: (json['authToken'] as String?) ?? '',
      eventsPath: (json['eventsPath'] as String?) ?? '/events',
      mode: _parseMode(json['mode'] as String?),
    );
  }

  static BridgeDataSourceMode _parseMode(String? value) {
    return switch (value) {
      'demo' => BridgeDataSourceMode.demo,
      _ => BridgeDataSourceMode.bridge,
    };
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return trimmed.toLowerCase();
    }
    final normalizedPath = uri.path == '/' ? '' : uri.path;
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: normalizedPath,
          query: null,
          fragment: null,
        )
        .toString()
        .toLowerCase();
  }
}
