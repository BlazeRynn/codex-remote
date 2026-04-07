import '../utils/json_utils.dart';

enum CodexInputPartType { text, localImage, mention }

class CodexInputPart {
  const CodexInputPart._({required this.type, this.text, this.path, this.name});

  const CodexInputPart.text(String text)
    : this._(type: CodexInputPartType.text, text: text);

  const CodexInputPart.localImage({required String path, String? name})
    : this._(type: CodexInputPartType.localImage, path: path, name: name);

  const CodexInputPart.mention({required String path, String? name})
    : this._(type: CodexInputPartType.mention, path: path, name: name);

  final CodexInputPartType type;
  final String? text;
  final String? path;
  final String? name;

  bool get isAttachment => type != CodexInputPartType.text;

  String get displayLabel {
    switch (type) {
      case CodexInputPartType.text:
        return text?.trim() ?? '';
      case CodexInputPartType.localImage:
      case CodexInputPartType.mention:
        final explicitName = name?.trim() ?? '';
        if (explicitName.isNotEmpty) {
          return explicitName;
        }
        return _basename(path);
    }
  }

  String get previewText {
    switch (type) {
      case CodexInputPartType.text:
        return text?.trim() ?? '';
      case CodexInputPartType.localImage:
        return '[image]';
      case CodexInputPartType.mention:
        final label = displayLabel;
        return label.isEmpty ? '[file]' : '[file] $label';
    }
  }

  Map<String, dynamic> toJson() {
    switch (type) {
      case CodexInputPartType.text:
        return {
          'type': 'text',
          'text': text?.trim() ?? '',
          'text_elements': const <Object>[],
        };
      case CodexInputPartType.localImage:
        return {'type': 'localImage', 'path': path?.trim() ?? ''};
      case CodexInputPartType.mention:
        return {
          'type': 'mention',
          'name': displayLabel,
          'path': path?.trim() ?? '',
        };
    }
  }

  static CodexInputPart? fromPlatformMap(Map<String, dynamic> value) {
    final type = readString(value, const ['type']);
    switch (type) {
      case 'localImage':
        final path = readString(value, const ['path']);
        return path.isEmpty
            ? null
            : CodexInputPart.localImage(
                path: path,
                name: _optionalString(value['name']),
              );
      case 'mention':
        final path = readString(value, const ['path']);
        return path.isEmpty
            ? null
            : CodexInputPart.mention(
                path: path,
                name: _optionalString(value['name']),
              );
      default:
        return null;
    }
  }
}

List<Map<String, dynamic>> codexInputPartsToJson(
  Iterable<CodexInputPart> parts,
) {
  return parts
      .map((part) => part.toJson())
      .where((part) {
        if (part['type'] == 'text') {
          return readString(part, const ['text']).trim().isNotEmpty;
        }
        return readString(part, const ['path']).trim().isNotEmpty;
      })
      .toList(growable: false);
}

String renderCodexInputPreview(Iterable<CodexInputPart> parts) {
  return parts
      .map((part) => part.previewText)
      .where((value) => value.trim().isNotEmpty)
      .join('\n');
}

String _basename(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return '';
  }
  final pieces = normalized
      .split(RegExp(r'[\\/]'))
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  if (pieces.isEmpty) {
    return normalized;
  }
  return pieces.last;
}

String? _optionalString(Object? value) {
  final normalized = value?.toString().trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}
