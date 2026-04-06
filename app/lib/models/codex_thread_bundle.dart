import 'codex_thread_item.dart';
import 'codex_thread_summary.dart';

class CodexThreadBundle {
  const CodexThreadBundle({required this.thread, required this.items});

  final CodexThreadSummary thread;
  final List<CodexThreadItem> items;
}
