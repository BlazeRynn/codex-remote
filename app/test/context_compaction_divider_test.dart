import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/codex_thread_item.dart';
import 'package:mobile/widgets/context_compaction_divider.dart';

void main() {
  testWidgets('shows an in-progress context compaction divider with a timer', (
    tester,
  ) async {
    final item = CodexThreadItem(
      id: 'compaction-1',
      type: 'context.compaction',
      title: 'Context compaction',
      body: '',
      status: 'in_progress',
      actor: 'assistant',
      createdAt: DateTime.now().toUtc().subtract(const Duration(seconds: 3)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ContextCompactionDivider(item: item)),
      ),
    );

    final initialLabelFinder = find.textContaining('Compressing context ');
    expect(initialLabelFinder, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);

    final initialLabel = tester.widget<Text>(initialLabelFinder).data;
    await tester.pump(const Duration(seconds: 1));

    final updatedLabel = tester
        .widget<Text>(find.textContaining('Compressing context '))
        .data;
    expect(updatedLabel, isNot(initialLabel));
  });

  testWidgets('shows a completed context compaction divider', (tester) async {
    const item = CodexThreadItem(
      id: 'compaction-2',
      type: 'context.compaction',
      title: 'Context compaction',
      body: 'Compacted prior turns.',
      status: 'completed',
      actor: 'assistant',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ContextCompactionDivider(item: item)),
      ),
    );

    expect(find.text('Context compressed'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets(
    'replaces the in-progress divider text when compaction completes',
    (tester) async {
      final startedAt = DateTime.now().toUtc().subtract(
        const Duration(seconds: 4),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextCompactionDivider(
              item: CodexThreadItem(
                id: 'compaction-1',
                type: 'context.compaction',
                title: 'Context compaction',
                body: '',
                status: 'in_progress',
                actor: 'assistant',
                createdAt: startedAt,
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('Compressing context '), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextCompactionDivider(
              item: CodexThreadItem(
                id: 'compaction-1',
                type: 'context.compaction',
                title: 'Context compaction',
                body: 'Compacted prior turns.',
                status: 'completed',
                actor: 'assistant',
                createdAt: startedAt,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Compressing context '), findsNothing);
      expect(find.text('Context compressed'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    },
  );

  testWidgets('keeps the timer from raw timestamps when createdAt is absent', (
    tester,
  ) async {
    final startedAt = DateTime.now().toUtc().subtract(
      const Duration(seconds: 5),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextCompactionDivider(
            item: CodexThreadItem(
              id: 'compaction-raw-timestamp',
              type: 'context.compaction',
              title: 'Context compaction',
              body: '',
              status: 'in_progress',
              actor: 'assistant',
              raw: {'turnOccurredAt': startedAt.toIso8601String()},
            ),
          ),
        ),
      ),
    );

    final label = tester
        .widget<Text>(find.textContaining('Compressing context '))
        .data;
    expect(label, isNot(contains('00:00')));
  });

  test('recognizes legacy realtime context compaction item types', () {
    const item = CodexThreadItem(
      id: 'compaction-3',
      type: 'contextCompaction',
      title: 'contextCompaction',
      body: '',
      status: 'started',
      actor: 'assistant',
      raw: {'type': 'contextCompaction'},
    );

    expect(isContextCompactionItem(item), isTrue);
    expect(isContextCompactionComplete(item), isFalse);
  });
}
