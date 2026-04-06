import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/codex_thread_item.dart';
import 'package:mobile/services/thread_item_timestamps.dart';

void main() {
  test('extractAppServerItemTimestamp prefers item timestamp fields', () {
    final timestamp = extractAppServerItemTimestamp(
      {'createdAt': '2026-04-05T12:34:56.000Z'},
      const {'createdAt': '2026-04-05T01:02:03.000Z'},
    );

    expect(timestamp, DateTime.parse('2026-04-05T12:34:56.000Z'));
  });

  test('extractAppServerItemTimestamp falls back to turn timestamps', () {
    final timestamp = extractAppServerItemTimestamp(const {}, const {
      'timestamp': 1775390400,
    });

    expect(timestamp, DateTime.utc(2026, 4, 5, 12));
  });

  test(
    'resolveThreadItemDisplayTimestamp falls back to raw turn timestamp',
    () {
      final item = CodexThreadItem(
        id: 'agent-1',
        type: 'agent.message',
        title: 'Assistant message',
        body: 'hello',
        status: 'completed',
        actor: 'assistant',
        raw: const {'turnCreatedAt': '2026-04-05T03:21:00.000Z'},
      );

      expect(
        resolveThreadItemDisplayTimestamp(item),
        DateTime.parse('2026-04-05T03:21:00.000Z'),
      );
    },
  );

  test(
    'extractAppServerItemTimestamp parses nested timestamp objects from snapshot payloads',
    () {
      final timestamp = extractAppServerItemTimestamp(const {
        'timestamp': {'seconds': 1775390400, 'nanos': 500000000},
      }, const {});

      expect(timestamp, DateTime.utc(2026, 4, 5, 12, 0, 0, 500));
    },
  );

  test(
    'resolveThreadItemDisplayTimestamp parses nested raw turn timestamp objects',
    () {
      final item = CodexThreadItem(
        id: 'agent-2',
        type: 'agent.message',
        title: 'Assistant message',
        body: 'hello again',
        status: 'completed',
        actor: 'assistant',
        raw: const {
          'turnTimestamp': {'seconds': 1775390400, 'nanos': 500000000},
        },
      );

      expect(
        resolveThreadItemDisplayTimestamp(item),
        DateTime.utc(2026, 4, 5, 12, 0, 0, 500),
      );
    },
  );
}
