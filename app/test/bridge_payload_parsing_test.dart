import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/bridge_config.dart';
import 'package:mobile/models/bridge_health.dart';
import 'package:mobile/models/codex_thread_item.dart';
import 'package:mobile/models/codex_thread_summary.dart';
import 'package:mobile/services/bridge_config_store.dart';
import 'package:mobile/services/bridge_realtime_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('CodexThreadSummary parses normalized bridge payloads', () {
    final summary = CodexThreadSummary.fromJson({
      'id': 'thread-1',
      'title': 'Inspect desktop bridge output',
      'status': 'idle',
      'preview': 'Verify list/detail/item payloads',
      'cwd': r'E:\workspace\codex-control',
      'updatedAt': '2026-04-04T02:55:43Z',
      'itemCount': 171,
      'provider': 'openai',
    });

    expect(summary.id, 'thread-1');
    expect(summary.status, 'idle');
    expect(summary.cwd, r'E:\workspace\codex-control');
    expect(summary.itemCount, 171);
    expect(summary.updatedAt, DateTime.parse('2026-04-04T02:55:43Z'));
    expect(summary.provider, 'openai');
  });

  test(
    'CodexThreadItem tolerates missing item timestamps from bridge payloads',
    () {
      final item = CodexThreadItem.fromJson({
        'id': 'item-1',
        'type': 'agent.message',
        'title': 'Assistant message (final_answer)',
        'body': 'Bridge payload looks good.',
        'status': 'final_answer',
        'actor': 'assistant',
      });

      expect(item.type, 'agent.message');
      expect(item.actor, 'assistant');
      expect(item.createdAt, isNull);
    },
  );

  test('BridgeHealth parses reachable online bridge state', () {
    final health = BridgeHealth.fromJson({
      'ok': true,
      'status': 'online',
      'version': '0.1.0',
      'message': 'Desktop bridge',
    });

    expect(health.reachable, isTrue);
    expect(health.status, 'online');
    expect(health.label, 'online');
  });

  test('BridgeRealtimeEvent parses JSON websocket payloads', () {
    final event = BridgeRealtimeEvent.fromPayload(
      '{"type":"bridge.connected","message":"Connected to desktop bridge","threadId":"thread-1","timestamp":"2026-04-04T02:00:00Z","occurredAt":"2026-04-04T03:00:00Z"}',
    );

    expect(event.type, 'bridge.connected');
    expect(event.description, 'Connected to desktop bridge');
    expect(event.raw['threadId'], 'thread-1');
    expect(event.receivedAt, DateTime.parse('2026-04-04T03:00:00Z'));
  });

  test('BridgeRealtimeEvent parses millisecond epoch timestamps as UTC', () {
    final event = BridgeRealtimeEvent.fromPayload({
      'type': 'bridge.connected',
      'message': 'Connected to desktop bridge',
      'timestamp': 1700000124000,
    });

    expect(event.receivedAt, DateTime.parse('2023-11-14T22:15:24Z'));
    expect(event.receivedAt.isUtc, isTrue);
  });

  test('CodexThreadSummary parses epoch timestamps as UTC', () {
    final summary = CodexThreadSummary.fromJson({
      'id': 'thread-2',
      'title': 'Epoch timestamp thread',
      'status': 'idle',
      'preview': 'Verify UTC epoch parsing',
      'updatedAt': 1700000124,
    });

    expect(summary.updatedAt, DateTime.parse('2023-11-14T22:15:24Z'));
    expect(summary.updatedAt?.isUtc, isTrue);
  });

  test(
    'BridgeConfig resolves app-server websocket uri and preserves query parameters',
    () {
      const config = BridgeConfig(
        baseUrl: 'https://bridge.example.com/api/',
        authToken: 'secret',
        eventsPath: '/events?source=mobile',
      );

      final uri = config.resolveEventsUri(threadId: 'thread-1');

      expect(uri.toString(), 'wss://bridge.example.com/api/?threadId=thread-1');
      expect(config.headers['Authorization'], 'Bearer secret');
    },
  );

  test(
    'SharedPrefsBridgeConfigStore defaults bridge mode to the local machine',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPrefsBridgeConfigStore(
        endpointProbe: (baseUrl) async =>
            baseUrl == BridgeConfig.defaultMirrorBaseUrl(),
      );

      final config = await store.load();

      expect(config.mode, BridgeDataSourceMode.bridge);
      expect(config.baseUrl, BridgeConfig.defaultMirrorBaseUrl());
      expect(config.eventsPath, BridgeConfig.defaultEventsPath);
      expect(config.isConfigured, isTrue);
    },
  );

  test(
    'SharedPrefsBridgeConfigStore migrates old local 8766 default to proxy mirror when available',
    () async {
      SharedPreferences.setMockInitialValues({
        'bridge.base_url': BridgeConfig.defaultDirectBaseUrl(),
      });
      final store = SharedPrefsBridgeConfigStore(
        endpointProbe: (baseUrl) async =>
            baseUrl == BridgeConfig.defaultMirrorBaseUrl(),
      );

      final config = await store.load();

      expect(config.baseUrl, BridgeConfig.defaultMirrorBaseUrl());
    },
  );

  test(
    'SharedPrefsBridgeConfigStore keeps direct local app-server when proxy mirror is unavailable',
    () async {
      SharedPreferences.setMockInitialValues({
        'bridge.base_url': BridgeConfig.defaultDirectBaseUrl(),
      });
      final store = SharedPrefsBridgeConfigStore(
        endpointProbe: (_) async => false,
      );

      final config = await store.load();

      expect(config.baseUrl, BridgeConfig.defaultDirectBaseUrl());
    },
  );
}
