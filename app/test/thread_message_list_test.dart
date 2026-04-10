import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/app/app_strings.dart';
import 'package:mobile/models/codex_thread_item.dart';
import 'package:mobile/services/thread_message_list_projection.dart';
import 'package:mobile/widgets/thread_message_list.dart';

void main() {
  testWidgets('hides completed status chips for user bubbles', (tester) async {
    final projection = projectThreadMessageList([
      CodexThreadItem(
        id: 'user-1',
        type: 'user.message',
        title: 'User message',
        body: 'hide completed badge',
        status: 'completed',
        actor: 'user',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        raw: const {'turnId': 'turn-1'},
      ),
    ]);

    await tester.pumpWidget(
      _buildTestApp(
        child: ThreadMessageList(
          projection: projection,
          loading: false,
          errorMessage: null,
          scrollController: ScrollController(),
          onRefresh: () async {},
          onScrollNotification: (_) => false,
          workspaceStyle: false,
          showLiveStatus: false,
          liveStateLabel: '',
          liveMessage: '',
          hasActiveTurn: false,
          stickToBottom: false,
          showScrollToBottomButton: false,
          onScrollToBottom: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You'), findsOneWidget);
    expect(find.text('hide completed badge'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
  });

  testWidgets('collapses long user messages and allows expanding', (tester) async {
    final longBody = List.filled(
      14,
      'This is a long user prompt line used to verify bubble collapsing behavior.',
    ).join('\n');
    final projection = projectThreadMessageList([
      CodexThreadItem(
        id: 'user-long-1',
        type: 'user.message',
        title: 'User message',
        body: longBody,
        status: 'completed',
        actor: 'user',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        raw: const {'turnId': 'turn-long-1'},
      ),
    ]);

    await tester.pumpWidget(
      _buildTestApp(
        child: ThreadMessageList(
          projection: projection,
          loading: false,
          errorMessage: null,
          scrollController: ScrollController(),
          onRefresh: () async {},
          onScrollNotification: (_) => false,
          workspaceStyle: false,
          showLiveStatus: false,
          liveStateLabel: '',
          liveMessage: '',
          hasActiveTurn: false,
          stickToBottom: false,
          showScrollToBottomButton: false,
          onScrollToBottom: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Expand'), findsOneWidget);
    expect(find.text('Collapse'), findsNothing);

    await tester.tap(find.text('Expand'));
    await tester.pumpAndSettle();
    expect(find.text('Collapse'), findsOneWidget);
  });

  testWidgets('uses hidden assistant items as the timestamp fallback', (
    tester,
  ) async {
    final projection = projectThreadMessageList([
      CodexThreadItem(
        id: 'user-1',
        type: 'user.message',
        title: 'User message',
        body: 'fix time',
        status: 'completed',
        actor: 'user',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
        raw: const {'turnId': 'turn-1'},
      ),
      CodexThreadItem(
        id: 'agent-1',
        type: 'agent.message',
        title: 'Assistant message (commentary)',
        body: 'checking',
        status: 'completed',
        actor: 'assistant',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
        raw: const {'turnId': 'turn-1', 'phase': 'commentary'},
      ),
      const CodexThreadItem(
        id: 'agent-2',
        type: 'agent.message',
        title: 'Assistant message (final_answer)',
        body: 'done',
        status: 'final_answer',
        actor: 'assistant',
        raw: {'turnId': 'turn-1', 'phase': 'final_answer'},
      ),
    ]);

    await tester.pumpWidget(
      _buildTestApp(
        child: ThreadMessageList(
          projection: projection,
          loading: false,
          errorMessage: null,
          scrollController: ScrollController(),
          onRefresh: () async {},
          onScrollNotification: (_) => false,
          workspaceStyle: false,
          showLiveStatus: false,
          liveStateLabel: '',
          liveMessage: '',
          hasActiveTurn: false,
          stickToBottom: false,
          showScrollToBottomButton: false,
          onScrollToBottom: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('done'), findsOneWidget);
    expect(find.text('Final answer'), findsOneWidget);
    expect(find.text('2m ago'), findsOneWidget);
    expect(find.text('Unknown time'), findsNothing);
  });

  testWidgets('does not show merged operation card inside the final answer bubble', (
    tester,
  ) async {
    final projection = projectThreadMessageList([
      CodexThreadItem(
        id: 'user-ops',
        type: 'user.message',
        title: 'User message',
        body: 'apply the change',
        status: 'completed',
        actor: 'user',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 4)),
        raw: const {'turnId': 'turn-ops'},
      ),
      CodexThreadItem(
        id: 'cmd-ops',
        type: 'command.execution',
        title: 'Run command',
        body: 'rg operation',
        status: 'completed',
        actor: 'assistant',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
        raw: const {'turnId': 'turn-ops', 'command': ['rg', 'operation']},
      ),
      CodexThreadItem(
        id: 'file-ops',
        type: 'file.change',
        title: 'Apply patch',
        body: '',
        status: 'completed',
        actor: 'assistant',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
        raw: const {
          'turnId': 'turn-ops',
          'changes': [
            {'path': 'lib/alpha.dart', 'kind': 'updated'},
            {'path': 'lib/beta.dart', 'kind': 'updated'},
          ],
        },
      ),
      CodexThreadItem(
        id: 'final-ops',
        type: 'agent.message',
        title: 'Final answer',
        body: 'done',
        status: 'completed',
        actor: 'assistant',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        raw: const {'turnId': 'turn-ops', 'phase': 'final_answer'},
      ),
    ]);

    await tester.pumpWidget(
      _buildTestApp(
        child: ThreadMessageList(
          projection: projection,
          loading: false,
          errorMessage: null,
          scrollController: ScrollController(),
          onRefresh: () async {},
          onScrollNotification: (_) => false,
          workspaceStyle: false,
          showLiveStatus: false,
          liveStateLabel: '',
          liveMessage: '',
          hasActiveTurn: false,
          stickToBottom: false,
          showScrollToBottomButton: false,
          onScrollToBottom: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edited 2 files and ran 1 command'), findsNothing);
    expect(find.text('done'), findsOneWidget);
    expect(find.text('rg operation'), findsNothing);
    expect(find.text('alpha.dart'), findsNothing);
    expect(find.text('beta.dart'), findsNothing);
  });

  testWidgets('shows merged operation card for any consecutive operation run', (
    tester,
  ) async {
    final projection = projectThreadMessageList([
      CodexThreadItem(
        id: 'user-boundary',
        type: 'user.message',
        title: 'User message',
        body: 'collapse only between texts',
        status: 'completed',
        actor: 'user',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        raw: const {'turnId': 'turn-boundary'},
      ),
      CodexThreadItem(
        id: 'agent-before',
        type: 'agent.message',
        title: 'Assistant message',
        body: 'checking files',
        status: 'completed',
        actor: 'assistant',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 4)),
        raw: const {'turnId': 'turn-boundary', 'phase': 'commentary'},
      ),
      CodexThreadItem(
        id: 'cmd-boundary',
        type: 'command.execution',
        title: 'Run command',
        body: 'rg boundary',
        status: 'completed',
        actor: 'assistant',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
        raw: const {'turnId': 'turn-boundary', 'command': ['rg', 'boundary']},
      ),
      CodexThreadItem(
        id: 'file-boundary',
        type: 'file.change',
        title: 'Apply patch',
        body: '',
        status: 'completed',
        actor: 'assistant',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
        raw: const {
          'turnId': 'turn-boundary',
          'changes': [
            {'path': 'lib/left.dart', 'kind': 'updated'},
            {'path': 'lib/right.dart', 'kind': 'updated'},
          ],
        },
      ),
    ]);

    await tester.pumpWidget(
      _buildTestApp(
        child: ThreadMessageList(
          projection: projection,
          loading: false,
          errorMessage: null,
          scrollController: ScrollController(),
          onRefresh: () async {},
          onScrollNotification: (_) => false,
          workspaceStyle: false,
          showLiveStatus: false,
          liveStateLabel: '',
          liveMessage: '',
          hasActiveTurn: false,
          stickToBottom: false,
          showScrollToBottomButton: false,
          onScrollToBottom: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edited 2 files and ran 1 command'), findsOneWidget);
    expect(find.text('checking files'), findsOneWidget);
    expect(find.text('rg boundary'), findsNothing);
    expect(find.text('left.dart'), findsNothing);
    expect(find.text('right.dart'), findsNothing);
  });

  testWidgets('keeps earlier assistant text visible when later text arrives', (
    tester,
  ) async {
    final projection = projectThreadMessageList([
      CodexThreadItem(
        id: 'user-text',
        type: 'user.message',
        title: 'User message',
        body: 'preserve the text order',
        status: 'completed',
        actor: 'user',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 4)),
        raw: const {'turnId': 'turn-text'},
      ),
      CodexThreadItem(
        id: 'agent-text-1',
        type: 'agent.message',
        title: 'Assistant message',
        body: 'first text',
        status: 'completed',
        actor: 'assistant',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
        raw: const {'turnId': 'turn-text', 'phase': 'commentary'},
      ),
      CodexThreadItem(
        id: 'cmd-text',
        type: 'command.execution',
        title: 'Run command',
        body: 'rg text',
        status: 'completed',
        actor: 'assistant',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
        raw: const {'turnId': 'turn-text', 'command': ['rg', 'text']},
      ),
      CodexThreadItem(
        id: 'agent-text-2',
        type: 'agent.message',
        title: 'Assistant message',
        body: 'second text',
        status: 'completed',
        actor: 'assistant',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        raw: const {'turnId': 'turn-text', 'phase': 'streaming'},
      ),
    ]);

    await tester.pumpWidget(
      _buildTestApp(
        child: ThreadMessageList(
          projection: projection,
          loading: false,
          errorMessage: null,
          scrollController: ScrollController(),
          onRefresh: () async {},
          onScrollNotification: (_) => false,
          workspaceStyle: false,
          showLiveStatus: false,
          liveStateLabel: '',
          liveMessage: '',
          hasActiveTurn: false,
          stickToBottom: false,
          showScrollToBottomButton: false,
          onScrollToBottom: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('first text'), findsOneWidget);
    expect(find.text('second text'), findsOneWidget);
    expect(find.text('Ran 1 command'), findsNothing);
  });
}

Widget _buildTestApp({required Widget child, Locale? locale}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}
