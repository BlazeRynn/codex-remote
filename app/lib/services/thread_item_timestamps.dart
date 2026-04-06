import '../models/codex_thread_item.dart';
import '../utils/json_utils.dart';

DateTime? extractAppServerItemTimestamp(
  Map<String, dynamic> item,
  Map<String, dynamic> turn,
) {
  return readDate(item, const [
        'occurredAt',
        'timestamp',
        'createdAt',
        'updatedAt',
      ]) ??
      readDate(turn, const [
        'occurredAt',
        'timestamp',
        'createdAt',
        'updatedAt',
      ]);
}

DateTime? resolveThreadItemDisplayTimestamp(CodexThreadItem item) {
  return item.createdAt ??
      readDate(item.raw, const [
        'occurredAt',
        'timestamp',
        'createdAt',
        'updatedAt',
        'turnOccurredAt',
        'turnTimestamp',
        'turnCreatedAt',
        'turnUpdatedAt',
      ]);
}
