import '../utils/json_utils.dart';

String commandExecutionDisplayLabel(
  Map<String, dynamic> item, {
  String fallback = 'Command',
}) {
  final joined =
      joinCommandParts(item['command']) ??
      joinCommandParts(item['argv']) ??
      joinCommandParts(item['args']) ??
      joinCommandParts(item['arguments']) ??
      joinCommandParts(item['commandArgs']);
  if (joined != null) {
    return joined;
  }

  final direct =
      _readOptionalString(item, const ['commandLine']) ??
      _readOptionalString(item, const ['rawCommand']) ??
      _readOptionalString(item, const ['cmd']) ??
      _readOptionalString(item, const ['program']) ??
      _readOptionalString(item, const ['executable']) ??
      _readOptionalString(item, const ['path']) ??
      _readOptionalString(item, const ['command']);
  return direct == null ? fallback : _simplifyCommandString(direct);
}

String? joinCommandParts(Object? value) {
  if (value is String) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : _simplifyCommandString(normalized);
  }

  final parts = asJsonList(value)
      .map((entry) => entry.toString().trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return null;
  }
  return _simplifyCommandTokens(parts).join(' ');
}

String? _readOptionalString(Map<String, dynamic> item, List<String> keys) {
  final text = readString(item, keys).trim();
  return text.isEmpty ? null : text;
}

String _simplifyCommandString(String value) {
  final tokens = _tokenizeCommandString(value);
  if (tokens.isEmpty) {
    return value.trim();
  }
  return _simplifyCommandTokens(tokens).join(' ');
}

List<String> _simplifyCommandTokens(List<String> tokens) {
  final normalized = tokens
      .map(_trimWrappingQuotes)
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  if (normalized.isEmpty) {
    return const [];
  }

  var parts = normalized.map(_basenameIfPathLike).toList(growable: false);
  if (parts.isEmpty) {
    return const [];
  }

  final first = parts.first.toLowerCase();
  if (first == 'env') {
    var index = 1;
    while (index < parts.length &&
        parts[index].contains('=') &&
        !parts[index].startsWith('-')) {
      index += 1;
    }
    if (index < parts.length) {
      parts = parts.sublist(index);
    }
  }

  if (parts.length >= 3 &&
      _isShellLauncher(parts.first) &&
      _isShellCommandOption(parts[1])) {
    final inlineCommand = normalized.sublist(2).join(' ').trim();
    if (inlineCommand.isNotEmpty) {
      return [inlineCommand];
    }
  }

  if (parts.length >= 3 &&
      _isCmdLauncher(parts.first) &&
      _isCmdCommandOption(parts[1])) {
    final inlineCommand = normalized.sublist(2).join(' ').trim();
    if (inlineCommand.isNotEmpty) {
      return [inlineCommand];
    }
  }

  if (parts.length >= 3 &&
      _isModuleLauncher(parts.first) &&
      parts[1] == '-m' &&
      parts[2].trim().isNotEmpty) {
    return parts.sublist(2);
  }

  if (parts.length >= 2 &&
      _isWrapperLauncher(parts.first) &&
      !_looksLikeOption(parts[1])) {
    return parts.sublist(1);
  }

  return parts;
}

List<String> _tokenizeCommandString(String value) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  String? quote;

  void flush() {
    final text = buffer.toString().trim();
    buffer.clear();
    if (text.isNotEmpty) {
      tokens.add(text);
    }
  }

  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (quote == null && (char == '"' || char == '\'')) {
      quote = char;
      continue;
    }
    if (quote != null && char == quote) {
      quote = null;
      continue;
    }
    if (quote == null && RegExp(r'\s').hasMatch(char)) {
      flush();
      continue;
    }
    buffer.write(char);
  }
  flush();
  return tokens;
}

String _trimWrappingQuotes(String value) {
  final text = value.trim();
  if (text.length >= 2 &&
      ((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith('\'') && text.endsWith('\'')))) {
    return text.substring(1, text.length - 1).trim();
  }
  return text;
}

String _basenameIfPathLike(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return text;
  }

  final normalized = text.replaceAll('\\', '/');
  if (!normalized.contains('/')) {
    return text;
  }

  final lastSegment = normalized.split('/').last.trim();
  return lastSegment.isEmpty ? text : lastSegment;
}

bool _isShellLauncher(String token) {
  switch (token.toLowerCase()) {
    case 'bash':
    case 'sh':
    case 'zsh':
    case 'pwsh':
    case 'powershell':
    case 'powershell.exe':
      return true;
    default:
      return false;
  }
}

bool _isCmdLauncher(String token) {
  switch (token.toLowerCase()) {
    case 'cmd':
    case 'cmd.exe':
      return true;
    default:
      return false;
  }
}

bool _isModuleLauncher(String token) {
  switch (token.toLowerCase()) {
    case 'python':
    case 'python3':
    case 'python.exe':
    case 'python3.exe':
      return true;
    default:
      return false;
  }
}

bool _isWrapperLauncher(String token) {
  switch (token.toLowerCase()) {
    case 'node':
    case 'node.exe':
    case 'python':
    case 'python3':
    case 'python.exe':
    case 'python3.exe':
    case 'ruby':
    case 'ruby.exe':
    case 'perl':
    case 'perl.exe':
      return true;
    default:
      return false;
  }
}

bool _isShellCommandOption(String token) {
  final normalized = token.toLowerCase();
  return normalized == '-c' ||
      normalized == '-lc' ||
      normalized == '-command' ||
      normalized == '-commandwithargs';
}

bool _isCmdCommandOption(String token) {
  final normalized = token.toLowerCase();
  return normalized == '/c' || normalized == '/k';
}

bool _looksLikeOption(String token) {
  final normalized = token.trim();
  return normalized.startsWith('-') || normalized.startsWith('/');
}
