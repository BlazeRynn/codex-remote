import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/file_change_cards.dart';

void main() {
  test(
    'normalizeFileChangeKind prefers modified when move and modify both appear',
    () {
      expect(normalizeFileChangeKind('moved_and_modified'), 'modified');
      expect(normalizeFileChangeKind('move-modified-write'), 'modified');
    },
  );

  test('normalizeFileChangeKind still recognizes plain renamed values', () {
    expect(normalizeFileChangeKind('renamed'), 'renamed');
    expect(normalizeFileChangeKind('moved'), 'renamed');
  });
}
