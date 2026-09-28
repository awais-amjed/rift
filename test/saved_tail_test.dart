import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/saved_tail.dart';

Map<String, dynamic> row(int id, [String text = '']) => {
  'id': id,
  'ciphertext': text,
};

List<int> ids(SavedTail tail) => [for (final r in tail.rows) r['id'] as int];

void main() {
  group('SavedTail', () {
    test('holds rows newest first, whatever order they came in', () {
      final tail = SavedTail()..replace([row(1), row(3), row(2)]);
      expect(ids(tail), [3, 2, 1]);
    });

    test('keeps only the newest page', () {
      final tail = SavedTail()
        ..replace([for (var i = 1; i <= SavedTail.size + 5; i++) row(i)]);
      expect(tail.rows.length, SavedTail.size);
      expect(ids(tail).first, SavedTail.size + 5);
      expect(ids(tail).last, 6);
    });

    test('a newer row pushes the oldest out', () {
      final tail = SavedTail()
        ..replace([for (var i = 1; i <= SavedTail.size; i++) row(i)])
        ..merge([row(SavedTail.size + 1)]);
      expect(tail.rows.length, SavedTail.size);
      expect(ids(tail).first, SavedTail.size + 1);
      expect(ids(tail), isNot(contains(1)));
    });

    test('replace forgets what was held', () {
      final tail = SavedTail()
        ..replace([row(1), row(2)])
        ..replace([row(7)]);
      expect(ids(tail), [7]);
    });

    test('an update changes a held row and ignores one it does not hold', () {
      final tail = SavedTail()
        ..replace([row(1, 'old')])
        ..update(row(1, 'new'))
        ..update(row(99, 'far up the history'));
      expect(tail.rows.single['ciphertext'], 'new');
    });

    test('a deleted row is gone, so it cannot come back from the disk', () {
      final tail = SavedTail()
        ..replace([row(1), row(2)])
        ..remove('1');
      expect(ids(tail), [2]);
    });

    test('rows without a numeric id are not kept', () {
      final tail = SavedTail()
        ..replace([
          {'id': 'pending-1'},
          row(4),
        ]);
      expect(ids(tail), [4]);
    });

    test('reports a change once, and nothing when nothing changed', () {
      final tail = SavedTail()..replace([row(1)]);
      expect(tail.takeChanged(), isTrue);
      expect(tail.takeChanged(), isFalse);

      tail
        ..update(row(99))
        ..remove('42');
      expect(tail.takeChanged(), isFalse);

      tail.remove('1');
      expect(tail.takeChanged(), isTrue);
    });
  });
}
