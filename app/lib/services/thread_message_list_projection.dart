import '../models/codex_thread_item.dart';

enum ThreadMessageEntryKind {
  bubble,
  commandExecution,
  fileChange,
  contextCompaction,
}

class ThreadMessageListProjection {
  ThreadMessageListProjection._({
    required this.entries,
    required this.legacyItems,
    required this.tailSignature,
    required this.tailBodyLength,
  });

  final List<ThreadMessageListEntry> entries;
  final List<CodexThreadItem> legacyItems;
  final String tailSignature;
  final int tailBodyLength;

  CodexThreadItem? get tailItem =>
      legacyItems.isEmpty ? null : legacyItems.last;
}

class ThreadMessageListEntry {
  ThreadMessageListEntry.bubble({
    required this.key,
    required List<CodexThreadItem> items,
    List<CodexThreadItem>? sourceItems,
    required this.actor,
    required this.status,
  }) : kind = ThreadMessageEntryKind.bubble,
       items = List.unmodifiable(items),
       sourceItems = List.unmodifiable(sourceItems ?? items),
       item = null;

  ThreadMessageListEntry.item({
    required this.key,
    required this.kind,
    required CodexThreadItem this.item,
  }) : assert(kind != ThreadMessageEntryKind.bubble),
       items = const [],
       sourceItems = const [],
       actor = item.actor,
       status = item.status;

  final String key;
  final ThreadMessageEntryKind kind;
  final List<CodexThreadItem> items;
  final List<CodexThreadItem> sourceItems;
  final CodexThreadItem? item;
  final String actor;
  final String status;

  CodexThreadItem? get displayItem {
    if (item != null) {
      return item;
    }
    if (items.isEmpty) {
      return null;
    }
    return items.last;
  }
}

ThreadMessageListProjection projectThreadMessageList(
  List<CodexThreadItem> items,
) {
  final entries = List<ThreadMessageListEntry>.unmodifiable(
    _buildThreadMessageEntries(items),
  );
  final legacyItems = List<CodexThreadItem>.unmodifiable(
    entries.map<CodexThreadItem>(_legacyItemFromEntry).toList(growable: false),
  );
  final tailItem = legacyItems.isEmpty ? null : legacyItems.last;

  return ThreadMessageListProjection._(
    entries: entries,
    legacyItems: legacyItems,
    tailSignature: tailItem == null
        ? 'empty'
        : [
            legacyItems.length,
            tailItem.raw['bubbleKey']?.toString().trim().isNotEmpty == true
                ? tailItem.raw['bubbleKey']
                : tailItem.id,
            tailItem.status,
            tailItem.body.length,
            tailItem.title.length,
            tailItem.createdAt?.millisecondsSinceEpoch ?? 0,
          ].join(':'),
    tailBodyLength: tailItem?.body.length ?? 0,
  );
}

List<ThreadMessageListEntry> _buildThreadMessageEntries(
  List<CodexThreadItem> items,
) {
  if (items.isEmpty) {
    return const [];
  }

  final entries = <ThreadMessageListEntry>[];
  final turnBuffer = <CodexThreadItem>[];
  String? activeTurnId;

  void flushTurnBuffer() {
    if (turnBuffer.isEmpty) {
      return;
    }
    entries.addAll(_buildTurnEntries(turnBuffer));
    turnBuffer.clear();
    activeTurnId = null;
  }

  for (final item in items) {
    final turnId = _turnId(item);
    if (turnId == null) {
      flushTurnBuffer();
      entries.add(_entryFromStandaloneItem(item));
      continue;
    }

    if (activeTurnId != null && turnId != activeTurnId) {
      flushTurnBuffer();
    }
    activeTurnId = turnId;
    turnBuffer.add(item);
  }

  flushTurnBuffer();
  return entries;
}

List<ThreadMessageListEntry> _buildTurnEntries(
  List<CodexThreadItem> turnItems,
) {
  final dedupedItems = _dedupeTurnItems(turnItems);
  if (dedupedItems.isEmpty) {
    return const [];
  }

  final entries = <ThreadMessageListEntry>[];
  final assistantItems = <CodexThreadItem>[];
  final turnKey = _turnId(dedupedItems.first) ?? dedupedItems.first.id;
  var assistantSegmentIndex = 0;

  void flushAssistantItems() {
    if (assistantItems.isEmpty) {
      return;
    }
    final entry = _buildAssistantEntry(
      assistantItems,
      segmentKey: 'assistant-bubble:$turnKey:$assistantSegmentIndex',
    );
    if (entry != null) {
      entries.add(entry);
      assistantSegmentIndex += 1;
    }
    assistantItems.clear();
  }

  for (final item in dedupedItems) {
    if (_isContextCompactionItem(item)) {
      flushAssistantItems();
      entries.add(_entryFromStandaloneItem(item));
      continue;
    }

    if (item.type == 'user.message') {
      flushAssistantItems();
      entries.add(
        ThreadMessageListEntry.bubble(
          key: item.id,
          items: [item],
          actor: item.actor,
          status: item.status,
        ),
      );
      continue;
    }

    assistantItems.add(item);
  }

  flushAssistantItems();
  return entries;
}

ThreadMessageListEntry? _buildAssistantEntry(
  List<CodexThreadItem> items, {
  required String segmentKey,
}) {
  if (items.isEmpty) {
    return null;
  }

  final agentMessages = items.where(_isAgentMessage).toList(growable: false);
  final finalAnswer = _latestMeaningfulFinalAnswer(agentMessages);
  final visibleItems = finalAnswer == null
      ? _visibleAssistantItems(items, agentMessages)
      : [finalAnswer];
  if (visibleItems.isEmpty) {
    return null;
  }

  if (visibleItems.length == 1) {
    final single = visibleItems.single;
    if (_isStandaloneEntryType(single)) {
      return _entryFromStandaloneItem(single, keyOverride: segmentKey);
    }
  }

  return ThreadMessageListEntry.bubble(
    key: segmentKey,
    items: visibleItems,
    sourceItems: items,
    actor: _bubbleActor(visibleItems),
    status: visibleItems.last.status,
  );
}

ThreadMessageListEntry _entryFromStandaloneItem(
  CodexThreadItem item, {
  String? keyOverride,
}) {
  final key = keyOverride ?? item.id;
  if (_isContextCompactionItem(item)) {
    return ThreadMessageListEntry.item(
      key: key,
      kind: ThreadMessageEntryKind.contextCompaction,
      item: item,
    );
  }
  if (item.type == 'command.execution') {
    return ThreadMessageListEntry.item(
      key: key,
      kind: ThreadMessageEntryKind.commandExecution,
      item: item,
    );
  }
  if (item.type == 'file.change') {
    return ThreadMessageListEntry.item(
      key: key,
      kind: ThreadMessageEntryKind.fileChange,
      item: item,
    );
  }
  return ThreadMessageListEntry.bubble(
    key: key,
    items: [item],
    sourceItems: [item],
    actor: item.actor,
    status: item.status,
  );
}

CodexThreadItem _legacyItemFromEntry(ThreadMessageListEntry entry) {
  switch (entry.kind) {
    case ThreadMessageEntryKind.commandExecution:
    case ThreadMessageEntryKind.fileChange:
    case ThreadMessageEntryKind.contextCompaction:
      return _withBubbleKey(entry.item!, entry.key);
    case ThreadMessageEntryKind.bubble:
      if (entry.items.length == 1) {
        return _withBubbleKey(entry.items.single, entry.key);
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
        createdAt: _latestCreatedAt(entry.items),
        raw: {
          ...latestItem.raw,
          'turnId': _turnId(entry.items.first),
          'bubbleKey': entry.key,
          'bubbleItems': entry.items,
          'phase': _itemPhase(latestItem),
        },
      );
  }
}

List<CodexThreadItem> _visibleAssistantItems(
  List<CodexThreadItem> items,
  List<CodexThreadItem> agentMessages,
) {
  final visibleItems = items
      .where((item) => !_isAgentMessage(item) || _hasMeaningfulBody(item))
      .toList(growable: false);
  if (visibleItems.isNotEmpty) {
    return visibleItems;
  }
  return _visibleAgentMessages(agentMessages);
}

CodexThreadItem? _latestMeaningfulFinalAnswer(List<CodexThreadItem> items) {
  for (final item in items.reversed) {
    if (_itemPhase(item) == 'final_answer' && _hasMeaningfulBody(item)) {
      return item;
    }
  }
  return null;
}

List<CodexThreadItem> _visibleAgentMessages(List<CodexThreadItem> items) {
  if (items.isEmpty) {
    return const [];
  }

  for (final item in items.reversed) {
    if (_itemPhase(item) == 'final_answer' && _hasMeaningfulBody(item)) {
      return [item];
    }
  }
  for (final item in items.reversed) {
    if (_itemPhase(item) == 'streaming' && _hasMeaningfulBody(item)) {
      return [item];
    }
  }
  for (final item in items.reversed) {
    if (_hasMeaningfulBody(item)) {
      return [item];
    }
  }
  for (final item in items.reversed) {
    if (_itemPhase(item) == 'final_answer') {
      return [item];
    }
  }
  for (final item in items.reversed) {
    if (_itemPhase(item) == 'streaming') {
      return [item];
    }
  }

  return [items.last];
}

List<CodexThreadItem> _dedupeTurnItems(List<CodexThreadItem> items) {
  final deduped = <CodexThreadItem>[];
  final seenUserMessages = <String>{};
  final seenAssistantMessages = <String>{};

  for (final item in items) {
    if (item.type == 'user.message') {
      final dedupKey = '${_turnId(item) ?? item.id}:${item.body.trim()}';
      if (seenUserMessages.add(dedupKey)) {
        deduped.add(item);
      }
      continue;
    }

    if (item.type == 'agent.message') {
      final dedupKey =
          '${_turnId(item) ?? item.id}:${_itemPhase(item) ?? ''}:${item.body.trim()}';
      if (seenAssistantMessages.add(dedupKey)) {
        deduped.add(item);
      }
      continue;
    }

    deduped.add(item);
  }

  return deduped;
}

String _bubbleActor(List<CodexThreadItem> items) {
  if (items.isEmpty) {
    return 'assistant';
  }
  if (items.every(
    (item) => item.actor == 'user' || item.type == 'user.message',
  )) {
    return 'user';
  }
  if (items.any(
    (item) =>
        item.actor == 'assistant' ||
        item.type == 'agent.message' ||
        item.type == 'plan' ||
        item.type == 'reasoning',
  )) {
    return 'assistant';
  }
  return items.last.actor;
}

CodexThreadItem _withBubbleKey(CodexThreadItem item, String bubbleKey) {
  final current = item.raw['bubbleKey']?.toString().trim() ?? '';
  if (current == bubbleKey) {
    return item;
  }
  return item.copyWith(raw: {...item.raw, 'bubbleKey': bubbleKey});
}

DateTime? _latestCreatedAt(List<CodexThreadItem> items) {
  DateTime? latest;
  for (final item in items) {
    final createdAt = item.createdAt;
    if (createdAt == null) {
      continue;
    }
    if (latest == null || createdAt.isAfter(latest)) {
      latest = createdAt;
    }
  }
  return latest;
}

bool _isAgentMessage(CodexThreadItem item) => item.type == 'agent.message';

bool _isStandaloneEntryType(CodexThreadItem item) {
  return item.type == 'command.execution' ||
      item.type == 'file.change' ||
      _isContextCompactionItem(item);
}

bool _isContextCompactionItem(CodexThreadItem item) {
  final type = item.type.trim();
  if (type == 'context.compaction' || type == 'contextCompaction') {
    return true;
  }
  return item.raw['type']?.toString().trim() == 'contextCompaction';
}

String? _turnId(CodexThreadItem item) {
  final value = item.raw['turnId']?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

String? _itemPhase(CodexThreadItem item) {
  final value = item.raw['phase']?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

bool _hasMeaningfulBody(CodexThreadItem item) {
  return item.body.trim().isNotEmpty;
}
