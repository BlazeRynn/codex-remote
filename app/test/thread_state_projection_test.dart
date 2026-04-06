import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/codex_pending_request.dart';
import 'package:mobile/models/codex_thread_runtime.dart';
import 'package:mobile/models/codex_thread_summary.dart';
import 'package:mobile/services/bridge_realtime_client.dart';
import 'package:mobile/services/thread_state_projection.dart';

void main() {
  test('projects active status onto matching thread summary', () {
    final thread = CodexThreadSummary(
      id: 'thread-1',
      title: 'Session',
      status: 'idle',
      preview: 'preview',
    );
    final event = _event(
      type: 'thread.status',
      threadId: 'thread-1',
      params: {
        'threadId': 'thread-1',
        'status': {'type': 'active'},
      },
    );

    final updated = projectRealtimeStatusOnThread(thread, event);

    expect(updated.status, 'active');
    expect(updated.updatedAt, event.receivedAt);
  });

  test('projects turn start and completion onto runtime', () {
    final runtime = CodexThreadRuntime(threadId: 'thread-2');
    final started = _event(
      type: 'turn.started',
      threadId: 'thread-2',
      params: {
        'threadId': 'thread-2',
        'turn': {'id': 'turn-2'},
      },
    );
    final completed = _event(
      type: 'turn.completed',
      threadId: 'thread-2',
      params: {
        'threadId': 'thread-2',
        'turn': {'id': 'turn-2'},
      },
    );

    final activeRuntime = projectRealtimeStatusOnRuntime(runtime, started);
    final idleRuntime = projectRealtimeStatusOnRuntime(
      activeRuntime,
      completed,
    );

    expect(activeRuntime.activeTurnId, 'turn-2');
    expect(idleRuntime.activeTurnId, isNull);
  });

  test('ignores events for other threads', () {
    final thread = CodexThreadSummary(
      id: 'thread-3',
      title: 'Session',
      status: 'idle',
      preview: 'preview',
    );
    final event = _event(
      type: 'turn.started',
      threadId: 'thread-x',
      params: {
        'threadId': 'thread-x',
        'turn': {'id': 'turn-x'},
      },
    );

    final updatedThread = projectRealtimeStatusOnThread(thread, event);

    expect(identical(updatedThread, thread), isTrue);
  });

  test('clears runtime when thread status becomes idle', () {
    final runtime = CodexThreadRuntime(
      threadId: 'thread-4',
      activeTurnId: 'turn-4',
    );
    final event = _event(
      type: 'thread.status',
      threadId: 'thread-4',
      params: {
        'threadId': 'thread-4',
        'status': {'type': 'idle'},
      },
    );

    final updated = projectRealtimeStatusOnRuntime(runtime, event);

    expect(updated.activeTurnId, isNull);
  });

  test('removes resolved pending requests from runtime', () {
    final request = CodexPendingRequest(
      id: 'req-1',
      kind: 'command_approval',
      title: 'Approve command',
      message: 'Allow command?',
      actions: const [],
      questions: const [],
      formFields: const [],
      receivedAt: DateTime.utc(2026, 4, 5, 11, 59),
      threadId: 'thread-5',
    );
    final runtime = CodexThreadRuntime(
      threadId: 'thread-5',
      pendingRequests: [request],
    );
    final event = _event(
      type: 'server.request.resolved',
      threadId: 'thread-5',
      params: {'threadId': 'thread-5', 'requestId': 'req-1'},
      raw: const {'requestId': 'req-1'},
    );

    final updated = projectRealtimeStatusOnRuntime(runtime, event);

    expect(updated.pendingRequests, isEmpty);
  });
}

BridgeRealtimeEvent _event({
  required String type,
  required String threadId,
  required Map<String, dynamic> params,
  Map<String, dynamic> raw = const {},
}) {
  final receivedAt = DateTime.utc(2026, 4, 5, 12);
  return BridgeRealtimeEvent(
    type: type,
    description: type,
    receivedAt: receivedAt,
    raw: {...raw, 'threadId': threadId, 'params': params},
  );
}
