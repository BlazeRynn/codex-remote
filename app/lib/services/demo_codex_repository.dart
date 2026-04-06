import 'dart:async';

import '../models/bridge_config.dart';
import '../models/bridge_health.dart';
import '../models/codex_composer_mode.dart';
import '../models/codex_model_option.dart';
import '../models/codex_pending_request.dart';
import '../models/codex_thread_bundle.dart';
import '../models/codex_thread_item.dart';
import '../models/codex_thread_runtime.dart';
import '../models/codex_thread_summary.dart';
import 'bridge_realtime_client.dart';
import 'codex_repository.dart';

class DemoCodexRepository implements CodexRepository {
  DemoCodexRepository(this.config);

  final BridgeConfig config;
  static final _store = _DemoStore();

  @override
  Future<BridgeHealth> getHealth() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return const BridgeHealth(
      reachable: true,
      status: 'demo',
      version: 'fixture-2',
      message: 'Interactive demo workspace',
    );
  }

  @override
  Future<List<CodexThreadSummary>> listThreads() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _store.listThreads();
  }

  @override
  Future<CodexThreadBundle> getThreadBundle(String threadId) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _store.readThread(threadId);
  }

  @override
  Future<List<CodexModelOption>> listModels() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return _store.models;
  }

  @override
  Future<CodexThreadRuntime> getThreadRuntime(String threadId) async {
    await Future<void>.delayed(const Duration(milliseconds: 90));
    return _store.readRuntime(threadId);
  }

  @override
  Future<CodexThreadBundle> createThread({
    required String message,
    required CodexComposerMode mode,
    String? model,
    String? cwd,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return _store.createThread(
      message: message,
      mode: mode,
      model: model,
      cwd: cwd,
    );
  }

  @override
  Future<CodexThreadRuntime> sendMessage({
    required String threadId,
    required String message,
    String? expectedTurnId,
    String? model,
    CodexComposerMode? mode,
    String? cwd,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _store.sendMessage(
      threadId: threadId,
      message: message,
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
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _store.interruptTurn(threadId: threadId, turnId: turnId);
  }

  @override
  Future<CodexThreadRuntime> respondToPendingRequest({
    required String requestId,
    required String action,
    Map<String, dynamic>? answers,
    Object? content,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _store.respondToPendingRequest(
      requestId: requestId,
      action: action,
      answers: answers,
      content: content,
    );
  }

  @override
  CodexRealtimeSession openThreadEvents({String? threadId}) {
    return _DemoRealtimeSession(threadId: threadId, store: _store);
  }
}

class _DemoRealtimeSession implements CodexRealtimeSession {
  _DemoRealtimeSession({required this.threadId, required _DemoStore store})
    : _store = store {
    final connectedAt = DateTime.now().toUtc();
    _controller.add(
      BridgeRealtimeEvent(
        type: 'app_server.connected',
        description: 'Connected to demo workspace',
        receivedAt: connectedAt,
        raw: {
          if (threadId != null) 'threadId': threadId,
          'type': 'app_server.connected',
          'message': 'Connected to demo workspace',
          'occurredAt': connectedAt.toIso8601String(),
          'source': 'demo',
        },
      ),
    );

    _subscription = _store.events(threadId: threadId).listen(_controller.add);
  }

  final String? threadId;
  final _DemoStore _store;
  final _controller = StreamController<BridgeRealtimeEvent>();
  late final StreamSubscription<BridgeRealtimeEvent> _subscription;

  @override
  Stream<BridgeRealtimeEvent> get stream => _controller.stream;

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _controller.close();
  }
}

class _DemoStore {
  _DemoStore() {
    final now = DateTime.now().toUtc();
    _models = const [
      CodexModelOption(
        id: 'gpt-5.4',
        model: 'gpt-5.4',
        displayName: 'GPT-5.4',
        description: 'Balanced frontier agent for coding and control tasks.',
        isDefault: true,
        defaultReasoningEffort: 'medium',
        supportedReasoningEfforts: ['low', 'medium', 'high'],
      ),
      CodexModelOption(
        id: 'gpt-5.3-codex',
        model: 'gpt-5.3-codex',
        displayName: 'GPT-5.3 Codex',
        description: 'Fast coding specialist for routine implementation loops.',
        isDefault: false,
        defaultReasoningEffort: 'medium',
        supportedReasoningEfforts: ['medium', 'high'],
      ),
    ];

    final seed = _buildSeedThreads(now);
    for (final thread in seed) {
      _threads[thread.bundle.thread.id] = thread;
    }

    _threadCounter = _threads.length + 1;
    _itemCounter = 100;
    _turnCounter = 20;
    _requestCounter = 10;
  }

  late final List<CodexModelOption> _models;
  final Map<String, _DemoThreadState> _threads = {};
  final _eventsController = StreamController<BridgeRealtimeEvent>.broadcast();

  int _threadCounter = 1;
  int _itemCounter = 1;
  int _turnCounter = 1;
  int _requestCounter = 1;

  List<CodexModelOption> get models => _models;

  List<CodexThreadSummary> listThreads() {
    final threads = _threads.values.map((state) => state.bundle.thread).toList();
    threads.sort((left, right) {
      final leftTime = left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightTime = right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return rightTime.compareTo(leftTime);
    });
    return threads;
  }

  CodexThreadBundle readThread(String threadId) {
    return _threads[threadId]?.bundle ?? _threads.values.first.bundle;
  }

  CodexThreadRuntime readRuntime(String threadId) {
    return _threads[threadId]?.runtime ??
        CodexThreadRuntime(threadId: threadId, pendingRequests: const []);
  }

  Stream<BridgeRealtimeEvent> events({String? threadId}) {
    if (threadId == null) {
      return _eventsController.stream;
    }
    return _eventsController.stream.where(
      (event) => _readThreadId(event.raw) == null || _readThreadId(event.raw) == threadId,
    );
  }

  CodexThreadBundle createThread({
    required String message,
    required CodexComposerMode mode,
    String? model,
    String? cwd,
  }) {
    final threadId = 'demo-thread-${_threadCounter.toString().padLeft(3, '0')}';
    _threadCounter += 1;
    final now = DateTime.now().toUtc();
    final turnId = _nextTurnId();

    final userItem = _newItem(
      type: 'user.message',
      title: 'Prompt',
      body: message,
      actor: 'user',
      status: 'done',
      createdAt: now,
    );

    final summary = CodexThreadSummary(
      id: threadId,
      title: _titleFromMessage(message),
      status: 'active',
      preview: message,
      createdAt: now,
      updatedAt: now,
      itemCount: 1,
    );

    _threads[threadId] = _DemoThreadState(
      bundle: CodexThreadBundle(thread: summary, items: [userItem]),
      runtime: CodexThreadRuntime(threadId: threadId, activeTurnId: turnId),
      mode: mode,
      model: model ?? _defaultModel().model,
      cwd: cwd,
    );

    _publishEvent(
      threadId: threadId,
      type: 'thread.started',
      message: 'Started ${summary.title}',
    );
    _publishEvent(
      threadId: threadId,
      type: 'turn.started',
      message: 'Turn started',
    );

    _scheduleContinuation(threadId, originalMessage: message);
    return _threads[threadId]!.bundle;
  }

  CodexThreadRuntime sendMessage({
    required String threadId,
    required String message,
    String? expectedTurnId,
    String? model,
    CodexComposerMode? mode,
    String? cwd,
  }) {
    final state = _requireThread(threadId);
    final now = DateTime.now().toUtc();
    final turnId = expectedTurnId ?? _nextTurnId();
    final item = _newItem(
      type: 'user.message',
      title: expectedTurnId == null ? 'Follow-up prompt' : 'Steer active turn',
      body: message,
      actor: 'user',
      status: 'done',
      createdAt: now,
    );

    _replaceState(
      threadId,
      state.copyWith(
        bundle: _appendItem(
          state.bundle,
          item,
          status: 'active',
          preview: message,
          updatedAt: now,
        ),
        runtime: CodexThreadRuntime(
          threadId: threadId,
          activeTurnId: turnId,
          pendingRequests: state.runtime.pendingRequests,
        ),
        mode: mode ?? state.mode,
        model: model ?? state.model,
        cwd: cwd ?? state.cwd,
      ),
    );

    _publishEvent(threadId: threadId, type: 'turn.started', message: 'Turn started');
    _scheduleContinuation(
      threadId,
      originalMessage: message,
      steering: expectedTurnId != null,
    );
    return _threads[threadId]!.runtime;
  }

  CodexThreadRuntime interruptTurn({
    required String threadId,
    String? turnId,
  }) {
    final state = _requireThread(threadId);
    final activeTurnId = turnId ?? state.runtime.activeTurnId;
    if (activeTurnId == null) {
      return state.runtime;
    }

    final now = DateTime.now().toUtc();
    final item = _newItem(
      type: 'agent.message',
      title: 'Turn interrupted',
      body: 'The active turn was interrupted from the remote client.',
      actor: 'assistant',
      status: 'interrupted',
      createdAt: now,
    );

    _replaceState(
      threadId,
      state.copyWith(
        bundle: _appendItem(
          state.bundle,
          item,
          status: 'idle',
          preview: state.bundle.thread.preview,
          updatedAt: now,
        ),
        runtime: CodexThreadRuntime(
          threadId: threadId,
          pendingRequests: state.runtime.pendingRequests,
        ),
      ),
    );

    _publishEvent(
      threadId: threadId,
      type: 'turn.completed',
      message: 'Turn interrupted',
    );
    return _threads[threadId]!.runtime;
  }

  CodexThreadRuntime respondToPendingRequest({
    required String requestId,
    required String action,
    Map<String, dynamic>? answers,
    Object? content,
  }) {
    final entry = _findPendingRequest(requestId);
    if (entry == null) {
      throw StateError('Pending request $requestId was not found.');
    }

    final threadId = entry.threadId;
    final state = _requireThread(threadId);
    final request = entry.request;
    final remaining = state.runtime.pendingRequests
        .where((item) => item.id != requestId)
        .toList(growable: false);
    final now = DateTime.now().toUtc();

    final outcomeItem = _newItem(
      type: 'agent.message',
      title: _responseTitleForAction(request, action),
      body: _responseBodyForAction(
        request: request,
        action: action,
        answers: answers,
        content: content,
      ),
      actor: 'assistant',
      status: 'done',
      createdAt: now,
    );

    final keepActive = action == 'approve' ||
        action == 'approve_for_session' ||
        action == 'grant_turn' ||
        action == 'grant_session' ||
        action == 'submit' ||
        action == 'accept';

    _replaceState(
      threadId,
      state.copyWith(
        bundle: _appendItem(
          state.bundle,
          outcomeItem,
          status: keepActive ? 'active' : 'idle',
          preview: outcomeItem.body,
          updatedAt: now,
        ),
        runtime: CodexThreadRuntime(
          threadId: threadId,
          activeTurnId: keepActive ? state.runtime.activeTurnId : null,
          pendingRequests: remaining,
        ),
      ),
    );

    _publishEvent(
      threadId: threadId,
      type: 'approval.request.completed',
      message: outcomeItem.title,
    );

    if (keepActive && state.runtime.activeTurnId != null) {
      _scheduleAssistantReply(
        threadId,
        responseText: _resolutionReply(request, action),
      );
    }

    return _threads[threadId]!.runtime;
  }

  void _scheduleContinuation(
    String threadId, {
    required String originalMessage,
    bool steering = false,
  }) {
    final lowered = originalMessage.toLowerCase();
    if (lowered.contains('approval') || lowered.contains('npm')) {
      Timer(const Duration(milliseconds: 700), () {
        _enqueuePendingRequest(
          threadId,
          _commandApprovalRequest(
            threadId: threadId,
            message: lowered.contains('npm')
                ? 'Allow Codex to run `npm test`?'
                : 'Allow a command that touches project configuration?',
            command: lowered.contains('npm') ? 'npm test' : 'npm run verify',
          ),
        );
      });
      return;
    }

    if (lowered.contains('input')) {
      Timer(const Duration(milliseconds: 700), () {
        _enqueuePendingRequest(threadId, _userInputRequest(threadId));
      });
      return;
    }

    if (lowered.contains('mcp')) {
      Timer(const Duration(milliseconds: 700), () {
        _enqueuePendingRequest(threadId, _mcpRequest(threadId));
      });
      return;
    }

    _scheduleAssistantReply(
      threadId,
      responseText: steering
          ? 'Adjusted the active turn with the new steering message.'
          : 'Accepted the prompt and continued the Codex session remotely.',
    );
  }

  void _scheduleAssistantReply(
    String threadId, {
    required String responseText,
  }) {
    Timer(const Duration(milliseconds: 900), () {
      final state = _threads[threadId];
      if (state == null || state.runtime.activeTurnId == null) {
        return;
      }

      final now = DateTime.now().toUtc();
      final item = _newItem(
        type: 'agent.message',
        title: 'Assistant update',
        body: responseText,
        actor: 'assistant',
        status: 'done',
        createdAt: now,
      );

      _replaceState(
        threadId,
        state.copyWith(
          bundle: _appendItem(
            state.bundle,
            item,
            status: 'idle',
            preview: responseText,
            updatedAt: now,
          ),
          runtime: CodexThreadRuntime(
            threadId: threadId,
            pendingRequests: state.runtime.pendingRequests,
          ),
        ),
      );

      _publishEvent(
        threadId: threadId,
        type: 'turn.completed',
        message: 'Turn completed',
      );
      _publishEvent(
        threadId: threadId,
        type: 'agent.message.completed',
        message: responseText,
      );
    });
  }

  void _enqueuePendingRequest(String threadId, CodexPendingRequest request) {
    final state = _requireThread(threadId);
    final now = DateTime.now().toUtc();
    _replaceState(
      threadId,
      state.copyWith(
        bundle: _appendItem(
          state.bundle,
          _newItem(
            type: request.kind,
            title: request.title,
            body: request.message,
            actor: 'system',
            status: 'pending',
            createdAt: now,
          ),
          status: 'active',
          preview: request.message,
          updatedAt: now,
        ),
        runtime: CodexThreadRuntime(
          threadId: threadId,
          activeTurnId: state.runtime.activeTurnId,
          pendingRequests: [request, ...state.runtime.pendingRequests],
        ),
      ),
    );

    _publishEvent(
      threadId: threadId,
      type: request.kind == 'user_input'
          ? 'user.input.request'
          : request.kind == 'mcp_elicitation'
              ? 'mcp.elicitation.request'
              : 'approval.request',
      message: request.message,
    );
  }

  void _replaceState(String threadId, _DemoThreadState state) {
    _threads[threadId] = state;
  }

  _DemoThreadState _requireThread(String threadId) {
    final state = _threads[threadId];
    if (state == null) {
      throw StateError('Thread $threadId was not found.');
    }
    return state;
  }

  _PendingEntry? _findPendingRequest(String requestId) {
    for (final state in _threads.values) {
      for (final request in state.runtime.pendingRequests) {
        if (request.id == requestId) {
          return _PendingEntry(threadId: state.bundle.thread.id, request: request);
        }
      }
    }
    return null;
  }

  BridgeRealtimeEvent _event({
    required String type,
    required String message,
    String? threadId,
  }) {
    final occurredAt = DateTime.now().toUtc();
    return BridgeRealtimeEvent(
      type: type,
      description: message,
      receivedAt: occurredAt,
      raw: {
        ...(threadId == null
            ? const <String, dynamic>{}
            : <String, dynamic>{'threadId': threadId}),
        'type': type,
        'message': message,
        'occurredAt': occurredAt.toIso8601String(),
        'source': 'demo',
      },
    );
  }

  void _publishEvent({
    required String threadId,
    required String type,
    required String message,
  }) {
    _eventsController.add(_event(threadId: threadId, type: type, message: message));
  }

  String _nextTurnId() => 'turn_${_turnCounter++}';

  CodexThreadItem _newItem({
    required String type,
    required String title,
    required String body,
    required String actor,
    required String status,
    required DateTime createdAt,
  }) {
    return CodexThreadItem(
      id: 'item_${_itemCounter++}',
      type: type,
      title: title,
      body: body,
      status: status,
      actor: actor,
      createdAt: createdAt,
    );
  }

  CodexThreadBundle _appendItem(
    CodexThreadBundle bundle,
    CodexThreadItem item, {
    required String status,
    required String preview,
    required DateTime updatedAt,
  }) {
    final items = [...bundle.items, item];
    return CodexThreadBundle(
      thread: CodexThreadSummary(
        id: bundle.thread.id,
        title: bundle.thread.title,
        status: status,
        preview: _previewFromItems(items, fallback: preview),
        createdAt: bundle.thread.createdAt ?? item.createdAt,
        cwd: bundle.thread.cwd,
        updatedAt: updatedAt,
        itemCount: items.length,
        provider: bundle.thread.provider,
      ),
      items: items,
    );
  }

  String _previewFromItems(List<CodexThreadItem> items, {required String fallback}) {
    for (final item in items.reversed) {
      if (item.actor != 'user') {
        continue;
      }
      final preview = _compactPreview(item.body);
      if (preview != null) {
        return preview;
      }
    }
    return _compactPreview(fallback) ?? 'No preview available yet.';
  }

  String? _compactPreview(String? value) {
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

  CodexModelOption _defaultModel() {
    return _models.firstWhere((model) => model.isDefault);
  }

  String _titleFromMessage(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) {
      return 'Untitled session';
    }
    return normalized.length > 42
        ? '${normalized.substring(0, 39)}...'
        : normalized;
  }

  String _responseTitleForAction(CodexPendingRequest request, String action) {
    switch (action) {
      case 'approve':
      case 'approve_for_session':
        return 'Approval granted';
      case 'grant_turn':
      case 'grant_session':
        return 'Permission granted';
      case 'submit':
      case 'accept':
        return request.kind == 'mcp_elicitation'
            ? 'MCP request answered'
            : 'Input submitted';
      case 'deny':
      case 'decline':
        return 'Request denied';
      case 'cancel':
      case 'abort':
        return 'Request cancelled';
      default:
        return 'Request updated';
    }
  }

  String _responseBodyForAction({
    required CodexPendingRequest request,
    required String action,
    Map<String, dynamic>? answers,
    Object? content,
  }) {
    switch (action) {
      case 'approve':
        return 'Approved ${request.title.toLowerCase()} from the remote client.';
      case 'approve_for_session':
        return 'Approved ${request.title.toLowerCase()} for the rest of this session.';
      case 'grant_turn':
        return 'Granted the requested permissions for the current turn.';
      case 'grant_session':
        return 'Granted the requested permissions for the full session.';
      case 'submit':
        return 'Submitted user input: ${answers?.values.join(', ') ?? 'response sent'}';
      case 'accept':
        return content == null
            ? 'Marked the MCP request as completed.'
            : 'Submitted MCP form data from the remote client.';
      case 'deny':
      case 'decline':
        return 'Denied the pending request from the remote client.';
      case 'cancel':
      case 'abort':
        return 'Cancelled the pending request and stopped the turn.';
      default:
        return 'Updated the pending request.';
    }
  }

  String _resolutionReply(CodexPendingRequest request, String action) {
    if (request.kind == 'user_input' && action == 'submit') {
      return 'Used the submitted answers and continued the Codex rollout.';
    }
    if (request.kind == 'mcp_elicitation' && action == 'accept') {
      return 'Accepted the MCP input and resumed the tool-assisted turn.';
    }
    return 'Applied the approval decision and continued the session.';
  }

  List<_DemoThreadState> _buildSeedThreads(DateTime now) {
    final threadOne = _DemoThreadState(
      bundle: CodexThreadBundle(
        thread: CodexThreadSummary(
          id: 'demo-thread-mobile',
          title: 'Remote coding from Windows',
          status: 'idle',
          preview: 'Need to create threads, send prompts, and handle approvals.',
          createdAt: now.subtract(const Duration(minutes: 28)),
          updatedAt: now.subtract(const Duration(minutes: 5)),
          itemCount: 5,
        ),
        items: [
          CodexThreadItem(
            id: 'item_1',
            type: 'user.message',
            title: 'Make the desktop client controllable',
            body: 'Need to create threads, send prompts, and handle approvals.',
            status: 'done',
            actor: 'user',
            createdAt: now.subtract(const Duration(minutes: 28)),
          ),
          CodexThreadItem(
            id: 'item_2',
            type: 'agent.message',
            title: 'Control gap identified',
            body: 'The mobile client only exposed read-only thread browsing.',
            status: 'done',
            actor: 'assistant',
            createdAt: now.subtract(const Duration(minutes: 24)),
          ),
          CodexThreadItem(
            id: 'item_3',
            type: 'file.change',
            title: 'Extended app-server control flow',
            body: 'Added create, send, and respond flows for remote operation.',
            status: 'done',
            actor: 'assistant',
            createdAt: now.subtract(const Duration(minutes: 16)),
          ),
          CodexThreadItem(
            id: 'item_4',
            type: 'command.execution',
            title: 'Verified direct app-server build',
            body: 'npm test passed after the new control endpoints were wired.',
            status: 'done',
            actor: 'assistant',
            createdAt: now.subtract(const Duration(minutes: 12)),
          ),
          CodexThreadItem(
            id: 'item_5',
            type: 'agent.message',
            title: 'Ready for live prompts',
            body: 'The composer can now drive turns instead of only reading them.',
            status: 'done',
            actor: 'assistant',
            createdAt: now.subtract(const Duration(minutes: 5)),
          ),
        ],
      ),
      runtime: const CodexThreadRuntime(
        threadId: 'demo-thread-mobile',
        pendingRequests: [],
      ),
      mode: CodexComposerMode.agent,
      model: 'gpt-5.4',
      cwd: r'E:\workspace\codex-control',
    );

    final pendingApproval = CodexPendingRequest(
      id: 'pending_1',
      kind: 'command_approval',
      title: 'Command Approval',
      message: 'Allow Codex to run `npm run verify` before applying the patch?',
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
      receivedAt: now.subtract(const Duration(minutes: 9)),
      threadId: 'demo-thread-direct',
      turnId: 'turn_11',
      itemId: 'item_pending',
      detail: 'Reason: verify the workspace before applying a larger refactor.',
      command: 'npm run verify',
      cwd: r'E:\workspace\codex-control',
    );

    final threadTwo = _DemoThreadState(
      bundle: CodexThreadBundle(
        thread: CodexThreadSummary(
          id: 'demo-thread-direct',
          title: 'Approval-driven rollout',
          status: 'active',
          preview: 'Add create/send/respond endpoints and surface approvals.',
          createdAt: now.subtract(const Duration(minutes: 25)),
          updatedAt: now.subtract(const Duration(minutes: 9)),
          itemCount: 4,
        ),
        items: [
          CodexThreadItem(
            id: 'item_6',
            type: 'user.message',
            title: 'Refactor the client for direct app-server control',
            body: 'Add create/send/respond endpoints and surface approvals.',
            status: 'done',
            actor: 'user',
            createdAt: now.subtract(const Duration(minutes: 25)),
          ),
          CodexThreadItem(
            id: 'item_7',
            type: 'agent.message',
            title: 'Started rollout',
            body: 'Preparing direct write-side app-server calls for the remote client.',
            status: 'done',
            actor: 'assistant',
            createdAt: now.subtract(const Duration(minutes: 22)),
          ),
          CodexThreadItem(
            id: 'item_8',
            type: 'approval.request',
            title: 'Command approval requested',
            body: pendingApproval.message,
            status: 'pending',
            actor: 'system',
            createdAt: now.subtract(const Duration(minutes: 9)),
          ),
          CodexThreadItem(
            id: 'item_9',
            type: 'agent.message',
            title: 'Waiting for approval',
            body: 'The session is paused until the remote reviewer responds.',
            status: 'pending',
            actor: 'assistant',
            createdAt: now.subtract(const Duration(minutes: 9)),
          ),
        ],
      ),
      runtime: CodexThreadRuntime(
        threadId: 'demo-thread-direct',
        activeTurnId: 'turn_11',
        pendingRequests: [pendingApproval],
      ),
      mode: CodexComposerMode.agent,
      model: 'gpt-5.4',
      cwd: r'E:\workspace\codex-control',
    );

    return [threadOne, threadTwo];
  }

  CodexPendingRequest _commandApprovalRequest({
    required String threadId,
    required String message,
    required String command,
  }) {
    return CodexPendingRequest(
      id: 'pending_${_requestCounter++}',
      kind: 'command_approval',
      title: 'Command Approval',
      message: message,
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
      receivedAt: DateTime.now().toUtc(),
      threadId: threadId,
      turnId: _threads[threadId]?.runtime.activeTurnId,
      command: command,
      cwd: _threads[threadId]?.cwd,
    );
  }

  CodexPendingRequest _userInputRequest(String threadId) {
    return CodexPendingRequest(
      id: 'pending_${_requestCounter++}',
      kind: 'user_input',
      title: 'User Input Required',
      message: 'Codex needs a direction before it can continue.',
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
      questions: const [
        CodexPendingQuestion(
          id: 'execution_mode',
          label: 'Mode',
          prompt: 'Which rollout path should Codex take next?',
          allowFreeform: true,
          multiSelect: false,
          options: [
            CodexPendingOption(
              id: 'minimal',
              label: 'Minimal patch',
              description: 'Prefer the smallest safe change set.',
              recommended: true,
            ),
            CodexPendingOption(
              id: 'full',
              label: 'Full implementation',
              description: 'Carry the feature through end-to-end now.',
              recommended: false,
            ),
          ],
        ),
      ],
      formFields: const [],
      receivedAt: DateTime.now().toUtc(),
      threadId: threadId,
      turnId: _threads[threadId]?.runtime.activeTurnId,
    );
  }

  CodexPendingRequest _mcpRequest(String threadId) {
    return CodexPendingRequest(
      id: 'pending_${_requestCounter++}',
      kind: 'mcp_elicitation',
      title: 'MCP Input Request',
      message: 'An MCP helper needs deployment details.',
      actions: const [
        CodexPendingAction(
          id: 'accept',
          label: 'Submit',
          recommended: true,
          destructive: false,
        ),
        CodexPendingAction(
          id: 'decline',
          label: 'Decline',
          recommended: false,
          destructive: true,
        ),
        CodexPendingAction(
          id: 'cancel',
          label: 'Cancel',
          recommended: false,
          destructive: true,
        ),
      ],
      questions: const [],
      formFields: const [
        CodexPendingFormField(
          id: 'environment',
          label: 'Environment',
          type: CodexPendingFieldType.singleSelect,
          required: true,
          options: [
            CodexPendingOption(
              id: 'staging',
              label: 'Staging',
              recommended: true,
            ),
            CodexPendingOption(
              id: 'production',
              label: 'Production',
              recommended: false,
            ),
          ],
        ),
        CodexPendingFormField(
          id: 'dry_run',
          label: 'Dry run first',
          type: CodexPendingFieldType.boolean,
          required: false,
          options: [],
          defaultValue: true,
        ),
      ],
      receivedAt: DateTime.now().toUtc(),
      threadId: threadId,
      turnId: _threads[threadId]?.runtime.activeTurnId,
    );
  }
}

class _DemoThreadState {
  const _DemoThreadState({
    required this.bundle,
    required this.runtime,
    required this.mode,
    required this.model,
    this.cwd,
  });

  final CodexThreadBundle bundle;
  final CodexThreadRuntime runtime;
  final CodexComposerMode mode;
  final String model;
  final String? cwd;

  _DemoThreadState copyWith({
    CodexThreadBundle? bundle,
    CodexThreadRuntime? runtime,
    CodexComposerMode? mode,
    String? model,
    String? cwd,
  }) {
    return _DemoThreadState(
      bundle: bundle ?? this.bundle,
      runtime: runtime ?? this.runtime,
      mode: mode ?? this.mode,
      model: model ?? this.model,
      cwd: cwd ?? this.cwd,
    );
  }
}

class _PendingEntry {
  const _PendingEntry({required this.threadId, required this.request});

  final String threadId;
  final CodexPendingRequest request;
}

String? _readThreadId(Map<String, dynamic> raw) {
  final value = raw['threadId'];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return null;
}
