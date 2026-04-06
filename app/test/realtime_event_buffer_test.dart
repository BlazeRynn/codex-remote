import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/bridge_realtime_client.dart';
import 'package:mobile/services/realtime_event_buffer.dart';

void main() {
  test('insertRealtimeEvent keeps events sorted by receivedAt descending', () {
    final events = <BridgeRealtimeEvent>[
      BridgeRealtimeEvent(
        type: 'agent.message',
        description: 'newer',
        receivedAt: DateTime.parse('2026-04-04T03:02:00Z'),
        raw: const {'occurredAt': '2026-04-04T03:02:00Z'},
      ),
    ];

    insertRealtimeEvent(
      events,
      BridgeRealtimeEvent(
        type: 'agent.message',
        description: 'older',
        receivedAt: DateTime.parse('2026-04-04T03:01:00Z'),
        raw: const {'occurredAt': '2026-04-04T03:01:00Z'},
      ),
    );

    insertRealtimeEvent(
      events,
      BridgeRealtimeEvent(
        type: 'agent.message',
        description: 'newest',
        receivedAt: DateTime.parse('2026-04-04T03:03:00Z'),
        raw: const {'occurredAt': '2026-04-04T03:03:00Z'},
      ),
    );

    expect(events.map((event) => event.description).toList(), [
      'newest',
      'newer',
      'older',
    ]);
  });

  test('insertRealtimeEvent truncates to the requested limit', () {
    final events = <BridgeRealtimeEvent>[];

    for (var i = 0; i < 3; i += 1) {
      insertRealtimeEvent(
        events,
        BridgeRealtimeEvent(
          type: 'agent.message',
          description: 'event-$i',
          receivedAt: DateTime.parse('2026-04-04T03:0${i + 1}:00Z'),
          raw: {'occurredAt': '2026-04-04T03:0${i + 1}:00Z'},
        ),
        limit: 2,
      );
    }

    expect(events, hasLength(2));
    expect(events.map((event) => event.description).toList(), [
      'event-2',
      'event-1',
    ]);
  });
}
