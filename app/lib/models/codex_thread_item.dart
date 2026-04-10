import '../utils/json_utils.dart';

class CodexThreadItem {
  const CodexThreadItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.status,
    required this.actor,
    this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final String status;
  final String actor;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  CodexThreadItem copyWith({
    String? id,
    String? type,
    String? title,
    String? body,
    String? status,
    String? actor,
    DateTime? createdAt,
    Map<String, dynamic>? raw,
  }) {
    return CodexThreadItem(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      status: status ?? this.status,
      actor: actor ?? this.actor,
      createdAt: createdAt ?? this.createdAt,
      raw: raw ?? this.raw,
    );
  }

  factory CodexThreadItem.fromJson(Map<String, dynamic> json) {
    final type = readString(json, const ['type', 'kind'], fallback: 'item');

    return CodexThreadItem(
      id: readString(json, const [
        'id',
        'itemId',
      ], fallback: DateTime.now().microsecondsSinceEpoch.toString()),
      type: type,
      title: readString(json, const [
        'title',
        'label',
        'summary',
        'name',
      ], fallback: _titleFromType(type)),
      body: readString(json, const [
        'body',
        'text',
        'message',
        'content',
        'detail',
      ], fallback: ''),
      status: readString(json, const [
        'status',
        'state',
        'approvalStatus',
      ], fallback: 'unknown'),
      actor: readString(json, const [
        'actor',
        'role',
        'source',
      ], fallback: 'bridge'),
      createdAt: readDate(json, const ['createdAt', 'timestamp', 'occurredAt']),
      raw: json,
    );
  }

  Map<String, dynamic> toTransferMap() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'status': status,
      'actor': actor,
      'createdAt': createdAt?.toUtc().toIso8601String(),
      'raw': _encodeTransferValue(raw),
    };
  }

  factory CodexThreadItem.fromTransferMap(Map<String, dynamic> json) {
    return CodexThreadItem(
      id: readString(json, const ['id']),
      type: readString(json, const ['type'], fallback: 'item'),
      title: _readTransferString(json, 'title', fallback: 'Operation'),
      body: _readTransferString(json, 'body'),
      status: readString(json, const ['status'], fallback: 'unknown'),
      actor: readString(json, const ['actor'], fallback: 'bridge'),
      createdAt: readDate(json, const ['createdAt']),
      raw: _decodeTransferMap(asJsonMap(json['raw'])),
    );
  }

  static String _titleFromType(String type) {
    if (type.isEmpty) {
      return 'Operation';
    }

    final normalized = type.replaceAll(RegExp(r'[_-]'), ' ').trim();
    return normalized.isEmpty
        ? 'Operation'
        : '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }
}

String _readTransferString(
  Map<String, dynamic> json,
  String key, {
  String fallback = '',
}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  return value.toString();
}

const _threadItemTransferKey = '__codexThreadItemTransfer__';
const _dateTimeTransferKey = '__codexDateTimeTransfer__';

Object? _encodeTransferValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is DateTime) {
    return {_dateTimeTransferKey: value.toUtc().toIso8601String()};
  }
  if (value is CodexThreadItem) {
    return {_threadItemTransferKey: value.toTransferMap()};
  }
  if (value is List) {
    return value.map(_encodeTransferValue).toList(growable: false);
  }
  if (value is Map) {
    return value.map<String, dynamic>(
      (key, item) => MapEntry(key.toString(), _encodeTransferValue(item)),
    );
  }
  return value.toString();
}

Map<String, dynamic> _decodeTransferMap(Map<String, dynamic> value) {
  return value.map<String, dynamic>(
    (key, item) => MapEntry(key.toString(), _decodeTransferValue(item)),
  );
}

Object? _decodeTransferValue(Object? value) {
  if (value is List) {
    return value.map(_decodeTransferValue).toList(growable: false);
  }
  if (value is Map) {
    final map = asJsonMap(value);
    if (map.length == 1 && map.containsKey(_threadItemTransferKey)) {
      return CodexThreadItem.fromTransferMap(
        asJsonMap(map[_threadItemTransferKey]),
      );
    }
    if (map.length == 1 && map.containsKey(_dateTimeTransferKey)) {
      return readDate(map, const [_dateTimeTransferKey]);
    }
    return _decodeTransferMap(map);
  }
  return value;
}
