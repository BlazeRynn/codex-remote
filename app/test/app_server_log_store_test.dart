import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/app_server_log_store.dart';

void main() {
  test('records searchable payloads and trims older entries', () {
    final store = AppServerLogStore(maxEntries: 2);

    store.record(
      kind: AppServerLogEntryKind.request,
      direction: AppServerLogDirection.outbound,
      rpcId: '1',
      method: 'thread/list',
      payload: {'threadId': 'thread-alpha'},
    );

    expect(store.entries, hasLength(1));
    expect(store.entries.single.matchesQuery('THREAD-ALPHA'), isTrue);
    expect(store.entries.single.matchesQuery('thread/list'), isTrue);

    store.record(
      kind: AppServerLogEntryKind.response,
      direction: AppServerLogDirection.inbound,
      rpcId: '1',
      method: 'thread/list',
      payload: {
        'data': ['ok'],
      },
    );
    store.record(
      kind: AppServerLogEntryKind.error,
      direction: AppServerLogDirection.inbound,
      rpcId: '2',
      method: 'thread/read',
      previewText: 'boom',
      payload: {'message': 'boom'},
    );

    expect(store.entries, hasLength(2));
    expect(store.entries.first.kind, AppServerLogEntryKind.response);
    expect(store.entries.last.kind, AppServerLogEntryKind.error);
  });

  test('formats json payloads for inspection', () {
    final store = AppServerLogStore(maxEntries: 1);

    store.record(
      kind: AppServerLogEntryKind.notification,
      direction: AppServerLogDirection.inbound,
      method: 'thread/started',
      payload: {
        'thread': {'id': 'thread-123'},
      },
    );

    expect(store.entries.single.formattedPayload, contains('"thread"'));
    expect(store.entries.single.formattedPayload, contains('"thread-123"'));
  });
}
