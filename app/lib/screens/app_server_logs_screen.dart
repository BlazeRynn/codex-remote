import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_strings.dart';
import '../app/workspace_theme.dart';
import '../services/app_server_log_store.dart';

enum _AppServerLogFilter { all, request, response, error, event }

class AppServerLogsScreen extends StatefulWidget {
  AppServerLogsScreen({super.key, AppServerLogStore? store})
    : store = store ?? appServerLogStore;

  final AppServerLogStore store;

  @override
  State<AppServerLogsScreen> createState() => _AppServerLogsScreenState();
}

class _AppServerLogsScreenState extends State<AppServerLogsScreen> {
  late final TextEditingController _searchController;
  _AppServerLogFilter _filter = _AppServerLogFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()..addListener(_handleSearch);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearch)
      ..dispose();
    super.dispose();
  }

  void _handleSearch() {
    setState(() {});
  }

  void _clearSearch() {
    _searchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('App-server Logs', 'App-server 日志')),
        actions: [
          IconButton(
            onPressed: widget.store.clear,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: strings.text('Clear logs', '清空日志'),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.store,
          builder: (context, _) {
            final entries = widget.store.entries;
            final filtered = entries.reversed
                .where(_matchesCurrentFilters)
                .toList(growable: false);
            return SelectionArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _LogsToolbar(
                      searchController: _searchController,
                      activeFilter: _filter,
                      totalCount: entries.length,
                      requestCount: _countFor(
                        entries,
                        AppServerLogEntryKind.request,
                      ),
                      responseCount: _countFor(
                        entries,
                        AppServerLogEntryKind.response,
                      ),
                      errorCount: _countFor(
                        entries,
                        AppServerLogEntryKind.error,
                      ),
                      eventCount: entries
                          .where(
                            (entry) =>
                                entry.kind ==
                                    AppServerLogEntryKind.notification ||
                                entry.kind == AppServerLogEntryKind.connection,
                          )
                          .length,
                      onFilterChanged: (filter) {
                        setState(() {
                          _filter = filter;
                        });
                      },
                      onClearSearch: _clearSearch,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _LogsList(
                        entries: filtered,
                        emptyTitle: strings.text(
                          'No log entries yet',
                          '还没有日志记录',
                        ),
                        emptyMessage: _searchController.text.trim().isNotEmpty
                            ? strings.text(
                                'Try a different keyword or clear the current filter.',
                                '换一个关键词，或者清空当前过滤条件。',
                              )
                            : strings.text(
                                'This page updates live after the client starts talking to the Codex app-server.',
                                '客户端开始与 Codex app-server 通信后，这里会实时出现日志。',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  bool _matchesCurrentFilters(AppServerLogEntry entry) {
    if (!_matchesSearch(entry)) {
      return false;
    }

    return switch (_filter) {
      _AppServerLogFilter.all => true,
      _AppServerLogFilter.request =>
        entry.kind == AppServerLogEntryKind.request,
      _AppServerLogFilter.response =>
        entry.kind == AppServerLogEntryKind.response,
      _AppServerLogFilter.error => entry.kind == AppServerLogEntryKind.error,
      _AppServerLogFilter.event =>
        entry.kind == AppServerLogEntryKind.notification ||
            entry.kind == AppServerLogEntryKind.connection,
    };
  }

  bool _matchesSearch(AppServerLogEntry entry) {
    return entry.matchesQuery(_searchController.text);
  }
}

class _LogsToolbar extends StatelessWidget {
  const _LogsToolbar({
    required this.searchController,
    required this.activeFilter,
    required this.totalCount,
    required this.requestCount,
    required this.responseCount,
    required this.errorCount,
    required this.eventCount,
    required this.onFilterChanged,
    required this.onClearSearch,
  });

  final TextEditingController searchController;
  final _AppServerLogFilter activeFilter;
  final int totalCount;
  final int requestCount;
  final int responseCount;
  final int errorCount;
  final int eventCount;
  final ValueChanged<_AppServerLogFilter> onFilterChanged;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: panelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(panelRadius(theme)),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.text('Live RPC trace', '实时 RPC 追踪'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              strings.text(
                'Search request params, response payloads, request IDs, thread IDs, and server events.',
                '可以搜索请求参数、返回内容、请求 ID、线程 ID，以及服务端事件。',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondaryTextColor(theme),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  label: strings.text('Total', '总数'),
                  value: totalCount.toString(),
                ),
                _MetricChip(
                  label: strings.text('Calls', '调用'),
                  value: requestCount.toString(),
                ),
                _MetricChip(
                  label: strings.text('Returns', '返回'),
                  value: responseCount.toString(),
                ),
                _MetricChip(
                  label: strings.text('Errors', '错误'),
                  value: errorCount.toString(),
                ),
                _MetricChip(
                  label: strings.text('Events', '事件'),
                  value: eventCount.toString(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.close),
                        tooltip: strings.text('Clear search', '清空搜索'),
                      ),
                hintText: strings.text(
                  'Search method, payload, request ID, thread ID...',
                  '搜索方法、负载、请求 ID、线程 ID...',
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _AppServerLogFilter.values
                  .map(
                    (filter) => ChoiceChip(
                      label: Text(_filterLabel(context, filter)),
                      selected: filter == activeFilter,
                      onSelected: (_) => onFilterChanged(filter),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogsList extends StatelessWidget {
  const _LogsList({
    required this.entries,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final List<AppServerLogEntry> entries;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entries.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: panelBackgroundColor(theme),
          borderRadius: BorderRadius.circular(panelRadius(theme)),
          border: Border.all(color: borderColor(theme)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 40,
                  color: secondaryTextColor(theme),
                ),
                const SizedBox(height: 12),
                Text(
                  emptyTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Text(
                    emptyMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: secondaryTextColor(theme),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: panelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(panelRadius(theme)),
        border: Border.all(color: borderColor(theme)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: entries.length,
        separatorBuilder: (context, _) =>
            Divider(height: 1, color: borderColor(theme)),
        itemBuilder: (context, index) => _LogEntryTile(entry: entries[index]),
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  const _LogEntryTile({required this.entry});

  final AppServerLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payloadText = entry.formattedPayload.trim();
    final hasPayload = payloadText.isNotEmpty;

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>(entry.id),
        tilePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _entryColor(theme, entry).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(
            _entryIcon(entry),
            size: 18,
            color: _entryColor(theme, entry),
          ),
        ),
        title: Text(
          _entryTitle(context, entry),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.previewText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: secondaryTextColor(theme),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(value: _kindLabel(context, entry.kind)),
                  _MetaChip(value: _directionLabel(context, entry.direction)),
                  _MetaChip(
                    value: context.strings.formatAbsoluteTime(entry.recordedAt),
                  ),
                  if (entry.rpcId != null)
                    _MetaChip(value: 'RPC ${entry.rpcId}'),
                  if (entry.duration != null)
                    _MetaChip(value: '${entry.duration!.inMilliseconds} ms'),
                  if (entry.threadId != null)
                    _MetaChip(value: 'Thread ${_shortId(entry.threadId!)}'),
                  if (entry.turnId != null)
                    _MetaChip(value: 'Turn ${_shortId(entry.turnId!)}'),
                  if (entry.itemId != null)
                    _MetaChip(value: 'Item ${_shortId(entry.itemId!)}'),
                ],
              ),
            ],
          ),
        ),
        children: [
          if (hasPayload) ...[
            Row(
              children: [
                Text(
                  context.strings.text('Payload', '负载'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: payloadText));
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.strings.text('Payload copied.', '负载已复制。'),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_all_outlined),
                  tooltip: context.strings.text('Copy payload', '复制负载'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _PayloadBlock(text: payloadText),
          ],
        ],
      ),
    );
  }
}

class _PayloadBlock extends StatelessWidget {
  const _PayloadBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor(theme)),
      ),
      child: SelectableText(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'Courier New',
          height: 1.45,
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: secondaryTextColor(theme),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(999),
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

int _countFor(List<AppServerLogEntry> entries, AppServerLogEntryKind kind) {
  return entries.where((entry) => entry.kind == kind).length;
}

String _filterLabel(BuildContext context, _AppServerLogFilter filter) {
  return switch (filter) {
    _AppServerLogFilter.all => context.strings.text('All', '全部'),
    _AppServerLogFilter.request => context.strings.text('Calls', '调用'),
    _AppServerLogFilter.response => context.strings.text('Returns', '返回'),
    _AppServerLogFilter.error => context.strings.text('Errors', '错误'),
    _AppServerLogFilter.event => context.strings.text('Events', '事件'),
  };
}

String _entryTitle(BuildContext context, AppServerLogEntry entry) {
  final method = entry.method?.trim();
  if (method != null && method.isNotEmpty) {
    return method;
  }
  return _kindLabel(context, entry.kind);
}

String _kindLabel(BuildContext context, AppServerLogEntryKind kind) {
  return switch (kind) {
    AppServerLogEntryKind.request => context.strings.text('Request', '请求'),
    AppServerLogEntryKind.response => context.strings.text('Response', '返回'),
    AppServerLogEntryKind.error => context.strings.text('Error', '错误'),
    AppServerLogEntryKind.notification => context.strings.text(
      'Notification',
      '通知',
    ),
    AppServerLogEntryKind.connection => context.strings.text(
      'Connection',
      '连接',
    ),
  };
}

String _directionLabel(BuildContext context, AppServerLogDirection direction) {
  return switch (direction) {
    AppServerLogDirection.outbound => context.strings.text('Outbound', '发出'),
    AppServerLogDirection.inbound => context.strings.text('Inbound', '收到'),
  };
}

Color _entryColor(ThemeData theme, AppServerLogEntry entry) {
  return switch (entry.kind) {
    AppServerLogEntryKind.request => theme.colorScheme.primary,
    AppServerLogEntryKind.response => Colors.green.shade600,
    AppServerLogEntryKind.error => theme.colorScheme.error,
    AppServerLogEntryKind.notification => Colors.orange.shade700,
    AppServerLogEntryKind.connection => secondaryTextColor(theme),
  };
}

IconData _entryIcon(AppServerLogEntry entry) {
  return switch (entry.kind) {
    AppServerLogEntryKind.request => Icons.call_made_rounded,
    AppServerLogEntryKind.response => Icons.call_received_rounded,
    AppServerLogEntryKind.error => Icons.error_outline,
    AppServerLogEntryKind.notification => Icons.notifications_active_outlined,
    AppServerLogEntryKind.connection => Icons.lan_outlined,
  };
}

String _shortId(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 10) {
    return trimmed;
  }
  return trimmed.substring(trimmed.length - 8);
}
