import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' as highlight;

import '../app/app_strings.dart';
import '../app/app_typography.dart';
import '../app/workspace_theme.dart';
import '../services/file_change_entries.dart';

class FileChangeCardList extends StatelessWidget {
  const FileChangeCardList({
    super.key,
    required this.entries,
    this.workspaceStyle = false,
  });

  final List<CodexFileChangeEntry> entries;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < entries.length; index += 1) ...[
          FileChangeCard(entry: entries[index], workspaceStyle: workspaceStyle),
          if (index < entries.length - 1)
            SizedBox(height: workspaceStyle ? 6 : 8),
        ],
      ],
    );
  }
}

class FileChangeCard extends StatefulWidget {
  const FileChangeCard({
    super.key,
    required this.entry,
    this.workspaceStyle = false,
  });

  final CodexFileChangeEntry entry;
  final bool workspaceStyle;

  @override
  State<FileChangeCard> createState() => _FileChangeCardState();
}

class _FileChangeCardState extends State<FileChangeCard> {
  bool _expanded = false;

  bool get _canExpand => widget.entry.hasDetails;

  void _toggleExpanded() {
    if (!_canExpand) {
      return;
    }
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = normalizeFileChangeKind(widget.entry.kind);
    final accentColor = fileChangeAccentColor(theme, kind);
    final badgeBackground = accentColor.withValues(alpha: 0.12);
    final pathStyle = appCodeTextStyle(theme.textTheme.bodyMedium).copyWith(
      fontSize: widget.workspaceStyle ? 12.5 : 13,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );

    return DecoratedBox(
      key: ValueKey(
        'file-change-card:${widget.entry.path}:${widget.entry.kind}',
      ),
      decoration: BoxDecoration(
        color: panelBackgroundColor(theme),
        borderRadius: BorderRadius.circular(widget.workspaceStyle ? 14 : 16),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.workspaceStyle ? 14 : 16),
          onTap: _canExpand ? _toggleExpanded : null,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.workspaceStyle ? 11 : 12,
              widget.workspaceStyle ? 8 : 9,
              widget.workspaceStyle ? 11 : 12,
              widget.workspaceStyle ? 8 : 9,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: widget.workspaceStyle ? 24 : 26,
                      height: widget.workspaceStyle ? 24 : 26,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        fileChangeIcon(kind),
                        size: widget.workspaceStyle ? 14 : 16,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.entry.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: pathStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: badgeBackground,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.workspaceStyle ? 7 : 8,
                          vertical: widget.workspaceStyle ? 3 : 4,
                        ),
                        child: Text(
                          fileChangeKindLabel(context, kind),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (_canExpand) ...[
                      const SizedBox(width: 4),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: secondaryTextColor(theme),
                        size: widget.workspaceStyle ? 16 : 18,
                      ),
                    ],
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 10),
                  Container(height: 1, color: borderColor(theme)),
                  const SizedBox(height: 10),
                  if (widget.entry.previousPath != null) ...[
                    Text(
                      '${_localizedText(context, 'from', '从')} ${widget.entry.previousPath!}',
                      style: appCodeTextStyle(theme.textTheme.bodySmall)
                          .copyWith(
                            fontSize: widget.workspaceStyle ? 11.5 : 12,
                            color: secondaryTextColor(theme),
                          ),
                    ),
                    if (widget.entry.diff != null &&
                        widget.entry.diff!.trim().isNotEmpty)
                      const SizedBox(height: 10),
                  ],
                  if (widget.entry.diff != null &&
                      widget.entry.diff!.trim().isNotEmpty)
                    _DiffSurface(
                      diff: widget.entry.diff!,
                      path: widget.entry.path,
                      workspaceStyle: widget.workspaceStyle,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiffSurface extends StatelessWidget {
  const _DiffSurface({
    required this.diff,
    required this.workspaceStyle,
    this.path,
  });

  final String diff;
  final bool workspaceStyle;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.brightness == Brightness.dark
        ? const Color(0xFF0E1116)
        : const Color(0xFFF8FAFD);
    final headerBackground = theme.brightness == Brightness.dark
        ? const Color(0xFF121720)
        : const Color(0xFFF2F5FA);
    final lines = _parseUnifiedDiff(diff);
    final language = _languageFromPath(path);
    final syntaxHighlighter = _DiffSyntaxHighlighter(theme);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(workspaceStyle ? 12 : 14),
        border: Border.all(color: borderColor(theme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language != null)
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
                  language,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondaryTextColor(theme),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: workspaceStyle ? 420 : 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < lines.length; index += 1)
                    _DiffLineRow(
                      key: ValueKey(
                        'diff-line:${lines[index].kind.name}:$index',
                      ),
                      line: lines[index],
                      workspaceStyle: workspaceStyle,
                      syntaxHighlighter: syntaxHighlighter,
                      language: language,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ParsedDiffLineKind { fileHeader, hunk, addition, deletion, context, meta }

class _ParsedDiffLine {
  const _ParsedDiffLine({
    required this.kind,
    required this.raw,
    required this.content,
    required this.prefix,
    this.oldLineNumber,
    this.newLineNumber,
  });

  final _ParsedDiffLineKind kind;
  final String raw;
  final String content;
  final String prefix;
  final int? oldLineNumber;
  final int? newLineNumber;
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow({
    super.key,
    required this.line,
    required this.workspaceStyle,
    required this.syntaxHighlighter,
    required this.language,
  });

  final _ParsedDiffLine line;
  final bool workspaceStyle;
  final _DiffSyntaxHighlighter syntaxHighlighter;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _diffLineStyle(theme, line.kind);
    final content = switch (line.kind) {
      _ParsedDiffLineKind.addition ||
      _ParsedDiffLineKind.deletion ||
      _ParsedDiffLineKind.context => SelectableText.rich(
        syntaxHighlighter.format(
          line.content,
          language: language,
          defaultColor: style.contentColor,
          workspaceStyle: workspaceStyle,
        ),
        style: _diffCodeStyle(
          theme,
          workspaceStyle,
        ).copyWith(color: style.contentColor),
      ),
      _ => SelectableText(
        line.raw,
        style: _diffCodeStyle(
          theme,
          workspaceStyle,
        ).copyWith(color: style.contentColor),
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(color: style.backgroundColor),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: workspaceStyle ? 10 : 12,
          vertical: workspaceStyle ? 3 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DiffLineNumber(
              value: line.oldLineNumber,
              color: style.lineNumberColor,
              workspaceStyle: workspaceStyle,
            ),
            const SizedBox(width: 8),
            _DiffLineNumber(
              value: line.newLineNumber,
              color: style.lineNumberColor,
              workspaceStyle: workspaceStyle,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: workspaceStyle ? 12 : 14,
              child: Text(
                line.prefix,
                style: _diffCodeStyle(theme, workspaceStyle).copyWith(
                  color: style.prefixColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(fit: FlexFit.loose, child: content),
          ],
        ),
      ),
    );
  }
}

class _DiffLineNumber extends StatelessWidget {
  const _DiffLineNumber({
    required this.value,
    required this.color,
    required this.workspaceStyle,
  });

  final int? value;
  final Color color;
  final bool workspaceStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: workspaceStyle ? 32 : 36,
      child: Text(
        value?.toString() ?? '',
        textAlign: TextAlign.right,
        style: _diffCodeStyle(
          Theme.of(context),
          workspaceStyle,
        ).copyWith(color: color, fontSize: workspaceStyle ? 11.5 : 12),
      ),
    );
  }
}

class _DiffLineStyle {
  const _DiffLineStyle({
    required this.backgroundColor,
    required this.contentColor,
    required this.prefixColor,
    required this.lineNumberColor,
  });

  final Color backgroundColor;
  final Color contentColor;
  final Color prefixColor;
  final Color lineNumberColor;
}

_DiffLineStyle _diffLineStyle(ThemeData theme, _ParsedDiffLineKind kind) {
  final dark = theme.brightness == Brightness.dark;
  switch (kind) {
    case _ParsedDiffLineKind.addition:
      return _DiffLineStyle(
        backgroundColor: dark
            ? const Color(0x33238836)
            : const Color(0x1F1A7F37),
        contentColor: dark ? const Color(0xFFD4D4D4) : const Color(0xFF1F2328),
        prefixColor: dark ? const Color(0xFF81B88B) : const Color(0xFF1A7F37),
        lineNumberColor: dark
            ? const Color(0xFF81B88B)
            : const Color(0xFF1A7F37),
      );
    case _ParsedDiffLineKind.deletion:
      return _DiffLineStyle(
        backgroundColor: dark
            ? const Color(0x33CF222E)
            : const Color(0x1FCF222E),
        contentColor: dark ? const Color(0xFFD4D4D4) : const Color(0xFF1F2328),
        prefixColor: dark ? const Color(0xFFFF7B72) : const Color(0xFFCF222E),
        lineNumberColor: dark
            ? const Color(0xFFFF7B72)
            : const Color(0xFFCF222E),
      );
    case _ParsedDiffLineKind.hunk:
      return _DiffLineStyle(
        backgroundColor: dark
            ? const Color(0x262F81F7)
            : const Color(0x140D5CAB),
        contentColor: dark ? const Color(0xFF9CDCFE) : const Color(0xFF0B62A8),
        prefixColor: dark ? const Color(0xFF9CDCFE) : const Color(0xFF0B62A8),
        lineNumberColor: secondaryTextColor(theme),
      );
    case _ParsedDiffLineKind.fileHeader:
      return _DiffLineStyle(
        backgroundColor: dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        contentColor: secondaryTextColor(theme),
        prefixColor: secondaryTextColor(theme),
        lineNumberColor: secondaryTextColor(theme),
      );
    case _ParsedDiffLineKind.meta:
      return _DiffLineStyle(
        backgroundColor: dark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.02),
        contentColor: secondaryTextColor(theme),
        prefixColor: secondaryTextColor(theme),
        lineNumberColor: secondaryTextColor(theme),
      );
    case _ParsedDiffLineKind.context:
      return _DiffLineStyle(
        backgroundColor: Colors.transparent,
        contentColor: dark ? const Color(0xFFD4D4D4) : const Color(0xFF1F2328),
        prefixColor: secondaryTextColor(theme),
        lineNumberColor: secondaryTextColor(theme),
      );
  }
}

TextStyle _diffCodeStyle(ThemeData theme, bool workspaceStyle) {
  return appCodeTextStyle(theme.textTheme.bodyMedium).copyWith(
    fontSize: workspaceStyle ? 12.5 : 13,
    color: theme.brightness == Brightness.dark
        ? const Color(0xFFD4D4D4)
        : const Color(0xFF1F2328),
  );
}

List<_ParsedDiffLine> _parseUnifiedDiff(String diff) {
  final lines = diff.trimRight().split(RegExp(r'\r?\n'));
  final result = <_ParsedDiffLine>[];
  var oldLine = 0;
  var newLine = 0;

  for (final rawLine in lines) {
    if (rawLine.startsWith('@@')) {
      final match = RegExp(
        r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@',
      ).firstMatch(rawLine);
      oldLine = int.tryParse(match?.group(1) ?? '') ?? 0;
      newLine = int.tryParse(match?.group(2) ?? '') ?? 0;
      result.add(
        _ParsedDiffLine(
          kind: _ParsedDiffLineKind.hunk,
          raw: rawLine,
          content: rawLine,
          prefix: '@',
        ),
      );
      continue;
    }

    if (rawLine.startsWith('--- ') || rawLine.startsWith('+++ ')) {
      result.add(
        _ParsedDiffLine(
          kind: _ParsedDiffLineKind.fileHeader,
          raw: rawLine,
          content: rawLine,
          prefix: rawLine.substring(0, 1),
        ),
      );
      continue;
    }

    if (rawLine.startsWith('+') && !rawLine.startsWith('+++')) {
      result.add(
        _ParsedDiffLine(
          kind: _ParsedDiffLineKind.addition,
          raw: rawLine,
          content: rawLine.substring(1),
          prefix: '+',
          newLineNumber: newLine == 0 ? null : newLine++,
        ),
      );
      continue;
    }

    if (rawLine.startsWith('-') && !rawLine.startsWith('---')) {
      result.add(
        _ParsedDiffLine(
          kind: _ParsedDiffLineKind.deletion,
          raw: rawLine,
          content: rawLine.substring(1),
          prefix: '-',
          oldLineNumber: oldLine == 0 ? null : oldLine++,
        ),
      );
      continue;
    }

    if (rawLine.startsWith(' ')) {
      result.add(
        _ParsedDiffLine(
          kind: _ParsedDiffLineKind.context,
          raw: rawLine,
          content: rawLine.substring(1),
          prefix: ' ',
          oldLineNumber: oldLine == 0 ? null : oldLine++,
          newLineNumber: newLine == 0 ? null : newLine++,
        ),
      );
      continue;
    }

    result.add(
      _ParsedDiffLine(
        kind: _ParsedDiffLineKind.meta,
        raw: rawLine,
        content: rawLine,
        prefix: '',
      ),
    );
  }

  return result;
}

String? _languageFromPath(String? path) {
  final value = path?.trim().toLowerCase() ?? '';
  if (value.isEmpty || !value.contains('.')) {
    return null;
  }
  final extension = value.split('.').last;
  return switch (extension) {
    'dart' => 'dart',
    'js' || 'jsx' => 'javascript',
    'ts' || 'tsx' => 'typescript',
    'json' => 'json',
    'yml' || 'yaml' => 'yaml',
    'py' => 'python',
    'sh' => 'bash',
    'ps1' => 'powershell',
    'md' => 'markdown',
    'swift' => 'swift',
    'kt' || 'kts' => 'kotlin',
    'java' => 'java',
    'go' => 'go',
    'rs' => 'rust',
    'c' || 'h' => 'c',
    'cc' || 'cpp' || 'cxx' || 'hpp' => 'cpp',
    'cs' => 'csharp',
    'html' || 'xml' => 'xml',
    'css' => 'css',
    'scss' => 'scss',
    'sql' => 'sql',
    _ => null,
  };
}

class _DiffSyntaxHighlighter {
  _DiffSyntaxHighlighter(this.theme);

  final ThemeData theme;

  TextSpan format(
    String source, {
    String? language,
    Color? defaultColor,
    required bool workspaceStyle,
  }) {
    final baseStyle = _diffCodeStyle(
      theme,
      workspaceStyle,
    ).copyWith(color: defaultColor);
    if (source.trim().isEmpty || language == null || language.trim().isEmpty) {
      return TextSpan(text: source.isEmpty ? ' ' : source, style: baseStyle);
    }

    try {
      final result = highlight.highlight.parse(source, language: language);
      final spans = _nodesToSpans(
        result.nodes,
        baseStyle,
        defaultColor ?? baseStyle.color!,
      );
      if (spans.isEmpty) {
        return TextSpan(text: source, style: baseStyle);
      }
      return TextSpan(style: baseStyle, children: spans);
    } catch (_) {
      return TextSpan(text: source, style: baseStyle);
    }
  }

  List<InlineSpan> _nodesToSpans(
    List<highlight.Node>? nodes,
    TextStyle baseStyle,
    Color defaultColor,
  ) {
    if (nodes == null) {
      return const [];
    }
    return nodes
        .map((node) => _nodeToSpan(node, baseStyle, defaultColor))
        .toList(growable: false);
  }

  InlineSpan _nodeToSpan(
    highlight.Node node,
    TextStyle baseStyle,
    Color defaultColor,
  ) {
    final style = baseStyle.merge(_styleForToken(node.className, defaultColor));
    if (node.value != null) {
      return TextSpan(text: node.value, style: style);
    }
    return TextSpan(
      style: style,
      children: _nodesToSpans(node.children, baseStyle, defaultColor),
    );
  }

  TextStyle? _styleForToken(String? className, Color defaultColor) {
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
    return TextStyle(color: defaultColor);
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

String normalizeFileChangeKind(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.contains('delete') || normalized.contains('remove')) {
    return 'deleted';
  }
  if (normalized.contains('rename') || normalized.contains('move')) {
    return 'renamed';
  }
  if (normalized.contains('add') || normalized.contains('create')) {
    return 'added';
  }
  if (normalized.contains('modify') ||
      normalized.contains('update') ||
      normalized.contains('edit') ||
      normalized.contains('change')) {
    return 'modified';
  }
  return normalized.isEmpty ? 'modified' : normalized;
}

String fileChangeKindLabel(BuildContext context, String kind) {
  switch (kind) {
    case 'added':
      return _localizedText(context, 'Added', '新增');
    case 'deleted':
      return _localizedText(context, 'Deleted', '删除');
    case 'renamed':
      return _localizedText(context, 'Renamed', '重命名');
    case 'modified':
      return _localizedText(context, 'Modified', '修改');
    default:
      return _humanizeMachineLabel(context, kind);
  }
}

IconData fileChangeIcon(String kind) {
  switch (kind) {
    case 'added':
      return Icons.add;
    case 'deleted':
      return Icons.remove;
    case 'renamed':
      return Icons.drive_file_rename_outline;
    case 'modified':
      return Icons.edit_outlined;
    default:
      return Icons.description_outlined;
  }
}

Color fileChangeAccentColor(ThemeData theme, String kind) {
  switch (kind) {
    case 'added':
      return Colors.green.shade600;
    case 'deleted':
      return theme.colorScheme.error;
    case 'renamed':
      return Colors.orange.shade700;
    case 'modified':
      return theme.colorScheme.primary;
    default:
      return secondaryTextColor(theme);
  }
}

String _humanizeMachineLabel(BuildContext context, String value) {
  final normalized = value.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (normalized.isEmpty) {
    return _localizedText(context, 'Changed', '改动');
  }

  final words = normalized
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
  return words;
}

String _localizedText(BuildContext context, String english, String chinese) {
  final strings = Localizations.of<AppStrings>(context, AppStrings);
  if (strings == null) {
    return english;
  }
  return strings.text(english, chinese);
}
