import '../utils/json_utils.dart';
import 'codex_pending_request.dart';

class CodexThreadRuntime {
  const CodexThreadRuntime({
    required this.threadId,
    this.activeTurnId,
    this.pendingRequests = const [],
  });

  final String threadId;
  final String? activeTurnId;
  final List<CodexPendingRequest> pendingRequests;

  CodexThreadRuntime copyWith({
    String? threadId,
    String? activeTurnId,
    bool clearActiveTurnId = false,
    List<CodexPendingRequest>? pendingRequests,
  }) {
    return CodexThreadRuntime(
      threadId: threadId ?? this.threadId,
      activeTurnId: clearActiveTurnId
          ? null
          : (activeTurnId ?? this.activeTurnId),
      pendingRequests: pendingRequests ?? this.pendingRequests,
    );
  }

  factory CodexThreadRuntime.fromJson(Map<String, dynamic> json) {
    return CodexThreadRuntime(
      threadId: readString(json, const ['threadId'], fallback: 'thread'),
      activeTurnId: readString(json, const ['activeTurnId']).trim().isEmpty
          ? null
          : readString(json, const ['activeTurnId']),
      pendingRequests: asJsonList(
        json['pendingRequests'],
      ).map(asJsonMap).map(CodexPendingRequest.fromJson).toList(
        growable: false,
      ),
    );
  }
}
