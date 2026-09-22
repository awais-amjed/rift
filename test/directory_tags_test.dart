import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/directory_tags.dart';

/// `DirectoryTags` mirrors a CHECK constraint that both directory tables in
/// central carry (`public_servers.tags` and `public_bots.tags`, migration
/// 001). These pin the mirror to the constraint: if the column ever widens,
/// one of these fails and says so, rather than the client refusing a tag the
/// database would have taken.
void main() {
  group('DirectoryTags', () {
    test('accepts what the column accepts', () {
      expect(DirectoryTags.isValid('gaming'), isTrue);
      expect(DirectoryTags.isValid('board-games'), isTrue);
      expect(DirectoryTags.isValid('a1'), isTrue);
    });

    test('refuses what the column refuses', () {
      expect(
        DirectoryTags.isValid('a'),
        isFalse,
        reason: 'under two characters',
      );
      expect(DirectoryTags.isValid('x' * 21), isFalse, reason: 'over twenty');
      expect(DirectoryTags.isValid('Gaming'), isFalse, reason: 'uppercase');
      expect(DirectoryTags.isValid('board games'), isFalse, reason: 'a space');
      expect(DirectoryTags.isValid('under_score'), isFalse);
    });

    test('normalises free text into one tag rather than dropping the gap', () {
      expect(DirectoryTags.normalise('  Board Games '), 'board-games');
      expect(DirectoryTags.normalise('Sci-Fi!'), 'sci-fi');
      expect(DirectoryTags.normalise('two__words'), 'two-words');
    });

    test('normalising returns null when nothing usable survives', () {
      expect(DirectoryTags.normalise('!!'), isNull);
      expect(DirectoryTags.normalise('a'), isNull);
      expect(DirectoryTags.normalise('   '), isNull);
    });
  });

  /// The editor turns typing into a chip on Enter, and a tag left in the box
  /// used to be invisible to the save — so filling the field and pressing Save
  /// published no tags at all. Saving reads through here instead.
  group('DirectoryTags.withPending', () {
    test('picks up a tag that was typed but never turned into a chip', () {
      expect(DirectoryTags.withPending(const ['gaming'], 'Board Games'), [
        'gaming',
        'board-games',
      ]);
    });

    test('an empty or unusable box changes nothing', () {
      expect(DirectoryTags.withPending(const ['gaming'], ''), ['gaming']);
      expect(DirectoryTags.withPending(const ['gaming'], '  '), ['gaming']);
      expect(DirectoryTags.withPending(const ['gaming'], '!!'), ['gaming']);
    });

    test('a duplicate is dropped rather than repeated', () {
      expect(DirectoryTags.withPending(const ['gaming'], 'Gaming'), ['gaming']);
    });

    test('it cannot push a listing past the column limit', () {
      final full = List.generate(DirectoryTags.maxCount, (i) => 'tag-$i');
      expect(DirectoryTags.withPending(full, 'one-more'), full);
    });

    test('no chips yet and one in the box still saves that one', () {
      expect(DirectoryTags.withPending(const [], 'tech'), ['tech']);
    });
  });

  /// The field's placeholder is `gaming, board-games`, so a comma has to mean
  /// two tags. It used to be stripped like any other stray character, which
  /// folded the example itself into the single tag `gaming-board-games`.
  group('DirectoryTags.normaliseAll', () {
    test('a comma separates rather than folding', () {
      expect(DirectoryTags.normaliseAll('gaming, board-games'), [
        'gaming',
        'board-games',
      ]);
      expect(DirectoryTags.normaliseAll('testing, Dev Stuff'), [
        'testing',
        'dev-stuff',
      ]);
    });

    test('unusable pieces drop out and the rest survive', () {
      expect(DirectoryTags.normaliseAll('music, !, ,  , art'), [
        'music',
        'art',
      ]);
    });

    test('no comma is still one tag', () {
      expect(DirectoryTags.normaliseAll('Board Games'), ['board-games']);
      expect(DirectoryTags.normaliseAll('  '), isEmpty);
    });

    test('a comma-separated list fills chips up to the limit and stops', () {
      expect(
        DirectoryTags.withPending(const [], 'a1, b2, c3, d4, e5, f6'),
        ['a1', 'b2', 'c3', 'd4', 'e5'],
      );
    });

    test('duplicates inside one box collapse', () {
      expect(DirectoryTags.withPending(const ['music'], 'Music, art, art'), [
        'music',
        'art',
      ]);
    });
  });
}
