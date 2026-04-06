import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/codex_thread_item.dart';
import 'package:mobile/services/bridge_realtime_client.dart';
import 'package:mobile/services/thread_realtime_accumulator.dart';

void main() {
  test('appends assistant deltas onto the same item', () {
    final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');
    accumulator.replaceSnapshot([
      _item(
        id: 'user-1',
        type: 'user.message',
        actor: 'user',
        body: 'hello',
        raw: const {'turnId': 'turn-1'},
      ),
    ]);

    expect(accumulator.apply(_deltaEvent(text: 'Hel')), isTrue);
    expect(accumulator.apply(_deltaEvent(text: 'lo world')), isTrue);

    final items = accumulator.items;
    expect(items, hasLength(2));
    expect(items.last.type, 'agent.message');
    expect(items.last.body, 'Hello world');
    expect(items.last.raw['turnId'], 'turn-1');
    expect(items.last.raw['phase'], 'streaming');
  });

  test(
    'keeps implicit assistant deltas on one item until a new boundary appears',
    () {
      final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

      expect(
        accumulator.apply(_implicitAssistantDeltaEvent(text: 'Hel')),
        isTrue,
      );
      expect(
        accumulator.apply(_implicitAssistantDeltaEvent(text: 'lo again')),
        isTrue,
      );

      final items = accumulator.items;
      expect(items, hasLength(1));
      expect(items.single.type, 'agent.message');
      expect(items.single.body, 'Hello again');
      expect(items.single.raw['turnId'], 'turn-1');
    },
  );

  test('keeps tool output separate from assistant text', () {
    final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

    expect(
      accumulator.apply(
        _notificationEvent(
          method: 'item/started',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'id': 'cmd-1',
              'type': 'commandExecution',
              'command': 'npm test',
              'status': 'in_progress',
            },
          },
        ),
      ),
      isTrue,
    );
    expect(
      accumulator.apply(
        _notificationEvent(
          method: 'item/commandExecution/outputDelta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'cmd-1',
            'delta': 'line 1',
          },
        ),
      ),
      isTrue,
    );
    expect(
      accumulator.apply(
        _notificationEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'agent-1',
            'delta': 'answer',
          },
        ),
      ),
      isTrue,
    );

    final items = accumulator.items;
    expect(items, hasLength(2));
    expect(items[0].type, 'command.execution');
    expect(items[0].body, contains('line 1'));
    expect(items[1].type, 'agent.message');
    expect(items[1].body, 'answer');
  });

  test('starts a new assistant item after tool output in the same turn', () {
    final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

    expect(
      accumulator.apply(_implicitAssistantDeltaEvent(text: 'before tool')),
      isTrue,
    );
    expect(
      accumulator.apply(
        _notificationEvent(
          method: 'item/started',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'id': 'cmd-1',
              'type': 'commandExecution',
              'command': 'rg something',
              'status': 'in_progress',
            },
          },
        ),
      ),
      isTrue,
    );
    expect(
      accumulator.apply(_implicitAssistantDeltaEvent(text: 'after tool')),
      isTrue,
    );

    final items = accumulator.items;
    expect(items, hasLength(3));
    expect(items[0].type, 'agent.message');
    expect(items[0].body, 'before tool');
    expect(items[1].type, 'command.execution');
    expect(items[2].type, 'agent.message');
    expect(items[2].body, 'after tool');
  });

  test(
    'keeps assistant text ahead of a later command when snapshot adds the command',
    () {
      final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

      expect(
        accumulator.apply(_implicitAssistantDeltaEvent(text: 'before tool')),
        isTrue,
      );
      expect(
        accumulator.apply(
          _notificationEvent(
            method: 'item/started',
            params: {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'id': 'cmd-1',
                'type': 'commandExecution',
                'command': 'rg something',
                'status': 'in_progress',
              },
            },
          ),
        ),
        isTrue,
      );

      accumulator.replaceSnapshot([
        _item(
          id: 'cmd-1',
          type: 'command.execution',
          actor: 'assistant',
          body: 'cwd: \nexitCode: n/a',
          raw: const {'turnId': 'turn-1'},
        ),
      ]);

      final items = accumulator.items;
      expect(items, hasLength(2));
      expect(items[0].type, 'agent.message');
      expect(items[0].body, 'before tool');
      expect(items[1].type, 'command.execution');
    },
  );

  test(
    'keeps pre-command assistant text in place when snapshot materializes a new agent item id',
    () {
      final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

      expect(
        accumulator.apply(_implicitAssistantDeltaEvent(text: 'before tool')),
        isTrue,
      );
      expect(
        accumulator.apply(
          _notificationEvent(
            method: 'item/started',
            params: {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'id': 'cmd-1',
                'type': 'commandExecution',
                'command': 'rg something',
                'status': 'in_progress',
              },
            },
          ),
        ),
        isTrue,
      );

      accumulator.replaceSnapshot([
        _item(
          id: 'cmd-1',
          type: 'command.execution',
          actor: 'assistant',
          body: 'cwd: \nexitCode: n/a',
          raw: const {'turnId': 'turn-1'},
        ),
        _item(
          id: 'agent-snapshot',
          type: 'agent.message',
          actor: 'assistant',
          body: 'before tool',
          raw: const {'turnId': 'turn-1', 'phase': 'commentary'},
        ),
      ]);

      final items = accumulator.items;
      expect(items, hasLength(2));
      expect(items[0].id, 'agent-snapshot');
      expect(items[0].type, 'agent.message');
      expect(items[0].body, 'before tool');
      expect(items[1].id, 'cmd-1');
      expect(items[1].type, 'command.execution');
    },
  );

  test(
    'snapshot reconcile drops older streaming overlay for completed turn',
    () {
      final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

      expect(accumulator.apply(_deltaEvent(text: 'streaming body')), isTrue);

      accumulator.replaceSnapshot([
        _item(
          id: 'agent-final',
          type: 'agent.message',
          actor: 'assistant',
          body: 'final body',
          status: 'final_answer',
          raw: const {'turnId': 'turn-1', 'phase': 'final_answer'},
        ),
      ]);

      final items = accumulator.items;
      expect(items, hasLength(1));
      expect(items.single.id, 'agent-final');
      expect(items.single.body, 'final body');
    },
  );

  test(
    'snapshot reconcile drops duplicate assistant overlay when snapshot id differs',
    () {
      final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

      expect(accumulator.apply(_deltaEvent(text: 'same reply')), isTrue);

      accumulator.replaceSnapshot([
        _item(
          id: 'agent-final',
          type: 'agent.message',
          actor: 'assistant',
          body: 'same reply',
          raw: const {'turnId': 'turn-1'},
        ),
      ]);

      final items = accumulator.items;
      expect(items, hasLength(1));
      expect(items.single.id, 'agent-final');
      expect(items.single.body, 'same reply');
    },
  );

  test('does not duplicate transcript updates that resend the full prefix', () {
    final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

    expect(
      accumulator.apply(
        _notificationEvent(
          method: 'thread/realtime/transcriptUpdated',
          type: 'thread.realtime.transcript.updated',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'agent-1',
            'transcript': 'Hel',
          },
        ),
      ),
      isTrue,
    );
    expect(
      accumulator.apply(
        _notificationEvent(
          method: 'thread/realtime/transcriptUpdated',
          type: 'thread.realtime.transcript.updated',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'agent-1',
            'transcript': 'Hello',
          },
        ),
      ),
      isTrue,
    );

    final items = accumulator.items;
    expect(items, hasLength(1));
    expect(items.single.body, 'Hello');
  });

  test('keeps separate assistant output for consecutive turns', () {
    final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

    expect(
      accumulator.apply(
        _notificationEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'agent-1',
            'delta': 'first',
          },
        ),
      ),
      isTrue,
    );
    expect(
      accumulator.apply(
        _notificationEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-2',
            'itemId': 'agent-2',
            'delta': 'second',
          },
        ),
      ),
      isTrue,
    );

    final items = accumulator.items;
    expect(items, hasLength(2));
    expect(items[0].raw['turnId'], 'turn-1');
    expect(items[0].body, 'first');
    expect(items[1].raw['turnId'], 'turn-2');
    expect(items[1].body, 'second');
  });

  test(
    'renders realtime user message content parts instead of raw list text',
    () {
      final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

      expect(
        accumulator.apply(
          _notificationEvent(
            method: 'item/started',
            params: {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'id': 'user-1',
                'type': 'userMessage',
                'content': [
                  {'type': 'text', 'text': 'hello'},
                  {'type': 'image', 'url': 'data:image/png;base64,abcd'},
                ],
              },
            },
          ),
        ),
        isTrue,
      );

      final items = accumulator.items;
      expect(items, hasLength(1));
      expect(items.single.type, 'user.message');
      expect(items.single.body, 'hello\n[image]');
    },
  );

  test(
    'normalizes realtime context compaction items for timeline rendering',
    () {
      final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

      expect(
        accumulator.apply(
          _notificationEvent(
            method: 'item/started',
            params: {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'id': 'compaction-1',
                'type': 'contextCompaction',
                'status': 'in_progress',
              },
            },
          ),
        ),
        isTrue,
      );

      final items = accumulator.items;
      expect(items, hasLength(1));
      expect(items.single.type, 'context.compaction');
      expect(items.single.title, 'Context compaction');
      expect(items.single.status, 'in_progress');
    },
  );

  test('normalizes realtime web search items with a readable title', () {
    final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

    expect(
      accumulator.apply(
        _notificationEvent(
          method: 'item/started',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'id': 'search-1',
              'type': 'webSearch',
              'query': 'latest flutter release',
              'status': 'completed',
            },
          },
        ),
      ),
      isTrue,
    );

    final items = accumulator.items;
    expect(items, hasLength(1));
    expect(items.single.type, 'web.search');
    expect(items.single.title, 'latest flutter release');
    expect(items.single.body, 'latest flutter release');
    expect(items.single.actor, 'assistant');
  });

  test(
    'merges context compaction completion into the existing divider even when item ids differ',
    () {
      final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

      expect(
        accumulator.apply(
          _notificationEvent(
            method: 'item/started',
            params: {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'id': 'compaction-start',
                'type': 'contextCompaction',
                'status': 'in_progress',
              },
            },
          ),
        ),
        isTrue,
      );

      expect(
        accumulator.apply(
          _notificationEvent(
            method: 'item/completed',
            params: {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'id': 'compaction-done',
                'type': 'contextCompaction',
                'status': 'completed',
              },
            },
          ),
        ),
        isTrue,
      );

      final items = accumulator.items;
      expect(items, hasLength(1));
      expect(items.single.type, 'context.compaction');
      expect(items.single.status, 'completed');
    },
  );

  test(
    'prefers the semantic context compaction overlay over a stale snapshot item',
    () {
      final accumulator = ThreadRealtimeAccumulator(threadId: 'thread-1');

      expect(
        accumulator.apply(
          _notificationEvent(
            method: 'item/completed',
            params: {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'id': 'compaction-done',
                'type': 'contextCompaction',
                'status': 'completed',
              },
            },
          ),
        ),
        isTrue,
      );

      accumulator.replaceSnapshot([
        _item(
          id: 'snapshot-compaction',
          type: 'context.compaction',
          actor: 'assistant',
          body: '',
          status: 'in_progress',
          raw: const {'turnId': 'turn-1'},
        ),
      ]);

      final items = accumulator.items;
      expect(items, hasLength(1));
      expect(items.single.type, 'context.compaction');
      expect(items.single.status, 'completed');
      expect(items.single.createdAt, isNotNull);
    },
  );
}

BridgeRealtimeEvent _deltaEvent({required String text}) {
  return _notificationEvent(
    method: 'item/agentMessage/delta',
    params: {
      'threadId': 'thread-1',
      'turnId': 'turn-1',
      'itemId': 'agent-1',
      'delta': text,
    },
  );
}

BridgeRealtimeEvent _implicitAssistantDeltaEvent({required String text}) {
  return _notificationEvent(
    method: 'item/agentMessage/delta',
    params: {'threadId': 'thread-1', 'turnId': 'turn-1', 'delta': text},
  );
}

BridgeRealtimeEvent _notificationEvent({
  required String method,
  required Map<String, dynamic> params,
  String? type,
}) {
  return BridgeRealtimeEvent(
    type: type ?? method.replaceAll('/', '.'),
    description: method,
    receivedAt: DateTime.utc(2026, 4, 5, 13),
    raw: {'method': method, 'params': params, 'threadId': params['threadId']},
  );
}

CodexThreadItem _item({
  required String id,
  required String type,
  required String actor,
  required String body,
  String status = 'completed',
  Map<String, dynamic> raw = const {},
}) {
  return CodexThreadItem(
    id: id,
    type: type,
    title: type,
    body: body,
    status: status,
    actor: actor,
    raw: raw,
  );
}
