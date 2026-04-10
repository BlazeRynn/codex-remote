import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:highlight/highlight.dart' as highlight;
import 'package:markdown/markdown.dart' as md;

import '../app/app_strings.dart';
import '../app/app_typography.dart';
import '../app/workspace_theme.dart';
import '../models/codex_thread_item.dart';
import '../services/command_execution_presentation.dart';
import '../services/file_change_entries.dart';
import '../services/thread_message_content.dart';
import '../utils/json_utils.dart';
import 'file_change_cards.dart';

class ConversationMessageBody extends StatelessWidget {
  const ConversationMessageBody({
    super.key,
    required this.item,
    this.workspaceStyle = false,
  });

  final CodexThreadItem item;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final assistantGroupItems = item.type == 'assistant.group'
        ? _assistantGroupItemsFromRaw(item.raw)
        : const <CodexThreadItem>[];
    if (assistantGroupItems.isNotEmpty) {
      return _AssistantGroupBody(
        items: assistantGroupItems,
        workspaceStyle: workspaceStyle,
      );
    }

    final userParts = item.type == 'user.message'
        ? parseUserMessageParts(item.raw['content'])
        : const <UserMessagePart>[];
    if (userParts.isNotEmpty) {
      return _StructuredUserMessageBody(
        parts: userParts,
        workspaceStyle: workspaceStyle,
      );
    }

    if (item.type == 'reasoning') {
      return _ReasoningMessageBody(item: item, workspaceStyle: workspaceStyle);
    }

    if (item.type == 'plan') {
      final planState = _planStateFromItem(item);
      if (planState != null) {
        return _PlanMessageBody(
          item: item,
          planState: planState,
          workspaceStyle: workspaceStyle,
        );
      }
    }

    if (item.type == 'web.search') {
      return _WebSearchMessageBody(item: item, workspaceStyle: workspaceStyle);
    }

    final mediaReference = _imageReferenceForItem(item);
    if (mediaReference != null) {
      final imageProvider = _providerForImageReference(mediaReference);
      if (imageProvider != null) {
        return _MessageImageView(
          imageProvider: imageProvider,
          fallbackLabel: item.body.trim().isEmpty ? item.title : item.body,
          caption: _captionForImageReference(mediaReference),
          workspaceStyle: workspaceStyle,
        );
      }
    }

    final body = item.type == 'user.message'
        ? normalizeUserMessageText(item.body).trimRight()
        : item.body.trimRight();
    if (body.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_preferPreformatted(item)) {
      return _CodeSurface(code: body, workspaceStyle: workspaceStyle);
    }

    final theme = Theme.of(context);
    return _MarkdownTextBody(
      data: body,
      workspaceStyle: workspaceStyle,
      fallbackStyle: theme.textTheme.bodyMedium,
    );
  }
}

class _AssistantGroupBody extends StatelessWidget {
  const _AssistantGroupBody({
    required this.items,
    required this.workspaceStyle,
  });

  final List<CodexThreadItem> items;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = workspaceStyle ? 8.0 : 10.0;
    final blocks = _buildAssistantGroupBlocks(
      items,
      collapseOperations: !_assistantGroupHasFinalAnswer(items),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < blocks.length; index += 1) ...[
          if (index > 0) SizedBox(height: spacing),
          if (blocks[index].item case final item?
              when _shouldShowAssistantGroupLabel(item)) ...[
            Text(
              _localizedAssistantGroupLabel(context, item),
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondaryTextColor(theme),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: workspaceStyle ? 4 : 5),
          ],
          if (blocks[index].operationItems != null)
            _AssistantGroupOperationSummary(
              items: blocks[index].operationItems!,
              workspaceStyle: workspaceStyle,
            )
          else
            _AssistantGroupItemBody(
              item: blocks[index].item!,
              workspaceStyle: workspaceStyle,
              showReasoningStatus: blocks[index].item!.type == 'reasoning',
              reasoningActiveOverride: blocks[index].item!.type == 'reasoning'
                  ? _isReasoningInProgress(blocks[index].item!) &&
                        !_hasLaterAssistantReply(items, items.indexOf(blocks[index].item!))
                  : null,
            ),
        ],
      ],
    );
  }
}

class _AssistantGroupRenderBlock {
  const _AssistantGroupRenderBlock.item(this.item) : operationItems = null;

  const _AssistantGroupRenderBlock.operation(this.operationItems) : item = null;

  final CodexThreadItem? item;
  final List<CodexThreadItem>? operationItems;
}

List<_AssistantGroupRenderBlock> _buildAssistantGroupBlocks(
  List<CodexThreadItem> items,
  {
  required bool collapseOperations,
}
) {
  if (items.isEmpty) {
    return const [];
  }

  final blocks = <_AssistantGroupRenderBlock>[];
  var index = 0;
  while (index < items.length) {
    final item = items[index];
    if (!_isAssistantOperationItem(item)) {
      blocks.add(_AssistantGroupRenderBlock.item(item));
      index += 1;
      continue;
    }

    if (!collapseOperations) {
      final runStart = index;
      while (index < items.length && _isAssistantOperationItem(items[index])) {
        index += 1;
      }
      final operationRun = items.sublist(runStart, index);
      for (final operationItem in operationRun) {
        blocks.add(_AssistantGroupRenderBlock.item(operationItem));
      }
      continue;
    }

    final collapsedOperations = <CodexThreadItem>[];
    var cursor = index;
    while (cursor < items.length) {
      final candidate = items[cursor];
      if (_isAssistantOperationItem(candidate)) {
        collapsedOperations.add(candidate);
        cursor += 1;
        continue;
      }
      final nextIsOperation =
          cursor + 1 < items.length &&
          _isAssistantOperationItem(items[cursor + 1]);
      if (_isCollapsibleReasoningSeparator(candidate) &&
          collapsedOperations.isNotEmpty &&
          nextIsOperation) {
        cursor += 1;
        continue;
      }
      break;
    }

    if (collapsedOperations.length > 1) {
      blocks.add(_AssistantGroupRenderBlock.operation(collapsedOperations));
      index = cursor;
      continue;
    }

    blocks.add(_AssistantGroupRenderBlock.item(item));
    index += 1;
  }
  return blocks;
}

bool _isAssistantOperationItem(CodexThreadItem item) {
  return item.type == 'command.execution' || item.type == 'file.change';
}

bool _assistantGroupHasFinalAnswer(List<CodexThreadItem> items) {
  return items.any((item) => _itemPhase(item) == 'final_answer');
}

bool _isCollapsibleReasoningSeparator(CodexThreadItem item) {
  if (item.type != 'reasoning') {
    return false;
  }
  if (_isReasoningInProgress(item)) {
    return false;
  }
  return item.body.trim().isEmpty;
}

class _AssistantGroupItemBody extends StatelessWidget {
  const _AssistantGroupItemBody({
    required this.item,
    required this.workspaceStyle,
    this.showReasoningStatus = true,
    this.reasoningActiveOverride,
  });

  final CodexThreadItem item;
  final bool workspaceStyle;
  final bool showReasoningStatus;
  final bool? reasoningActiveOverride;

  @override
  Widget build(BuildContext context) {
    if (item.type == 'command.execution') {
      return _EmbeddedCommandExecutionCard(
        item: item,
        workspaceStyle: workspaceStyle,
      );
    }

    if (item.type == 'file.change') {
      final entries = parseCodexFileChangeEntries(item);
      if (entries.isNotEmpty) {
        return _EmbeddedFileChangeGroup(
          item: item,
          entries: entries,
          workspaceStyle: workspaceStyle,
        );
      }
    }

    if (item.type == 'reasoning') {
      return _ReasoningMessageBody(
        item: item,
        workspaceStyle: workspaceStyle,
        showStatus: showReasoningStatus,
        activeOverride: reasoningActiveOverride,
      );
    }

    if (item.type == 'web.search') {
      return _WebSearchMessageBody(item: item, workspaceStyle: workspaceStyle);
    }

    return ConversationMessageBody(item: item, workspaceStyle: workspaceStyle);
  }
}

class _AssistantGroupOperationSummary extends StatefulWidget {
  const _AssistantGroupOperationSummary({
    required this.items,
    required this.workspaceStyle,
  });

  final List<CodexThreadItem> items;
  final bool workspaceStyle;

  @override
  State<_AssistantGroupOperationSummary> createState() =>
      _AssistantGroupOperationSummaryState();
}

class _AssistantGroupOperationSummaryState
    extends State<_AssistantGroupOperationSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commandCount = widget.items
        .where((item) => item.type == 'command.execution')
        .length;
    final fileCount = _assistantGroupFileCount(widget.items);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(widget.workspaceStyle ? 10 : 12),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.workspaceStyle ? 10 : 12),
          onTap: () {
            setState(() {
              _expanded = !_expanded;
            });
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.workspaceStyle ? 8 : 10,
              widget.workspaceStyle ? 6 : 7,
              widget.workspaceStyle ? 8 : 10,
              widget.workspaceStyle ? 6 : 7,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: widget.workspaceStyle ? 20 : 22,
                      height: widget.workspaceStyle ? 20 : 22,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.layers_rounded,
                        size: widget.workspaceStyle ? 12 : 13,
                        color: secondaryTextColor(theme),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _assistantGroupOperationSummaryText(
                          context,
                          commandCount: commandCount,
                          fileCount: fileCount,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: widget.workspaceStyle ? 15 : 16,
                      color: secondaryTextColor(theme),
                    ),
                  ],
                ),
                if (_expanded) ...[
                  SizedBox(height: widget.workspaceStyle ? 6 : 8),
                  for (var index = 0; index < widget.items.length; index += 1) ...[
                    if (index > 0) SizedBox(height: widget.workspaceStyle ? 4 : 6),
                    _AssistantGroupItemBody(
                      item: widget.items[index],
                      workspaceStyle: widget.workspaceStyle,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasoningMessageBody extends StatefulWidget {
  const _ReasoningMessageBody({
    required this.item,
    required this.workspaceStyle,
    this.showStatus = true,
    this.activeOverride,
  });

  final CodexThreadItem item;
  final bool workspaceStyle;
  final bool showStatus;
  final bool? activeOverride;

  @override
  State<_ReasoningMessageBody> createState() => _ReasoningMessageBodyState();
}

class _ReasoningMessageBodyState extends State<_ReasoningMessageBody> {
  @override
  Widget build(BuildContext context) {
    final body = widget.item.body.trimRight();
    final active = widget.activeOverride ?? _isReasoningInProgress(widget.item);
    final showStatus = widget.showStatus;
    if (body.isEmpty && !showStatus) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showStatus)
          _ReasoningStatusLine(
            workspaceStyle: widget.workspaceStyle,
            active: active,
          ),
        if (showStatus && body.isNotEmpty)
          SizedBox(height: widget.workspaceStyle ? 6 : 8),
        if (body.isNotEmpty)
          _MarkdownTextBody(data: body, workspaceStyle: widget.workspaceStyle),
      ],
    );
  }
}

class _ReasoningStatusLine extends StatelessWidget {
  const _ReasoningStatusLine({
    required this.workspaceStyle,
    required this.active,
  });

  final bool workspaceStyle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = active
        ? _localizedText(context, 'Thinking', '正在思考')
        : _localizedText(context, 'Thought complete', '思考完成');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: secondaryTextColor(theme),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (active) ...[
          SizedBox(width: workspaceStyle ? 6 : 8),
          _ThinkingDots(workspaceStyle: workspaceStyle),
        ],
      ],
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots({required this.workspaceStyle});

  final bool workspaceStyle;

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dotColor = secondaryTextColor(theme);
    final dotSize = widget.workspaceStyle ? 4.0 : 5.0;
    final gap = widget.workspaceStyle ? 4.0 : 5.0;
    final travel = widget.workspaceStyle ? 3.0 : 4.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          key: const ValueKey('reasoning-thinking-dots'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < 3; index += 1) ...[
              if (index > 0) SizedBox(width: gap),
              Transform.translate(
                offset: Offset(0, _dotOffset(index, travel)),
                child: Opacity(
                  opacity: _dotOpacity(index),
                  child: Container(
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  double _dotOffset(int index, double travel) {
    final progress = _dotProgress(index);
    if (progress < 0.18) {
      return -travel * (progress / 0.18);
    }
    if (progress < 0.36) {
      return -travel * (1 - ((progress - 0.18) / 0.18));
    }
    return 0;
  }

  double _dotOpacity(int index) {
    final progress = _dotProgress(index);
    if (progress < 0.18) {
      return 0.45 + (progress / 0.18) * 0.55;
    }
    if (progress < 0.36) {
      return 0.45 + (1 - ((progress - 0.18) / 0.18)) * 0.55;
    }
    return 0.45;
  }

  double _dotProgress(int index) {
    var value = _controller.value - (index * 0.14);
    while (value < 0) {
      value += 1;
    }
    while (value >= 1) {
      value -= 1;
    }
    return value;
  }
}

class _PlanMessageBody extends StatelessWidget {
  const _PlanMessageBody({
    required this.item,
    required this.planState,
    required this.workspaceStyle,
  });

  final CodexThreadItem item;
  final _PlanState planState;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completedCount = planState.steps
        .where((step) => step.status == _PlanStepStatus.completed)
        .length;
    final progressLabel = _localizedPlanProgressLabel(
      context,
      completed: completedCount,
      total: planState.steps.length,
    );

    return Container(
      key: ValueKey('plan-card:${item.id}'),
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(workspaceStyle ? 14 : 16),
        border: Border.all(color: borderColor(theme)),
      ),
      padding: EdgeInsets.fromLTRB(
        workspaceStyle ? 12 : 14,
        workspaceStyle ? 10 : 12,
        workspaceStyle ? 12 : 14,
        workspaceStyle ? 10 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            progressLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: secondaryTextColor(theme),
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: workspaceStyle ? 10 : 12),
          for (var index = 0; index < planState.steps.length; index += 1) ...[
            if (index > 0) SizedBox(height: workspaceStyle ? 8 : 10),
            _PlanStepRow(
              index: index,
              step: planState.steps[index],
              workspaceStyle: workspaceStyle,
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanStepRow extends StatelessWidget {
  const _PlanStepRow({
    required this.index,
    required this.step,
    required this.workspaceStyle,
  });

  final int index;
  final _PlanStep step;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = switch (step.status) {
      _PlanStepStatus.completed => theme.colorScheme.primary,
      _PlanStepStatus.inProgress => theme.colorScheme.secondary,
      _PlanStepStatus.pending => secondaryTextColor(theme),
    };
    final icon = switch (step.status) {
      _PlanStepStatus.completed => Icons.check_circle_rounded,
      _PlanStepStatus.inProgress => Icons.adjust_rounded,
      _PlanStepStatus.pending => Icons.radio_button_unchecked_rounded,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: workspaceStyle ? 16 : 18, color: iconColor),
        ),
        SizedBox(width: workspaceStyle ? 8 : 10),
        Expanded(
          child: Text(
            '${index + 1}. ${step.label}',
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.45,
              color: theme.colorScheme.onSurface,
              decoration: step.status == _PlanStepStatus.completed
                  ? TextDecoration.lineThrough
                  : null,
              decorationColor: theme.colorScheme.onSurface.withValues(
                alpha: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StructuredUserMessageBody extends StatelessWidget {
  const _StructuredUserMessageBody({
    required this.parts,
    required this.workspaceStyle,
  });

  final List<UserMessagePart> parts;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final spacing = workspaceStyle ? 8.0 : 10.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < parts.length; index += 1) ...[
          _UserMessagePartView(
            part: parts[index],
            workspaceStyle: workspaceStyle,
          ),
          if (index < parts.length - 1) SizedBox(height: spacing),
        ],
      ],
    );
  }
}

class _UserMessagePartView extends StatelessWidget {
  const _UserMessagePartView({
    required this.part,
    required this.workspaceStyle,
  });

  final UserMessagePart part;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    switch (part.type) {
      case UserMessagePartType.image:
        return _MessageImageView(
          imageProvider: _providerForUrl(part.url),
          fallbackLabel: '[image]',
          caption: _captionForRemoteImage(part.url),
          workspaceStyle: workspaceStyle,
        );
      case UserMessagePartType.localImage:
        return _MessageImageView(
          imageProvider: _providerForLocalPath(part.path),
          fallbackLabel: part.text,
          caption: null,
          workspaceStyle: workspaceStyle,
        );
      case UserMessagePartType.mention:
        if (_isLocalFileMention(part)) {
          return _MessageAttachmentView(
            icon: Icons.attach_file_rounded,
            label: part.name ?? _basename(part.path),
            caption: _fileMentionCaption(part),
            workspaceStyle: workspaceStyle,
          );
        }
        return _MarkdownTextBody(
          data: part.text,
          workspaceStyle: workspaceStyle,
        );
      default:
        return _MarkdownTextBody(
          data: part.text,
          workspaceStyle: workspaceStyle,
        );
    }
  }
}

class _MarkdownTextBody extends StatelessWidget {
  const _MarkdownTextBody({
    required this.data,
    required this.workspaceStyle,
    this.fallbackStyle,
  });

  final String data;
  final bool workspaceStyle;
  final TextStyle? fallbackStyle;

  @override
  Widget build(BuildContext context) {
    final trimmed = data.trimRight();
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }
    final fencedSegments = _parseFencedCodeSegments(trimmed);
    if (fencedSegments != null) {
      return _SegmentedMarkdownBody(
        segments: fencedSegments,
        workspaceStyle: workspaceStyle,
        fallbackStyle: fallbackStyle,
      );
    }
    return _SafeMarkdownBody(
      data: trimmed,
      workspaceStyle: workspaceStyle,
      fallbackStyle: fallbackStyle,
    );
  }
}

class _SegmentedMarkdownBody extends StatelessWidget {
  const _SegmentedMarkdownBody({
    required this.segments,
    required this.workspaceStyle,
    this.fallbackStyle,
  });

  final List<_FencedCodeSegment> segments;
  final bool workspaceStyle;
  final TextStyle? fallbackStyle;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final segment in segments) {
      if (segment.isCode) {
        children.add(
          _CodeSurface(
            code: segment.content,
            language: segment.language,
            workspaceStyle: workspaceStyle,
          ),
        );
        continue;
      }
      if (segment.content.trim().isEmpty) {
        continue;
      }
      children.add(
        _SafeMarkdownBody(
          data: segment.content,
          workspaceStyle: workspaceStyle,
          fallbackStyle: fallbackStyle,
        ),
      );
    }
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    if (children.length == 1) {
      return children.single;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < children.length; index += 1) ...[
          if (index > 0) SizedBox(height: workspaceStyle ? 8 : 10),
          children[index],
        ],
      ],
    );
  }
}

class _FencedCodeSegment {
  const _FencedCodeSegment.text(this.content) : language = null, isCode = false;

  const _FencedCodeSegment.code(this.content, {this.language}) : isCode = true;

  final String content;
  final String? language;
  final bool isCode;
}

List<_FencedCodeSegment>? _parseFencedCodeSegments(String value) {
  final normalized = value.trimRight();
  if (!normalized.contains('```')) {
    return null;
  }

  final lines = const LineSplitter().convert(normalized);
  final segments = <_FencedCodeSegment>[];
  final textBuffer = <String>[];
  final codeBuffer = <String>[];
  String? activeLanguage;
  var insideFence = false;
  var sawFence = false;

  void flushText() {
    if (textBuffer.isEmpty) {
      return;
    }
    segments.add(_FencedCodeSegment.text(textBuffer.join('\n')));
    textBuffer.clear();
  }

  void flushCode() {
    segments.add(
      _FencedCodeSegment.code(codeBuffer.join('\n'), language: activeLanguage),
    );
    codeBuffer.clear();
    activeLanguage = null;
  }

  for (final line in lines) {
    final trimmedLeft = line.trimLeft();
    if (trimmedLeft.startsWith('```')) {
      final fenceMarker = trimmedLeft.substring(3).trim();
      if (!insideFence) {
        sawFence = true;
        flushText();
        activeLanguage = fenceMarker.isEmpty ? null : fenceMarker;
        insideFence = true;
      } else {
        flushCode();
        insideFence = false;
      }
      continue;
    }

    if (insideFence) {
      codeBuffer.add(line);
    } else {
      textBuffer.add(line);
    }
  }

  if (!sawFence || insideFence) {
    return null;
  }

  flushText();
  return segments.isEmpty ? null : segments;
}

class _MessageAttachmentView extends StatelessWidget {
  const _MessageAttachmentView({
    required this.icon,
    required this.label,
    required this.caption,
    required this.workspaceStyle,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(workspaceStyle ? 12 : 14),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          workspaceStyle ? 10 : 12,
          workspaceStyle ? 8 : 10,
          workspaceStyle ? 10 : 12,
          workspaceStyle ? 8 : 10,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: workspaceStyle ? 16 : 18),
            SizedBox(width: workspaceStyle ? 8 : 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.trim().isEmpty
                        ? _localizedText(context, 'Attachment', '附件')
                        : label.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if ((caption?.trim() ?? '').isNotEmpty)
                    Text(
                      caption!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryTextColor(theme),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafeMarkdownBody extends StatefulWidget {
  const _SafeMarkdownBody({
    required this.data,
    required this.workspaceStyle,
    this.fallbackStyle,
  });

  final String data;
  final bool workspaceStyle;
  final TextStyle? fallbackStyle;

  @override
  State<_SafeMarkdownBody> createState() => _SafeMarkdownBodyState();
}

class _SafeMarkdownBodyState extends State<_SafeMarkdownBody>
    implements MarkdownBuilderDelegate {
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];
  List<Widget>? _children;
  Object? _renderError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parseMarkdown();
  }

  @override
  void didUpdateWidget(covariant _SafeMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.workspaceStyle != widget.workspaceStyle ||
        oldWidget.fallbackStyle != widget.fallbackStyle) {
      _parseMarkdown();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _parseMarkdown() {
    final theme = Theme.of(context);
    final styleSheet = _markdownStyleSheet(
      theme,
      workspaceStyle: widget.workspaceStyle,
    );
    _disposeRecognizers();

    try {
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      );
      final astNodes = document.parseLines(
        const LineSplitter().convert(widget.data),
      );
      final builder = MarkdownBuilder(
        delegate: this,
        selectable: true,
        styleSheet: styleSheet,
        imageDirectory: null,
        sizedImageBuilder: null,
        checkboxBuilder: null,
        bulletBuilder: null,
        builders: {
          'pre': _MarkdownCodeBlockBuilder(
            workspaceStyle: widget.workspaceStyle,
          ),
        },
        paddingBuilders: const {},
        fitContent: true,
        listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
        softLineBreak: true,
      );
      _children = builder.build(astNodes);
      _renderError = null;
    } catch (error) {
      _children = null;
      _renderError = error;
    }
  }

  void _disposeRecognizers() {
    if (_recognizers.isEmpty) {
      return;
    }
    final localRecognizers = List<GestureRecognizer>.from(_recognizers);
    _recognizers.clear();
    for (final recognizer in localRecognizers) {
      recognizer.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = _children;
    if (_renderError != null || children == null) {
      return SelectableText(
        widget.data,
        style:
            widget.fallbackStyle ??
            theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.45,
            ),
      );
    }
    if (children.length == 1) {
      return children.single;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer();
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    code = code.replaceAll(RegExp(r'\n$'), '');
    return TextSpan(style: styleSheet.code, text: code);
  }
}

class _MessageImageView extends StatelessWidget {
  const _MessageImageView({
    required this.imageProvider,
    required this.fallbackLabel,
    required this.workspaceStyle,
    this.caption,
  });

  final ImageProvider<Object>? imageProvider;
  final String fallbackLabel;
  final String? caption;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = workspaceStyle ? 340.0 : 380.0;
    final image = imageProvider;
    if (image == null) {
      return _ImageFallbackCard(
        label: fallbackLabel,
        caption: caption,
        workspaceStyle: workspaceStyle,
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('message-image-preview'),
          onTap: () => _showPreview(context, image),
          borderRadius: BorderRadius.circular(workspaceStyle ? 14 : 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(workspaceStyle ? 14 : 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor(theme)),
                borderRadius: BorderRadius.circular(workspaceStyle ? 14 : 16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image(
                    image: image,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _ImageFallbackCard(
                          label: fallbackLabel,
                          caption: caption,
                          workspaceStyle: workspaceStyle,
                        ),
                  ),
                  if (caption != null && caption!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: Text(
                        caption!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondaryTextColor(theme),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPreview(
    BuildContext context,
    ImageProvider<Object> image,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: panelBackgroundColor(theme),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor(theme)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
                    child: Row(
                      children: [
                        Text(
                          _localizedText(dialogContext, 'Preview', '预览'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: _localizedText(
                            dialogContext,
                            'Close preview',
                            '关闭预览',
                          ),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: mutedPanelBackgroundColor(theme),
                            border: Border.all(color: borderColor(theme)),
                          ),
                          child: InteractiveViewer(
                            minScale: 1,
                            maxScale: 5,
                            child: Center(
                              child: Image(
                                image: image,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    _ImageFallbackCard(
                                      label: fallbackLabel,
                                      caption: caption,
                                      workspaceStyle: workspaceStyle,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (caption != null && caption!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Text(
                        caption!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: secondaryTextColor(theme),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ImageFallbackCard extends StatelessWidget {
  const _ImageFallbackCard({
    required this.label,
    required this.workspaceStyle,
    this.caption,
  });

  final String label;
  final String? caption;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF0E1116)
            : const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(workspaceStyle ? 14 : 16),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            if (caption != null && caption!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                caption!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondaryTextColor(theme),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmbeddedCommandExecutionCard extends StatefulWidget {
  const _EmbeddedCommandExecutionCard({
    required this.item,
    required this.workspaceStyle,
  });

  final CodexThreadItem item;
  final bool workspaceStyle;

  @override
  State<_EmbeddedCommandExecutionCard> createState() =>
      _EmbeddedCommandExecutionCardState();
}

class _EmbeddedCommandExecutionCardState
    extends State<_EmbeddedCommandExecutionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final commandLabel = _commandExecutionLabel(item, context);
    final cwd = item.raw['cwd']?.toString().trim() ?? '';
    final exitCode = item.raw['exitCode']?.toString().trim() ?? '';
    final output = _commandExecutionOutput(item);
    final canExpand = _canShowCommandDisclosure(cwd, exitCode, output);

    return DecoratedBox(
      key: ValueKey('assistant-group-command-card:${widget.item.id}'),
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(widget.workspaceStyle ? 14 : 16),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: canExpand
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(
              widget.workspaceStyle ? 14 : 16,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                widget.workspaceStyle ? 12 : 14,
                widget.workspaceStyle ? 9 : 10,
                widget.workspaceStyle ? 12 : 14,
                widget.workspaceStyle ? 9 : 10,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: widget.workspaceStyle ? 22 : 24,
                    height: widget.workspaceStyle ? 22 : 24,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.terminal,
                      size: widget.workspaceStyle ? 13 : 14,
                      color: secondaryTextColor(theme),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      commandLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appCodeTextStyle(theme.textTheme.bodyMedium)
                          .copyWith(
                            fontSize: widget.workspaceStyle ? 12 : 12.5,
                            fontWeight: FontWeight.w500,
                            color: secondaryTextColor(theme),
                          ),
                    ),
                  ),
                  if (canExpand) ...[
                    const SizedBox(width: 6),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: widget.workspaceStyle ? 16 : 18,
                      color: secondaryTextColor(theme),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded && canExpand)
            Padding(
              padding: EdgeInsets.fromLTRB(
                widget.workspaceStyle ? 12 : 14,
                0,
                widget.workspaceStyle ? 12 : 14,
                widget.workspaceStyle ? 12 : 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cwd.isNotEmpty || exitCode.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (cwd.isNotEmpty)
                          _InlineMetaBadge(
                            value:
                                '${_localizedText(context, 'Working directory', '工作目录')}: $cwd',
                            workspaceStyle: widget.workspaceStyle,
                          ),
                        if (exitCode.isNotEmpty)
                          _InlineMetaBadge(
                            value:
                                '${_localizedText(context, 'Exit code', '退出码')}: $exitCode',
                            workspaceStyle: widget.workspaceStyle,
                          ),
                      ],
                    ),
                  if (cwd.isNotEmpty || exitCode.isNotEmpty)
                    const SizedBox(height: 10),
                  if (output != null)
                    _CodeSurface(
                      code: output,
                      workspaceStyle: widget.workspaceStyle,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EmbeddedFileChangeCard extends StatelessWidget {
  const _EmbeddedFileChangeCard({
    required this.entries,
    required this.workspaceStyle,
  });

  final List<CodexFileChangeEntry> entries;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    return FileChangeCardList(entries: entries, workspaceStyle: workspaceStyle);
  }
}

class _EmbeddedFileChangeGroup extends StatelessWidget {
  const _EmbeddedFileChangeGroup({
    required this.item,
    required this.entries,
    required this.workspaceStyle,
  });

  final CodexThreadItem item;
  final List<CodexFileChangeEntry> entries;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('assistant-group-file-card:${item.id}'),
      child: _EmbeddedFileChangeCard(
        entries: entries,
        workspaceStyle: workspaceStyle,
      ),
    );
  }
}

class _WebSearchMessageBody extends StatelessWidget {
  const _WebSearchMessageBody({
    required this.item,
    required this.workspaceStyle,
  });

  final CodexThreadItem item;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _webSearchSummary(context, item);
    final accentColor = theme.colorScheme.primary;
    final primaryText = summary.primaryText;
    final secondaryText = summary.secondaryText;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(workspaceStyle ? 14 : 16),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: workspaceStyle ? 22 : 24,
                  height: workspaceStyle ? 22 : 24,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    summary.icon,
                    size: workspaceStyle ? 13 : 14,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _InlineMetaBadge(
                  value: summary.kindLabel,
                  workspaceStyle: workspaceStyle,
                ),
              ],
            ),
            if (primaryText.isNotEmpty) ...[
              SizedBox(height: workspaceStyle ? 8 : 10),
              SelectableText(
                primaryText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
            if (secondaryText != null && secondaryText.trim().isNotEmpty) ...[
              SizedBox(height: workspaceStyle ? 6 : 8),
              SelectableText(
                secondaryText,
                style: appCodeTextStyle(theme.textTheme.bodySmall).copyWith(
                  color: secondaryTextColor(theme),
                  fontSize: workspaceStyle ? 11.5 : 12,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InlineMetaBadge extends StatelessWidget {
  const _InlineMetaBadge({required this.value, required this.workspaceStyle});

  final String value;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: mutedPanelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: workspaceStyle ? 7 : 8,
          vertical: workspaceStyle ? 3 : 4,
        ),
        child: Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            color: secondaryTextColor(theme),
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

bool _preferPreformatted(CodexThreadItem item) {
  switch (item.type) {
    case 'command.execution':
    case 'file.change':
    case 'mcp.tool.call':
    case 'tool.call':
    case 'agent.tool.call':
      return true;
    default:
      return false;
  }
}

String? _itemPhase(CodexThreadItem item) {
  final value = item.raw['phase']?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

MarkdownStyleSheet _markdownStyleSheet(
  ThemeData theme, {
  required bool workspaceStyle,
}) {
  final base = MarkdownStyleSheet.fromTheme(theme);
  final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
    height: 1.55,
    color: theme.brightness == Brightness.dark
        ? const Color(0xFFE6EDF5)
        : theme.colorScheme.onSurface,
  );
  final inlineCodeBackground = theme.brightness == Brightness.dark
      ? const Color(0xFF0F1319)
      : const Color(0xFFF3F6FB);
  final blockBackground = theme.brightness == Brightness.dark
      ? const Color(0xFF0E1116)
      : const Color(0xFFFBFCFE);

  return base.copyWith(
    p: bodyStyle,
    pPadding: EdgeInsets.zero,
    code: _codeTextStyle(theme).copyWith(
      backgroundColor: inlineCodeBackground,
      color: theme.brightness == Brightness.dark
          ? const Color(0xFF9CDCFE)
          : const Color(0xFF0B62A8),
      fontSize: workspaceStyle ? 13 : 13.5,
    ),
    h1: theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
    h1Padding: const EdgeInsets.only(bottom: 6),
    h2: theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
    h2Padding: const EdgeInsets.only(bottom: 6),
    h3: theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
    h3Padding: const EdgeInsets.only(bottom: 4),
    h4: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
    h4Padding: const EdgeInsets.only(bottom: 4),
    h5: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
    h5Padding: const EdgeInsets.only(bottom: 4),
    h6: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
    h6Padding: const EdgeInsets.only(bottom: 4),
    strong: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
    em: bodyStyle?.copyWith(fontStyle: FontStyle.italic),
    a: bodyStyle?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    ),
    blockSpacing: workspaceStyle ? 8 : 10,
    listIndent: workspaceStyle ? 20 : 24,
    listBullet: bodyStyle?.copyWith(color: secondaryTextColor(theme)),
    listBulletPadding: const EdgeInsets.only(right: 8),
    blockquote: bodyStyle?.copyWith(
      color: secondaryTextColor(theme),
      height: 1.5,
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
    blockquoteDecoration: BoxDecoration(
      color: blockBackground,
      borderRadius: BorderRadius.circular(workspaceStyle ? 12 : 14),
      border: Border(
        left: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.6),
          width: 3,
        ),
      ),
    ),
    codeblockPadding: const EdgeInsets.all(0),
    codeblockDecoration: const BoxDecoration(),
    tableBorder: TableBorder.all(color: borderColor(theme)),
    tableCellsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    tableCellsDecoration: BoxDecoration(
      color: blockBackground,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

TextStyle _codeTextStyle(ThemeData theme) {
  return appCodeTextStyle(theme.textTheme.bodyMedium);
}

class _MarkdownCodeBlockBuilder extends MarkdownElementBuilder {
  _MarkdownCodeBlockBuilder({required this.workspaceStyle});

  final bool workspaceStyle;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    md.Element? codeElement;
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        codeElement = child;
        break;
      }
    }

    final rawClass = codeElement?.attributes['class'];
    final language = _languageFromClassName(rawClass);
    final code = (codeElement?.textContent ?? element.textContent).trimRight();
    if (code.isEmpty) {
      return const SizedBox.shrink();
    }

    return _CodeSurface(
      code: code,
      language: language,
      workspaceStyle: workspaceStyle,
    );
  }
}

String? _languageFromClassName(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return null;
  }
  final match = RegExp(r'language-([\w#+.-]+)').firstMatch(normalized);
  return match?.group(1);
}

class _CodeSurface extends StatelessWidget {
  const _CodeSurface({
    required this.code,
    this.language,
    this.workspaceStyle = false,
  });

  final String code;
  final String? language;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chromeBackground = theme.brightness == Brightness.dark
        ? const Color(0xFF0E1116)
        : const Color(0xFFF8FAFD);
    final headerBackground = theme.brightness == Brightness.dark
        ? const Color(0xFF121720)
        : const Color(0xFFF2F5FA);
    final highlighter = _VsCodeSyntaxHighlighter(theme);
    final textSpan = highlighter.format(code, language: language);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: chromeBackground,
        borderRadius: BorderRadius.circular(workspaceStyle ? 12 : 14),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language != null && language!.trim().isNotEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                color: headerBackground,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(workspaceStyle ? 12 : 14),
                ),
                border: Border(bottom: BorderSide(color: borderColor(theme))),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                child: Text(
                  language!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondaryTextColor(theme),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: SelectableText.rich(
              textSpan,
              style: _codeTextStyle(theme).copyWith(
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFFD4D4D4)
                    : const Color(0xFF1F2328),
                fontSize: workspaceStyle ? 13 : 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

ImageProvider<Object>? _providerForUrl(String? url) {
  final value = url?.trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  if (value.startsWith('data:')) {
    try {
      final data = UriData.parse(value);
      return MemoryImage(data.contentAsBytes());
    } catch (_) {
      return null;
    }
  }
  final uri = Uri.tryParse(value);
  if (uri == null) {
    return null;
  }
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    return NetworkImage(value);
  }
  if (uri.scheme == 'file' && uri.toFilePath().trim().isNotEmpty) {
    return FileImage(File(uri.toFilePath()));
  }
  return null;
}

ImageProvider<Object>? _providerForLocalPath(String? path) {
  final value = path?.trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  final file = File(value);
  return file.existsSync() ? FileImage(file) : null;
}

ImageProvider<Object>? _providerForImageReference(String? reference) {
  final localProvider = _providerForLocalPath(reference);
  if (localProvider != null) {
    return localProvider;
  }
  return _providerForUrl(reference);
}

String? _captionForRemoteImage(String? url) {
  final value = url?.trim() ?? '';
  if (value.isEmpty || value.startsWith('data:')) {
    return null;
  }
  return value;
}

String? _captionForImageReference(String? reference) {
  final value = reference?.trim() ?? '';
  if (value.isEmpty || value.startsWith('data:')) {
    return null;
  }
  return value;
}

enum _PlanStepStatus { completed, inProgress, pending }

class _PlanStep {
  const _PlanStep({required this.label, required this.status});

  final String label;
  final _PlanStepStatus status;
}

class _PlanState {
  const _PlanState({required this.steps});

  final List<_PlanStep> steps;
}

bool _isLocalFileMention(UserMessagePart part) {
  final path = part.path?.trim() ?? '';
  return path.isNotEmpty && !path.contains('://');
}

String? _fileMentionCaption(UserMessagePart part) {
  final basename = _basename(part.path);
  if (basename.isEmpty) {
    return null;
  }
  final label = (part.name ?? '').trim();
  return label == basename ? null : basename;
}

String _basename(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return '';
  }
  final pieces = normalized
      .split(RegExp(r'[\\/]'))
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  if (pieces.isEmpty) {
    return normalized;
  }
  return pieces.last;
}

String? _imageReferenceForItem(CodexThreadItem item) {
  if (item.type != 'image.view' && item.type != 'image.generation') {
    return null;
  }
  for (final value in <Object?>[
    item.raw['savedPath'],
    item.raw['path'],
    item.raw['url'],
    item.raw['result'],
    item.body,
  ]) {
    final candidate = value?.toString().trim() ?? '';
    if (_providerForImageReference(candidate) != null) {
      return candidate;
    }
  }
  return null;
}

List<CodexThreadItem> _assistantGroupItemsFromRaw(Map<String, dynamic> raw) {
  final value = raw['bubbleItems'];
  if (value is List) {
    return value.whereType<CodexThreadItem>().toList(growable: false);
  }
  return const [];
}

bool _shouldShowAssistantGroupLabel(CodexThreadItem item) {
  return item.type != 'agent.message' &&
      item.type != 'reasoning' &&
      item.type != 'command.execution' &&
      item.type != 'file.change' &&
      item.type != 'web.search';
}

String _localizedAssistantGroupLabel(
  BuildContext context,
  CodexThreadItem item,
) {
  switch (item.type) {
    case 'reasoning':
      return _localizedText(context, 'Reasoning', '思考');
    case 'plan':
      return _localizedText(context, 'Plan', '计划');
    default:
      return item.title;
  }
}

int _assistantGroupFileCount(List<CodexThreadItem> items) {
  var count = 0;
  for (final item in items) {
    if (item.type != 'file.change') {
      continue;
    }
    final entries = parseCodexFileChangeEntries(item);
    count += entries.isEmpty ? 1 : entries.length;
  }
  return count;
}

String _assistantGroupOperationSummaryText(
  BuildContext context, {
  required int commandCount,
  required int fileCount,
}) {
  if (fileCount > 0 && commandCount > 0) {
    return _localizedText(
      context,
      'Edited $fileCount file${fileCount == 1 ? '' : 's'} and ran $commandCount command${commandCount == 1 ? '' : 's'}',
      '编辑了 $fileCount 个文件，执行了 $commandCount 条命令',
    );
  }
  if (fileCount > 0) {
    return _localizedText(
      context,
      'Edited $fileCount file${fileCount == 1 ? '' : 's'}',
      '编辑了 $fileCount 个文件',
    );
  }
  return _localizedText(
    context,
    'Ran $commandCount command${commandCount == 1 ? '' : 's'}',
    '执行了 $commandCount 条命令',
  );
}

String _localizedText(BuildContext context, String english, String chinese) {
  final strings = Localizations.of<AppStrings>(context, AppStrings);
  if (strings == null) {
    return english;
  }
  return strings.text(english, chinese);
}

String _localizedPlanProgressLabel(
  BuildContext context, {
  required int completed,
  required int total,
}) {
  final strings = Localizations.of<AppStrings>(context, AppStrings);
  if (strings == null || !strings.isChinese) {
    return '$completed out of $total tasks completed';
  }
  return '已完成 $completed / $total 项任务';
}

_PlanState? _planStateFromItem(CodexThreadItem item) {
  final structured = _planStepsFromStructuredRaw(item.raw);
  if (structured.isNotEmpty) {
    return _PlanState(steps: structured);
  }

  final parsed = _planStepsFromBody(item.body);
  if (parsed.isNotEmpty) {
    return _PlanState(steps: parsed);
  }
  return null;
}

List<_PlanStep> _planStepsFromStructuredRaw(Map<String, dynamic> raw) {
  const candidateKeys = ['steps', 'plan', 'items'];
  for (final key in candidateKeys) {
    final steps = asJsonList(raw[key]);
    if (steps.isEmpty) {
      continue;
    }
    final parsed = steps
        .map(asJsonMap)
        .map(_planStepFromMap)
        .whereType<_PlanStep>()
        .toList(growable: false);
    if (parsed.isNotEmpty) {
      return parsed;
    }
  }
  return const [];
}

_PlanStep? _planStepFromMap(Map<String, dynamic> raw) {
  if (raw.isEmpty) {
    return null;
  }
  final label = readString(raw, const [
    'step',
    'title',
    'text',
    'label',
    'description',
    'name',
  ]).trim();
  if (label.isEmpty) {
    return null;
  }
  return _PlanStep(
    label: label,
    status: _planStepStatusFromValue(raw['status']),
  );
}

List<_PlanStep> _planStepsFromBody(String body) {
  final trimmedBody = body.trim();
  if (trimmedBody.isEmpty) {
    return const [];
  }
  final lines = const LineSplitter().convert(trimmedBody);
  final steps = <_PlanStep>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }

    final checkboxMatch = RegExp(
      r'^[-*]\s+\[( |x|X)\]\s+(.*)$',
    ).firstMatch(trimmed);
    if (checkboxMatch != null) {
      final checked = checkboxMatch.group(1)?.toLowerCase() == 'x';
      final label = checkboxMatch.group(2)?.trim() ?? '';
      if (label.isNotEmpty) {
        steps.add(
          _PlanStep(
            label: label,
            status: checked
                ? _PlanStepStatus.completed
                : _PlanStepStatus.pending,
          ),
        );
      }
      continue;
    }

    final numberedMatch = RegExp(r'^\d+[.)]\s+(.*)$').firstMatch(trimmed);
    if (numberedMatch != null) {
      final label = numberedMatch.group(1)?.trim() ?? '';
      if (label.isNotEmpty) {
        steps.add(_PlanStep(label: label, status: _PlanStepStatus.pending));
      }
    }
  }
  return steps;
}

_PlanStepStatus _planStepStatusFromValue(Object? value) {
  final status = value?.toString().trim().toLowerCase() ?? '';
  switch (status) {
    case 'completed':
    case 'done':
      return _PlanStepStatus.completed;
    case 'in_progress':
    case 'in-progress':
    case 'active':
    case 'started':
    case 'running':
    case 'current':
      return _PlanStepStatus.inProgress;
    default:
      return _PlanStepStatus.pending;
  }
}

String? _commandExecutionOutput(CodexThreadItem item) {
  final aggregated = item.raw['aggregatedOutput']?.toString().trim() ?? '';
  if (aggregated.isNotEmpty) {
    return aggregated;
  }

  final body = item.body.trimRight();
  if (body.isEmpty) {
    return null;
  }

  final cwd = item.raw['cwd']?.toString().trim() ?? '';
  final exitCode = item.raw['exitCode']?.toString().trim() ?? '';
  if (cwd.isNotEmpty || exitCode.isNotEmpty) {
    final syntheticOutput =
        'cwd: $cwd\nexitCode: ${exitCode.isEmpty ? 'n/a' : exitCode}';
    if (body.trim() == syntheticOutput) {
      return null;
    }
  }
  return body;
}

String _commandExecutionLabel(CodexThreadItem item, BuildContext context) {
  return commandExecutionDisplayLabel(
    item.raw,
    fallback: item.title.trim().isEmpty
        ? _localizedText(context, 'Command', '命令')
        : item.title.trim(),
  );
}

bool _canShowCommandDisclosure(String cwd, String exitCode, String? output) {
  return cwd.isNotEmpty || exitCode.isNotEmpty || (output?.isNotEmpty ?? false);
}

bool _isReasoningInProgress(CodexThreadItem item) {
  final status = item.status.trim().toLowerCase();
  return status == 'started' ||
      status == 'starting' ||
      status == 'in_progress' ||
      status == 'streaming' ||
      status == 'running' ||
      status == 'active';
}

bool _hasLaterAssistantReply(List<CodexThreadItem> items, int index) {
  for (var cursor = index + 1; cursor < items.length; cursor += 1) {
    final item = items[cursor];
    switch (item.type) {
      case 'agent.message':
        if (_itemPhase(item) == 'final_answer' && item.body.trim().isNotEmpty) {
          return true;
        }
      case 'assistant.group':
      case 'image.view':
      case 'image.generation':
        return true;
      default:
        break;
    }
  }
  return false;
}

_WebSearchSummary _webSearchSummary(
  BuildContext context,
  CodexThreadItem item,
) {
  final action = asJsonMap(item.raw['action']);
  final actionType = readString(action, const ['type']).trim();
  final query = readString(
    action,
    const ['query'],
    fallback: readString(item.raw, const ['query'], fallback: item.title),
  ).trim();
  final url = readString(action, const [
    'url',
  ], fallback: readString(item.raw, const ['url'])).trim();
  final fallbackBody = item.body.trim();

  switch (actionType) {
    case 'openPage':
      return _WebSearchSummary(
        label: _localizedText(context, 'Opened page', '已打开网页'),
        kindLabel: _localizedText(context, 'Open', '打开'),
        primaryText: url.isNotEmpty
            ? url
            : (query.isNotEmpty ? query : fallbackBody),
        secondaryText: query.isNotEmpty && query != url ? query : null,
        icon: Icons.open_in_browser_rounded,
      );
    case 'search':
    default:
      return _WebSearchSummary(
        label: _localizedText(context, 'Web search', '网页搜索'),
        kindLabel: _localizedText(context, 'Search', '搜索'),
        primaryText: query.isNotEmpty ? query : fallbackBody,
        secondaryText: url.isNotEmpty && url != query ? url : null,
        icon: Icons.travel_explore_rounded,
      );
  }
}

class _WebSearchSummary {
  const _WebSearchSummary({
    required this.label,
    required this.kindLabel,
    required this.primaryText,
    required this.secondaryText,
    required this.icon,
  });

  final String label;
  final String kindLabel;
  final String primaryText;
  final String? secondaryText;
  final IconData icon;
}

class _VsCodeSyntaxHighlighter {
  _VsCodeSyntaxHighlighter(this.theme);

  final ThemeData theme;

  TextSpan format(String source, {String? language}) {
    if (source.trim().isEmpty) {
      return TextSpan(text: source, style: _baseStyle);
    }

    final normalizedLanguage = language?.trim() ?? '';
    if (normalizedLanguage.isEmpty) {
      return TextSpan(text: source, style: _baseStyle);
    }

    try {
      final result = highlight.highlight.parse(
        source,
        language: normalizedLanguage,
      );
      final spans = _nodesToSpans(result.nodes);
      if (spans.isEmpty) {
        return TextSpan(text: source, style: _baseStyle);
      }
      return TextSpan(style: _baseStyle, children: spans);
    } catch (_) {
      return TextSpan(text: source, style: _baseStyle);
    }
  }

  TextStyle get _baseStyle => _codeTextStyle(theme).copyWith(
    color: theme.brightness == Brightness.dark
        ? const Color(0xFFD4D4D4)
        : const Color(0xFF1F2328),
  );

  List<InlineSpan> _nodesToSpans(List<highlight.Node>? nodes) {
    if (nodes == null) {
      return const [];
    }
    return nodes.map(_nodeToSpan).toList(growable: false);
  }

  InlineSpan _nodeToSpan(highlight.Node node) {
    final style = _baseStyle.merge(_styleForToken(node.className));
    if (node.value != null) {
      return TextSpan(text: node.value, style: style);
    }
    return TextSpan(style: style, children: _nodesToSpans(node.children));
  }

  TextStyle? _styleForToken(String? className) {
    if (className == null || className.trim().isEmpty) {
      return null;
    }

    final token = className.toLowerCase();
    final dark = theme.brightness == Brightness.dark;

    if (_matchesAny(token, const ['comment', 'quote', 'doctag'])) {
      return TextStyle(
        color: dark ? const Color(0xFF6A9955) : const Color(0xFF008000),
        fontStyle: FontStyle.italic,
      );
    }
    if (_matchesAny(token, const ['keyword', 'meta-keyword'])) {
      return TextStyle(
        color: dark ? const Color(0xFFC586C0) : const Color(0xFF0000FF),
      );
    }
    if (_matchesAny(token, const ['string', 'regexp'])) {
      return TextStyle(
        color: dark ? const Color(0xFFCE9178) : const Color(0xFFA31515),
      );
    }
    if (_matchesAny(token, const ['number', 'literal', 'symbol', 'bullet'])) {
      return TextStyle(
        color: dark ? const Color(0xFFB5CEA8) : const Color(0xFF098658),
      );
    }
    if (_matchesAny(token, const ['type', 'class', 'built_in'])) {
      return TextStyle(
        color: dark ? const Color(0xFF4EC9B0) : const Color(0xFF267F99),
      );
    }
    if (_matchesAny(token, const ['title', 'function', 'section'])) {
      return TextStyle(
        color: dark ? const Color(0xFFDCDCAA) : const Color(0xFF795E26),
      );
    }
    if (_matchesAny(token, const ['tag', 'name'])) {
      return TextStyle(
        color: dark ? const Color(0xFF569CD6) : const Color(0xFF800000),
      );
    }
    if (_matchesAny(token, const ['attr', 'attribute', 'selector'])) {
      return TextStyle(
        color: dark ? const Color(0xFF9CDCFE) : const Color(0xFFE50000),
      );
    }
    if (_matchesAny(token, const ['meta'])) {
      return TextStyle(
        color: dark ? const Color(0xFF9CDCFE) : const Color(0xFF0B62A8),
      );
    }
    if (_matchesAny(token, const ['addition'])) {
      return TextStyle(
        color: dark ? const Color(0xFF81B88B) : const Color(0xFF1A7F37),
      );
    }
    if (_matchesAny(token, const ['deletion'])) {
      return TextStyle(
        color: dark ? const Color(0xFFFF7B72) : const Color(0xFFCF222E),
      );
    }
    return null;
  }

  bool _matchesAny(String token, List<String> fragments) {
    for (final fragment in fragments) {
      if (token.contains(fragment)) {
        return true;
      }
    }
    return false;
  }
}
