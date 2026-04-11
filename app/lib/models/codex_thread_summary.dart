import '../utils/json_utils.dart';

class CodexThreadSummary {
  const CodexThreadSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.preview,
    this.isLoaded = false,
    this.createdAt,
    this.cwd,
    this.updatedAt,
    this.itemCount,
    this.provider,
  });

  final String id;
  final String title;
  final String status;
  final String preview;
  final bool isLoaded;
  final DateTime? createdAt;
  final String? cwd;
  final DateTime? updatedAt;
  final int? itemCount;
  final String? provider;

  CodexThreadSummary copyWith({
    String? id,
    String? title,
    String? status,
    String? preview,
    bool? isLoaded,
    DateTime? createdAt,
    String? cwd,
    DateTime? updatedAt,
    int? itemCount,
    String? provider,
  }) {
    return CodexThreadSummary(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      preview: preview ?? this.preview,
      isLoaded: isLoaded ?? this.isLoaded,
      createdAt: createdAt ?? this.createdAt,
      cwd: cwd ?? this.cwd,
      updatedAt: updatedAt ?? this.updatedAt,
      itemCount: itemCount ?? this.itemCount,
      provider: provider ?? this.provider,
    );
  }

  factory CodexThreadSummary.fromJson(Map<String, dynamic> json) {
    return CodexThreadSummary(
      id: readString(json, const [
        'id',
        'threadId',
      ], fallback: 'unknown-thread'),
      title: readString(json, const [
        'title',
        'name',
        'threadTitle',
      ], fallback: 'Untitled session'),
      status: readString(json, const ['status', 'state'], fallback: 'unknown'),
      preview: readString(json, const [
        'preview',
        'snippet',
        'lastMessagePreview',
      ], fallback: 'No preview available yet.'),
      isLoaded: readBool(json, const ['isLoaded', 'loaded']) ?? false,
      createdAt: readDate(json, const ['createdAt']),
      cwd:
          readString(json, const [
            'cwd',
            'workspacePath',
            'path',
          ]).trim().isEmpty
          ? null
          : readString(json, const ['cwd', 'workspacePath', 'path']),
      updatedAt: readDate(json, const [
        'updatedAt',
        'lastActivityAt',
        'createdAt',
      ]),
      itemCount: readInt(json, const ['itemCount', 'itemsCount', 'count']),
      provider: _readOptionalProvider(json),
    );
  }

  static String? _readOptionalProvider(Map<String, dynamic> json) {
    final provider = readString(json, const [
      'provider',
      'modelProvider',
    ]).trim();
    return provider.isEmpty ? null : provider;
  }
}
