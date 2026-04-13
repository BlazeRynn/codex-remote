import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app_strings.dart';
import 'package:mobile/models/bridge_config.dart';
import 'package:mobile/models/bridge_health.dart';
import 'package:mobile/models/codex_composer_mode.dart';
import 'package:mobile/models/codex_directory_entry.dart';
import 'package:mobile/models/codex_input_part.dart';
import 'package:mobile/models/codex_model_option.dart';
import 'package:mobile/models/codex_pending_request.dart';
import 'package:mobile/models/codex_thread_bundle.dart';
import 'package:mobile/models/codex_thread_runtime.dart';
import 'package:mobile/models/codex_thread_summary.dart';
import 'package:mobile/screens/thread_detail_screen.dart';
import 'package:mobile/services/bridge_realtime_client.dart';
import 'package:mobile/services/codex_repository.dart';

void main() {
  testWidgets('mobile approvals are merged into one grouped card', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final thread = CodexThreadSummary(
      id: 'thread-mobile-approvals',
      title: 'Approvals',
      status: 'idle',
      preview: 'Preview',
      cwd: r'C:\workspace\mobile',
      updatedAt: DateTime.utc(2026, 4, 13),
    );
    final runtime = CodexThreadRuntime(
      threadId: thread.id,
      pendingRequests: [
        CodexPendingRequest(
          id: 'req-1',
          kind: 'command_approval',
          title: 'Run tests',
          message: 'Approve npm test',
          actions: const [
            CodexPendingAction(
              id: 'approve',
              label: 'Approve',
              recommended: true,
              destructive: false,
            ),
            CodexPendingAction(
              id: 'deny',
              label: 'Deny',
              recommended: false,
              destructive: true,
            ),
          ],
          questions: const [],
          formFields: const [],
          receivedAt: DateTime.utc(2026, 4, 13, 9),
          command: 'npm test',
        ),
        CodexPendingRequest(
          id: 'req-2',
          kind: 'file_change_approval',
          title: 'Apply patch',
          message: 'Approve file edits',
          actions: const [
            CodexPendingAction(
              id: 'approve',
              label: 'Approve',
              recommended: true,
              destructive: false,
            ),
            CodexPendingAction(
              id: 'approve_for_session',
              label: 'Approve for session',
              recommended: false,
              destructive: false,
            ),
          ],
          questions: const [],
          formFields: const [],
          receivedAt: DateTime.utc(2026, 4, 13, 10),
          detail: '2 files changed',
        ),
      ],
    );
    final repository = _FakeApprovalRepository(
      bundle: CodexThreadBundle(thread: thread, items: const []),
      runtime: runtime,
    );

    await tester.pumpWidget(_buildTestApp(thread, repository));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('2 approvals waiting'), findsOneWidget);
    expect(find.textContaining('Run tests'), findsOneWidget);
    expect(find.textContaining('Apply patch'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsNWidgets(2));

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

class _FakeApprovalRepository implements CodexRepository {
  _FakeApprovalRepository({required this.bundle, required this.runtime});

  final CodexThreadBundle bundle;
  final CodexThreadRuntime runtime;

  @override
  Future<BridgeHealth> getHealth() async {
    return const BridgeHealth(reachable: true, status: 'online');
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
  ) async => const [];

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
  }) async => runtime;

  @override
  Future<CodexThreadRuntime> interruptTurn({
    required String threadId,
    String? turnId,
  }) async => runtime;

  @override
  Future<CodexThreadRuntime> respondToPendingRequest({
    required String requestId,
    required String action,
    Map<String, dynamic>? answers,
    Object? content,
  }) async => runtime;

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
