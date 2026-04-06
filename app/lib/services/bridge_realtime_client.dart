import 'dart:convert';

import '../utils/json_utils.dart';

class BridgeRealtimeEvent {
  const BridgeRealtimeEvent({
    required this.type,
    required this.description,
    required this.receivedAt,
    required this.raw,
  });

  final String type;
  final String description;
  final DateTime receivedAt;
  final Map<String, dynamic> raw;

  factory BridgeRealtimeEvent.fromPayload(dynamic payload) {
    final fallbackReceivedAt = DateTime.now();

    if (payload is String) {
      try {
        final decoded = jsonDecode(payload);
        final map = asJsonMap(decoded);
        if (map.isNotEmpty) {
          return BridgeRealtimeEvent._fromMap(
            map,
            fallbackReceivedAt: fallbackReceivedAt,
          );
        }
      } on FormatException {
        return BridgeRealtimeEvent(
          type: 'text',
          description: payload,
          receivedAt: fallbackReceivedAt,
          raw: {'message': payload},
        );
      }

      return BridgeRealtimeEvent(
        type: 'text',
        description: payload,
        receivedAt: fallbackReceivedAt,
        raw: {'message': payload},
      );
    }

    return BridgeRealtimeEvent._fromMap(
      asJsonMap(payload),
      fallbackReceivedAt: fallbackReceivedAt,
    );
  }

  factory BridgeRealtimeEvent._fromMap(
    Map<String, dynamic> map, {
    DateTime? fallbackReceivedAt,
  }) {
    final encoder = const JsonEncoder.withIndent('  ');
    final description = readString(map, const [
      'message',
      'summary',
      'text',
      'title',
      'detail',
    ], fallback: map.isEmpty ? 'No event payload' : encoder.convert(map));

    return BridgeRealtimeEvent(
      type: readString(map, const ['type', 'op', 'event'], fallback: 'event'),
      description: description,
      receivedAt:
          readDate(map, const ['occurredAt', 'createdAt', 'timestamp']) ??
          fallbackReceivedAt ??
          DateTime.now(),
      raw: map,
    );
  }
}
