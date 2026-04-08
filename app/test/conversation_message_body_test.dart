import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/codex_thread_item.dart';
import 'package:mobile/widgets/conversation_message_body.dart';

void main() {
  testWidgets('renders structured user text and inline image parts', (
    tester,
  ) async {
    final onePixelPng = base64Encode(_transparentPng);
    final item = CodexThreadItem(
      id: 'user-1',
      type: 'user.message',
      title: 'User message',
      body: 'hello\n[image]',
      status: 'completed',
      actor: 'user',
      raw: {
        'content': [
          {'type': 'text', 'text': 'hello'},
          {'type': 'image', 'url': 'data:image/png;base64,$onePixelPng'},
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationMessageBody(item: item)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('[image]'), findsNothing);
  });

  testWidgets('opens a larger image preview when tapping an inline image', (
    tester,
  ) async {
    final onePixelPng = base64Encode(_transparentPng);
    final item = CodexThreadItem(
      id: 'user-2',
      type: 'user.message',
      title: 'User message',
      body: '[image]',
      status: 'completed',
      actor: 'user',
      raw: {
        'content': [
          {'type': 'image', 'url': 'data:image/png;base64,$onePixelPng'},
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationMessageBody(item: item)),
      ),
    );
    await tester.pumpAndSettle();

    final previewTrigger = tester.widget<InkWell>(
      find.byKey(const ValueKey('message-image-preview')),
    );
    previewTrigger.onTap?.call();
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
  });

  testWidgets('renders local file mentions as attachment chips', (
    tester,
  ) async {
    final item = CodexThreadItem(
      id: 'user-file-1',
      type: 'user.message',
      title: 'User message',
      body: '[file] spec.txt',
      status: 'completed',
      actor: 'user',
      raw: {
        'content': [
          {'type': 'text', 'text': 'Check this file'},
          {
            'type': 'mention',
            'name': 'spec.txt',
            'path': r'E:\workspace\codex-control\spec.txt',
          },
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationMessageBody(item: item)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Check this file'), findsOneWidget);
    expect(find.text('spec.txt'), findsWidgets);
    expect(find.text(r'E:\workspace\codex-control\spec.txt'), findsOneWidget);
  });

  testWidgets('renders assistant gif items as previewable images', (
    tester,
  ) async {
    final onePixelGif = base64Encode(_transparentGif);
    final item = CodexThreadItem(
      id: 'gif-1',
      type: 'image.generation',
      title: 'Image generation',
      body: 'data:image/gif;base64,$onePixelGif',
      status: 'completed',
      actor: 'assistant',
      raw: {'result': 'data:image/gif;base64,$onePixelGif'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationMessageBody(item: item)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);

    final previewTrigger = tester.widget<InkWell>(
      find.byKey(const ValueKey('message-image-preview')),
    );
    previewTrigger.onTap?.call();
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('renders grouped command and file changes as rich cards', (
    tester,
  ) async {
    final item = CodexThreadItem(
      id: 'assistant-group-1',
      type: 'assistant.group',
      title: 'Codex',
      body: '',
      status: 'in_progress',
      actor: 'assistant',
      raw: {
        'bubbleItems': [
          CodexThreadItem(
            id: 'agent-3',
            type: 'agent.message',
            title: 'Assistant',
            body: 'Running checks',
            status: 'in_progress',
            actor: 'assistant',
            raw: const {'phase': 'streaming'},
          ),
          CodexThreadItem(
            id: 'cmd-1',
            type: 'command.execution',
            title: 'Command',
            body: 'All tests passed.',
            status: 'completed',
            actor: 'assistant',
            raw: const {
              'command': ['/usr/bin/node', 'npm', 'test'],
              'cwd': '/workspace/app',
              'exitCode': 0,
              'aggregatedOutput': 'All tests passed.',
            },
          ),
          CodexThreadItem(
            id: 'file-1',
            type: 'file.change',
            title: '2 file changes',
            body: 'modified lib/main.dart',
            status: 'completed',
            actor: 'assistant',
            raw: const {
              'changes': [
                {
                  'path': 'lib/main.dart',
                  'kind': 'modified',
                  'diff': '@@ -1 +1 @@\n-old\n+new',
                },
                {
                  'path': 'lib/new_name.dart',
                  'oldPath': 'lib/old_name.dart',
                  'kind': 'renamed',
                },
              ],
            },
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationMessageBody(item: item)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('assistant-group-command-card:cmd-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('assistant-group-file-card:file-1')),
      findsOneWidget,
    );
    expect(find.text('npm test'), findsOneWidget);
    expect(find.text('Working directory: /workspace/app'), findsNothing);
    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('Renamed'), findsOneWidget);
    expect(find.textContaining('@@ -1 +1 @@'), findsNothing);
    expect(tester.widget<Text>(find.text('npm test')).maxLines, 1);
    expect(tester.widget<Text>(find.text('lib/main.dart')).maxLines, 1);

    await tester.tap(find.text('npm test'));
    await tester.pumpAndSettle();

    expect(find.text('Working directory: /workspace/app'), findsOneWidget);
    expect(find.text('All tests passed.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('file-change-card:lib/main.dart:modified')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('@@ -1 +1 @@'), findsOneWidget);
    expect(find.byKey(const ValueKey('diff-line:hunk:0')), findsOneWidget);
    expect(find.byKey(const ValueKey('diff-line:addition:2')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('file-change-card:lib/new_name.dart:renamed')),
    );
    await tester.pumpAndSettle();

    expect(find.text('from lib/old_name.dart'), findsOneWidget);
  });

  testWidgets('shows the reasoning status only while thinking', (tester) async {
    final item = CodexThreadItem(
      id: 'reasoning-1',
      type: 'reasoning',
      title: 'Reasoning',
      body: 'Inspecting the workspace.',
      status: 'in_progress',
      actor: 'assistant',
      createdAt: DateTime.now().toUtc().subtract(const Duration(seconds: 5)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationMessageBody(item: item)),
      ),
    );

    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Inspecting the workspace.'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConversationMessageBody(
            item: CodexThreadItem(
              id: 'reasoning-1',
              type: 'reasoning',
              title: 'Reasoning',
              body: 'Inspecting the workspace.',
              status: 'completed',
              actor: 'assistant',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Inspecting the workspace.'), findsOneWidget);
  });

  testWidgets(
    'keeps the reasoning status visible while later assistant replies are still streaming',
    (tester) async {
      final item = CodexThreadItem(
        id: 'assistant-group-reasoning',
        type: 'assistant.group',
        title: 'Codex',
        body: '',
        status: 'in_progress',
        actor: 'assistant',
        raw: {
          'bubbleItems': [
            CodexThreadItem(
              id: 'reasoning-active',
              type: 'reasoning',
              title: 'Reasoning',
              body: '',
              status: 'in_progress',
              actor: 'assistant',
            ),
            CodexThreadItem(
              id: 'assistant-reply',
              type: 'agent.message',
              title: 'Assistant',
              body: 'Here is the next reply.',
              status: 'streaming',
              actor: 'assistant',
              raw: const {'phase': 'streaming'},
            ),
          ],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConversationMessageBody(item: item)),
        ),
      );
      await tester.pump();

      expect(find.text('Thinking'), findsOneWidget);
      expect(find.text('Here is the next reply.'), findsOneWidget);
    },
  );

  testWidgets('hides the reasoning status once a later final answer exists', (
    tester,
  ) async {
    final item = CodexThreadItem(
      id: 'assistant-group-reasoning-final',
      type: 'assistant.group',
      title: 'Codex',
      body: '',
      status: 'in_progress',
      actor: 'assistant',
      raw: {
        'bubbleItems': [
          CodexThreadItem(
            id: 'reasoning-active',
            type: 'reasoning',
            title: 'Reasoning',
            body: '',
            status: 'in_progress',
            actor: 'assistant',
          ),
          CodexThreadItem(
            id: 'assistant-final',
            type: 'agent.message',
            title: 'Assistant',
            body: 'Final answer is ready.',
            status: 'completed',
            actor: 'assistant',
            raw: const {'phase': 'final_answer'},
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationMessageBody(item: item)),
      ),
    );
    await tester.pump();

    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Final answer is ready.'), findsOneWidget);
  });

  testWidgets(
    'keeps assistant group height stable when reasoning status becomes hidden',
    (tester) async {
      final key = GlobalKey();

      Widget buildBody(CodexThreadItem item) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: Container(
                key: key,
                child: ConversationMessageBody(item: item),
              ),
            ),
          ),
        );
      }

      final streamingGroup = CodexThreadItem(
        id: 'assistant-group-reasoning-streaming',
        type: 'assistant.group',
        title: 'Codex',
        body: '',
        status: 'in_progress',
        actor: 'assistant',
        raw: {
          'bubbleItems': [
            const CodexThreadItem(
              id: 'reasoning-active',
              type: 'reasoning',
              title: 'Reasoning',
              body: '',
              status: 'in_progress',
              actor: 'assistant',
            ),
            const CodexThreadItem(
              id: 'assistant-reply',
              type: 'agent.message',
              title: 'Assistant',
              body: 'Stable reply body.',
              status: 'streaming',
              actor: 'assistant',
              raw: {'phase': 'streaming'},
            ),
          ],
        },
      );

      final finalGroup = CodexThreadItem(
        id: 'assistant-group-reasoning-final-stable',
        type: 'assistant.group',
        title: 'Codex',
        body: '',
        status: 'completed',
        actor: 'assistant',
        raw: {
          'bubbleItems': [
            const CodexThreadItem(
              id: 'reasoning-active',
              type: 'reasoning',
              title: 'Reasoning',
              body: '',
              status: 'completed',
              actor: 'assistant',
            ),
            const CodexThreadItem(
              id: 'assistant-final',
              type: 'agent.message',
              title: 'Assistant',
              body: 'Stable reply body.',
              status: 'completed',
              actor: 'assistant',
              raw: {'phase': 'final_answer'},
            ),
          ],
        },
      );

      await tester.pumpWidget(buildBody(streamingGroup));
      await tester.pump();
      final beforeHeight = tester.getSize(find.byKey(key)).height;

      await tester.pumpWidget(buildBody(finalGroup));
      await tester.pump();
      final afterHeight = tester.getSize(find.byKey(key)).height;

      expect(find.text('Thinking'), findsNothing);
      expect(afterHeight, beforeHeight);
    },
  );

  testWidgets('renders web search items as structured cards', (tester) async {
    final item = CodexThreadItem(
      id: 'search-1',
      type: 'web.search',
      title: 'latest flutter release',
      body: 'latest flutter release',
      status: 'completed',
      actor: 'assistant',
      raw: const {
        'query': 'latest flutter release',
        'action': {
          'type': 'openPage',
          'query': 'latest flutter release',
          'url': 'https://docs.flutter.dev/release/whats-new',
        },
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationMessageBody(item: item)),
      ),
    );
    await tester.pump();

    expect(find.text('Opened page'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(
      find.text('https://docs.flutter.dev/release/whats-new'),
      findsOneWidget,
    );
    expect(find.text('latest flutter release'), findsOneWidget);
  });

  testWidgets('falls back safely for incomplete streaming markdown', (
    tester,
  ) async {
    final item = CodexThreadItem(
      id: 'assistant-unsafe-markdown',
      type: 'agent.message',
      title: 'Assistant',
      body:
          '正在输出链接 [thread_detail_screen.dart](E:/workspace/codex-control/app/lib/screens/thread_detail_screen.dart:1313\n```dart\nprint("partial");',
      status: 'streaming',
      actor: 'assistant',
      raw: const {'phase': 'streaming'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationMessageBody(item: item)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('正在输出链接'), findsOneWidget);
    expect(find.textContaining('print("partial");'), findsOneWidget);
  });

  testWidgets('renders unfinished assistant content as plain text first', (
    tester,
  ) async {
    final item = CodexThreadItem(
      id: 'assistant-streaming-markdown',
      type: 'agent.message',
      title: 'Assistant',
      body: '**bold**\n- item',
      status: 'streaming',
      actor: 'assistant',
      raw: const {'phase': 'streaming'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationMessageBody(item: item)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('**bold**\n- item'), findsOneWidget);
    expect(find.text('bold'), findsNothing);
  });

  testWidgets('renders streaming final answers as markdown instead of source', (
    tester,
  ) async {
    final item = CodexThreadItem(
      id: 'assistant-final-answer-streaming-markdown',
      type: 'agent.message',
      title: 'Assistant',
      body: '**bold**\n- item',
      status: 'streaming',
      actor: 'assistant',
      raw: const {'phase': 'final_answer'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationMessageBody(item: item)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('**bold**\n- item'), findsNothing);
    expect(find.text('bold'), findsOneWidget);
    expect(find.text('item'), findsOneWidget);
  });

  testWidgets('renders completed fenced code blocks without fence markers', (
    tester,
  ) async {
    final item = CodexThreadItem(
      id: 'assistant-completed-code-fence',
      type: 'agent.message',
      title: 'Assistant',
      body:
          '可以用这个：\n\n```text\nImprove mobile composer layout and guard attachment bridge fallback\n```',
      status: 'completed',
      actor: 'assistant',
      raw: const {'phase': 'final_answer'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationMessageBody(item: item)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Improve mobile composer layout'), findsOneWidget);
    expect(find.text('```text'), findsNothing);
    expect(find.text('```'), findsNothing);
  });
}

const List<int> _transparentPng = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  11,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  0,
  1,
  0,
  0,
  5,
  0,
  1,
  13,
  10,
  45,
  180,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

const List<int> _transparentGif = <int>[
  71,
  73,
  70,
  56,
  57,
  97,
  1,
  0,
  1,
  0,
  128,
  0,
  0,
  0,
  0,
  0,
  255,
  255,
  255,
  33,
  249,
  4,
  1,
  0,
  0,
  0,
  0,
  44,
  0,
  0,
  0,
  0,
  1,
  0,
  1,
  0,
  0,
  2,
  2,
  68,
  1,
  0,
  59,
];
