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

  test('does not treat loaded idle threads as active', () {
    final sorted = sortThreadsForDisplay([
      _thread(
        id: 'idle',
        status: 'idle',
        createdAt: DateTime.utc(2026, 4, 6),
      ),
      _thread(
        id: 'loaded',
        isLoaded: true,
        createdAt: DateTime.utc(2026, 4, 5),
      ),
    ]);

    expect(sorted.map((thread) => thread.id), ['idle', 'loaded']);
    expect(activeThreadIdOfThreads(sorted), isNull);
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

  test('does not auto-select the first thread without a preferred selection', () {
    final projection = ThreadListProjection(
      threads: sortThreadsForDisplay([
        _thread(
          id: 'active',
          status: 'active',
          createdAt: DateTime.utc(2026, 4, 6),
        ),
        _thread(id: 'idle', createdAt: DateTime.utc(2026, 4, 5)),
      ]),
      preferredSelectedThreadId: null,
      showArchivedThreads: false,
      showAllWorkspaces: true,
      isThreadArchived: (_) => false,
    );

    expect(projection.selectedThreadId, isNull);
    expect(projection.selectedThread, isNull);
  });

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

  test(
    'workspaceQuickSelections deduplicates normalized workspaces and sorts by relevance',
    () {
      final selections = workspaceQuickSelections([
        _thread(
          id: 'alpha-1',
          cwd: r'\\?\C:\alpha',
          createdAt: DateTime.utc(2026, 4, 1),
        ),
        _thread(
          id: 'gamma-1',
          cwd: r'C:\gamma',
          updatedAt: DateTime.utc(2026, 4, 4),
        ),
        _thread(
          id: 'beta-1',
          cwd: r'C:\beta',
          status: 'active',
          updatedAt: DateTime.utc(2026, 4, 2),
        ),
        _thread(
          id: 'alpha-2',
          cwd: r'C:\alpha',
          updatedAt: DateTime.utc(2026, 4, 3),
        ),
        _thread(id: 'unknown', cwd: null),
      ]);

      expect(selections.map((selection) => selection.cwd), [
        r'C:\beta',
        r'C:\gamma',
        r'C:\alpha',
      ]);
      expect(
        selections.map((selection) => selection.threadCount),
        orderedEquals([1, 1, 2]),
      );
      expect(
        selections.map((selection) => selection.hasActiveThread),
        orderedEquals([true, false, false]),
      );
      expect(selections.last.latestActivityAt, DateTime.utc(2026, 4, 3));
    },
  );
}

CodexThreadSummary _thread({
  required String id,
  String status = 'idle',
  bool isLoaded = false,
  DateTime? createdAt,
  DateTime? updatedAt,
  String? cwd,
}) {
  return CodexThreadSummary(
    id: id,
    title: 'Session $id',
    status: status,
    preview: 'Preview $id',
    isLoaded: isLoaded,
    createdAt: createdAt,
    updatedAt: updatedAt,
    cwd: cwd,
  );
}
