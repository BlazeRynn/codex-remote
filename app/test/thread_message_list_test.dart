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
        body: '不要显示已完成',
        status: 'completed',
        actor: 'user',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        raw: const {'turnId': 'turn-1'},
      ),
    ]);

    await tester.pumpWidget(
      _buildTestApp(
        locale: const Locale('zh'),
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
          showScrollToBottomButton: false,
          onScrollToBottom: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你'), findsOneWidget);
    expect(find.text('不要显示已完成'), findsOneWidget);
    expect(find.text('已完成'), findsNothing);
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
