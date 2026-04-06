import 'bridge_realtime_client.dart';

void insertRealtimeEvent(
  List<BridgeRealtimeEvent> events,
  BridgeRealtimeEvent event, {
  int limit = 20,
}) {
  events.add(event);
  events.sort((left, right) => right.receivedAt.compareTo(left.receivedAt));

  if (events.length > limit) {
    events.removeRange(limit, events.length);
  }
}
