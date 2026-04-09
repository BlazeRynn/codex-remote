import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_strings.dart';
import '../app/workspace_theme.dart';
import '../models/bridge_config.dart';
import '../models/bridge_health.dart';
import '../models/codex_composer_mode.dart';
import '../models/codex_directory_entry.dart';
import '../models/codex_input_part.dart';
import '../models/codex_model_option.dart';
import '../models/codex_thread_summary.dart';
import '../services/app_preferences_controller.dart';
import '../services/bridge_config_store.dart';
import '../services/bridge_realtime_client.dart';
import '../services/codex_repository.dart';
import '../services/realtime_event_helpers.dart';
import '../services/thread_list_projection.dart';
import '../services/thread_state_projection.dart';
import '../services/ui_debug_logger.dart';
import 'app_server_logs_screen.dart';
import 'settings_screen.dart';
import 'thread_detail_screen.dart';

class ThreadListScreen extends StatefulWidget {
  const ThreadListScreen({
    super.key,
    required this.configStore,
    required this.preferencesController,
  });

  final BridgeConfigStore configStore;
  final AppPreferencesController preferencesController;

  @override
  State<ThreadListScreen> createState() => _ThreadListScreenState();
}

class _ThreadListScreenState extends State<ThreadListScreen> {
  static const int _maxDesktopDetailPanes = 4;

  BridgeConfig _config = BridgeConfig.empty;
  BridgeHealth _health = const BridgeHealth.offline(
    'Codex app-server not configured',
  );
  List<CodexThreadSummary> _threads = const [];
  String? _selectedThreadId;
  final List<String> _desktopDetailThreadIds = <String>[];
  final Set<String> _collapsedWorkspaceKeys = <String>{};

  bool _loading = true;
  bool _creatingThread = false;
  String? _error;

  CodexRealtimeSession? _realtimeSession;
  StreamSubscription<BridgeRealtimeEvent>? _realtimeSubscription;
  Timer? _realtimeRefreshDebounce;

  @override
  void initState() {
    super.initState();
    widget.preferencesController.addListener(_handlePreferencesChanged);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    widget.preferencesController.removeListener(_handlePreferencesChanged);
    _realtimeRefreshDebounce?.cancel();
    unawaited(_closeRealtime());
    super.dispose();
  }

  void _handlePreferencesChanged() {
    if (!mounted) {
      return;
    }

    final projection = _projectThreads();
    setState(() {
      _syncSelectionFromProjection(projection);
    });
  }

  ThreadListProjection _projectThreads({
    List<CodexThreadSummary>? threads,
    String? preferredSelectedThreadId,
  }) {
    return ThreadListProjection(
      threads: threads ?? _threads,
      preferredSelectedThreadId: preferredSelectedThreadId ?? _selectedThreadId,
      showArchivedThreads: false,
      showAllWorkspaces: true,
      isThreadArchived: _isThreadArchived,
    );
  }

  void _syncSelectionFromProjection(ThreadListProjection projection) {
    _selectedThreadId = projection.selectedThreadId;
    _rememberDesktopDetailThread(_selectedThreadId);
    _expandWorkspaceForThread(projection.selectedThread);
  }

  Future<void> _initialize() async {
    final config = await widget.configStore.load();
    if (!mounted) {
      return;
    }

    setState(() {
      _config = config;
    });

    if (!config.isConfigured) {
      await _closeRealtime();
      setState(() {
        _loading = false;
        _health = const BridgeHealth.offline('Codex app-server not configured');
        _threads = const [];
        _selectedThreadId = null;
        _desktopDetailThreadIds.clear();
      });
      return;
    }

    await _refresh(config: config);
  }

  Future<void> _refresh({BridgeConfig? config}) async {
    final activeConfig = config ?? _config;
    if (!activeConfig.isConfigured) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final repository = createCodexRepository(activeConfig);

    try {
      final health = await repository.getHealth();
      final threads = await repository.listThreads();
      if (!mounted) {
        return;
      }

      final sortedThreads = sortThreadsForDisplay(threads);
      final preferredSelectedId = _preferredSelectedThreadId(sortedThreads);
      final projection = _projectThreads(
        threads: sortedThreads,
        preferredSelectedThreadId: preferredSelectedId,
      );
      setState(() {
        _health = health;
        _threads = sortedThreads;
        _syncSelectionFromProjection(projection);
        _loading = false;
      });
      _debugLog(
        'refresh.completed',
        fields: {
          'threadCount': sortedThreads.length,
          'selectedThreadId': _selectedThreadId,
          'targetThreadId': UiDebugLogger.targetThreadId,
        },
      );
      _ensureRealtimeSubscription(activeConfig);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _health = const BridgeHealth.offline('Codex app-server unreachable');
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openSettings() async {
    final updatedConfig = await Navigator.of(context).push<BridgeConfig>(
      MaterialPageRoute(
        builder: (_) => BridgeSettingsScreen(
          initialConfig: _config,
          configStore: widget.configStore,
          preferencesController: widget.preferencesController,
        ),
      ),
    );

    if (updatedConfig == null || !mounted) {
      return;
    }

    await _closeRealtime();

    setState(() {
      _config = updatedConfig;
      _threads = const [];
      _selectedThreadId = null;
      _desktopDetailThreadIds.clear();
    });

    if (!updatedConfig.isConfigured) {
      setState(() {
        _health = const BridgeHealth.offline('Codex app-server not configured');
        _loading = false;
        _error = null;
      });
      return;
    }

    await _refresh(config: updatedConfig);
  }

  Future<void> _openLogs() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AppServerLogsScreen()));
  }

  Future<void> _ensureRealtimeSubscription(BridgeConfig config) async {
    final currentBaseUrl = _config.baseUrl.trim();
    final nextBaseUrl = config.baseUrl.trim();
    if (!config.isConfigured) {
      await _closeRealtime();
      return;
    }

    if (_realtimeSession != null &&
        currentBaseUrl == nextBaseUrl &&
        _realtimeSubscription != null) {
      return;
    }

    await _closeRealtime();

    try {
      final session = createCodexRepository(config).openThreadEvents();
      _realtimeSession = session;
      _realtimeSubscription = session.stream.listen(
        _handleRealtimeEvent,
        onError: (_) {},
      );
    } catch (_) {}
  }

  Future<void> _closeRealtime() async {
    await _realtimeSubscription?.cancel();
    await _realtimeSession?.close();
    _realtimeSubscription = null;
    _realtimeSession = null;
  }

  void _handleRealtimeEvent(BridgeRealtimeEvent event) {
    if (_isStreamingListEvent(event) || event.type.startsWith('app_server.')) {
      return;
    }

    _realtimeRefreshDebounce?.cancel();
    _realtimeRefreshDebounce = null;

    final previousSelectedThreadId = _selectedThreadId;
    final previousById = <String, CodexThreadSummary>{
      for (final thread in _threads) thread.id: thread,
    };
    final projected = _threads
        .map((thread) => projectRealtimeStatusOnThread(thread, event))
        .toList(growable: false);
    final nextSelectedThreadId = _nextSelectedThreadIdForRealtimeEvent(
      event,
      previousById: previousById,
      projectedThreads: projected,
    );
    final sortedThreads = sortThreadsForDisplay(projected);
    final projection = _projectThreads(
      threads: sortedThreads,
      preferredSelectedThreadId: nextSelectedThreadId,
    );
    if (!threadSummaryListsEquivalent(_threads, sortedThreads) ||
        _selectedThreadId != projection.selectedThreadId) {
      setState(() {
        _threads = sortedThreads;
        _syncSelectionFromProjection(projection);
      });
    }
    _debugLog(
      'realtime.event',
      fields: {
        'eventType': event.type,
        'eventThreadId': realtimeEventThreadId(event),
        'selectedThreadId.before': previousSelectedThreadId,
        'selectedThreadId.after': _selectedThreadId,
        'autoFollow': previousSelectedThreadId != _selectedThreadId,
      },
    );

    if (!_shouldRefreshThreadList(event)) {
      return;
    }

    _realtimeRefreshDebounce?.cancel();
    _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 420), () {
      unawaited(_refreshThreadsQuietly());
    });
  }

  String? _nextSelectedThreadIdForRealtimeEvent(
    BridgeRealtimeEvent event, {
    required Map<String, CodexThreadSummary> previousById,
    required List<CodexThreadSummary> projectedThreads,
  }) {
    final currentSelectedId = _selectedThreadId;
    final eventThreadId = realtimeEventThreadId(event);
    if (event.type != 'thread.status' ||
        realtimeEventThreadStatusType(event) != 'active' ||
        eventThreadId == null) {
      return currentSelectedId;
    }

    CodexThreadSummary? nextActiveThread;
    for (final thread in projectedThreads) {
      if (thread.id == eventThreadId) {
        nextActiveThread = thread;
        break;
      }
    }
    if (nextActiveThread == null) {
      return currentSelectedId;
    }

    final currentSelected = currentSelectedId == null
        ? null
        : previousById[currentSelectedId];
    if (currentSelected == null || currentSelected.id == eventThreadId) {
      return eventThreadId;
    }

    final currentWorkspace = normalizeWorkspacePath(currentSelected.cwd);
    final nextWorkspace = normalizeWorkspacePath(nextActiveThread.cwd);
    if (currentWorkspace != null &&
        nextWorkspace != null &&
        currentWorkspace != nextWorkspace) {
      return currentSelectedId;
    }

    if (currentSelected.status != 'active') {
      return eventThreadId;
    }
    return currentSelectedId;
  }

  String? _preferredSelectedThreadId(List<CodexThreadSummary> threads) {
    final targetThreadId = UiDebugLogger.targetThreadId;
    if (targetThreadId != null &&
        threads.any((thread) => thread.id == targetThreadId)) {
      return targetThreadId;
    }
    return _selectedThreadId;
  }

  void _debugLog(String message, {Map<String, Object?> fields = const {}}) {
    final selectedThreadId = _selectedThreadId;
    if (!UiDebugLogger.matchesThread(selectedThreadId) &&
        !UiDebugLogger.matchesThread(UiDebugLogger.targetThreadId)) {
      return;
    }
    UiDebugLogger.log(
      'ThreadList',
      message,
      threadId: UiDebugLogger.targetThreadId ?? selectedThreadId,
      fields: fields,
    );
  }

  bool _shouldRefreshThreadList(BridgeRealtimeEvent event) {
    if (_isStreamingListEvent(event)) {
      return false;
    }

    if (event.type.startsWith('app_server.')) {
      return false;
    }

    if (event.type == 'thread.status') {
      return true;
    }

    return realtimeEventThreadId(event) != null ||
        event.type == 'approval.request' ||
        event.type == 'user.input.request' ||
        event.type == 'mcp.elicitation.request';
  }

  bool _isStreamingListEvent(BridgeRealtimeEvent event) {
    final method = realtimeEventMethod(event) ?? '';
    return method == 'item/agentMessage/delta' ||
        method == 'item/plan/delta' ||
        method == 'item/commandExecution/outputDelta' ||
        method == 'item/fileChange/outputDelta' ||
        method == 'item/reasoning/summaryTextDelta' ||
        method == 'item/reasoning/textDelta' ||
        method == 'thread/realtime/transcriptUpdated' ||
        event.type.endsWith('.delta');
  }

  Future<void> _refreshThreadsQuietly() async {
    if (!_config.isConfigured || !mounted) {
      return;
    }

    final repository = createCodexRepository(_config);

    try {
      final threads = await repository.listThreads();
      if (!mounted) {
        return;
      }

      final currentById = <String, CodexThreadSummary>{
        for (final thread in _threads) thread.id: thread,
      };
      final mergedThreads = threads
          .map((thread) {
            final current = currentById[thread.id];
            if (current == null) {
              return thread;
            }
            var next = thread;
            if (next.createdAt == null && current.createdAt != null) {
              next = next.copyWith(createdAt: current.createdAt);
            }
            if (current.status == 'active' && next.status != 'active') {
              return next.copyWith(
                status: 'active',
                updatedAt: _laterThreadTimestamp(
                  next.updatedAt,
                  current.updatedAt,
                ),
              );
            }
            return next;
          })
          .toList(growable: false);
      final sortedThreads = sortThreadsForDisplay(mergedThreads);
      final projection = _projectThreads(threads: sortedThreads);
      if (!threadSummaryListsEquivalent(_threads, sortedThreads) ||
          _selectedThreadId != projection.selectedThreadId) {
        setState(() {
          _threads = sortedThreads;
          _syncSelectionFromProjection(projection);
        });
      }
    } catch (_) {}
  }

  Future<void> _createThread() async {
    if (!_config.isConfigured) {
      await _openSettings();
      return;
    }

    setState(() {
      _creatingThread = true;
      _error = null;
    });

    final repository = createCodexRepository(_config);

    try {
      final models = await repository.listModels();
      if (!mounted) {
        return;
      }

      final draft = await showDialog<_CreateThreadDraft>(
        context: context,
        builder: (_) => _CreateThreadDialog(
          models: models,
          listWorkspaceRoots: repository.listWorkspaceRoots,
          listWorkspaceDirectories: repository.listWorkspaceDirectories,
          getDefaultWorkspacePath: repository.getDefaultWorkspacePath,
        ),
      );
      if (draft == null || !mounted) {
        return;
      }

      final bundle = await repository.createThread(
        input: [CodexInputPart.text(draft.message)],
        mode: draft.mode,
        model: draft.modelId,
        cwd: draft.cwd,
      );
      if (!mounted) {
        return;
      }

      await _refresh();
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedThreadId = bundle.thread.id;
        _rememberDesktopDetailThread(bundle.thread.id);
        _expandWorkspaceForThread(bundle.thread);
      });

      final wideLayout = MediaQuery.sizeOf(context).width >= 1180;
      if (!wideLayout) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ThreadDetailScreen(
              config: _config,
              thread: bundle.thread,
              selectedThreadId: bundle.thread.id,
              activeThreadId: activeThreadIdOfThreads(_threads),
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _creatingThread = false;
        });
      }
    }
  }

  bool _isThreadArchived(CodexThreadSummary thread) {
    return widget.preferencesController.isThreadArchived(thread.id);
  }

  void _rememberDesktopDetailThread(String? threadId) {
    final normalized = threadId?.trim() ?? '';
    if (normalized.isEmpty) {
      return;
    }
    if (_desktopDetailThreadIds.contains(normalized)) {
      return;
    }
    _desktopDetailThreadIds.add(normalized);
    final overflow = _desktopDetailThreadIds.length - _maxDesktopDetailPanes;
    if (overflow > 0) {
      _desktopDetailThreadIds.removeRange(0, overflow);
    }
  }

  List<CodexThreadSummary> _desktopDetailThreads(
    List<CodexThreadSummary> visibleThreads, {
    required CodexThreadSummary selectedThread,
  }) {
    final byId = <String, CodexThreadSummary>{
      for (final thread in visibleThreads) thread.id: thread,
    };
    final orderedIds = <String>[
      for (final threadId in _desktopDetailThreadIds)
        if (byId.containsKey(threadId)) threadId,
      if (!_desktopDetailThreadIds.contains(selectedThread.id))
        selectedThread.id,
    ];
    return orderedIds
        .map((threadId) => byId[threadId])
        .whereType<CodexThreadSummary>()
        .toList(growable: false);
  }

  bool _isWorkspaceCollapsed(String? cwd) {
    return _collapsedWorkspaceKeys.contains(workspaceGroupKey(cwd));
  }

  void _toggleWorkspaceCollapsed(String? cwd) {
    final key = workspaceGroupKey(cwd);
    setState(() {
      if (_collapsedWorkspaceKeys.contains(key)) {
        _collapsedWorkspaceKeys.remove(key);
      } else {
        _collapsedWorkspaceKeys.add(key);
      }
    });
  }

  void _expandWorkspaceForThread(CodexThreadSummary? thread) {
    if (thread == null) {
      return;
    }
    _collapsedWorkspaceKeys.remove(workspaceGroupKey(thread.cwd));
  }

  Future<void> _toggleThreadArchived(CodexThreadSummary thread) async {
    final wasArchived = _isThreadArchived(thread);
    await widget.preferencesController.toggleThreadArchived(thread.id);
    if (!mounted) {
      return;
    }

    final strings = context.strings;
    final nextPreferredSelectedId = _selectedThreadId == thread.id
        ? null
        : _selectedThreadId;
    final projection = ThreadListProjection(
      threads: _threads,
      preferredSelectedThreadId: nextPreferredSelectedId,
      showArchivedThreads: false,
      showAllWorkspaces: true,
      isThreadArchived: _isThreadArchived,
    );
    setState(() {
      _syncSelectionFromProjection(projection);
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            wasArchived
                ? strings.text('Session restored from archive.', '会话已从归档中恢复。')
                : strings.text('Session archived.', '会话已归档。'),
          ),
          action: SnackBarAction(
            label: strings.text('Undo', '撤销'),
            onPressed: () {
              unawaited(_toggleThreadArchived(thread));
            },
          ),
        ),
      );
  }

  void _openThread(CodexThreadSummary thread, {required bool wideLayout}) {
    if (wideLayout) {
      setState(() {
        _selectedThreadId = thread.id;
        _rememberDesktopDetailThread(thread.id);
        _expandWorkspaceForThread(thread);
      });
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadDetailScreen(
          config: _config,
          thread: thread,
          selectedThreadId: thread.id,
          activeThreadId: activeThreadIdOfThreads(_threads),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projection = _projectThreads();
    final strings = context.strings;
    final host = Uri.tryParse(_config.baseUrl)?.host;
    final desktopWorkspace = useDesktopWorkspaceShell(context);
    final showDesktopShell =
        desktopWorkspace && MediaQuery.sizeOf(context).width >= 1180;
    final visibleThreads = projection.visibleThreads;
    final selectedThread = projection.selectedThread;
    final currentProvider = projection.currentProvider;
    final emptyThreadListMessage = strings.text(
      'No sessions returned by the app-server yet.',
      'App-server 还没有返回任何会话。',
    );
    final effectiveSelectedThreadId =
        selectedThread?.id ??
        (visibleThreads.isNotEmpty
            ? visibleThreads.first.id
            : _selectedThreadId);
    _debugLog(
      'build',
      fields: {
        'selectedThreadId': effectiveSelectedThreadId,
        'selectedThreadStatus': selectedThread?.status,
        'activeThreadId': activeThreadIdOfThreads(_threads),
        'visibleThreadCount': visibleThreads.length,
      },
    );

    return Scaffold(
      appBar: showDesktopShell
          ? null
          : AppBar(
              title: _ConnectionAppBarTitle(
                currentProvider: currentProvider,
                configured: _config.isConfigured,
                health: _health,
                loading: _loading,
              ),
              actions: [
                IconButton(
                  onPressed: _config.isConfigured
                      ? () {
                          unawaited(_refresh());
                        }
                      : null,
                  icon: const Icon(Icons.refresh),
                  tooltip: strings.text('Refresh', '刷新'),
                ),
                IconButton(
                  onPressed: _config.isConfigured && !_creatingThread
                      ? () {
                          unawaited(_createThread());
                        }
                      : null,
                  icon: const Icon(Icons.add_comment_outlined),
                  tooltip: strings.text('New session', '新建会话'),
                ),
                IconButton(
                  onPressed: () {
                    unawaited(_openLogs());
                  },
                  icon: const Icon(Icons.receipt_long_outlined),
                  tooltip: strings.text('App-server logs', 'App-server 日志'),
                ),
                IconButton(
                  onPressed: () {
                    unawaited(_openSettings());
                  },
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: strings.text('Codex settings', 'Codex 设置'),
                ),
              ],
            ),
      floatingActionButton: _config.isConfigured && !showDesktopShell
          ? FloatingActionButton.extended(
              onPressed: _creatingThread
                  ? null
                  : () {
                      unawaited(_createThread());
                    },
              icon: _creatingThread
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_comment_outlined),
              label: Text(strings.text('New Session', '新建会话')),
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wideLayout = constraints.maxWidth >= 1180;
            if (wideLayout && desktopWorkspace) {
              return Theme(
                data: buildDesktopWorkspaceTheme(
                  Theme.of(context),
                  locale: Localizations.localeOf(context),
                ),
                child: _WindowsDesktopWorkspace(
                  configured: _config.isConfigured,
                  host: host,
                  health: _health,
                  threads: visibleThreads,
                  selectedThreadId: effectiveSelectedThreadId,
                  currentProvider: currentProvider,
                  loading: _loading,
                  creatingThread: _creatingThread,
                  error: _error,
                  emptyMessage: emptyThreadListMessage,
                  onConfigure: _openSettings,
                  onOpenLogs: _openLogs,
                  onRefresh: _refresh,
                  onCreateThread: _createThread,
                  collapsedWorkspaceKeys: _collapsedWorkspaceKeys,
                  onToggleWorkspaceCollapsed: _toggleWorkspaceCollapsed,
                  onSelectThread: (thread) {
                    _openThread(thread, wideLayout: true);
                  },
                  onToggleThreadArchived: _toggleThreadArchived,
                  isThreadArchived: _isThreadArchived,
                  detail: _buildDesktopDetail(
                    visibleThreads,
                    windowsStyle: true,
                  ),
                ),
              );
            }

            if (wideLayout) {
              return _DesktopWorkspace(
                configured: _config.isConfigured,
                host: host,
                health: _health,
                threads: visibleThreads,
                selectedThreadId: effectiveSelectedThreadId,
                currentProvider: currentProvider,
                loading: _loading,
                error: _error,
                emptyMessage: emptyThreadListMessage,
                onConfigure: _openSettings,
                onOpenLogs: _openLogs,
                onRefresh: _refresh,
                collapsedWorkspaceKeys: _collapsedWorkspaceKeys,
                onToggleWorkspaceCollapsed: _toggleWorkspaceCollapsed,
                onSelectThread: (thread) {
                  _openThread(thread, wideLayout: true);
                },
                onToggleThreadArchived: _toggleThreadArchived,
                isThreadArchived: _isThreadArchived,
                detail: _buildDesktopDetail(visibleThreads),
              );
            }

            return RefreshIndicator(
              onRefresh: _config.isConfigured ? () => _refresh() : () async {},
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    _MessagePanel(
                      title: strings.text(
                        'App-server request failed',
                        'App-server 请求失败',
                      ),
                      message: _error!,
                      accent: const Color(0xFFFFF1F2),
                      actionLabel: strings.text('Retry', '重试'),
                      onAction: _refresh,
                    )
                  else if (!_config.isConfigured)
                    _MessagePanel(
                      title: strings.text('Configure Codex', '配置 Codex'),
                      message: strings.text(
                        'This app needs the local Codex app-server URL before it can load Codex sessions.',
                        '应用需要本机 Codex app-server 的 URL，才能加载 Codex 会话。',
                      ),
                      actionLabel: strings.text(
                        'Open Codex settings',
                        '打开 Codex 设置',
                      ),
                      onAction: _openSettings,
                    )
                  else if (_loading && _threads.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 56),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (visibleThreads.isEmpty)
                    _MessagePanel(
                      title: strings.text('No sessions yet', '还没有会话'),
                      message: strings.text(
                        'The app-server is reachable, but it did not return any threads.',
                        'App-server 已连通，但当前没有返回任何线程。',
                      ),
                    )
                  else
                    ...workspaceThreadGroups(visibleThreads).map(
                      (group) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _WorkspaceThreadGroupSection(
                          group: group,
                          collapsed: _isWorkspaceCollapsed(group.cwd),
                          compact: false,
                          sidebarStyle: false,
                          selectedThreadId: effectiveSelectedThreadId,
                          onToggleCollapsed: () {
                            _toggleWorkspaceCollapsed(group.cwd);
                          },
                          onSelectThread: (thread) {
                            _openThread(thread, wideLayout: false);
                          },
                          onToggleThreadArchived: _toggleThreadArchived,
                          isThreadArchived: _isThreadArchived,
                          spacing: 10,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDesktopDetail(
    List<CodexThreadSummary> visibleThreads, {
    bool windowsStyle = false,
  }) {
    final strings = context.strings;
    final selectedThread = selectedThreadForThreads(
      visibleThreads,
      selectedThreadId: _selectedThreadId,
    );
    if (_error != null) {
      return _MessagePanel(
        title: strings.text('App-server request failed', 'App-server 请求失败'),
        message: _error!,
        accent: windowsStyle
            ? const Color(0xFF2A1416)
            : const Color(0xFFFFF1F2),
        actionLabel: strings.text('Retry', '重试'),
        onAction: _refresh,
      );
    }

    if (!_config.isConfigured) {
      return _MessagePanel(
        title: strings.text('Configure Codex', '配置 Codex'),
        message: strings.text(
          'Point this client at your local Codex app-server before loading sessions.',
          '先把客户端指向本机 Codex app-server，再加载会话。',
        ),
        actionLabel: strings.text('Open Codex settings', '打开 Codex 设置'),
        onAction: _openSettings,
      );
    }

    if (_loading && visibleThreads.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (selectedThread == null) {
      return const _DesktopPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(windowsStyle ? 20 : 32),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: panelBackgroundColor(Theme.of(context)),
          border: Border.all(color: borderColor(Theme.of(context))),
          borderRadius: BorderRadius.circular(windowsStyle ? 20 : 32),
        ),
        child: _DesktopDetailStack(
          config: _config,
          threads: _desktopDetailThreads(
            visibleThreads,
            selectedThread: selectedThread,
          ),
          selectedThreadId: selectedThread.id,
          activeThreadId: activeThreadIdOfThreads(_threads),
          workspaceStyle: windowsStyle,
        ),
      ),
    );
  }
}

class _DesktopDetailStack extends StatelessWidget {
  const _DesktopDetailStack({
    required this.config,
    required this.threads,
    required this.selectedThreadId,
    required this.activeThreadId,
    required this.workspaceStyle,
  });

  final BridgeConfig config;
  final List<CodexThreadSummary> threads;
  final String selectedThreadId;
  final String? activeThreadId;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = threads.indexWhere(
      (thread) => thread.id == selectedThreadId,
    );
    if (threads.isEmpty || selectedIndex < 0) {
      return const SizedBox.shrink();
    }

    return IndexedStack(
      index: selectedIndex,
      sizing: StackFit.expand,
      children: [
        for (final thread in threads)
          ThreadDetailPane(
            key: ValueKey('${config.baseUrl}:${thread.id}'),
            config: config,
            thread: thread,
            selectedThreadId: selectedThreadId,
            activeThreadId: activeThreadId,
            workspaceStyle: workspaceStyle,
          ),
      ],
    );
  }
}

DateTime? _laterThreadTimestamp(DateTime? left, DateTime? right) {
  if (left == null) {
    return right;
  }
  if (right == null) {
    return left;
  }
  return left.isAfter(right) ? left : right;
}

class _WindowsDesktopWorkspace extends StatelessWidget {
  const _WindowsDesktopWorkspace({
    required this.configured,
    required this.host,
    required this.health,
    required this.threads,
    required this.selectedThreadId,
    required this.currentProvider,
    required this.loading,
    required this.creatingThread,
    required this.error,
    required this.emptyMessage,
    required this.onConfigure,
    required this.onOpenLogs,
    required this.onRefresh,
    required this.onCreateThread,
    required this.collapsedWorkspaceKeys,
    required this.onToggleWorkspaceCollapsed,
    required this.onSelectThread,
    required this.onToggleThreadArchived,
    required this.isThreadArchived,
    required this.detail,
  });

  final bool configured;
  final String? host;
  final BridgeHealth health;
  final List<CodexThreadSummary> threads;
  final String? selectedThreadId;
  final String? currentProvider;
  final bool loading;
  final bool creatingThread;
  final String? error;
  final String emptyMessage;
  final Future<void> Function() onConfigure;
  final Future<void> Function() onOpenLogs;
  final Future<void> Function({BridgeConfig? config}) onRefresh;
  final Future<void> Function() onCreateThread;
  final Set<String> collapsedWorkspaceKeys;
  final ValueChanged<String?> onToggleWorkspaceCollapsed;
  final ValueChanged<CodexThreadSummary> onSelectThread;
  final Future<void> Function(CodexThreadSummary thread) onToggleThreadArchived;
  final bool Function(CodexThreadSummary thread) isThreadArchived;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Row(
          children: [
            SizedBox(
              width: 328,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: mutedPanelBackgroundColor(theme),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: borderColor(theme)),
                ),
                child: Column(
                  children: [
                    _WindowsSidebarHeader(
                      configured: configured,
                      host: host,
                      health: health,
                      currentProvider: currentProvider,
                      threadCount: threads.length,
                      loading: loading,
                      creatingThread: creatingThread,
                      onConfigure: onConfigure,
                      onOpenLogs: onOpenLogs,
                      onRefresh: onRefresh,
                      onCreateThread: onCreateThread,
                    ),
                    Expanded(
                      child: _WindowsThreadList(
                        configured: configured,
                        error: error,
                        loading: loading,
                        threads: threads,
                        selectedThreadId: selectedThreadId,
                        onSelectThread: onSelectThread,
                        onToggleThreadArchived: onToggleThreadArchived,
                        isThreadArchived: isThreadArchived,
                        collapsedWorkspaceKeys: collapsedWorkspaceKeys,
                        onToggleWorkspaceCollapsed: onToggleWorkspaceCollapsed,
                        emptyMessage: emptyMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: detail),
          ],
        ),
      ),
    );
  }
}

class _WindowsSidebarHeader extends StatelessWidget {
  const _WindowsSidebarHeader({
    required this.configured,
    required this.host,
    required this.health,
    required this.currentProvider,
    required this.threadCount,
    required this.loading,
    required this.creatingThread,
    required this.onConfigure,
    required this.onOpenLogs,
    required this.onRefresh,
    required this.onCreateThread,
  });

  final bool configured;
  final String? host;
  final BridgeHealth health;
  final String? currentProvider;
  final int threadCount;
  final bool loading;
  final bool creatingThread;
  final Future<void> Function() onConfigure;
  final Future<void> Function() onOpenLogs;
  final Future<void> Function({BridgeConfig? config}) onRefresh;
  final Future<void> Function() onCreateThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final healthLabel = _humanize(context, health.label);
    final providerLabel = _providerLabel(context, currentProvider);
    final subtitle = configured
        ? strings.text(
            '$threadCount session${threadCount == 1 ? '' : 's'} · $healthLabel',
            '$threadCount 个会话 · $healthLabel',
          )
        : strings.text(
            'Connect to the local Codex app-server to browse sessions.',
            '连接到本机 Codex app-server 以浏览会话。',
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text('Current provider', '当前 Provider'),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: secondaryTextColor(theme),
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      providerLabel,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryTextColor(theme),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _WindowsHeaderAction(
                tooltip: strings.text('New session', '新建会话'),
                onPressed: configured && !creatingThread
                    ? () {
                        unawaited(onCreateThread());
                      }
                    : null,
                child: creatingThread
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_comment_outlined, size: 18),
              ),
              const SizedBox(width: 8),
              _WindowsHeaderAction(
                tooltip: strings.text('Refresh', '刷新'),
                onPressed: configured
                    ? () {
                        unawaited(onRefresh());
                      }
                    : null,
                child: Icon(loading ? Icons.sync : Icons.refresh, size: 18),
              ),
              const SizedBox(width: 8),
              _WindowsHeaderAction(
                tooltip: strings.text('App-server logs', 'App-server 日志'),
                onPressed: () {
                  unawaited(onOpenLogs());
                },
                child: const Icon(Icons.receipt_long_outlined, size: 18),
              ),
              const SizedBox(width: 8),
              _WindowsHeaderAction(
                tooltip: strings.text('Codex settings', 'Codex 设置'),
                onPressed: () {
                  unawaited(onConfigure());
                },
                child: const Icon(Icons.settings_outlined, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _WindowsMetaChip(
                label:
                    host ?? strings.text('local app-server', '本机 app-server'),
              ),
              _WindowsMetaChip(label: healthLabel),
              _WindowsMetaChip(
                label: strings.text(
                  '$threadCount sessions',
                  '$threadCount 个会话',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _ConnectionIndicatorState { connected, disconnected, connecting }

class _ConnectionAppBarTitle extends StatelessWidget {
  const _ConnectionAppBarTitle({
    required this.currentProvider,
    required this.configured,
    required this.health,
    required this.loading,
  });

  final String? currentProvider;
  final bool configured;
  final BridgeHealth health;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final title = _providerLabel(context, currentProvider);
    final indicatorState = _connectionIndicatorState(
      configured: configured,
      health: health,
      loading: loading,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ConnectionStatusDot(state: indicatorState),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ConnectionStatusDot extends StatefulWidget {
  const _ConnectionStatusDot({required this.state});

  final _ConnectionIndicatorState state;

  @override
  State<_ConnectionStatusDot> createState() => _ConnectionStatusDotState();
}

class _ConnectionStatusDotState extends State<_ConnectionStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _ConnectionStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.state == _ConnectionIndicatorState.connecting) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.state) {
      _ConnectionIndicatorState.connected => const Color(0xFF16A34A),
      _ConnectionIndicatorState.disconnected => const Color(0xFF9CA3AF),
      _ConnectionIndicatorState.connecting => const Color(0xFFDC2626),
    };

    if (widget.state != _ConnectionIndicatorState.connecting) {
      return _Dot(color: color, opacity: 1);
    }

    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_controller),
      child: _Dot(color: color, opacity: 1),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

_ConnectionIndicatorState _connectionIndicatorState({
  required bool configured,
  required BridgeHealth health,
  required bool loading,
}) {
  if (!configured) {
    return _ConnectionIndicatorState.disconnected;
  }
  if (loading) {
    return _ConnectionIndicatorState.connecting;
  }
  if (health.reachable) {
    return _ConnectionIndicatorState.connected;
  }
  return _ConnectionIndicatorState.disconnected;
}

class _WindowsHeaderAction extends StatelessWidget {
  const _WindowsHeaderAction({
    required this.child,
    this.onPressed,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      icon: child,
      style: IconButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        backgroundColor: panelBackgroundColor(Theme.of(context)),
        disabledBackgroundColor: panelBackgroundColor(
          Theme.of(context),
        ).withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: borderColor(Theme.of(context))),
      ),
      tooltip: tooltip,
    );

    return SizedBox(width: 42, height: 42, child: button);
  }
}

class _WindowsMetaChip extends StatelessWidget {
  const _WindowsMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: secondaryTextColor(theme),
        ),
      ),
    );
  }
}

class _WindowsThreadList extends StatelessWidget {
  const _WindowsThreadList({
    required this.configured,
    required this.error,
    required this.loading,
    required this.threads,
    required this.selectedThreadId,
    required this.onSelectThread,
    required this.onToggleThreadArchived,
    required this.isThreadArchived,
    required this.collapsedWorkspaceKeys,
    required this.onToggleWorkspaceCollapsed,
    required this.emptyMessage,
  });

  final bool configured;
  final String? error;
  final bool loading;
  final List<CodexThreadSummary> threads;
  final String? selectedThreadId;
  final ValueChanged<CodexThreadSummary> onSelectThread;
  final Future<void> Function(CodexThreadSummary thread) onToggleThreadArchived;
  final bool Function(CodexThreadSummary thread) isThreadArchived;
  final Set<String> collapsedWorkspaceKeys;
  final ValueChanged<String?> onToggleWorkspaceCollapsed;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (!configured) {
      return _CenteredHint(
        message: context.strings.text(
          'Configure a Codex app-server to list sessions.',
          '先配置 Codex app-server，才能列出会话。',
        ),
      );
    }

    if (error != null && threads.isEmpty) {
      return _CenteredHint(message: error!);
    }

    if (loading && threads.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (threads.isEmpty) {
      return _CenteredHint(message: emptyMessage);
    }

    final groups = workspaceThreadGroups(threads);
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          _WorkspaceThreadGroupSection(
            group: groups[index],
            compact: true,
            sidebarStyle: true,
            collapsed: collapsedWorkspaceKeys.contains(
              workspaceGroupKey(groups[index].cwd),
            ),
            selectedThreadId: selectedThreadId,
            onToggleCollapsed: () {
              onToggleWorkspaceCollapsed(groups[index].cwd);
            },
            onSelectThread: onSelectThread,
            onToggleThreadArchived: onToggleThreadArchived,
            isThreadArchived: isThreadArchived,
            spacing: 2,
          ),
        ],
      ],
    );
  }
}

class _SidebarThreadTile extends StatelessWidget {
  const _SidebarThreadTile({
    required this.thread,
    required this.archived,
    required this.selected,
    required this.onTap,
    required this.onToggleArchived,
  });

  final CodexThreadSummary thread;
  final bool archived;
  final bool selected;
  final VoidCallback onTap;
  final Future<void> Function() onToggleArchived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final strings = context.strings;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: selected ? selectionFillColor(theme) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.40)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 48,
                decoration: BoxDecoration(
                  color: selected ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            thread.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _ThreadPill(
                          label: _humanize(context, thread.status),
                          status: thread.status,
                        ),
                        const SizedBox(width: 2),
                        _ThreadArchiveButton(
                          archived: archived,
                          compact: true,
                          onPressed: onToggleArchived,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _threadCardSubtitle(thread),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: secondaryTextColor(theme),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (thread.cwd != null)
                          workspaceLabelForDisplay(context, thread.cwd),
                        if (thread.updatedAt != null)
                          _formatRelative(context, thread.updatedAt),
                        shortThreadId(thread.id),
                        if (thread.itemCount != null)
                          strings.text(
                            '${thread.itemCount} items',
                            '${thread.itemCount} 项',
                          ),
                      ].join('  ·  '),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: secondaryTextColor(theme),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopWorkspace extends StatelessWidget {
  const _DesktopWorkspace({
    required this.configured,
    required this.host,
    required this.health,
    required this.threads,
    required this.selectedThreadId,
    required this.currentProvider,
    required this.loading,
    required this.error,
    required this.emptyMessage,
    required this.onConfigure,
    required this.onOpenLogs,
    required this.onRefresh,
    required this.collapsedWorkspaceKeys,
    required this.onToggleWorkspaceCollapsed,
    required this.onSelectThread,
    required this.onToggleThreadArchived,
    required this.isThreadArchived,
    required this.detail,
  });

  final bool configured;
  final String? host;
  final BridgeHealth health;
  final List<CodexThreadSummary> threads;
  final String? selectedThreadId;
  final String? currentProvider;
  final bool loading;
  final String? error;
  final String emptyMessage;
  final Future<void> Function() onConfigure;
  final Future<void> Function() onOpenLogs;
  final Future<void> Function({BridgeConfig? config}) onRefresh;
  final Set<String> collapsedWorkspaceKeys;
  final ValueChanged<String?> onToggleWorkspaceCollapsed;
  final ValueChanged<CodexThreadSummary> onSelectThread;
  final Future<void> Function(CodexThreadSummary thread) onToggleThreadArchived;
  final bool Function(CodexThreadSummary thread) isThreadArchived;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final providerLabel = _providerLabel(context, currentProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 380,
            child: _PanelShell(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.text('Current provider', '当前 Provider'),
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: secondaryTextColor(
                                        Theme.of(context),
                                      ),
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                providerLabel,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                configured
                                    ? strings.text(
                                        '${threads.length} sessions · ${host ?? strings.text('local app-server', '本机 app-server')}',
                                        '${threads.length} 个会话 · ${host ?? strings.text('本机 app-server', '本机 app-server')}',
                                      )
                                    : strings.text(
                                        'Waiting for app-server setup',
                                        '等待 app-server 配置',
                                      ),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: configured
                              ? () {
                                  unawaited(onRefresh());
                                }
                              : null,
                          icon: const Icon(Icons.sync),
                          tooltip: strings.text('Refresh threads', '刷新线程'),
                        ),
                        IconButton(
                          onPressed: () {
                            unawaited(onOpenLogs());
                          },
                          icon: const Icon(Icons.receipt_long_outlined),
                          tooltip: strings.text(
                            'App-server logs',
                            'App-server 日志',
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            unawaited(onConfigure());
                          },
                          icon: const Icon(Icons.settings_outlined),
                          tooltip: strings.text('Codex settings', 'Codex 设置'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _DesktopThreadList(
                      configured: configured,
                      error: error,
                      loading: loading,
                      threads: threads,
                      selectedThreadId: selectedThreadId,
                      onSelectThread: onSelectThread,
                      onToggleThreadArchived: onToggleThreadArchived,
                      isThreadArchived: isThreadArchived,
                      collapsedWorkspaceKeys: collapsedWorkspaceKeys,
                      onToggleWorkspaceCollapsed: onToggleWorkspaceCollapsed,
                      emptyMessage: emptyMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(child: detail),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _BridgeHero extends StatelessWidget {
  const _BridgeHero({
    required this.configured,
    required this.host,
    required this.health,
    required this.onConfigure,
  });

  final bool configured;
  final String? host;
  final BridgeHealth health;
  final Future<void> Function() onConfigure;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          colors: [Color(0xFF164E63), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              configured
                  ? (host ??
                        strings.text('Configured app-server', '已配置 app-server'))
                  : strings.text('App-server not configured', 'App-server 未配置'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              configured
                  ? strings.text(
                      'Sessions and live updates are fetched from the local Codex app-server.',
                      '会话与实时更新都从本机 Codex app-server 拉取。',
                    )
                  : strings.text(
                      'Add your app-server URL before trying to load sessions.',
                      '先填写 app-server URL，再尝试加载会话。',
                    ),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.86),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _HeroChip(
                  label: strings.text('Codex', 'Codex'),
                  value: strings.humanizeMachineLabel(
                    configured ? 'ready' : 'missing',
                  ),
                ),
                _HeroChip(
                  label: strings.text('Health', '状态'),
                  value: _humanize(context, health.label),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: () {
                unawaited(onConfigure());
              },
              icon: const Icon(Icons.settings_outlined),
              label: Text(
                configured
                    ? strings.text('Edit Codex', '编辑 Codex')
                    : strings.text('Configure Codex', '配置 Codex'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopThreadList extends StatelessWidget {
  const _DesktopThreadList({
    required this.configured,
    required this.error,
    required this.loading,
    required this.threads,
    required this.selectedThreadId,
    required this.onSelectThread,
    required this.onToggleThreadArchived,
    required this.isThreadArchived,
    required this.collapsedWorkspaceKeys,
    required this.onToggleWorkspaceCollapsed,
    required this.emptyMessage,
  });

  final bool configured;
  final String? error;
  final bool loading;
  final List<CodexThreadSummary> threads;
  final String? selectedThreadId;
  final ValueChanged<CodexThreadSummary> onSelectThread;
  final Future<void> Function(CodexThreadSummary thread) onToggleThreadArchived;
  final bool Function(CodexThreadSummary thread) isThreadArchived;
  final Set<String> collapsedWorkspaceKeys;
  final ValueChanged<String?> onToggleWorkspaceCollapsed;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (!configured) {
      return _CenteredHint(
        message: context.strings.text(
          'Configure a Codex app-server to list sessions.',
          '先配置 Codex app-server，才能列出会话。',
        ),
      );
    }

    if (error != null && threads.isEmpty) {
      return _CenteredHint(message: error!);
    }

    if (loading && threads.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (threads.isEmpty) {
      return _CenteredHint(message: emptyMessage);
    }

    final groups = workspaceThreadGroups(threads);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          if (index > 0) const SizedBox(height: 18),
          _WorkspaceThreadGroupSection(
            group: groups[index],
            compact: false,
            sidebarStyle: false,
            collapsed: collapsedWorkspaceKeys.contains(
              workspaceGroupKey(groups[index].cwd),
            ),
            selectedThreadId: selectedThreadId,
            onToggleCollapsed: () {
              onToggleWorkspaceCollapsed(groups[index].cwd);
            },
            onSelectThread: onSelectThread,
            onToggleThreadArchived: onToggleThreadArchived,
            isThreadArchived: isThreadArchived,
            spacing: 8,
          ),
        ],
      ],
    );
  }
}

class _ThreadEntriesList extends StatelessWidget {
  const _ThreadEntriesList({
    required this.threads,
    required this.onSelectThread,
    required this.onToggleThreadArchived,
    required this.isThreadArchived,
    this.selectedThreadId,
    this.sidebarStyle = false,
    this.spacing = 8,
  });

  final List<CodexThreadSummary> threads;
  final String? selectedThreadId;
  final ValueChanged<CodexThreadSummary> onSelectThread;
  final Future<void> Function(CodexThreadSummary thread) onToggleThreadArchived;
  final bool Function(CodexThreadSummary thread) isThreadArchived;
  final bool sidebarStyle;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < threads.length; index += 1)
          Padding(
            padding: EdgeInsets.only(
              bottom: index == threads.length - 1 ? 0 : spacing,
            ),
            child: sidebarStyle
                ? _SidebarThreadTile(
                    thread: threads[index],
                    archived: isThreadArchived(threads[index]),
                    selected: threads[index].id == selectedThreadId,
                    onTap: () => onSelectThread(threads[index]),
                    onToggleArchived: () =>
                        onToggleThreadArchived(threads[index]),
                  )
                : _ThreadListItem(
                    thread: threads[index],
                    archived: isThreadArchived(threads[index]),
                    selected: threads[index].id == selectedThreadId,
                    onTap: () => onSelectThread(threads[index]),
                    onToggleArchived: () =>
                        onToggleThreadArchived(threads[index]),
                  ),
          ),
      ],
    );
  }
}

class _ThreadListItem extends StatelessWidget {
  const _ThreadListItem({
    required this.thread,
    required this.archived,
    required this.selected,
    required this.onTap,
    required this.onToggleArchived,
  });

  final CodexThreadSummary thread;
  final bool archived;
  final bool selected;
  final VoidCallback onTap;
  final Future<void> Function() onToggleArchived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final metadata = <String>[
      if (thread.cwd != null) workspaceLabelForDisplay(context, thread.cwd),
      if (thread.updatedAt != null) _formatRelative(context, thread.updatedAt),
      'ID ${shortThreadId(thread.id)}',
      if (thread.itemCount != null)
        context.strings.text('${thread.itemCount} items', '${thread.itemCount} 项'),
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(panelRadius(theme) - 6),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: selected
                ? selectionFillColor(theme)
                : panelBackgroundColor(theme),
            borderRadius: BorderRadius.circular(panelRadius(theme) - 6),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.36)
                  : borderColor(theme),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      thread.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ThreadPill(
                    label: _humanize(context, thread.status),
                    status: thread.status,
                    compact: true,
                  ),
                  const SizedBox(width: 2),
                  _ThreadArchiveButton(
                    archived: archived,
                    onPressed: onToggleArchived,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _threadCardSubtitle(thread),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondaryTextColor(theme),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                metadata.join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondaryTextColor(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceThreadGroupSection extends StatelessWidget {
  const _WorkspaceThreadGroupSection({
    required this.group,
    required this.collapsed,
    required this.selectedThreadId,
    required this.onToggleCollapsed,
    required this.onSelectThread,
    required this.onToggleThreadArchived,
    required this.isThreadArchived,
    this.compact = false,
    this.sidebarStyle = false,
    this.spacing = 8,
  });

  final WorkspaceThreadGroup group;
  final bool collapsed;
  final String? selectedThreadId;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<CodexThreadSummary> onSelectThread;
  final Future<void> Function(CodexThreadSummary thread) onToggleThreadArchived;
  final bool Function(CodexThreadSummary thread) isThreadArchived;
  final bool compact;
  final bool sidebarStyle;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final archivedCount = group.threads.where(isThreadArchived).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WorkspaceSectionHeader(
          group: group,
          compact: compact,
          collapsed: collapsed,
          archivedCount: archivedCount,
          onTap: onToggleCollapsed,
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: collapsed
                ? const SizedBox.shrink()
                : Padding(
                    padding: EdgeInsets.only(top: compact ? 4 : 8),
                    child: _ThreadEntriesList(
                      threads: group.threads,
                      selectedThreadId: selectedThreadId,
                      onSelectThread: onSelectThread,
                      onToggleThreadArchived: onToggleThreadArchived,
                      isThreadArchived: isThreadArchived,
                      sidebarStyle: sidebarStyle,
                      spacing: spacing,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _WorkspaceSectionHeader extends StatelessWidget {
  const _WorkspaceSectionHeader({
    required this.group,
    required this.collapsed,
    required this.archivedCount,
    required this.onTap,
    this.compact = false,
  });

  final WorkspaceThreadGroup group;
  final bool collapsed;
  final int archivedCount;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = group.threads.length;
    final summary = archivedCount > 0
        ? context.strings.text(
            '$count sessions · $archivedCount archived',
            '$count 个会话 · $archivedCount 个归档',
          )
        : context.strings.text(
            '$count session${count == 1 ? '' : 's'}',
            '$count 个会话',
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 0,
            vertical: compact ? 4 : 6,
          ),
          child: Row(
            children: [
              Icon(
                collapsed
                    ? Icons.chevron_right_rounded
                    : Icons.expand_more_rounded,
                size: compact ? 18 : 20,
                color: secondaryTextColor(theme),
              ),
              Icon(
                collapsed ? Icons.folder_outlined : Icons.folder_open_outlined,
                size: compact ? 15 : 16,
                color: secondaryTextColor(theme),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  workspaceLabelForDisplay(context, group.cwd),
                  style:
                      (compact
                              ? theme.textTheme.labelLarge
                              : theme.textTheme.titleSmall)
                          ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                summary,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: secondaryTextColor(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String workspaceLabelForDisplay(BuildContext context, String? value) {
  final normalized = normalizeWorkspacePath(value);
  if (normalized == null) {
    return context.strings.text('Unknown workspace', '未知工作区');
  }

  final segments = normalized
      .split(RegExp(r'[\\/]'))
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  return segments.isNotEmpty ? segments.last : normalized;
}

String shortThreadId(String id) {
  final normalized = id.trim();
  if (normalized.length <= 8) {
    return normalized;
  }
  return normalized.substring(normalized.length - 6);
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

String _threadCardSubtitle(CodexThreadSummary thread) {
  final preview = thread.preview.trim();
  return preview.isEmpty ? thread.title : preview;
}

String _modeLabel(BuildContext context, CodexComposerMode mode) {
  return switch (mode) {
    CodexComposerMode.chat => context.strings.text('Read only', '只读'),
    CodexComposerMode.agent => context.strings.text('Edit project', '项目内修改'),
    CodexComposerMode.agentFullAccess => context.strings.text(
      'Full access',
      '完全访问',
    ),
  };
}

class _CreateThreadDraft {
  const _CreateThreadDraft({
    required this.message,
    required this.mode,
    this.modelId,
    this.cwd,
  });

  final String message;
  final CodexComposerMode mode;
  final String? modelId;
  final String? cwd;
}

class _CreateThreadDialog extends StatefulWidget {
  const _CreateThreadDialog({
    required this.models,
    required this.listWorkspaceRoots,
    required this.listWorkspaceDirectories,
    required this.getDefaultWorkspacePath,
  });

  final List<CodexModelOption> models;
  final Future<List<CodexDirectoryEntry>> Function() listWorkspaceRoots;
  final Future<List<CodexDirectoryEntry>> Function(String path)
  listWorkspaceDirectories;
  final Future<String?> Function() getDefaultWorkspacePath;

  @override
  State<_CreateThreadDialog> createState() => _CreateThreadDialogState();
}

class _CreateThreadDialogState extends State<_CreateThreadDialog> {
  late final TextEditingController _messageController;
  late CodexComposerMode _mode;
  String? _selectedModelId;
  String? _selectedCwd;
  String? _defaultWorkspacePath;
  bool _defaultWorkspaceLoading = true;
  List<_DirectoryTreeRoot> _roots = const <_DirectoryTreeRoot>[];
  bool _rootsLoading = true;
  String? _rootsError;
  final Set<String> _expandedPaths = <String>{};
  final Set<String> _loadingPaths = <String>{};
  final Map<String, List<_DirectoryTreeEntry>> _childrenByPath =
      <String, List<_DirectoryTreeEntry>>{};
  final Map<String, String> _errorsByPath = <String, String>{};

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _mode = CodexComposerMode.agent;
    unawaited(_loadDefaultWorkspacePath());
    unawaited(_loadRoots());
    for (final model in widget.models) {
      if (model.isDefault) {
        _selectedModelId = model.id;
        break;
      }
    }
    _selectedModelId ??= widget.models.isNotEmpty
        ? widget.models.first.id
        : null;
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadRoots() async {
    setState(() {
      _rootsLoading = true;
      _rootsError = null;
    });
    try {
      final entries = await widget.listWorkspaceRoots();
      if (!mounted) {
        return;
      }
      setState(() {
        _roots = entries
            .map(
              (entry) => _DirectoryTreeRoot(
                path: entry.path,
                label: entry.label,
              ),
            )
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _rootsError = 'unreadable';
      });
    } finally {
      if (mounted) {
        setState(() {
          _rootsLoading = false;
        });
      }
    }
  }

  Future<void> _loadDefaultWorkspacePath() async {
    setState(() {
      _defaultWorkspaceLoading = true;
    });
    try {
      final path = await widget.getDefaultWorkspacePath();
      if (!mounted) {
        return;
      }
      setState(() {
        _defaultWorkspacePath = path?.trim().isEmpty ?? true ? null : path;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _defaultWorkspacePath = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _defaultWorkspaceLoading = false;
        });
      }
    }
  }

  Future<void> _toggleNode(String path) async {
    if (_expandedPaths.contains(path)) {
      setState(() {
        _expandedPaths.remove(path);
      });
      return;
    }

    setState(() {
      _expandedPaths.add(path);
    });

    if (_childrenByPath.containsKey(path) || _loadingPaths.contains(path)) {
      return;
    }

    await _loadChildren(path);
  }

  Future<void> _loadChildren(String path) async {
    setState(() {
      _loadingPaths.add(path);
      _errorsByPath.remove(path);
    });

    try {
      final entries = await widget.listWorkspaceDirectories(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _childrenByPath[path] = entries
            .map(
              (entry) => _DirectoryTreeEntry(
                path: entry.path,
                name: entry.label,
              ),
            )
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorsByPath[path] = 'unreadable';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPaths.remove(path);
        });
      }
    }
  }

  Widget _buildTreeNode(
    BuildContext context, {
    required String path,
    required String label,
    required int depth,
  }) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final expanded = _expandedPaths.contains(path);
    final loading = _loadingPaths.contains(path);
    final selected = _selectedCwd == path;
    final children = _childrenByPath[path];
    final hasLoadedChildren = children != null;
    final error = _errorsByPath[path];
    final canExpand =
        loading || error != null || (children?.isNotEmpty ?? !hasLoadedChildren);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                _selectedCwd = path;
              });
            },
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: depth * 14.0,
                end: 10,
                top: 8,
                bottom: 8,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: canExpand
                        ? IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 24,
                              height: 24,
                            ),
                            splashRadius: 16,
                            onPressed: () {
                              unawaited(_toggleNode(path));
                            },
                            icon: loading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    expanded
                                        ? Icons.keyboard_arrow_down
                                        : Icons.keyboard_arrow_right,
                                    size: 18,
                                  ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Icon(
                    selected ? Icons.folder_open : Icons.folder_outlined,
                    size: 18,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded && error != null)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: depth * 14.0 + 32,
              top: 2,
              bottom: 6,
            ),
            child: Text(
              strings.text('Unable to read this folder', '无法读取这个目录'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (expanded && children != null && children.isEmpty && error == null)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: depth * 14.0 + 32,
              top: 2,
              bottom: 6,
            ),
            child: Text(
              strings.text('No subfolders', '没有子目录'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (expanded && children != null && children.isNotEmpty)
          ...children.map(
            (child) => _buildTreeNode(
              context,
              path: child.path,
              label: child.name,
              depth: depth + 1,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(strings.text('New Session', '新建会话')),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _messageController,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: strings.text('Prompt', '提示词'),
                  hintText: strings.text(
                    'Tell Codex what to do in the new session',
                    '告诉 Codex 在新会话里要做什么',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (widget.models.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _selectedModelId,
                  items: widget.models
                      .map(
                        (model) => DropdownMenuItem(
                          value: model.id,
                          child: Text(model.displayName),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    setState(() {
                      _selectedModelId = value;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: strings.text('Model', '模型'),
                  ),
                ),
              const SizedBox(height: 14),
              SegmentedButton<CodexComposerMode>(
                segments: CodexComposerMode.values
                    .map(
                      (mode) => ButtonSegment(
                        value: mode,
                        label: Text(_modeLabel(context, mode)),
                      ),
                    )
                    .toList(growable: false),
                selected: {_mode},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) {
                    return;
                  }
                  setState(() {
                    _mode = selection.first;
                  });
                },
              ),
              const SizedBox(height: 14),
              Text(
                strings.text('Workspace', '工作区'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: Icon(
                        _selectedCwd == null
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 20,
                        color: _selectedCwd == null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        strings.text(
                          'Use provider default workspace',
                          '使用 provider 默认工作区',
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedCwd = null;
                        });
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        _defaultWorkspaceLoading
                            ? strings.text(
                                'Loading default workspace...',
                                '正在读取默认工作区...',
                              )
                            : (_defaultWorkspacePath ??
                                  strings.text(
                                    'No default workspace provided',
                                    '未提供默认工作区路径',
                                  )),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (_selectedCwd != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          _selectedCwd!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        strings.text(
                          'Choose from the directory tree',
                          '从目录树选择',
                        ),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: _rootsLoading
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : _rootsError != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  strings.text(
                                    'Unable to load workspaces',
                                    '无法加载工作区',
                                  ),
                                ),
                              ),
                            )
                          : ListView(
                              shrinkWrap: true,
                              children: _roots
                                  .map(
                                    (root) => _buildTreeNode(
                                      context,
                                      path: root.path,
                                      label: root.label,
                                      depth: 0,
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(strings.text('Cancel', '取消')),
        ),
        FilledButton(
          onPressed: () {
            final message = _messageController.text.trim();
            if (message.isEmpty) {
              return;
            }
            Navigator.of(context).pop(
              _CreateThreadDraft(
                message: message,
                mode: _mode,
                modelId: _selectedModelId,
                cwd: _selectedCwd,
              ),
            );
          },
          child: Text(strings.text('Create', '创建')),
        ),
      ],
    );
  }
}

class _DirectoryTreeRoot {
  const _DirectoryTreeRoot({
    required this.path,
    required this.label,
  });

  final String path;
  final String label;
}

class _DirectoryTreeEntry {
  const _DirectoryTreeEntry({
    required this.path,
    required this.name,
  });

  final String path;
  final String name;
}

class _ThreadPill extends StatelessWidget {
  const _ThreadPill({
    required this.label,
    required this.status,
    this.compact = false,
  });

  final String label;
  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _threadPillStyle(theme, status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.borderColor),
      ),
      child: Text(
        label,
        style:
            (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
                ?.copyWith(
                  color: style.foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
      ),
    );
  }
}

_ThreadPillStyle _threadPillStyle(ThemeData theme, String status) {
  final normalized = status.trim().toLowerCase();
  final foreground = switch (normalized) {
    'active' => theme.colorScheme.secondary,
    'idle' => secondaryTextColor(theme),
    'error' || 'failed' => theme.colorScheme.error,
    _ => theme.colorScheme.primary,
  };

  final background = switch (normalized) {
    'idle' =>
      theme.brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.05),
    _ => foreground.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.18 : 0.12,
    ),
  };

  final border = switch (normalized) {
    'idle' =>
      theme.brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.08),
    _ => foreground.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.34 : 0.18,
    ),
  };

  return _ThreadPillStyle(
    foregroundColor: foreground,
    backgroundColor: background,
    borderColor: border,
  );
}

class _ThreadPillStyle {
  const _ThreadPillStyle({
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
  });

  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;
}

class _ThreadArchiveButton extends StatelessWidget {
  const _ThreadArchiveButton({
    required this.archived,
    required this.onPressed,
    this.compact = false,
  });

  final bool archived;
  final Future<void> Function() onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return IconButton(
      onPressed: () {
        unawaited(onPressed());
      },
      icon: Icon(
        archived ? Icons.unarchive_outlined : Icons.archive_outlined,
        size: compact ? 18 : 20,
      ),
      tooltip: archived
          ? strings.text('Restore session', '恢复会话')
          : strings.text('Archive session', '归档会话'),
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      splashRadius: compact ? 18 : 20,
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: panelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(panelRadius(theme)),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.title,
    required this.message,
    this.accent,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final Color? accent;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent ?? panelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(panelRadius(theme)),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  unawaited(onAction!.call());
                },
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _DesktopPlaceholder extends StatelessWidget {
  const _DesktopPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _PanelShell(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 42,
                color: secondaryTextColor(theme),
              ),
              const SizedBox(height: 14),
              Text(
                context.strings.text(
                  'Select a session to inspect messages and operations.',
                  '选择一个会话以查看消息和操作。',
                ),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: secondaryTextColor(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
