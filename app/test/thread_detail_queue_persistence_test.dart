import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app_strings.dart';
import 'package:mobile/models/bridge_config.dart';
import 'package:mobile/models/bridge_health.dart';
import 'package:mobile/models/codex_composer_mode.dart';
import 'package:mobile/models/codex_directory_entry.dart';
import 'package:mobile/models/codex_input_part.dart';
import 'package:mobile/models/codex_model_option.dart';
import 'package:mobile/models/codex_thread_bundle.dart';
import 'package:mobile/models/codex_thread_runtime.dart';
import 'package:mobile/models/codex_thread_summary.dart';
import 'package:mobile/screens/thread_detail_screen.dart';
import 'package:mobile/services/bridge_realtime_client.dart';
import 'package:mobile/services/codex_repository.dart';

void main() {
  testWidgets('queued prompts survive leaving and reopening thread detail', (
    WidgetTester tester,
  ) async {
    final thread = CodexThreadSummary(
      id: 'thread-queue-persist',
      title: 'Queue persistence',
      status: 'active',
      preview: 'Preview',
      cwd: r'C:\workspace\queue',
      updatedAt: DateTime.utc(2026, 4, 13),
    );
    final repository = _FakeCodexRepository(
      bundle: CodexThreadBundle(thread: thread, items: const []),
      runtime: const CodexThreadRuntime(
        threadId: 'thread-queue-persist',
        activeTurnId: 'turn-1',
      ),
    );

    await tester.pumpWidget(_buildTestApp(thread, repository));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(TextField), 'Queued persistence prompt');
    await tester.tap(find.byType(TextField));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Queued persistence prompt'), findsOneWidget);
    expect(repository.sendMessageCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(_buildTestApp(thread, repository));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Queued persistence prompt'), findsOneWidget);
    expect(repository.sendMessageCalls, 0);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });
}

Widget _buildTestApp(CodexThreadSummary thread, CodexRepository repository) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: ThreadDetailScreen(
      config: BridgeConfig.empty,
      thread: thread,
      repository: repository,
    ),
  );
}

class _FakeCodexRepository implements CodexRepository {
  _FakeCodexRepository({required this.bundle, required this.runtime});

  final CodexThreadBundle bundle;
  final CodexThreadRuntime runtime;
  int sendMessageCalls = 0;

  @override
  Future<BridgeHealth> getHealth() async {
    return const BridgeHealth(reachable: true, status: 'online', message: 'ok');
  }

  @override
  Future<List<CodexThreadSummary>> listThreads() async => [bundle.thread];

  @override
  Future<CodexThreadBundle> getThreadBundle(String threadId) async => bundle;

  @override
  Future<List<CodexModelOption>> listModels() async => const [
    CodexModelOption(
      id: 'model-default',
      model: 'model-default',
      displayName: 'Default model',
      description: 'Default model',
      isDefault: true,
    ),
  ];

  @override
  Future<CodexThreadRuntime> getThreadRuntime(String threadId) async => runtime;

  @override
  Future<String?> getDefaultWorkspacePath() async => bundle.thread.cwd;

  @override
  Future<List<CodexDirectoryEntry>> listWorkspaceRoots() async => const [];

  @override
  Future<List<CodexDirectoryEntry>> listWorkspaceDirectories(
    String path,
  ) async {
    return const [];
  }

  @override
  Future<CodexThreadBundle> createThread({
    required List<CodexInputPart> input,
    required CodexComposerMode mode,
    String? model,
    String? cwd,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<CodexThreadRuntime> sendMessage({
    required String threadId,
    required List<CodexInputPart> input,
    String? expectedTurnId,
    String? model,
    CodexComposerMode? mode,
    String? cwd,
  }) async {
    sendMessageCalls += 1;
    return runtime;
  }

  @override
  Future<CodexThreadRuntime> interruptTurn({
    required String threadId,
    String? turnId,
  }) async {
    return const CodexThreadRuntime(threadId: 'thread-queue-persist');
  }

  @override
  Future<CodexThreadRuntime> respondToPendingRequest({
    required String requestId,
    required String action,
    Map<String, dynamic>? answers,
    Object? content,
  }) async {
    return runtime;
  }

  @override
  CodexRealtimeSession openThreadEvents({String? threadId}) {
    return const _FakeRealtimeSession();
  }
}

class _FakeRealtimeSession implements CodexRealtimeSession {
  const _FakeRealtimeSession();

  @override
  Stream<BridgeRealtimeEvent> get stream => const Stream.empty();

  @override
  Future<void> close() async {}
}
