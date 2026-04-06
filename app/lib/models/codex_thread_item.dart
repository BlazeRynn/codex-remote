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
