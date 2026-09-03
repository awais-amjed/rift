import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/paging.dart';

void main() {
  group('Paging.split', () {
    List<int> rows(int count) => List.generate(count, (i) => i);

    test('the spare row is dropped and reported as more to come', () {
      final page = Paging.split(rows(4), limit: 3);
      expect(page.rows, [0, 1, 2]);
      expect(page.hasMore, isTrue);
    });

    test('a page exactly the limit long is the end — the old bug', () {
      // 50 messages used to promise a fifty-first, and the reader who scrolled
      // back got a spinner for a page that came back empty. The same shortcut
      // in the roster would leave a "load more" that never loads anything.
      final page = Paging.split(rows(3), limit: 3);
      expect(page.rows, [0, 1, 2]);
      expect(page.hasMore, isFalse);
    });

    test('a short page is passed through', () {
      final page = Paging.split(rows(2), limit: 3);
      expect(page.rows, [0, 1]);
      expect(page.hasMore, isFalse);
    });

    test('no rows at all', () {
      final page = Paging.split(<int>[], limit: 3);
      expect(page.rows, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('a limit of one still separates the page from the proof of more', () {
      expect(Paging.split(rows(2), limit: 1).rows, [0]);
      expect(Paging.split(rows(2), limit: 1).hasMore, isTrue);
      expect(Paging.split(rows(1), limit: 1).hasMore, isFalse);
    });
  });
}
