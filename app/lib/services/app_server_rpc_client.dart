import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/bridge_config.dart';
import '../models/bridge_health.dart';
import '../models/codex_composer_mode.dart';
import '../models/codex_directory_entry.dart';
import '../models/codex_input_part.dart';
import '../models/codex_model_option.dart';
import '../models/codex_pending_request.dart';
import '../models/codex_thread_bundle.dart';
import '../models/codex_thread_item.dart';
import '../models/codex_thread_runtime.dart';
import '../models/codex_thread_summary.dart';
import '../utils/json_utils.dart';
import 'app_server_log_store.dart';
import 'bridge_realtime_client.dart';
import 'command_execution_presentation.dart';
import 'realtime_event_helpers.dart';
import 'thread_message_content.dart';
import 'thread_item_timestamps.dart';
import 'ui_debug_logger.dart';

class AppServerRpcClient {
  AppServerRpcClient._(this._config, {this.sharedKey});

  static final Map<String, AppServerRpcClient> _sharedClients = {};

  static AppServerRpcClient shared(BridgeConfig config) {
    final key = config.resolveRpcUri().toString();
    return _sharedClients.putIfAbsent(
      key,
      () => AppServerRpcClient._(config, sharedKey: key),
    );
  }

  static AppServerRpcClient dedicated(BridgeConfig config) {
    return AppServerRpcClient._(config);
  }

  final BridgeConfig _config;
  final String? sharedKey;
  final StreamController<BridgeRealtimeEvent> _eventsController =
      StreamController<BridgeRealtimeEvent>.broadcast();

  final Map<int, _PendingClientRequest> _pendingClientRequests = {};
  final Map<String, _PendingServerRequestRecord> _pendingServerRequests = {};

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Future<void>? _connecting;
  int _requestId = 1;
  bool _initialized = false;
  bool _disposed = false;
  String? _userAgent;

  Stream<BridgeRealtimeEvent> events({String? threadId}) {
    if (threadId == null || threadId.trim().isEmpty) {
      return _eventsController.stream;
    }

    return _eventsController.stream.where((event) {
      final effectiveThreadId = realtimeEventThreadId(event) ?? '';
      return effectiveThreadId.isEmpty || effectiveThreadId == threadId;
    });
  }

  Future<void> ensureConnected() async {
    if (_disposed) {
      throw const AppServerRpcException('Codex app-server client was closed.');
    }
    if (_isConnected && _initialized) {
      return;
    }

    if (_connecting != null) {
      return _connecting!;
    }

    _connecting = _connectAndInitialize();
    try {
      await _connecting;
    } finally {
      _connecting = null;
    }
  }

  Future<BridgeHealth> getHealth() async {
    try {
      await ensureConnected();
      return BridgeHealth(
        reachable: true,
        status: 'online',
        version: _userAgent,
        message: 'Connected to local Codex app-server',
      );
    } catch (error) {
      return BridgeHealth.offline(error.toString());
    }
  }

  Future<List<CodexThreadSummary>> listThreads({int limit = 100}) async {
    await ensureConnected();
    _logAppServerHistory('thread/list.request', {'limit': limit});
    final modelProvider = await _readConfiguredModelProvider();
    final response = await _request<Map<String, dynamic>>('thread/list', {
      'limit': limit,
      'archived': false,
      if (modelProvider != null) 'modelProviders': [modelProvider],
    });
    final loadedResponse = await _request<Map<String, dynamic>>(
      'thread/loaded/list',
      {'limit': limit},
    );

    final threads = asJsonList(response['data']).map(asJsonMap).toList();
    final loadedIds = asJsonList(
      loadedResponse['data'],
    ).map((value) => value.toString()).toSet();

    threads.sort((left, right) {
      final leftLoaded = loadedIds.contains(readString(left, const ['id']));
      final rightLoaded = loadedIds.contains(readString(right, const ['id']));
      if (leftLoaded != rightLoaded) {
        return leftLoaded ? -1 : 1;
      }

      final leftCreatedAt =
          _deriveThreadCreatedAt(left) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final rightCreatedAt =
          _deriveThreadCreatedAt(right) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final createdComparison = rightCreatedAt.compareTo(leftCreatedAt);
      if (createdComparison != 0) {
        return createdComparison;
      }

      return readString(left, const [
        'id',
      ]).compareTo(readString(right, const ['id']));
    });

    final summaries = threads.map(_mapThreadSummary).toList(growable: false);
    _logAppServerHistory('thread/list.result', {
      'count': summaries.length,
      'loadedCount': loadedIds.length,
      'provider': modelProvider,
    });
    return summaries;
  }

  Future<CodexThreadBundle> getThreadBundle(String threadId) async {
    final thread = await readThread(threadId);
    return _mapThreadBundle(thread);
  }

  Future<CodexThreadRuntime> getThreadRuntime(String threadId) async {
    final thread = await readThread(threadId);
    return _buildThreadRuntime(threadId, thread);
  }

  Future<void> attachThread(String threadId) async {
    await ensureConnected();
    _logAppServerHistory('thread/resume.attach', {'threadId': threadId});
    await _resumeThread(threadId, const <String, dynamic>{});
  }

  Future<List<CodexModelOption>> listModels({int limit = 40}) async {
    await ensureConnected();
    final response = await _request<Map<String, dynamic>>('model/list', {
      'includeHidden': false,
      'limit': limit,
    });

    return asJsonList(response['data'])
        .map(asJsonMap)
        .where((item) => item.isNotEmpty)
        .map(
          (model) => CodexModelOption(
            id: readString(model, const ['id'], fallback: 'model'),
            model: readString(model, const ['model'], fallback: 'model'),
            displayName: readString(model, const [
              'displayName',
              'model',
            ], fallback: 'Model'),
            description: readString(model, const ['description']),
            isDefault: readBool(model, const ['isDefault']) ?? false,
            defaultReasoningEffort:
                readString(model, const [
                  'defaultReasoningEffort',
                ]).trim().isEmpty
                ? null
                : readString(model, const ['defaultReasoningEffort']),
            supportedReasoningEfforts: asJsonList(
              model['supportedReasoningEfforts'],
            ).map((value) => value.toString()).toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  Future<List<CodexDirectoryEntry>> listWorkspaceRoots() async {
    await ensureConnected();
    final response = await _request<Map<String, dynamic>>(
      'workspace/listRoots',
      const <String, dynamic>{},
    );
    return asJsonList(response['data'])
        .map(asJsonMap)
        .map(
          (item) => CodexDirectoryEntry(
            path: readString(item, const ['path']),
            label: readString(item, const ['label', 'name']),
          ),
        )
        .where((entry) => entry.path.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<List<CodexDirectoryEntry>> listWorkspaceDirectories(
    String path,
  ) async {
    await ensureConnected();
    final response = await _request<Map<String, dynamic>>(
      'workspace/listDirectory',
      {'path': path},
    );
    return asJsonList(response['data'])
        .map(asJsonMap)
        .map(
          (item) => CodexDirectoryEntry(
            path: readString(item, const ['path']),
            label: readString(item, const ['label', 'name']),
          ),
        )
        .where((entry) => entry.path.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<String?> getDefaultWorkspacePath() async {
    await ensureConnected();
    try {
      final response = await _request<Map<String, dynamic>>('config/read', {
        'includeLayers': false,
      });
      final config = asJsonMap(response['config']);
      final cwd = readString(config, const [
        'cwd',
        'workingDirectory',
        'working_directory',
        'workspacePath',
      ]).trim();
      if (cwd.isEmpty) {
        return null;
      }
      return _normalizeCwd(cwd);
    } catch (_) {
      return null;
    }
  }

  Future<CodexThreadBundle> createThread({
    required List<CodexInputPart> input,
    required CodexComposerMode mode,
    String? model,
    String? cwd,
  }) async {
    await ensureConnected();
    final overrides = _modeToThreadOverrides(mode);
    final startParams = {
      if (_hasValue(model)) 'model': model,
      if (_hasValue(cwd)) 'cwd': cwd,
      if (overrides.approvalPolicy != null)
        'approvalPolicy': overrides.approvalPolicy,
      if (overrides.sandbox != null) 'sandbox': overrides.sandbox,
      'approvalsReviewer': 'user',
      'persistExtendedHistory': false,
    };
    Map<String, dynamic> response;
    try {
      response = await _request<Map<String, dynamic>>('thread/start', {
        ...startParams,
        'experimentalRawEvents': true,
      });
    } on AppServerRpcException catch (_) {
      response = await _request<Map<String, dynamic>>(
        'thread/start',
        startParams,
      );
    }

    final thread = asJsonMap(response['thread']);
    final threadId = readString(thread, const ['id']);
    await _request<Map<String, dynamic>>('turn/start', {
      'threadId': threadId,
      'input': codexInputPartsToJson(input),
    });

    try {
      return await getThreadBundle(threadId);
    } on AppServerRpcException catch (error) {
      if (_isMaterializationError(error)) {
        _logAppServerHistory('thread/read.materializing', {
          'threadId': threadId,
        });
        return CodexThreadBundle(
          thread: _mapThreadSummary(thread),
          items: const [],
        );
      }
      rethrow;
    }
  }

  Future<CodexThreadRuntime> sendMessage({
    required String threadId,
    required List<CodexInputPart> input,
    String? expectedTurnId,
    String? model,
    CodexComposerMode? mode,
    String? cwd,
  }) async {
    await ensureConnected();

    if (_hasValue(expectedTurnId)) {
      await _request<void>('turn/steer', {
        'threadId': threadId,
        'expectedTurnId': expectedTurnId,
        'input': codexInputPartsToJson(input),
      });
      return getThreadRuntime(threadId);
    }

    final overrides = mode == null
        ? const _ThreadOverrides()
        : _modeToThreadOverrides(mode);
    if (_hasValue(model) ||
        _hasValue(cwd) ||
        overrides.approvalPolicy != null ||
        overrides.sandbox != null) {
      await _resumeThread(threadId, {
        if (_hasValue(model)) 'model': model,
        if (_hasValue(cwd)) 'cwd': cwd,
        if (overrides.approvalPolicy != null)
          'approvalPolicy': overrides.approvalPolicy,
        if (overrides.sandbox != null) 'sandbox': overrides.sandbox,
        'approvalsReviewer': 'user',
      });
    }

    await _request<void>('turn/start', {
      'threadId': threadId,
      'input': codexInputPartsToJson(input),
    });
    return getThreadRuntime(threadId);
  }

  Future<CodexThreadRuntime> interruptTurn({
    required String threadId,
    String? turnId,
  }) async {
    final runtime = await getThreadRuntime(threadId);
    final effectiveTurnId = _hasValue(turnId) ? turnId! : runtime.activeTurnId;
    if (!_hasValue(effectiveTurnId)) {
      throw const AppServerRpcException('No active turn to interrupt.');
    }

    await _request<void>('turn/interrupt', {
      'threadId': threadId,
      'turnId': effectiveTurnId,
    });
    return getThreadRuntime(threadId);
  }

  Future<CodexThreadRuntime> respondToPendingRequest({
    required String requestId,
    required String action,
    Map<String, dynamic>? answers,
    Object? content,
  }) async {
    await ensureConnected();
    final record = _pendingServerRequests[requestId];
    if (record == null) {
      throw AppServerRpcException('Pending request $requestId was not found.');
    }

    final response = _buildPendingRequestResponse(
      record,
      action: action,
      answers: answers,
      content: content,
    );

    if (response.errorMessage != null) {
      await _sendServerError(record.rawId, response.errorMessage!);
    } else {
      await _sendServerResult(record.rawId, response.result);
    }

    _pendingServerRequests.remove(requestId);
    return getThreadRuntime(record.threadId ?? '');
  }

  Future<Map<String, dynamic>> readThread(String threadId) async {
    await ensureConnected();
    AppServerRpcException? lastError;

    for (var attempt = 0; attempt < 5; attempt += 1) {
      _logAppServerHistory('thread/read.request', {
        'threadId': threadId,
        'attempt': attempt + 1,
      });
      try {
        final response = await _request<Map<String, dynamic>>('thread/read', {
          'threadId': threadId,
          'includeTurns': true,
        });
        final thread = asJsonMap(response['thread']);
        if (thread.isNotEmpty) {
          final turns = asJsonList(thread['turns']).map(asJsonMap).toList();
          var itemCount = 0;
          for (final turn in turns) {
            itemCount += asJsonList(turn['items']).length;
          }
          _logAppServerHistory('thread/read.result', {
            'threadId': threadId,
            'turns': turns.length,
            'items': itemCount,
          });
          return thread;
        }
      } on AppServerRpcException catch (error) {
        lastError = error;
        _logAppServerHistory('thread/read.error', {
          'threadId': threadId,
          'attempt': attempt + 1,
          'message': error.message,
        });
      }

      if (attempt < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
    }

    throw lastError ??
        AppServerRpcException('Failed to read thread $threadId.');
  }

  Future<void> close() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (sharedKey != null && identical(_sharedClients[sharedKey], this)) {
      _sharedClients.remove(sharedKey);
    }
    await _closeSocket();
    if (!_eventsController.isClosed) {
      await _eventsController.close();
    }
  }

  Future<void> _connectAndInitialize() async {
    await _closeSocket();
    final socket = await WebSocket.connect(
      _config.resolveRpcUri().toString(),
      headers: _config.headers,
    );
    socket.pingInterval = const Duration(seconds: 20);
    _socket = socket;
    _socketSubscription = socket.listen(
      _handleSocketMessage,
      onError: _handleSocketError,
      onDone: _handleSocketDone,
      cancelOnError: false,
    );
    _recordAppServerEntry(
      kind: AppServerLogEntryKind.connection,
      direction: AppServerLogDirection.inbound,
      method: 'socket.connected',
      previewText: 'Connected to Codex app-server',
      payload: {'uri': _config.resolveRpcUri().toString()},
    );

    _initialized = false;
    final initializeResponse = await _request<Map<String, dynamic>>(
      'initialize',
      {
        'clientInfo': {'name': 'codex-control-mobile', 'version': '0.1.0'},
        'capabilities': {'experimentalApi': true},
      },
    );
    await _sendNotification('initialized', const <String, dynamic>{});
    _userAgent = readString(initializeResponse, const ['userAgent']);
    _initialized = true;
  }

  Future<T> _request<T>(String method, Map<String, dynamic>? params) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw const AppServerRpcException('Codex app-server is not connected.');
    }

    final id = _requestId++;
    final sentAt = DateTime.now().toUtc();
    final requestContext = _logContextFromPayload(params);
    final completer = Completer<dynamic>();
    final timeout = Timer(const Duration(seconds: 20), () {
      _pendingClientRequests.remove(id);
      _recordAppServerEntry(
        kind: AppServerLogEntryKind.error,
        direction: AppServerLogDirection.inbound,
        rpcId: '$id',
        method: method,
        threadId: requestContext.threadId,
        turnId: requestContext.turnId,
        itemId: requestContext.itemId,
        duration: DateTime.now().toUtc().difference(sentAt),
        previewText: 'Timed out waiting for $method.',
        payload: {
          'message': 'Timed out waiting for $method.',
          'params': params ?? const <String, dynamic>{},
        },
      );
      if (!completer.isCompleted) {
        completer.completeError(
          AppServerRpcException('Timed out waiting for $method.'),
        );
      }
    });

    _pendingClientRequests[id] = _PendingClientRequest(
      rpcId: '$id',
      method: method,
      completer: completer,
      timeout: timeout,
      sentAt: sentAt,
      threadId: requestContext.threadId,
      turnId: requestContext.turnId,
      itemId: requestContext.itemId,
    );
    _recordAppServerEntry(
      kind: AppServerLogEntryKind.request,
      direction: AppServerLogDirection.outbound,
      rpcId: '$id',
      method: method,
      threadId: requestContext.threadId,
      turnId: requestContext.turnId,
      itemId: requestContext.itemId,
      payload: params ?? const <String, dynamic>{},
    );

    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params ?? const <String, dynamic>{},
      }),
    );
    final result = await completer.future;
    return result as T;
  }

  Future<void> _sendServerResult(Object rawId, Object? result) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw const AppServerRpcException('Codex app-server is not connected.');
    }

    final pending = _pendingServerRequests[_requestKey(rawId)];
    final responseContext = _mergeLogContext(
      _logContextFromPayload(result),
      _AppServerLogContext(
        threadId: pending?.threadId,
        turnId: pending?.turnId,
        itemId: pending?.itemId,
      ),
    );
    _recordAppServerEntry(
      kind: AppServerLogEntryKind.response,
      direction: AppServerLogDirection.outbound,
      rpcId: _requestKey(rawId),
      method: pending?.method,
      threadId: responseContext.threadId,
      turnId: responseContext.turnId,
      itemId: responseContext.itemId,
      previewText: 'Resolved server request',
      payload: result,
    );
    socket.add(jsonEncode({'jsonrpc': '2.0', 'id': rawId, 'result': result}));
  }

  Future<void> _sendNotification(
    String method,
    Map<String, dynamic> params,
  ) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw const AppServerRpcException('Codex app-server is not connected.');
    }

    final context = _logContextFromPayload(params);
    _recordAppServerEntry(
      kind: AppServerLogEntryKind.notification,
      direction: AppServerLogDirection.outbound,
      method: method,
      threadId: context.threadId,
      turnId: context.turnId,
      itemId: context.itemId,
      payload: params,
    );
    socket.add(
      jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}),
    );
  }

  Future<void> _sendServerError(
    Object rawId,
    String message, {
    int code = -32000,
  }) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw const AppServerRpcException('Codex app-server is not connected.');
    }

    final pending = _pendingServerRequests[_requestKey(rawId)];
    _recordAppServerEntry(
      kind: AppServerLogEntryKind.error,
      direction: AppServerLogDirection.outbound,
      rpcId: _requestKey(rawId),
      method: pending?.method,
      threadId: pending?.threadId,
      turnId: pending?.turnId,
      itemId: pending?.itemId,
      previewText: message,
      payload: {'code': code, 'message': message},
    );
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': rawId,
        'error': {'code': code, 'message': message},
      }),
    );
  }

  Future<String?> _readConfiguredModelProvider() async {
    try {
      final response = await _request<Map<String, dynamic>>('config/read', {
        'includeLayers': false,
      });
      final config = asJsonMap(response['config']);
      final provider = readString(config, const ['model_provider']).trim();
      return provider.isEmpty ? null : provider;
    } catch (_) {
      return null;
    }
  }

  Future<void> _resumeThread(
    String threadId,
    Map<String, dynamic> extraParams,
  ) async {
    final params = <String, dynamic>{
      'threadId': threadId,
      'persistExtendedHistory': false,
      ...extraParams,
    };
    try {
      await _request<void>('thread/resume', {
        ...params,
        'experimentalRawEvents': true,
      });
    } on AppServerRpcException catch (_) {
      await _request<void>('thread/resume', params);
    }
  }

  Future<void> _closeSocket() async {
    for (final pending in _pendingClientRequests.values) {
      pending.timeout.cancel();
      _recordAppServerEntry(
        kind: AppServerLogEntryKind.error,
        direction: AppServerLogDirection.inbound,
        rpcId: pending.rpcId,
        method: pending.method,
        threadId: pending.threadId,
        turnId: pending.turnId,
        itemId: pending.itemId,
        duration: DateTime.now().toUtc().difference(pending.sentAt),
        previewText: 'Connection closed while waiting for ${pending.method}.',
        payload: {
          'message': 'Connection closed while waiting for ${pending.method}.',
        },
      );
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          AppServerRpcException(
            'Connection closed while waiting for ${pending.method}.',
          ),
        );
      }
    }
    _pendingClientRequests.clear();

    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
  }

  void _handleSocketMessage(dynamic payload) {
    final decoded = _decodeSocketPayload(payload);
    if (decoded.isEmpty) {
      return;
    }

    final rawId = decoded['id'];
    if (rawId is int && decoded.containsKey('result')) {
      final pending = _pendingClientRequests.remove(rawId);
      if (pending == null) {
        return;
      }
      pending.timeout.cancel();
      final responseContext = _mergeLogContext(
        _logContextFromPayload(decoded['result']),
        _AppServerLogContext(
          threadId: pending.threadId,
          turnId: pending.turnId,
          itemId: pending.itemId,
        ),
      );
      _recordAppServerEntry(
        kind: AppServerLogEntryKind.response,
        direction: AppServerLogDirection.inbound,
        rpcId: pending.rpcId,
        method: pending.method,
        threadId: responseContext.threadId,
        turnId: responseContext.turnId,
        itemId: responseContext.itemId,
        duration: DateTime.now().toUtc().difference(pending.sentAt),
        payload: decoded['result'],
      );
      if (!pending.completer.isCompleted) {
        pending.completer.complete(decoded['result']);
      }
      return;
    }

    if (rawId is int && decoded.containsKey('error')) {
      final pending = _pendingClientRequests.remove(rawId);
      if (pending == null) {
        return;
      }
      pending.timeout.cancel();
      final error = asJsonMap(decoded['error']);
      _recordAppServerEntry(
        kind: AppServerLogEntryKind.error,
        direction: AppServerLogDirection.inbound,
        rpcId: pending.rpcId,
        method: pending.method,
        threadId: pending.threadId,
        turnId: pending.turnId,
        itemId: pending.itemId,
        duration: DateTime.now().toUtc().difference(pending.sentAt),
        previewText: readString(error, const [
          'message',
        ], fallback: 'Request failed.'),
        payload: error,
      );
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          AppServerRpcException(
            readString(error, const ['message'], fallback: 'Request failed.'),
            code: readInt(error, const ['code']),
            data: error['data'],
          ),
        );
      }
      return;
    }

    final method = readString(decoded, const ['method']);
    if (method.isEmpty) {
      return;
    }

    final params = asJsonMap(decoded['params']);
    _logAppServerNotification(method, params, rawId: rawId);
    final context = _logContextFromPayload(params);
    _recordAppServerEntry(
      kind: AppServerLogEntryKind.notification,
      direction: AppServerLogDirection.inbound,
      rpcId: rawId == null ? null : _requestKey(rawId),
      method: method,
      threadId: context.threadId,
      turnId: context.turnId,
      itemId: context.itemId,
      payload: params,
    );
    if (rawId != null) {
      final record = _toPendingServerRequestRecord(
        rawId: rawId,
        method: method,
        params: params,
      );
      if (record != null) {
        _pendingServerRequests[record.id] = record;
      }
    }

    Map<String, dynamic>? effectiveParams;
    if (method == 'serverRequest/resolved') {
      final resolvedId = params['requestId'];
      if (resolvedId != null) {
        final resolvedKey = _requestKey(resolvedId);
        final resolvedRecord = _pendingServerRequests[resolvedKey];
        final resolvedThreadId = resolvedRecord?.threadId;
        final resolvedTurnId = resolvedRecord?.turnId;
        final resolvedItemId = resolvedRecord?.itemId;
        effectiveParams = {
          ...params,
          ...?resolvedThreadId == null ? null : {'threadId': resolvedThreadId},
          ...?resolvedTurnId == null ? null : {'turnId': resolvedTurnId},
          ...?resolvedItemId == null ? null : {'itemId': resolvedItemId},
        };
        _pendingServerRequests.remove(resolvedKey);
      }
    }

    final event = _mapNotificationToRealtimeEvent(
      method: method,
      params: effectiveParams ?? params,
      rawId: rawId,
    );
    if (event != null) {
      _eventsController.add(event);
    }
  }

  void _handleSocketDone() {
    _initialized = false;
    final closeCode = _socket?.closeCode;
    final closeReason = _socket?.closeReason;
    final message = [
      'Disconnected from Codex app-server',
      if (closeCode != null) '(code=$closeCode)',
      if (_hasValue(closeReason)) closeReason,
    ].join(' ');
    _recordAppServerEntry(
      kind: AppServerLogEntryKind.connection,
      direction: AppServerLogDirection.inbound,
      method: 'socket.closed',
      previewText: message,
      payload: {'code': closeCode, 'reason': closeReason},
    );
    _eventsController.add(
      BridgeRealtimeEvent(
        type: 'app_server.disconnected',
        description: message,
        receivedAt: DateTime.now().toUtc(),
        raw: {'type': 'app_server.disconnected', 'message': message},
      ),
    );
  }

  void _handleSocketError(Object error) {
    _initialized = false;
    _recordAppServerEntry(
      kind: AppServerLogEntryKind.connection,
      direction: AppServerLogDirection.inbound,
      method: 'socket.error',
      previewText: error.toString(),
      payload: {'message': error.toString()},
    );
    _eventsController.add(
      BridgeRealtimeEvent(
        type: 'app_server.error',
        description: error.toString(),
        receivedAt: DateTime.now().toUtc(),
        raw: {'type': 'app_server.error', 'message': error.toString()},
      ),
    );
  }

  bool get _isConnected {
    return _socket?.readyState == WebSocket.open;
  }

  Map<String, dynamic> _decodeSocketPayload(dynamic payload) {
    if (payload is List<int>) {
      payload = utf8.decode(payload);
    }

    if (payload is String) {
      final decoded = jsonDecode(payload);
      return asJsonMap(decoded);
    }

    return asJsonMap(payload);
  }

  CodexThreadSummary _mapThreadSummary(Map<String, dynamic> thread) {
    final turns = asJsonList(thread['turns']).map(asJsonMap);
    var itemCount = 0;
    for (final turn in turns) {
      itemCount += asJsonList(turn['items']).length;
    }

    return CodexThreadSummary(
      id: readString(thread, const ['id'], fallback: 'unknown-thread'),
      title: _deriveThreadTitle(thread),
      status: _normalizeThreadStatus(asJsonMap(thread['status'])['type']),
      preview: _deriveThreadPreview(thread),
      createdAt: _deriveThreadCreatedAt(thread),
      cwd: _normalizeCwd(readString(thread, const ['cwd'])),
      updatedAt: readDate(thread, const ['updatedAt', 'createdAt']),
      itemCount: itemCount > 0 ? itemCount : null,
      provider: _optionalString(thread['modelProvider']),
    );
  }

  CodexThreadBundle _mapThreadBundle(Map<String, dynamic> thread) {
    final items = <CodexThreadItem>[];
    for (final turn in asJsonList(thread['turns']).map(asJsonMap)) {
      for (final item in asJsonList(turn['items']).map(asJsonMap)) {
        items.add(_mapThreadItem(item, turn, thread));
      }
    }

    return CodexThreadBundle(thread: _mapThreadSummary(thread), items: items);
  }

  CodexThreadRuntime _buildThreadRuntime(
    String threadId,
    Map<String, dynamic> thread,
  ) {
    String? activeTurnId;
    for (final turn in asJsonList(
      thread['turns'],
    ).map(asJsonMap).toList().reversed) {
      if (readString(turn, const ['status']) == 'inProgress') {
        activeTurnId = readString(turn, const ['id']);
        break;
      }
    }

    final itemStatesById = _threadItemsById(thread);
    final stalePendingRequestIds = <String>[];
    final pendingRequests =
        _pendingServerRequests.values
            .where((request) => request.threadId == threadId)
            .where((request) {
              final keep = _shouldKeepPendingServerRequest(
                request,
                activeTurnId: activeTurnId,
                itemStatesById: itemStatesById,
              );
              if (!keep) {
                stalePendingRequestIds.add(request.id);
              }
              return keep;
            })
            .toList()
          ..sort((left, right) => right.receivedAt.compareTo(left.receivedAt));
    for (final requestId in stalePendingRequestIds) {
      _pendingServerRequests.remove(requestId);
    }

    return CodexThreadRuntime(
      threadId: threadId,
      activeTurnId: _hasValue(activeTurnId) ? activeTurnId : null,
      pendingRequests: pendingRequests
          .map(_mapPendingServerRequest)
          .toList(growable: false),
    );
  }

  CodexThreadItem _mapThreadItem(
    Map<String, dynamic> item,
    Map<String, dynamic> turn,
    Map<String, dynamic> thread,
  ) {
    final rawType = readString(item, const ['type'], fallback: 'item');
    final type = _normalizeItemType(rawType);
    final createdAt = extractAppServerItemTimestamp(item, turn);
    final threadCreatedAt =
        readDate(thread, const ['createdAt']) ?? _deriveThreadCreatedAt(thread);
    final raw = <String, dynamic>{
      'turnId': readString(turn, const ['id']),
      'turnStatus': readString(turn, const ['status']),
      if (turn['occurredAt'] != null) 'turnOccurredAt': turn['occurredAt'],
      if (turn['timestamp'] != null) 'turnTimestamp': turn['timestamp'],
      if (turn['createdAt'] != null) 'turnCreatedAt': turn['createdAt'],
      if (turn['updatedAt'] != null) 'turnUpdatedAt': turn['updatedAt'],
      if (threadCreatedAt != null)
        'threadCreatedAt': threadCreatedAt.toUtc().toIso8601String(),
      ...item,
    };

    switch (rawType) {
      case 'userMessage':
        final userBody =
            renderUserMessageContent(item['content']).trim().isNotEmpty
            ? renderUserMessageContent(item['content'])
            : renderUserMessageContent(item);
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title: 'User message',
          body: userBody,
          status: readString(turn, const ['status'], fallback: 'unknown'),
          actor: 'user',
          createdAt: createdAt,
          raw: raw,
        );
      case 'agentMessage':
        final phase = _optionalString(item['phase']);
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title: phase == null
              ? 'Assistant message'
              : 'Assistant message ($phase)',
          body: readString(item, const ['text']),
          status:
              phase ?? readString(turn, const ['status'], fallback: 'unknown'),
          actor: 'assistant',
          createdAt: createdAt,
          raw: raw,
        );
      case 'plan':
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title: 'Plan',
          body: readString(item, const ['text']),
          status: readString(turn, const ['status'], fallback: 'unknown'),
          actor: 'assistant',
          createdAt: createdAt,
          raw: raw,
        );
      case 'reasoning':
        final summary = asJsonList(
          item['summary'],
        ).map((value) => value.toString());
        final content = asJsonList(
          item['content'],
        ).map((value) => value.toString());
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title: 'Reasoning',
          body: [...summary, ...content].join('\n'),
          status: readString(turn, const ['status'], fallback: 'unknown'),
          actor: 'assistant',
          createdAt: createdAt,
          raw: raw,
        );
      case 'commandExecution':
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title: commandExecutionDisplayLabel(item),
          body: readString(item, const ['aggregatedOutput']).trim().isNotEmpty
              ? readString(item, const ['aggregatedOutput'])
              : 'cwd: ${readString(item, const ['cwd'])}\nexitCode: ${item['exitCode'] ?? 'n/a'}',
          status: _approvalAwareItemStatus(item, fallback: 'unknown'),
          actor: 'assistant',
          createdAt: createdAt,
          raw: raw,
        );
      case 'fileChange':
        final changes = asJsonList(item['changes']).map(asJsonMap).toList();
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title:
              '${changes.length} file change${changes.length == 1 ? '' : 's'}',
          body: changes
              .take(8)
              .map(
                (change) =>
                    '${readString(change, const ['kind'])} ${readString(change, const ['path'])}',
              )
              .join('\n'),
          status: _approvalAwareItemStatus(item, fallback: 'unknown'),
          actor: 'assistant',
          createdAt: createdAt,
          raw: raw,
        );
      case 'mcpToolCall':
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title:
              '${readString(item, const ['server'], fallback: 'mcp')}/${readString(item, const ['tool'], fallback: 'tool')}',
          body: _describeJson(
            item['error'] ?? item['result'] ?? item['arguments'],
          ),
          status: readString(item, const ['status'], fallback: 'unknown'),
          actor: 'mcp',
          createdAt: createdAt,
          raw: raw,
        );
      case 'dynamicToolCall':
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title: readString(item, const ['tool'], fallback: 'Tool'),
          body: _describeJson(item['contentItems'] ?? item['arguments']),
          status: readString(item, const ['status'], fallback: 'unknown'),
          actor: 'tool',
          createdAt: createdAt,
          raw: raw,
        );
      case 'collabAgentToolCall':
        final receiverIds = asJsonList(
          item['receiverThreadIds'],
        ).map((value) => value.toString()).toList(growable: false);
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title: readString(item, const ['tool'], fallback: 'Agent tool'),
          body: readString(item, const ['prompt']).trim().isNotEmpty
              ? readString(item, const ['prompt'])
              : 'receiverThreadIds: ${receiverIds.join(', ')}',
          status: readString(item, const ['status'], fallback: 'unknown'),
          actor: 'agent',
          createdAt: createdAt,
          raw: raw,
        );
      case 'webSearch':
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title: readString(item, const ['query'], fallback: 'Web search'),
          body: _describeWebSearch(item),
          status: readString(turn, const ['status'], fallback: 'unknown'),
          actor: 'assistant',
          createdAt: createdAt,
          raw: raw,
        );
      case 'imageView':
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title: 'Image view',
          body: readString(item, const ['path']),
          status: readString(turn, const ['status'], fallback: 'unknown'),
          actor: 'assistant',
          createdAt: createdAt,
          raw: raw,
        );
      case 'imageGeneration':
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title: 'Image generation',
          body:
              _optionalString(item['savedPath']) ??
              _optionalString(item['result']) ??
              _optionalString(item['revisedPrompt']) ??
              '',
          status: readString(item, const ['status'], fallback: 'unknown'),
          actor: 'assistant',
          createdAt: createdAt,
          raw: raw,
        );
      case 'enteredReviewMode':
      case 'exitedReviewMode':
      case 'contextCompaction':
        return CodexThreadItem(
          id: readString(item, const ['id']),
          type: type,
          title: _humanizeType(rawType),
          body: readString(item, const ['review']),
          status: readString(item, const [
            'status',
          ], fallback: readString(turn, const ['status'], fallback: 'unknown')),
          actor: 'assistant',
          createdAt: createdAt,
          raw: raw,
        );
      default:
        return CodexThreadItem(
          id: readString(item, const [
            'id',
          ], fallback: DateTime.now().microsecondsSinceEpoch.toString()),
          type: type,
          title: _humanizeType(rawType),
          body: _describeJson(item),
          status: readString(turn, const ['status'], fallback: 'unknown'),
          actor: 'assistant',
          createdAt: createdAt,
          raw: raw,
        );
    }
  }

  CodexPendingRequest _mapPendingServerRequest(
    _PendingServerRequestRecord request,
  ) {
    final params = request.params;
    switch (request.method) {
      case 'item/commandExecution/requestApproval':
        return CodexPendingRequest(
          id: request.id,
          kind: 'command_approval',
          title: 'Command Approval',
          message:
              _optionalString(params['reason']) ??
              'Allow Codex to run ${_optionalString(params['command']) ?? 'the requested command'}?',
          actions: _commandApprovalActions(params['availableDecisions']),
          questions: const [],
          formFields: const [],
          receivedAt: request.receivedAt,
          threadId: request.threadId,
          turnId: request.turnId,
          itemId: request.itemId,
          detail: _optionalString(params['command']),
          command: _optionalString(params['command']),
          cwd: _optionalString(params['cwd']),
          raw: params,
        );
      case 'item/fileChange/requestApproval':
        return CodexPendingRequest(
          id: request.id,
          kind: 'file_change_approval',
          title: 'File Change Approval',
          message:
              _optionalString(params['reason']) ??
              'Codex wants permission to write the requested file changes.',
          actions: const [
            CodexPendingAction(
              id: 'approve',
              label: 'Approve',
              recommended: true,
              destructive: false,
            ),
            CodexPendingAction(
              id: 'approve_for_session',
              label: 'Always Allow',
              recommended: false,
              destructive: false,
            ),
            CodexPendingAction(
              id: 'deny',
              label: 'Deny',
              recommended: false,
              destructive: true,
            ),
            CodexPendingAction(
              id: 'cancel',
              label: 'Stop Turn',
              recommended: false,
              destructive: true,
            ),
          ],
          questions: const [],
          formFields: const [],
          receivedAt: request.receivedAt,
          threadId: request.threadId,
          turnId: request.turnId,
          itemId: request.itemId,
          detail: _optionalString(params['grantRoot']),
          raw: params,
        );
      case 'item/permissions/requestApproval':
        return CodexPendingRequest(
          id: request.id,
          kind: 'permissions_approval',
          title: 'Permission Request',
          message:
              _optionalString(params['reason']) ??
              'Codex requested additional permissions for this turn.',
          actions: const [
            CodexPendingAction(
              id: 'grant_turn',
              label: 'Grant Once',
              recommended: true,
              destructive: false,
            ),
            CodexPendingAction(
              id: 'grant_session',
              label: 'Grant For Session',
              recommended: false,
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
          receivedAt: request.receivedAt,
          threadId: request.threadId,
          turnId: request.turnId,
          itemId: request.itemId,
          permissions: asJsonMap(params['permissions']),
          raw: params,
        );
      case 'item/tool/requestUserInput':
        final questions = asJsonList(params['questions'])
            .map(asJsonMap)
            .map(_mapUserInputQuestion)
            .whereType<CodexPendingQuestion>()
            .toList(growable: false);
        return CodexPendingRequest(
          id: request.id,
          kind: 'user_input',
          title: 'User Input Required',
          message: questions.isNotEmpty
              ? 'Codex needs answers before the turn can continue.'
              : 'Codex requested additional user input.',
          actions: const [
            CodexPendingAction(
              id: 'submit',
              label: 'Submit',
              recommended: true,
              destructive: false,
            ),
            CodexPendingAction(
              id: 'cancel',
              label: 'Cancel',
              recommended: false,
              destructive: true,
            ),
          ],
          questions: questions,
          formFields: const [],
          receivedAt: request.receivedAt,
          threadId: request.threadId,
          turnId: request.turnId,
          itemId: request.itemId,
          raw: params,
        );
      case 'mcpServer/elicitation/request':
        final formFields = _buildMcpFormFields(params);
        return CodexPendingRequest(
          id: request.id,
          kind: 'mcp_elicitation',
          title: 'MCP Input Request',
          message:
              _optionalString(params['message']) ??
              'An MCP server requested additional input.',
          actions: [
            CodexPendingAction(
              id: 'accept',
              label: formFields.isEmpty ? 'Done' : 'Submit',
              recommended: true,
              destructive: false,
            ),
            const CodexPendingAction(
              id: 'decline',
              label: 'Decline',
              recommended: false,
              destructive: true,
            ),
            const CodexPendingAction(
              id: 'cancel',
              label: 'Cancel',
              recommended: false,
              destructive: true,
            ),
          ],
          questions: const [],
          formFields: formFields,
          receivedAt: request.receivedAt,
          threadId: request.threadId,
          turnId: request.turnId,
          itemId: request.itemId,
          url: _optionalString(params['url']),
          raw: params,
        );
      case 'execCommandApproval':
        return CodexPendingRequest(
          id: request.id,
          kind: 'legacy_command_approval',
          title: 'Command Approval',
          message:
              _optionalString(params['message']) ??
              'Command approval requested.',
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
            CodexPendingAction(
              id: 'cancel',
              label: 'Abort',
              recommended: false,
              destructive: true,
            ),
          ],
          questions: const [],
          formFields: const [],
          receivedAt: request.receivedAt,
          threadId: request.threadId,
          turnId: request.turnId,
          itemId: request.itemId,
          detail: _joinCommand(params['command']),
          raw: params,
        );
      case 'applyPatchApproval':
        return CodexPendingRequest(
          id: request.id,
          kind: 'legacy_patch_approval',
          title: 'Patch Approval',
          message:
              _optionalString(params['message']) ?? 'Patch approval requested.',
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
            CodexPendingAction(
              id: 'cancel',
              label: 'Abort',
              recommended: false,
              destructive: true,
            ),
          ],
          questions: const [],
          formFields: const [],
          receivedAt: request.receivedAt,
          threadId: request.threadId,
          turnId: request.turnId,
          itemId: request.itemId,
          raw: params,
        );
      default:
        return CodexPendingRequest(
          id: request.id,
          kind: 'request',
          title: 'Pending request',
          message: 'Codex requested additional input.',
          actions: const [],
          questions: const [],
          formFields: const [],
          receivedAt: request.receivedAt,
          threadId: request.threadId,
          turnId: request.turnId,
          itemId: request.itemId,
          raw: params,
        );
    }
  }

  _PendingServerRequestRecord? _toPendingServerRequestRecord({
    required Object rawId,
    required String method,
    required Map<String, dynamic> params,
  }) {
    if (!_supportedServerRequests.contains(method)) {
      return null;
    }

    final item = asJsonMap(params['item']);
    final turn = asJsonMap(params['turn']);
    return _PendingServerRequestRecord(
      id: _requestKey(rawId),
      rawId: rawId,
      method: method,
      params: params,
      receivedAt: DateTime.now().toUtc(),
      threadId: _optionalString(
        params['threadId'] ??
            params['conversationId'] ??
            turn['threadId'] ??
            item['threadId'],
      ),
      turnId: _optionalString(params['turnId'] ?? turn['id'] ?? item['turnId']),
      itemId: _optionalString(params['itemId'] ?? item['id']),
    );
  }

  BridgeRealtimeEvent? _mapNotificationToRealtimeEvent({
    required String method,
    required Map<String, dynamic> params,
    required Object? rawId,
  }) {
    final occurredAt = _extractNotificationOccurredAt(method, params);
    final thread = asJsonMap(params['thread']);
    final turn = asJsonMap(params['turn']);
    final item = asJsonMap(params['item']);
    final threadId = _optionalString(
      params['threadId'] ??
          params['conversationId'] ??
          thread['id'] ??
          turn['threadId'] ??
          item['threadId'],
    );
    final raw = <String, dynamic>{
      'method': method,
      'params': params,
      ...?threadId == null ? null : {'threadId': threadId},
      ...?occurredAt == null
          ? null
          : {'occurredAt': occurredAt.toIso8601String()},
      ...?rawId == null ? null : {'requestId': rawId.toString()},
    };

    switch (method) {
      case 'thread/started':
        final thread = asJsonMap(params['thread']);
        return BridgeRealtimeEvent(
          type: 'thread.started',
          description: 'Thread started: ${_deriveThreadTitle(thread)}',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'thread/status/changed':
        final status = asJsonMap(params['status']);
        return BridgeRealtimeEvent(
          type: 'thread.status',
          description:
              'Thread status changed to ${readString(status, const ['type'], fallback: 'unknown')}',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'turn/started':
      case 'turn/completed':
        final turn = asJsonMap(params['turn']);
        return BridgeRealtimeEvent(
          type: method.replaceAll('/', '.'),
          description:
              'Turn ${method.endsWith('started') ? 'started' : 'completed'} (${readString(turn, const ['status'], fallback: 'unknown')})',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'turn/diff/updated':
        return BridgeRealtimeEvent(
          type: 'turn.diff.updated',
          description: 'Turn diff updated',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'turn/plan/updated':
        return BridgeRealtimeEvent(
          type: 'turn.plan.updated',
          description: 'Turn plan updated',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'item/started':
      case 'item/completed':
        final item = _mapThreadItem(asJsonMap(params['item']), {
          'id': readString(params, const ['turnId']),
          'status': 'completed',
        }, asJsonMap(params['thread']));
        return BridgeRealtimeEvent(
          type:
              '${item.type}.${method.endsWith('started') ? 'started' : 'completed'}',
          description: item.title,
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'item/agentMessage/delta':
      case 'item/plan/delta':
      case 'item/commandExecution/outputDelta':
      case 'item/fileChange/outputDelta':
      case 'item/reasoning/summaryTextDelta':
      case 'item/reasoning/textDelta':
        return BridgeRealtimeEvent(
          type: _mapStreamingEventType(method),
          description:
              _optionalString(params['delta']) ??
              _defaultStreamingMessage(method),
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'thread/realtime/started':
        return BridgeRealtimeEvent(
          type: 'thread.realtime.started',
          description: 'Thread realtime started',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'thread/realtime/itemAdded':
        final item = _mapThreadItem(asJsonMap(params['item']), {
          'id': readString(params, const ['turnId']),
          'status': 'started',
        }, asJsonMap(params['thread']));
        return BridgeRealtimeEvent(
          type: 'thread.realtime.item.added',
          description: item.title,
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'thread/realtime/transcriptUpdated':
        return BridgeRealtimeEvent(
          type: 'thread.realtime.transcript.updated',
          description:
              _optionalString(params['transcript']) ??
              _optionalString(params['text']) ??
              _optionalString(params['delta']) ??
              'Realtime transcript updated',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'thread/realtime/outputAudio/delta':
        return BridgeRealtimeEvent(
          type: 'thread.realtime.output_audio.delta',
          description: 'Realtime audio delta',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'thread/realtime/error':
        return BridgeRealtimeEvent(
          type: 'thread.realtime.error',
          description:
              _optionalString(params['message']) ??
              _optionalString(params['error']) ??
              'Realtime stream error',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'thread/realtime/closed':
        return BridgeRealtimeEvent(
          type: 'thread.realtime.closed',
          description: 'Realtime stream closed',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'item/commandExecution/requestApproval':
      case 'item/fileChange/requestApproval':
      case 'item/permissions/requestApproval':
      case 'execCommandApproval':
      case 'applyPatchApproval':
        return BridgeRealtimeEvent(
          type: 'approval.request',
          description: 'Approval requested via $method',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'item/tool/requestUserInput':
        return BridgeRealtimeEvent(
          type: 'user.input.request',
          description: 'User input requested by Codex',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'mcpServer/elicitation/request':
        return BridgeRealtimeEvent(
          type: 'mcp.elicitation.request',
          description: _optionalString(params['serverName']) == null
              ? 'MCP input requested'
              : 'MCP input requested by ${_optionalString(params['serverName'])}',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: raw,
        );
      case 'serverRequest/resolved':
        final requestId = _optionalString(params['requestId']);
        return BridgeRealtimeEvent(
          type: 'server.request.resolved',
          description: requestId == null
              ? 'Pending request resolved'
              : 'Pending request $requestId resolved',
          receivedAt: occurredAt ?? DateTime.now().toUtc(),
          raw: {
            ...raw,
            ...?requestId == null ? null : {'requestId': requestId},
          },
        );
      default:
        return null;
    }
  }
}

class AppServerRpcException implements Exception {
  const AppServerRpcException(this.message, {this.code, this.data});

  final String message;
  final int? code;
  final Object? data;

  @override
  String toString() => message;
}

class _PendingClientRequest {
  const _PendingClientRequest({
    required this.rpcId,
    required this.method,
    required this.completer,
    required this.timeout,
    required this.sentAt,
    this.threadId,
    this.turnId,
    this.itemId,
  });

  final String rpcId;
  final String method;
  final Completer<dynamic> completer;
  final Timer timeout;
  final DateTime sentAt;
  final String? threadId;
  final String? turnId;
  final String? itemId;
}

class _AppServerLogContext {
  const _AppServerLogContext({this.threadId, this.turnId, this.itemId});

  final String? threadId;
  final String? turnId;
  final String? itemId;
}

class _PendingServerRequestRecord {
  const _PendingServerRequestRecord({
    required this.id,
    required this.rawId,
    required this.method,
    required this.params,
    required this.receivedAt,
    this.threadId,
    this.turnId,
    this.itemId,
  });

  final String id;
  final Object rawId;
  final String method;
  final Map<String, dynamic> params;
  final DateTime receivedAt;
  final String? threadId;
  final String? turnId;
  final String? itemId;
}

class _PendingRequestResponse {
  const _PendingRequestResponse({this.result, this.errorMessage});

  final Object? result;
  final String? errorMessage;
}

class _ThreadOverrides {
  const _ThreadOverrides({this.approvalPolicy, this.sandbox});

  final String? approvalPolicy;
  final String? sandbox;
}

const Set<String> _supportedServerRequests = {
  'item/commandExecution/requestApproval',
  'item/fileChange/requestApproval',
  'item/permissions/requestApproval',
  'item/tool/requestUserInput',
  'mcpServer/elicitation/request',
  'execCommandApproval',
  'applyPatchApproval',
};

_ThreadOverrides _modeToThreadOverrides(CodexComposerMode mode) {
  switch (mode) {
    case CodexComposerMode.chat:
      return const _ThreadOverrides(
        approvalPolicy: 'untrusted',
        sandbox: 'read-only',
      );
    case CodexComposerMode.agent:
      return const _ThreadOverrides(
        approvalPolicy: 'on-request',
        sandbox: 'workspace-write',
      );
    case CodexComposerMode.agentFullAccess:
      return const _ThreadOverrides(
        approvalPolicy: 'never',
        sandbox: 'danger-full-access',
      );
  }
}

_PendingRequestResponse _buildPendingRequestResponse(
  _PendingServerRequestRecord request, {
  required String action,
  Map<String, dynamic>? answers,
  Object? content,
}) {
  switch (request.method) {
    case 'item/commandExecution/requestApproval':
      final decision = _mapCommandApprovalAction(action);
      return decision == null
          ? const _PendingRequestResponse(
              errorMessage: 'Command approval was declined.',
            )
          : _PendingRequestResponse(result: {'decision': decision});
    case 'item/fileChange/requestApproval':
      final decision = _mapFileApprovalAction(action);
      return decision == null
          ? const _PendingRequestResponse(
              errorMessage: 'File change approval was declined.',
            )
          : _PendingRequestResponse(result: {'decision': decision});
    case 'item/permissions/requestApproval':
      final permissions = asJsonMap(request.params['permissions']);
      switch (action) {
        case 'grant_turn':
          return _PendingRequestResponse(
            result: {'permissions': permissions, 'scope': 'turn'},
          );
        case 'grant_session':
          return _PendingRequestResponse(
            result: {'permissions': permissions, 'scope': 'session'},
          );
        case 'deny':
        case 'cancel':
          return const _PendingRequestResponse(
            errorMessage: 'Permission request was denied.',
          );
        default:
          throw AppServerRpcException('Unsupported permission action: $action');
      }
    case 'item/tool/requestUserInput':
      if (action == 'cancel' || action == 'decline') {
        return const _PendingRequestResponse(
          errorMessage: 'User input request was cancelled.',
        );
      }
      if (action != 'submit') {
        throw AppServerRpcException('Unsupported user input action: $action');
      }
      return _PendingRequestResponse(
        result: {'answers': _normalizeUserInputAnswers(answers)},
      );
    case 'mcpServer/elicitation/request':
      switch (action) {
        case 'accept':
          return _PendingRequestResponse(
            result: {'action': 'accept', 'content': content, '_meta': null},
          );
        case 'decline':
          return const _PendingRequestResponse(
            result: {'action': 'decline', 'content': null, '_meta': null},
          );
        case 'cancel':
          return const _PendingRequestResponse(
            result: {'action': 'cancel', 'content': null, '_meta': null},
          );
        default:
          throw AppServerRpcException('Unsupported MCP action: $action');
      }
    case 'execCommandApproval':
      final decision = _mapLegacyApprovalAction(action);
      return decision == null
          ? const _PendingRequestResponse(
              errorMessage: 'Command approval was denied.',
            )
          : _PendingRequestResponse(result: {'decision': decision});
    case 'applyPatchApproval':
      final decision = _mapLegacyApprovalAction(action);
      return decision == null
          ? const _PendingRequestResponse(
              errorMessage: 'Patch approval was denied.',
            )
          : _PendingRequestResponse(result: {'decision': decision});
    default:
      throw AppServerRpcException(
        'Unsupported pending request: ${request.method}',
      );
  }
}

List<CodexPendingAction> _commandApprovalActions(Object? value) {
  final available = asJsonList(value).map((entry) => entry.toString()).toSet();
  final actions = <(String, CodexPendingAction)>[
    (
      'accept',
      const CodexPendingAction(
        id: 'approve',
        label: 'Approve',
        recommended: true,
        destructive: false,
      ),
    ),
    (
      'acceptForSession',
      const CodexPendingAction(
        id: 'approve_for_session',
        label: 'Always Allow',
        recommended: false,
        destructive: false,
      ),
    ),
    (
      'decline',
      const CodexPendingAction(
        id: 'deny',
        label: 'Deny',
        recommended: false,
        destructive: true,
      ),
    ),
    (
      'cancel',
      const CodexPendingAction(
        id: 'cancel',
        label: 'Stop Turn',
        recommended: false,
        destructive: true,
      ),
    ),
  ];

  final filtered = actions
      .where((entry) => available.isEmpty || available.contains(entry.$1))
      .map((entry) => entry.$2)
      .toList(growable: false);
  return filtered.isNotEmpty
      ? filtered
      : const [
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
        ];
}

CodexPendingQuestion? _mapUserInputQuestion(Map<String, dynamic> question) {
  final id = _optionalString(question['id']);
  if (id == null) {
    return null;
  }

  final options = asJsonList(question['options'])
      .map(asJsonMap)
      .mapIndexed((index, option) {
        final label = _optionalString(option['label']);
        if (label == null) {
          return null;
        }

        return CodexPendingOption(
          id: label,
          label: label,
          description: _optionalString(option['description']),
          recommended: index == 0,
        );
      })
      .whereType<CodexPendingOption>()
      .toList(growable: false);

  return CodexPendingQuestion(
    id: id,
    label: _optionalString(question['header']) ?? id,
    prompt: _optionalString(question['question']) ?? id,
    allowFreeform: question['isOther'] == true,
    multiSelect: false,
    options: options,
  );
}

List<CodexPendingFormField> _buildMcpFormFields(Map<String, dynamic> params) {
  if (_optionalString(params['mode']) != 'form') {
    return const [];
  }

  final schema = asJsonMap(params['requestedSchema']);
  final properties = asJsonMap(schema['properties']);
  final requiredFields = asJsonList(
    schema['required'],
  ).map((value) => value.toString()).toSet();

  final fields = <CodexPendingFormField>[];
  for (final entry in properties.entries) {
    final field = _mapMcpField(
      entry.key,
      asJsonMap(entry.value),
      requiredFields.contains(entry.key),
    );
    if (field != null) {
      fields.add(field);
    }
  }
  return fields;
}

CodexPendingFormField? _mapMcpField(
  String fieldId,
  Map<String, dynamic> definition,
  bool required,
) {
  final fieldType = _inferMcpFieldType(definition);
  if (fieldType == null) {
    return null;
  }

  return CodexPendingFormField(
    id: fieldId,
    label: _optionalString(definition['title']) ?? fieldId,
    description: _optionalString(definition['description']),
    type: fieldType,
    required: required,
    options: _optionsForField(definition, fieldType),
    defaultValue: _defaultValueForField(definition),
  );
}

CodexPendingFieldType? _inferMcpFieldType(Map<String, dynamic> definition) {
  final type = _optionalString(definition['type']);
  if (definition['enum'] is List || definition['oneOf'] is List) {
    return CodexPendingFieldType.singleSelect;
  }
  if (type == 'array') {
    return CodexPendingFieldType.multiSelect;
  }
  if (type == 'boolean') {
    return CodexPendingFieldType.boolean;
  }
  if (type == 'number' || type == 'integer') {
    return CodexPendingFieldType.number;
  }
  if (type == 'string') {
    return CodexPendingFieldType.text;
  }
  return null;
}

List<CodexPendingOption> _optionsForField(
  Map<String, dynamic> definition,
  CodexPendingFieldType fieldType,
) {
  if (fieldType == CodexPendingFieldType.singleSelect) {
    final oneOf = asJsonList(definition['oneOf']).map(asJsonMap).toList();
    if (oneOf.isNotEmpty) {
      return oneOf
          .mapIndexed((index, option) {
            final id = _optionalString(option['const']);
            if (id == null) {
              return null;
            }
            return CodexPendingOption(
              id: id,
              label: _optionalString(option['title']) ?? id,
              recommended: index == 0,
            );
          })
          .whereType<CodexPendingOption>()
          .toList(growable: false);
    }

    final values = asJsonList(definition['enum']);
    final names = asJsonList(definition['enumNames']);
    return values
        .mapIndexed(
          (index, value) => CodexPendingOption(
            id: value.toString(),
            label: index < names.length
                ? names[index].toString()
                : value.toString(),
            recommended: index == 0,
          ),
        )
        .toList(growable: false);
  }

  if (fieldType == CodexPendingFieldType.multiSelect) {
    final items = asJsonMap(definition['items']);
    final oneOf = asJsonList(items['oneOf']).map(asJsonMap).toList();
    if (oneOf.isNotEmpty) {
      return oneOf
          .mapIndexed((index, option) {
            final id = _optionalString(option['const']);
            if (id == null) {
              return null;
            }
            return CodexPendingOption(
              id: id,
              label: _optionalString(option['title']) ?? id,
              recommended: index == 0,
            );
          })
          .whereType<CodexPendingOption>()
          .toList(growable: false);
    }

    final values = asJsonList(items['enum']);
    final names = asJsonList(items['enumNames']);
    return values
        .mapIndexed(
          (index, value) => CodexPendingOption(
            id: value.toString(),
            label: index < names.length
                ? names[index].toString()
                : value.toString(),
            recommended: index == 0,
          ),
        )
        .toList(growable: false);
  }

  return const [];
}

Object? _defaultValueForField(Map<String, dynamic> definition) {
  final value = definition['default'];
  if (value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return value.map((item) => item.toString()).toList(growable: false);
  }
  return null;
}

Map<String, dynamic> _normalizeUserInputAnswers(Map<String, dynamic>? answers) {
  final value = answers ?? const <String, dynamic>{};
  final normalized = <String, dynamic>{};
  for (final entry in value.entries) {
    final items = entry.value is List
        ? (entry.value as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : [
            entry.value.toString().trim(),
          ].where((item) => item.isNotEmpty).toList(growable: false);
    if (items.isNotEmpty) {
      normalized[entry.key] = {'answers': items};
    }
  }

  if (normalized.isEmpty) {
    throw const AppServerRpcException(
      'User input responses must include at least one answer.',
    );
  }
  return normalized;
}

String? _mapCommandApprovalAction(String actionId) {
  switch (actionId) {
    case 'approve':
      return 'accept';
    case 'approve_for_session':
      return 'acceptForSession';
    case 'deny':
      return 'decline';
    case 'cancel':
      return 'cancel';
    default:
      throw AppServerRpcException(
        'Unsupported command approval action: $actionId',
      );
  }
}

String? _mapFileApprovalAction(String actionId) {
  switch (actionId) {
    case 'approve':
      return 'accept';
    case 'approve_for_session':
      return 'acceptForSession';
    case 'deny':
      return 'decline';
    case 'cancel':
      return 'cancel';
    default:
      throw AppServerRpcException(
        'Unsupported file approval action: $actionId',
      );
  }
}

String? _mapLegacyApprovalAction(String actionId) {
  switch (actionId) {
    case 'approve':
      return 'approved';
    case 'approve_for_session':
      return 'approved_for_session';
    case 'deny':
      return 'denied';
    case 'abort':
    case 'cancel':
      return 'abort';
    default:
      throw AppServerRpcException('Unsupported approval action: $actionId');
  }
}

String _deriveThreadTitle(Map<String, dynamic> thread) {
  final explicitName = _sanitizeTitleCandidate(_optionalString(thread['name']));
  if (explicitName != null) {
    return explicitName;
  }

  final preview = _sanitizeTitleCandidate(_optionalString(thread['preview']));
  if (preview == null) {
    return 'Untitled session';
  }

  return preview.length > 48 ? '${preview.substring(0, 45)}...' : preview;
}

String _deriveThreadPreview(Map<String, dynamic> thread) {
  final lastUserPrompt =
      _lastUserPromptFromThread(thread) ?? _lastUserPromptFromSummary(thread);
  if (lastUserPrompt != null) {
    return lastUserPrompt;
  }

  final preview = _sanitizePreviewCandidate(_optionalString(thread['preview']));
  if (preview != null) {
    return preview;
  }

  return 'No preview available yet.';
}

String? _lastUserPromptFromSummary(Map<String, dynamic> thread) {
  for (final candidate in <Object?>[
    thread['lastUserPrompt'],
    thread['lastUserMessage'],
    thread['latestUserPrompt'],
    thread['latestUserMessage'],
    thread['prompt'],
    thread['question'],
    thread['input'],
    asJsonMap(thread['latestTurn'])['lastUserPrompt'],
    asJsonMap(thread['latestTurn'])['lastUserMessage'],
    asJsonMap(thread['latestTurn'])['prompt'],
    asJsonMap(thread['latestTurn'])['question'],
    asJsonMap(thread['lastTurn'])['lastUserPrompt'],
    asJsonMap(thread['lastTurn'])['lastUserMessage'],
    asJsonMap(thread['lastTurn'])['prompt'],
    asJsonMap(thread['lastTurn'])['question'],
  ]) {
    final prompt = _sanitizePreviewCandidate(candidate?.toString());
    if (prompt != null) {
      return prompt;
    }
  }
  return null;
}

DateTime? _deriveThreadCreatedAt(Map<String, dynamic> thread) {
  final direct = readDate(thread, const ['createdAt']);
  if (direct != null) {
    return direct;
  }

  DateTime? earliest;
  for (final turn in asJsonList(thread['turns']).map(asJsonMap)) {
    final turnCreatedAt = readDate(turn, const [
      'createdAt',
      'occurredAt',
      'timestamp',
    ]);
    if (turnCreatedAt != null &&
        (earliest == null || turnCreatedAt.isBefore(earliest))) {
      earliest = turnCreatedAt;
    }

    for (final item in asJsonList(turn['items']).map(asJsonMap)) {
      final itemCreatedAt = extractAppServerItemTimestamp(item, turn);
      if (itemCreatedAt != null &&
          (earliest == null || itemCreatedAt.isBefore(earliest))) {
        earliest = itemCreatedAt;
      }
    }
  }

  return earliest;
}

String? _lastUserPromptFromThread(Map<String, dynamic> thread) {
  final turns = asJsonList(
    thread['turns'],
  ).map(asJsonMap).toList(growable: false);
  for (final turn in turns.reversed) {
    final items = asJsonList(
      turn['items'],
    ).map(asJsonMap).toList(growable: false);
    for (final item in items.reversed) {
      if (!_isUserPromptItem(item)) {
        continue;
      }
      final prompt = _sanitizePreviewCandidate(_readUserPromptText(item));
      if (prompt != null) {
        return prompt;
      }
    }
  }
  return null;
}

bool _isUserPromptItem(Map<String, dynamic> item) {
  final type = readString(item, const ['type']).trim();
  if (type == 'userMessage' || type == 'user.message') {
    return true;
  }

  final role = _optionalString(item['role'] ?? item['actor'] ?? item['source']);
  return role == 'user';
}

String _readUserPromptText(Map<String, dynamic> item) {
  final content = renderUserMessageContent(item['content']);
  if (content.trim().isNotEmpty) {
    return content;
  }
  return renderUserMessageContent(item);
}

String? _sanitizeTitleCandidate(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final firstLine = trimmed
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  if (firstLine.isEmpty) {
    return null;
  }

  final normalized = firstLine
      .replaceFirst(RegExp(r'\}\]\}.*$'), '')
      .replaceFirst(RegExp(r'\s+to=functions\.[\w.]+.*$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return normalized.isEmpty ? null : normalized;
}

String? _sanitizePreviewCandidate(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final firstLine = trimmed
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  if (firstLine.isEmpty) {
    return null;
  }

  final normalized = firstLine.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized.length <= 140) {
    return normalized;
  }
  return '${normalized.substring(0, 137)}...';
}

String _describeWebSearch(Map<String, dynamic> item) {
  final action = asJsonMap(item['action']);
  if (action.isEmpty) {
    return readString(item, const ['query']);
  }

  switch (readString(action, const ['type'])) {
    case 'search':
      return readString(action, const [
        'query',
      ], fallback: readString(item, const ['query']));
    case 'openPage':
      return readString(action, const [
        'url',
      ], fallback: readString(item, const ['query']));
    default:
      return readString(item, const ['query']);
  }
}

String _describeJson(Object? value) {
  if (value == null) {
    return '';
  }

  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}

String _humanizeType(String type) {
  return type
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'[_.-]'), ' ')
      .replaceFirstMapped(
        RegExp(r'^\w'),
        (match) => match.group(0)!.toUpperCase(),
      );
}

String _normalizeThreadStatus(Object? statusType) {
  switch (statusType) {
    case 'active':
      return 'active';
    case 'idle':
      return 'idle';
    case 'systemError':
      return 'error';
    case 'notLoaded':
      return 'idle';
    default:
      final value = statusType?.toString().trim();
      return value == null || value.isEmpty ? 'unknown' : value;
  }
}

String _normalizeItemType(String type) {
  switch (type) {
    case 'userMessage':
      return 'user.message';
    case 'hookPrompt':
      return 'hook.prompt';
    case 'agentMessage':
      return 'agent.message';
    case 'plan':
      return 'plan';
    case 'reasoning':
      return 'reasoning';
    case 'commandExecution':
      return 'command.execution';
    case 'fileChange':
      return 'file.change';
    case 'mcpToolCall':
      return 'mcp.tool.call';
    case 'dynamicToolCall':
      return 'tool.call';
    case 'collabAgentToolCall':
      return 'agent.tool.call';
    case 'webSearch':
      return 'web.search';
    case 'imageView':
      return 'image.view';
    case 'imageGeneration':
      return 'image.generation';
    case 'enteredReviewMode':
      return 'review.entered';
    case 'exitedReviewMode':
      return 'review.exited';
    case 'contextCompaction':
      return 'context.compaction';
    default:
      return type;
  }
}

String _mapStreamingEventType(String method) {
  switch (method) {
    case 'item/agentMessage/delta':
      return 'agent.message.delta';
    case 'item/plan/delta':
      return 'plan.delta';
    case 'item/commandExecution/outputDelta':
      return 'command.execution.delta';
    case 'item/fileChange/outputDelta':
      return 'file.change.delta';
    case 'item/reasoning/summaryTextDelta':
      return 'reasoning.summary.delta';
    case 'item/reasoning/textDelta':
      return 'reasoning.delta';
    default:
      return method.replaceAll('/', '.');
  }
}

String _defaultStreamingMessage(String method) {
  switch (method) {
    case 'item/agentMessage/delta':
      return 'Assistant response streaming';
    case 'item/plan/delta':
      return 'Plan updated';
    case 'item/commandExecution/outputDelta':
      return 'Command output streaming';
    case 'item/fileChange/outputDelta':
      return 'File change streaming';
    case 'item/reasoning/summaryTextDelta':
      return 'Reasoning summary streaming';
    case 'item/reasoning/textDelta':
      return 'Reasoning streaming';
    default:
      return 'Streaming update';
  }
}

DateTime? _extractNotificationOccurredAt(
  String method,
  Map<String, dynamic> params,
) {
  final thread = asJsonMap(params['thread']);
  final turn = asJsonMap(params['turn']);
  final item = asJsonMap(params['item']);
  final candidates = method == 'thread/started'
      ? [
          thread['createdAt'],
          thread['updatedAt'],
          params['occurredAt'],
          params['timestamp'],
          params['createdAt'],
          params['updatedAt'],
          item['occurredAt'],
          item['timestamp'],
          item['createdAt'],
          item['updatedAt'],
          turn['occurredAt'],
          turn['timestamp'],
          turn['createdAt'],
          turn['updatedAt'],
        ]
      : [
          params['occurredAt'],
          params['timestamp'],
          params['createdAt'],
          params['updatedAt'],
          item['occurredAt'],
          item['timestamp'],
          item['createdAt'],
          item['updatedAt'],
          turn['occurredAt'],
          turn['timestamp'],
          turn['createdAt'],
          turn['updatedAt'],
          thread['occurredAt'],
          thread['timestamp'],
          thread['createdAt'],
          thread['updatedAt'],
        ];

  for (final candidate in candidates) {
    final date = _normalizeTimestamp(candidate);
    if (date != null) {
      return date;
    }
  }
  return null;
}

DateTime? _normalizeTimestamp(Object? value) {
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is int) {
    return _fromEpoch(value);
  }
  if (value is num) {
    return _fromEpoch(value.toInt());
  }
  if (value is String) {
    final parsedDate = DateTime.tryParse(value);
    if (parsedDate != null) {
      return parsedDate.toUtc();
    }
    final parsedInt = int.tryParse(value);
    if (parsedInt != null) {
      return _fromEpoch(parsedInt);
    }
  }
  return null;
}

DateTime _fromEpoch(int value) {
  final milliseconds = value > 9999999999 ? value : value * 1000;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}

bool _isMaterializationError(AppServerRpcException error) {
  final message = error.message.toLowerCase();
  return message.contains('not materialized yet') ||
      message.contains('includeTurns is unavailable');
}

void _logAppServerHistory(String action, Map<String, Object?> fields) {
  final compactFields = Map<String, Object?>.from(fields)
    ..removeWhere(
      (_, value) => value == null || value.toString().trim().isEmpty,
    );
  UiDebugLogger.log('Protocol', action, fields: compactFields);
}

void _logAppServerNotification(
  String method,
  Map<String, dynamic> params, {
  required Object? rawId,
}) {
  final receivedAt = DateTime.now().toUtc().toIso8601String();
  final thread = asJsonMap(params['thread']);
  final turn = asJsonMap(params['turn']);
  final item = asJsonMap(params['item']);
  final fields =
      <String, Object?>{
        'requestId': rawId,
        'threadId':
            params['threadId'] ??
            params['conversationId'] ??
            thread['id'] ??
            turn['threadId'] ??
            item['threadId'],
        'turnId': params['turnId'] ?? turn['id'],
        'itemId': params['itemId'] ?? item['id'],
        'status':
            asJsonMap(params['status'])['type'] ??
            params['status'] ??
            item['status'],
        'itemType': item['type'],
        'phase': item['phase'] ?? params['phase'],
        'receivedAt': receivedAt,
        'deltaLen': _deltaLength(params['delta']),
        'delta': _deltaPreview(params['delta']),
      }..removeWhere(
        (_, value) => value == null || value.toString().trim().isEmpty,
      );
  UiDebugLogger.log(
    'Protocol',
    'notification',
    threadId: fields['threadId']?.toString(),
    fields: {'method': method, ...fields},
  );
}

void _recordAppServerEntry({
  required AppServerLogEntryKind kind,
  required AppServerLogDirection direction,
  String? clientKey,
  String? rpcId,
  String? method,
  String? threadId,
  String? turnId,
  String? itemId,
  Duration? duration,
  String? previewText,
  Object? payload,
}) {
  appServerLogStore.record(
    kind: kind,
    direction: direction,
    clientKey: clientKey,
    rpcId: rpcId,
    method: method,
    threadId: threadId,
    turnId: turnId,
    itemId: itemId,
    duration: duration,
    previewText: previewText,
    payload: payload,
  );
}

_AppServerLogContext _logContextFromPayload(Object? payload) {
  final params = asJsonMap(payload);
  if (params.isEmpty) {
    return const _AppServerLogContext();
  }

  final thread = asJsonMap(params['thread']);
  final turn = asJsonMap(params['turn']);
  final item = asJsonMap(params['item']);
  return _AppServerLogContext(
    threadId: _optionalString(
      params['threadId'] ??
          params['conversationId'] ??
          thread['id'] ??
          turn['threadId'] ??
          item['threadId'],
    ),
    turnId: _optionalString(params['turnId'] ?? turn['id']),
    itemId: _optionalString(params['itemId'] ?? item['id']),
  );
}

_AppServerLogContext _mergeLogContext(
  _AppServerLogContext primary,
  _AppServerLogContext secondary,
) {
  return _AppServerLogContext(
    threadId: primary.threadId ?? secondary.threadId,
    turnId: primary.turnId ?? secondary.turnId,
    itemId: primary.itemId ?? secondary.itemId,
  );
}

String _compactLogValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  final text = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= 120) {
    return text;
  }
  return '${text.substring(0, 117)}...';
}

int? _deltaLength(Object? delta) {
  if (delta == null) {
    return null;
  }
  if (delta is String) {
    return delta.length;
  }
  if (delta is List) {
    return delta
        .map((entry) => _compactLogValue(entry).length)
        .fold<int>(0, (sum, length) => sum + length);
  }
  return _compactLogValue(delta).length;
}

String? _deltaPreview(Object? delta) {
  if (delta == null) {
    return null;
  }
  if (delta is String) {
    final text = delta.trim();
    return text.isEmpty ? null : text;
  }
  if (delta is List) {
    final buffer = StringBuffer();
    for (final entry in delta) {
      final preview = _deltaPreview(entry);
      if (preview != null && preview.isNotEmpty) {
        buffer.write(preview);
      }
    }
    final text = buffer.toString().trim();
    return text.isEmpty ? null : text;
  }
  if (delta is Map) {
    final map = asJsonMap(delta);
    final text = readString(map, const ['text', 'value', 'content']).trim();
    return text.isEmpty ? null : text;
  }
  return null;
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

bool _hasValue(Object? value) {
  return _optionalString(value) != null;
}

String? _normalizeCwd(String? cwd) {
  if (cwd == null || cwd.trim().isEmpty) {
    return null;
  }
  return cwd.replaceFirst(RegExp(r'^\\\\\?\\'), '');
}

String? _joinCommand(Object? value) {
  return joinCommandParts(value);
}

Map<String, Map<String, dynamic>> _threadItemsById(
  Map<String, dynamic> thread,
) {
  final itemsById = <String, Map<String, dynamic>>{};
  for (final turn in asJsonList(thread['turns']).map(asJsonMap)) {
    for (final item in asJsonList(turn['items']).map(asJsonMap)) {
      final itemId = _optionalString(item['id']);
      if (itemId != null) {
        itemsById[itemId] = item;
      }
    }
  }
  return itemsById;
}

bool _shouldKeepPendingServerRequest(
  _PendingServerRequestRecord request, {
  required String? activeTurnId,
  required Map<String, Map<String, dynamic>> itemStatesById,
}) {
  if (activeTurnId == null) {
    return false;
  }
  if (!_isApprovalRequestMethod(request.method)) {
    return true;
  }
  final itemId = request.itemId;
  if (itemId == null) {
    return true;
  }
  final item = itemStatesById[itemId];
  if (item == null || item.isEmpty) {
    return true;
  }
  return _itemAwaitingApproval(item);
}

bool _isApprovalRequestMethod(String method) {
  switch (method) {
    case 'item/commandExecution/requestApproval':
    case 'item/fileChange/requestApproval':
    case 'item/permissions/requestApproval':
    case 'execCommandApproval':
    case 'applyPatchApproval':
      return true;
    default:
      return false;
  }
}

bool _itemAwaitingApproval(Map<String, dynamic> item) {
  final approvalStatus = _optionalString(item['approvalStatus']);
  if (approvalStatus != null) {
    return _isPendingApprovalState(approvalStatus);
  }
  final status = _optionalString(item['status']);
  if (status == null) {
    return true;
  }
  return _isPendingApprovalState(status);
}

bool _isPendingApprovalState(String value) {
  switch (value.trim().toLowerCase()) {
    case 'pending':
    case 'requested':
    case 'requires_approval':
    case 'requires-approval':
    case 'needs_approval':
    case 'needs-approval':
    case 'waiting':
    case 'waiting_for_approval':
    case 'waiting-for-approval':
      return true;
    default:
      return false;
  }
}

String _approvalAwareItemStatus(
  Map<String, dynamic> item, {
  required String fallback,
}) {
  final approvalStatus = _optionalString(item['approvalStatus']);
  if (approvalStatus != null) {
    return approvalStatus;
  }
  final status = _optionalString(item['status']);
  return status ?? fallback;
}

String _requestKey(Object? rawId) => rawId?.toString() ?? '';

extension<T> on Iterable<T> {
  Iterable<R> mapIndexed<R>(R Function(int index, T item) transform) sync* {
    var index = 0;
    for (final item in this) {
      yield transform(index, item);
      index += 1;
    }
  }
}
