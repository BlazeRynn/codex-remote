import '../models/codex_thread_item.dart';
import 'thread_message_list_projection.dart';

List<CodexThreadItem> buildConversationTimelineItems(
  List<CodexThreadItem> items,
) {
  return projectThreadMessageList(items).legacyItems;
}
