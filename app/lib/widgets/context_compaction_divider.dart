import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_strings.dart';
import '../app/workspace_theme.dart';
import '../models/codex_thread_item.dart';
import '../services/thread_item_timestamps.dart';

class ContextCompactionDivider extends StatefulWidget {
  const ContextCompactionDivider({
    super.key,
    required this.item,
    this.workspaceStyle = false,
  });

  final CodexThreadItem item;
  final bool workspaceStyle;

  @override
  State<ContextCompactionDivider> createState() =>
      _ContextCompactionDividerState();
}

class _ContextCompactionDividerState extends State<ContextCompactionDivider> {
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ContextCompactionDivider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.status != widget.item.status ||
        oldWidget.item.body != widget.item.body ||
        oldWidget.item.id != widget.item.id ||
        _displayStartedAt(oldWidget.item) != _displayStartedAt(widget.item)) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    _timer?.cancel();
    _timer = null;
    _elapsedSeconds = _computeElapsedSeconds();
    if (!isContextCompactionComplete(widget.item)) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _elapsedSeconds += 1;
        });
      });
    }
  }

  int _computeElapsedSeconds() {
    final startedAt = _displayStartedAt(widget.item);
    if (startedAt == null) {
      return 0;
    }
    final elapsed = DateTime.now().toUtc().difference(startedAt.toUtc());
    return elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  }

  DateTime? _displayStartedAt(CodexThreadItem item) {
    return resolveThreadItemDisplayTimestamp(item)?.toUtc();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final useStableWindowsSemantics = Platform.isWindows;
    final completed = isContextCompactionComplete(widget.item);
    final accentColor = completed
        ? secondaryTextColor(theme)
        : theme.colorScheme.primary;
    final dividerColor = completed
        ? borderColor(theme)
        : theme.colorScheme.primary.withValues(alpha: 0.35);
    final elapsed = Duration(seconds: _elapsedSeconds);
    final label = completed
        ? _localizedText(context, 'Context compressed', '上下文压缩完成')
        : _localizedText(
            context,
            'Compressing context ${_formatElapsedDuration(elapsed)}',
            '正在压缩上下文 ${_formatElapsedDuration(elapsed)}',
          );
    final semanticsLabel = completed
        ? _localizedText(context, 'Context compressed', '上下文压缩完成')
        : _localizedText(context, 'Compressing context', '正在压缩上下文');
    final indicator = completed
        ? ExcludeSemantics(
            child: Icon(
              Icons.check_circle_outline,
              size: widget.workspaceStyle ? 15 : 16,
              color: accentColor,
            ),
          )
        : ExcludeSemantics(
            child: SizedBox.square(
              dimension: widget.workspaceStyle ? 14 : 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
          );
    final statusRow = Row(
      key: ValueKey(
        'context-compaction:${widget.item.id}:${completed ? 'done' : 'active'}',
      ),
      mainAxisSize: MainAxisSize.min,
      children: [
        indicator,
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
    final semanticsStableContent = Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(child: statusRow),
    );
    final statusContent = useStableWindowsSemantics
        ? semanticsStableContent
        : statusRow;

    return Padding(
      padding: EdgeInsets.only(bottom: widget.workspaceStyle ? 8 : 14),
      child: Row(
        children: [
          Expanded(child: _DividerSegment(color: dividerColor)),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.workspaceStyle ? 12 : 14,
            ),
            child: statusContent,
          ),
          Expanded(child: _DividerSegment(color: dividerColor)),
        ],
      ),
    );
  }
}

class _DividerSegment extends StatelessWidget {
  const _DividerSegment({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: color);
  }
}

bool isContextCompactionItem(CodexThreadItem item) {
  final type = item.type.trim();
  if (type == 'context.compaction' || type == 'contextCompaction') {
    return true;
  }
  return item.raw['type']?.toString().trim() == 'contextCompaction';
}

bool isContextCompactionComplete(CodexThreadItem item) {
  final status = item.status.trim().toLowerCase();
  if (status == 'completed' ||
      status == 'complete' ||
      status == 'done' ||
      status == 'succeeded' ||
      status == 'success') {
    return true;
  }
  if (_isInProgressStatus(status)) {
    return false;
  }
  return item.body.trim().isNotEmpty;
}

bool _isInProgressStatus(String status) {
  return status == 'started' ||
      status == 'starting' ||
      status == 'in_progress' ||
      status == 'streaming' ||
      status == 'running' ||
      status == 'pending';
}

String _localizedText(BuildContext context, String english, String chinese) {
  final strings = Localizations.of<AppStrings>(context, AppStrings);
  if (strings == null) {
    return english;
  }
  return strings.text(english, chinese);
}

String _formatElapsedDuration(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
