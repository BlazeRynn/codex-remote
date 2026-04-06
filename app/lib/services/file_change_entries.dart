import '../models/codex_thread_item.dart';
import '../utils/json_utils.dart';

class CodexFileChangeEntry {
  const CodexFileChangeEntry({
    required this.path,
    required this.kind,
    this.previousPath,
    this.diff,
  });

  final String path;
  final String kind;
  final String? previousPath;
  final String? diff;

  bool get hasDetails =>
      (previousPath?.trim().isNotEmpty ?? false) ||
      (diff?.trim().isNotEmpty ?? false);
}

List<CodexFileChangeEntry> parseCodexFileChangeEntries(CodexThreadItem item) {
  final changes = asJsonList(item.raw['changes']).map(asJsonMap);
  return changes
      .map((change) {
        final path = readString(change, const [
          'path',
          'newPath',
          'targetPath',
          'filePath',
        ]).trim();
        if (path.isEmpty) {
          return null;
        }

        final previousPath = readString(change, const [
          'oldPath',
          'fromPath',
          'sourcePath',
        ]).trim();
        return CodexFileChangeEntry(
          path: path,
          kind: readString(change, const ['kind', 'type'], fallback: 'updated'),
          previousPath: previousPath.isEmpty ? null : previousPath,
          diff: _readFileChangeDiff(change),
        );
      })
      .whereType<CodexFileChangeEntry>()
      .toList(growable: false);
}

String? _readFileChangeDiff(Map<String, dynamic> change) {
  final direct = _nonEmptyString(
    change['diff'] ??
        change['patch'] ??
        change['unifiedDiff'] ??
        change['patchText'] ??
        change['diffText'],
  );
  if (direct != null) {
    return direct;
  }

  final hunks = asJsonList(
    change['hunks'] ?? change['chunks'] ?? change['edits'],
  ).map(asJsonMap).toList(growable: false);
  if (hunks.isEmpty) {
    return null;
  }

  final rendered = hunks
      .map(_renderHunk)
      .where((chunk) => chunk.isNotEmpty)
      .join('\n');
  return rendered.trim().isEmpty ? null : rendered.trimRight();
}

String _renderHunk(Map<String, dynamic> hunk) {
  final header =
      _nonEmptyString(hunk['header']) ??
      _buildHunkHeader(hunk) ??
      _nonEmptyString(hunk['title']);
  final direct = _nonEmptyString(
    hunk['diff'] ?? hunk['patch'] ?? hunk['text'] ?? hunk['body'],
  );
  final lines = asJsonList(
    hunk['lines'] ?? hunk['content'] ?? hunk['entries'],
  ).map(_renderHunkLine).where((line) => line.isNotEmpty).join('\n');

  final parts = <String>[
    if (header != null && header.isNotEmpty) header,
    if (direct != null && direct.isNotEmpty) direct,
    if (lines.isNotEmpty) lines,
  ];
  return parts.join('\n').trim();
}

String? _buildHunkHeader(Map<String, dynamic> hunk) {
  final oldStart = readInt(hunk, const ['oldStart', 'fromStart']);
  final newStart = readInt(hunk, const ['newStart', 'toStart']);
  if (oldStart == null || newStart == null) {
    return null;
  }
  final oldLines = readInt(hunk, const ['oldLines', 'fromLines']) ?? 1;
  final newLines = readInt(hunk, const ['newLines', 'toLines']) ?? 1;
  final section = readString(hunk, const ['section', 'context']);
  final suffix = section.isEmpty ? '' : ' $section';
  return '@@ -$oldStart,$oldLines +$newStart,$newLines @@$suffix';
}

String _renderHunkLine(Object? value) {
  if (value is String) {
    return value.trimRight();
  }

  final line = asJsonMap(value);
  final direct = _nonEmptyString(
    line['text'] ?? line['content'] ?? line['value'],
  );
  if (direct != null) {
    return direct.trimRight();
  }

  final prefix = _nonEmptyString(line['prefix']) ?? '';
  final body = _nonEmptyString(line['line']) ?? _nonEmptyString(line['body']);
  if (body == null) {
    return '';
  }
  return '$prefix$body'.trimRight();
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trimRight() ?? '';
  return text.trim().isEmpty ? null : text;
}
