import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final settings = ProxySettings.fromEnvironment();
  await runZonedGuarded(
    () async {
      try {
        final subcommandIndex = _findAppServerSubcommand(args);
        final exitCode =
            subcommandIndex >= 0 &&
                _shouldInterceptAppServer(args.sublist(subcommandIndex + 1))
            ? await CodexProxy(
                settings,
              ).runAppServerProxy(args.sublist(subcommandIndex + 1))
            : await CodexProxy(settings).runPassthrough(args);
        exit(exitCode);
      } on ProxyException catch (error) {
        settings.log('fatal.proxy_exception', {'error': '$error'});
        stderr.writeln('[codex-proxy] $error');
        exit(1);
      } on ProcessException catch (error) {
        settings.log('fatal.process_exception', {'error': error.message});
        stderr.writeln('[codex-proxy] ${error.message}');
        exit(1);
      }
    },
    (Object error, StackTrace stackTrace) {
      settings.log('fatal.uncaught', {
        'error': '$error',
        'stack': _singleLineStack(stackTrace),
      });
      stderr.writeln('[codex-proxy] unhandled error: $error');
      exit(1);
    },
  );
}

int _findAppServerSubcommand(List<String> args) {
  for (var index = 0; index < args.length; index += 1) {
    if (args[index] == 'app-server') {
      return index;
    }
  }
  return -1;
}

bool _hasNestedAppServerSubcommand(List<String> args) {
  for (final arg in args) {
    if (!arg.startsWith('-')) {
      return true;
    }
  }
  return false;
}

bool _hasExplicitListenArg(List<String> args) {
  for (final arg in args) {
    if (arg == '--listen' || arg.startsWith('--listen=')) {
      return true;
    }
  }
  return false;
}

bool _shouldInterceptAppServer(List<String> args) {
  if (_hasNestedAppServerSubcommand(args) || _hasExplicitListenArg(args)) {
    return false;
  }
  for (final arg in args) {
    if (arg == '--help' || arg == '-h' || arg == '--version' || arg == '-V') {
      return false;
    }
  }
  return true;
}

class CodexProxy {
  CodexProxy(this.settings);

  final ProxySettings settings;

  Future<int> runPassthrough(List<String> args) async {
    final cliPath = await settings.resolveRealCliPath();
    settings.log('passthrough', {'cli': cliPath, 'args': args.join(' ')});
    final process = await Process.start(
      cliPath,
      args,
      runInShell: Platform.isWindows,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }

  Future<int> runAppServerProxy(List<String> appServerArgs) async {
    final cliPath = await settings.resolveRealCliPath();
    final childArgs = ['app-server', ...appServerArgs];
    settings.log('stdio_proxy.launch', {
      'cli': cliPath,
      'args': childArgs.join(' '),
      'mirrorWs': settings.mirrorWsUri.toString(),
    });
    final child = await Process.start(
      cliPath,
      childArgs,
      runInShell: Platform.isWindows,
      mode: ProcessStartMode.normal,
    );
    return _ProxyRuntime(settings: settings, child: child).run();
  }
}

class _ProxyRuntime {
  _ProxyRuntime({required this.settings, required this.child});

  static const _primaryClientId = 'stdio';

  final ProxySettings settings;
  final Process child;

  final Map<String, _WsClient> _wsClients = {};
  final Map<String, _PendingClientRequest> _pendingClientRequests = {};
  final Map<String, _PendingServerRequest> _pendingServerRequests = {};
  final Map<String, _PendingServerRequest> _pendingServerRequestByClientId = {};

  HttpServer? _mirrorServer;
  Future<void> _childWriteQueue = Future<void>.value();
  bool _finishing = false;
  int _nextWsClientOrdinal = 1;
  int _nextWsRequestOrdinal = 1;
  int _nextServerRequestOrdinal = 1;
  Object? _cachedInitializeResult;

  Future<int> run() async {
    final done = Completer<int>();

    await _startMirrorServer();

    unawaited(_pumpChildStdout(done));
    unawaited(_pumpChildStderr(done));
    unawaited(_pumpPrimaryStdin(done));
    unawaited(_watchChildExit(done));

    return done.future;
  }

  Future<void> _startMirrorServer() async {
    final uri = settings.mirrorWsUri;
    if (uri.scheme != 'ws') {
      settings.log('mirror_server.unsupported_scheme', {'uri': uri.toString()});
      return;
    }
    try {
      _mirrorServer = await HttpServer.bind(uri.host, uri.port, shared: false);
      settings.log('mirror_server.listening', {'uri': uri.toString()});
      unawaited(
        _mirrorServer!.forEach((request) async {
          if (!WebSocketTransformer.isUpgradeRequest(request)) {
            request.response
              ..statusCode = HttpStatus.upgradeRequired
              ..write('WebSocket upgrade required')
              ..close();
            return;
          }
          if (!_pathMatches(request.uri.path, uri.path)) {
            request.response
              ..statusCode = HttpStatus.notFound
              ..write('Proxy endpoint not found')
              ..close();
            return;
          }
          final socket = await WebSocketTransformer.upgrade(request);
          await _handleWsClient(socket);
        }),
      );
    } catch (error, stackTrace) {
      settings.log('mirror_server.open_failed', {
        'uri': uri.toString(),
        'error': '$error',
        'stack': _singleLineStack(stackTrace),
      });
    }
  }

  Future<void> _handleWsClient(WebSocket socket) async {
    final client = _WsClient(
      id: 'ws-${_nextWsClientOrdinal++}',
      socket: socket,
    );
    _wsClients[client.id] = client;
    settings.log('mirror_client.connected', {'clientId': client.id});
    try {
      await for (final message in socket) {
        final text = switch (message) {
          String value => value,
          List<int> value => utf8.decode(value),
          _ => message.toString(),
        };
        await _handleWsClientLine(client, text);
      }
    } catch (error, stackTrace) {
      settings.log('mirror_client.error', {
        'clientId': client.id,
        'error': '$error',
        'stack': _singleLineStack(stackTrace),
      });
    } finally {
      await _disconnectWsClient(client);
    }
  }

  Future<void> _disconnectWsClient(_WsClient client) async {
    if (_wsClients.remove(client.id) == null) {
      return;
    }
    settings.log('mirror_client.disconnected', {'clientId': client.id});
    final pendingKeys = _pendingServerRequestByClientId.keys
        .where((key) => key.startsWith('${client.id}|'))
        .toList();
    for (final key in pendingKeys) {
      _pendingServerRequestByClientId.remove(key);
    }
    try {
      await client.socket.close();
    } catch (_) {}
  }

  Future<void> _pumpChildStdout(Completer<int> done) async {
    try {
      await for (final line
          in child.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        await _handleChildLine(line);
      }
    } catch (error, stackTrace) {
      settings.log('child.stdout_error', {
        'error': '$error',
        'stack': _singleLineStack(stackTrace),
      });
      await _finish(done, 1);
      return;
    }
    settings.log('child.stdout_closed');
  }

  Future<void> _pumpChildStderr(Completer<int> done) async {
    try {
      await for (final chunk in child.stderr.transform(utf8.decoder)) {
        stderr.write(chunk);
      }
    } catch (error, stackTrace) {
      settings.log('child.stderr_error', {
        'error': '$error',
        'stack': _singleLineStack(stackTrace),
      });
      await _finish(done, 1);
    }
  }

  Future<void> _pumpPrimaryStdin(Completer<int> done) async {
    try {
      await for (final line
          in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
        await _handlePrimaryLine(line);
      }
    } catch (error, stackTrace) {
      settings.log('primary.stdin_error', {
        'error': '$error',
        'stack': _singleLineStack(stackTrace),
      });
      await _finish(done, 1);
      return;
    }
    settings.log('primary.stdin_closed');
    await _finish(done, 0);
  }

  Future<void> _watchChildExit(Completer<int> done) async {
    final exitCode = await child.exitCode;
    settings.log('child.exit', {'code': '$exitCode'});
    await _finish(done, exitCode);
  }

  Future<void> _finish(Completer<int> done, int exitCode) async {
    if (done.isCompleted || _finishing) {
      return;
    }
    _finishing = true;
    settings.log('stdio_proxy.finish', {'code': '$exitCode'});

    try {
      await child.stdin.close();
    } catch (_) {}

    for (final client in _wsClients.values.toList()) {
      try {
        await client.socket.close();
      } catch (_) {}
    }
    _wsClients.clear();

    if (_mirrorServer != null) {
      try {
        await _mirrorServer!.close(force: true);
      } catch (_) {}
    }

    if (child.kill()) {
      settings.log('child.kill_requested');
    }

    done.complete(exitCode);
  }

  Future<void> _handlePrimaryLine(String line) async {
    final decoded = _tryDecodeJsonObject(line);
    if (decoded == null) {
      await _writeToChild(line);
      return;
    }

    if (_isServerResponse(decoded)) {
      final pending = _lookupPendingServerRequest(
        _primaryClientId,
        decoded['id'],
      );
      if (pending != null) {
        await _forwardServerRequestResponse(
          clientId: _primaryClientId,
          localId: decoded['id'],
          response: decoded,
        );
        return;
      }
    }

    if (_isClientRequest(decoded)) {
      final intercepted = await _interceptClientRequest(decoded);
      if (intercepted != null) {
        await _writePrimary(jsonEncode(intercepted));
        return;
      }

      final method = decoded['method']?.toString() ?? '';
      final id = decoded['id'];
      _pendingClientRequests[_idKey(id)] = _PendingClientRequest(
        clientId: _primaryClientId,
        clientRequestId: id,
        childRequestId: id,
        method: method,
      );
    }

    await _writeToChild(line);
  }

  Future<void> _handleWsClientLine(_WsClient client, String line) async {
    final decoded = _tryDecodeJsonObject(line);
    if (decoded == null) {
      settings.log('mirror_client.invalid_json', {'clientId': client.id});
      return;
    }

    if (_isServerResponse(decoded)) {
      final pending = _lookupPendingServerRequest(client.id, decoded['id']);
      if (pending == null) {
        await client.sendJson(
          _jsonRpcError(
            id: decoded['id'],
            message: 'Unknown server request response id.',
          ),
        );
        return;
      }
      await _forwardServerRequestResponse(
        clientId: client.id,
        localId: decoded['id'],
        response: decoded,
      );
      return;
    }

    if (!_isClientRequest(decoded) && !_isNotification(decoded)) {
      await client.sendJson(
        _jsonRpcError(id: decoded['id'], message: 'Unsupported message shape.'),
      );
      return;
    }

    final method = decoded['method']?.toString();
    if (method == 'initialize') {
      await _handleWsInitialize(client, decoded);
      return;
    }
    if (method == 'initialized') {
      client.initialized = true;
      settings.log('mirror_client.initialized', {'clientId': client.id});
      return;
    }
    if (method == 'shutdown' || method == 'exit') {
      await client.sendJson(
        _jsonRpcError(
          id: decoded['id'],
          message: 'shutdown and exit are not supported through codex-proxy.',
        ),
      );
      return;
    }
    if (!client.initialized) {
      await client.sendJson(
        _jsonRpcError(
          id: decoded['id'],
          message: 'Client must send initialize and initialized first.',
        ),
      );
      return;
    }

    if (_isClientRequest(decoded)) {
      final intercepted = await _interceptClientRequest(decoded);
      if (intercepted != null) {
        await client.sendJson(intercepted);
        return;
      }

      final originalId = decoded['id'];
      final childId = 'ws:${client.id}:${_nextWsRequestOrdinal++}';
      _pendingClientRequests[_idKey(childId)] = _PendingClientRequest(
        clientId: client.id,
        clientRequestId: originalId,
        childRequestId: childId,
        method: method ?? '',
      );
      final forwarded = Map<String, Object?>.from(decoded)..['id'] = childId;
      await _writeToChild(jsonEncode(forwarded));
      return;
    }

    await _writeToChild(line);
  }

  Future<void> _handleWsInitialize(
    _WsClient client,
    Map<String, Object?> request,
  ) async {
    if (_cachedInitializeResult == null) {
      await client.sendJson(
        _jsonRpcError(
          id: request['id'],
          message: 'Primary Codex session has not initialized yet.',
        ),
      );
      return;
    }
    client.initialized = true;
    await client.sendJson({
      'jsonrpc': request['jsonrpc'] ?? '2.0',
      'id': request['id'],
      'result': _cachedInitializeResult,
    });
    settings.log('mirror_client.initialize_served', {'clientId': client.id});
  }

  Future<Map<String, Object?>?> _interceptClientRequest(
    Map<String, Object?> request,
  ) async {
    final method = request['method']?.toString();
    if (method == null) {
      return null;
    }

    try {
      switch (method) {
        case 'workspace/listRoots':
          return {
            'jsonrpc': request['jsonrpc'] ?? '2.0',
            'id': request['id'],
            'result': {'data': _listWorkspaceRoots()},
          };
        case 'workspace/listDirectory':
          final params = switch (request['params']) {
            Map<String, Object?> value => value,
            Map value => value.cast<String, Object?>(),
            _ => const <String, Object?>{},
          };
          final path = params['path']?.toString().trim() ?? '';
          if (path.isEmpty) {
            return _jsonRpcError(
              id: request['id'],
              message: 'workspace/listDirectory requires a path.',
            );
          }
          final entries = await _listWorkspaceDirectories(path);
          return {
            'jsonrpc': request['jsonrpc'] ?? '2.0',
            'id': request['id'],
            'result': {'data': entries},
          };
      }
    } on FileSystemException catch (error) {
      return _jsonRpcError(id: request['id'], message: error.message);
    }

    return null;
  }

  Future<void> _handleChildLine(String line) async {
    final decoded = _tryDecodeJsonObject(line);
    if (decoded == null) {
      await _writePrimary(line);
      return;
    }

    if (_isResponse(decoded)) {
      final pending = _pendingClientRequests.remove(_idKey(decoded['id']));
      if (pending == null) {
        await _writePrimary(line);
        return;
      }
      if (pending.clientId == _primaryClientId) {
        if (pending.method == 'initialize' && decoded.containsKey('result')) {
          _cachedInitializeResult = decoded['result'];
        }
        await _writePrimary(line);
        return;
      }
      final response = Map<String, Object?>.from(decoded)
        ..['id'] = pending.clientRequestId;
      await _sendToWsClient(pending.clientId, response);
      return;
    }

    if (_isServerRequest(decoded)) {
      final pending = _PendingServerRequest(childRequestId: decoded['id']);
      _pendingServerRequests[_idKey(decoded['id'])] = pending;
      _bindPendingServerRequest(_primaryClientId, decoded['id'], pending);
      await _writePrimary(line);

      for (final client in _wsClients.values) {
        if (!client.initialized) {
          continue;
        }
        final localId = 'srv:${client.id}:${_nextServerRequestOrdinal++}';
        _bindPendingServerRequest(client.id, localId, pending);
        final forwarded = Map<String, Object?>.from(decoded)..['id'] = localId;
        await client.sendJson(forwarded);
      }
      return;
    }

    if (_isNotification(decoded)) {
      await _writePrimary(line);
      await _broadcastToWsClients(decoded);
      return;
    }

    await _writePrimary(line);
  }

  void _bindPendingServerRequest(
    String clientId,
    Object? localId,
    _PendingServerRequest pending,
  ) {
    final key = _pendingServerRequestClientKey(clientId, localId);
    pending.clientLocalIds[clientId] = localId;
    _pendingServerRequestByClientId[key] = pending;
  }

  _PendingServerRequest? _lookupPendingServerRequest(
    String clientId,
    Object? localId,
  ) {
    return _pendingServerRequestByClientId[_pendingServerRequestClientKey(
      clientId,
      localId,
    )];
  }

  Future<void> _forwardServerRequestResponse({
    required String clientId,
    required Object? localId,
    required Map<String, Object?> response,
  }) async {
    final key = _pendingServerRequestClientKey(clientId, localId);
    final pending = _pendingServerRequestByClientId.remove(key);
    if (pending == null) {
      return;
    }
    if (pending.responded) {
      return;
    }
    pending.responded = true;

    for (final entry in pending.clientLocalIds.entries) {
      final removeKey = _pendingServerRequestClientKey(entry.key, entry.value);
      _pendingServerRequestByClientId.remove(removeKey);
    }
    _pendingServerRequests.remove(_idKey(pending.childRequestId));

    final forwarded = Map<String, Object?>.from(response)
      ..['id'] = pending.childRequestId;
    await _writeToChild(jsonEncode(forwarded));
  }

  Future<void> _broadcastToWsClients(Map<String, Object?> message) async {
    for (final client in _wsClients.values) {
      if (!client.initialized) {
        continue;
      }
      await client.sendJson(message);
    }
  }

  Future<void> _sendToWsClient(
    String clientId,
    Map<String, Object?> message,
  ) async {
    final client = _wsClients[clientId];
    if (client == null) {
      return;
    }
    await client.sendJson(message);
  }

  Future<void> _writePrimary(String line) async {
    stdout.writeln(line);
    await stdout.flush();
  }

  Future<void> _writeToChild(String line) {
    _childWriteQueue = _childWriteQueue.then((_) async {
      child.stdin.writeln(line);
      await child.stdin.flush();
    });
    return _childWriteQueue;
  }
}

class _WsClient {
  _WsClient({required this.id, required this.socket});

  final String id;
  final WebSocket socket;
  bool initialized = false;

  Future<void> sendJson(Map<String, Object?> message) async {
    socket.add(jsonEncode(message));
  }
}

class _PendingClientRequest {
  const _PendingClientRequest({
    required this.clientId,
    required this.clientRequestId,
    required this.childRequestId,
    required this.method,
  });

  final String clientId;
  final Object? clientRequestId;
  final Object? childRequestId;
  final String method;
}

class _PendingServerRequest {
  _PendingServerRequest({required this.childRequestId});

  final Object? childRequestId;
  final Map<String, Object?> clientLocalIds = {};
  bool responded = false;
}

class ProxySettings {
  ProxySettings({
    required this.mirrorWsUri,
    required this.verbose,
    this.realCliOverride,
  });

  factory ProxySettings.fromEnvironment() {
    final env = Platform.environment;
    final mirrorWs = env['CODEX_PROXY_MIRROR_WS']?.trim();
    final verboseRaw = env['CODEX_PROXY_DEBUG']?.trim().toLowerCase() ?? '0';
    return ProxySettings(
      mirrorWsUri: Uri.parse(
        mirrorWs?.isEmpty ?? true ? 'ws://127.0.0.1:8767' : mirrorWs!,
      ),
      verbose: verboseRaw == '1' || verboseRaw == 'true',
      realCliOverride: env['CODEX_PROXY_REAL_CLI']?.trim(),
    );
  }

  final Uri mirrorWsUri;
  final bool verbose;
  final String? realCliOverride;

  Future<String> resolveRealCliPath() async {
    final override = realCliOverride;
    if (override != null && override.isNotEmpty) {
      return override;
    }

    final currentLocations = _currentExecutableCandidates();
    for (final candidate in _candidateCliPaths()) {
      final normalized = _normalizePath(candidate);
      if (normalized == null) {
        continue;
      }
      if (currentLocations.contains(normalized)) {
        continue;
      }
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    return 'codex';
  }

  void log(String action, [Map<String, String> fields = const {}]) {
    if (!verbose) {
      return;
    }
    final normalized = fields.entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    stderr.writeln(
      '[codex-proxy] ${DateTime.now().toUtc().toIso8601String()} '
      '$action${normalized.isEmpty ? '' : ' $normalized'}',
    );
  }

  Set<String> _currentExecutableCandidates() {
    final values = <String>{
      if (_normalizePath(Platform.script.toFilePath()) case final value?) value,
      if (_normalizePath(Platform.resolvedExecutable) case final value?) value,
    };
    return values;
  }

  Iterable<String> _candidateCliPaths() sync* {
    final path = Platform.environment['PATH'] ?? '';
    final separator = Platform.isWindows ? ';' : ':';
    final names = Platform.isWindows
        ? const ['codex.cmd', 'codex.exe', 'codex.ps1', 'codex.bat']
        : const ['codex'];
    for (final rawEntry in path.split(separator)) {
      final entry = rawEntry.trim();
      if (entry.isEmpty) {
        continue;
      }
      for (final name in names) {
        yield _joinPath(entry, name);
      }
    }
  }
}

Map<String, Object?>? _tryDecodeJsonObject(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map<String, dynamic>) {
      return decoded.cast<String, Object?>();
    }
  } catch (_) {}
  return null;
}

bool _isClientRequest(Map<String, Object?> message) {
  return message.containsKey('id') && message['method'] is String;
}

bool _isServerRequest(Map<String, Object?> message) {
  return _isClientRequest(message);
}

bool _isResponse(Map<String, Object?> message) {
  return message.containsKey('id') &&
      !message.containsKey('method') &&
      (message.containsKey('result') || message.containsKey('error'));
}

bool _isServerResponse(Map<String, Object?> message) {
  return _isResponse(message);
}

bool _isNotification(Map<String, Object?> message) {
  return !message.containsKey('id') && message['method'] is String;
}

Map<String, Object?> _jsonRpcError({
  required Object? id,
  required String message,
}) {
  return {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': -32000, 'message': message},
  };
}

String _pendingServerRequestClientKey(String clientId, Object? localId) {
  return '$clientId|${_idKey(localId)}';
}

String _idKey(Object? id) {
  return jsonEncode(id);
}

bool _pathMatches(String actual, String expected) {
  final normalizedActual = actual.isEmpty ? '/' : actual;
  final normalizedExpected = expected.isEmpty ? '/' : expected;
  return normalizedActual == normalizedExpected;
}

String _joinPath(String directory, String fileName) {
  if (directory.endsWith('\\') || directory.endsWith('/')) {
    return '$directory$fileName';
  }
  return '$directory${Platform.pathSeparator}$fileName';
}

List<Map<String, Object?>> _listWorkspaceRoots() {
  if (Platform.isWindows) {
    final roots = <Map<String, Object?>>[];
    for (final codeUnit in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.codeUnits) {
      final letter = String.fromCharCode(codeUnit);
      final path = '$letter:\\';
      if (_directoryExistsSafe(path)) {
        roots.add({'path': path, 'label': path});
      }
    }
    return roots;
  }

  final roots = <Map<String, Object?>>[];

  void addIfExists(String path, {String? label}) {
    if (_directoryExistsSafe(path)) {
      roots.add({'path': path, 'label': label ?? path});
    }
  }

  addIfExists('/', label: '/');
  final home = Platform.environment['HOME'];
  if (home != null && home.trim().isNotEmpty) {
    addIfExists(home, label: _directoryTreeLabel(home));
  }
  if (Platform.isAndroid) {
    addIfExists('/storage/emulated/0', label: 'Internal storage');
    addIfExists('/sdcard', label: 'sdcard');
  }
  return roots;
}

Future<List<Map<String, Object?>>> _listWorkspaceDirectories(String path) async {
  final directory = Directory(path);
  if (!await directory.exists()) {
    return const <Map<String, Object?>>[];
  }

  final entries = <Map<String, Object?>>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! Directory) {
      continue;
    }
    final childPath = entity.path;
    final label = _basename(childPath);
    if (label.isEmpty || label.startsWith('.')) {
      continue;
    }
    entries.add({'path': childPath, 'label': label});
  }

  entries.sort(
    (left, right) => (left['label'] as String).toLowerCase().compareTo(
      (right['label'] as String).toLowerCase(),
    ),
  );
  return entries;
}

bool _directoryExistsSafe(String path) {
  try {
    return Directory(path).existsSync();
  } on FileSystemException {
    return false;
  }
}

String _directoryTreeLabel(String path) {
  final name = _basename(path);
  return name.isEmpty ? path : name;
}

String _basename(String path) {
  var normalized = path.replaceAll('\\', '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  final index = normalized.lastIndexOf('/');
  if (index < 0) {
    return normalized;
  }
  return normalized.substring(index + 1);
}

String? _normalizePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed.replaceAll('/', '\\').toLowerCase();
}

class ProxyException implements Exception {
  const ProxyException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _singleLineStack(StackTrace stackTrace) {
  return stackTrace.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
