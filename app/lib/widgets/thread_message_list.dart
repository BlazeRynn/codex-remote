import 'package:flutter/material.dart';

import '../app/app_strings.dart';
import '../app/app_typography.dart';
import '../app/workspace_theme.dart';
import '../models/codex_thread_item.dart';
import '../services/command_execution_presentation.dart';
import '../services/file_change_entries.dart';
import '../services/thread_item_timestamps.dart';
import '../services/thread_message_list_projection.dart';
import 'context_compaction_divider.dart';
import 'conversation_message_body.dart';
import 'file_change_cards.dart';

class ThreadMessageList extends StatelessWidget {
  const ThreadMessageList({
    super.key,
    required this.projection,
    required this.loading,
    required this.errorMessage,
    required this.scrollController,
    required this.onRefresh,
    required this.onScrollNotification,
    required this.workspaceStyle,
    required this.showLiveStatus,
    required this.liveStateLabel,
    required this.liveMessage,
    required this.hasActiveTurn,
    required this.stickToBottom,
    required this.showScrollToBottomButton,
    required this.onScrollToBottom,
    this.footer,
  });

  final ThreadMessageListProjection projection;
  final bool loading;
  final String? errorMessage;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;
  final bool Function(ScrollNotification) onScrollNotification;
  final bool workspaceStyle;
  final bool showLiveStatus;
  final String liveStateLabel;
  final String liveMessage;
  final bool hasActiveTurn;
  final bool stickToBottom;
  final bool showScrollToBottomButton;
  final VoidCallback onScrollToBottom;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final renderNodes = _buildRenderNodes(projection.entries);
    final padding = EdgeInsets.fromLTRB(
      16,
      workspaceStyle ? 2 : 4,
      16,
      workspaceStyle ? 12 : 18,
    );
    final stateChild = _buildStateChild();
    final itemCount =
        (showLiveStatus ? 1 : 0) +
        (stateChild == null ? renderNodes.length : 1) +
        (footer == null ? 0 : 1);

    return ColoredBox(
      color: panelBackgroundColor(theme),
      child: Stack(
        children: [
          RefreshIndicator(
            color: theme.colorScheme.primary,
            backgroundColor: mutedPanelBackgroundColor(theme),
            onRefresh: onRefresh,
            child: Scrollbar(
              controller: scrollController,
              thumbVisibility: false,
              trackVisibility: false,
              child: NotificationListener<ScrollNotification>(
                onNotification: onScrollNotification,
                child: ListView.builder(
                  controller: scrollController,
                  physics: BottomAnchoredScrollPhysics(
                    stickToBottom: stickToBottom,
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: padding,
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    var cursor = index;
                    if (showLiveStatus) {
                      if (cursor == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _ThreadMessageStatusBar(
                            stateLabel: liveStateLabel,
                            message: liveMessage,
                            hasActiveTurn: hasActiveTurn,
                            workspaceStyle: workspaceStyle,
                          ),
                        );
                      }
                      cursor -= 1;
                    }

                    if (stateChild != null) {
                      if (cursor == 0) {
                        return stateChild;
                      }
                      cursor -= 1;
                    } else {
                      if (cursor < renderNodes.length) {
                        final node = renderNodes[cursor];
                        if (node.groupedEntries != null) {
                          return _ThreadMessageOperationGroupCard(
                            key: ValueKey(node.key),
                            entries: node.groupedEntries!,
                            workspaceStyle: workspaceStyle,
                          );
                        }
                        return _ThreadMessageEntryView(
                          key: ValueKey(node.key),
                          entry: node.entry!,
                          workspaceStyle: workspaceStyle,
                        );
                      }
                      cursor -= renderNodes.length;
                    }

                    if (footer != null && cursor == 0) {
                      return Padding(
                        padding: EdgeInsets.only(top: workspaceStyle ? 8 : 18),
                        child: footer,
                      );
                    }

                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
          if (showScrollToBottomButton)
            Positioned(
              right: workspaceStyle ? 16 : 20,
              bottom: workspaceStyle ? 16 : 20,
              child: _ThreadMessageScrollButton(
                label: context.strings.text('Back to bottom', '回到底部'),
                onPressed: onScrollToBottom,
              ),
            ),
        ],
      ),
    );
  }

  Widget? _buildStateChild() {
    if (errorMessage != null) {
      return _ThreadMessageErrorCard(
        message: errorMessage!,
        onRetry: onRefresh,
      );
    }
    if (loading && projection.entries.isEmpty) {
      return const _ThreadMessageLoadingState();
    }
    if (projection.entries.isEmpty) {
      return const _ThreadMessageEmptyState();
    }
    return null;
  }
}

class _ThreadMessageRenderNode {
  _ThreadMessageRenderNode.entry(this.entry)
    : assert(entry != null),
      groupedEntries = null,
      key = entry!.key;

  _ThreadMessageRenderNode.group(List<ThreadMessageListEntry> entries)
    : assert(entries.length > 1),
      entry = null,
      groupedEntries = List.unmodifiable(entries),
      key =
          'operation-group:${entries.first.key}:${entries.last.key}:${entries.length}';

  final String key;
  final ThreadMessageListEntry? entry;
  final List<ThreadMessageListEntry>? groupedEntries;
}

List<_ThreadMessageRenderNode> _buildRenderNodes(
  List<ThreadMessageListEntry> entries,
) {
  if (entries.isEmpty) {
    return const [];
  }

  final nodes = <_ThreadMessageRenderNode>[];
  var index = 0;
  while (index < entries.length) {
    final entry = entries[index];
    if (!_isOperationEntry(entry)) {
      nodes.add(_ThreadMessageRenderNode.entry(entry));
      index += 1;
      continue;
    }

    final runStart = index;
    while (index < entries.length && _isOperationEntry(entries[index])) {
      index += 1;
    }

    final operationRun = entries.sublist(runStart, index);
    final shouldCollapseRun = _shouldCollapseOperationRun(
      entries,
      runStart: runStart,
      runEnd: index,
    );
    if (shouldCollapseRun) {
      nodes.add(_ThreadMessageRenderNode.group(operationRun));
      continue;
    }

    for (final operationEntry in operationRun) {
      nodes.add(_ThreadMessageRenderNode.entry(operationEntry));
    }
  }
  return nodes;
}

bool _isOperationEntry(ThreadMessageListEntry entry) {
  return entry.kind == ThreadMessageEntryKind.commandExecution ||
      entry.kind == ThreadMessageEntryKind.fileChange;
}

bool _shouldCollapseOperationRun(
  List<ThreadMessageListEntry> entries, {
  required int runStart,
  required int runEnd,
}) {
  final runLength = runEnd - runStart;
  return runLength > 1;
}

bool _shouldCollapseUserBubble(CodexThreadItem item) {
  if (item.type != 'user.message' && item.actor != 'user') {
    return false;
  }
  final body = item.body.trimRight();
  if (body.isEmpty) {
    return false;
  }
  final lineCount = '\n'.allMatches(body).length + 1;
  final charCount = body.runes.length;
  return charCount >= 420 || lineCount >= 8;
}

class BottomAnchoredScrollPhysics extends AlwaysScrollableScrollPhysics {
  const BottomAnchoredScrollPhysics({
    required this.stickToBottom,
    super.parent,
  });

  final bool stickToBottom;

  @override
  BottomAnchoredScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return BottomAnchoredScrollPhysics(
      stickToBottom: stickToBottom,
      parent: buildParent(ancestor),
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final wasAtBottom =
        (oldPosition.maxScrollExtent - oldPosition.pixels).abs() <= 1;
    if (stickToBottom && !isScrolling && wasAtBottom) {
      final target = newPosition.maxScrollExtent < newPosition.minScrollExtent
          ? newPosition.minScrollExtent
          : newPosition.maxScrollExtent;
      return target;
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

class _ThreadMessageEntryView extends StatelessWidget {
  const _ThreadMessageEntryView({
    super.key,
    required this.entry,
    required this.workspaceStyle,
  });

  final ThreadMessageListEntry entry;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    switch (entry.kind) {
      case ThreadMessageEntryKind.contextCompaction:
        return ContextCompactionDivider(
          item: entry.item!,
          workspaceStyle: workspaceStyle,
        );
      case ThreadMessageEntryKind.commandExecution:
        return _ThreadMessageCommandCard(
          item: entry.item!,
          workspaceStyle: workspaceStyle,
        );
      case ThreadMessageEntryKind.fileChange:
        return _ThreadMessageFileChangePanel(
          item: entry.item!,
          entries: parseCodexFileChangeEntries(entry.item!),
          workspaceStyle: workspaceStyle,
        );
      case ThreadMessageEntryKind.bubble:
        return _ThreadMessageBubbleCard(
          entry: entry,
          workspaceStyle: workspaceStyle,
        );
    }
  }
}

class _ThreadMessageBubbleCard extends StatefulWidget {
  const _ThreadMessageBubbleCard({
    required this.entry,
    required this.workspaceStyle,
  });

  final ThreadMessageListEntry entry;
  final bool workspaceStyle;

  @override
  State<_ThreadMessageBubbleCard> createState() =>
      _ThreadMessageBubbleCardState();
}

class _ThreadMessageBubbleCardState extends State<_ThreadMessageBubbleCard> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ThreadMessageBubbleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.key != widget.entry.key && _expanded) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;
    final workspaceStyle = widget.workspaceStyle;
    final item = _bubbleDisplayItem(entry);
    if (item == null) {
      return const SizedBox.shrink();
    }

    final isUser = entry.actor == 'user' || item.type == 'user.message';
    final bubbleColor = isUser
        ? theme.colorScheme.primary.withValues(alpha: 0.16)
        : mutedPanelBackgroundColor(theme);
    final borderColorValue = isUser
        ? theme.colorScheme.primary.withValues(alpha: 0.24)
        : borderColor(theme);
    final canCollapseBody = isUser && _shouldCollapseUserBubble(item);
    final collapsedBodyPreview = canCollapseBody && !_expanded;
    final messageBody = collapsedBodyPreview
        ? _CollapsedUserBubblePreview(
            item: item,
            workspaceStyle: workspaceStyle,
          )
        : ConversationMessageBody(
            item: item,
            workspaceStyle: workspaceStyle,
          );

    return Padding(
      padding: EdgeInsets.only(bottom: workspaceStyle ? 8 : 14),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: workspaceStyle ? 760 : 720),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(workspaceStyle ? 18 : 24),
              border: Border.all(color: borderColorValue),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                workspaceStyle ? 14 : 18,
                workspaceStyle ? 12 : 16,
                workspaceStyle ? 14 : 18,
                workspaceStyle ? 12 : 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ThreadMessageHeader(
                    speaker: _speakerLabel(
                      context,
                      item,
                      fallbackActor: entry.actor,
                    ),
                    status: _statusLabel(context, item),
                    timestamp: context.strings.formatRelativeTime(
                      _latestBubbleTimestamp(
                        entry.sourceItems.isEmpty
                            ? entry.items
                            : entry.sourceItems,
                      ),
                    ),
                    workspaceStyle: workspaceStyle,
                  ),
                  if (_shouldShowBubbleTitle(item)) ...[
                    SizedBox(height: workspaceStyle ? 8 : 10),
                    Text(
                      item.title.trim(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  SizedBox(height: workspaceStyle ? 8 : 10),
                  messageBody,
                  if (canCollapseBody) ...[
                    SizedBox(height: workspaceStyle ? 6 : 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _expanded = !_expanded;
                          });
                        },
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.symmetric(
                            horizontal: workspaceStyle ? 8 : 10,
                            vertical: workspaceStyle ? 4 : 6,
                          ),
                        ),
                        icon: Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: workspaceStyle ? 16 : 18,
                        ),
                        label: Text(
                          context.strings.text(
                            _expanded ? 'Collapse' : 'Expand',
                            _expanded ? '收起' : '展开',
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapsedUserBubblePreview extends StatelessWidget {
  const _CollapsedUserBubblePreview({
    required this.item,
    required this.workspaceStyle,
  });

  final CodexThreadItem item;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = item.body.trimRight();
    if (content.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      content,
      maxLines: workspaceStyle ? 8 : 10,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
    );
  }
}

class _ThreadMessageCommandCard extends StatefulWidget {
  const _ThreadMessageCommandCard({
    required this.item,
    required this.workspaceStyle,
  });

  final CodexThreadItem item;
  final bool workspaceStyle;

  @override
  State<_ThreadMessageCommandCard> createState() =>
      _ThreadMessageCommandCardState();
}

class _ThreadMessageCommandCardState extends State<_ThreadMessageCommandCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final commandLabel = commandExecutionDisplayLabel(
      item.raw,
      fallback: item.title.trim().isEmpty
          ? context.strings.text('Command', '命令')
          : item.title.trim(),
    );
    final cwd = _commandCwd(item);
    final exitCode = _commandExitCode(item);
    final output = _commandOutput(item);
    final canExpand = _canShowCommandDetails(cwd, exitCode, output);

    return Padding(
      padding: EdgeInsets.only(bottom: widget.workspaceStyle ? 8 : 14),
      child: _StandaloneMessageFrame(
        workspaceStyle: widget.workspaceStyle,
        backgroundColor: mutedPanelBackgroundColor(theme),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('thread-command-card:${item.id}'),
            borderRadius: BorderRadius.circular(
              widget.workspaceStyle ? 18 : 20,
            ),
            onTap: canExpand
                ? () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  }
                : null,
            child: Padding(
              padding: EdgeInsets.all(widget.workspaceStyle ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ThreadMessageHeader(
                    speaker: _speakerLabel(context, item),
                    status: _statusLabel(context, item),
                    timestamp: context.strings.formatRelativeTime(
                      resolveThreadItemDisplayTimestamp(item),
                    ),
                    workspaceStyle: widget.workspaceStyle,
                  ),
                  SizedBox(height: widget.workspaceStyle ? 10 : 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: widget.workspaceStyle ? 24 : 28,
                        height: widget.workspaceStyle ? 24 : 28,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.terminal_rounded,
                          size: widget.workspaceStyle ? 14 : 16,
                          color: secondaryTextColor(theme),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          commandLabel,
                          maxLines: _expanded ? null : 1,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: appCodeTextStyle(theme.textTheme.bodyMedium)
                              .copyWith(
                                fontWeight: FontWeight.w500,
                                fontSize: widget.workspaceStyle ? 12 : 12.75,
                                color: secondaryTextColor(theme),
                              ),
                        ),
                      ),
                      if (canExpand)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: secondaryTextColor(theme),
                          ),
                        ),
                    ],
                  ),
                  if (_expanded) ...[
                    SizedBox(height: widget.workspaceStyle ? 12 : 14),
                    if (cwd != null && cwd.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          context.strings.text(
                            'Working directory: $cwd',
                            '工作目录: $cwd',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondaryTextColor(theme),
                          ),
                        ),
                      ),
                    if (exitCode != null && exitCode.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          context.strings.text(
                            'Exit code: $exitCode',
                            '退出码: $exitCode',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondaryTextColor(theme),
                          ),
                        ),
                      ),
                    if (output != null && output.isNotEmpty)
                      _CodePanel(
                        code: output,
                        workspaceStyle: widget.workspaceStyle,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadMessageFileChangePanel extends StatelessWidget {
  const _ThreadMessageFileChangePanel({
    required this.item,
    required this.entries,
    required this.workspaceStyle,
  });

  final CodexThreadItem item;
  final List<CodexFileChangeEntry> entries;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.title.trim().isEmpty
        ? context.strings.text('File Changes', '文件变更')
        : item.title.trim();

    return Padding(
      padding: EdgeInsets.only(bottom: workspaceStyle ? 8 : 14),
      child: _StandaloneMessageFrame(
        workspaceStyle: workspaceStyle,
        child: Padding(
          padding: EdgeInsets.all(workspaceStyle ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ThreadMessageHeader(
                speaker: _speakerLabel(context, item),
                status: _statusLabel(context, item),
                timestamp: context.strings.formatRelativeTime(
                  resolveThreadItemDisplayTimestamp(item),
                ),
                workspaceStyle: workspaceStyle,
              ),
              SizedBox(height: workspaceStyle ? 10 : 12),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: workspaceStyle ? 10 : 12),
              if (entries.isNotEmpty)
                FileChangeCardList(
                  entries: entries,
                  workspaceStyle: workspaceStyle,
                )
              else if (item.body.trim().isNotEmpty)
                SelectableText(
                  item.body.trimRight(),
                  style: theme.textTheme.bodyMedium,
                )
              else
                Text(
                  context.strings.text(
                    'No file changes available.',
                    '没有可显示的文件变更。',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
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

class _ThreadMessageOperationGroupCard extends StatefulWidget {
  const _ThreadMessageOperationGroupCard({
    super.key,
    required this.entries,
    required this.workspaceStyle,
  });

  final List<ThreadMessageListEntry> entries;
  final bool workspaceStyle;

  @override
  State<_ThreadMessageOperationGroupCard> createState() =>
      _ThreadMessageOperationGroupCardState();
}

class _ThreadMessageOperationGroupCardState
    extends State<_ThreadMessageOperationGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commandCount = widget.entries
        .where((entry) => entry.kind == ThreadMessageEntryKind.commandExecution)
        .length;
    final fileCount = _groupedFileCount(widget.entries);
    final latestTimestamp = _latestGroupedEntryTimestamp(widget.entries);

    return Padding(
      padding: EdgeInsets.only(bottom: widget.workspaceStyle ? 8 : 14),
      child: _StandaloneMessageFrame(
        workspaceStyle: widget.workspaceStyle,
        backgroundColor: mutedPanelBackgroundColor(theme),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(
              widget.workspaceStyle ? 16 : 18,
            ),
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
            },
            child: Padding(
              padding: EdgeInsets.all(widget.workspaceStyle ? 10 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: widget.workspaceStyle ? 22 : 24,
                        height: widget.workspaceStyle ? 22 : 24,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.layers_rounded,
                          size: widget.workspaceStyle ? 13 : 14,
                          color: secondaryTextColor(theme),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _operationGroupSummaryText(
                            context,
                            commandCount: commandCount,
                            fileCount: fileCount,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: widget.workspaceStyle ? 18 : 20,
                        color: secondaryTextColor(theme),
                      ),
                    ],
                  ),
                  if (_expanded) ...[
                    SizedBox(height: widget.workspaceStyle ? 8 : 10),
                    _ThreadMessageHeader(
                      speaker: 'Codex',
                      status: context.strings.text('Actions', '操作'),
                      timestamp: context.strings.formatRelativeTime(
                        latestTimestamp,
                      ),
                      workspaceStyle: widget.workspaceStyle,
                    ),
                    SizedBox(height: widget.workspaceStyle ? 8 : 10),
                    Container(height: 1, color: borderColor(theme)),
                    SizedBox(height: widget.workspaceStyle ? 8 : 10),
                    for (final entry in widget.entries)
                      _ThreadMessageEntryView(
                        key: ValueKey('group-child:${entry.key}'),
                        entry: entry,
                        workspaceStyle: widget.workspaceStyle,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadMessageStatusBar extends StatelessWidget {
  const _ThreadMessageStatusBar({
    required this.stateLabel,
    required this.message,
    required this.hasActiveTurn,
    required this.workspaceStyle,
  });

  final String stateLabel;
  final String message;
  final bool hasActiveTurn;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _connectionAccentColor(theme, stateLabel);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(workspaceStyle ? 16 : 18),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          workspaceStyle ? 12 : 14,
          workspaceStyle ? 10 : 12,
          workspaceStyle ? 12 : 14,
          workspaceStyle ? 10 : 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fiber_manual_record_rounded,
                      size: workspaceStyle ? 10 : 11,
                      color: accentColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.strings.text('Realtime', '实时'),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                _ThreadMessageMetaChip(
                  label: context.strings.humanizeMachineLabel(stateLabel),
                  emphasized: true,
                  accentColor: accentColor,
                  workspaceStyle: workspaceStyle,
                ),
                _ThreadMessageMetaChip(
                  label: hasActiveTurn
                      ? context.strings.text('Turn active', '当前 turn 活跃')
                      : context.strings.text('Turn idle', '当前 turn 空闲'),
                  workspaceStyle: workspaceStyle,
                ),
              ],
            ),
            SizedBox(height: workspaceStyle ? 8 : 10),
            Text(
              message.trim().isEmpty
                  ? context.strings.text('Waiting for updates', '等待更新')
                  : message.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondaryTextColor(theme),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadMessageScrollButton extends StatelessWidget {
  const _ThreadMessageScrollButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_downward_rounded, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

class _ThreadMessageLoadingState extends StatelessWidget {
  const _ThreadMessageLoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _StatePanel(
      icon: SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
        ),
      ),
      title: context.strings.text('Loading thread', '正在加载线程'),
      description: context.strings.text(
        'Fetching timeline items and workspace state.',
        '正在拉取时间线项目和工作区状态。',
      ),
    );
  }
}

class _ThreadMessageEmptyState extends StatelessWidget {
  const _ThreadMessageEmptyState();

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: const Icon(Icons.chat_bubble_outline_rounded),
      title: context.strings.text('No messages yet', '暂无消息'),
      description: context.strings.text(
        'Start a new turn to see messages, reasoning, commands, and file changes here.',
        '开始一个新的 turn 后，消息、思考、命令和文件变更会显示在这里。',
      ),
    );
  }
}

class _ThreadMessageErrorCard extends StatelessWidget {
  const _ThreadMessageErrorCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _StatePanel(
      icon: Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
      title: context.strings.text('Failed to load thread', '加载线程失败'),
      description: message,
      action: FilledButton.tonal(
        onPressed: () {
          onRetry();
        },
        child: Text(context.strings.text('Retry', '重试')),
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final Widget icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: mutedPanelBackgroundColor(theme),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor(theme)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: secondaryTextColor(theme),
                ),
              ),
              if (action != null) ...[const SizedBox(height: 14), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _StandaloneMessageFrame extends StatelessWidget {
  const _StandaloneMessageFrame({
    required this.child,
    required this.workspaceStyle,
    this.backgroundColor,
  });

  final Widget child;
  final bool workspaceStyle;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: workspaceStyle ? 760 : 720),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor ?? panelBackgroundColor(theme),
            borderRadius: BorderRadius.circular(workspaceStyle ? 18 : 20),
            border: Border.all(color: borderColor(theme)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ThreadMessageHeader extends StatelessWidget {
  const _ThreadMessageHeader({
    required this.speaker,
    required this.status,
    required this.timestamp,
    required this.workspaceStyle,
  });

  final String speaker;
  final String? status;
  final String timestamp;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedStatus = status?.trim() ?? '';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          speaker,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (normalizedStatus.isNotEmpty)
          _ThreadMessageMetaChip(
            label: normalizedStatus,
            workspaceStyle: workspaceStyle,
          ),
        _ThreadMessageMetaChip(
          label: timestamp,
          workspaceStyle: workspaceStyle,
        ),
      ],
    );
  }
}

class _ThreadMessageMetaChip extends StatelessWidget {
  const _ThreadMessageMetaChip({
    required this.label,
    this.emphasized = false,
    this.accentColor,
    this.workspaceStyle = false,
  });

  final String label;
  final bool emphasized;
  final Color? accentColor;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveAccent = accentColor ?? theme.colorScheme.primary;
    final background = emphasized
        ? effectiveAccent.withValues(alpha: 0.14)
        : theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.04);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasized
              ? effectiveAccent.withValues(alpha: 0.22)
              : borderColor(theme),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: workspaceStyle ? 7 : 8,
          vertical: workspaceStyle ? 3 : 4,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: emphasized ? effectiveAccent : secondaryTextColor(theme),
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _CodePanel extends StatelessWidget {
  const _CodePanel({required this.code, required this.workspaceStyle});

  final String code;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.brightness == Brightness.dark
        ? const Color(0xFF0E1116)
        : const Color(0xFFF8FAFD);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(workspaceStyle ? 12 : 14),
        border: Border.all(color: borderColor(theme)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: SelectableText(
          code.trimRight(),
          style: appCodeTextStyle(theme.textTheme.bodyMedium).copyWith(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFFD4D4D4)
                : const Color(0xFF1F2328),
            fontSize: workspaceStyle ? 13 : 13.5,
          ),
        ),
      ),
    );
  }
}

CodexThreadItem? _bubbleDisplayItem(ThreadMessageListEntry entry) {
  if (entry.items.isEmpty) {
    return entry.item;
  }
  if (entry.items.length == 1) {
    return entry.items.single;
  }

  final latestItem = entry.items.last;
  return CodexThreadItem(
    id: 'assistant-group:${entry.key}',
    type: 'assistant.group',
    title: 'Codex',
    body: entry.items
        .map((item) => item.body.trim())
        .where((body) => body.isNotEmpty)
        .join('\n\n'),
    status: latestItem.status,
    actor: entry.actor,
    createdAt: _latestBubbleTimestamp(entry.items),
    raw: {
      ...latestItem.raw,
      'bubbleItems': entry.items,
      'bubbleKey': entry.key,
    },
  );
}

DateTime? _latestBubbleTimestamp(List<CodexThreadItem> items) {
  DateTime? latest;
  for (final item in items) {
    final timestamp = resolveThreadItemDisplayTimestamp(item);
    if (timestamp == null) {
      continue;
    }
    if (latest == null || timestamp.isAfter(latest)) {
      latest = timestamp;
    }
  }
  return latest;
}

String _speakerLabel(
  BuildContext context,
  CodexThreadItem item, {
  String? fallbackActor,
}) {
  final actor = (fallbackActor ?? item.actor).trim();
  if (actor == 'user' || item.type == 'user.message') {
    return context.strings.text('You', '你');
  }
  if (actor == 'assistant' ||
      item.type == 'agent.message' ||
      item.type == 'assistant.group' ||
      item.type == 'reasoning') {
    return 'Codex';
  }
  return context.strings.humanizeMachineLabel(actor);
}

String? _statusLabel(BuildContext context, CodexThreadItem item) {
  if (item.actor == 'user' || item.type == 'user.message') {
    return null;
  }
  final phase = item.raw['phase']?.toString().trim() ?? '';
  if (phase.isNotEmpty) {
    if (phase == 'streaming') {
      return context.strings.text('In progress', '进行中');
    }
    return context.strings.humanizeMachineLabel(phase);
  }
  final status = item.status.trim();
  if (status.isEmpty) {
    return context.strings.text('Unknown', '未知');
  }
  if (status == 'in_progress') {
    return context.strings.text('In progress', '进行中');
  }
  return context.strings.humanizeMachineLabel(status);
}

bool _shouldShowBubbleTitle(CodexThreadItem item) {
  if (item.title.trim().isEmpty) {
    return false;
  }
  switch (item.type) {
    case 'user.message':
    case 'agent.message':
    case 'assistant.group':
    case 'reasoning':
      return false;
    default:
      return true;
  }
}

Color _connectionAccentColor(ThemeData theme, String stateLabel) {
  switch (stateLabel.trim().toLowerCase()) {
    case 'connected':
      return theme.colorScheme.primary;
    case 'connecting':
      return theme.colorScheme.tertiary;
    case 'failed':
      return theme.colorScheme.error;
    case 'disconnected':
      return secondaryTextColor(theme);
    default:
      return theme.colorScheme.primary;
  }
}

String? _commandCwd(CodexThreadItem item) {
  for (final key in const ['cwd', 'workingDirectory', 'workdir']) {
    final value = item.raw[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String? _commandExitCode(CodexThreadItem item) {
  for (final key in const ['exitCode', 'code']) {
    final value = item.raw[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String? _commandOutput(CodexThreadItem item) {
  for (final key in const [
    'aggregatedOutput',
    'output',
    'stdout',
    'stderr',
    'detail',
  ]) {
    final value = item.raw[key]?.toString().trimRight() ?? '';
    if (value.trim().isNotEmpty) {
      return value.trimRight();
    }
  }
  final body = item.body.trimRight();
  return body.isEmpty ? null : body;
}

bool _canShowCommandDetails(String? cwd, String? exitCode, String? output) {
  return (cwd?.isNotEmpty ?? false) ||
      (exitCode?.isNotEmpty ?? false) ||
      (output?.isNotEmpty ?? false);
}

int _groupedFileCount(List<ThreadMessageListEntry> entries) {
  var count = 0;
  for (final entry in entries) {
    if (entry.kind != ThreadMessageEntryKind.fileChange || entry.item == null) {
      continue;
    }
    final fileEntries = parseCodexFileChangeEntries(entry.item!);
    count += fileEntries.isEmpty ? 1 : fileEntries.length;
  }
  return count;
}

DateTime? _latestGroupedEntryTimestamp(List<ThreadMessageListEntry> entries) {
  DateTime? latest;
  for (final entry in entries) {
    final item = entry.displayItem;
    if (item == null) {
      continue;
    }
    final timestamp = resolveThreadItemDisplayTimestamp(item);
    if (timestamp == null) {
      continue;
    }
    if (latest == null || timestamp.isAfter(latest)) {
      latest = timestamp;
    }
  }
  return latest;
}

String _operationGroupSummaryText(
  BuildContext context, {
  required int commandCount,
  required int fileCount,
}) {
  if (fileCount > 0 && commandCount > 0) {
    return context.strings.text(
      'Edited $fileCount file${fileCount == 1 ? '' : 's'} and ran $commandCount command${commandCount == 1 ? '' : 's'}',
      '编辑了 $fileCount 个文件，执行了 $commandCount 条命令',
    );
  }
  if (fileCount > 0) {
    return context.strings.text(
      'Edited $fileCount file${fileCount == 1 ? '' : 's'}',
      '编辑了 $fileCount 个文件',
    );
  }
  return context.strings.text(
    'Ran $commandCount command${commandCount == 1 ? '' : 's'}',
    '执行了 $commandCount 条命令',
  );
}
