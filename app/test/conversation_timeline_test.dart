import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/codex_thread_item.dart';
import 'package:mobile/services/conversation_timeline.dart';

void main() {
  test('collapses commentary messages into the final answer for one turn', () {
    final items = [
      _item(
        id: 'user-1',
        actor: 'user',
        type: 'user.message',
        body: 'split reply?',
        raw: const {'turnId': 'turn-1'},
      ),
      _item(
        id: 'agent-1',
        actor: 'assistant',
        type: 'agent.message',
        body: 'step 1',
        raw: const {'turnId': 'turn-1', 'phase': 'commentary'},
      ),
      _item(
        id: 'agent-2',
        actor: 'assistant',
        type: 'agent.message',
        body: 'step 2',
        raw: const {'turnId': 'turn-1', 'phase': 'commentary'},
      ),
      _item(
        id: 'agent-3',
        actor: 'assistant',
        type: 'agent.message',
        body: 'final reply',
        raw: const {'turnId': 'turn-1', 'phase': 'final_answer'},
      ),
    ];

    final collapsed = buildConversationTimelineItems(items);

    expect(collapsed, hasLength(2));
    expect(collapsed[0].actor, 'user');
    expect(collapsed[1].actor, 'assistant');
    expect(collapsed[1].body, 'final reply');
    expect(collapsed[1].raw['phase'], 'final_answer');
  });

  test('appends assistant commentary into one bubble before final answer', () {
    final items = [
      _item(
        id: 'user-2',
        actor: 'user',
        type: 'user.message',
        body: 'keep streaming',
        raw: const {'turnId': 'turn-2'},
      ),
      _item(
        id: 'agent-4',
        actor: 'assistant',
        type: 'agent.message',
        body: 'checking files',
        raw: const {'turnId': 'turn-2', 'phase': 'commentary'},
      ),
      _item(
        id: 'agent-5',
        actor: 'assistant',
        type: 'agent.message',
        body: 'updating layout',
        raw: const {'turnId': 'turn-2', 'phase': 'commentary'},
      ),
    ];

    final collapsed = buildConversationTimelineItems(items);

    expect(collapsed, hasLength(2));
    expect(collapsed[1].type, 'assistant.group');
    final grouped = (collapsed[1].raw['bubbleItems'] as List)
        .whereType<CodexThreadItem>()
        .toList(growable: false);
    expect(grouped.map((item) => item.id).toList(growable: false), [
      'agent-4',
      'agent-5',
    ]);
  });

  test('keeps streaming assistant text appended after older commentary', () {
    final items = [
      _item(
        id: 'user-3',
        actor: 'user',
        type: 'user.message',
        body: 'stream now',
        raw: const {'turnId': 'turn-3'},
      ),
      _item(
        id: 'agent-6',
        actor: 'assistant',
        type: 'agent.message',
        body: 'thinking',
        raw: const {'turnId': 'turn-3', 'phase': 'commentary'},
      ),
      _item(
        id: 'agent-7',
        actor: 'assistant',
        type: 'agent.message',
        body: 'streaming body',
        raw: const {'turnId': 'turn-3', 'phase': 'streaming'},
      ),
    ];

    final collapsed = buildConversationTimelineItems(items);

    expect(collapsed, hasLength(2));
    expect(collapsed[1].type, 'assistant.group');
    final grouped = (collapsed[1].raw['bubbleItems'] as List)
        .whereType<CodexThreadItem>()
        .toList(growable: false);
    expect(grouped.map((item) => item.id).toList(growable: false), [
      'agent-6',
      'agent-7',
    ]);
    expect(grouped.last.raw['phase'], 'streaming');
  });

  test('ignores empty final answer placeholders while streaming', () {
    final items = [
      _item(
        id: 'user-4',
        actor: 'user',
        type: 'user.message',
        body: 'show live text',
        raw: const {'turnId': 'turn-4'},
      ),
      _item(
        id: 'agent-8',
        actor: 'assistant',
        type: 'agent.message',
        body: '',
        raw: const {'turnId': 'turn-4', 'phase': 'final_answer'},
      ),
      _item(
        id: 'agent-9',
        actor: 'assistant',
        type: 'agent.message',
        body: 'live answer',
        raw: const {'turnId': 'turn-4', 'phase': 'streaming'},
      ),
    ];

    final collapsed = buildConversationTimelineItems(items);

    expect(collapsed, hasLength(2));
    expect(collapsed[1].id, 'agent-9');
    expect(collapsed[1].body, 'live answer');
    expect(collapsed[1].raw['phase'], 'streaming');
  });

  test(
    'keeps latest non-empty assistant text when final placeholder is empty',
    () {
      final items = [
        _item(
          id: 'user-5',
          actor: 'user',
          type: 'user.message',
          body: 'keep commentary visible',
          raw: const {'turnId': 'turn-5'},
        ),
        _item(
          id: 'agent-10',
          actor: 'assistant',
          type: 'agent.message',
          body: 'working through it',
          raw: const {'turnId': 'turn-5', 'phase': 'commentary'},
        ),
        _item(
          id: 'agent-11',
          actor: 'assistant',
          type: 'agent.message',
          body: '',
          raw: const {'turnId': 'turn-5', 'phase': 'final_answer'},
        ),
      ];

      final collapsed = buildConversationTimelineItems(items);

      expect(collapsed, hasLength(2));
      expect(collapsed[1].id, 'agent-10');
      expect(collapsed[1].body, 'working through it');
    },
  );

  test(
    'preserves multiple assistant replies inside one turn when users speak again',
    () {
      final items = [
        _item(
          id: 'user-6',
          actor: 'user',
          type: 'user.message',
          body: 'first question',
          raw: const {'turnId': 'turn-6'},
        ),
        _item(
          id: 'agent-12',
          actor: 'assistant',
          type: 'agent.message',
          body: 'first answer',
          raw: const {'turnId': 'turn-6', 'phase': 'final_answer'},
        ),
        _item(
          id: 'user-7',
          actor: 'user',
          type: 'user.message',
          body: 'second question',
          raw: const {'turnId': 'turn-6'},
        ),
        _item(
          id: 'agent-13',
          actor: 'assistant',
          type: 'agent.message',
          body: 'second answer',
          raw: const {'turnId': 'turn-6', 'phase': 'final_answer'},
        ),
      ];

      final collapsed = buildConversationTimelineItems(items);

      expect(collapsed, hasLength(4));
      expect(collapsed[0].body, 'first question');
      expect(collapsed[1].body, 'first answer');
      expect(collapsed[2].body, 'second question');
      expect(collapsed[3].body, 'second answer');
    },
  );

  test('replaces reasoning content once the final answer is available', () {
    final items = [
      _item(
        id: 'user-8',
        actor: 'user',
        type: 'user.message',
        body: 'why',
        raw: const {'turnId': 'turn-7'},
      ),
      _item(
        id: 'reason-1',
        actor: 'assistant',
        type: 'reasoning',
        body: 'thinking',
        raw: const {'turnId': 'turn-7'},
      ),
      _item(
        id: 'agent-14',
        actor: 'assistant',
        type: 'agent.message',
        body: 'because',
        raw: const {'turnId': 'turn-7', 'phase': 'final_answer'},
      ),
    ];

    final collapsed = buildConversationTimelineItems(items);

    expect(collapsed, hasLength(2));
    expect(collapsed[0].type, 'user.message');
    expect(collapsed[1].type, 'agent.message');
    expect(collapsed[1].body, 'because');
    expect(collapsed[1].raw['phase'], 'final_answer');
  });

  test('hides web search items once the final answer is available', () {
    final items = [
      _item(
        id: 'user-9',
        actor: 'user',
        type: 'user.message',
        body: 'find it',
        raw: const {'turnId': 'turn-8'},
      ),
      CodexThreadItem(
        id: 'search-1',
        actor: 'assistant',
        type: 'web.search',
        title: 'Web search',
        body: 'query text',
        status: 'completed',
        raw: const {'turnId': 'turn-8'},
      ),
      _item(
        id: 'agent-15',
        actor: 'assistant',
        type: 'agent.message',
        body: 'found it',
        raw: const {'turnId': 'turn-8', 'phase': 'final_answer'},
      ),
    ];

    final collapsed = buildConversationTimelineItems(items);

    expect(collapsed, hasLength(2));
    expect(collapsed[0].type, 'user.message');
    expect(collapsed[1].type, 'agent.message');
    expect(collapsed[1].body, 'found it');
  });

  test(
    'keeps a stable bubble key when final answer replaces grouped content',
    () {
      final beforeFinal = buildConversationTimelineItems([
        _item(
          id: 'user-10',
          actor: 'user',
          type: 'user.message',
          body: 'keep row stable',
          raw: const {'turnId': 'turn-9'},
        ),
        _item(
          id: 'agent-16',
          actor: 'assistant',
          type: 'agent.message',
          body: 'checking files',
          raw: const {'turnId': 'turn-9', 'phase': 'commentary'},
        ),
        _item(
          id: 'agent-17',
          actor: 'assistant',
          type: 'agent.message',
          body: 'updating code',
          raw: const {'turnId': 'turn-9', 'phase': 'streaming'},
        ),
      ]);
      final afterFinal = buildConversationTimelineItems([
        _item(
          id: 'user-10',
          actor: 'user',
          type: 'user.message',
          body: 'keep row stable',
          raw: const {'turnId': 'turn-9'},
        ),
        _item(
          id: 'agent-16',
          actor: 'assistant',
          type: 'agent.message',
          body: 'checking files',
          raw: const {'turnId': 'turn-9', 'phase': 'commentary'},
        ),
        _item(
          id: 'agent-18',
          actor: 'assistant',
          type: 'agent.message',
          body: 'done',
          raw: const {'turnId': 'turn-9', 'phase': 'final_answer'},
        ),
      ]);

      expect(beforeFinal[1].raw['bubbleKey'], afterFinal[1].raw['bubbleKey']);
      expect(afterFinal[1].type, 'agent.message');
      expect(afterFinal[1].body, 'done');
    },
  );

  test(
    'keeps a stable bubble key when a single streaming message becomes the final answer',
    () {
      final beforeFinal = buildConversationTimelineItems([
        _item(
          id: 'user-11',
          actor: 'user',
          type: 'user.message',
          body: 'single message path',
          raw: const {'turnId': 'turn-10'},
        ),
        _item(
          id: 'agent-19',
          actor: 'assistant',
          type: 'agent.message',
          body: 'streaming text',
          raw: const {'turnId': 'turn-10', 'phase': 'streaming'},
        ),
      ]);
      final afterFinal = buildConversationTimelineItems([
        _item(
          id: 'user-11',
          actor: 'user',
          type: 'user.message',
          body: 'single message path',
          raw: const {'turnId': 'turn-10'},
        ),
        _item(
          id: 'agent-20',
          actor: 'assistant',
          type: 'agent.message',
          body: 'final text',
          raw: const {'turnId': 'turn-10', 'phase': 'final_answer'},
        ),
      ]);

      expect(beforeFinal[1].type, 'agent.message');
      expect(afterFinal[1].type, 'agent.message');
      expect(beforeFinal[1].raw['bubbleKey'], afterFinal[1].raw['bubbleKey']);
      expect(afterFinal[1].body, 'final text');
    },
  );

  test('keeps reasoning visible when no assistant reply exists yet', () {
    final items = [
      _item(
        id: 'user-9',
        actor: 'user',
        type: 'user.message',
        body: 'still working?',
        raw: const {'turnId': 'turn-8'},
      ),
      _item(
        id: 'reason-2',
        actor: 'assistant',
        type: 'reasoning',
        body: 'thinking',
        raw: const {'turnId': 'turn-8'},
      ),
    ];

    final collapsed = buildConversationTimelineItems(items);

    expect(collapsed, hasLength(2));
    expect(collapsed[0].type, 'user.message');
    expect(collapsed[1].type, 'reasoning');
  });

  test('groups command execution and file changes before the final answer', () {
    final items = [
      _item(
        id: 'user-10',
        actor: 'user',
        type: 'user.message',
        body: 'run something',
        raw: const {'turnId': 'turn-9'},
      ),
      _item(
        id: 'reason-3',
        actor: 'assistant',
        type: 'reasoning',
        body: 'thinking',
        raw: const {'turnId': 'turn-9'},
      ),
      _item(
        id: 'agent-15',
        actor: 'assistant',
        type: 'agent.message',
        body: 'running checks',
        raw: const {'turnId': 'turn-9', 'phase': 'streaming'},
      ),
      _item(
        id: 'cmd-1',
        actor: 'assistant',
        type: 'command.execution',
        body: 'npm test',
        raw: const {'turnId': 'turn-9'},
      ),
      _item(
        id: 'file-1',
        actor: 'assistant',
        type: 'file.change',
        body: 'modified lib/main.dart',
        raw: const {'turnId': 'turn-9'},
      ),
    ];

    final collapsed = buildConversationTimelineItems(items);

    expect(collapsed, hasLength(2));
    expect(collapsed[0].type, 'user.message');
    expect(collapsed[1].type, 'assistant.group');
    final grouped = (collapsed[1].raw['bubbleItems'] as List)
        .whereType<CodexThreadItem>()
        .toList(growable: false);
    expect(grouped.map((item) => item.type).toList(growable: false), [
      'reasoning',
      'agent.message',
      'command.execution',
      'file.change',
    ]);
  });

  test('replaces grouped tool output once the final answer is available', () {
    final items = [
      _item(
        id: 'user-13',
        actor: 'user',
        type: 'user.message',
        body: 'ship it',
        raw: const {'turnId': 'turn-11'},
      ),
      _item(
        id: 'agent-18',
        actor: 'assistant',
        type: 'agent.message',
        body: 'checking the repo',
        raw: const {'turnId': 'turn-11', 'phase': 'commentary'},
      ),
      _item(
        id: 'cmd-2',
        actor: 'assistant',
        type: 'command.execution',
        body: 'npm test',
        raw: const {'turnId': 'turn-11'},
      ),
      _item(
        id: 'file-2',
        actor: 'assistant',
        type: 'file.change',
        body: 'modified app.dart',
        raw: const {'turnId': 'turn-11'},
      ),
      _item(
        id: 'agent-19',
        actor: 'assistant',
        type: 'agent.message',
        body: 'All checks passed. Ready to merge.',
        raw: const {'turnId': 'turn-11', 'phase': 'final_answer'},
      ),
    ];

    final collapsed = buildConversationTimelineItems(items);

    expect(collapsed, hasLength(2));
    expect(collapsed[1].type, 'agent.message');
    expect(collapsed[1].body, 'All checks passed. Ready to merge.');
    expect(collapsed[1].raw['phase'], 'final_answer');
  });

  test('deduplicates repeated user messages inside the same turn', () {
    final items = [
      _item(
        id: 'user-11',
        actor: 'user',
        type: 'user.message',
        body: 'repeat once',
        raw: const {'turnId': 'turn-10'},
      ),
      _item(
        id: 'agent-16',
        actor: 'assistant',
        type: 'agent.message',
        body: 'working on it',
        raw: const {'turnId': 'turn-10', 'phase': 'commentary'},
      ),
      _item(
        id: 'user-12',
        actor: 'user',
        type: 'user.message',
        body: 'repeat once',
        raw: const {'turnId': 'turn-10'},
      ),
      _item(
        id: 'agent-17',
        actor: 'assistant',
        type: 'agent.message',
        body: 'done',
        raw: const {'turnId': 'turn-10', 'phase': 'final_answer'},
      ),
    ];

    final collapsed = buildConversationTimelineItems(items);

    expect(collapsed, hasLength(2));
    expect(collapsed[0].type, 'user.message');
    expect(collapsed[0].body, 'repeat once');
    expect(collapsed[1].type, 'agent.message');
    expect(collapsed[1].body, 'done');
  });

  test('deduplicates repeated assistant messages inside the same turn', () {
    final items = [
      _item(
        id: 'user-14',
        actor: 'user',
        type: 'user.message',
        body: 'say it once',
        raw: const {'turnId': 'turn-12'},
      ),
      _item(
        id: 'agent-20',
        actor: 'assistant',
        type: 'agent.message',
        body: 'same assistant text',
        raw: const {'turnId': 'turn-12', 'phase': 'completed'},
      ),
      _item(
        id: 'agent-21',
        actor: 'assistant',
        type: 'agent.message',
        body: 'same assistant text',
        raw: const {'turnId': 'turn-12', 'phase': 'completed'},
      ),
    ];

    final collapsed = buildConversationTimelineItems(items);

    expect(collapsed, hasLength(2));
    expect(collapsed[1].type, 'agent.message');
    expect(collapsed[1].body, 'same assistant text');
  });
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
