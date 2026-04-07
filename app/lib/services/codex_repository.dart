import 'dart:async';

import '../models/bridge_config.dart';
import '../models/bridge_health.dart';
import '../models/codex_composer_mode.dart';
import '../models/codex_input_part.dart';
import '../models/codex_model_option.dart';
import '../models/codex_thread_bundle.dart';
import '../models/codex_thread_runtime.dart';
import '../models/codex_thread_summary.dart';
import '../services/bridge_realtime_client.dart';
import 'app_server_rpc_client.dart';
import 'demo_codex_repository.dart';

abstract class CodexRealtimeSession {
  Stream<BridgeRealtimeEvent> get stream;

  Future<void> close();
}

abstract class CodexRepository {
  Future<BridgeHealth> getHealth();

  Future<List<CodexThreadSummary>> listThreads();

  Future<CodexThreadBundle> getThreadBundle(String threadId);

  Future<List<CodexModelOption>> listModels();

  Future<CodexThreadRuntime> getThreadRuntime(String threadId);

  Future<CodexThreadBundle> createThread({
    required List<CodexInputPart> input,
    required CodexComposerMode mode,
    String? model,
    String? cwd,
  });

  Future<CodexThreadRuntime> sendMessage({
    required String threadId,
    required List<CodexInputPart> input,
    String? expectedTurnId,
    String? model,
    CodexComposerMode? mode,
    String? cwd,
  });

  Future<CodexThreadRuntime> interruptTurn({
    required String threadId,
    String? turnId,
  });

  Future<CodexThreadRuntime> respondToPendingRequest({
    required String requestId,
    required String action,
    Map<String, dynamic>? answers,
    Object? content,
  });

  CodexRealtimeSession openThreadEvents({String? threadId});
}

CodexRepository createCodexRepository(BridgeConfig config) {
  if (config.usesDemoData) {
    return DemoCodexRepository(config);
  }

  return AppServerCodexRepository(config);
}

class AppServerCodexRepository implements CodexRepository {
  AppServerCodexRepository(this.config)
    : _client = AppServerRpcClient.shared(config);

  final BridgeConfig config;
  final AppServerRpcClient _client;

  @override
  Future<BridgeHealth> getHealth() => _client.getHealth();

  @override
  Future<List<CodexThreadSummary>> listThreads() => _client.listThreads();

  @override
  Future<CodexThreadBundle> getThreadBundle(String threadId) {
    return _client.getThreadBundle(threadId);
  }

  @override
  Future<List<CodexModelOption>> listModels() => _client.listModels();

  @override
  Future<CodexThreadRuntime> getThreadRuntime(String threadId) {
    return _client.getThreadRuntime(threadId);
  }

  @override
  Future<CodexThreadBundle> createThread({
    required List<CodexInputPart> input,
    required CodexComposerMode mode,
    String? model,
    String? cwd,
  }) {
    return _client.createThread(
      input: input,
      mode: mode,
      model: model,
      cwd: cwd,
    );
  }

  @override
  Future<CodexThreadRuntime> sendMessage({
    required String threadId,
    required List<CodexInputPart> input,
    String? expectedTurnId,
    String? model,
    CodexComposerMode? mode,
    String? cwd,
  }) {
    return _client.sendMessage(
      threadId: threadId,
      input: input,
      expectedTurnId: expectedTurnId,
      model: model,
      mode: mode,
      cwd: cwd,
    );
  }

  @override
  Future<CodexThreadRuntime> interruptTurn({
    required String threadId,
    String? turnId,
  }) {
    return _client.interruptTurn(threadId: threadId, turnId: turnId);
  }

  @override
  Future<CodexThreadRuntime> respondToPendingRequest({
    required String requestId,
    required String action,
    Map<String, dynamic>? answers,
    Object? content,
  }) {
    return _client.respondToPendingRequest(
      requestId: requestId,
      action: action,
      answers: answers,
      content: content,
    );
  }

  @override
  CodexRealtimeSession openThreadEvents({String? threadId}) {
    return _AppServerRealtimeRepositorySession(
      client: threadId == null || threadId.trim().isEmpty
          ? _client
          : AppServerRpcClient.dedicated(config),
      threadId: threadId,
      ownsClient: threadId != null && threadId.trim().isNotEmpty,
    );
  }
}

class _AppServerRealtimeRepositorySession implements CodexRealtimeSession {
  _AppServerRealtimeRepositorySession({
    required AppServerRpcClient client,
    this.threadId,
    required this.ownsClient,
  }) : _client = client,
       stream = Stream.multi((controller) {
         unawaited(
           client
               .ensureConnected()
               .then((_) async {
                 if (threadId != null && threadId.isNotEmpty) {
                   try {
                     await client.attachThread(threadId);
                     controller.add(
                       BridgeRealtimeEvent(
                         type: 'app_server.attached',
                         description: 'Attached to thread realtime stream',
                         receivedAt: DateTime.now().toUtc(),
                         raw: {
                           'type': 'app_server.attached',
                           'message': 'Attached to thread realtime stream',
                           'threadId': threadId,
                         },
                       ),
                     );
                   } on AppServerRpcException catch (error) {
                     if (!_isMissingRollout(error)) {
                       rethrow;
                     }
                     controller.add(
                       BridgeRealtimeEvent(
                         type: 'app_server.attach.skipped',
                         description: error.message,
                         receivedAt: DateTime.now().toUtc(),
                         raw: {
                           'type': 'app_server.attach.skipped',
                           'message': error.message,
                           'threadId': threadId,
                         },
                       ),
                     );
                   }
                 }
                 controller.add(
                   BridgeRealtimeEvent(
                     type: 'app_server.connected',
                     description: 'Connected to local Codex app-server',
                     receivedAt: DateTime.now().toUtc(),
                     raw: {
                       'type': 'app_server.connected',
                       'message': 'Connected to local Codex app-server',
                       if (threadId != null && threadId.isNotEmpty)
                         'threadId': threadId,
                     },
                   ),
                 );
               })
               .catchError((Object error, StackTrace stackTrace) {
                 controller.addError(error, stackTrace);
               }),
         );

         final subscription = client
             .events(threadId: threadId)
             .listen(
               controller.add,
               onError: controller.addError,
               onDone: controller.close,
             );

         controller.onCancel = () async {
           await subscription.cancel();
           if (ownsClient) {
             await client.close();
           }
         };
       });

  final String? threadId;
  final AppServerRpcClient _client;
  final bool ownsClient;

  @override
  final Stream<BridgeRealtimeEvent> stream;

  @override
  Future<void> close() async {
    if (ownsClient) {
      await _client.close();
    }
  }
}

bool _isMissingRollout(AppServerRpcException error) {
  return error.message.toLowerCase().contains('no rollout found');
}
