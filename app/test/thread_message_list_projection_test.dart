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
    'keeps assistant text updates and tool output in their original order inside one bubble',
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
      expect(
        projection.entries.map((entry) => entry.kind).toList(growable: false),
        [
          ThreadMessageEntryKind.bubble,
          ThreadMessageEntryKind.bubble,
        ],
      );
      expect(
        projection.entries[1].items.map((item) => item.id).toList(growable: false),
        ['agent-4', 'cmd-1', 'agent-5'],
      );
    },
  );

  test('keeps trailing tool output visible without requiring a newer text', () {
    final projection = projectThreadMessageList([
      _item(
        id: 'user-5',
        actor: 'user',
        type: 'user.message',
        body: 'wait for the next text',
        raw: const {'turnId': 'turn-5'},
      ),
      _item(
        id: 'agent-9',
        actor: 'assistant',
        type: 'agent.message',
        body: 'starting work',
        raw: const {'turnId': 'turn-5', 'phase': 'commentary'},
      ),
      _item(
        id: 'cmd-4',
        actor: 'assistant',
        type: 'command.execution',
        body: 'rg pending',
        raw: const {'turnId': 'turn-5', 'command': ['rg', 'pending']},
      ),
      _item(
        id: 'file-2',
        actor: 'assistant',
        type: 'file.change',
        body: '',
        raw: const {
          'turnId': 'turn-5',
          'changes': [
            {'path': 'lib/pending.dart', 'kind': 'updated'},
            {'path': 'lib/next.dart', 'kind': 'updated'},
          ],
        },
      ),
    ]);

    expect(projection.entries, hasLength(2));
    expect(projection.entries[1].kind, ThreadMessageEntryKind.bubble);
    expect(
      projection.entries[1].items.map((item) => item.id).toList(growable: false),
      ['agent-9', 'cmd-4', 'file-2'],
    );
  });

  test('does not replace earlier visible text when later text arrives', () {
    final projection = projectThreadMessageList([
      _item(
        id: 'user-6',
        actor: 'user',
        type: 'user.message',
        body: 'preserve text',
        raw: const {'turnId': 'turn-6'},
      ),
      _item(
        id: 'agent-10',
        actor: 'assistant',
        type: 'agent.message',
        body: 'first text',
        raw: const {'turnId': 'turn-6', 'phase': 'commentary'},
      ),
      _item(
        id: 'cmd-5',
        actor: 'assistant',
        type: 'command.execution',
        body: 'rg preserve',
        raw: const {'turnId': 'turn-6', 'command': ['rg', 'preserve']},
      ),
      _item(
        id: 'agent-11',
        actor: 'assistant',
        type: 'agent.message',
        body: 'second text',
        raw: const {'turnId': 'turn-6', 'phase': 'streaming'},
      ),
    ]);

    expect(projection.entries, hasLength(2));
    expect(projection.entries[1].kind, ThreadMessageEntryKind.bubble);
    expect(
      projection.entries[1].items.map((item) => item.id).toList(growable: false),
      ['agent-10', 'cmd-5', 'agent-11'],
    );
  });

  test('final answer bubble hides prior tool entries and keeps source items', () {
    final projection = projectThreadMessageList([
      _item(
        id: 'user-4',
        actor: 'user',
        type: 'user.message',
        body: 'wrap the tools',
        raw: const {'turnId': 'turn-4'},
      ),
      _item(
        id: 'agent-7',
        actor: 'assistant',
        type: 'agent.message',
        body: 'checking files',
        raw: const {'turnId': 'turn-4', 'phase': 'commentary'},
      ),
      _item(
        id: 'cmd-3',
        actor: 'assistant',
        type: 'command.execution',
        body: 'rg operation',
        raw: const {'turnId': 'turn-4', 'command': ['rg', 'operation']},
      ),
      _item(
        id: 'file-1',
        actor: 'assistant',
        type: 'file.change',
        body: '',
        raw: const {
          'turnId': 'turn-4',
          'changes': [
            {'path': 'lib/a.dart', 'kind': 'updated'},
            {'path': 'lib/b.dart', 'kind': 'updated'},
          ],
        },
      ),
      _item(
        id: 'agent-8',
        actor: 'assistant',
        type: 'agent.message',
        body: 'done',
        raw: const {'turnId': 'turn-4', 'phase': 'final_answer'},
      ),
    ]);

    expect(projection.entries, hasLength(2));
    expect(
      projection.entries.map((entry) => entry.kind).toList(growable: false),
      [
        ThreadMessageEntryKind.bubble,
        ThreadMessageEntryKind.bubble,
      ],
    );
    expect(projection.entries[1].items.single.id, 'agent-8');
    expect(
      projection.entries[1].sourceItems.map((item) => item.id).toList(),
      ['agent-7', 'cmd-3', 'file-1', 'agent-8'],
    );
  });

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

  test(
    'background projection matches sync projection for large conversations',
    () async {
      final items = <CodexThreadItem>[];
      for (var index = 0; index < 30; index += 1) {
        final turnId = 'turn-$index';
        items.add(
          _item(
            id: 'user-$index',
            actor: 'user',
            type: 'user.message',
            body: 'question $index',
            raw: {'turnId': turnId},
          ),
        );
        items.add(
          _item(
            id: 'agent-commentary-$index',
            actor: 'assistant',
            type: 'agent.message',
            body: 'working on step $index',
            raw: {'turnId': turnId, 'phase': 'commentary'},
          ),
        );
        items.add(
          _item(
            id: 'command-$index',
            actor: 'assistant',
            type: 'command.execution',
            body: 'rg item $index',
            raw: {'turnId': turnId},
          ),
        );
        items.add(
          _item(
            id: 'agent-streaming-$index',
            actor: 'assistant',
            type: 'agent.message',
            body: 'partial answer ' * 12,
            raw: {'turnId': turnId, 'phase': 'streaming'},
          ),
        );
      }

      final syncProjection = projectThreadMessageList(items);
      final asyncProjection = await projectThreadMessageListAsync(items);

      expect(asyncProjection.tailSignature, syncProjection.tailSignature);
      expect(asyncProjection.tailBodyLength, syncProjection.tailBodyLength);
      expect(asyncProjection.entries, hasLength(syncProjection.entries.length));
      expect(
        asyncProjection.entries.map((entry) => entry.key).toList(),
        syncProjection.entries.map((entry) => entry.key).toList(),
      );

      final assistantBubble = asyncProjection.entries.firstWhere(
        (entry) =>
            entry.kind == ThreadMessageEntryKind.bubble &&
            entry.items.any((item) => item.type == 'command.execution'),
      );
      expect(
        assistantBubble.items.any((item) => item.type == 'command.execution'),
        isTrue,
      );
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
