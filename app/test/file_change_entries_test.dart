import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/codex_thread_item.dart';
import 'package:mobile/services/file_change_entries.dart';

void main() {
  test('parseCodexFileChangeEntries reads changed files from raw payload', () {
    final item = CodexThreadItem(
      id: 'file-change-1',
      type: 'file.change',
      title: '2 file changes',
      body: '',
      status: 'completed',
      actor: 'assistant',
      raw: const {
        'changes': [
          {'kind': 'modified', 'path': 'app/lib/main.dart'},
          {
            'kind': 'renamed',
            'path': 'app/lib/app/app.dart',
            'oldPath': 'app/lib/app/legacy_app.dart',
            'diff': '@@ -1 +1 @@\n-old\n+new',
          },
        ],
      },
    );

    final entries = parseCodexFileChangeEntries(item);

    expect(entries, hasLength(2));
    expect(entries[0].kind, 'modified');
    expect(entries[0].path, 'app/lib/main.dart');
    expect(entries[1].kind, 'renamed');
    expect(entries[1].path, 'app/lib/app/app.dart');
    expect(entries[1].previousPath, 'app/lib/app/legacy_app.dart');
    expect(entries[1].diff, '@@ -1 +1 @@\n-old\n+new');
  });

  test('parseCodexFileChangeEntries skips empty file paths', () {
    final item = CodexThreadItem(
      id: 'file-change-2',
      type: 'file.change',
      title: '1 file change',
      body: '',
      status: 'completed',
      actor: 'assistant',
      raw: const {
        'changes': [
          {'kind': 'modified'},
          {'kind': 'added', 'path': 'README.md'},
        ],
      },
    );

    final entries = parseCodexFileChangeEntries(item);

    expect(entries, hasLength(1));
    expect(entries.single.path, 'README.md');
  });

  test('parseCodexFileChangeEntries renders diff hunks when provided', () {
    final item = CodexThreadItem(
      id: 'file-change-3',
      type: 'file.change',
      title: '1 file change',
      body: '',
      status: 'completed',
      actor: 'assistant',
      raw: const {
        'changes': [
          {
            'kind': 'modified',
            'path': 'README.md',
            'hunks': [
              {
                'oldStart': 1,
                'oldLines': 1,
                'newStart': 1,
                'newLines': 2,
                'lines': ['-old', '+new', '+next'],
              },
            ],
          },
        ],
      },
    );

    final entries = parseCodexFileChangeEntries(item);

    expect(entries.single.diff, '@@ -1,1 +1,2 @@\n-old\n+new\n+next');
  });
}
