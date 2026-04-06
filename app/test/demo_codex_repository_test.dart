import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/bridge_config.dart';
import 'package:mobile/services/codex_repository.dart';

void main() {
  final demoConfig = BridgeConfig(
    baseUrl: '',
    authToken: '',
    mode: BridgeDataSourceMode.demo,
  );

  test('demo repository returns fixture threads', () async {
    final repository = createCodexRepository(demoConfig);

    final threads = await repository.listThreads();

    expect(threads, isNotEmpty);
    expect(threads.first.id, isNotEmpty);
    expect(threads.first.title, isNotEmpty);
  });

  test('demo repository returns bundle and emits live events', () async {
    final repository = createCodexRepository(demoConfig);
    final threads = await repository.listThreads();
    final bundle = await repository.getThreadBundle(threads.first.id);
    final session = repository.openThreadEvents(threadId: threads.first.id);

    expect(bundle.thread.id, threads.first.id);
    expect(bundle.items, isNotEmpty);

    final event = await session.stream.first;
    expect(event.raw['threadId'], threads.first.id);
    expect(event.type, isNotEmpty);
    expect(event.raw['occurredAt'], isA<String>());
    expect(DateTime.tryParse(event.raw['occurredAt']! as String), isNotNull);

    await session.close();
  });
}
