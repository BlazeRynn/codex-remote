import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/codex_thread_item.dart';
import 'package:mobile/services/thread_message_list_projection.dart';

void main() {
  test(
    'keeps a stable bubble entry key when final answer replaces streaming items',
    () {
      final beforeFinal = projectThreadMessageList([
        _item(
          id: 'user-1',
          actor: 'user',
          type: 'user.message',
          body: 'keep row stable',
          raw: const {'turnId': 'turn-1'},
        ),
        _item(
          id: 'agent-1',
          actor: 'assistant',
          type: 'agent.message',
          body: 'checking files',
          raw: const {'turnId': 'turn-1', 'phase': 'commentary'},
        ),
        _item(
          id: 'agent-2',
          actor: 'assistant',
          type: 'agent.message',
          body: 'updating code',
          raw: const {'turnId': 'turn-1', 'phase': 'streaming'},
        ),
      ]);
      final afterFinal = projectThreadMessageList([
        _item(
          id: 'user-1',
          actor: 'user',
          type: 'user.message',
          body: 'keep row stable',
          raw: const {'turnId': 'turn-1'},
        ),
        _item(
          id: 'agent-1',
          actor: 'assistant',
          type: 'agent.message',
          body: 'checking files',
          raw: const {'turnId': 'turn-1', 'phase': 'commentary'},
        ),
        _item(
          id: 'agent-3',
          actor: 'assistant',
          type: 'agent.message',
          body: 'done',
          raw: const {'turnId': 'turn-1', 'phase': 'final_answer'},
        ),
      ]);

      expect(beforeFinal.entries, hasLength(2));
      expect(afterFinal.entries, hasLength(2));
      expect(beforeFinal.entries[1].key, afterFinal.entries[1].key);
      expect(beforeFinal.entries[1].kind, ThreadMessageEntryKind.bubble);
      expect(afterFinal.entries[1].kind, ThreadMessageEntryKind.bubble);
      expect(afterFinal.entries[1].items.single.body, 'done');
    },
  );

  test(
    'keeps assistant text and tool output in their original order within one bubble',
    () {
      final projection = projectThreadMessageList([
        _item(
          id: 'user-2',
          actor: 'user',
          type: 'user.message',
          body: 'ship it',
          raw: const {'turnId': 'turn-2'},
        ),
        _item(
          id: 'agent-4',
          actor: 'assistant',
          type: 'agent.message',
          body: 'checking the repo',
          raw: const {'turnId': 'turn-2', 'phase': 'commentary'},
        ),
        _item(
          id: 'cmd-1',
          actor: 'assistant',
          type: 'command.execution',
          body: 'flutter test',
          raw: const {'turnId': 'turn-2'},
        ),
        _item(
          id: 'agent-5',
          actor: 'assistant',
          type: 'agent.message',
          body: 'all checks passed',
          raw: const {'turnId': 'turn-2', 'phase': 'streaming'},
        ),
      ]);

      expect(projection.entries, hasLength(2));
      expect(projection.entries[1].kind, ThreadMessageEntryKind.bubble);
      expect(
        projection.entries[1].items
            .map((item) => item.id)
            .toList(growable: false),
        ['agent-4', 'cmd-1', 'agent-5'],
      );
    },
  );

  test('keeps context compaction as a standalone divider inside a turn', () {
    final projection = projectThreadMessageList([
      _item(
        id: 'user-3',
        actor: 'user',
        type: 'user.message',
        body: 'compress it',
        raw: const {'turnId': 'turn-3'},
      ),
      _item(
        id: 'compaction-1',
        actor: 'assistant',
        type: 'context.compaction',
        body: '',
        raw: const {'turnId': 'turn-3', 'type': 'contextCompaction'},
      ),
      _item(
        id: 'agent-6',
        actor: 'assistant',
        type: 'agent.message',
        body: 'done',
        raw: const {'turnId': 'turn-3', 'phase': 'final_answer'},
      ),
    ]);

    expect(projection.entries, hasLength(3));
    expect(projection.entries[0].kind, ThreadMessageEntryKind.bubble);
    expect(
      projection.entries[1].kind,
      ThreadMessageEntryKind.contextCompaction,
    );
    expect(projection.entries[2].kind, ThreadMessageEntryKind.bubble);
  });

  test(
    'renders standalone tool items without forcing them into a chat bubble',
    () {
      final projection = projectThreadMessageList([
        _item(
          id: 'cmd-2',
          actor: 'assistant',
          type: 'command.execution',
          body: 'npm test',
          raw: const {},
        ),
      ]);

      expect(projection.entries, hasLength(1));
      expect(
        projection.entries.single.kind,
        ThreadMessageEntryKind.commandExecution,
      );
      expect(projection.legacyItems.single.type, 'command.execution');
    },
  );
}

CodexThreadItem _item({
  required String id,
  required String actor,
  required String type,
  required String body,
  required Map<String, dynamic> raw,
}) {
  return CodexThreadItem(
    id: id,
    type: type,
    title: type,
    body: body,
    status: 'completed',
    actor: actor,
    raw: raw,
  );
}
