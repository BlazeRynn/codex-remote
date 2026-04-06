import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/services/command_execution_presentation.dart';

void main() {
  test('strips launcher paths and shows the actual command content', () {
    expect(
      commandExecutionDisplayLabel({
        'command': ['/usr/bin/node', 'npm', 'test'],
      }),
      'npm test',
    );
  });

  test('unwraps shell launcher command strings', () {
    expect(
      commandExecutionDisplayLabel({
        'commandLine': '/bin/bash -lc "npm run lint"',
      }),
      'npm run lint',
    );
  });
}
