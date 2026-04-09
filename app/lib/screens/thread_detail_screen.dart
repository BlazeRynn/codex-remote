import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../app/app_strings.dart';
import '../app/app_typography.dart';
import '../app/workspace_theme.dart';
import '../models/bridge_config.dart';
import '../models/codex_composer_mode.dart';
import '../models/codex_input_part.dart';
import '../models/codex_model_option.dart';
import '../models/codex_pending_request.dart';
import '../models/codex_thread_bundle.dart';
import '../models/codex_thread_item.dart';
import '../models/codex_thread_runtime.dart';
import '../models/codex_thread_summary.dart';
import '../services/bridge_realtime_client.dart';
import '../services/composer_attachment_bridge.dart';
import '../services/codex_repository.dart';
import '../services/realtime_event_helpers.dart';
import '../services/realtime_event_buffer.dart';
import '../services/thread_state_projection.dart';
import '../services/thread_message_list_projection.dart';
import '../services/thread_realtime_accumulator.dart';
import '../services/ui_debug_logger.dart';
import '../utils/json_utils.dart';
import '../widgets/thread_message_list.dart';

class ThreadDetailScreen extends StatefulWidget {
  const ThreadDetailScreen({
    super.key,
    required this.config,
    required this.thread,
    this.selectedThreadId,
    this.activeThreadId,
  });

  final BridgeConfig config;
  final CodexThreadSummary thread;
  final String? selectedThreadId;
  final String? activeThreadId;

  @override
  State<ThreadDetailScreen> createState() => _ThreadDetailScreenState();
}

class _ThreadDetailScreenState extends State<ThreadDetailScreen> {
  final GlobalKey<_ThreadDetailPaneState> _paneKey =
      GlobalKey<_ThreadDetailPaneState>();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.thread.title),
        actions: [
          IconButton(
            onPressed: () {
              unawaited(_paneKey.currentState?.refresh() ?? Future.value());
            },
            tooltip: strings.text('Refresh', 'Refresh'),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: ThreadDetailPane(
        key: _paneKey,
        config: widget.config,
        thread: widget.thread,
        selectedThreadId: widget.selectedThreadId ?? widget.thread.id,
        activeThreadId: widget.activeThreadId,
      ),
    );
  }
}

class ThreadDetailPane extends StatefulWidget {
  const ThreadDetailPane({
    super.key,
    required this.config,
    required this.thread,
    this.selectedThreadId,
    this.activeThreadId,
    this.workspaceStyle = false,
  });

  final BridgeConfig config;
  final CodexThreadSummary thread;
  final String? selectedThreadId;
  final String? activeThreadId;
  final bool workspaceStyle;

  @override
  State<ThreadDetailPane> createState() => _ThreadDetailPaneState();
}

class _ThreadDetailPaneState extends State<ThreadDetailPane>
    with AutomaticKeepAliveClientMixin<ThreadDetailPane> {
  static final Map<String, CodexThreadBundle> _bundleCache = {};
  static final Map<String, CodexThreadRuntime> _runtimeCache = {};
  static final Map<String, double> _timelineOffsetCache = {};
  static final Map<String, bool> _followConversationCache = {};

  late final CodexRepository _repository;
  late final TextEditingController _composerController;
  late final ScrollController _timelineScrollController;
  late final ThreadRealtimeAccumulator _realtimeAccumulator;
  late CodexThreadBundle _bundle;
  late CodexThreadRuntime _runtime;
  final List<BridgeRealtimeEvent> _liveEvents = [];

  bool _loading = true;
  bool _runtimeLoading = true;
  bool _modelsLoading = true;
  bool _submitting = false;
  bool _responding = false;
  String? _error;
  String? _controlError;
  LiveConnectionState _liveConnectionState = LiveConnectionState.disconnected;
  String? _liveError;
  List<CodexModelOption> _models = const [];
  List<CodexInputPart> _composerAttachments = const [];
  CodexComposerMode _selectedMode = CodexComposerMode.agent;
  String? _selectedModelId;

  CodexRealtimeSession? _realtimeSession;
  StreamSubscription<BridgeRealtimeEvent>? _realtimeSubscription;
  Timer? _refreshDebounce;
  Timer? _reattachProbeTimer;
  bool _bundleRequestInFlight = false;
  bool _runtimeRequestInFlight = false;
  bool _pendingRequestsExpanded = false;
  bool _followConversation = true;
  bool _realtimeAttachPending = false;
  bool _programmaticScrollInProgress = false;
  bool _userScrollInProgress = false;
  bool _scrollToBottomScheduled = false;
  bool _scrollToBottomQueued = false;
  bool _queuedScrollToBottomAnimated = false;
  bool _queuedScrollToBottomForce = false;
  int _scrollToBottomRequestId = 0;

  @override
  bool get wantKeepAlive => true;

  Future<void> refresh() => _reloadAll();

  @override
  void initState() {
    super.initState();
    _repository = createCodexRepository(widget.config);
    _composerController = TextEditingController();
    _followConversation =
        _followConversationCache[widget.thread.id] ?? _followConversation;
    _timelineScrollController = ScrollController(
      initialScrollOffset: _initialTimelineOffsetForThread(widget.thread.id),
    )..addListener(_handleTimelineScroll);
    _realtimeAccumulator = ThreadRealtimeAccumulator(
      threadId: widget.thread.id,
    );
    _bundle = CodexThreadBundle(thread: widget.thread, items: const []);
    _runtime = CodexThreadRuntime(
      threadId: widget.thread.id,
      pendingRequests: const [],
    );
    _primeFromCache();
    if (_isSelectedThread) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _activateFollowConversationAndScroll();
      });
    }
    _debugLog('init', fields: {'initialStatus': _bundle.thread.status});
    unawaited(
      _reloadAll(
        showBundleSpinner: _bundle.items.isEmpty,
        loadBundle: !_shouldSkipInitialBundleReload(),
        quietRuntime: _runtimeCache.containsKey(widget.thread.id),
      ),
    );
    _openRealtime();
  }

  @override
  void didUpdateWidget(covariant ThreadDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasSelected = _matchesSelectedThread(
      selectedThreadId: oldWidget.selectedThreadId,
      threadId: oldWidget.thread.id,
    );
    final isSelected = _isSelectedThread;
    if (!wasSelected && isSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _activateFollowConversationAndScroll();
      });
    }
    if (oldWidget.thread.id != widget.thread.id) {
      return;
    }

    final nextThread = widget.thread;
    final currentThread = _bundle.thread;
    final changed =
        currentThread.status != nextThread.status ||
        currentThread.title != nextThread.title ||
        currentThread.preview != nextThread.preview ||
        currentThread.createdAt != nextThread.createdAt ||
        currentThread.cwd != nextThread.cwd ||
        currentThread.provider != nextThread.provider ||
        currentThread.updatedAt != nextThread.updatedAt ||
        currentThread.itemCount != nextThread.itemCount;
    if (!changed) {
      return;
    }

    setState(() {
      _bundle = CodexThreadBundle(thread: nextThread, items: _bundle.items);
    });
    _maybeProbeRealtimeAttach();
  }

  bool get _isSelectedThread => _matchesSelectedThread(
    selectedThreadId: widget.selectedThreadId,
    threadId: widget.thread.id,
  );

  bool _matchesSelectedThread({
    required String? selectedThreadId,
    required String threadId,
  }) {
    final effectiveSelectedThreadId = selectedThreadId ?? threadId;
    return effectiveSelectedThreadId == threadId;
  }

  void _activateFollowConversationAndScroll() {
    _timelineOffsetCache.remove(widget.thread.id);
    if (_followConversation) {
      _scrollConversationToBottom(animated: false, force: true);
      return;
    }
    setState(() {
      _followConversation = true;
    });
    _scrollConversationToBottom(animated: false, force: true);
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _reattachProbeTimer?.cancel();
    _storeTimelineScrollState();
    _composerController.dispose();
    _timelineScrollController
      ..removeListener(_handleTimelineScroll)
      ..dispose();
    unawaited(_closeRealtime());
    super.dispose();
  }

  Future<void> _reloadAll({
    bool showBundleSpinner = true,
    bool loadBundle = true,
    bool quietRuntime = false,
  }) async {
    final futures = <Future<void>>[
      if (loadBundle) _loadBundle(showSpinner: showBundleSpinner),
      _loadRuntime(quiet: quietRuntime),
      _loadModels(),
    ];
    await Future.wait(futures);
  }

  void _primeFromCache() {
    final cachedBundle = _bundleCache[widget.thread.id];
    final hasCachedTimelineOffset = _timelineOffsetCache.containsKey(
      widget.thread.id,
    );
    if (cachedBundle != null) {
      _bundle = CodexThreadBundle(
        thread: _mergeThreadSummary(widget.thread, cachedBundle.thread),
        items: cachedBundle.items,
      );
      _realtimeAccumulator.replaceSnapshot(cachedBundle.items);
      _loading = false;
      if (cachedBundle.items.isNotEmpty &&
          !hasCachedTimelineOffset &&
          _followConversation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollConversationToBottom(animated: false, force: true);
        });
      }
    }

    final cachedRuntime = _runtimeCache[widget.thread.id];
    if (cachedRuntime != null) {
      _runtime = cachedRuntime;
      _runtimeLoading = false;
    }
  }

  bool _shouldSkipInitialBundleReload() {
    final cachedBundle = _bundleCache[widget.thread.id];
    if (cachedBundle == null || cachedBundle.items.isEmpty) {
      return false;
    }
    if (widget.thread.status == 'active' ||
        cachedBundle.thread.status == 'active') {
      return false;
    }
    return _sameThreadSummarySnapshot(cachedBundle.thread, widget.thread);
  }

  CodexThreadSummary _mergeThreadSummary(
    CodexThreadSummary preferred,
    CodexThreadSummary fallback,
  ) {
    return preferred.copyWith(
      status: preferred.status,
      title: preferred.title,
      preview: preferred.preview,
      createdAt: preferred.createdAt ?? fallback.createdAt,
      cwd: preferred.cwd ?? fallback.cwd,
      updatedAt: _laterTimestamp(preferred.updatedAt, fallback.updatedAt),
      itemCount: preferred.itemCount ?? fallback.itemCount,
      provider: preferred.provider ?? fallback.provider,
    );
  }

  bool _sameThreadSummarySnapshot(
    CodexThreadSummary left,
    CodexThreadSummary right,
  ) {
    return left.id == right.id &&
        left.title == right.title &&
        left.status == right.status &&
        left.preview == right.preview &&
        _sameTimestamp(left.createdAt, right.createdAt) &&
        left.cwd == right.cwd &&
        left.itemCount == right.itemCount &&
        left.provider == right.provider &&
        _sameTimestamp(left.updatedAt, right.updatedAt);
  }

  void _storeBundleCache(CodexThreadBundle bundle) {
    _bundleCache[bundle.thread.id] = CodexThreadBundle(
      thread: bundle.thread,
      items: List.unmodifiable(bundle.items),
    );
    _pruneThreadCaches();
  }

  void _storeRuntimeCache(CodexThreadRuntime runtime) {
    _runtimeCache[runtime.threadId] = CodexThreadRuntime(
      threadId: runtime.threadId,
      activeTurnId: runtime.activeTurnId,
      pendingRequests: List.unmodifiable(runtime.pendingRequests),
    );
    _pruneThreadCaches();
  }

  void _storeCurrentThreadState({List<CodexThreadItem>? items}) {
    _storeBundleCache(
      CodexThreadBundle(
        thread: _bundle.thread,
        items: items ?? _realtimeAccumulator.items,
      ),
    );
    _storeRuntimeCache(_runtime);
  }

  void _pruneThreadCaches() {
    while (_bundleCache.length > 24) {
      _bundleCache.remove(_bundleCache.keys.first);
    }
    while (_runtimeCache.length > 24) {
      _runtimeCache.remove(_runtimeCache.keys.first);
    }
    while (_timelineOffsetCache.length > 24) {
      final threadId = _timelineOffsetCache.keys.first;
      _timelineOffsetCache.remove(threadId);
      _followConversationCache.remove(threadId);
    }
  }

  double _initialTimelineOffsetForThread(String threadId) {
    final cachedOffset = _timelineOffsetCache[threadId];
    if (cachedOffset == null || !cachedOffset.isFinite || cachedOffset < 0) {
      return 0;
    }
    return cachedOffset;
  }

  void _storeTimelineScrollState() {
    _followConversationCache[widget.thread.id] = _followConversation;
    if (!_timelineScrollController.hasClients) {
      return;
    }

    final position = _timelineScrollController.position;
    final pixels = position.pixels;
    if (!pixels.isFinite || pixels < 0) {
      return;
    }
    _timelineOffsetCache[widget.thread.id] = pixels;
  }

  Future<void> _loadBundle({
    bool showSpinner = true,
    bool forceScrollToBottom = false,
  }) async {
    if (_bundleRequestInFlight) {
      return;
    }

    _bundleRequestInFlight = true;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final previousBundle = _bundle;
      final previousConversationItems = _realtimeAccumulator.items;
      final previousProjection = projectThreadMessageList(
        previousConversationItems,
      );
      final bundle = await _repository.getThreadBundle(widget.thread.id);
      if (!mounted) {
        return;
      }

      final mergedThread =
          _bundle.thread.status == 'active' && bundle.thread.status != 'active'
          ? bundle.thread.copyWith(
              status: 'active',
              updatedAt: _laterTimestamp(
                bundle.thread.updatedAt,
                _bundle.thread.updatedAt,
              ),
            )
          : bundle.thread;

      _realtimeAccumulator.replaceSnapshot(bundle.items);
      final nextConversationItems = _realtimeAccumulator.items;
      final nextProjection = projectThreadMessageList(nextConversationItems);
      setState(() {
        _bundle = CodexThreadBundle(thread: mergedThread, items: bundle.items);
        _loading = false;
      });
      _storeBundleCache(
        CodexThreadBundle(thread: mergedThread, items: nextConversationItems),
      );
      _debugLog(
        'bundle.loaded',
        fields: {
          'status': _bundle.thread.status,
          'itemCount': bundle.items.length,
        },
      );
      _maybeProbeRealtimeAttach();
      _maybeScrollConversationToBottom(
        previousProjection: previousProjection,
        nextProjection: nextProjection,
        force:
            forceScrollToBottom ||
            (previousBundle.items.isEmpty && nextConversationItems.isNotEmpty),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        if (showSpinner) {
          _error = error.toString();
        }
      });
    } finally {
      _bundleRequestInFlight = false;
    }
  }

  void _handleTimelineScroll() {
    if (!_timelineScrollController.hasClients) {
      return;
    }
    if (_programmaticScrollInProgress) {
      return;
    }
    if (_userScrollInProgress) {
      if (!_followConversation && _isAtConversationBottom()) {
        _setFollowConversation(true);
      }
      return;
    }
    final nextFollowConversation = _isNearConversationBottom();
    _setFollowConversation(nextFollowConversation);
  }

  bool _handleTimelineScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        _setFollowConversation(false);
      } else if (notification.direction == ScrollDirection.idle &&
          _isAtConversationBottom()) {
        _setFollowConversation(true);
      }
      _updateUserScrollState(
        active: notification.direction != ScrollDirection.idle,
      );
      return false;
    }

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _updateUserScrollState(active: true);
      return false;
    }

    if (notification is ScrollEndNotification) {
      _updateUserScrollState(active: false);
    }
    return false;
  }

  void _updateUserScrollState({required bool active}) {
    if (_userScrollInProgress == active) {
      return;
    }
    _userScrollInProgress = active;
    if (active) {
      _scrollToBottomRequestId += 1;
      _scrollToBottomQueued = false;
      _queuedScrollToBottomAnimated = false;
      _queuedScrollToBottomForce = false;
      _programmaticScrollInProgress = false;
      return;
    }
    if (_followConversation) {
      _scrollConversationToBottom(animated: false, force: true);
    }
  }

  bool _isNearConversationBottom() {
    if (!_timelineScrollController.hasClients) {
      return true;
    }
    final position = _timelineScrollController.position;
    return (position.maxScrollExtent - position.pixels) <= 24;
  }

  bool _isAtConversationBottom() {
    if (!_timelineScrollController.hasClients) {
      return true;
    }
    final position = _timelineScrollController.position;
    return (position.maxScrollExtent - position.pixels) <= 1;
  }

  void _setFollowConversation(bool next) {
    if (_followConversation == next || !mounted) {
      _followConversation = next;
      return;
    }
    setState(() {
      _followConversation = next;
    });
  }

  void _maybeScrollConversationToBottom({
    required ThreadMessageListProjection previousProjection,
    required ThreadMessageListProjection nextProjection,
    bool force = false,
  }) {
    final changed =
        previousProjection.tailSignature != nextProjection.tailSignature;
    if (!force && (!changed || !_followConversation || _userScrollInProgress)) {
      return;
    }
    _scrollConversationToBottom(animated: false, force: force);
  }

  void _scrollConversationToBottom({bool animated = true, bool force = false}) {
    if (!force && (_userScrollInProgress || !_followConversation)) {
      return;
    }
    if (_programmaticScrollInProgress || _scrollToBottomScheduled) {
      _scrollToBottomQueued = true;
      _queuedScrollToBottomAnimated = _queuedScrollToBottomAnimated || animated;
      _queuedScrollToBottomForce = _queuedScrollToBottomForce || force;
      return;
    }
    _scheduleScrollToBottom(animated: animated, force: force);
  }

  void _scheduleScrollToBottom({required bool animated, required bool force}) {
    if (_scrollToBottomScheduled) {
      return;
    }
    final requestId = ++_scrollToBottomRequestId;
    _scrollToBottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomScheduled = false;
      unawaited(
        _runScheduledScrollToBottom(
          requestId: requestId,
          animated: animated,
          force: force,
        ),
      );
    });
  }

  Future<void> _runScheduledScrollToBottom({
    required int requestId,
    required bool animated,
    required bool force,
  }) async {
    await _settleConversationScrollToBottom(
      requestId: requestId,
      animated: animated,
      force: force,
    );

    if (!mounted || _userScrollInProgress || !_scrollToBottomQueued) {
      return;
    }

    final queuedAnimated = _queuedScrollToBottomAnimated;
    final queuedForce = _queuedScrollToBottomForce;
    _scrollToBottomQueued = false;
    _queuedScrollToBottomAnimated = false;
    _queuedScrollToBottomForce = false;
    _scheduleScrollToBottom(animated: queuedAnimated, force: queuedForce);
  }

  Future<void> _settleConversationScrollToBottom({
    required int requestId,
    required bool animated,
    required bool force,
  }) async {
    if (!mounted || !_timelineScrollController.hasClients) {
      return;
    }

    if (_userScrollInProgress && !force) {
      return;
    }

    if (!_followConversation) {
      setState(() {
        _followConversation = true;
      });
    } else {
      _followConversation = true;
    }

    _programmaticScrollInProgress = true;
    try {
      var previousExtent = -1.0;
      var stablePasses = 0;
      for (var attempt = 0; attempt < 10; attempt += 1) {
        if (!mounted ||
            !_timelineScrollController.hasClients ||
            (_userScrollInProgress && !force) ||
            requestId != _scrollToBottomRequestId) {
          return;
        }

        final position = _timelineScrollController.position;
        final target = position.maxScrollExtent < position.minScrollExtent
            ? position.minScrollExtent
            : position.maxScrollExtent;
        final delta = target - position.pixels;
        if (delta.abs() > 0.5) {
          if (animated && attempt == 0 && delta.abs() > 24) {
            await _timelineScrollController.animateTo(
              target,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          } else {
            _timelineScrollController.jumpTo(target);
          }
        }

        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (!mounted ||
            !_timelineScrollController.hasClients ||
            (_userScrollInProgress && !force) ||
            requestId != _scrollToBottomRequestId) {
          return;
        }

        final settledPosition = _timelineScrollController.position;
        final settledExtent = settledPosition.maxScrollExtent;
        final remaining = settledExtent - settledPosition.pixels;
        final extentStable = (settledExtent - previousExtent).abs() <= 0.5;
        if (remaining.abs() <= 0.5 && extentStable) {
          stablePasses += 1;
          if (stablePasses >= 2) {
            return;
          }
        } else {
          stablePasses = 0;
        }
        if (attempt == 9 && remaining.abs() > 0.5) {
          _timelineScrollController.jumpTo(settledExtent);
          return;
        }
        previousExtent = settledExtent;
      }
    } finally {
      if (requestId == _scrollToBottomRequestId) {
        _programmaticScrollInProgress = false;
      }
    }
  }

  void _applyRealtimeThreadState(BridgeRealtimeEvent event) {
    final projectedThread = projectRealtimeStatusOnThread(
      _bundle.thread,
      event,
    );
    if (!identical(projectedThread, _bundle.thread)) {
      _bundle = CodexThreadBundle(
        thread: projectedThread,
        items: _bundle.items,
      );
    }

    _runtime = projectRealtimeStatusOnRuntime(_runtime, event);
  }

  Future<void> _loadRuntime({bool quiet = false}) async {
    if (_runtimeRequestInFlight) {
      return;
    }

    _runtimeRequestInFlight = true;
    if (!quiet) {
      setState(() {
        _runtimeLoading = true;
      });
    }

    try {
      final runtime = await _repository.getThreadRuntime(widget.thread.id);
      if (!mounted) {
        return;
      }

      final mergedRuntime =
          _runtime.activeTurnId != null && runtime.activeTurnId == null
          ? runtime.copyWith(activeTurnId: _runtime.activeTurnId)
          : runtime;

      setState(() {
        _runtime = mergedRuntime;
        _runtimeLoading = false;
      });
      _storeRuntimeCache(mergedRuntime);
      _debugLog(
        'runtime.loaded',
        fields: {
          'activeTurnId': _runtime.activeTurnId,
          'pendingRequestCount': _runtime.pendingRequests.length,
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _runtimeLoading = false;
        if (!quiet) {
          _controlError = error.toString();
        }
      });
    } finally {
      _runtimeRequestInFlight = false;
    }
  }

  Future<void> _loadModels() async {
    setState(() {
      _modelsLoading = true;
    });

    try {
      final models = await _repository.listModels();
      if (!mounted) {
        return;
      }

      final selected = _selectedModelId;
      setState(() {
        _models = models;
        _selectedModelId = _resolveSelectedModelId(
          models,
          preferredId: selected,
        );
        _modelsLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _modelsLoading = false;
      });
    }
  }

  void _openRealtime() {
    if (!widget.config.isConfigured) {
      return;
    }

    setState(() {
      _liveConnectionState = LiveConnectionState.connecting;
      _liveError = null;
    });
    _debugLog('realtime.open');

    try {
      final session = _repository.openThreadEvents(threadId: widget.thread.id);
      _realtimeSession = session;
      _realtimeSubscription = session.stream.listen(
        (event) {
          if (!_matchesThread(event)) {
            return;
          }

          if (!mounted) {
            return;
          }

          _refreshDebounce?.cancel();
          _refreshDebounce = null;

          final previousConversationItems = _realtimeAccumulator.items;
          final previousProjection = projectThreadMessageList(
            previousConversationItems,
          );
          final previousTail = previousProjection.tailItem;
          final conversationChanged = _realtimeAccumulator.apply(event);
          final nextConversationItems = conversationChanged
              ? _realtimeAccumulator.items
              : previousConversationItems;
          final nextProjection = projectThreadMessageList(
            nextConversationItems,
          );
          final tail = nextProjection.tailItem;
          setState(() {
            _liveConnectionState = LiveConnectionState.connected;
            _applyRealtimeSessionState(event);
            _applyRealtimeThreadState(event);
            insertRealtimeEvent(_liveEvents, event);
          });
          _storeCurrentThreadState(items: nextConversationItems);
          _debugLog(
            'realtime.event',
            fields: {
              'eventType': event.type,
              'method': realtimeEventMethod(event),
              'turnId': realtimeEventTurnId(event),
              'itemId': realtimeEventItemId(event),
              'delta': realtimeEventDeltaText(event),
              'conversationChanged': conversationChanged,
              'tailItemId': tail?.id,
              'tailTurnId': tail?.raw['turnId'],
              'tailBodyLength': tail?.body.length,
              'activeTurnId': _runtime.activeTurnId,
            },
          );
          if (_isStreamingEventType(event)) {
            _debugLog(
              'state.delta',
              fields: {
                'turnId': realtimeEventTurnId(event),
                'itemId': realtimeEventItemId(event),
                'tailBodyLength.before': previousTail?.body.length ?? 0,
                'tailBodyLength.after': tail?.body.length ?? 0,
              },
            );
          }
          _maybeScrollConversationToBottom(
            previousProjection: previousProjection,
            nextProjection: nextProjection,
          );
          _scheduleFollowUpRefresh(event);
        },
        onError: (Object error) {
          if (!mounted) {
            return;
          }

          setState(() {
            _liveConnectionState = LiveConnectionState.failed;
            _liveError = error.toString();
          });
          _debugLog('realtime.error', fields: {'error': error});
        },
        onDone: () {
          if (!mounted) {
            return;
          }

          setState(() {
            if (_liveConnectionState != LiveConnectionState.failed) {
              _liveConnectionState = LiveConnectionState.disconnected;
            }
          });
          _debugLog('realtime.closed');
        },
      );

      setState(() {
        _liveConnectionState = LiveConnectionState.connected;
      });
      _debugLog('realtime.connected');
    } catch (error) {
      setState(() {
        _liveConnectionState = LiveConnectionState.failed;
        _liveError = error.toString();
      });
      _debugLog('realtime.open_failed', fields: {'error': error});
    }
  }

  Future<void> _closeRealtime() async {
    _stopReattachProbe();
    await _realtimeSubscription?.cancel();
    await _realtimeSession?.close();
    _realtimeSubscription = null;
    _realtimeSession = null;
  }

  Future<void> _reconnectRealtime() async {
    _debugLog('realtime.reconnect');
    await _closeRealtime();
    if (!mounted) {
      return;
    }
    _openRealtime();
  }

  void _applyRealtimeSessionState(BridgeRealtimeEvent event) {
    switch (event.type) {
      case 'app_server.attach.skipped':
        _realtimeAttachPending = true;
        _startReattachProbe();
        _debugLog('realtime.attach_skipped');
        return;
      case 'thread.status':
        if (_realtimeAttachPending &&
            realtimeEventThreadStatusType(event) == 'active') {
          _realtimeAttachPending = false;
          _stopReattachProbe();
          _debugLog('realtime.reconnect_on_active');
          unawaited(_reconnectRealtime());
          return;
        }
        return;
      case 'app_server.attached':
      case 'turn.started':
      case 'agent.message.delta':
      case 'thread.realtime.started':
      case 'thread.realtime.item.added':
      case 'thread.realtime.transcript.updated':
        _realtimeAttachPending = false;
        _stopReattachProbe();
        _debugLog('realtime.attached');
        return;
      default:
        return;
    }
  }

  bool _matchesThread(BridgeRealtimeEvent event) {
    final eventThreadId =
        realtimeEventThreadId(event) ??
        readString(event.raw, const ['threadId', 'thread_id']);
    return eventThreadId.isEmpty || eventThreadId == widget.thread.id;
  }

  String? _resolveSelectedModelId(
    List<CodexModelOption> models, {
    String? preferredId,
  }) {
    if (models.isEmpty) {
      return null;
    }
    if (preferredId != null && models.any((model) => model.id == preferredId)) {
      return preferredId;
    }
    for (final model in models) {
      if (model.isDefault) {
        return model.id;
      }
    }
    return models.first.id;
  }

  void _scheduleFollowUpRefresh(BridgeRealtimeEvent event) {
    final reloadBundle = _shouldReloadBundle(event);
    final reloadRuntime = _shouldReloadRuntime(event);
    if (!reloadBundle && !reloadRuntime) {
      return;
    }

    _refreshDebounce?.cancel();
    final delay = _isStreamingEventType(event)
        ? const Duration(milliseconds: 140)
        : const Duration(milliseconds: 450);
    _refreshDebounce = Timer(delay, () {
      if (reloadBundle) {
        unawaited(_loadBundle(showSpinner: false));
      }
      if (reloadRuntime) {
        unawaited(_loadRuntime(quiet: true));
      }
    });
  }

  void _maybeProbeRealtimeAttach() {
    if (!_realtimeAttachPending) {
      return;
    }
    if (_bundle.thread.status == 'active') {
      unawaited(_reconnectRealtime());
      return;
    }
    _startReattachProbe();
  }

  void _startReattachProbe() {
    if (_reattachProbeTimer != null) {
      return;
    }
    _reattachProbeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_realtimeAttachPending) {
        _stopReattachProbe();
        return;
      }
      unawaited(_probeRealtimeAttach());
    });
  }

  void _stopReattachProbe() {
    _reattachProbeTimer?.cancel();
    _reattachProbeTimer = null;
  }

  Future<void> _probeRealtimeAttach() async {
    try {
      final threads = await _repository.listThreads();
      if (!mounted) {
        return;
      }

      for (final thread in threads) {
        if (thread.id != widget.thread.id) {
          continue;
        }

        setState(() {
          _bundle = CodexThreadBundle(thread: thread, items: _bundle.items);
        });
        _debugLog(
          'realtime.probe',
          fields: {
            'probedStatus': thread.status,
            'selectedThreadId': widget.thread.id,
          },
        );
        if (thread.status == 'active') {
          await _reconnectRealtime();
        }
        return;
      }
    } catch (_) {}
  }

  bool _shouldReloadBundle(BridgeRealtimeEvent event) {
    final method = realtimeEventMethod(event) ?? '';
    final type = event.type;
    if (method == 'item/agentMessage/delta' ||
        method == 'item/plan/delta' ||
        method == 'item/commandExecution/outputDelta' ||
        method == 'item/fileChange/outputDelta' ||
        method == 'item/reasoning/summaryTextDelta' ||
        method == 'item/reasoning/textDelta' ||
        method == 'thread/realtime/transcriptUpdated') {
      return false;
    }

    if (type == 'thread.status') {
      return true;
    }

    return method == 'item/completed' ||
        method == 'turn/started' ||
        method == 'turn/completed' ||
        method == 'thread/realtime/error' ||
        method == 'thread/realtime/closed' ||
        type == 'turn.started' ||
        type == 'turn.completed' ||
        type == 'thread.realtime.error' ||
        type == 'thread.realtime.closed';
  }

  bool _shouldReloadRuntime(BridgeRealtimeEvent event) {
    if (event.type == 'thread.status') {
      return realtimeEventThreadStatusType(event) != 'active';
    }

    return event.type == 'approval.request' ||
        event.type == 'user.input.request' ||
        event.type == 'mcp.elicitation.request' ||
        event.type == 'server.request.resolved' ||
        event.type == 'turn.completed' ||
        event.type == 'thread.realtime.error' ||
        event.type == 'thread.realtime.closed';
  }

  bool _isStreamingEventType(BridgeRealtimeEvent event) {
    final method = realtimeEventMethod(event) ?? '';
    return method == 'item/agentMessage/delta' ||
        method == 'item/plan/delta' ||
        method == 'item/commandExecution/outputDelta' ||
        method == 'item/fileChange/outputDelta' ||
        method == 'item/reasoning/summaryTextDelta' ||
        method == 'item/reasoning/textDelta' ||
        method == 'thread/realtime/transcriptUpdated' ||
        event.type.endsWith('.delta') ||
        event.type.endsWith('.updated');
  }

  List<CodexInputPart> _composerInputParts() {
    final message = _composerController.text.trim();
    return [
      if (message.isNotEmpty) CodexInputPart.text(message),
      ..._composerAttachments,
    ];
  }

  Future<void> _pickComposerAttachments() async {
    final attachments = await composerAttachmentBridge.pickAttachments();
    if (!mounted || attachments.isEmpty) {
      return;
    }
    _appendComposerAttachments(attachments);
  }

  Future<bool> _pasteComposerContent() async {
    final attachments = await composerAttachmentBridge
        .readClipboardAttachments();
    if (!mounted) {
      return attachments.isNotEmpty;
    }
    if (attachments.isNotEmpty) {
      _appendComposerAttachments(attachments);
      return true;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted || text == null || text.isEmpty) {
      return false;
    }
    _insertComposerTextAtSelection(text);
    return true;
  }

  void _insertComposerTextAtSelection(String text) {
    final value = _composerController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final safeStart = start < 0 ? value.text.length : start;
    final safeEnd = end < 0 ? value.text.length : end;
    final replaced = value.text.replaceRange(safeStart, safeEnd, text);
    final caretOffset = safeStart + text.length;
    _composerController.value = value.copyWith(
      text: replaced,
      selection: TextSelection.collapsed(offset: caretOffset),
      composing: TextRange.empty,
    );
  }

  void _appendComposerAttachments(List<CodexInputPart> attachments) {
    final next = [..._composerAttachments];
    for (final attachment in attachments) {
      final duplicate = next.any(
        (existing) =>
            existing.type == attachment.type &&
            existing.path == attachment.path,
      );
      if (!duplicate) {
        next.add(attachment);
      }
    }
    setState(() {
      _composerAttachments = List.unmodifiable(next);
    });
  }

  void _removeComposerAttachment(CodexInputPart attachment) {
    setState(() {
      _composerAttachments = _composerAttachments
          .where(
            (item) =>
                item.type != attachment.type || item.path != attachment.path,
          )
          .toList(growable: false);
    });
  }

  Future<void> _submitComposer() async {
    final input = _composerInputParts();
    if (input.isEmpty) {
      return;
    }

    setState(() {
      _submitting = true;
      _controlError = null;
    });

    try {
      final runtime = await _repository.sendMessage(
        threadId: widget.thread.id,
        input: input,
        expectedTurnId: _runtime.activeTurnId,
        model: _runtime.activeTurnId == null ? _selectedModelId : null,
        mode: _runtime.activeTurnId == null ? _selectedMode : null,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _composerController.clear();
        _composerAttachments = const [];
        _followConversation = true;
        _runtime = runtime;
        final nextStatus = runtime.activeTurnId == null ? 'idle' : 'active';
        _bundle = CodexThreadBundle(
          thread: _bundle.thread.copyWith(
            status: nextStatus,
            updatedAt: DateTime.now().toUtc(),
          ),
          items: _bundle.items,
        );
      });
      _storeCurrentThreadState();
      _scrollConversationToBottom(animated: false, force: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _controlError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _interruptTurn() async {
    final activeTurnId = _runtime.activeTurnId;
    if (activeTurnId == null) {
      return;
    }

    setState(() {
      _submitting = true;
      _controlError = null;
    });

    try {
      final runtime = await _repository.interruptTurn(
        threadId: widget.thread.id,
        turnId: activeTurnId,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _runtime = runtime;
        final nextStatus = runtime.activeTurnId == null ? 'idle' : 'active';
        _bundle = CodexThreadBundle(
          thread: _bundle.thread.copyWith(
            status: nextStatus,
            updatedAt: DateTime.now().toUtc(),
          ),
          items: _bundle.items,
        );
      });
      _storeCurrentThreadState();
      unawaited(_loadBundle(showSpinner: false, forceScrollToBottom: true));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _controlError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _respondToPendingRequest(
    CodexPendingRequest request,
    String action, {
    Map<String, dynamic>? answers,
    Object? content,
  }) async {
    setState(() {
      _responding = true;
      _controlError = null;
    });

    try {
      final runtime = await _repository.respondToPendingRequest(
        requestId: request.id,
        action: action,
        answers: answers,
        content: content,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _runtime = runtime;
        final nextStatus = runtime.activeTurnId == null ? 'idle' : 'active';
        _bundle = CodexThreadBundle(
          thread: _bundle.thread.copyWith(
            status: nextStatus,
            updatedAt: DateTime.now().toUtc(),
          ),
          items: _bundle.items,
        );
      });
      _storeCurrentThreadState();
      unawaited(_loadBundle(showSpinner: false, forceScrollToBottom: true));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _controlError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _responding = false;
        });
      }
    }
  }

  Future<void> _openStructuredRequest(CodexPendingRequest request) async {
    final primaryAction = request.actions.firstWhere(
      (action) => !action.destructive,
      orElse: () => request.actions.first,
    );
    final result = await showDialog<_PendingRequestSubmission>(
      context: context,
      builder: (context) => _PendingRequestDialog(request: request),
    );
    if (result == null || !mounted) {
      return;
    }

    await _respondToPendingRequest(
      request,
      primaryAction.id,
      answers: result.answers,
      content: result.content,
    );
  }

  Future<void> _copyRequestUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.strings.text(
            'Request URL copied to clipboard.',
            '请求 URL 已复制到剪贴板。',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final strings = context.strings;
    final compactLayout =
        widget.workspaceStyle || MediaQuery.sizeOf(context).width < 640;
    final conversationProjection = projectThreadMessageList(
      _realtimeAccumulator.items,
    );
    final conversationEntries = conversationProjection.entries;
    final showScrollToBottomButton =
        conversationEntries.isNotEmpty && !_followConversation;
    final liveMessage = _liveError != null && _liveError!.trim().isNotEmpty
        ? _liveError!.trim()
        : _liveEvents.isEmpty
        ? strings.text('Waiting for live updates', '等待实时更新')
        : _liveEvents.first.description.trim().isEmpty
        ? _humanize(context, _liveEvents.first.type)
        : _liveEvents.first.description.trim();
    final padding = EdgeInsets.fromLTRB(
      compactLayout ? 10 : 16,
      compactLayout ? 6 : 14,
      compactLayout ? 10 : 16,
      compactLayout ? 4 : 10,
    );
    final tailBodyLength = conversationProjection.tailBodyLength;
    final effectiveActiveThreadId =
        widget.activeThreadId ??
        ((_bundle.thread.status == 'active' || _runtime.activeTurnId != null)
            ? widget.thread.id
            : null);
    _debugLog(
      'page.binding',
      fields: {
        'selectedThreadId': widget.selectedThreadId ?? widget.thread.id,
        'currentDetailThreadId': widget.thread.id,
        'activeThreadId': effectiveActiveThreadId,
        'activeTurnId': _runtime.activeTurnId,
        'tailBodyLength': tailBodyLength,
      },
    );
    _debugLog(
      'ui.rebuild',
      fields: {
        'threadId': widget.thread.id,
        'tailBodyLength': tailBodyLength,
        'activeTurnId': _runtime.activeTurnId,
      },
    );

    return ColoredBox(
      color: panelBackgroundColor(theme),
      child: Column(
        children: [
          if (_controlError != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                0,
                padding.right,
                compactLayout ? 6 : 10,
              ),
              child: _InlineNotice(message: _controlError!, error: true),
            ),
          if (compactLayout &&
              _liveError != null &&
              _liveError!.trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 6),
              child: _InlineNotice(message: _liveError!, error: true),
            ),
          Expanded(
            child: ThreadMessageList(
              projection: conversationProjection,
              loading: _loading,
              errorMessage: _error,
              scrollController: _timelineScrollController,
              onRefresh: _reloadAll,
              onScrollNotification: _handleTimelineScrollNotification,
              workspaceStyle: widget.workspaceStyle,
              showLiveStatus: !compactLayout,
              liveStateLabel: _liveConnectionState.name,
              liveMessage: liveMessage,
              hasActiveTurn: _runtime.activeTurnId != null,
              showScrollToBottomButton: showScrollToBottomButton,
              onScrollToBottom: () {
                _scrollConversationToBottom(force: true);
              },
              footer: _runtime.pendingRequests.isEmpty
                  ? null
                  : _PendingRequestsPanel(
                      requests: _runtime.pendingRequests,
                      busy: _responding,
                      onRespond: _respondToPendingRequest,
                      onOpenStructuredRequest: _openStructuredRequest,
                      onCopyUrl: _copyRequestUrl,
                      workspaceStyle: widget.workspaceStyle,
                      expanded: _pendingRequestsExpanded,
                      onToggleExpanded: () {
                        setState(() {
                          _pendingRequestsExpanded = !_pendingRequestsExpanded;
                        });
                      },
                    ),
            ),
          ),
          _ComposerDock(
            composerController: _composerController,
            attachments: _composerAttachments,
            selectedMode: _selectedMode,
            onModeChanged: (mode) {
              setState(() {
                _selectedMode = mode;
              });
            },
            models: _models,
            selectedModelId: _selectedModelId,
            onModelChanged: (value) {
              setState(() {
                _selectedModelId = value;
              });
            },
            submitting: _submitting,
            loadingModels: _modelsLoading,
            runtimeLoading: _runtimeLoading,
            hasActiveTurn: _runtime.activeTurnId != null,
            onSubmit: _submitComposer,
            onInterrupt: _interruptTurn,
            onPickAttachments: _pickComposerAttachments,
            onPasteFromClipboard: _pasteComposerContent,
            onRemoveAttachment: _removeComposerAttachment,
            workspaceStyle: widget.workspaceStyle,
            compact: compactLayout,
          ),
        ],
      ),
    );
  }
}

enum LiveConnectionState { disconnected, connecting, connected, failed }

DateTime? _laterTimestamp(DateTime? left, DateTime? right) {
  if (left == null) {
    return right;
  }
  if (right == null) {
    return left;
  }
  return left.isAfter(right) ? left : right;
}

bool _sameTimestamp(DateTime? left, DateTime? right) {
  if (left == null && right == null) {
    return true;
  }
  if (left == null || right == null) {
    return false;
  }
  return left.isAtSameMomentAs(right);
}

extension on _ThreadDetailPaneState {
  void _debugLog(String message, {Map<String, Object?> fields = const {}}) {
    if (!UiDebugLogger.matchesThread(widget.thread.id)) {
      return;
    }
    UiDebugLogger.log(
      'ThreadDetail',
      message,
      threadId: widget.thread.id,
      fields: fields,
    );
  }
}

typedef PendingRequestResponder =
    Future<void> Function(
      CodexPendingRequest request,
      String action, {
      Map<String, dynamic>? answers,
      Object? content,
    });

// ignore: unused_element
class _WorkspaceHeaderPanel extends StatelessWidget {
  const _WorkspaceHeaderPanel({
    required this.thread,
    required this.liveConnectionState,
    required this.pendingCount,
    required this.activeTurnId,
    required this.onRefresh,
    required this.workspaceStyle,
    required this.compact,
  });

  final CodexThreadSummary thread;
  final LiveConnectionState liveConnectionState;
  final int pendingCount;
  final String? activeTurnId;
  final Future<void> Function() onRefresh;
  final bool workspaceStyle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final compactLayout = compact || workspaceStyle;
    final statusLine = <String>[
      _providerLabel(context, thread.provider),
      _humanize(context, thread.status),
      _humanize(context, liveConnectionState.name),
      activeTurnId == null
          ? strings.text('Idle', '空闲')
          : strings.text('Active turn', '轮次活动中'),
      if (pendingCount > 0)
        strings.text('$pendingCount pending', '$pendingCount 个待处理'),
      if (thread.cwd != null) _workspaceLabel(context, thread.cwd),
      _formatRelative(context, thread.updatedAt),
    ].join(' • ');
    final metadata = <String>[
      if (thread.cwd != null) _workspaceLabel(context, thread.cwd),
      '${strings.text('Updated', '更新于')} ${_formatRelative(context, thread.updatedAt)}',
      if (!workspaceStyle)
        strings.text('Pending $pendingCount', '待处理 $pendingCount'),
    ];
    final metadataLine = metadata.join(' • ');
    if (workspaceStyle) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: borderColor(theme))),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      statusLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryTextColor(theme),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  unawaited(onRefresh());
                },
                tooltip: strings.text('Refresh', '刷新'),
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                splashRadius: 18,
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
        ),
      );
    }
    if (compactLayout) {
      return _SurfaceSection(
        compact: true,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text('Current session', '当前会话'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: secondaryTextColor(theme),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryTextColor(theme),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: () {
                unawaited(onRefresh());
              },
              tooltip: strings.text('Refresh', '刷新'),
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: const Icon(Icons.sync),
            ),
          ],
        ),
      );
    }
    return _SurfaceSection(
      workspaceStyle: workspaceStyle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!workspaceStyle) ...[
                      Text(
                        strings.text('Current session', '当前会话'),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: secondaryTextColor(theme),
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Wrap(
                      spacing: workspaceStyle ? 6 : 8,
                      runSpacing: workspaceStyle ? 6 : 8,
                      children: [
                        _SessionMetaBadge(
                          compact: workspaceStyle,
                          value:
                              '${strings.text('Provider', 'Provider')} ${_providerLabel(context, thread.provider)}',
                        ),
                        _SessionMetaBadge(
                          compact: workspaceStyle,
                          value:
                              '${strings.text('Live', '实时')} ${_humanize(context, liveConnectionState.name)}',
                        ),
                        _SessionMetaBadge(
                          compact: workspaceStyle,
                          value: activeTurnId == null
                              ? strings.text('Turn idle', '轮次空闲')
                              : strings.text('Turn active', '轮次活动中'),
                        ),
                      ],
                    ),
                    SizedBox(height: workspaceStyle ? 6 : 12),
                    Text(
                      thread.title,
                      maxLines: workspaceStyle ? 1 : null,
                      overflow: workspaceStyle ? TextOverflow.ellipsis : null,
                      style:
                          (workspaceStyle
                                  ? theme.textTheme.titleMedium
                                  : theme.textTheme.headlineSmall)
                              ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: workspaceStyle ? 6 : 12),
                    if (workspaceStyle)
                      Text(
                        metadataLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondaryTextColor(theme),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: metadata
                            .map(
                              (value) => _SessionMetaBadge(
                                value: value,
                                compact: workspaceStyle,
                              ),
                            )
                            .toList(growable: false),
                      ),
                  ],
                ),
              ),
              SizedBox(width: workspaceStyle ? 10 : 16),
              if (workspaceStyle)
                IconButton(
                  onPressed: () {
                    unawaited(onRefresh());
                  },
                  tooltip: strings.text('Refresh', '刷新'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.sync),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: () {
                    unawaited(onRefresh());
                  },
                  icon: const Icon(Icons.sync),
                  label: Text(strings.text('Refresh', '刷新')),
                ),
            ],
          ),
          if (!workspaceStyle) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _InfoChip(
                  label: strings.text('Provider', 'Provider'),
                  value: _providerLabel(context, thread.provider),
                ),
                _InfoChip(
                  label: strings.text('Status', '状态'),
                  value: _humanize(context, thread.status),
                ),
                _InfoChip(
                  label: strings.text('Live', '实时'),
                  value: _humanize(context, liveConnectionState.name),
                ),
                _InfoChip(
                  label: strings.text('Pending', '待处理'),
                  value: '$pendingCount',
                ),
                _InfoChip(
                  label: strings.text('Turn', '轮次'),
                  value: activeTurnId == null
                      ? strings.text('idle', '空闲')
                      : strings.text('active', '活动中'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: error
            ? theme.colorScheme.error.withValues(alpha: 0.12)
            : selectionFillColor(theme),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: error
              ? theme.colorScheme.error.withValues(alpha: 0.35)
              : borderColor(theme),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: error
                ? theme.colorScheme.error
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _PendingRequestsPanel extends StatelessWidget {
  const _PendingRequestsPanel({
    required this.requests,
    required this.busy,
    required this.onRespond,
    required this.onOpenStructuredRequest,
    required this.onCopyUrl,
    required this.expanded,
    required this.onToggleExpanded,
    this.workspaceStyle = false,
  });

  final List<CodexPendingRequest> requests;
  final bool busy;
  final PendingRequestResponder onRespond;
  final Future<void> Function(CodexPendingRequest request)
  onOpenStructuredRequest;
  final Future<void> Function(String url) onCopyUrl;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final summary = strings.text(
      '${requests.length} pending request${requests.length == 1 ? '' : 's'}',
      '${requests.length} 个待处理请求',
    );
    final firstTitle = requests.first.title.trim();
    return _SurfaceSection(
      workspaceStyle: workspaceStyle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: workspaceStyle ? 2 : 0,
                vertical: workspaceStyle ? 2 : 0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.text('Pending Requests', '待处理请求'),
                          style:
                              (workspaceStyle
                                      ? theme.textTheme.titleMedium
                                      : theme.textTheme.titleLarge)
                                  ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          workspaceStyle && !expanded && firstTitle.isNotEmpty
                              ? '$summary · $firstTitle'
                              : strings.text(
                                  'Approvals and follow-up prompts from the active session.',
                                  '活动会话里的审批和后续提示会显示在这里。',
                                ),
                          maxLines: workspaceStyle && !expanded ? 1 : null,
                          overflow: workspaceStyle && !expanded
                              ? TextOverflow.ellipsis
                              : null,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: secondaryTextColor(theme),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (workspaceStyle) ...[
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: onToggleExpanded,
                      icon: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: Text(
                        expanded
                            ? strings.text('Hide', '收起')
                            : strings.text('Show', '展开'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!workspaceStyle || expanded) ...[
            SizedBox(height: workspaceStyle ? 10 : 16),
            ...requests.map(
              (request) => Padding(
                padding: EdgeInsets.only(bottom: workspaceStyle ? 8 : 12),
                child: _PendingRequestCard(
                  request: request,
                  busy: busy,
                  onRespond: onRespond,
                  onOpenStructuredRequest: onOpenStructuredRequest,
                  onCopyUrl: onCopyUrl,
                  compact: workspaceStyle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingRequestCard extends StatelessWidget {
  const _PendingRequestCard({
    required this.request,
    required this.busy,
    required this.onRespond,
    required this.onOpenStructuredRequest,
    required this.onCopyUrl,
    this.compact = false,
  });

  final CodexPendingRequest request;
  final bool busy;
  final PendingRequestResponder onRespond;
  final Future<void> Function(CodexPendingRequest request)
  onOpenStructuredRequest;
  final Future<void> Function(String url) onCopyUrl;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final structuredAction = request.actions.where(
      (action) =>
          !action.destructive &&
          (action.id == 'submit' || action.id == 'accept'),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.title,
                        style:
                            (compact
                                    ? theme.textTheme.titleSmall
                                    : theme.textTheme.titleMedium)
                                ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request.message,
                        style: compact
                            ? theme.textTheme.bodySmall
                            : theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _StatusPill(label: request.kind, compact: compact),
              ],
            ),
            if (request.detail != null) ...[
              const SizedBox(height: 8),
              Text(
                request.detail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondaryTextColor(theme),
                ),
              ),
            ],
            if (request.command != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                request.command!,
                style: appCodeTextStyle(theme.textTheme.bodySmall),
              ),
            ],
            if (request.cwd != null) ...[
              const SizedBox(height: 4),
              Text(
                request.cwd!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondaryTextColor(theme),
                ),
              ),
            ],
            if (request.url != null) ...[
              const SizedBox(height: 8),
              SelectableText(request.url!),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        unawaited(onCopyUrl(request.url!));
                      },
                icon: const Icon(Icons.copy_all_outlined),
                label: Text(strings.text('Copy URL', '复制 URL')),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...structuredAction.map(
                  (action) => FilledButton(
                    onPressed: busy
                        ? null
                        : () {
                            unawaited(onOpenStructuredRequest(request));
                          },
                    child: Text(action.label),
                  ),
                ),
                ...request.actions
                    .where(
                      (action) => structuredAction.contains(action) == false,
                    )
                    .map(
                      (action) => action.destructive
                          ? OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      unawaited(onRespond(request, action.id));
                                    },
                              child: Text(action.label),
                            )
                          : FilledButton.tonal(
                              onPressed: busy
                                  ? null
                                  : () {
                                      unawaited(onRespond(request, action.id));
                                    },
                              child: Text(action.label),
                            ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerDock extends StatelessWidget {
  const _ComposerDock({
    required this.composerController,
    required this.attachments,
    required this.selectedMode,
    required this.onModeChanged,
    required this.models,
    required this.selectedModelId,
    required this.onModelChanged,
    required this.submitting,
    required this.loadingModels,
    required this.runtimeLoading,
    required this.hasActiveTurn,
    required this.onSubmit,
    required this.onInterrupt,
    required this.onPickAttachments,
    required this.onPasteFromClipboard,
    required this.onRemoveAttachment,
    this.workspaceStyle = false,
    this.compact = false,
  });

  final TextEditingController composerController;
  final List<CodexInputPart> attachments;
  final CodexComposerMode selectedMode;
  final ValueChanged<CodexComposerMode> onModeChanged;
  final List<CodexModelOption> models;
  final String? selectedModelId;
  final ValueChanged<String?> onModelChanged;
  final bool submitting;
  final bool loadingModels;
  final bool runtimeLoading;
  final bool hasActiveTurn;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onInterrupt;
  final Future<void> Function() onPickAttachments;
  final Future<bool> Function() onPasteFromClipboard;
  final ValueChanged<CodexInputPart> onRemoveAttachment;
  final bool workspaceStyle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final compactWorkspace = compact || workspaceStyle;
    final helperText = hasActiveTurn
        ? strings.text(
            'Steer the active turn, or leave the box empty to interrupt it.',
            '可以引导当前轮次；留空并发送会中断当前轮次。',
          )
        : strings.text(
            'Start the next turn with the composer below.',
            '使用下方输入框开始下一轮。',
          );
    CodexModelOption? selectedModel;
    if (selectedModelId != null) {
      for (final model in models) {
        if (model.id == selectedModelId) {
          selectedModel = model;
          break;
        }
      }
    }
    final modelLabel = loadingModels && models.isEmpty
        ? strings.text('Loading models', '加载模型')
        : selectedModel?.displayName ??
              selectedModelId ??
              strings.text('Model auto', '模型自动');
    final reasoningLabel = _reasoningEffortLabel(context, selectedModel);
    final permissionLabel = _permissionLabel(context, selectedMode);
    final composerLabel = hasActiveTurn || compactWorkspace
        ? null
        : strings.text('Prompt', '提示词');
    final composerHint = hasActiveTurn
        ? strings.text(
            'Provide steering or clarifying instructions',
            '提供引导或澄清指令',
          )
        : strings.text('Tell Codex what to do next', '告诉 Codex 下一步做什么');
    final modelControl = _InlineComposerMenu<String>(
      label: modelLabel,
      compact: compactWorkspace,
      enabled: !loadingModels && !submitting && models.isNotEmpty,
      tooltip: strings.text('Select model', '选择模型'),
      items: models
          .map(
            (model) => PopupMenuItem<String>(
              value: model.id,
              child: SizedBox(
                width: compactWorkspace ? 220 : 260,
                child: Text(model.displayName, overflow: TextOverflow.ellipsis),
              ),
            ),
          )
          .toList(growable: false),
      onSelected: (value) {
        onModelChanged(value);
      },
    );
    final reasoningControl = Tooltip(
      message: strings.text(
        'Showing the selected model default reasoning effort.',
        '当前显示所选模型的默认推理强度。',
      ),
      child: _InlineComposerValue(
        label: reasoningLabel,
        compact: compactWorkspace,
      ),
    );
    final permissionControl = _InlineComposerMenu<CodexComposerMode>(
      label: permissionLabel,
      compact: compactWorkspace,
      enabled: !hasActiveTurn && !submitting,
      tooltip: hasActiveTurn
          ? strings.text(
              'Permission changes apply when the next turn starts.',
              '权限调整会在下一轮开始时生效。',
            )
          : strings.text('Select permissions', '选择权限'),
      items: CodexComposerMode.values
          .map(
            (mode) => PopupMenuItem<CodexComposerMode>(
              value: mode,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_permissionLabel(context, mode)),
                  Text(
                    _modeLabel(context, mode),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryTextColor(theme),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
      onSelected: onModeChanged,
    );
    final attachmentButton = Tooltip(
      message: strings.text('Add image or file', '添加图片或文件'),
      child: IconButton(
        onPressed: submitting || runtimeLoading
            ? null
            : () {
                unawaited(onPickAttachments());
              },
        visualDensity: VisualDensity.compact,
        splashRadius: compactWorkspace ? 16 : 18,
        iconSize: compactWorkspace ? 16 : 18,
        constraints: BoxConstraints.tightFor(
          width: compactWorkspace ? 32 : 36,
          height: compactWorkspace ? 32 : 36,
        ),
        icon: const Icon(Icons.attach_file_rounded),
      ),
    );
    final submitButton = ValueListenableBuilder<TextEditingValue>(
      valueListenable: composerController,
      builder: (context, value, _) {
        final interruptAction =
            hasActiveTurn && value.text.trim().isEmpty && attachments.isEmpty;
        return Tooltip(
          message: interruptAction
              ? strings.text('Interrupt current turn', '中断当前轮次')
              : hasActiveTurn
              ? strings.text('Send steering message', '发送引导消息')
              : strings.text('Send prompt', '发送提示词'),
          child: IconButton.filled(
            onPressed: submitting || runtimeLoading
                ? null
                : () {
                    unawaited(interruptAction ? onInterrupt() : onSubmit());
                  },
            style: IconButton.styleFrom(
              backgroundColor: interruptAction
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
              foregroundColor: interruptAction
                  ? theme.colorScheme.onError
                  : theme.colorScheme.onPrimary,
              disabledBackgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.28,
              ),
              disabledForegroundColor: theme.colorScheme.onPrimary.withValues(
                alpha: 0.55,
              ),
              minimumSize: Size(
                compactWorkspace ? 32 : 34,
                compactWorkspace ? 32 : 34,
              ),
            ),
            icon: submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    interruptAction
                        ? Icons.stop_rounded
                        : Icons.arrow_upward_rounded,
                    size: compactWorkspace ? 16 : 18,
                  ),
          ),
        );
      },
    );
    final composerField = DecoratedBox(
      decoration: BoxDecoration(
        color:
            theme.inputDecorationTheme.fillColor ?? panelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(compactWorkspace ? 18 : 22),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (composerLabel != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                compactWorkspace ? 12 : 16,
                compactWorkspace ? 10 : 14,
                compactWorkspace ? 12 : 16,
                0,
              ),
              child: Text(
                composerLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondaryTextColor(theme),
                  letterSpacing: 0.2,
                ),
              ),
            ),
          Actions(
            actions: {
              PasteTextIntent: _ComposerPasteTextAction(
                onPaste: onPasteFromClipboard,
              ),
            },
            child: TextField(
              controller: composerController,
              minLines: hasActiveTurn
                  ? (compactWorkspace ? 2 : 6)
                  : (compactWorkspace ? 1 : 2),
              maxLines: hasActiveTurn
                  ? (compactWorkspace ? 6 : 12)
                  : (compactWorkspace ? 4 : 6),
              enabled: !submitting && !runtimeLoading,
              decoration: InputDecoration(
                isDense: compactWorkspace,
                hintText: composerHint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                fillColor: Colors.transparent,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                contentPadding: EdgeInsets.fromLTRB(
                  compactWorkspace ? 12 : 16,
                  compactWorkspace ? 6 : 12,
                  compactWorkspace ? 12 : 16,
                  compactWorkspace ? 6 : 12,
                ),
              ),
            ),
          ),
          if (attachments.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                compactWorkspace ? 10 : 14,
                0,
                compactWorkspace ? 10 : 14,
                compactWorkspace ? 8 : 10,
              ),
              child: Wrap(
                spacing: compactWorkspace ? 6 : 8,
                runSpacing: compactWorkspace ? 6 : 8,
                children: [
                  for (final attachment in attachments)
                    _ComposerAttachmentChip(
                      attachment: attachment,
                      compact: compactWorkspace,
                      onRemoved: () => onRemoveAttachment(attachment),
                    ),
                ],
              ),
            ),
          Divider(height: 1, thickness: 1, color: borderColor(theme)),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compactWorkspace ? 8 : 10,
              compactWorkspace ? 6 : 6,
              compactWorkspace ? 8 : 10,
              compactWorkspace ? 6 : 6,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final inlineControls = [
                  attachmentButton,
                  modelControl,
                  reasoningControl,
                  permissionControl,
                ];
                if (compactWorkspace ||
                    constraints.maxWidth >= (compactWorkspace ? 500 : 600)) {
                  return Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (
                                var index = 0;
                                index < inlineControls.length;
                                index += 1
                              ) ...[
                                if (index > 0)
                                  SizedBox(width: compactWorkspace ? 8 : 10),
                                inlineControls[index],
                              ],
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: compactWorkspace ? 4 : 6),
                      submitButton,
                    ],
                  );
                }

                return Wrap(
                  spacing: compactWorkspace ? 8 : 10,
                  runSpacing: compactWorkspace ? 6 : 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [...inlineControls, submitButton],
                );
              },
            ),
          ),
        ],
      ),
    );
    if (compactWorkspace) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: panelBackgroundColor(theme),
          border: Border(top: BorderSide(color: borderColor(theme))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: composerField,
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: panelBackgroundColor(theme),
        border: Border(top: BorderSide(color: borderColor(theme))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compactWorkspace ? 10 : 16,
            compactWorkspace ? 4 : 14,
            compactWorkspace ? 10 : 16,
            compactWorkspace ? 8 : 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compactWorkspace && hasActiveTurn)
                Text(
                  helperText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: compactWorkspace ? 12 : null,
                    color: secondaryTextColor(theme),
                  ),
                ),
              if (!compactWorkspace && hasActiveTurn)
                SizedBox(height: compactWorkspace ? 6 : 12),
              composerField,
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingRequestSubmission {
  const _PendingRequestSubmission({this.answers, this.content});

  final Map<String, dynamic>? answers;
  final Object? content;
}

class _PendingRequestDialog extends StatefulWidget {
  const _PendingRequestDialog({required this.request});

  final CodexPendingRequest request;

  @override
  State<_PendingRequestDialog> createState() => _PendingRequestDialogState();
}

class _PendingRequestDialogState extends State<_PendingRequestDialog> {
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, String?> _singleSelections = {};
  final Map<String, Set<String>> _multiSelections = {};
  final Map<String, bool> _booleanSelections = {};

  @override
  void initState() {
    super.initState();
    for (final question in widget.request.questions) {
      _textControllers[question.id] = TextEditingController();
      _singleSelections[question.id] = question.options
          .firstWhere(
            (option) => option.recommended,
            orElse: () => question.options.isNotEmpty
                ? question.options.first
                : const CodexPendingOption(
                    id: '',
                    label: '',
                    recommended: false,
                  ),
          )
          .id;
    }

    for (final field in widget.request.formFields) {
      switch (field.type) {
        case CodexPendingFieldType.text:
        case CodexPendingFieldType.number:
          _textControllers[field.id] = TextEditingController(
            text: field.defaultValue?.toString() ?? '',
          );
        case CodexPendingFieldType.boolean:
          _booleanSelections[field.id] = field.defaultValue == true;
        case CodexPendingFieldType.singleSelect:
          _singleSelections[field.id] =
              field.defaultValue?.toString() ??
              (field.options.isNotEmpty ? field.options.first.id : null);
        case CodexPendingFieldType.multiSelect:
          final defaults = field.defaultValue is List
              ? (field.defaultValue as List)
                    .map((item) => item.toString())
                    .toSet()
              : <String>{};
          _multiSelections[field.id] = defaults;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return AlertDialog(
      title: Text(widget.request.title),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.request.message),
              if (widget.request.questions.isNotEmpty) ...[
                const SizedBox(height: 18),
                ...widget.request.questions.map(_buildQuestionBlock),
              ],
              if (widget.request.formFields.isNotEmpty) ...[
                const SizedBox(height: 18),
                ...widget.request.formFields.map(_buildFormFieldBlock),
              ],
              if (widget.request.url != null) ...[
                const SizedBox(height: 18),
                Text(
                  strings.text('URL', 'URL'),
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                SelectableText(widget.request.url!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(strings.text('Close', '关闭')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(_collectSubmission());
          },
          child: Text(strings.text('Submit', '提交')),
        ),
      ],
    );
  }

  Widget _buildQuestionBlock(CodexPendingQuestion question) {
    final theme = Theme.of(context);
    final controller = _textControllers[question.id];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            question.prompt,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondaryTextColor(theme),
            ),
          ),
          if (question.options.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: question.options
                  .map((option) {
                    final selected =
                        _singleSelections[question.id] == option.id;
                    return ChoiceChip(
                      label: Text(option.label),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _singleSelections[question.id] = option.id;
                        });
                      },
                    );
                  })
                  .toList(growable: false),
            ),
          ],
          if (question.allowFreeform && controller != null) ...[
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: context.strings.text('Other', '其他'),
                hintText: context.strings.text(
                  'Enter a custom answer',
                  '输入自定义答案',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormFieldBlock(CodexPendingFormField field) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (field.description != null) ...[
            const SizedBox(height: 4),
            Text(
              field.description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondaryTextColor(theme),
              ),
            ),
          ],
          const SizedBox(height: 8),
          switch (field.type) {
            CodexPendingFieldType.text ||
            CodexPendingFieldType.number => TextField(
              controller: _textControllers[field.id],
              keyboardType: field.type == CodexPendingFieldType.number
                  ? TextInputType.number
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: field.required ? '${field.label} *' : field.label,
              ),
            ),
            CodexPendingFieldType.boolean => SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _booleanSelections[field.id] ?? false,
              title: Text(field.label),
              onChanged: (value) {
                setState(() {
                  _booleanSelections[field.id] = value;
                });
              },
            ),
            CodexPendingFieldType.singleSelect =>
              DropdownButtonFormField<String>(
                initialValue: _singleSelections[field.id],
                items: field.options
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.id,
                        child: Text(option.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  setState(() {
                    _singleSelections[field.id] = value;
                  });
                },
                decoration: InputDecoration(
                  labelText: field.required ? '${field.label} *' : field.label,
                ),
              ),
            CodexPendingFieldType.multiSelect => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: field.options
                  .map((option) {
                    final selection = _multiSelections[field.id] ?? <String>{};
                    return FilterChip(
                      label: Text(option.label),
                      selected: selection.contains(option.id),
                      onSelected: (selected) {
                        setState(() {
                          final next = {...selection};
                          if (selected) {
                            next.add(option.id);
                          } else {
                            next.remove(option.id);
                          }
                          _multiSelections[field.id] = next;
                        });
                      },
                    );
                  })
                  .toList(growable: false),
            ),
          },
        ],
      ),
    );
  }

  _PendingRequestSubmission _collectSubmission() {
    if (widget.request.questions.isNotEmpty) {
      final answers = <String, dynamic>{};
      for (final question in widget.request.questions) {
        final selected = _singleSelections[question.id];
        final freeform = _textControllers[question.id]?.text.trim() ?? '';
        if (freeform.isNotEmpty) {
          answers[question.id] = freeform;
        } else if (selected != null && selected.isNotEmpty) {
          answers[question.id] = selected;
        }
      }
      return _PendingRequestSubmission(answers: answers);
    }

    if (widget.request.formFields.isNotEmpty) {
      final content = <String, dynamic>{};
      for (final field in widget.request.formFields) {
        switch (field.type) {
          case CodexPendingFieldType.text:
            final value = _textControllers[field.id]?.text.trim() ?? '';
            if (value.isNotEmpty) {
              content[field.id] = value;
            }
          case CodexPendingFieldType.number:
            final raw = _textControllers[field.id]?.text.trim() ?? '';
            if (raw.isNotEmpty) {
              content[field.id] = num.tryParse(raw) ?? raw;
            }
          case CodexPendingFieldType.boolean:
            content[field.id] = _booleanSelections[field.id] ?? false;
          case CodexPendingFieldType.singleSelect:
            final value = _singleSelections[field.id];
            if (value != null && value.isNotEmpty) {
              content[field.id] = value;
            }
          case CodexPendingFieldType.multiSelect:
            content[field.id] = (_multiSelections[field.id] ?? <String>{})
                .toList(growable: false);
        }
      }
      return _PendingRequestSubmission(content: content);
    }

    return const _PendingRequestSubmission();
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = mutedPanelBackgroundColor(theme);
    final foreground = theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: foreground.withValues(alpha: 0.78),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: foreground,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionMetaBadge extends StatelessWidget {
  const _SessionMetaBadge({required this.value, this.compact = false});

  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: panelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Text(
        value,
        style: theme.textTheme.labelMedium?.copyWith(
          color: secondaryTextColor(theme),
        ),
      ),
    );
  }
}

class _ComposerPasteTextAction extends Action<PasteTextIntent> {
  _ComposerPasteTextAction({required this.onPaste});

  final Future<bool> Function() onPaste;

  @override
  Object? invoke(PasteTextIntent intent) {
    unawaited(onPaste());
    return null;
  }
}

class _ComposerAttachmentChip extends StatelessWidget {
  const _ComposerAttachmentChip({
    required this.attachment,
    required this.onRemoved,
    this.compact = false,
  });

  final CodexInputPart attachment;
  final VoidCallback onRemoved;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = attachment.displayLabel.trim().isEmpty
        ? attachment.previewText
        : attachment.displayLabel.trim();
    return Container(
      padding: EdgeInsets.only(
        left: compact ? 10 : 12,
        right: compact ? 6 : 8,
        top: compact ? 5 : 6,
        bottom: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            attachment.type == CodexInputPartType.localImage
                ? Icons.image_outlined
                : Icons.description_outlined,
            size: compact ? 14 : 16,
            color: secondaryTextColor(theme),
          ),
          SizedBox(width: compact ? 6 : 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 180 : 240),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ),
          SizedBox(width: compact ? 2 : 4),
          InkWell(
            onTap: onRemoved,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: compact ? 14 : 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineComposerMenu<T> extends StatelessWidget {
  const _InlineComposerMenu({
    required this.label,
    required this.items,
    required this.onSelected,
    this.enabled = true,
    this.compact = false,
    this.tooltip,
  });

  final String label;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final bool compact;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = _InlineComposerValue(
      label: label,
      trailingIcon: enabled ? Icons.expand_more_rounded : null,
      enabled: enabled,
      compact: compact,
    );
    if (!enabled) {
      return Tooltip(message: tooltip ?? label, child: child);
    }
    return PopupMenuButton<T>(
      tooltip: tooltip,
      enabled: enabled,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (context) => items,
      child: child,
    );
  }
}

class _InlineComposerValue extends StatelessWidget {
  const _InlineComposerValue({
    required this.label,
    this.trailingIcon,
    this.enabled = true,
    this.compact = false,
  });

  final String label;
  final IconData? trailingIcon;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled
        ? theme.colorScheme.onSurface
        : secondaryTextColor(theme);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 150 : 190),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: 2),
          Icon(trailingIcon, size: 14, color: color),
        ],
      ],
    );
    if (!compact) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 22),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: child,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _humanize(context, label),
        style:
            (compact
                    ? Theme.of(context).textTheme.labelSmall
                    : Theme.of(context).textTheme.labelMedium)
                ?.copyWith(
                  color: theme.brightness == Brightness.dark
                      ? theme.colorScheme.primary
                      : null,
                ),
      ),
    );
  }
}

class _SurfaceSection extends StatelessWidget {
  const _SurfaceSection({
    required this.child,
    this.workspaceStyle = false,
    this.compact = false,
  });

  final Widget child;
  final bool workspaceStyle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: workspaceStyle
            ? mutedPanelBackgroundColor(theme)
            : panelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(
          workspaceStyle ? 20 : (compact ? 18 : panelRadius(theme)),
        ),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Padding(
        padding: EdgeInsets.all(workspaceStyle || compact ? 12 : 20),
        child: child,
      ),
    );
  }
}

String _workspaceLabel(BuildContext context, String? value) {
  if (value == null) {
    return context.strings.text('Unknown workspace', '未知工作区');
  }

  final normalized = value.trim().replaceFirst(r'\\?\', '');
  final segments = normalized
      .split(RegExp(r'[\\/]'))
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  return segments.isNotEmpty ? segments.last : normalized;
}

String _formatRelative(BuildContext context, DateTime? value) {
  return context.strings.formatRelativeTime(value);
}

String _humanize(BuildContext context, String value) {
  return context.strings.humanizeMachineLabel(value);
}

String _providerLabel(BuildContext context, String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return context.strings.text('Unknown provider', '未知 Provider');
  }
  return normalized;
}

String _modeLabel(BuildContext context, CodexComposerMode mode) {
  return switch (mode) {
    CodexComposerMode.chat => context.strings.text('No file changes', '不修改文件'),
    CodexComposerMode.agent => context.strings.text(
      'Current project only',
      '仅当前项目',
    ),
    CodexComposerMode.agentFullAccess => context.strings.text(
      'Includes outside project',
      '包括项目外路径',
    ),
  };
}

String _permissionLabel(BuildContext context, CodexComposerMode mode) {
  return switch (mode) {
    CodexComposerMode.chat => context.strings.text('Read only', '只读'),
    CodexComposerMode.agent => context.strings.text('Edit project', '项目内修改'),
    CodexComposerMode.agentFullAccess => context.strings.text(
      'Full access',
      '完全访问',
    ),
  };
}

String _reasoningEffortLabel(
  BuildContext context,
  CodexModelOption? selectedModel,
) {
  final rawValue =
      selectedModel?.defaultReasoningEffort?.trim().isNotEmpty == true
      ? selectedModel!.defaultReasoningEffort!.trim()
      : selectedModel != null &&
            selectedModel.supportedReasoningEfforts.isNotEmpty
      ? selectedModel.supportedReasoningEfforts.first.trim()
      : '';
  return switch (rawValue) {
    'low' => context.strings.text('Low', '低'),
    'medium' => context.strings.text('Medium', '中'),
    'high' => context.strings.text('High', '高'),
    'very_high' || 'very-high' => context.strings.text('Very high', '超高'),
    _ when rawValue.isNotEmpty => context.strings.humanizeMachineLabel(
      rawValue,
    ),
    _ => context.strings.text('Auto', '自动'),
  };
}
