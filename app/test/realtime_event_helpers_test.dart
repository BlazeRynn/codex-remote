import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/bridge_realtime_client.dart';
import 'package:mobile/services/realtime_event_helpers.dart';

void main() {
  test('realtimeEventDeltaText reads string deltas from app-server events', () {
    final event = BridgeRealtimeEvent(
      type: 'agent.message.delta',
      description: 'Assistant response streaming',
      receivedAt: DateTime.utc(2026, 4, 5, 7, 0),
      raw: {
        'method': 'item/agentMessage/delta',
        'params': {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'item-1',
          'delta': 'Hello',
        },
      },
    );

    expect(realtimeEventTurnId(event), 'turn-1');
    expect(realtimeEventItemId(event), 'item-1');
    expect(realtimeEventDeltaText(event), 'Hello');
  });

  test('realtimeEventDeltaText joins list-based deltas', () {
    final event = BridgeRealtimeEvent(
      type: 'agent.message.delta',
      description: 'Assistant response streaming',
      receivedAt: DateTime.utc(2026, 4, 5, 7, 0),
      raw: {
        'method': 'item/agentMessage/delta',
        'params': {
          'delta': [
            {'text': 'Hello'},
            ' ',
            {'value': 'world'},
          ],
        },
      },
    );

    expect(realtimeEventDeltaText(event), 'Hello world');
  });

  test('realtimeEventThreadStatusType reads active status updates', () {
    final event = BridgeRealtimeEvent(
      type: 'thread.status',
      description: 'Thread status changed to active',
      receivedAt: DateTime.utc(2026, 4, 5, 7, 0),
      raw: {
        'method': 'thread/status/changed',
        'params': {
          'threadId': 'thread-1',
          'status': {'type': 'active'},
        },
      },
    );

    expect(realtimeEventThreadStatusType(event), 'active');
  });

  test('realtime helpers fall back to nested turn identifiers', () {
    final event = BridgeRealtimeEvent(
      type: 'agent.message.delta',
      description: 'Assistant response streaming',
      receivedAt: DateTime.utc(2026, 4, 5, 7, 0),
      raw: {
        'method': 'item/agentMessage/delta',
        'params': {
          'turn': {'id': 'turn-2', 'threadId': 'thread-2'},
          'item': {'turnId': 'turn-2'},
          'delta': 'Hi',
        },
      },
    );

    expect(realtimeEventThreadId(event), 'thread-2');
    expect(realtimeEventTurnId(event), 'turn-2');
  });

  test('realtimeEventRequestId reads resolved pending request ids', () {
    final event = BridgeRealtimeEvent(
      type: 'server.request.resolved',
      description: 'Pending request req-3 resolved',
      receivedAt: DateTime.utc(2026, 4, 5, 7, 0),
      raw: {
        'method': 'serverRequest/resolved',
        'threadId': 'thread-3',
        'requestId': 'req-3',
        'params': {'threadId': 'thread-3', 'requestId': 'req-3'},
      },
    );

    expect(realtimeEventThreadId(event), 'thread-3');
    expect(realtimeEventRequestId(event), 'req-3');
  });
}
