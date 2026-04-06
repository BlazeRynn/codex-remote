import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/utils/label_formatters.dart';

void main() {
  group('humanizeMachineLabel', () {
    test('humanizes dotted labels', () {
      expect(humanizeMachineLabel('agent.message'), 'Agent message');
    });

    test('humanizes camelCase labels', () {
      expect(humanizeMachineLabel('inProgress'), 'In Progress');
    });

    test('falls back for blank labels', () {
      expect(humanizeMachineLabel('   '), 'Unknown');
    });
  });
}
