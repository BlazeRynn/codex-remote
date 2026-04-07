import '../utils/json_utils.dart';

enum UserMessagePartType { text, image, localImage, skill, mention, other }

class UserMessagePart {
  const UserMessagePart({
    required this.type,
    required this.text,
    this.url,
    this.path,
    this.name,
  });

  final UserMessagePartType type;
  final String text;
  final String? url;
  final String? path;
  final String? name;

  bool get hasVisualMedia =>
      type == UserMessagePartType.image ||
      type == UserMessagePartType.localImage;
}

List<UserMessagePart> parseUserMessageParts(Object? value) {
  final content = asJsonList(value).map(asJsonMap).toList(growable: false);
  if (content.isEmpty) {
    return const [];
  }

  return content
      .map(_parseUserInputPart)
      .whereType<UserMessagePart>()
      .toList(growable: false);
}

String renderUserMessageContent(Object? value) {
  final parts = parseUserMessageParts(value);
  if (parts.isEmpty) {
    return '';
  }

  return parts
      .map((part) => part.text)
      .where((part) => part.trim().isNotEmpty)
      .join('\n');
}

UserMessagePart? _parseUserInputPart(Map<String, dynamic> item) {
  switch (readString(item, const ['type'])) {
    case 'text':
      final text = readString(item, const ['text']);
      return text.isEmpty
          ? null
          : UserMessagePart(type: UserMessagePartType.text, text: text);
    case 'image':
      final url = readString(item, const ['url']);
      return UserMessagePart(
        type: UserMessagePartType.image,
        text: url.startsWith('data:')
            ? '[image]'
            : (url.isEmpty ? '[image]' : '[image] $url'),
        url: url.isEmpty ? null : url,
      );
    case 'localImage':
      final path = readString(item, const ['path']);
      return UserMessagePart(
        type: UserMessagePartType.localImage,
        text: path.isEmpty ? '[local image]' : '[local image] $path',
        path: path.isEmpty ? null : path,
      );
    case 'skill':
      final name = readString(item, const ['name']);
      return UserMessagePart(
        type: UserMessagePartType.skill,
        text: '[skill] $name',
        name: name.isEmpty ? null : name,
      );
    case 'mention':
      final name = readString(item, const ['name']);
      final path = readString(item, const ['path']);
      return UserMessagePart(
        type: UserMessagePartType.mention,
        text: _renderMentionText(name: name, path: path),
        name: name.isEmpty ? null : name,
        path: path.isEmpty ? null : path,
      );
    default:
      final text = readString(item, const ['text', 'message', 'content']);
      return text.isEmpty
          ? null
          : UserMessagePart(type: UserMessagePartType.other, text: text);
  }
}

String _renderMentionText({required String name, required String path}) {
  final trimmedPath = path.trim();
  final label = name.trim().isNotEmpty ? name.trim() : _basename(trimmedPath);
  if (trimmedPath.isNotEmpty && !_looksLikeStructuredMention(trimmedPath)) {
    return label.isEmpty ? '[file]' : '[file] $label';
  }
  return label.isEmpty ? '[mention]' : '[mention] $label';
}

bool _looksLikeStructuredMention(String value) {
  return value.contains('://');
}

String _basename(String value) {
  if (value.isEmpty) {
    return '';
  }
  final segments = value
      .split(RegExp(r'[\\/]'))
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  return segments.isEmpty ? value : segments.last;
}
