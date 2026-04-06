import 'bridge_realtime_client.dart';
import '../utils/json_utils.dart';

Map<String, dynamic> realtimeEventParams(BridgeRealtimeEvent event) {
  return asJsonMap(event.raw['params']);
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _extractThreadId(Map<String, dynamic> payload) {
  final thread = asJsonMap(payload['thread']);
  final turn = asJsonMap(payload['turn']);
  final item = asJsonMap(payload['item']);
  final conversation = asJsonMap(payload['conversation']);
  final value =
      _nonEmpty(payload['threadId']) ??
      _nonEmpty(payload['conversationId']) ??
      _nonEmpty(thread['id']) ??
      _nonEmpty(turn['threadId']) ??
      _nonEmpty(conversation['id']) ??
      _nonEmpty(item['threadId']);
  return value;
}

String? realtimeEventMethod(BridgeRealtimeEvent event) {
  return _nonEmpty(event.raw['method']);
}

Map<String, dynamic> realtimeEventItem(BridgeRealtimeEvent event) {
  final params = realtimeEventParams(event);
  return asJsonMap(params['item']);
}

String? realtimeEventThreadId(BridgeRealtimeEvent event) {
  return _extractThreadId(event.raw) ??
      _extractThreadId(realtimeEventParams(event));
}

String? realtimeEventTurnId(BridgeRealtimeEvent event) {
  final params = realtimeEventParams(event);
  final turn = asJsonMap(params['turn']);
  final item = realtimeEventItem(event);
  final value =
      (params['turnId'] ?? turn['id'] ?? item['turnId'])?.toString().trim() ??
      '';
  return value.isEmpty ? null : value;
}

String? realtimeEventItemId(BridgeRealtimeEvent event) {
  final params = realtimeEventParams(event);
  final item = realtimeEventItem(event);
  final value =
      (event.raw['itemId'] ?? params['itemId'] ?? item['id'])
          ?.toString()
          .trim() ??
      '';
  return value.isEmpty ? null : value;
}

String? realtimeEventItemType(BridgeRealtimeEvent event) {
  final item = realtimeEventItem(event);
  final params = realtimeEventParams(event);
  return _nonEmpty(item['type']) ?? _nonEmpty(params['itemType']);
}

String? realtimeEventItemPhase(BridgeRealtimeEvent event) {
  final item = realtimeEventItem(event);
  final params = realtimeEventParams(event);
  return _nonEmpty(item['phase']) ?? _nonEmpty(params['phase']);
}

String? realtimeEventItemStatus(BridgeRealtimeEvent event) {
  final item = realtimeEventItem(event);
  final params = realtimeEventParams(event);
  return _nonEmpty(item['status']) ?? _nonEmpty(params['status']);
}

String? realtimeEventDeltaText(BridgeRealtimeEvent event) {
  final params = realtimeEventParams(event);
  final delta = params['delta'];

  if (delta is String) {
    return delta;
  }

  if (delta is Map || delta is Map<String, dynamic>) {
    final text = readString(asJsonMap(delta), const [
      'text',
      'value',
      'content',
    ]);
    return text.isEmpty ? null : text;
  }

  if (delta is List) {
    final buffer = StringBuffer();
    for (final entry in delta) {
      if (entry is String) {
        buffer.write(entry);
        continue;
      }

      final text = readString(asJsonMap(entry), const [
        'text',
        'value',
        'content',
      ]);
      if (text.isNotEmpty) {
        buffer.write(text);
      }
    }
    final value = buffer.toString();
    return value.isEmpty ? null : value;
  }

  final text = readString(params, const ['text']);
  return text.isEmpty ? null : text;
}

String? realtimeEventTranscriptText(BridgeRealtimeEvent event) {
  final params = realtimeEventParams(event);
  final item = realtimeEventItem(event);

  final directText = readString(params, const [
    'transcript',
    'text',
    'content',
    'value',
  ]);
  if (directText.isNotEmpty) {
    return directText;
  }

  final itemText = readString(item, const [
    'text',
    'transcript',
    'content',
    'value',
  ]);
  return itemText.isEmpty ? null : itemText;
}

String? realtimeEventThreadStatusType(BridgeRealtimeEvent event) {
  final params = realtimeEventParams(event);
  final status = asJsonMap(params['status']);
  final nested = readString(status, const ['type', 'status']);
  final value = nested.isNotEmpty
      ? nested
      : readString(params, const ['status']);
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String? realtimeEventRequestId(BridgeRealtimeEvent event) {
  final params = realtimeEventParams(event);
  final value =
      (event.raw['requestId'] ?? params['requestId'])?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

DateTime realtimeEventOccurredAt(BridgeRealtimeEvent event) {
  return readDate(event.raw, const ['occurredAt']) ??
      readDate(realtimeEventParams(event), const [
        'occurredAt',
        'timestamp',
        'createdAt',
        'updatedAt',
      ]) ??
      event.receivedAt;
}
