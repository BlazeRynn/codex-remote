import 'dart:io';

class UiDebugLogger {
  UiDebugLogger._();

  static final String? targetThreadId = _optionalEnvironmentValue(
    'CODEX_CONTROL_DEBUG_THREAD_ID',
  );
  static final String? _logPath = _optionalEnvironmentValue(
    'CODEX_CONTROL_DEBUG_UI_LOG',
  );

  static bool get enabled => targetThreadId != null || _logPath != null;

  static bool matchesThread(String? threadId) {
    if (!enabled) {
      return false;
    }
    if (targetThreadId == null) {
      return true;
    }
    return threadId == targetThreadId;
  }

  static void log(
    String scope,
    String message, {
    String? threadId,
    Map<String, Object?> fields = const {},
  }) {
    if (!enabled) {
      return;
    }
    if (threadId != null && !matchesThread(threadId)) {
      return;
    }

    final timestamp = DateTime.now().toUtc().toIso8601String();
    final buffer = StringBuffer()
      ..write('[DEBUG-TRACE] ')
      ..write(timestamp)
      ..write(' [')
      ..write(scope)
      ..write('] ')
      ..write(message);
    if (threadId != null && threadId.isNotEmpty) {
      buffer.write(' threadId=$threadId');
    }
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isEmpty) {
        continue;
      }
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(_compact(text));
    }

    final line = buffer.toString();
    final path = _logPath;
    if (path == null) {
      return;
    }
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  static String _compact(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 240) {
      return normalized;
    }
    return '${normalized.substring(0, 237)}...';
  }
}

String? _optionalEnvironmentValue(String key) {
  final value = Platform.environment[key]?.trim() ?? '';
  return value.isEmpty ? null : value;
}
