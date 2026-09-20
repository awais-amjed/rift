import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/logic/services/quote_lookup.dart';

/// Finding the message a reply names when it is further back than the page
/// the reader has loaded.
void main() {
  ChatMessage msg(String id) => ChatMessage(
    id: id,
    authorId: 'ana',
    authorName: 'ana',
    text: 'x',
    sentAt: DateTime.utc(2026, 9, 20),
    isMine: false,
  );

  group('QuotedMessage', () {
    test('keeps "not found" and "not there" apart', () {
      // The whole reason the type exists. Telling a reader the second when
      // the first is true says somebody deleted something they did not.
      const unknown = QuotedMessage.unknown();
      const deleted = QuotedMessage.deleted();
      final found = QuotedMessage.found(msg('1'));

      expect(unknown.isFound, isFalse);
      expect(unknown.deleted, isFalse);
      expect(deleted.isFound, isFalse);
      expect(deleted.deleted, isTrue);
      expect(found.isFound, isTrue);
      expect(found.deleted, isFalse);
      expect(found.message!.id, '1');
    });
  });

  group('pageUntilLoaded', () {
    /// A list that reveals [pageSize] older messages per call, down to
    /// [total] of them.
    ({Future<bool> Function(String) find, int Function() pages}) paging({
      required int total,
      int pageSize = 5,
    }) {
      var loaded = pageSize;
      var pages = 0;
      Future<bool> find(String id) => QuoteLookup.pageUntilLoaded(
        isLoaded: () => int.parse(id) <= loaded,
        hasMore: () => loaded < total,
        loadedCount: () => loaded,
        loadMore: () async {
          pages++;
          loaded = (loaded + pageSize).clamp(0, total);
        },
      );
      return (find: find, pages: () => pages);
    }

    test('finds one already loaded without asking for a page', () async {
      final p = paging(total: 100);
      expect(await p.find('3'), isTrue);
      expect(p.pages(), 0);
    });

    test('pages until it has it, and no further', () async {
      final p = paging(total: 100);
      expect(await p.find('18'), isTrue);
      // 5 loaded, needs 20 → four pages. A fifth would be history nobody
      // asked for.
      expect(p.pages(), 3);
    });

    test('stops at the end of the history rather than the cap', () async {
      final p = paging(total: 20);
      expect(await p.find('999'), isFalse);
      expect(p.pages(), 3);
    });

    test('gives up at the cap on a history that never ends', () async {
      var loaded = 0;
      var pages = 0;
      final reached = await QuoteLookup.pageUntilLoaded(
        isLoaded: () => false,
        hasMore: () => true,
        loadedCount: () => loaded,
        loadMore: () async {
          pages++;
          loaded++;
        },
        maxPages: 4,
      );
      expect(reached, isFalse);
      expect(pages, 4);
    });

    test('a page that adds nothing is the end, whatever the flag says', () {
      // `loadMoreHistory` declines while one is already in flight. Trusting
      // `hasMore` alone spins the loop to its cap on every tap.
      var pages = 0;
      return expectLater(
        QuoteLookup.pageUntilLoaded(
          isLoaded: () => false,
          hasMore: () => true,
          loadedCount: () => 7,
          loadMore: () async => pages++,
        ),
        completion(isFalse),
      ).then((_) => expect(pages, 1));
    });

    test('the default cap is a real ceiling, not unbounded', () {
      expect(QuoteLookup.maxPages, greaterThan(1));
      expect(QuoteLookup.maxPages, lessThan(1000));
    });
  });
}
