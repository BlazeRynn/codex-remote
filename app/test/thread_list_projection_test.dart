import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/codex_thread_summary.dart';
import 'package:mobile/services/thread_list_projection.dart';

void main() {
  test('sorts active threads ahead of idle threads', () {
    final sorted = sortThreadsForDisplay([
      _thread(
        id: 'idle-new',
        status: 'idle',
        createdAt: DateTime.utc(2026, 4, 6),
      ),
      _thread(
        id: 'active-old',
        status: 'active',
        createdAt: DateTime.utc(2026, 4, 4),
      ),
      _thread(
        id: 'active-new',
        status: 'active',
        createdAt: DateTime.utc(2026, 4, 5),
      ),
    ]);

    expect(sorted.map((thread) => thread.id), [
      'active-new',
      'active-old',
      'idle-new',
    ]);
  });

  test(
    'keeps the selected workspace in focus when workspace scope is narrowed',
    () {
      final projection = ThreadListProjection(
        threads: sortThreadsForDisplay([
          _thread(
            id: 'alpha-1',
            cwd: r'C:\alpha',
            createdAt: DateTime.utc(2026, 4, 4),
          ),
          _thread(
            id: 'beta-1',
            cwd: r'D:\beta',
            createdAt: DateTime.utc(2026, 4, 6),
          ),
          _thread(
            id: 'beta-2',
            cwd: r'D:\beta',
            createdAt: DateTime.utc(2026, 4, 5),
          ),
        ]),
        preferredSelectedThreadId: 'beta-2',
        showArchivedThreads: false,
        showAllWorkspaces: false,
        isThreadArchived: (_) => false,
      );

      expect(projection.primaryWorkspace, r'D:\beta');
      expect(projection.visibleThreads.map((thread) => thread.id), [
        'beta-1',
        'beta-2',
      ]);
      expect(projection.selectedThreadId, 'beta-2');
    },
  );

  test(
    're-resolves selection when archive scope hides the previous thread',
    () {
      final projection = ThreadListProjection(
        threads: sortThreadsForDisplay([
          _thread(
            id: 'active',
            status: 'active',
            createdAt: DateTime.utc(2026, 4, 6),
          ),
          _thread(id: 'archived', createdAt: DateTime.utc(2026, 4, 5)),
        ]),
        preferredSelectedThreadId: 'archived',
        showArchivedThreads: false,
        showAllWorkspaces: true,
        isThreadArchived: (thread) => thread.id == 'archived',
      );

      expect(projection.archivedThreadCount, 1);
      expect(projection.visibleThreads.map((thread) => thread.id), ['active']);
      expect(projection.selectedThreadId, 'active');
    },
  );

  test('showArchivedThreads includes both active and archived threads', () {
    final projection = ThreadListProjection(
      threads: sortThreadsForDisplay([
        _thread(
          id: 'active',
          status: 'active',
          createdAt: DateTime.utc(2026, 4, 6),
        ),
        _thread(id: 'archived', createdAt: DateTime.utc(2026, 4, 5)),
      ]),
      preferredSelectedThreadId: 'active',
      showArchivedThreads: true,
      showAllWorkspaces: true,
      isThreadArchived: (thread) => thread.id == 'archived',
    );

    expect(projection.archivedThreadCount, 1);
    expect(
      projection.visibleThreads.map((thread) => thread.id),
      orderedEquals(['active', 'archived']),
    );
    expect(projection.selectedThreadId, 'active');
  });

  test(
    'groups workspaces by normalized path and puts active workspaces first',
    () {
      final groups = workspaceThreadGroups([
        _thread(id: 'alpha', cwd: r'\\?\C:\alpha'),
        _thread(id: 'beta', cwd: r'C:\beta', status: 'active'),
        _thread(id: 'unknown', cwd: null),
      ]);

      expect(
        groups.map((group) => group.cwd),
        orderedEquals([r'C:\beta', r'C:\alpha', null]),
      );
    },
  );

  test('workspaceGroupKey is stable for normalized and unknown workspaces', () {
    expect(workspaceGroupKey(r'\\?\C:\alpha'), r'C:\alpha');
    expect(workspaceGroupKey(null), workspaceGroupKey(''));
  });
}

CodexThreadSummary _thread({
  required String id,
  String status = 'idle',
  DateTime? createdAt,
  String? cwd,
}) {
  return CodexThreadSummary(
    id: id,
    title: 'Session $id',
    status: status,
    preview: 'Preview $id',
    createdAt: createdAt,
    cwd: cwd,
  );
}
