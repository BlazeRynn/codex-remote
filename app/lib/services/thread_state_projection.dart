import '../models/codex_thread_runtime.dart';
import '../models/codex_thread_summary.dart';
import 'bridge_realtime_client.dart';
import 'realtime_event_helpers.dart';

CodexThreadSummary projectRealtimeStatusOnThread(
  CodexThreadSummary thread,
  BridgeRealtimeEvent event,
) {
  final eventThreadId = realtimeEventThreadId(event);
  if (eventThreadId == null || eventThreadId != thread.id) {
    return thread;
  }

  final nextUpdatedAt = _laterTimestamp(thread.updatedAt, event.receivedAt);
  switch (event.type) {
    case 'thread.status':
      final status = realtimeEventThreadStatusType(event);
      if (status == null) {
        return thread;
      }
      return thread.copyWith(status: status, updatedAt: nextUpdatedAt);
    case 'turn.started':
      return thread.copyWith(status: 'active', updatedAt: nextUpdatedAt);
    case 'turn.completed':
      return thread.copyWith(status: 'idle', updatedAt: nextUpdatedAt);
    default:
      if (_isStreamingActivityEvent(event)) {
        return thread.copyWith(status: 'active', updatedAt: nextUpdatedAt);
      }
      return thread;
  }
}

CodexThreadRuntime projectRealtimeStatusOnRuntime(
  CodexThreadRuntime runtime,
  BridgeRealtimeEvent event,
) {
  final eventThreadId = realtimeEventThreadId(event);
  if (eventThreadId == null || eventThreadId != runtime.threadId) {
    return runtime;
  }

  switch (event.type) {
    case 'turn.started':
      final turnId = realtimeEventTurnId(event);
      return turnId == null ? runtime : runtime.copyWith(activeTurnId: turnId);
    case 'turn.completed':
      final turnId = realtimeEventTurnId(event);
      if (turnId == null ||
          runtime.activeTurnId == null ||
          runtime.activeTurnId == turnId) {
        return runtime.copyWith(clearActiveTurnId: true);
      }
      return runtime;
    case 'thread.status':
      final status = realtimeEventThreadStatusType(event);
      if (status == 'idle') {
        return runtime.copyWith(clearActiveTurnId: true);
      }
      return runtime;
    case 'server.request.resolved':
      final requestId = realtimeEventRequestId(event);
      if (requestId == null) {
        return runtime;
      }
      return runtime.copyWith(
        pendingRequests: runtime.pendingRequests
            .where((request) => request.id != requestId)
            .toList(growable: false),
      );
    default:
      if (_isStreamingActivityEvent(event)) {
        final turnId = realtimeEventTurnId(event);
        return turnId == null ? runtime : runtime.copyWith(activeTurnId: turnId);
      }
      return runtime;
  }
}

bool _isStreamingActivityEvent(BridgeRealtimeEvent event) {
  final method = realtimeEventMethod(event) ?? '';
  if (method == 'item/agentMessage/delta' ||
      method == 'item/plan/delta' ||
      method == 'item/commandExecution/outputDelta' ||
      method == 'item/fileChange/outputDelta' ||
      method == 'item/reasoning/summaryTextDelta' ||
      method == 'item/reasoning/textDelta' ||
      method == 'thread/realtime/transcriptUpdated') {
    return true;
  }

  return event.type == 'thread.realtime.started' ||
      event.type == 'thread.realtime.item.added' ||
      event.type == 'thread.realtime.transcript.updated' ||
      event.type.endsWith('.delta') ||
      event.type.endsWith('.updated');
}

DateTime _laterTimestamp(DateTime? current, DateTime next) {
  if (current == null || next.isAfter(current)) {
    return next;
  }
  return current;
}
