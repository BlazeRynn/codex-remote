import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

enum AppServerLogEntryKind {
  request,
  response,
  error,
  notification,
  connection,
}

enum AppServerLogDirection { outbound, inbound }

class AppServerLogEntry {
  const AppServerLogEntry({
    required this.id,
    required this.recordedAt,
    required this.kind,
    required this.direction,
    required this.previewText,
    required this.searchIndex,
    this.clientKey,
    this.rpcId,
    this.method,
    this.threadId,
    this.turnId,
    this.itemId,
    this.duration,
    this.payload,
  });

  final String id;
  final DateTime recordedAt;
  final AppServerLogEntryKind kind;
  final AppServerLogDirection direction;
  final String previewText;
  final String searchIndex;
  final String? clientKey;
  final String? rpcId;
  final String? method;
  final String? threadId;
  final String? turnId;
  final String? itemId;
  final Duration? duration;
  final Object? payload;

  bool matchesQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return searchIndex.contains(normalized);
  }

  String get formattedPayload => formatAppServerLogPayload(payload);
}

class AppServerLogStore extends ChangeNotifier {
  AppServerLogStore({this.maxEntries = 1500});

  static final AppServerLogStore instance = AppServerLogStore();

  final int maxEntries;
  final List<AppServerLogEntry> _entries = <AppServerLogEntry>[];
  int _sequence = 0;

  UnmodifiableListView<AppServerLogEntry> get entries =>
      UnmodifiableListView<AppServerLogEntry>(_entries);

  void record({
    required AppServerLogEntryKind kind,
    required AppServerLogDirection direction,
    String? clientKey,
    String? rpcId,
    String? method,
    String? threadId,
    String? turnId,
    String? itemId,
    Duration? duration,
    String? previewText,
    Object? payload,
  }) {
    final effectivePreview = _effectivePreview(
      previewText: previewText,
      kind: kind,
      method: method,
      payload: payload,
    );
    final entry = AppServerLogEntry(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      recordedAt: DateTime.now().toUtc(),
      kind: kind,
      direction: direction,
      clientKey: _normalize(clientKey),
      rpcId: _normalize(rpcId),
      method: _normalize(method),
      threadId: _normalize(threadId),
      turnId: _normalize(turnId),
      itemId: _normalize(itemId),
      duration: duration,
      previewText: effectivePreview,
      payload: payload,
      searchIndex: _buildSearchIndex(
        kind: kind,
        direction: direction,
        clientKey: clientKey,
        rpcId: rpcId,
        method: method,
        threadId: threadId,
        turnId: turnId,
        itemId: itemId,
        previewText: effectivePreview,
        payload: payload,
      ),
    );

    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) {
      return;
    }
    _entries.clear();
    notifyListeners();
  }
}

final AppServerLogStore appServerLogStore = AppServerLogStore.instance;

String formatAppServerLogPayload(Object? payload) {
  if (payload == null) {
    return '';
  }
  if (payload is String) {
    return payload;
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(payload);
  } catch (_) {
    return payload.toString();
  }
}

String _effectivePreview({
  required String? previewText,
  required AppServerLogEntryKind kind,
  required String? method,
  required Object? payload,
}) {
  final explicit = _normalize(previewText);
  if (explicit != null) {
    return explicit;
  }

  final payloadPreview = _normalize(_compactPayload(payload));
  if (payloadPreview != null) {
    return payloadPreview;
  }

  final normalizedMethod = _normalize(method);
  if (normalizedMethod != null) {
    return normalizedMethod;
  }

  return kind.name;
}

String _buildSearchIndex({
  required AppServerLogEntryKind kind,
  required AppServerLogDirection direction,
  required String? clientKey,
  required String? rpcId,
  required String? method,
  required String? threadId,
  required String? turnId,
  required String? itemId,
  required String previewText,
  required Object? payload,
}) {
  final parts = <String>[
    kind.name,
    direction.name,
    if (_normalize(clientKey) != null) clientKey!,
    if (_normalize(rpcId) != null) rpcId!,
    if (_normalize(method) != null) method!,
    if (_normalize(threadId) != null) threadId!,
    if (_normalize(turnId) != null) turnId!,
    if (_normalize(itemId) != null) itemId!,
    previewText,
    formatAppServerLogPayload(payload),
  ];
  final normalized = parts.join('\n').toLowerCase();
  if (normalized.length <= 12000) {
    return normalized;
  }
  return normalized.substring(0, 12000);
}

String _compactPayload(Object? payload) {
  final formatted = formatAppServerLogPayload(
    payload,
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (formatted.isEmpty) {
    return '';
  }
  if (formatted.length <= 220) {
    return formatted;
  }
  return '${formatted.substring(0, 217)}...';
}

String? _normalize(Object? value) {
  final normalized = value?.toString().trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}
