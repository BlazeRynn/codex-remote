import 'dart:convert';

import '../models/codex_thread_item.dart';
import '../utils/json_utils.dart';
import 'bridge_realtime_client.dart';
import 'command_execution_presentation.dart';
import 'realtime_event_helpers.dart';
import 'thread_message_content.dart';
import 'ui_debug_logger.dart';

class ThreadRealtimeAccumulator {
  ThreadRealtimeAccumulator({required this.threadId});

  final String threadId;

  List<CodexThreadItem> _snapshotItems = const [];
  final Map<String, CodexThreadItem> _overlayItems = {};
  final Map<String, int> _overlayOrdinals = {};
  final Map<String, int> _itemOrdinals = {};
  final Map<String, String> _implicitStreamingItemIds = {};
  int _nextOrdinal = 0;

  List<CodexThreadItem> get items {
    final snapshotIds = _snapshotItems.map((item) => item.id).toSet();
    final snapshotSemanticKeys = _snapshotItems
        .map(_semanticItemKeyFromItem)
        .whereType<String>()
        .toSet();
    final consumedOverlayIds = <String>{};
    final orderedItems = <_OrderedThreadItem>[];
    for (final item in _snapshotItems) {
      final semanticKey = _semanticItemKeyFromItem(item);
      final overlayKey = _overlayItems.containsKey(item.id)
          ? item.id
          : (semanticKey == null || !_overlayItems.containsKey(semanticKey)
                ? null
                : semanticKey);
      final overlay = overlayKey == null ? null : _overlayItems[overlayKey];
      if (overlayKey != null) {
        consumedOverlayIds.add(overlayKey);
      }
      final mergedItem = overlay ?? item;
      orderedItems.add(
        _OrderedThreadItem(
          item: mergedItem,
          ordinal: _stableOrdinalFor(item, overlayKey: overlayKey),
        ),
      );
    }
    for (final entry in _overlayItems.entries) {
      if (consumedOverlayIds.contains(entry.key) ||
          snapshotIds.contains(entry.key) ||
          snapshotSemanticKeys.contains(entry.key)) {
        continue;
      }
      orderedItems.add(
        _OrderedThreadItem(
          item: entry.value,
          ordinal: _stableOrdinalFor(entry.value, overlayKey: entry.key),
        ),
      );
    }
    orderedItems.sort((left, right) {
      final byOrdinal = left.ordinal.compareTo(right.ordinal);
      if (byOrdinal != 0) {
        return byOrdinal;
      }
      final leftCreatedAt =
          left.item.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final rightCreatedAt =
          right.item.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return leftCreatedAt.compareTo(rightCreatedAt);
    });
    return List.unmodifiable(
      orderedItems.map((entry) => entry.item).toList(growable: false),
    );
  }

  void replaceSnapshot(List<CodexThreadItem> items) {
    final mergedItems = items
        .map(_mergeSnapshotItemMetadata)
        .toList(growable: false);
    for (final item in mergedItems) {
      _stableOrdinalFor(item);
    }
    _snapshotItems = List.unmodifiable(mergedItems);
    _reconcileOverlay();
  }

  CodexThreadItem _mergeSnapshotItemMetadata(CodexThreadItem item) {
    final semanticKey = _semanticItemKeyFromItem(item);
    final overlay =
        _overlayItems[item.id] ??
        (semanticKey == null ? null : _overlayItems[semanticKey]);
    if (overlay == null) {
      return item;
    }

    if (item.createdAt != null) {
      return item.copyWith(raw: {...overlay.raw, ...item.raw});
    }

    return item.copyWith(
      createdAt: overlay.createdAt,
      raw: {...overlay.raw, ...item.raw},
    );
  }

  bool apply(BridgeRealtimeEvent event) {
    final eventThreadId = realtimeEventThreadId(event);
    if (eventThreadId != null && eventThreadId != threadId) {
      return false;
    }

    final method = realtimeEventMethod(event) ?? event.type;
    switch (method) {
      case 'item/started':
      case 'thread/realtime/itemAdded':
        return _applyItemPayload(event, completed: false);
      case 'item/completed':
        return _applyItemPayload(event, completed: true);
      case 'item/agentMessage/delta':
      case 'item/plan/delta':
      case 'item/commandExecution/outputDelta':
      case 'item/fileChange/outputDelta':
      case 'item/reasoning/summaryTextDelta':
      case 'item/reasoning/textDelta':
        return _applyDelta(event, text: realtimeEventDeltaText(event));
      case 'thread/realtime/transcriptUpdated':
        return _applyDelta(
          event,
          text:
              realtimeEventTranscriptText(event) ??
              realtimeEventDeltaText(event),
        );
      default:
        return false;
    }
  }

  bool _applyItemPayload(BridgeRealtimeEvent event, {required bool completed}) {
    final item = realtimeEventItem(event);
    if (item.isEmpty) {
      return false;
    }

    final turnId = realtimeEventTurnId(event);
    final normalizedType = _normalizeRealtimeItemType(
      realtimeEventItemType(event) ??
          readString(item, const [
            'type',
          ], fallback: _fallbackItemTypeFromEvent(event)),
    );
    _applyImplicitStreamingBoundary(
      turnId: turnId,
      incomingType: normalizedType,
      explicitId: realtimeEventItemId(event) ?? _nonEmpty(item['id']),
    );
    final itemId = _resolveOverlayItemId(
      event,
      item: item,
      turnId: turnId,
      normalizedType: normalizedType,
    );
    final nextItem = _buildRealtimeItem(
      event,
      itemId: itemId,
      turnId: turnId,
      item: item,
      bodyOverride: null,
      statusOverride: completed
          ? (_readItemStatus(item) ?? 'completed')
          : (_readItemStatus(item) ?? 'started'),
      keepExistingBody: completed,
    );
    return _setOverlayItem(nextItem);
  }

  bool _applyDelta(BridgeRealtimeEvent event, {required String? text}) {
    if (text == null || text.isEmpty) {
      return false;
    }

    final item = realtimeEventItem(event);
    final turnId = realtimeEventTurnId(event);
    final normalizedType = _normalizeRealtimeItemType(
      realtimeEventItemType(event) ??
          readString(item, const [
            'type',
          ], fallback: _fallbackItemTypeFromEvent(event)),
    );
    _applyImplicitStreamingBoundary(
      turnId: turnId,
      incomingType: normalizedType,
      explicitId: realtimeEventItemId(event) ?? _nonEmpty(item['id']),
    );
    final itemId = _resolveOverlayItemId(
      event,
      item: item,
      turnId: turnId,
      normalizedType: normalizedType,
    );
    final current = _overlayItems[itemId] ?? _snapshotItemById(itemId);
    final previousBody = current?.body ?? _readItemBody(item);
    final nextBody = _appendStreamingText(previousBody, text);
    UiDebugLogger.log(
      'RealtimeState',
      'delta.apply',
      threadId: threadId,
      fields: {
        'turnId': turnId,
        'itemId': itemId,
        'tailBodyLength.before': previousBody.length,
        'tailBodyLength.after': nextBody.length,
        'delta': text,
      },
    );
    final nextItem = _buildRealtimeItem(
      event,
      itemId: itemId,
      turnId: turnId,
      item: item,
      bodyOverride: nextBody,
      statusOverride: _readItemStatus(item) ?? 'streaming',
      keepExistingBody: false,
    );
    return _setOverlayItem(nextItem);
  }

  CodexThreadItem _buildRealtimeItem(
    BridgeRealtimeEvent event, {
    required String itemId,
    required String? turnId,
    required Map<String, dynamic> item,
    required String? bodyOverride,
    required String statusOverride,
    required bool keepExistingBody,
  }) {
    final existing = _overlayItems[itemId] ?? _snapshotItemById(itemId);
    final normalizedType = _normalizeRealtimeItemType(
      realtimeEventItemType(event) ??
          readString(item, const [
            'type',
          ], fallback: _fallbackItemTypeFromEvent(event)),
    );
    final phase =
        realtimeEventItemPhase(event) ??
        readString(
          item,
          const ['phase'],
          fallback:
              existing?.raw['phase']?.toString() ??
              _fallbackPhaseFromEvent(event) ??
              '',
        );
    final itemBody = _readItemBody(item);
    final body =
        bodyOverride ??
        (itemBody.trim().isNotEmpty
            ? itemBody
            : (keepExistingBody ? existing?.body ?? '' : ''));
    final raw = <String, dynamic>{
      ...?existing?.raw,
      if (turnId != null && turnId.isNotEmpty) 'turnId': turnId,
      if (phase.isNotEmpty) 'phase': phase,
      ...item,
    };

    return CodexThreadItem(
      id: itemId,
      type: normalizedType,
      title: _itemTitle(
        normalizedType,
        phase: phase.isEmpty ? null : phase,
        item: item,
      ),
      body: body,
      status: statusOverride,
      actor: _itemActor(normalizedType),
      createdAt: existing?.createdAt ?? realtimeEventOccurredAt(event),
      raw: raw,
    );
  }

  bool _setOverlayItem(CodexThreadItem next) {
    final current = _overlayItems[next.id];
    if (current != null &&
        current.type == next.type &&
        current.title == next.title &&
        current.body == next.body &&
        current.status == next.status &&
        current.actor == next.actor &&
        _sameTimestamp(current.createdAt, next.createdAt) &&
        _sameRaw(current.raw, next.raw)) {
      return false;
    }

    _overlayItems[next.id] = next;
    _overlayOrdinals.putIfAbsent(
      next.id,
      () => _stableOrdinalFor(next, overlayKey: next.id),
    );
    _reconcileOverlay();
    return true;
  }

  CodexThreadItem? _snapshotItemById(String itemId) {
    for (final item in _snapshotItems) {
      if (item.id == itemId) {
        return item;
      }
    }
    return null;
  }

  String _resolveOverlayItemId(
    BridgeRealtimeEvent event, {
    required Map<String, dynamic> item,
    required String? turnId,
    required String normalizedType,
  }) {
    final semanticKey = _semanticItemKey(normalizedType, turnId: turnId);
    if (semanticKey != null) {
      return semanticKey;
    }

    final explicitId = realtimeEventItemId(event) ?? _nonEmpty(item['id']);
    if (explicitId != null) {
      if (turnId != null && turnId.isNotEmpty) {
        _implicitStreamingItemIds.remove(
          _implicitStreamingKey(turnId, normalizedType),
        );
      }
      return explicitId;
    }

    if (turnId != null && turnId.isNotEmpty) {
      final implicitKey = _implicitStreamingKey(turnId, normalizedType);
      final existingId = _implicitStreamingItemIds[implicitKey];
      if (existingId != null) {
        return existingId;
      }
      final nextId = _nextImplicitStreamItemId(
        turnId: turnId,
        type: normalizedType,
      );
      _implicitStreamingItemIds[implicitKey] = nextId;
      return nextId;
    }

    return '$normalizedType:${event.receivedAt.microsecondsSinceEpoch}';
  }

  String _nextImplicitStreamItemId({
    required String turnId,
    required String type,
  }) {
    var segmentCount = 0;
    for (final item in items) {
      if (_readTurnId(item.raw) != turnId || item.type != type) {
        continue;
      }
      segmentCount += 1;
    }
    return 'implicit::$turnId::$type::${segmentCount + 1}';
  }

  void _applyImplicitStreamingBoundary({
    required String? turnId,
    required String incomingType,
    required String? explicitId,
  }) {
    if (turnId == null || turnId.isEmpty) {
      return;
    }

    if (!_segmentableImplicitType(incomingType)) {
      _clearSegmentableImplicitItems(turnId);
      return;
    }

    if (explicitId != null && explicitId.isNotEmpty) {
      _implicitStreamingItemIds.remove(
        _implicitStreamingKey(turnId, incomingType),
      );
    }
  }

  void _clearSegmentableImplicitItems(String turnId) {
    for (final type in _segmentableImplicitTypes) {
      _implicitStreamingItemIds.remove(_implicitStreamingKey(turnId, type));
    }
  }

  void _reconcileOverlay() {
    if (_overlayItems.isEmpty) {
      return;
    }

    final snapshotById = <String, CodexThreadItem>{
      for (final item in _snapshotItems) item.id: item,
    };
    final snapshotBySemanticKey = <String, CodexThreadItem>{
      for (final item in _snapshotItems)
        if (_semanticItemKeyFromItem(item) != null)
          _semanticItemKeyFromItem(item)!: item,
    };
    final snapshotAgentMessagesByTurn = <String, List<CodexThreadItem>>{};
    for (final item in _snapshotItems) {
      final turnId = _readTurnId(item.raw);
      if (item.type != 'agent.message' || turnId == null) {
        continue;
      }
      snapshotAgentMessagesByTurn.putIfAbsent(turnId, () => []).add(item);
    }
    final completedAssistantTurns = <String>{
      for (final item in _snapshotItems)
        if (item.type == 'agent.message' &&
            _readPhase(item.raw) == 'final_answer' &&
            item.body.trim().isNotEmpty &&
            _readTurnId(item.raw) != null)
          _readTurnId(item.raw)!,
    };

    final removals = <String>[];
    for (final entry in _overlayItems.entries) {
      final overlayItem = entry.value;
      final snapshotItem = snapshotById[entry.key];
      if (snapshotItem != null &&
          _snapshotSupersedesOverlay(snapshotItem, overlayItem)) {
        removals.add(entry.key);
        continue;
      }

      final semanticKey = _semanticItemKeyFromItem(overlayItem);
      final semanticSnapshot = semanticKey == null
          ? null
          : snapshotBySemanticKey[semanticKey];
      if (semanticSnapshot != null &&
          _snapshotSupersedesOverlay(semanticSnapshot, overlayItem)) {
        removals.add(entry.key);
        continue;
      }

      final overlayTurnId = _readTurnId(overlayItem.raw);
      final sameTurnAgentSnapshots =
          overlayItem.type == 'agent.message' && overlayTurnId != null
          ? snapshotAgentMessagesByTurn[overlayTurnId] ?? const []
          : const <CodexThreadItem>[];
      if (sameTurnAgentSnapshots.any(
        (snapshotItem) => _snapshotSupersedesOverlay(snapshotItem, overlayItem),
      )) {
        removals.add(entry.key);
        continue;
      }

      if (overlayItem.type == 'agent.message' &&
          overlayTurnId != null &&
          completedAssistantTurns.contains(overlayTurnId)) {
        removals.add(entry.key);
      }
    }

    for (final itemId in removals) {
      _overlayItems.remove(itemId);
      _overlayOrdinals.remove(itemId);
      _implicitStreamingItemIds.removeWhere((_, value) => value == itemId);
    }
  }

  bool _snapshotSupersedesOverlay(
    CodexThreadItem snapshot,
    CodexThreadItem overlay,
  ) {
    final snapshotBody = snapshot.body.trim();
    final overlayBody = overlay.body.trim();
    if (snapshot.type == overlay.type &&
        snapshot.status == overlay.status &&
        snapshotBody == overlayBody) {
      return true;
    }
    if (snapshot.type == overlay.type &&
        snapshotBody.isNotEmpty &&
        (snapshotBody == overlayBody || snapshotBody.startsWith(overlayBody))) {
      return true;
    }
    if (snapshot.type == 'agent.message' &&
        _readPhase(snapshot.raw) == 'final_answer' &&
        snapshotBody.isNotEmpty) {
      return true;
    }
    return false;
  }

  int _stableOrdinalFor(CodexThreadItem item, {String? overlayKey}) {
    final semanticKey = _semanticItemKeyFromItem(item);
    final existing =
        (overlayKey == null ? null : _overlayOrdinals[overlayKey]) ??
        _itemOrdinals[item.id] ??
        (semanticKey == null ? null : _itemOrdinals[semanticKey]) ??
        _supersededOverlayOrdinal(item);
    final ordinal = existing ?? _nextOrdinal++;
    _itemOrdinals[item.id] = ordinal;
    if (semanticKey != null) {
      _itemOrdinals[semanticKey] = ordinal;
    }
    if (overlayKey != null) {
      _overlayOrdinals[overlayKey] = ordinal;
    }
    return ordinal;
  }

  int? _supersededOverlayOrdinal(CodexThreadItem snapshotItem) {
    final turnId = _readTurnId(snapshotItem.raw);
    if (turnId == null || snapshotItem.type != 'agent.message') {
      return null;
    }

    int? earliestOrdinal;
    for (final entry in _overlayItems.entries) {
      final overlayItem = entry.value;
      if (overlayItem.type != 'agent.message' ||
          _readTurnId(overlayItem.raw) != turnId ||
          !_snapshotSupersedesOverlay(snapshotItem, overlayItem)) {
        continue;
      }
      final ordinal = _overlayOrdinals[entry.key];
      if (ordinal == null) {
        continue;
      }
      if (earliestOrdinal == null || ordinal < earliestOrdinal) {
        earliestOrdinal = ordinal;
      }
    }
    return earliestOrdinal;
  }
}

class _OrderedThreadItem {
  const _OrderedThreadItem({required this.item, required this.ordinal});

  final CodexThreadItem item;
  final int ordinal;
}

String? _semanticItemKey(String type, {required String? turnId}) {
  if (type == 'context.compaction' && turnId != null && turnId.isNotEmpty) {
    return '$turnId::$type';
  }
  return null;
}

const Set<String> _segmentableImplicitTypes = {
  'agent.message',
  'plan',
  'reasoning',
};

bool _segmentableImplicitType(String type) {
  return _segmentableImplicitTypes.contains(type);
}

String _implicitStreamingKey(String turnId, String type) {
  return '$turnId::$type';
}

String? _semanticItemKeyFromItem(CodexThreadItem item) {
  return _semanticItemKey(item.type, turnId: _readTurnId(item.raw));
}

String _appendStreamingText(String existing, String incoming) {
  if (existing.isEmpty) {
    return incoming;
  }
  if (incoming.isEmpty || existing.endsWith(incoming)) {
    return existing;
  }
  if (incoming.startsWith(existing)) {
    return incoming;
  }

  final maxOverlap = existing.length < incoming.length
      ? existing.length
      : incoming.length;
  for (var overlap = maxOverlap; overlap > 1; overlap -= 1) {
    if (existing.substring(existing.length - overlap) ==
        incoming.substring(0, overlap)) {
      return existing + incoming.substring(overlap);
    }
  }
  return existing + incoming;
}

String _normalizeRealtimeItemType(String type) {
  switch (type) {
    case 'userMessage':
      return 'user.message';
    case 'agentMessage':
      return 'agent.message';
    case 'plan':
      return 'plan';
    case 'reasoning':
      return 'reasoning';
    case 'commandExecution':
      return 'command.execution';
    case 'fileChange':
      return 'file.change';
    case 'mcpToolCall':
      return 'mcp.tool.call';
    case 'dynamicToolCall':
      return 'tool.call';
    case 'collabAgentToolCall':
      return 'agent.tool.call';
    case 'webSearch':
      return 'web.search';
    case 'imageView':
      return 'image.view';
    case 'imageGeneration':
      return 'image.generation';
    case 'contextCompaction':
      return 'context.compaction';
    default:
      return type.replaceAll('/', '.');
  }
}

String _fallbackItemTypeFromEvent(BridgeRealtimeEvent event) {
  switch (realtimeEventMethod(event)) {
    case 'item/agentMessage/delta':
    case 'thread/realtime/transcriptUpdated':
      return 'agentMessage';
    case 'item/plan/delta':
      return 'plan';
    case 'item/commandExecution/outputDelta':
      return 'commandExecution';
    case 'item/fileChange/outputDelta':
      return 'fileChange';
    case 'item/reasoning/summaryTextDelta':
    case 'item/reasoning/textDelta':
      return 'reasoning';
    default:
      return 'item';
  }
}

String? _fallbackPhaseFromEvent(BridgeRealtimeEvent event) {
  switch (realtimeEventMethod(event)) {
    case 'item/agentMessage/delta':
    case 'thread/realtime/transcriptUpdated':
      return 'streaming';
    default:
      return null;
  }
}

String _itemTitle(
  String type, {
  required String? phase,
  required Map<String, dynamic> item,
}) {
  switch (type) {
    case 'user.message':
      return 'User message';
    case 'agent.message':
      return phase == null ? 'Assistant message' : 'Assistant message ($phase)';
    case 'plan':
      return 'Plan';
    case 'reasoning':
      return 'Reasoning';
    case 'command.execution':
      return commandExecutionDisplayLabel(item);
    case 'file.change':
      final count = asJsonList(item['changes']).length;
      return count > 0
          ? '$count file change${count == 1 ? '' : 's'}'
          : 'File change';
    case 'mcp.tool.call':
      final server = readString(item, const ['server'], fallback: 'mcp');
      final tool = readString(item, const ['tool'], fallback: 'tool');
      return '$server/$tool';
    case 'tool.call':
      return readString(item, const ['tool'], fallback: 'Tool');
    case 'agent.tool.call':
      return readString(item, const ['tool'], fallback: 'Agent tool');
    case 'web.search':
      return readString(item, const ['query'], fallback: 'Web search');
    case 'image.view':
      return 'Image view';
    case 'image.generation':
      return 'Image generation';
    case 'context.compaction':
      return 'Context compaction';
    default:
      return type;
  }
}

String _itemActor(String type) {
  switch (type) {
    case 'user.message':
      return 'user';
    case 'agent.message':
    case 'plan':
    case 'reasoning':
    case 'command.execution':
    case 'file.change':
    case 'mcp.tool.call':
    case 'tool.call':
    case 'agent.tool.call':
    case 'web.search':
    case 'image.view':
    case 'image.generation':
      return 'assistant';
    default:
      return 'assistant';
  }
}

String _readItemBody(Map<String, dynamic> item) {
  final rawType = readString(item, const ['type']);
  switch (rawType) {
    case 'userMessage':
      final contentBody = renderUserMessageContent(item['content']);
      if (contentBody.trim().isNotEmpty) {
        return contentBody;
      }
      return readString(item, const ['text', 'message'], fallback: '');
    case 'agentMessage':
    case 'plan':
      return readString(item, const ['text']);
    case 'commandExecution':
      final aggregated = readString(item, const ['aggregatedOutput']);
      if (aggregated.isNotEmpty) {
        return aggregated;
      }
      final cwd = readString(item, const ['cwd']);
      final exitCode = item['exitCode']?.toString() ?? 'n/a';
      return 'cwd: $cwd\nexitCode: $exitCode';
    case 'fileChange':
      return asJsonList(item['changes'])
          .map(asJsonMap)
          .take(8)
          .map(
            (change) =>
                '${readString(change, const ['kind'])} ${readString(change, const ['path'])}',
          )
          .join('\n');
    case 'reasoning':
      final summary = asJsonList(
        item['summary'],
      ).map((value) => value.toString());
      final content = asJsonList(
        item['content'],
      ).map((value) => value.toString());
      return [...summary, ...content].join('\n');
    case 'mcpToolCall':
      return _describeJson(
        item['error'] ?? item['result'] ?? item['arguments'],
      );
    case 'dynamicToolCall':
      return _describeJson(item['contentItems'] ?? item['arguments']);
    case 'collabAgentToolCall':
      final receiverIds = asJsonList(
        item['receiverThreadIds'],
      ).map((value) => value.toString()).toList(growable: false);
      final prompt = readString(item, const ['prompt']);
      return prompt.trim().isNotEmpty
          ? prompt
          : 'receiverThreadIds: ${receiverIds.join(', ')}';
    case 'webSearch':
      return _describeWebSearch(item);
    case 'imageView':
      return readString(item, const ['path']);
    case 'imageGeneration':
      return _optionalString(item['savedPath']) ??
          _optionalString(item['result']) ??
          _optionalString(item['revisedPrompt']) ??
          '';
    default:
      return readString(item, const [
        'text',
        'message',
        'content',
      ], fallback: '');
  }
}

String _describeWebSearch(Map<String, dynamic> item) {
  final action = asJsonMap(item['action']);
  if (action.isEmpty) {
    return readString(item, const ['query']);
  }

  switch (readString(action, const ['type'])) {
    case 'search':
      return readString(action, const [
        'query',
      ], fallback: readString(item, const ['query']));
    case 'openPage':
      return readString(action, const [
        'url',
      ], fallback: readString(item, const ['query']));
    default:
      return readString(item, const ['query']);
  }
}

String _describeJson(Object? value) {
  if (value == null) {
    return '';
  }

  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _readItemStatus(Map<String, dynamic> item) {
  final status = readString(item, const ['status']);
  return status.isEmpty ? null : status;
}

String? _readTurnId(Map<String, dynamic> raw) {
  final turnId = raw['turnId']?.toString().trim() ?? '';
  return turnId.isEmpty ? null : turnId;
}

String? _readPhase(Map<String, dynamic> raw) {
  final phase = raw['phase']?.toString().trim() ?? '';
  return phase.isEmpty ? null : phase;
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
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

bool _sameRaw(Map<String, dynamic> left, Map<String, dynamic> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!_deepEquals(entry.value, right[entry.key])) {
      return false;
    }
  }
  return true;
}

bool _deepEquals(Object? left, Object? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final key in left.keys) {
      if (!_deepEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_deepEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}
