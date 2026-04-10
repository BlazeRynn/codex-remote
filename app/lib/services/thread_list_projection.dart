import '../models/codex_thread_summary.dart';

typedef ThreadArchivePredicate = bool Function(CodexThreadSummary thread);

class ThreadListProjection {
  const ThreadListProjection._({
    required this.archivedThreadCount,
    required this.scopedThreads,
    required this.visibleThreads,
    required this.selectedThreadId,
    required this.selectedThread,
    required this.workspaceCount,
    required this.primaryWorkspace,
    required this.currentProvider,
  });

  factory ThreadListProjection({
    required List<CodexThreadSummary> threads,
    required String? preferredSelectedThreadId,
    required bool showArchivedThreads,
    required bool showAllWorkspaces,
    required ThreadArchivePredicate isThreadArchived,
  }) {
    final archivedThreadCount = threads.where(isThreadArchived).length;
    final scopedThreads = threads
        .where((thread) => showArchivedThreads || !isThreadArchived(thread))
        .toList(growable: false);
    final primaryWorkspace = primaryWorkspaceForThreads(
      scopedThreads,
      selectedThreadId: preferredSelectedThreadId,
    );
    final visibleThreads = _visibleThreads(
      scopedThreads,
      selectedThreadId: preferredSelectedThreadId,
      showAllWorkspaces: showAllWorkspaces,
      primaryWorkspace: primaryWorkspace,
    );
    final selectedThreadId = resolveSelectedThreadId(
      visibleThreads,
      preferredId: preferredSelectedThreadId,
    );

    return ThreadListProjection._(
      archivedThreadCount: archivedThreadCount,
      scopedThreads: List.unmodifiable(scopedThreads),
      visibleThreads: List.unmodifiable(visibleThreads),
      selectedThreadId: selectedThreadId,
      selectedThread: selectedThreadForThreads(
        visibleThreads,
        selectedThreadId: selectedThreadId,
      ),
      workspaceCount: workspaceCountForThreads(scopedThreads),
      primaryWorkspace: primaryWorkspace,
      currentProvider: currentProviderForThreads(
        scopedThreads,
        selectedThreadId: preferredSelectedThreadId,
      ),
    );
  }

  final int archivedThreadCount;
  final List<CodexThreadSummary> scopedThreads;
  final List<CodexThreadSummary> visibleThreads;
  final String? selectedThreadId;
  final CodexThreadSummary? selectedThread;
  final int workspaceCount;
  final String? primaryWorkspace;
  final String? currentProvider;
}

class WorkspaceThreadGroup {
  const WorkspaceThreadGroup({required this.cwd, required this.threads});

  final String? cwd;
  final List<CodexThreadSummary> threads;
}

class WorkspaceQuickSelection {
  const WorkspaceQuickSelection({
    required this.cwd,
    required this.threadCount,
    required this.hasActiveThread,
    required this.latestActivityAt,
  });

  final String cwd;
  final int threadCount;
  final bool hasActiveThread;
  final DateTime? latestActivityAt;
}

String workspaceGroupKey(String? value) {
  return normalizeWorkspacePath(value) ?? '\u0000unknown-workspace';
}

List<CodexThreadSummary> sortThreadsForDisplay(
  List<CodexThreadSummary> threads,
) {
  final indexed = threads.indexed.toList(growable: false);
  indexed.sort((left, right) {
    final activityOrder = _activityRank(
      left.$2.status,
    ).compareTo(_activityRank(right.$2.status));
    if (activityOrder != 0) {
      return activityOrder;
    }

    final leftCreated = left.$2.createdAt?.millisecondsSinceEpoch ?? -1;
    final rightCreated = right.$2.createdAt?.millisecondsSinceEpoch ?? -1;
    if (leftCreated != rightCreated) {
      return rightCreated.compareTo(leftCreated);
    }

    return left.$1.compareTo(right.$1);
  });

  return indexed.map((entry) => entry.$2).toList(growable: false);
}

String? activeThreadIdOfThreads(List<CodexThreadSummary> threads) {
  for (final thread in threads) {
    if (thread.status == 'active') {
      return thread.id;
    }
  }
  return null;
}

int workspaceCountForThreads(List<CodexThreadSummary> threads) {
  final workspaces = <String>{};
  for (final thread in threads) {
    final normalized = normalizeWorkspacePath(thread.cwd);
    if (normalized != null) {
      workspaces.add(normalized);
    }
  }
  return workspaces.length;
}

String? primaryWorkspaceForThreads(
  List<CodexThreadSummary> threads, {
  String? selectedThreadId,
}) {
  if (selectedThreadId != null) {
    for (final thread in threads) {
      if (thread.id == selectedThreadId) {
        final normalized = normalizeWorkspacePath(thread.cwd);
        if (normalized != null) {
          return normalized;
        }
      }
    }
  }

  for (final thread in threads) {
    final normalized = normalizeWorkspacePath(thread.cwd);
    if (normalized != null) {
      return normalized;
    }
  }
  return null;
}

String? resolveSelectedThreadId(
  List<CodexThreadSummary> threads, {
  String? preferredId,
}) {
  if (threads.isEmpty) {
    return null;
  }

  if (preferredId == null) {
    return null;
  }

  if (threads.any((thread) => thread.id == preferredId)) {
    return preferredId;
  }

  return threads.first.id;
}

CodexThreadSummary? selectedThreadForThreads(
  List<CodexThreadSummary> threads, {
  String? selectedThreadId,
}) {
  if (threads.isEmpty) {
    return null;
  }

  final selectedId = selectedThreadId;
  if (selectedId == null) {
    return null;
  }
  for (final thread in threads) {
    if (thread.id == selectedId) {
      return thread;
    }
  }
  return threads.first;
}

String? currentProviderForThreads(
  List<CodexThreadSummary> threads, {
  String? selectedThreadId,
}) {
  final selectedThread = selectedThreadForThreads(
    threads,
    selectedThreadId: selectedThreadId,
  );
  if (selectedThread?.provider case final provider?
      when provider.trim().isNotEmpty) {
    return provider;
  }

  for (final thread in threads) {
    final provider = thread.provider?.trim();
    if (provider != null && provider.isNotEmpty) {
      return provider;
    }
  }

  return null;
}

List<WorkspaceThreadGroup> workspaceThreadGroups(
  List<CodexThreadSummary> threads,
) {
  final grouped = <String?, List<CodexThreadSummary>>{};
  for (final thread in threads) {
    final key = normalizeWorkspacePath(thread.cwd);
    grouped.putIfAbsent(key, () => <CodexThreadSummary>[]).add(thread);
  }

  final groups = grouped.entries
      .map(
        (entry) => WorkspaceThreadGroup(
          cwd: entry.key,
          threads: List.unmodifiable(entry.value),
        ),
      )
      .toList(growable: false);
  groups.sort((left, right) {
    final leftHasActive = left.threads.any(
      (thread) => thread.status == 'active',
    );
    final rightHasActive = right.threads.any(
      (thread) => thread.status == 'active',
    );
    if (leftHasActive != rightHasActive) {
      return leftHasActive ? -1 : 1;
    }

    final labelComparison = _workspaceSortLabel(
      left.cwd,
    ).compareTo(_workspaceSortLabel(right.cwd));
    if (labelComparison != 0) {
      return labelComparison;
    }

    return _workspaceSortPath(
      left.cwd,
    ).compareTo(_workspaceSortPath(right.cwd));
  });
  return List.unmodifiable(groups);
}

List<WorkspaceQuickSelection> workspaceQuickSelections(
  List<CodexThreadSummary> threads,
) {
  final grouped = <String, WorkspaceQuickSelection>{};
  for (final thread in threads) {
    final cwd = normalizeWorkspacePath(thread.cwd);
    if (cwd == null) {
      continue;
    }

    final latestActivityAt = _laterTimestamp(
      thread.updatedAt,
      thread.createdAt,
    );
    final current = grouped[cwd];
    if (current == null) {
      grouped[cwd] = WorkspaceQuickSelection(
        cwd: cwd,
        threadCount: 1,
        hasActiveThread: thread.status == 'active',
        latestActivityAt: latestActivityAt,
      );
      continue;
    }

    grouped[cwd] = WorkspaceQuickSelection(
      cwd: cwd,
      threadCount: current.threadCount + 1,
      hasActiveThread: current.hasActiveThread || thread.status == 'active',
      latestActivityAt: _laterTimestamp(
        current.latestActivityAt,
        latestActivityAt,
      ),
    );
  }

  final selections = grouped.values.toList(growable: false);
  selections.sort((left, right) {
    if (left.hasActiveThread != right.hasActiveThread) {
      return left.hasActiveThread ? -1 : 1;
    }

    final leftActivity = left.latestActivityAt?.millisecondsSinceEpoch ?? -1;
    final rightActivity = right.latestActivityAt?.millisecondsSinceEpoch ?? -1;
    if (leftActivity != rightActivity) {
      return rightActivity.compareTo(leftActivity);
    }

    final labelComparison = _workspaceSortLabel(
      left.cwd,
    ).compareTo(_workspaceSortLabel(right.cwd));
    if (labelComparison != 0) {
      return labelComparison;
    }

    return _workspaceSortPath(
      left.cwd,
    ).compareTo(_workspaceSortPath(right.cwd));
  });
  return List.unmodifiable(selections);
}

bool threadSummaryListsEquivalent(
  List<CodexThreadSummary> left,
  List<CodexThreadSummary> right,
) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (!sameThreadSummary(left[index], right[index])) {
      return false;
    }
  }
  return true;
}

bool sameThreadSummary(CodexThreadSummary left, CodexThreadSummary right) {
  return left.id == right.id &&
      left.title == right.title &&
      left.status == right.status &&
      left.preview == right.preview &&
      _sameTimestamp(left.createdAt, right.createdAt) &&
      left.cwd == right.cwd &&
      left.itemCount == right.itemCount &&
      left.provider == right.provider &&
      _sameTimestamp(left.updatedAt, right.updatedAt);
}

String? normalizeWorkspacePath(String? value) {
  if (value == null) {
    return null;
  }

  final normalized = value.trim().replaceFirst('\\\\?\\', '');
  return normalized.isEmpty ? null : normalized;
}

List<CodexThreadSummary> _visibleThreads(
  List<CodexThreadSummary> threads, {
  required String? selectedThreadId,
  required bool showAllWorkspaces,
  required String? primaryWorkspace,
}) {
  if (showAllWorkspaces || primaryWorkspace == null) {
    return _ensureSelectedThreadVisible(
      threads,
      allThreads: threads,
      selectedThreadId: selectedThreadId,
    );
  }

  final workspaceThreads = threads
      .where((thread) => normalizeWorkspacePath(thread.cwd) == primaryWorkspace)
      .toList(growable: false);
  if (workspaceThreads.isEmpty) {
    return _ensureSelectedThreadVisible(
      threads,
      allThreads: threads,
      selectedThreadId: selectedThreadId,
    );
  }

  return _ensureSelectedThreadVisible(
    workspaceThreads,
    allThreads: threads,
    selectedThreadId: selectedThreadId,
  );
}

List<CodexThreadSummary> _ensureSelectedThreadVisible(
  List<CodexThreadSummary> visibleThreads, {
  required List<CodexThreadSummary> allThreads,
  required String? selectedThreadId,
}) {
  final selectedId = selectedThreadId;
  if (selectedId == null ||
      visibleThreads.any((thread) => thread.id == selectedId)) {
    return visibleThreads;
  }

  CodexThreadSummary? selectedThread;
  for (final thread in allThreads) {
    if (thread.id == selectedId) {
      selectedThread = thread;
      break;
    }
  }
  if (selectedThread == null) {
    return visibleThreads;
  }

  final merged = <String, CodexThreadSummary>{
    for (final thread in visibleThreads) thread.id: thread,
    selectedThread.id: selectedThread,
  };
  return sortThreadsForDisplay(merged.values.toList(growable: false));
}

int _activityRank(String status) {
  return switch (status) {
    'active' => 0,
    _ => 1,
  };
}

String _workspaceSortLabel(String? value) {
  final normalized = normalizeWorkspacePath(value);
  if (normalized == null) {
    return '\uffff';
  }

  final segments = normalized
      .split(RegExp(r'[\\/]'))
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  final label = segments.isNotEmpty ? segments.last : normalized;
  return label.toLowerCase();
}

String _workspaceSortPath(String? value) {
  return normalizeWorkspacePath(value)?.toLowerCase() ?? '\uffff';
}

bool _sameTimestamp(DateTime? left, DateTime? right) {
  if (left == null && right == null) {
    return true;
  }
  if (left == null || right == null) {
    return false;
  }
  return left.isAtSameMomentAs(right);
}

DateTime? _laterTimestamp(DateTime? left, DateTime? right) {
  if (left == null) {
    return right;
  }
  if (right == null) {
    return left;
  }
  return left.isAfter(right) ? left : right;
}
